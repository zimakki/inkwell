# Repository-Wide Markdown File Search — Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Repository" section to the file picker that finds all markdown files in the current git repo, plus fix the empty-state page to show the picker instead of an error.

**Architecture:** New `Inkwell.GitRepo` module handles git root detection and recursive directory walking. `Inkwell.Search` gains structured responses with a repository section. The `/search` endpoint changes from flat array to structured object. Frontend parses the new format and renders a third picker section.

**Tech Stack:** Elixir, Plug, vanilla JS, CSS custom properties

**Spec:** `docs/superpowers/specs/2026-03-13-repository-search-design.md`

---

## Chunk 1: GitRepo Module + Search Integration

### Task 1: GitRepo — find_root/1

**Files:**
- Create: `lib/inkwell/git_repo.ex`
- Create: `test/inkwell/git_repo_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/inkwell/git_repo_test.exs
defmodule Inkwell.GitRepoTest do
  use ExUnit.Case, async: true

  describe "find_root/1" do
    test "finds git root from a file inside a repo" do
      # This project itself is a git repo
      file = Path.expand("lib/inkwell/git_repo.ex")
      assert {:ok, root} = Inkwell.GitRepo.find_root(file)
      assert File.exists?(Path.join(root, ".git"))
    end

    test "finds git root from a directory inside a repo" do
      dir = Path.expand("lib/inkwell")
      assert {:ok, root} = Inkwell.GitRepo.find_root(dir)
      assert File.exists?(Path.join(root, ".git"))
    end

    test "returns :error for path outside any repo" do
      assert :error = Inkwell.GitRepo.find_root("/tmp")
    end

    test "returns :error for root directory" do
      assert :error = Inkwell.GitRepo.find_root("/")
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/git_repo_test.exs --max-failures 1`
Expected: FAIL — module `Inkwell.GitRepo` not found

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/inkwell/git_repo.ex
defmodule Inkwell.GitRepo do
  @moduledoc "Detects git repositories and discovers markdown files within them."

  @doc "Walk up from `path` looking for a `.git` directory. Returns `{:ok, root}` or `:error`."
  def find_root(path) do
    path
    |> Path.expand()
    |> do_find_root()
  end

  defp do_find_root("/"), do: :error

  defp do_find_root(dir) do
    dir = if File.dir?(dir), do: dir, else: Path.dirname(dir)

    if File.exists?(Path.join(dir, ".git")) do
      {:ok, dir}
    else
      do_find_root(Path.dirname(dir))
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/inkwell/git_repo_test.exs -v`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell/git_repo.ex test/inkwell/git_repo_test.exs
git commit -m "feat: add GitRepo.find_root/1 for git root detection"
```

### Task 2: GitRepo — find_markdown_files/1

**Files:**
- Modify: `lib/inkwell/git_repo.ex`
- Modify: `test/inkwell/git_repo_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/inkwell/git_repo_test.exs`:

