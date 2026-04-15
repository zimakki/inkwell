# Diff View & View Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken live reload and add three view modes (Static/Live/Diff) with rendered block+word diff highlighting and per-block accept.

**Architecture:** Server stays dumb — watcher bug fix + mode flag passthrough only. All diff/mode logic lives client-side in `app.js`. The diff engine compares DOM blocks using LCS, with word-level drill-down for modified blocks. No external JS dependencies.

**Tech Stack:** Elixir/OTP (watcher fix, CLI, router), vanilla JavaScript (diff engine, mode UI, accept UX), CSS (diff highlighting styles)

---

### Task 1: Fix watcher symlink resolution

**Files:**
- Modify: `lib/inkwell/watcher.ex:11-13` (ensure_file)
- Modify: `lib/inkwell/watcher.ex:80-82` (handle_call watch_file)
- Modify: `lib/inkwell/watcher.ex:91-92` (handle_info)

- [ ] **Step 1: Add a `resolve_path/1` helper to `Inkwell.Watcher`**

Add this private function at the bottom of the module, before the final `end`:

```elixir
defp resolve_path(path) do
  expanded = Path.expand(path)

  case :file.read_link_all(String.to_charlist(expanded)) do
    {:ok, resolved} -> List.to_string(resolved)
    {:error, _} -> expanded
  end
end
```

This follows symlinks (e.g., `/tmp` → `/private/tmp` on macOS) using the Erlang `:file.read_link_all/1` function. Falls back to expanded path if no symlink exists.

- [ ] **Step 2: Use `resolve_path/1` in `ensure_file/1`**

Replace line 12:

```elixir
# Before:
path = Path.expand(path)

# After:
path = resolve_path(path)
```

Wait — `resolve_path/1` is private and `ensure_file/1` is a public function called from outside the GenServer process. It can't call a private function that we want to also use inside the GenServer callbacks. Instead, extract resolution into a module attribute or inline it. The simplest fix: make `resolve_path/1` a **public** function (`def` not `defp`).

Change `defp resolve_path` to `def resolve_path`. Then update `ensure_file/1`:

```elixir
def ensure_file(path) do
  path = resolve_path(path)
  dir = Path.dirname(path)

  case Registry.lookup(Inkwell.Registry, {:watcher, dir}) do
    [{pid, _}] ->
      GenServer.call(pid, {:watch_file, path})

    [] ->
      spec = {__MODULE__, dir: dir}
      {:ok, pid} = DynamicSupervisor.start_child(Inkwell.WatcherSupervisor, spec)
      GenServer.call(pid, {:watch_file, path})
  end
end
```

- [ ] **Step 3: Use `resolve_path/1` in `handle_info/2` for incoming event paths**

Replace line 92:

```elixir
# Before:
expanded = Path.expand(changed_path)

# After:
expanded = resolve_path(changed_path)
```

The full `handle_info` clause now reads:

```elixir
@impl true
def handle_info({:file_event, _pid, {changed_path, events}}, state) do
  expanded = resolve_path(changed_path)

  if MapSet.member?(state.files, expanded) and :modified in events do
    Logger.debug("File changed: #{expanded}")

    case File.read(expanded) do
      {:ok, content} ->
        {html, headings, alerts} = Inkwell.Renderer.render_with_nav(content)
        broadcast_nav(html, headings, alerts, expanded)

      {:error, reason} ->
        Logger.warning("Failed to read #{expanded}: #{inspect(reason)}")
    end
  end

  {:noreply, state}
end
```

- [ ] **Step 4: Compile and verify no warnings**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation, no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell/watcher.ex
git commit -m "fix: resolve symlinks in watcher path matching"
```

---

### Task 2: Fix watcher event filter

**Files:**
- Modify: `lib/inkwell/watcher.ex:94` (event filter guard)

- [ ] **Step 1: Broaden the event filter**

Replace the condition on line 94:

```elixir
# Before:
if MapSet.member?(state.files, expanded) and :modified in events do

# After:
if MapSet.member?(state.files, expanded) and
     Enum.any?(events, &(&1 in [:modified, :renamed, :created])) do
```

This catches atomic writes (`:renamed`), direct writes (`:modified`), and new file creation (`:created`).

- [ ] **Step 2: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 3: Commit**

```bash
git add lib/inkwell/watcher.ex
git commit -m "fix: broaden watcher event filter for atomic writes"
```

---

### Task 3: Add watcher tests for symlinks and renamed events

**Files:**
- Modify: `test/inkwell/watcher_test.exs`

- [ ] **Step 1: Write test for `:renamed` events triggering broadcast**

Add this test to `test/inkwell/watcher_test.exs`:

```elixir
test "handle_info with :renamed event triggers broadcast", %{test_file: test_file} do
  :ok = Inkwell.Watcher.ensure_file(test_file)
  expanded = Inkwell.Watcher.resolve_path(test_file)
  Registry.register(Inkwell.Registry, {:ws_clients, expanded}, [])

  # Simulate an atomic write (write-to-temp + rename) producing a :renamed event
  [{watcher_pid, _}] =
    Registry.lookup(Inkwell.Registry, {:watcher, Path.dirname(expanded)})

  send(watcher_pid, {:file_event, self(), {expanded, [:renamed]}})

  assert_receive {:reload, payload}, 1000
  assert %{"html" => _} = Jason.decode!(payload)