```elixir
describe "find_markdown_files/1" do
  setup do
    base = Path.join(System.tmp_dir!(), "inkwell-gitrepo-#{System.unique_integer([:positive])}")
    # Create a fake repo structure
    File.mkdir_p!(Path.join(base, ".git"))
    File.mkdir_p!(Path.join(base, "docs/api"))
    File.mkdir_p!(Path.join(base, "node_modules/pkg"))
    File.mkdir_p!(Path.join(base, "_build/dev"))
    File.mkdir_p!(Path.join(base, ".superpowers"))

    File.write!(Path.join(base, "README.md"), "# Root Readme")
    File.write!(Path.join(base, "docs/setup.md"), "# Setup")
    File.write!(Path.join(base, "docs/api/endpoints.md"), "# Endpoints")
    File.write!(Path.join(base, "node_modules/pkg/README.md"), "# Should skip")
    File.write!(Path.join(base, "_build/dev/notes.md"), "# Should skip")
    File.write!(Path.join(base, ".superpowers/design.md"), "# Should NOT skip")
    File.write!(Path.join(base, "not_markdown.txt"), "ignore")

    on_exit(fn -> File.rm_rf!(base) end)
    {:ok, %{base: base}}
  end

  test "finds all .md files recursively", %{base: base} do
    files = Inkwell.GitRepo.find_markdown_files(base)
    filenames = Enum.map(files, &Path.basename/1)

    assert "README.md" in filenames
    assert "setup.md" in filenames
    assert "endpoints.md" in filenames
    assert "design.md" in filenames
  end

  test "skips directories in the skip list", %{base: base} do
    files = Inkwell.GitRepo.find_markdown_files(base)
    paths = Enum.join(files, " ")

    refute paths =~ "node_modules"
    refute paths =~ "_build"
  end

  test "does NOT skip .superpowers", %{base: base} do
    files = Inkwell.GitRepo.find_markdown_files(base)
    assert Enum.any?(files, &String.contains?(&1, ".superpowers"))
  end

  test "excludes non-markdown files", %{base: base} do
    files = Inkwell.GitRepo.find_markdown_files(base)
    refute Enum.any?(files, &String.ends_with?(&1, ".txt"))
  end

  test "returns sorted paths", %{base: base} do
    files = Inkwell.GitRepo.find_markdown_files(base)
    assert files == Enum.sort(files)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/git_repo_test.exs --max-failures 1`
Expected: FAIL — `find_markdown_files/1` undefined

- [ ] **Step 3: Write implementation**

Add to `lib/inkwell/git_repo.ex`:

```elixir
@skip_dirs MapSet.new([
  ".git", "node_modules", "_build", "deps", ".elixir_ls",
  "_opam", "target", "vendor", ".cache", "dist", "build"
])

@doc "Recursively find all `.md` files under `root`, skipping common artifact directories."
def find_markdown_files(root) do
  root
  |> walk_dir([])
  |> Enum.sort()
end

defp walk_dir(dir, acc) do
  case File.ls(dir) do
    {:ok, entries} ->
      Enum.reduce(entries, acc, fn entry, acc ->
        full = Path.join(dir, entry)

        cond do
          File.dir?(full) and entry not in @skip_dirs ->
            walk_dir(full, acc)

          String.ends_with?(entry, ".md") ->
            [full | acc]

          true ->
            acc
        end
      end)

    {:error, _} ->
      acc
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/inkwell/git_repo_test.exs -v`
Expected: 9 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell/git_repo.ex test/inkwell/git_repo_test.exs
git commit -m "feat: add GitRepo.find_markdown_files/1 for recursive discovery"
```

### Task 3: Search — structured response with repository section

**Files:**
- Modify: `lib/inkwell/search.ex:41-95`
- Modify: `test/inkwell/search_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/inkwell/search_test.exs`:

```elixir
describe "list_recent/0" do
  test "returns structured response with only recent files", %{current: current} do
    result = Inkwell.Search.list_recent()
    assert is_map(result)
    assert is_list(result.recent)
    assert result.siblings == []
    assert result.repository == nil
    assert Enum.any?(result.recent, &(&1.path == current))
  end
end

describe "structured list_files/1" do
  test "returns map with recent and siblings keys", %{current: current, sibling: sibling} do
    result = Inkwell.Search.list_files(current)
    assert is_map(result)
    assert Enum.any?(result.recent, &(&1.path == current))
    assert Enum.any?(result.siblings, &(&1.path == sibling))
  end
end

describe "structured search/2" do
  test "search with query returns structured result", %{current: current} do
    result = Inkwell.Search.search(current, "beta")
    assert is_map(result)
    # Results are merged into recent/siblings based on original section
    all_files = result.recent ++ result.siblings ++ (result.repository && result.repository.files || [])
    assert Enum.any?(all_files, &(&1.filename == "beta.md"))
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/search_test.exs --max-failures 1`
Expected: FAIL — `list_recent/0` undefined or `list_files/1` returns list not map

- [ ] **Step 3: Refactor list_files/1 to return structured map, add list_recent/0**

Modify `lib/inkwell/search.ex`. Key changes:

1. `list_files/1` returns `%{recent: [...], siblings: [...], repository: repo_or_nil}`
2. New `list_recent/0` returns `%{recent: [...], siblings: [], repository: nil}`
3. Repository section: call `GitRepo.find_root/1`, then `GitRepo.find_markdown_files/1`, dedup against recent+siblings, cap at 20, extract titles
4. `search/2` with query: fuzzy match across all entries (including repo), return structured. For repo entries, score against `rel_path` at 0.8 weight too.
5. `allowed_path?/2` stays working — it now checks the structured result

```elixir
@max_results 50
@max_repo_initial 20

def list_recent do
  recent =
    Inkwell.History.list()
    |> Enum.filter(&File.exists?/1)
    |> Enum.map(fn path ->
      %{path: path, filename: Path.basename(path), title: extract_title(path), section: :recent}
    end)

  %{recent: recent, siblings: [], repository: nil}
end

def list_files(current_path) do
  dir = Path.dirname(current_path)
  recent = Inkwell.History.list()
  existing_recent = Enum.filter(recent, &File.exists?/1)

  recent_entries =
    Enum.map(existing_recent, fn path ->
      %{
        path: path,
        filename: Path.basename(path),
        title: extract_title(path),
        section: :recent,
        active: path == current_path
      }
    end)

  recent_paths = MapSet.new(existing_recent)

  sibling_entries =
    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".md"))
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.reject(&MapSet.member?(recent_paths, &1))
    |> Enum.sort()
    |> Enum.map(fn path ->
      %{
        path: path,
        filename: Path.basename(path),
        title: extract_title(path),
        section: :sibling,
        active: path == current_path
      }
    end)

  known_paths = MapSet.union(recent_paths, MapSet.new(sibling_entries, & &1.path))
  repository = build_repository(current_path, known_paths)

  %{recent: recent_entries, siblings: sibling_entries, repository: repository}
end

def search(current_path, query) when query in ["", nil], do: list_files(current_path)

def search(current_path, query) do
  %{recent: recent, siblings: siblings, repository: repo} = list_files(current_path)

  all_entries = recent ++ siblings ++ if(repo, do: repo.files, else: [])

  scored =
    all_entries
    |> Enum.map(fn entry ->
      filename_score = fuzzy_score(query, entry.filename)
      title_score = fuzzy_score(query, entry.title) * 1.2
      rel_path_score = fuzzy_score(query, Map.get(entry, :rel_path)) * 0.8
      score = Enum.max([filename_score, title_score, rel_path_score])
      {entry, score}
    end)
    |> Enum.reject(fn {_entry, score} -> score == 0 end)
    |> Enum.sort_by(fn {_entry, score} -> score end, :desc)
    |> Enum.take(@max_results)

  # Re-group into sections
  {recent_results, rest} = Enum.split_with(scored, fn {e, _} -> e.section == :recent end)
  {sibling_results, repo_results} = Enum.split_with(rest, fn {e, _} -> e.section == :sibling end)

  strip = fn list -> Enum.map(list, fn {entry, _score} -> entry end) end

  repo_section =
    if repo do
      %{repo | files: strip.(repo_results)}
    else
      nil
    end

  %{recent: strip.(recent_results), siblings: strip.(sibling_results), repository: repo_section}
end

def allowed_path?(current_path, candidate_path) do
  # Use a lightweight check that skips the expensive build_repository call
  dir = Path.dirname(current_path)
  recent_paths = Inkwell.History.list() |> Enum.filter(&File.exists?/1)

  sibling_paths =
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.map(&Path.join(dir, &1))

      {:error, _} ->
        []
    end

  candidate_path in recent_paths or candidate_path in sibling_paths
end