end
```

- [ ] **Step 2: Write test for `:created` events triggering broadcast**

```elixir
test "handle_info with :created event triggers broadcast", %{test_file: test_file} do
  :ok = Inkwell.Watcher.ensure_file(test_file)
  expanded = Inkwell.Watcher.resolve_path(test_file)
  Registry.register(Inkwell.Registry, {:ws_clients, expanded}, [])

  [{watcher_pid, _}] =
    Registry.lookup(Inkwell.Registry, {:watcher, Path.dirname(expanded)})

  send(watcher_pid, {:file_event, self(), {expanded, [:created, :modified]}})

  assert_receive {:reload, payload}, 1000
  assert %{"html" => _} = Jason.decode!(payload)
end
```

- [ ] **Step 3: Write test for symlink path resolution**

```elixir
test "resolve_path follows symlinks" do
  base = Path.join(System.tmp_dir!(), "inkwell-symlink-#{System.unique_integer([:positive])}")
  target = Path.join(base, "target")
  link = Path.join(base, "link")
  File.mkdir_p!(target)
  File.ln_s!(target, link)

  on_exit(fn -> File.rm_rf!(base) end)

  resolved = Inkwell.Watcher.resolve_path(link)
  assert resolved == Inkwell.Watcher.resolve_path(target)
  refute resolved == link
end
```

- [ ] **Step 4: Write test for untracked events being ignored**

```elixir
test "handle_info ignores events for untracked files", %{base: base} do
  tracked = Path.join(base, "tracked.md")
  untracked = Path.join(base, "untracked.md")
  File.write!(tracked, "# Tracked")
  File.write!(untracked, "# Untracked")

  :ok = Inkwell.Watcher.ensure_file(tracked)
  expanded_tracked = Inkwell.Watcher.resolve_path(tracked)
  expanded_untracked = Inkwell.Watcher.resolve_path(untracked)

  Registry.register(Inkwell.Registry, {:ws_clients, expanded_tracked}, [])

  [{watcher_pid, _}] =
    Registry.lookup(Inkwell.Registry, {:watcher, Path.dirname(expanded_tracked)})

  # Send event for untracked file — should NOT trigger broadcast
  send(watcher_pid, {:file_event, self(), {expanded_untracked, [:modified]}})

  refute_receive {:reload, _}, 200
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/inkwell/watcher_test.exs`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add test/inkwell/watcher_test.exs
git commit -m "test: add watcher tests for atomic writes and symlink resolution"
```

---

### Task 4: Add `--mode` CLI flag and pass through server

**Files:**
- Modify: `lib/inkwell/cli.ex:7-8` (option parser)
- Modify: `lib/inkwell/cli.ex:168-189` (preview function)
- Modify: `lib/inkwell/router.ex:83-99` (GET /open)
- Modify: `lib/inkwell/router.ex:473` (html_page body tag)

- [ ] **Step 1: Add `mode` to CLI option parser**

In `lib/inkwell/cli.ex`, update the `OptionParser.parse` call in `main/1` (line 7):

```elixir
# Before:
strict: [theme: :string, help: :boolean, version: :boolean, check: :boolean],

# After:
strict: [theme: :string, mode: :string, help: :boolean, version: :boolean, check: :boolean],
```

- [ ] **Step 2: Pass `mode` through `preview/3`**

The `preview/3` function already passes all `opts` through. The `mode` will be included in opts from the parser. Update the HTTP call in `preview/3` to include mode in the URL (line 182):

```elixir
# Before:
case http_get_json(
       "http://localhost:#{port}/open?path=#{URI.encode_www_form(file)}&theme=#{URI.encode_www_form(theme)}"
     ) do

# After:
mode = Keyword.get(opts, :mode, "diff")

case http_get_json(
       "http://localhost:#{port}/open?path=#{URI.encode_www_form(file)}&theme=#{URI.encode_www_form(theme)}&mode=#{URI.encode_www_form(mode)}"
     ) do
```

- [ ] **Step 3: Pass `mode` through `/open` route response**

In `lib/inkwell/router.ex`, update the `/open` route. The `open_file_payload/2` function returns a map. We need to include `mode` in it. Update the `GET /open` handler (line 83-99):

```elixir
get "/open" do
  conn = Plug.Conn.fetch_query_params(conn)
  path = conn.query_params["path"]
  theme = conn.query_params["theme"]
  mode = conn.query_params["mode"] || "diff"

  Logger.debug("Opening file: #{path}")

  case open_file_payload(path, theme) do
    {:ok, payload} ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(Map.put(payload, :mode, mode)))

    {:error, {status, message}} ->
      send_resp(conn, status, message)
  end
end
```

- [ ] **Step 4: Add `data-mode` to the HTML page body tag**

In `lib/inkwell/router.ex`, update the `GET "/"` route to read `mode` from query params and pass it to `html_page`. Update the route handler (around line 15-37):