defp build_repository(current_path, known_paths) do
  case Inkwell.GitRepo.find_root(current_path) do
    {:ok, root} ->
      all_files = Inkwell.GitRepo.find_markdown_files(root)
      repo_name = Path.basename(root)

      repo_files =
        all_files
        |> Enum.reject(&MapSet.member?(known_paths, &1))
        |> Enum.take(@max_repo_initial)
        |> Enum.map(fn path ->
          rel = Path.relative_to(path, root)

          %{
            path: path,
            filename: Path.basename(path),
            rel_path: rel,
            title: extract_title(path),
            section: :repository
          }
        end)

      %{name: repo_name, files: repo_files, total: length(all_files) - MapSet.size(known_paths)}

    :error ->
      nil
  end
end
```

- [ ] **Step 4: Update existing tests that expect flat list**

The existing tests in `search_test.exs` expect `search/2` to return a flat list. Update them:

- `test "search returns recent and sibling markdown files"` — change to access `result.recent` and `result.siblings`
- `test "search excludes non-markdown files"` — check all sections
- `test "search with query filters results"` — check across all sections
- `test "allowed_path? accepts sibling files"` — should still work (internal change)
- `test "allowed_path? rejects files outside allowed set"` — should still work

```elixir
test "search returns recent and sibling markdown files", %{current: current, sibling: sibling} do
  result = Inkwell.Search.search(current, "")

  assert Enum.any?(result.recent, &(&1.path == current and &1.section == :recent))
  assert Enum.any?(result.siblings, &(&1.path == sibling and &1.section == :sibling))
end

test "search excludes non-markdown files", %{current: current, base: base} do
  result = Inkwell.Search.search(current, "")
  gamma_txt = Path.join(base, "gamma.txt")
  all_paths = Enum.map(result.recent ++ result.siblings, & &1.path)
  refute gamma_txt in all_paths
end

test "search with query filters results", %{current: current} do
  result = Inkwell.Search.search(current, "beta")
  all_files = result.recent ++ result.siblings ++ if(result.repository, do: result.repository.files, else: [])
  assert Enum.any?(all_files, &(&1.filename == "beta.md"))
end
```

- [ ] **Step 5: Run all tests**

Run: `mix test test/inkwell/search_test.exs -v`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell/search.ex test/inkwell/search_test.exs
git commit -m "feat: structured search responses with repository section"
```

### Task 4: Router — update /search handler and authorized?

**Files:**
- Modify: `lib/inkwell/router.ex:42-43` (empty state GET /)
- Modify: `lib/inkwell/router.ex:133-146` (/search handler)
- Modify: `lib/inkwell/router.ex:235-243` (authorized?)
- Modify: `test/inkwell/router_test.exs`

- [ ] **Step 1: Write failing tests**

Add to `test/inkwell/router_test.exs`:

```elixir
test "GET / without path or dir returns 200 with picker page" do
  conn = conn(:get, "/") |> Inkwell.Router.call(Inkwell.Router.init([]))

  assert conn.status == 200
  assert conn.resp_body =~ "data-no-file"
  assert conn.resp_body =~ "app.js"
end

test "GET /search without current returns recent files only", %{test_file: test_file} do
  Inkwell.History.push(test_file)

  conn =
    conn(:get, "/search?q=")
    |> Inkwell.Router.call(Inkwell.Router.init([]))

  assert conn.status == 200
  body = Jason.decode!(conn.resp_body)
  assert is_map(body)
  assert is_list(body["recent"])
  assert body["siblings"] == []
  assert body["repository"] == nil
end

test "GET /search with current returns structured response", %{test_file: test_file} do
  Inkwell.History.push(test_file)

  conn =
    conn(:get, "/search?current=#{URI.encode_www_form(test_file)}&q=")
    |> Inkwell.Router.call(Inkwell.Router.init([]))

  assert conn.status == 200
  body = Jason.decode!(conn.resp_body)
  assert is_map(body)
  assert is_list(body["recent"])
  assert is_list(body["siblings"])
end

test "GET /switch with source=repository allows files under git root", %{base: base} do
  # Create a file in a subdirectory
  sub_dir = Path.join(base, "sub")
  File.mkdir_p!(sub_dir)
  # Need a .git dir in base to make it a "repo"
  File.mkdir_p!(Path.join(base, ".git"))
  sub_file = Path.join(sub_dir, "deep.md")
  File.write!(sub_file, "# Deep File")
  current = Path.join(base, "test.md")

  conn =
    conn(
      :get,
      "/switch?current=#{URI.encode_www_form(current)}&path=#{URI.encode_www_form(sub_file)}&source=repository"
    )
    |> Inkwell.Router.call(Inkwell.Router.init([]))

  assert conn.status == 200
  body = Jason.decode!(conn.resp_body)
  assert body["path"] == sub_file
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/router_test.exs --max-failures 1`
Expected: FAIL — the empty state test expects 200 but gets 400

- [ ] **Step 3: Update router**

In `lib/inkwell/router.ex`:

**Empty state (line 42-43):**
```elixir
true ->
  theme = :persistent_term.get(:inkwell_theme, "dark")
  page = empty_page(theme)

  conn
  |> put_resp_content_type("text/html")
  |> send_resp(200, page)
```

**Search handler (lines 133-146):**
```elixir
get "/search" do
  conn = Plug.Conn.fetch_query_params(conn)
  query = conn.query_params["q"] || ""

  results =
    case conn.query_params["current"] do
      nil -> Inkwell.Search.list_recent()
      "" -> Inkwell.Search.list_recent()
      current -> Inkwell.Search.search(Path.expand(current), query)
    end

  conn
  |> put_resp_content_type("application/json")
  |> send_resp(200, Jason.encode!(results))
end
```

**Authorization (lines 235-243):**
```elixir
defp authorized?(_current_path, new_path, "browse") do
  File.exists?(new_path) and markdown_file?(new_path)
end

defp authorized?(current_path, new_path, "repository") do
  File.exists?(new_path) and markdown_file?(new_path) and
    case Inkwell.GitRepo.find_root(current_path) do
      {:ok, root} -> String.starts_with?(new_path, root <> "/") or new_path == root
      :error -> false
    end
end

defp authorized?(current_path, new_path, _source) do
  File.exists?(new_path) and
    markdown_file?(new_path) and
    Inkwell.Search.allowed_path?(current_path, new_path)
end
```

**Add empty_page/1 function** (new private function, similar to browse_page):
```elixir
defp empty_page(theme) do
  """
  <!DOCTYPE html>
  <html lang="en">
  <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Inkwell</title>
    <link rel="stylesheet" href="/static/markdown-wide.css">
    <link rel="stylesheet" href="/static/app.css">
    <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
  </head>
  <body data-no-file="true">
    <div data-theme="#{theme}">
      <div id="page-header">
        <h3 id="header-title">Inkwell</h3>
      </div>
      <div id="page-ctn">
        <div style="display:flex;align-items:center;justify-content:center;height:60vh;color:var(--text-muted);font-family:system-ui;font-size:15px;">
          Open a file to get started
        </div>
      </div>
    </div>

    <div id="picker-overlay">
      <div id="picker">
        <div id="picker-search">
          <span id="picker-search-icon">&#9906;</span>
          <input type="text" id="picker-input" placeholder="Search files and titles..." autocomplete="off" />
          <button id="btn-open-file" class="picker-btn" title="Open a markdown file">Open File</button>
          <button id="btn-open-folder" class="picker-btn" title="Browse a folder">Open Folder</button>
          <span class="hint">ESC to close</span>
        </div>
        <div id="picker-path"></div>
        <div id="picker-body">
          <div id="picker-list">
            <div id="picker-list-items"></div>
            <div id="picker-status"></div>
          </div>
          <div id="picker-preview">
            <div class="preview-unavailable">Select a file to preview</div>
          </div>
        </div>
      </div>
    </div>

    <script src="/static/app.js"></script>
  </body>
  </html>
  """
end
```

- [ ] **Step 4: Remove/update existing router tests that conflict with new behavior**

Delete these two tests that now have different expected behavior (replaced by new tests in Step 1):