```elixir
# In the conn.query_params["path"] branch, add mode extraction:
theme = :persistent_term.get(:inkwell_theme, "dark")
mode = conn.query_params["mode"] || "diff"
markdown = File.read!(file_path)
{html, headings, alerts} = Inkwell.Renderer.render_with_nav(markdown)
filename = Path.basename(file_path)
page = html_page(html, headings, alerts, filename, theme, file_path, mode)
```

Update the `html_page` function signature and body tag. Change the function head (line 442):

```elixir
# Before:
defp html_page(content, headings, alerts, filename, theme, current_path) do

# After:
defp html_page(content, headings, alerts, filename, theme, current_path, mode \\ "diff") do
```

Update the `<body>` tag in `html_page` (line 473):

```elixir
# Before:
<body data-current-path="#{safe_current_path}" data-rel-dir="#{safe_rel_dir}" data-nav="#{nav_data_json}">

# After:
<body data-current-path="#{safe_current_path}" data-rel-dir="#{safe_rel_dir}" data-nav="#{nav_data_json}" data-mode="#{Plug.HTML.html_escape(mode)}">
```

- [ ] **Step 5: Compile and verify**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add lib/inkwell/cli.ex lib/inkwell/router.ex
git commit -m "feat: add --mode CLI flag and pass through to page HTML"
```

---

### Task 5: Add diff CSS classes

**Files:**
- Modify: `priv/static/app.css` (append diff styles)

- [ ] **Step 1: Add all diff-related CSS at the end of `app.css`**

Append the following to `priv/static/app.css`:

```css
/* ── View mode toggle ── */
#mode-toggle {
  display: flex; align-items: center; gap: 2px;
  margin-right: 8px;
}
.mode-btn {
  padding: 3px 10px;
  border: none; border-radius: 4px;
  background: var(--bg-hover);
  color: var(--text-muted);
  font-size: 11px; font-weight: 500;
  cursor: pointer;
  transition: background 0.15s ease, color 0.15s ease;
}
.mode-btn:hover { background: var(--border); color: var(--text-secondary); }
.mode-btn--active {
  background: var(--accent, #cba6f7);
  color: var(--bg, #1e1e2e);
  font-weight: 600;
}
.mode-btn--active:hover {
  background: var(--accent, #cba6f7);
  color: var(--bg, #1e1e2e);
}

/* ── Diff block highlights ── */
.inkwell-diff-added {
  border-left: 3px solid #a6e3a1;
  background: rgba(166, 227, 161, 0.08);
  padding-left: 12px;
  border-radius: 0 6px 6px 0;
  position: relative;
}
.inkwell-diff-removed {
  border-left: 3px solid #f38ba8;
  background: rgba(243, 139, 168, 0.08);
  padding-left: 12px;
  border-radius: 0 6px 6px 0;
  text-decoration: line-through;
  opacity: 0.5;
  position: relative;
}
.inkwell-diff-modified {
  border-left: 3px solid #fab387;
  background: rgba(250, 179, 135, 0.08);
  padding-left: 12px;
  border-radius: 0 6px 6px 0;
  position: relative;
}

/* ── Diff word highlights ── */
.inkwell-diff-word-added {
  background: rgba(166, 227, 161, 0.25);
  color: #a6e3a1;
  padding: 1px 3px;
  border-radius: 3px;
}
.inkwell-diff-word-removed {
  background: rgba(243, 139, 168, 0.25);
  color: #f38ba8;
  text-decoration: line-through;
  padding: 1px 3px;
  border-radius: 3px;
}

/* ── Per-block accept button ── */
.inkwell-diff-accept-btn {
  position: absolute;
  top: 4px; right: 4px;
  width: 22px; height: 22px;
  border: none; border-radius: 4px;
  background: rgba(166, 227, 161, 0.15);
  color: #a6e3a1;
  cursor: pointer;
  display: flex; align-items: center; justify-content: center;
  font-size: 13px;
  opacity: 0;
  transition: opacity 0.15s ease;
}
.inkwell-diff-added:hover .inkwell-diff-accept-btn,
.inkwell-diff-removed:hover .inkwell-diff-accept-btn,
.inkwell-diff-modified:hover .inkwell-diff-accept-btn {
  opacity: 1;
}
.inkwell-diff-accept-btn:hover {
  background: rgba(166, 227, 161, 0.3);
}

/* ── Global accept FAB ── */
#diff-accept-fab {
  position: fixed;
  bottom: 20px; right: 20px;
  display: none;
  align-items: center;
  background: var(--bg-secondary, #181825);
  border: 1px solid var(--border, #313244);
  border-radius: 24px;
  padding: 4px;
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
  font-family: system-ui, sans-serif;
  font-size: 12px;
  z-index: 100;
}
#diff-accept-fab.visible { display: flex; }
#diff-accept-fab .diff-summary {
  display: flex; align-items: center; gap: 8px;
  padding: 4px 12px;
  color: var(--text-muted);
}
#diff-accept-fab .diff-summary .added { color: #a6e3a1; }
#diff-accept-fab .diff-summary .modified { color: #fab387; }
#diff-accept-fab .diff-summary .removed { color: #f38ba8; }
#diff-accept-fab .diff-separator {
  width: 1px; height: 20px;
  background: var(--border, #313244);
}
#diff-accept-fab .accept-all-btn {
  display: flex; align-items: center; gap: 6px;
  padding: 6px 14px;
  background: #a6e3a1;
  color: #1e1e2e;
  border: none; border-radius: 20px;
  font-weight: 600; font-size: 12px;
  cursor: pointer;
  margin-left: 4px;
}
#diff-accept-fab .accept-all-btn:hover {
  background: #b8f0c0;
}
#diff-accept-fab .accept-all-btn .shortcut {
  font-size: 10px; opacity: 0.6;
}

/* ── Diff block fade-out animation ── */
.inkwell-diff-fade-out {
  transition: opacity 0.2s ease, border-color 0.2s ease, background 0.2s ease;
  opacity: 1;
  border-left-color: transparent !important;
  background: transparent !important;
}

/* ── Light theme overrides ── */
[data-theme="light"] .inkwell-diff-added { background: rgba(64, 160, 43, 0.08); border-left-color: #40a02b; }
[data-theme="light"] .inkwell-diff-removed { background: rgba(210, 15, 57, 0.08); border-left-color: #d20f39; }
[data-theme="light"] .inkwell-diff-modified { background: rgba(254, 100, 11, 0.08); border-left-color: #fe640b; }
[data-theme="light"] .inkwell-diff-word-added { background: rgba(64, 160, 43, 0.2); color: #40a02b; }
[data-theme="light"] .inkwell-diff-word-removed { background: rgba(210, 15, 57, 0.2); color: #d20f39; }
[data-theme="light"] .inkwell-diff-accept-btn { background: rgba(64, 160, 43, 0.15); color: #40a02b; }
[data-theme="light"] #diff-accept-fab .diff-summary .added { color: #40a02b; }
[data-theme="light"] #diff-accept-fab .diff-summary .modified { color: #fe640b; }
[data-theme="light"] #diff-accept-fab .diff-summary .removed { color: #d20f39; }
[data-theme="light"] #diff-accept-fab .accept-all-btn { background: #40a02b; color: #fff; }
[data-theme="light"] #diff-accept-fab .accept-all-btn:hover { background: #4db836; }
```

- [ ] **Step 2: Commit**

```bash
git add priv/static/app.css
git commit -m "feat: add CSS for diff highlights, mode toggle, and accept UX"
```

---

### Task 6: Add mode toggle UI and state management in app.js

**Files:**
- Modify: `priv/static/app.js` (add mode state + toggle buttons + switchMode)

- [ ] **Step 1: Add mode state variables after existing variable declarations**

After line 38 (`var findDebounceTimer = null;`), add:

```javascript
// ── View mode state ──
var currentMode = (function() {
  var dataMode = document.body.dataset.mode;
  if (dataMode && (dataMode === 'diff' || dataMode === 'live' || dataMode === 'static')) {
    return dataMode;
  }
  var stored = localStorage.getItem('inkwell-mode');
  if (stored && (stored === 'diff' || stored === 'live' || stored === 'static')) {
    return stored;
  }
  return 'diff';
})();
var baselineBlocks = [];
var pendingHtml = null;
var pendingHeadings = null;
var pendingAlerts = null;
var diffDebounceTimer = null;
var isFirstWsMessage = true;
```

- [ ] **Step 2: Add the mode toggle buttons to the DOM**

After the `mermaid.initialize` call (line 40), add:

```javascript
// ── Build mode toggle ──
var modeToggle = document.createElement('div');
modeToggle.id = 'mode-toggle';
['static', 'live', 'diff'].forEach(function(mode) {
  var btn = document.createElement('button');
  btn.className = 'mode-btn' + (mode === currentMode ? ' mode-btn--active' : '');
  btn.textContent = mode.charAt(0).toUpperCase() + mode.slice(1);
  btn.dataset.mode = mode;
  btn.addEventListener('click', function() { switchMode(mode); });
  modeToggle.appendChild(btn);
});
var headerActions = document.getElementById('header-actions');
if (headerActions && currentPath) {
  headerActions.insertBefore(modeToggle, headerActions.firstChild);
}
```

- [ ] **Step 3: Add the global accept FAB to the DOM**

After the mode toggle code, add:

```javascript
// ── Build global accept FAB ──
var diffFab = document.createElement('div');
diffFab.id = 'diff-accept-fab';
diffFab.innerHTML = '<div class="diff-summary"></div><div class="diff-separator"></div><button class="accept-all-btn" onclick=""><span>\u2713 Accept</span> <span class="shortcut">\u2318\u23CE</span></button>';
document.body.appendChild(diffFab);
diffFab.querySelector('.accept-all-btn').addEventListener('click', function() {
  acceptAll();
});
```

- [ ] **Step 4: Add `switchMode` function**

Add before the `// ── WebSocket` section:

```javascript
// ── Mode switching ──
function switchMode(newMode) {
  var oldMode = currentMode;
  currentMode = newMode;
  localStorage.setItem('inkwell-mode', newMode);

  // Update toggle button styles
  var btns = modeToggle.querySelectorAll('.mode-btn');
  btns.forEach(function(btn) {
    if (btn.dataset.mode === newMode) {
      btn.classList.add('mode-btn--active');
    } else {
      btn.classList.remove('mode-btn--active');
    }
  });

  if (newMode === 'live') {
    // Clear diff highlights, show latest content
    clearDiffHighlights();
    if (pendingHtml !== null) {
      ctn.innerHTML = pendingHtml;
      renderMermaid();
      updateDocNav(pendingHeadings || [], pendingAlerts || []);
      reapplyFindHighlights();
      pendingHtml = null;
      pendingHeadings = null;
      pendingAlerts = null;
    }
    baselineBlocks = extractBlocks(ctn);
    updateFab();
  } else if (newMode === 'static') {
    // Freeze — do nothing, keep current DOM as-is
  } else if (newMode === 'diff') {
    baselineBlocks = extractBlocks(ctn);
    if (pendingHtml !== null && oldMode === 'static') {
      // There's a pending update from while we were in static mode
      applyDiff(pendingHtml, pendingHeadings, pendingAlerts);
      pendingHtml = null;
      pendingHeadings = null;
      pendingAlerts = null;
    }
    updateFab();
  }
}
```

- [ ] **Step 5: Add `extractBlocks` helper**

Add right after `switchMode`:

```javascript
function extractBlocks(container) {
  var blocks = [];
  var children = container.children;
  for (var i = 0; i < children.length; i++) {
    var el = children[i];
    blocks.push({
      tag: el.tagName.toLowerCase(),
      textContent: el.textContent.replace(/\s+/g, ' ').trim(),
      outerHTML: el.outerHTML
    });
  }
  return blocks;
}
```

- [ ] **Step 6: Add stubs for functions we'll implement in later tasks**

```javascript
function clearDiffHighlights() {
  // Remove all diff classes and injected removed blocks
  var highlighted = ctn.querySelectorAll('.inkwell-diff-added, .inkwell-diff-removed, .inkwell-diff-modified');
  highlighted.forEach(function(el) {
    if (el.classList.contains('inkwell-diff-removed')) {
      el.remove();
    } else {
      el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified');
      el.style.borderLeft = '';
      el.style.background = '';
      el.style.paddingLeft = '';
      // Remove accept buttons
      var btn = el.querySelector('.inkwell-diff-accept-btn');
      if (btn) btn.remove();
      // Remove word-level spans
      var wordSpans = el.querySelectorAll('.inkwell-diff-word-added, .inkwell-diff-word-removed');
      wordSpans.forEach(function(span) {
        if (span.classList.contains('inkwell-diff-word-removed')) {
          span.remove();
        } else {
          span.replaceWith(document.createTextNode(span.textContent));
        }
      });
    }
  });
}

function applyDiff(html, headings, alerts) {
  // Stub — implemented in Task 8
}

function updateFab() {
  // Stub — implemented in Task 9
}
```

- [ ] **Step 7: Compile check — verify the JS is syntactically valid**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 8: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: add mode toggle UI and state management"
```

---

### Task 7: Implement block-level diff engine

**Files:**
- Modify: `priv/static/app.js` (add `computeBlockDiff` and LCS)

- [ ] **Step 1: Add the LCS helper function**

Add after `extractBlocks`:

```javascript
// ── LCS (Longest Common Subsequence) ──
function lcs(a, b, eq) {
  var m = a.length, n = b.length;
  var dp = [];
  for (var i = 0; i <= m; i++) {
    dp[i] = [];
    for (var j = 0; j <= n; j++) {
      if (i === 0 || j === 0) {
        dp[i][j] = 0;
      } else if (eq(a[i - 1], b[j - 1])) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }
  // Backtrack to find the matched indices
  var result = [];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (eq(a[i - 1], b[j - 1])) {
      result.unshift({ ai: i - 1, bi: j - 1 });
      i--; j--;
    } else if (dp[i - 1][j] > dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return result;
}
```

- [ ] **Step 2: Add `computeBlockDiff`**

```javascript
function computeBlockDiff(oldBlocks, newBlocks) {
  // Find LCS based on normalized text content
  var matched = lcs(oldBlocks, newBlocks, function(a, b) {
    return a.tag === b.tag && a.textContent === b.textContent;
  });

  var result = [];
  var oi = 0, ni = 0, mi = 0;

  while (oi < oldBlocks.length || ni < newBlocks.length) {
    if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
      // Exact match
      result.push({ type: 'unchanged', oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
      oi++; ni++; mi++;
    } else if (mi < matched.length && oi < matched[mi].ai && ni < matched[mi].bi) {
      // Both sides have unmatched blocks before the next match — try to pair them as modifications
      var oldEnd = matched[mi].ai;
      var newEnd = matched[mi].bi;
      while (oi < oldEnd && ni < newEnd) {
        if (oldBlocks[oi].tag === newBlocks[ni].tag) {
          result.push({ type: 'modified', oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
        } else {
          result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
          result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
        }
        oi++; ni++;
      }
      // Remaining unmatched on one side
      while (oi < oldEnd) {
        result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
        oi++;
      }
      while (ni < newEnd) {
        result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
        ni++;
      }
    } else if (mi >= matched.length || oi < matched[mi].ai) {
      // Old block not in LCS — removed
      result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
      oi++;
    } else {
      // New block not in LCS — added
      result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
      ni++;
    }
  }

  return result;
}
```

- [ ] **Step 3: Verify syntax**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 4: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: implement block-level LCS diff engine"
```

---

### Task 8: Implement word-level diff engine

**Files:**
- Modify: `priv/static/app.js` (add `computeWordDiff`)

- [ ] **Step 1: Add `computeWordDiff` function**

Add after `computeBlockDiff`:

```javascript
function computeWordDiff(oldText, newText) {
  var oldWords = oldText.split(/(\s+)/);
  var newWords = newText.split(/(\s+)/);

  var matched = lcs(oldWords, newWords, function(a, b) { return a === b; });

  var spans = [];
  var oi = 0, ni = 0, mi = 0;

  while (oi < oldWords.length || ni < newWords.length) {
    if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
      // Same word
      spans.push({ type: 'same', text: newWords[ni] });
      oi++; ni++; mi++;
    } else {
      // Collect contiguous removed words
      var removedStart = oi;
      while (oi < oldWords.length && (mi >= matched.length || oi < matched[mi].ai)) {
        oi++;
      }
      if (oi > removedStart) {
        spans.push({ type: 'removed', text: oldWords.slice(removedStart, oi).join('') });
      }
      // Collect contiguous added words
      var addedStart = ni;
      while (ni < newWords.length && (mi >= matched.length || ni < matched[mi].bi)) {
        ni++;
      }
      if (ni > addedStart) {
        spans.push({ type: 'added', text: newWords.slice(addedStart, ni).join('') });
      }
    }
  }

  return spans;
}

function buildWordDiffHTML(oldText, newText) {
  var spans = computeWordDiff(oldText, newText);
  var html = '';
  spans.forEach(function(span) {
    var escaped = span.text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    if (span.type === 'same') {
      html += escaped;
    } else if (span.type === 'added') {
      html += '<span class="inkwell-diff-word-added">' + escaped + '</span>';
    } else if (span.type === 'removed') {
      html += '<span class="inkwell-diff-word-removed">' + escaped + '</span>';
    }
  });
  return html;
}
```

- [ ] **Step 2: Verify syntax**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: implement word-level diff engine"
```

---

### Task 9: Implement `handleContentUpdate` mode branching and `applyDiff`

**Files:**
- Modify: `priv/static/app.js` (rewrite `handleContentUpdate`, implement `applyDiff`)

- [ ] **Step 1: Extract HTML parsing into a helper**

Add before `handleContentUpdate`:

```javascript
function parseContentPayload(data) {
  if (typeof data === 'string') {
    try {
      var parsed = JSON.parse(data);
      if (parsed.html !== undefined) {
        return { html: parsed.html, headings: parsed.headings || [], alerts: parsed.alerts || [] };
      }
    } catch(e) {}
    return { html: data, headings: [], alerts: [] };
  }
  return { html: data.html, headings: data.headings || [], alerts: data.alerts || [] };
}
```

- [ ] **Step 2: Rewrite `handleContentUpdate` to branch on mode**

Replace the existing `handleContentUpdate` function (lines 423-448) with:

```javascript
function handleContentUpdate(data) {
  var payload = parseContentPayload(data);

  // First message after connect/reconnect — always set as baseline (handles file switching)
  if (isFirstWsMessage) {
    isFirstWsMessage = false;
    ctn.innerHTML = payload.html;
    renderMermaid();
    updateDocNav(payload.headings, payload.alerts);
    reapplyFindHighlights();
    baselineBlocks = extractBlocks(ctn);
    clearDiffHighlights();
    updateFab();
    return;
  }

  if (currentMode === 'static') {
    // Store but don't render
    pendingHtml = payload.html;
    pendingHeadings = payload.headings;
    pendingAlerts = payload.alerts;
    return;
  }

  if (currentMode === 'live') {
    ctn.innerHTML = payload.html;
    renderMermaid();
    updateDocNav(payload.headings, payload.alerts);
    reapplyFindHighlights();
    baselineBlocks = extractBlocks(ctn);
    return;
  }

  // Diff mode — debounce rapid saves
  pendingHtml = payload.html;
  pendingHeadings = payload.headings;
  pendingAlerts = payload.alerts;
  if (diffDebounceTimer) clearTimeout(diffDebounceTimer);
  diffDebounceTimer = setTimeout(function() {
    applyDiff(pendingHtml, pendingHeadings, pendingAlerts);
    pendingHtml = null;
    pendingHeadings = null;
    pendingAlerts = null;
    diffDebounceTimer = null;
  }, 300);
}
```

- [ ] **Step 3: Implement `applyDiff`**

Replace the `applyDiff` stub with the real implementation:

```javascript
function applyDiff(html, headings, alerts) {
  // Parse incoming HTML into blocks
  var tempDiv = document.createElement('div');
  tempDiv.innerHTML = html;
  var newBlocks = extractBlocks(tempDiv);

  // Compute diff
  var diff = computeBlockDiff(baselineBlocks, newBlocks);

  // Save scroll position before DOM rebuild
  var scrollEl = ctn.parentElement || document.documentElement;
  var scrollPos = scrollEl.scrollTop;

  // Build the new DOM
  ctn.innerHTML = '';
  diff.forEach(function(entry, idx) {
    var el;
    if (entry.type === 'unchanged') {
      el = createElementFromHTML(entry.newBlock.outerHTML);
      ctn.appendChild(el);
    } else if (entry.type === 'added') {
      el = createElementFromHTML(entry.newBlock.outerHTML);
      el.classList.add('inkwell-diff-added');
      el.dataset.diffIndex = idx;
      addPerBlockAcceptBtn(el, idx);
      ctn.appendChild(el);
    } else if (entry.type === 'removed') {
      el = createElementFromHTML(entry.oldBlock.outerHTML);
      el.classList.add('inkwell-diff-removed');
      el.dataset.diffIndex = idx;
      addPerBlockAcceptBtn(el, idx);
      ctn.appendChild(el);
    } else if (entry.type === 'modified') {
      el = createElementFromHTML(entry.newBlock.outerHTML);
      el.classList.add('inkwell-diff-modified');
      el.dataset.diffIndex = idx;
      // Apply word-level diff
      var oldText = entry.oldBlock.textContent;
      var newText = entry.newBlock.textContent;
      el.innerHTML = buildWordDiffHTML(oldText, newText);
      addPerBlockAcceptBtn(el, idx);
      ctn.appendChild(el);
    }
  });

  // Store the diff result for accept operations
  ctn.dataset.currentDiff = JSON.stringify(diff.map(function(e) { return e.type; }));

  renderMermaid();
  updateDocNav(headings, alerts);
  reapplyFindHighlights();
  updateFab();

  // Restore scroll position
  scrollEl.scrollTop = scrollPos;
}

function createElementFromHTML(htmlString) {
  var temp = document.createElement('div');
  temp.innerHTML = htmlString;
  return temp.firstElementChild;
}
```

- [ ] **Step 4: Verify syntax**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 5: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: implement mode branching and diff rendering in handleContentUpdate"
```

---

### Task 10: Implement accept UX (per-block + global)

**Files:**
- Modify: `priv/static/app.js` (implement accept functions, FAB updates, keyboard shortcut)

- [ ] **Step 1: Implement `addPerBlockAcceptBtn`**

Add after `createElementFromHTML`:

```javascript
function addPerBlockAcceptBtn(el, diffIndex) {
  var btn = document.createElement('button');
  btn.className = 'inkwell-diff-accept-btn';
  btn.innerHTML = '\u2713';
  btn.title = 'Accept this change';
  btn.addEventListener('click', function(e) {
    e.stopPropagation();
    acceptBlock(el, diffIndex);
  });
  el.appendChild(btn);
}
```

- [ ] **Step 2: Implement `acceptBlock`**

```javascript
function acceptBlock(el, diffIndex) {
  if (el.classList.contains('inkwell-diff-removed')) {
    // Accepting a removal means we agree it's gone — remove from DOM
    el.style.transition = 'opacity 0.2s ease';
    el.style.opacity = '0';
    setTimeout(function() { el.remove(); updateFab(); }, 200);
    // Update baseline: remove the old block entry
    baselineBlocks = baselineBlocks.filter(function(_, i) {
      // Find which baseline index this removed block corresponds to
      return true; // We'll rebuild baseline from current DOM after
    });
  } else {
    // Added or modified — accept means keep the new content, clear highlight
    var btn = el.querySelector('.inkwell-diff-accept-btn');
    if (btn) btn.remove();
    // Remove word-level diff spans, keeping just their text
    var wordSpans = el.querySelectorAll('.inkwell-diff-word-removed');
    wordSpans.forEach(function(span) { span.remove(); });
    var addedSpans = el.querySelectorAll('.inkwell-diff-word-added');
    addedSpans.forEach(function(span) {
      span.replaceWith(document.createTextNode(span.textContent));
    });
    el.classList.add('inkwell-diff-fade-out');
    setTimeout(function() {
      el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified', 'inkwell-diff-fade-out');
      el.style.borderLeft = '';
      el.style.background = '';
      el.style.paddingLeft = '';
      el.removeAttribute('data-diff-index');
      updateFab();
    }, 200);
  }
  // Rebuild baseline from current DOM state after animation
  setTimeout(function() {
    baselineBlocks = extractBlocks(ctn);
  }, 250);
}
```

- [ ] **Step 3: Implement `acceptAll`**

```javascript
function acceptAll() {
  var highlighted = ctn.querySelectorAll('.inkwell-diff-added, .inkwell-diff-removed, .inkwell-diff-modified');
  highlighted.forEach(function(el) {
    if (el.classList.contains('inkwell-diff-removed')) {
      el.remove();
    } else {
      var btn = el.querySelector('.inkwell-diff-accept-btn');
      if (btn) btn.remove();
      var wordSpans = el.querySelectorAll('.inkwell-diff-word-removed');
      wordSpans.forEach(function(span) { span.remove(); });
      var addedSpans = el.querySelectorAll('.inkwell-diff-word-added');
      addedSpans.forEach(function(span) {
        span.replaceWith(document.createTextNode(span.textContent));
      });
      el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified');
      el.style.borderLeft = '';
      el.style.background = '';
      el.style.paddingLeft = '';
      el.removeAttribute('data-diff-index');
    }
  });
  baselineBlocks = extractBlocks(ctn);
  updateFab();
}
```

- [ ] **Step 4: Implement `updateFab`**

Replace the `updateFab` stub:

```javascript
function updateFab() {
  var added = ctn.querySelectorAll('.inkwell-diff-added').length;
  var modified = ctn.querySelectorAll('.inkwell-diff-modified').length;
  var removed = ctn.querySelectorAll('.inkwell-diff-removed').length;
  var total = added + modified + removed;

  if (total === 0 || currentMode !== 'diff') {
    diffFab.classList.remove('visible');
    return;
  }

  var summaryParts = [];
  if (added > 0) summaryParts.push('<span class="added">+' + added + '</span>');
  if (modified > 0) summaryParts.push('<span class="modified">~' + modified + '</span>');
  if (removed > 0) summaryParts.push('<span class="removed">-' + removed + '</span>');

  diffFab.querySelector('.diff-summary').innerHTML = summaryParts.join(' ');
  diffFab.classList.add('visible');
}
```

- [ ] **Step 5: Add keyboard shortcut for global accept**

In the existing `document.addEventListener('keydown', ...)` handler (around line 829), add this before the Escape handling:

```javascript
// Cmd+Enter or Ctrl+Enter to accept all diffs
if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
  if (currentMode === 'diff' && diffFab.classList.contains('visible')) {
    e.preventDefault();
    acceptAll();
    return;
  }
}
```

- [ ] **Step 6: Verify syntax**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 7: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: implement per-block and global accept with keyboard shortcut"
```

---

### Task 11: Initialize baseline on page load

**Files:**
- Modify: `priv/static/app.js` (set baseline after initial render)

- [ ] **Step 1: Set `baselineBlocks` on initial page load**

At the bottom of `app.js`, right after `renderMermaid()` on line 930 (the final line before the closing `})()`), add:

```javascript
// Initialize baseline for diff mode
if (currentPath && ctn) {
  baselineBlocks = extractBlocks(ctn);
}
```

Also, update the existing `reconnectSocket` function to reset the first-message flag. Find the `reconnectSocket` function and add `isFirstWsMessage = true;` inside it:

```javascript
// In the existing reconnectSocket function, add the reset:
function reconnectSocket() {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
  if (ws) ws.close();
  isFirstWsMessage = true;
  connect();
}
```

- [ ] **Step 2: Verify syntax**

Run: `node -c priv/static/app.js`
Expected: No syntax errors.

- [ ] **Step 3: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: initialize baseline blocks on page load"
```

---

### Task 12: Manual end-to-end testing

**Files:** None (testing only)

- [ ] **Step 1: Compile the project**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 2: Run the full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 3: Start Inkwell and test live reload**

1. Start the daemon: `mix run --no-halt -e 'Inkwell.CLI.run_daemon("dark")'`
2. Create a test file: `echo "# Test\n\nOriginal content" > /tmp/test-diff.md`
3. Open preview: `curl "http://localhost:$(cat ~/.inkwell/port)/open?path=/tmp/test-diff.md&theme=dark"`
4. Open the URL in a browser
5. Verify you see the mode toggle buttons (Static | Live | Diff) in the header
6. Verify Diff mode is active by default

- [ ] **Step 4: Test diff mode**

1. In another terminal, modify the file:
   ```bash
   printf "# Test\n\nUpdated content with changes.\n\n## New Section\n\nThis was added.\n" > /tmp/test-diff.md
   ```
2. Verify the browser shows:
   - The modified paragraph with amber border and word-level highlights ("Original" struck through in red, "Updated" + "with changes." in green)
   - The new section with green border
3. Verify the floating accept FAB appears in the bottom-right with change counts

- [ ] **Step 5: Test per-block accept**

1. Hover over a highlighted block — verify the checkmark icon appears
2. Click the checkmark on the modified block — verify the highlight fades away
3. Verify the FAB count updates
4. Click the remaining "New Section" accept — verify the FAB disappears

- [ ] **Step 6: Test global accept**

1. Modify the file again to produce new diffs
2. Press `Cmd+Enter` — verify all highlights clear at once
3. Verify the FAB disappears

- [ ] **Step 7: Test mode switching**

1. Switch to Live mode — verify future edits update immediately with no diff highlights
2. Switch to Static mode — verify edits have no visible effect
3. Switch back to Diff mode — verify the pending change (if any) is shown as a diff
4. Refresh the page — verify the mode persists from `localStorage`

- [ ] **Step 8: Test the --mode CLI flag**

1. Stop the daemon
2. Preview with `--mode live`: verify page opens in Live mode
3. Verify the `data-mode="live"` attribute is on the `<body>` tag

- [ ] **Step 9: Final commit**

If any fixes were needed during testing, commit them:

```bash
git add -A
git commit -m "fix: adjustments from end-to-end testing"
```