1. `"GET / without path or dir param returns 400"` (line 52-56) — now returns 200 with `data-no-file`
2. `"GET /search without current returns 400"` (line 119-125) — now returns 200 with `list_recent()` results

- [ ] **Step 5: Update the /search test that expects a flat list**

The existing test `"GET /search returns results"` expects `is_list(results)`. Update to expect `is_map(body)`:

```elixir
test "GET /search returns structured results", %{test_file: test_file} do
  Inkwell.History.push(test_file)

  conn =
    conn(:get, "/search?current=#{URI.encode_www_form(test_file)}&q=")
    |> Inkwell.Router.call(Inkwell.Router.init([]))

  assert conn.status == 200
  body = Jason.decode!(conn.resp_body)
  assert is_map(body)
  assert is_list(body["recent"])
end
```

- [ ] **Step 6: Run all tests**

Run: `mix test test/inkwell/router_test.exs test/inkwell/search_test.exs -v`
Expected: All pass

- [ ] **Step 7: Run full test suite**

Run: `mix test`
Expected: All pass

- [ ] **Step 8: Commit**

```bash
git add lib/inkwell/router.ex test/inkwell/router_test.exs
git commit -m "feat: structured /search response, repository auth, empty state page"
```

---

## Chunk 2: Frontend — Picker Updates and Styling

### Task 5: CSS — repository section styling

**Files:**
- Modify: `priv/static/app.css:86-109`

- [ ] **Step 1: Add CSS for repository section and directory path**

Append to `priv/static/app.css`:

```css
.picker-section.repo {
  color: var(--h2);
}

.picker-item-dir {
  color: var(--text-muted);
  font-size: 11px;
  font-family: 'SF Mono', monospace;
  margin-left: auto;
  flex-shrink: 0;
  padding-left: 8px;
}

.picker-item-title-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.picker-hint {
  padding: 6px 12px;
  color: var(--text-muted);
  font-size: 11px;
  font-style: italic;
  font-family: system-ui;
}
```

- [ ] **Step 2: Verify format**

Run: `mix format --check-formatted`
Expected: CSS is not checked by mix format, should pass

- [ ] **Step 3: Commit**

```bash
git add priv/static/app.css
git commit -m "feat: add CSS for repository picker section"
```

### Task 6: app.js — parse structured response and render repository section

**Files:**
- Modify: `priv/static/app.js:56-106`

- [ ] **Step 1: Update loadSearch() to parse structured response**

In `priv/static/app.js`, modify the `loadSearch` function (line 56). The `.then(function(files) {...})` handler changes to:

```javascript
var repoInfo = null;

function loadSearch(query) {
  if (previewController) { previewController.abort(); previewController = null; }
  var url;
  if (browseDir) {
    url = '/browse?dir=' + encodeURIComponent(browseDir) + '&q=' + encodeURIComponent(query);
  } else {
    var params = 'q=' + encodeURIComponent(query);
    if (currentPath) {
      params = 'current=' + encodeURIComponent(currentPath) + '&' + params;
    }
    url = '/search?' + params;
  }
  fetch(url)
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (browseDir) {
        // Browse mode still returns flat array
        currentFiles = data;
        repoInfo = null;
      } else {
        // Structured response
        currentFiles = (data.recent || []).concat(data.siblings || []);
        if (data.repository && data.repository.files) {
          repoInfo = { name: data.repository.name, total: data.repository.total };
          currentFiles = currentFiles.concat(data.repository.files);
        } else {
          repoInfo = null;
        }
      }
      selectedIndex = 0;
      renderPathBar();
      renderFileList();
      loadPreview();
    })
    .catch(function() {});
}
```

- [ ] **Step 2: Update renderFileList() to render repository section with directory paths**

Replace `renderFileList` function (line 78):

```javascript
function renderFileList() {
  var html = '';
  var currentSection = null;
  currentFiles.forEach(function(f, i) {
    if (f.section !== currentSection) {
      currentSection = f.section;
      var label;
      var cls = 'picker-section';
      if (f.section === 'recent') {
        label = 'Recent';
      } else if (f.section === 'browse' && browseDir) {
        label = 'Browse: ' + browseDir;
      } else if (f.section === 'repository' && repoInfo) {
        label = 'Repository (' + repoInfo.name + ')';
        cls = 'picker-section repo';
      } else {
        label = f.path.split('/').slice(-2, -1)[0] + '/';
      }
      html += '<div class="' + cls + '">' + escapeHtml(label) + '</div>';
    }
    var itemCls = i === selectedIndex ? 'picker-item selected' : 'picker-item';
    var title = f.title || f.filename;

    if (f.section === 'repository' && f.rel_path) {
      var relDir = f.rel_path.split('/').slice(0, -1).join('/');
      html += '<div class="' + itemCls + '" data-index="' + i + '">'
        + '<div class="picker-item-title-row">'
        + '<span class="picker-item-title">' + escapeHtml(title) + '</span>'
        + (relDir ? '<span class="picker-item-dir">' + escapeHtml(relDir + '/') + '</span>' : '')
        + '</div>'
        + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
        + '</div>';
    } else {
      html += '<div class="' + itemCls + '" data-index="' + i + '">'
        + '<div class="picker-item-title">' + escapeHtml(title) + '</div>'
        + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
        + '</div>';
    }
  });

  // Truncation hint for repository section
  if (repoInfo && repoInfo.total > 0) {
    var repoFilesShown = currentFiles.filter(function(f) { return f.section === 'repository'; }).length;
    if (repoFilesShown < repoInfo.total) {
      html += '<div class="picker-hint">Showing ' + repoFilesShown + ' of ' + repoInfo.total + ' files — type to search all</div>';
    }
  }

  pickerListItems.innerHTML = html;
  pickerStatus.textContent = currentFiles.length + ' files \u00b7 \u2191\u2193 navigate \u00b7 \u21b5 open';

  var sel = pickerListItems.querySelector('.selected');
  if (sel) sel.scrollIntoView({ block: 'nearest' });
}
```

- [ ] **Step 3: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: parse structured search response and render repository section"
```

### Task 7: app.js — empty state, source=repository, and selectFile/preview updates

**Files:**
- Modify: `priv/static/app.js:108-136` (loadPreview, selectFile)
- Modify: `priv/static/app.js:209-256` (btnOpenFile, btnOpenFolder handlers)
- Modify: `priv/static/app.js:373-384` (init block)

- [ ] **Step 1: Update selectFile() — handle empty state + source=repository**

Replace the entire `selectFile` function (line 147-166) with the final version that handles all cases:

```javascript
function selectFile() {
  var file = currentFiles[selectedIndex];
  if (!file) return;

  // Empty state: no currentPath, do full page navigation
  if (!currentPath && !browseDir) {
    window.location = '/?path=' + encodeURIComponent(file.path);
    return;
  }

  var switchCurrent = currentPath || file.path;
  var source = '';
  if (browseDir) {
    source = '&source=browse';
  } else if (file.section === 'repository') {
    source = '&source=repository';
  }
  var url = '/switch?current=' + encodeURIComponent(switchCurrent) + '&path=' + encodeURIComponent(file.path) + source;
  fetch(url)
    .then(function(r) {
      if (!r.ok) throw new Error('Switch failed');
      return r.json();
    })
    .then(function(data) {
      currentPath = data.path;
      headerTitle.textContent = data.filename;
      document.title = data.filename;
      history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
      reconnectSocket();
      closePicker();
    });
}
```

- [ ] **Step 2: Update loadPreview() — add source=repository**

In the `loadPreview` function (line 108-136), update the URL construction (around line 120-121) to include source param:

```javascript
// Replace line 121:
//   if (browseDir) url += '&source=browse';
// With:
var source = '';
if (browseDir) source = '&source=browse';
else if (file.section === 'repository') source = '&source=repository';
var url = '/preview?current=' + encodeURIComponent(previewCurrent) + '&path=' + encodeURIComponent(file.path) + source;
```

- [ ] **Step 3: Update btnOpenFile handler for empty state**

The `btnOpenFile` click handler (line 209-235) uses `currentPath` in the `/switch` URL. When `currentPath` is null (empty state), this breaks. Update to do full page navigation instead:

```javascript
btnOpenFile.addEventListener('click', function(e) {
  e.stopPropagation();
  fetch('/pick-file')
    .then(function(r) {
      if (r.status === 204) return null;
      if (!r.ok) throw new Error('Pick failed');
      return r.json();
    })
    .then(function(data) {
      if (!data) return;

      // Empty state: no currentPath, do full page navigation
      if (!currentPath) {
        window.location = '/?path=' + encodeURIComponent(data.path);
        return;
      }

      browseDir = '__pick__';
      var url = '/switch?current=' + encodeURIComponent(currentPath) + '&path=' + encodeURIComponent(data.path) + '&source=browse';
      return fetch(url).then(function(r) {
        if (!r.ok) throw new Error('Switch failed');
        return r.json();
      }).then(function(switchData) {
        currentPath = switchData.path;
        headerTitle.textContent = switchData.filename;
        document.title = switchData.filename;
        history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
        reconnectSocket();
        closePicker();
      });
    })
    .catch(function() {});
});
```

- [ ] **Step 4: Update btnOpenFolder handler for empty state**

The `btnOpenFolder` click handler (line 237-256) works fine in empty state (it sets `browseDir` and loads files without needing `currentPath`). No changes needed — verify by reading the existing code.

- [ ] **Step 5: Add empty state detection to init block**

At the bottom of `app.js`, update the init block (line 373-384):

```javascript
var noFile = document.body.dataset.noFile;

if (noFile) {
  // Empty state — auto-open picker with recent files
  pickerOverlay.classList.add('open');
  pickerInput.focus();
  selectedIndex = 0;
  renderPathBar();
  loadSearch('');
} else if (initialBrowseDir) {
  browseDir = initialBrowseDir;
  pickerOverlay.classList.add('open');
  pickerInput.focus();
  selectedIndex = 0;
  renderPathBar();
  loadSearch('');
} else if (currentPath) {
  connect();
}
renderMermaid();
```

- [ ] **Step 6: Manual test**

Open Inkwell without arguments:
```bash
open http://localhost:50146/
```

Expected:
- Page loads with "Open a file to get started" message
- Picker auto-opens
- Recent files shown (if any in history)
- Open File button works — picks a file and navigates via full page load
- Open Folder button works — switches to browse mode
- Selecting a recent file navigates to preview mode

- [ ] **Step 7: Commit**

```bash
git add priv/static/app.js
git commit -m "feat: empty state handling, source=repository for switch/preview"
```

### Task 8: Final verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 2: Run format check**

Run: `mix format --check-formatted`
Expected: No formatting issues

- [ ] **Step 3: Run compiler warnings check**

Run: `mix compile --warnings-as-errors`
Expected: No warnings

- [ ] **Step 4: Manual end-to-end test**

1. Open a markdown file in a git repo: `inkwell preview README.md`
2. Press Ctrl+P to open picker
3. Verify: Recent, Sibling, and Repository sections all appear
4. Verify: Repository files show directory path on the right
5. Verify: "Showing N of M files" hint appears
6. Type a search query — verify repo files are included in results
7. Select a repo file — verify it loads with preview
8. Open `http://localhost:<port>/` directly — verify empty state with picker

- [ ] **Step 5: Final commit with version bump**

Update version in `mix.exs` (patch bump per project conventions), plus `src-tauri/Cargo.toml`, `src-tauri/tauri.conf.json`, and `src-tauri/Cargo.lock`:

```bash
# After bumping versions in all 4 files:
git add mix.exs src-tauri/Cargo.toml src-tauri/tauri.conf.json src-tauri/Cargo.lock
git commit -m "Bump version to 0.2.12"
```
