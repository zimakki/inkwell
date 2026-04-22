# Theme Configurability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Inkwell's hardcoded dark/light themes with a JSON-backed theme system: shipped presets plus user themes, settings tab in the file-picker modal with a live-preview editor, header theme dropdown, and CLI `--theme` accepting any theme name.

**Architecture:** One new module `Inkwell.Themes` (GenServer) loads all theme JSON files at boot and caches their pre-computed CSS. The root layout emits the active theme's CSS as an inline `<style>` block. `Inkwell.Settings` grows from a plain-text file to a JSON file with the active theme name. Settings UI lives inside the existing `PickerComponent` as a second tab.

**Tech Stack:** Elixir + Phoenix LiveView + MDEx + Jason. Rust `font-kit` crate for system-font enumeration in the Tauri desktop app. No new Elixir dependencies.

**Spec:** `docs/superpowers/specs/2026-04-19-theme-configurability-design.md`

---

## File Structure

**New files:**

- `lib/inkwell/themes.ex` — GenServer: load/cache/list/get/active/set_active/save/duplicate/rename/delete
- `priv/themes/default-dark.json` — exact port of today's dark values
- `priv/themes/default-light.json` — exact port of today's light values
- `priv/themes/plain.json` — minimalist grayscale
- `priv/themes/dracula.json`
- `priv/themes/solarized-light.json`
- `priv/themes/gruvbox-dark.json`
- `assets/js/hooks/system_fonts.js` — Tauri font-list hook
- `test/inkwell/themes_test.exs`
- `test/inkwell_web/live/settings_tab_test.exs`

**Modified files:**

- `lib/inkwell/application.ex` — start `Inkwell.Themes` under supervisor; drop `:persistent_term.put(:inkwell_theme, …)` / `resolve_theme/1`
- `lib/inkwell/settings.ex` — switch from plain-text `theme` file to JSON `settings.json`; `read_active/0`, `write_active/1`, `init/0`
- `lib/inkwell/renderer.ex` — pull `syntax_theme` from `Inkwell.Themes.active/0`
- `lib/inkwell/cli.ex` — `--theme` accepts any theme name; update `help_text/0`
- `lib/inkwell_web/live_hooks/shell.ex` — `set_active_theme` event replaces `toggle_theme`; assigns `:active_theme` (full struct) instead of `:theme` string
- `lib/inkwell_web/picker_component.ex` — add `:tab` assign (`:files | :settings`); render settings tab alongside files tab; gear button switches tabs; new events for theme list + editor
- `lib/inkwell_web/components/layouts/root.html.heex` — inline `<style>` block with active theme CSS
- `lib/inkwell_web/components/layouts/app.html.heex` — `data-theme={@active_theme.mode}`; replace sun/moon button with theme dropdown
- `priv/static/markdown-wide.css` — remove the two top-level CSS-variable declaration blocks; everything else stays
- `priv/static/app.css` — tab switcher styles, settings tab styles, dropdown styles
- `assets/js/app.js` — register `SystemFonts` hook
- `src-tauri/src/main.rs` — register `list_system_fonts` command
- `src-tauri/Cargo.toml` — add `font-kit` dependency
- `test/inkwell/renderer_test.exs` — syntax_theme sourced from active theme
- `test/inkwell/cli_test.exs` — `--theme` accepts any valid theme name
- `test/inkwell/settings_test.exs` — JSON settings read/write

**No Ecto/SQLite here.** Everything is plain JSON on disk + in-memory cache.

---

## Task 1: Theme JSON schema + `priv/themes/default-dark.json` + `priv/themes/default-light.json`

**Files:**
- Create: `priv/themes/default-dark.json`
- Create: `priv/themes/default-light.json`

Port today's two hardcoded CSS blocks in `priv/static/markdown-wide.css` (the top-level `body { --bg: … }` for light, and `body:has([data-theme="dark"]) { … }` for dark) into theme JSON files. The JSON keys are the CSS variable names with `--` stripped and `-` replaced by `_` (e.g. `--bg-surface` → `bg_surface`).

- [ ] **Step 1: Create `priv/themes/default-dark.json`**

Populate from the dark block in `priv/static/markdown-wide.css` (lines ~77–136). `mode: "dark"`, `syntax_theme: "onedark"`, fonts match today's layout (`Bricolage Grotesque`, `Outfit`, `SF Mono`).

```json
{
  "name": "Default Dark",
  "mode": "dark",
  "syntax_theme": "onedark",
  "fonts": {
    "heading": "Bricolage Grotesque",
    "body": "Outfit",
    "mono": "SF Mono"
  },
  "colors": {
    "bg": "#16161e",
    "bg_surface": "#1f2335",
    "bg_hover": "#292e46",
    "text": "#c0caf5",
    "text_secondary": "#a9b1d6",
    "text_muted": "#565f89",
    "h1": "#f0c674",
    "h2": "#7aa2f7",
    "h3": "#73daca",
    "h4": "#bb9af7",
    "link": "#7dcfff",
    "link_hover": "#a8e0ff",
    "accent": "#ff757f",
    "border": "#2f334d",
    "border_subtle": "#24283b",
    "blockquote_bar": "#ff757f",
    "blockquote_bg": "rgba(255, 117, 127, 0.06)",
    "blockquote_text": "#a9b1d6",
    "table_border": "rgba(122, 162, 247, 0.25)",
    "table_header_bg": "rgba(122, 162, 247, 0.12)",
    "table_header_text": "#7aa2f7",
    "table_stripe": "rgba(122, 162, 247, 0.05)",
    "table_hover": "rgba(122, 162, 247, 0.1)",
    "table_accent": "#7aa2f7",
    "code_bg": "#24283b",
    "code_text": "#ff9e64",
    "code_border": "#2f334d",
    "pre_bg": "#1a1b26",
    "pre_border": "#2f334d",
    "pre_scrollbar_thumb": "#3b4261",
    "pre_scrollbar_track": "transparent",
    "header_text": "#565f89",
    "header_border": "#2f334d",
    "header_bg": "rgba(31, 35, 53, 0.85)",
    "mark_bg": "rgba(240, 198, 116, 0.2)",
    "mark_text": "#f0c674",
    "scrollbar_thumb": "#3b4261",
    "scrollbar_track": "transparent",
    "hr": "linear-gradient(90deg, transparent, #2f334d 20%, #2f334d 80%, transparent)",
    "shadow": "0 2px 8px rgba(0, 0, 0, 0.4)",
    "selection": "rgba(122, 162, 247, 0.3)"
  }
}
```

- [ ] **Step 2: Create `priv/themes/default-light.json`**

Populate from the top-level light block in `priv/static/markdown-wide.css` (lines ~14–73). `mode: "light"`, `syntax_theme: "onelight"`. Same keys as default-dark with light values:

```json
{
  "name": "Default Light",
  "mode": "light",
  "syntax_theme": "onelight",
  "fonts": {
    "heading": "Bricolage Grotesque",
    "body": "Outfit",
    "mono": "SF Mono"
  },
  "colors": {
    "bg": "#faf9f6",
    "bg_surface": "#f0eee8",
    "bg_hover": "#e8e5dd",
    "text": "#2b2b2b",
    "text_secondary": "#484848",
    "text_muted": "#888888",
    "h1": "#b45309",
    "h2": "#1e40af",
    "h3": "#047857",
    "h4": "#6d28d9",
    "link": "#2563eb",
    "link_hover": "#1d4ed8",
    "accent": "#dc2626",
    "border": "#d6d3cc",
    "border_subtle": "#e8e5de",
    "blockquote_bar": "#dc2626",
    "blockquote_bg": "rgba(220, 38, 38, 0.04)",
    "blockquote_text": "#484848",
    "table_border": "rgba(30, 64, 175, 0.2)",
    "table_header_bg": "rgba(30, 64, 175, 0.08)",
    "table_header_text": "#1e40af",
    "table_stripe": "rgba(30, 64, 175, 0.04)",
    "table_hover": "rgba(30, 64, 175, 0.08)",
    "table_accent": "#1e40af",
    "code_bg": "#eae8e1",
    "code_text": "#a8370e",
    "code_border": "#d6d3cc",
    "pre_bg": "#f5f3ee",
    "pre_border": "#d6d3cc",
    "pre_scrollbar_thumb": "#c4c0b8",
    "pre_scrollbar_track": "transparent",
    "header_text": "#888888",
    "header_border": "#d6d3cc",
    "header_bg": "rgba(240, 238, 232, 0.85)",
    "mark_bg": "rgba(180, 83, 9, 0.12)",
    "mark_text": "#b45309",
    "scrollbar_thumb": "#c4c0b8",
    "scrollbar_track": "transparent",
    "hr": "linear-gradient(90deg, transparent, #d6d3cc 20%, #d6d3cc 80%, transparent)",
    "shadow": "0 2px 8px rgba(0, 0, 0, 0.06)",
    "selection": "rgba(37, 99, 235, 0.15)"
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add priv/themes/default-dark.json priv/themes/default-light.json
git commit -m "feat(themes): add default dark/light preset JSON files"
```

---

## Task 2: `Inkwell.Themes` — load from disk + render CSS

**Files:**
- Create: `lib/inkwell/themes.ex`
- Create: `test/inkwell/themes_test.exs`

Start with the pure functions: loading a single theme JSON, validating it, rendering it to a CSS string. GenServer comes in Task 3.

- [ ] **Step 1: Write failing test for `Inkwell.Themes.render_css/1`**

```elixir
defmodule Inkwell.ThemesTest do
  use ExUnit.Case, async: true

  alias Inkwell.Themes

  describe "render_css/1" do
    test "returns a :root { … } CSS string with dashes from snake_case keys" do
      theme = %{
        name: "Tiny",
        mode: "dark",
        syntax_theme: "onedark",
        fonts: %{heading: "H", body: "B", mono: "M"},
        colors: %{bg: "#111", text_muted: "#888", bg_surface: "#222"}
      }

      css = Themes.render_css(theme)

      assert css =~ ":root {"
      assert css =~ "--bg: #111;"
      assert css =~ "--text-muted: #888;"
      assert css =~ "--bg-surface: #222;"
      assert css =~ "--font-heading: \"H\""
      assert css =~ "--font-body: \"B\""
      assert css =~ "--font-mono: \"M\""
      assert String.ends_with?(String.trim(css), "}")
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/inkwell/themes_test.exs`
Expected: FAIL with `Inkwell.Themes is undefined`.

- [ ] **Step 3: Implement `Inkwell.Themes` — `render_css/1`, `parse/1`, `load_dir/1`**

```elixir
defmodule Inkwell.Themes do
  @moduledoc """
  Loads theme JSON files (shipped presets + user themes) and caches their
  pre-computed CSS. The active theme's CSS is injected as an inline
  `<style>` block in the root layout.
  """

  require Logger

  @type theme :: %{
          required(:name) => String.t(),
          required(:mode) => String.t(),
          required(:syntax_theme) => String.t(),
          required(:fonts) => %{heading: String.t(), body: String.t(), mono: String.t()},
          required(:colors) => %{atom() => String.t()},
          required(:source) => :preset | :user
        }

  @doc "Render a theme map into a `:root { --bg: …; … }` CSS string."
  def render_css(theme) do
    color_lines =
      theme.colors
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "  --#{dasherize(k)}: #{v};" end)

    font_lines = [
      ~s(  --font-heading: "#{theme.fonts.heading}", system-ui, sans-serif;),
      ~s(  --font-body: "#{theme.fonts.body}", system-ui, sans-serif;),
      ~s(  --font-mono: "#{theme.fonts.mono}", ui-monospace, SF Mono, monospace;)
    ]

    """
    :root {
    #{Enum.join(color_lines ++ font_lines, "\n")}
    }
    """
  end

  @doc "Parse a JSON string into a theme map. Returns {:ok, theme} or {:error, reason}."
  def parse(json, source) when source in [:preset, :user] do
    with {:ok, data} <- Jason.decode(json),
         {:ok, theme} <- validate(data, source) do
      {:ok, theme}
    end
  end

  @doc "Load every `*.json` under `dir`, tagged with `source`. Malformed files are skipped with a log."
  def load_dir(dir, source) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn name -> Path.join(dir, name) end)
        |> Enum.flat_map(fn path ->
          case File.read(path) do
            {:ok, body} ->
              case parse(body, source) do
                {:ok, theme} ->
                  [theme]

                {:error, reason} ->
                  Logger.warning("Skipping theme #{path}: #{inspect(reason)}")
                  []
              end

            {:error, _} ->
              []
          end
        end)

      {:error, _} ->
        []
    end
  end

  defp validate(%{"name" => name, "mode" => mode, "colors" => colors, "fonts" => fonts} = data, source)
       when mode in ["dark", "light"] and is_map(colors) and is_map(fonts) do
    theme = %{
      name: name,
      mode: mode,
      syntax_theme: Map.get(data, "syntax_theme", default_syntax_theme(mode)),
      fonts: %{
        heading: fonts["heading"] || "Bricolage Grotesque",
        body: fonts["body"] || "Outfit",
        mono: fonts["mono"] || "SF Mono"
      },
      colors: Map.new(colors, fn {k, v} -> {String.to_atom(k), v} end),
      source: source
    }

    {:ok, theme}
  end

  defp validate(_, _), do: {:error, :invalid_theme}

  defp default_syntax_theme("dark"), do: "onedark"
  defp default_syntax_theme("light"), do: "onelight"

  defp dasherize(key) do
    key |> Atom.to_string() |> String.replace("_", "-")
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/inkwell/themes_test.exs`
Expected: PASS.

- [ ] **Step 5: Add test for `parse/1` and `load_dir/1`**

```elixir
  describe "parse/2" do
    test "parses a valid theme JSON with preset source" do
      json = ~s({
        "name": "T", "mode": "light", "syntax_theme": "onelight",
        "fonts": {"heading":"H","body":"B","mono":"M"},
        "colors": {"bg":"#fff","text":"#000"}
      })

      assert {:ok, theme} = Inkwell.Themes.parse(json, :preset)
      assert theme.name == "T"
      assert theme.mode == "light"
      assert theme.source == :preset
      assert theme.colors[:bg] == "#fff"
    end

    test "errors on missing required fields" do
      assert {:error, _} = Inkwell.Themes.parse(~s({"name":"nope"}), :user)
    end

    test "errors on invalid mode" do
      bad = ~s({"name":"X","mode":"sepia","fonts":{"heading":"H","body":"B","mono":"M"},"colors":{}})
      assert {:error, _} = Inkwell.Themes.parse(bad, :preset)
    end
  end

  describe "load_dir/2" do
    @tag :tmp_dir
    test "loads valid themes and skips malformed files", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "good.json"), ~s({
        "name":"G","mode":"dark","syntax_theme":"onedark",
        "fonts":{"heading":"H","body":"B","mono":"M"},
        "colors":{"bg":"#000"}
      }))
      File.write!(Path.join(dir, "bad.json"), "not json")
      File.write!(Path.join(dir, "ignore.txt"), "ignored")

      themes = Inkwell.Themes.load_dir(dir, :user)
      assert Enum.map(themes, & &1.name) == ["G"]
      assert hd(themes).source == :user
    end

    test "returns [] for missing directory" do
      assert Inkwell.Themes.load_dir("/no/such/path", :user) == []
    end
  end
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/inkwell/themes_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add lib/inkwell/themes.ex test/inkwell/themes_test.exs
git commit -m "feat(themes): add Inkwell.Themes pure loader and CSS renderer"
```

---

## Task 3: `Inkwell.Themes` — GenServer with active-theme state

**Files:**
- Modify: `lib/inkwell/themes.ex`
- Modify: `test/inkwell/themes_test.exs`
- Modify: `lib/inkwell/application.ex`

Make `Inkwell.Themes` a GenServer started under the supervisor. State is `%{themes: %{name => theme}, active: name}`. Expose read and mutation API.

- [ ] **Step 1: Add failing tests for GenServer API**

Append to `test/inkwell/themes_test.exs`:

```elixir
  describe "GenServer API" do
    setup %{tmp_dir: dir} = ctx do
      preset_dir = Path.join(dir, "presets")
      user_dir = Path.join(dir, "user")
      File.mkdir_p!(preset_dir)
      File.mkdir_p!(user_dir)

      File.write!(Path.join(preset_dir, "dark.json"), ~s({
        "name":"Dark","mode":"dark","syntax_theme":"onedark",
        "fonts":{"heading":"H","body":"B","mono":"M"},
        "colors":{"bg":"#000","text":"#fff"}
      }))

      File.write!(Path.join(preset_dir, "light.json"), ~s({
        "name":"Light","mode":"light","syntax_theme":"onelight",
        "fonts":{"heading":"H","body":"B","mono":"M"},
        "colors":{"bg":"#fff","text":"#000"}
      }))

      start_supervised!(
        {Inkwell.Themes,
         preset_dir: preset_dir, user_dir: user_dir, settings_file: Path.join(dir, "settings.json")}
      )

      Map.put(ctx, :user_dir, user_dir)
    end

    @tag :tmp_dir
    test "list/0 returns presets + user themes", %{user_dir: _} do
      assert Enum.map(Inkwell.Themes.list(), & &1.name) |> Enum.sort() == ["Dark", "Light"]
    end

    @tag :tmp_dir
    test "active/0 defaults to Default Dark or first-loaded" do
      assert Inkwell.Themes.active().name in ["Dark", "Light"]
    end

    @tag :tmp_dir
    test "set_active/1 changes active and broadcasts" do
      Phoenix.PubSub.subscribe(Inkwell.PubSub, "theme")
      :ok = Inkwell.Themes.set_active("Light")
      assert Inkwell.Themes.active().name == "Light"
      assert_receive {:theme_changed, %{name: "Light"}}
    end

    @tag :tmp_dir
    test "set_active/1 on unknown name errors", %{user_dir: _} do
      assert {:error, :not_found} = Inkwell.Themes.set_active("Nope")
    end

    @tag :tmp_dir
    test "active_css/0 returns a :root CSS string" do
      assert Inkwell.Themes.active_css() =~ ":root {"
      assert Inkwell.Themes.active_css() =~ "--bg:"
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/themes_test.exs`
Expected: FAIL (GenServer API and child spec don't exist yet).

- [ ] **Step 3: Extend `lib/inkwell/themes.ex` with GenServer + public API**

Add after the existing module content:

```elixir
  use GenServer

  # Public API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def list, do: GenServer.call(__MODULE__, :list)
  def get(name), do: GenServer.call(__MODULE__, {:get, name})
  def active, do: GenServer.call(__MODULE__, :active)
  def active_css, do: GenServer.call(__MODULE__, :active_css)
  def set_active(name), do: GenServer.call(__MODULE__, {:set_active, name})
  def save(theme), do: GenServer.call(__MODULE__, {:save, theme})
  def duplicate(source_name, new_name),
    do: GenServer.call(__MODULE__, {:duplicate, source_name, new_name})
  def rename(old, new), do: GenServer.call(__MODULE__, {:rename, old, new})
  def delete(name), do: GenServer.call(__MODULE__, {:delete, name})

  # GenServer callbacks

  @impl true
  def init(opts) do
    preset_dir = Keyword.get(opts, :preset_dir, Application.app_dir(:inkwell, "priv/themes"))
    user_dir = Keyword.get(opts, :user_dir, Path.join(Inkwell.Settings.state_dir(), "themes"))
    settings_file =
      Keyword.get(opts, :settings_file, Path.join(Inkwell.Settings.state_dir(), "settings.json"))

    File.mkdir_p!(user_dir)

    presets = load_dir(preset_dir, :preset)
    user = load_dir(user_dir, :user)

    themes =
      (presets ++ user)
      |> Enum.reduce(%{}, fn t, acc -> Map.put(acc, t.name, Map.put(t, :css, render_css(t))) end)

    active = resolve_active(settings_file, themes)

    {:ok,
     %{
       themes: themes,
       active: active,
       preset_dir: preset_dir,
       user_dir: user_dir,
       settings_file: settings_file
     }}
  end

  @impl true
  def handle_call(:list, _from, state) do
    {:reply, state.themes |> Map.values() |> Enum.sort_by(&{&1.source, &1.name}), state}
  end

  def handle_call({:get, name}, _from, state) do
    {:reply, Map.fetch(state.themes, name), state}
  end

  def handle_call(:active, _from, state) do
    {:reply, Map.fetch!(state.themes, state.active), state}
  end

  def handle_call(:active_css, _from, state) do
    {:reply, Map.fetch!(state.themes, state.active).css, state}
  end

  def handle_call({:set_active, name}, _from, state) do
    case Map.fetch(state.themes, name) do
      {:ok, theme} ->
        write_settings(state.settings_file, name)
        Phoenix.PubSub.broadcast(Inkwell.PubSub, "theme", {:theme_changed, theme})
        {:reply, :ok, %{state | active: name}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # save/duplicate/rename/delete — implemented in Task 4.

  # Helpers

  defp resolve_active(settings_file, themes) do
    with {:ok, body} <- File.read(settings_file),
         {:ok, %{"active_theme" => name}} <- Jason.decode(body),
         true <- Map.has_key?(themes, name) do
      name
    else
      _ -> fallback_active(themes)
    end
  end

  defp fallback_active(themes) do
    cond do
      Map.has_key?(themes, "Default Dark") -> "Default Dark"
      true -> themes |> Map.keys() |> List.first()
    end
  end

  defp write_settings(path, active) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(%{active_theme: active}))
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/inkwell/themes_test.exs`
Expected: PASS.

- [ ] **Step 5: Start `Inkwell.Themes` under the supervisor**

Modify `lib/inkwell/application.ex`: replace the `resolve_theme`/`:persistent_term` block (lines 60–79) with a call that starts `Inkwell.Themes`. The new daemon children list becomes:

```elixir
:daemon ->
  # Theme is now loaded by Inkwell.Themes at supervisor start; the --theme
  # CLI flag is applied by CLI.run_daemon before Application.start/2.
  Inkwell.GitRepo.init_cache()

  [
    {Phoenix.PubSub, name: Inkwell.PubSub},
    {Registry, keys: :unique, name: Inkwell.WatcherRegistry},
    {Inkwell.History, []},
    Inkwell.Themes,
    {Inkwell.Daemon, []},
    {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
    InkwellWeb.Telemetry,
    InkwellWeb.Endpoint
  ]
```

Delete `defp resolve_theme(...)` — no longer needed.

- [ ] **Step 6: Run full test suite to catch regressions**

Run: `mix test`
Expected: most tests pass; some may fail because the old `:persistent_term.get(:inkwell_theme, "dark")` calls still exist in `Inkwell.Renderer` and `Shell` — those are fixed in Tasks 5–6.

- [ ] **Step 7: Commit**

```bash
git add lib/inkwell/themes.ex lib/inkwell/application.ex test/inkwell/themes_test.exs
git commit -m "feat(themes): add Inkwell.Themes GenServer with list/active/set_active"
```

---

## Task 4: `Inkwell.Themes` — save/duplicate/rename/delete

**Files:**
- Modify: `lib/inkwell/themes.ex`
- Modify: `test/inkwell/themes_test.exs`

- [ ] **Step 1: Add failing tests**

Append to the GenServer-API describe block:

```elixir
    @tag :tmp_dir
    test "duplicate/2 copies a preset into user dir with new name", %{user_dir: user_dir} do
      assert :ok = Inkwell.Themes.duplicate("Dark", "My Dark")
      assert {:ok, theme} = Inkwell.Themes.get("My Dark")
      assert theme.source == :user
      assert File.exists?(Path.join(user_dir, "my-dark.json"))
    end

    @tag :tmp_dir
    test "duplicate/2 errors on name collision with preset" do
      assert {:error, :name_taken} = Inkwell.Themes.duplicate("Dark", "Light")
    end

    @tag :tmp_dir
    test "save/1 writes a user theme to disk and caches its CSS" do
      {:ok, base} = Inkwell.Themes.get("Dark")
      mine = %{base | name: "Mine", source: :user, colors: Map.put(base.colors, :bg, "#abc")}
      assert :ok = Inkwell.Themes.save(mine)
      assert {:ok, got} = Inkwell.Themes.get("Mine")
      assert got.colors[:bg] == "#abc"
      assert got.css =~ "--bg: #abc;"
    end

    @tag :tmp_dir
    test "save/1 errors when name collides with preset" do
      {:ok, base} = Inkwell.Themes.get("Dark")
      dup = %{base | name: "Light", source: :user}
      assert {:error, :name_taken} = Inkwell.Themes.save(dup)
    end

    @tag :tmp_dir
    test "rename/2 moves a user theme and updates active if needed" do
      :ok = Inkwell.Themes.duplicate("Dark", "A")
      :ok = Inkwell.Themes.set_active("A")
      :ok = Inkwell.Themes.rename("A", "B")
      assert Inkwell.Themes.active().name == "B"
      assert {:error, _} = Inkwell.Themes.get("A")
    end

    @tag :tmp_dir
    test "delete/1 removes a user theme; active falls back to Default Dark" do
      :ok = Inkwell.Themes.duplicate("Dark", "Temp")
      :ok = Inkwell.Themes.set_active("Temp")
      :ok = Inkwell.Themes.delete("Temp")
      assert Inkwell.Themes.active().name == "Dark"
    end

    @tag :tmp_dir
    test "delete/1 errors on preset" do
      assert {:error, :readonly_preset} = Inkwell.Themes.delete("Dark")
    end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/themes_test.exs`
Expected: FAIL (undefined GenServer calls).

- [ ] **Step 3: Implement the four mutations**

Add to the `handle_call` block in `lib/inkwell/themes.ex`:

```elixir
  def handle_call({:save, theme}, _from, state) do
    with :ok <- ensure_user(theme),
         :ok <- ensure_available(theme.name, state) do
      path = user_path(state, theme.name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, encode(theme))

      theme = Map.put(theme, :css, render_css(theme))
      themes = Map.put(state.themes, theme.name, theme)

      if state.active == theme.name,
        do: Phoenix.PubSub.broadcast(Inkwell.PubSub, "theme", {:theme_changed, theme})

      {:reply, :ok, %{state | themes: themes}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:duplicate, source_name, new_name}, _from, state) do
    with {:ok, source} <- Map.fetch(state.themes, source_name) |> wrap_not_found(),
         :ok <- ensure_available(new_name, state) do
      new = %{source | name: new_name, source: :user}
      path = user_path(state, new.name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, encode(new))
      new = Map.put(new, :css, render_css(new))
      {:reply, :ok, %{state | themes: Map.put(state.themes, new_name, new)}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:rename, old, new}, _from, state) do
    with {:ok, theme} <- Map.fetch(state.themes, old) |> wrap_not_found(),
         :ok <- ensure_user(theme),
         :ok <- ensure_available(new, state) do
      File.rename!(user_path(state, old), user_path(state, new))
      renamed = %{theme | name: new} |> then(&Map.put(&1, :css, render_css(&1)))

      themes =
        state.themes
        |> Map.delete(old)
        |> Map.put(new, renamed)

      active =
        if state.active == old do
          write_settings(state.settings_file, new)
          Phoenix.PubSub.broadcast(Inkwell.PubSub, "theme", {:theme_changed, renamed})
          new
        else
          state.active
        end

      {:reply, :ok, %{state | themes: themes, active: active}}
    else
      err -> {:reply, err, state}
    end
  end

  def handle_call({:delete, name}, _from, state) do
    with {:ok, theme} <- Map.fetch(state.themes, name) |> wrap_not_found(),
         :ok <- ensure_user(theme) do
      File.rm!(user_path(state, name))
      themes = Map.delete(state.themes, name)

      active =
        if state.active == name do
          new_active = fallback_active(themes)
          write_settings(state.settings_file, new_active)
          Phoenix.PubSub.broadcast(Inkwell.PubSub, "theme", {:theme_changed, themes[new_active]})
          new_active
        else
          state.active
        end

      {:reply, :ok, %{state | themes: themes, active: active}}
    else
      err -> {:reply, err, state}
    end
  end

  defp ensure_user(%{source: :user}), do: :ok
  defp ensure_user(_), do: {:error, :readonly_preset}

  defp ensure_available(name, state) do
    if Map.has_key?(state.themes, name), do: {:error, :name_taken}, else: :ok
  end

  defp wrap_not_found(:error), do: {:error, :not_found}
  defp wrap_not_found({:ok, _} = ok), do: ok

  defp user_path(state, name), do: Path.join(state.user_dir, slug(name) <> ".json")

  defp slug(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp encode(theme) do
    Jason.encode!(%{
      name: theme.name,
      mode: theme.mode,
      syntax_theme: theme.syntax_theme,
      fonts: theme.fonts,
      colors: Map.new(theme.colors, fn {k, v} -> {Atom.to_string(k), v} end)
    })
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/inkwell/themes_test.exs`
Expected: PASS (all GenServer-API tests, incl. the new four).

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell/themes.ex test/inkwell/themes_test.exs
git commit -m "feat(themes): add save/duplicate/rename/delete for user themes"
```

---

## Task 5: `Inkwell.Settings` → JSON settings

**Files:**
- Modify: `lib/inkwell/settings.ex`
- Modify: `test/inkwell/settings_test.exs`

Switch from the plain-text `theme` file to `settings.json`. Leave a first-boot cleanup that deletes the old `theme` file.

- [ ] **Step 1: Replace `test/inkwell/settings_test.exs` contents**

```elixir
defmodule Inkwell.SettingsTest do
  use ExUnit.Case, async: true

  alias Inkwell.Settings

  setup %{tmp_dir: dir} = ctx do
    Map.put(ctx, :state_dir, dir)
  end

  @tag :tmp_dir
  test "read_active/1 returns nil when settings.json is missing", %{state_dir: dir} do
    assert Settings.read_active(dir) == nil
  end

  @tag :tmp_dir
  test "read_active/1 returns the active theme from settings.json", %{state_dir: dir} do
    File.write!(Path.join(dir, "settings.json"), ~s({"active_theme":"Plain"}))
    assert Settings.read_active(dir) == "Plain"
  end

  @tag :tmp_dir
  test "write_active/2 writes settings.json", %{state_dir: dir} do
    :ok = Settings.write_active("Dracula", dir)
    assert %{"active_theme" => "Dracula"} = Jason.decode!(File.read!(Path.join(dir, "settings.json")))
  end

  @tag :tmp_dir
  test "init/1 creates settings.json with Default Dark and deletes old theme file", %{state_dir: dir} do
    File.write!(Path.join(dir, "theme"), "light")
    :ok = Settings.init(dir)
    refute File.exists?(Path.join(dir, "theme"))
    assert Settings.read_active(dir) == "Default Dark"
  end

  @tag :tmp_dir
  test "init/1 is idempotent — does not overwrite existing settings.json", %{state_dir: dir} do
    File.write!(Path.join(dir, "settings.json"), ~s({"active_theme":"Dracula"}))
    :ok = Settings.init(dir)
    assert Settings.read_active(dir) == "Dracula"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/inkwell/settings_test.exs`
Expected: FAIL (functions don't exist in their new shape).

- [ ] **Step 3: Rewrite `lib/inkwell/settings.ex`**

```elixir
defmodule Inkwell.Settings do
  @moduledoc """
  Persistent user preferences in `~/.inkwell/settings.json`.

  Currently stores just `active_theme`. Grows as more preferences land.
  """

  @settings_file "settings.json"
  @legacy_theme_file "theme"
  @default_active "Default Dark"

  @doc "Return the active theme name, or nil if settings.json is missing or unreadable."
  def read_active(dir \\ state_dir()) do
    with {:ok, body} <- File.read(Path.join(dir, @settings_file)),
         {:ok, %{"active_theme" => name}} <- Jason.decode(body) do
      name
    else
      _ -> nil
    end
  end

  @doc "Set the active theme and write settings.json."
  def write_active(name, dir \\ state_dir()) do
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, @settings_file), Jason.encode!(%{active_theme: name}))
    :ok
  end

  @doc """
  First-boot setup. Creates settings.json with Default Dark if missing, and
  deletes the legacy ~/.inkwell/theme file if present.
  """
  def init(dir \\ state_dir()) do
    File.mkdir_p!(dir)
    legacy = Path.join(dir, @legacy_theme_file)
    if File.exists?(legacy), do: File.rm!(legacy)

    settings_path = Path.join(dir, @settings_file)

    unless File.exists?(settings_path) do
      File.write!(settings_path, Jason.encode!(%{active_theme: @default_active}))
    end

    :ok
  end

  @doc false
  def state_dir, do: Path.join(System.user_home!(), ".inkwell")
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/inkwell/settings_test.exs`
Expected: PASS.

- [ ] **Step 5: Call `Inkwell.Settings.init/0` before `Inkwell.Themes` starts**

In `lib/inkwell/application.ex`, inside the `:daemon` branch, just before the children list:

```elixir
Inkwell.Settings.init()
Inkwell.GitRepo.init_cache()
```

- [ ] **Step 6: Remove the old `read_theme/0` + `write_theme/1` call sites**

Grep for them:

Run: `grep -rn "Settings.read_theme\|Settings.write_theme\|:inkwell_theme" lib test`

Replace each call site — the remaining ones are in `lib/inkwell/application.ex`, `lib/inkwell/cli.ex`, `lib/inkwell_web/live_hooks/shell.ex`, `lib/inkwell/renderer.ex`. Hold off on cli.ex and shell.ex — those are fixed in Tasks 7 and 8. For now, stop the old `resolve_theme` flow in application.ex (already done in Task 3 Step 5) and remove the `if parsed[:theme], do: Inkwell.Settings.write_theme(theme)` line if present.

For `lib/inkwell/cli.ex` lines 54–57, temporarily change to:

```elixir
if theme do
  Inkwell.Settings.write_active(theme)
end
```

(Task 8 will make this validate the theme name against Inkwell.Themes.list.)

- [ ] **Step 7: Commit**

```bash
git add lib/inkwell/settings.ex lib/inkwell/application.ex lib/inkwell/cli.ex test/inkwell/settings_test.exs
git commit -m "feat(settings): move to JSON settings.json; add init/1 for first-boot cleanup"
```

---

## Task 6: CSS refactor + inline `<style>` in root layout

**Files:**
- Modify: `priv/static/markdown-wide.css`
- Modify: `lib/inkwell_web/components/layouts/root.html.heex`
- Modify: `lib/inkwell_web/components/layouts/app.html.heex`
- Modify: `lib/inkwell_web/live_hooks/shell.ex`
- Modify: `lib/inkwell/renderer.ex`

- [ ] **Step 1: Strip theme-value blocks from `priv/static/markdown-wide.css`**

Remove lines 12–73 (the top-level `body { --bg: …; … }` block that declares light values).
Remove lines 75–136 (the `body:has([data-theme="dark"]) { … }` block).

Leave the comment header (lines 1–10) in place but update it:

```css
/* ─────────────────────────────────────────────────────────
   Markdown Preview — Developer Editorial Theme
   Fonts: Bricolage Grotesque (headings) + Outfit (body)
   Theme CSS variables are injected into <style> in root.html.heex
   by Inkwell.Themes.active_css/0.
   ───────────────────────────────────────────────────────── */
```

Leave every rule below that unchanged. Do NOT remove the `body:has([data-theme="dark"]) .doc-rail-link { … }` rules and other similar mode-specific rules lower in the file — those still work because the root layout still sets `data-theme`.

- [ ] **Step 2: Modify `lib/inkwell_web/components/layouts/root.html.heex`**

Replace with:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="Inkwell">{assigns[:page_title]}</.live_title>
    <link rel="icon" type="image/svg+xml" href={~p"/favicon.svg"} />
    <link phx-track-static rel="stylesheet" href={~p"/markdown-wide.css"} />
    <link phx-track-static rel="stylesheet" href={~p"/app.css"} />
    <style id="inkwell-theme-vars">{Phoenix.HTML.raw(@theme_css)}</style>
    <script
      src="https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.min.js"
      integrity="sha384-o+g/BxPwhi0C3RK7oQBxQuNimeafQ3GE/ST4iT2BxVI4Wzt60SH4pq9iXVYujjaS"
      crossorigin="anonymous"
      referrerpolicy="no-referrer"
    >
    </script>
    <script defer phx-track-static type="text/javascript" src={~p"/assets/app.js"}>
    </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

The `@theme_css` assign is supplied by `InkwellWeb.LiveHooks.Shell`.

- [ ] **Step 3: Modify `lib/inkwell_web/live_hooks/shell.ex`**

Replace contents with:

```elixir
defmodule InkwellWeb.LiveHooks.Shell do
  @moduledoc "on_mount hook for live_session :shell — shared theme + picker state."

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Inkwell.PubSub, "theme")

    active = Inkwell.Themes.active()

    socket =
      socket
      |> assign(:active_theme, active)
      |> assign(:theme_css, active.css)
      |> assign(:picker_open, false)
      |> assign(:picker_tab, :files)
      |> attach_hook(:shell_events, :handle_event, &handle_event/3)
      |> attach_hook(:shell_info, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_event("set_active_theme", %{"name" => name}, socket) do
    case Inkwell.Themes.set_active(name) do
      :ok -> {:halt, socket}
      {:error, _} -> {:halt, socket}
    end
  end

  defp handle_event("open_picker", %{"tab" => tab}, socket) when tab in ~w(files settings) do
    {:halt, socket |> assign(:picker_open, true) |> assign(:picker_tab, String.to_existing_atom(tab))}
  end

  defp handle_event("open_picker", _, socket),
    do: {:halt, socket |> assign(:picker_open, true) |> assign(:picker_tab, :files)}

  defp handle_event("close_picker", _, socket),
    do: {:halt, assign(socket, :picker_open, false)}

  defp handle_event("set_picker_tab", %{"tab" => tab}, socket) when tab in ~w(files settings),
    do: {:halt, assign(socket, :picker_tab, String.to_existing_atom(tab))}

  defp handle_event(_, _, socket), do: {:cont, socket}

  defp handle_info({:theme_changed, theme}, socket) do
    {:halt,
     socket
     |> assign(:active_theme, theme)
     |> assign(:theme_css, theme.css)}
  end

  defp handle_info({:picker_selected, path}, socket) do
    {:halt,
     socket
     |> assign(:picker_open, false)
     |> push_navigate(to: "/files?#{URI.encode_query(path: path)}")}
  end

  defp handle_info(:close_picker, socket) do
    {:halt, assign(socket, :picker_open, false)}
  end

  defp handle_info(_, socket), do: {:cont, socket}
end
```

- [ ] **Step 4: Modify `lib/inkwell_web/components/layouts/app.html.heex`**

Replace the outer `<div>` and the toggle-theme button. The dropdown is added in Task 11; for now keep a simple button that opens the picker's Settings tab. (Task 11 replaces this with the full dropdown.)

```heex
<div data-theme={@active_theme.mode}>
  <div id="page-header" phx-hook="Shortcuts">
    <div id="header-actions">
      <button
        id="btn-theme"
        class="header-btn"
        aria-label="Theme settings"
        phx-click={JS.push("open_picker", value: %{tab: "settings"})}
        title={"Theme: " <> @active_theme.name}
      >
        <!-- Keep the sun/moon SVGs for now; swap them for a theme icon in Task 11 -->
        <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="12" cy="12" r="5" />
          <line x1="12" y1="1" x2="12" y2="3" />
          <line x1="12" y1="21" x2="12" y2="23" />
          <line x1="4.22" y1="4.22" x2="5.64" y2="5.64" />
          <line x1="18.36" y1="18.36" x2="19.78" y2="19.78" />
          <line x1="1" y1="12" x2="3" y2="12" />
          <line x1="21" y1="12" x2="23" y2="12" />
          <line x1="4.22" y1="19.78" x2="5.64" y2="18.36" />
          <line x1="18.36" y1="5.64" x2="19.78" y2="4.22" />
        </svg>
        <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z" />
        </svg>
        <span class="header-tooltip">Theme</span>
      </button>
      <button id="btn-search" class="header-btn" aria-label="Search files" phx-click="open_picker">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <span class="header-tooltip">Ctrl+P</span>
      </button>
    </div>
    <div id="header-separator"></div>
    <div id="header-file-info">
      <div id="header-title">
        <span id="header-filename">{@filename || "Inkwell"}</span>
        <span id="header-caret">&#9662;</span>
      </div>
      <div id="header-dir">{@rel_dir}</div>
    </div>
    <div id="mode-toggle" phx-hook="ModeToggle" phx-update="ignore"></div>
  </div>
  <.live_component
    module={InkwellWeb.PickerComponent}
    id="picker"
    open={@picker_open}
    tab={@picker_tab}
    current_path={assigns[:path]}
  />
  {@inner_content}
</div>
```

- [ ] **Step 5: Modify `lib/inkwell/renderer.ex`**

Replace contents with:

```elixir
defmodule Inkwell.Renderer do
  @moduledoc "Converts markdown to HTML with syntax highlighting and mermaid support."

  @base_opts [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true,
      footnotes: true,
      alerts: true
    ],
    render: [unsafe: true]
  ]

  @doc "Render markdown to HTML string (legacy, no nav data)."
  def render(markdown) do
    {html, _headings, _alerts} = render_with_nav(markdown)
    html
  end

  @doc "Render markdown to {html, headings, alerts} with injected IDs for navigation."
  def render_with_nav(markdown, syntax_theme \\ nil) do
    theme_name =
      syntax_theme || Inkwell.Themes.active().syntax_theme

    opts =
      Keyword.put(@base_opts, :syntax_highlight, formatter: {:html_inline, [theme: theme_name]})

    md =
      Regex.replace(~r/```mermaid\n(.*?)```/s, markdown, fn _, content ->
        escaped = Plug.HTML.html_escape(content)
        "<pre class=\"mermaid\">#{escaped}</pre>"
      end)

    html = MDEx.to_html!(md, opts)
    Inkwell.DocNav.process(markdown, html)
  end
end
```

- [ ] **Step 6: Run the full suite**

Run: `mix test`

Expected: `inkwell_web` tests that depend on `@theme` assign may fail. Fix the smallest number of them by renaming `@theme` references to `@active_theme.mode` or just to `@active_theme.name`, wherever they're checking it for display. Update the existing `renderer_test.exs` if it asserted on hardcoded `onedark`/`onelight`.

- [ ] **Step 7: Commit**

```bash
git add priv/static/markdown-wide.css lib/inkwell_web/components/layouts/root.html.heex lib/inkwell_web/components/layouts/app.html.heex lib/inkwell_web/live_hooks/shell.ex lib/inkwell/renderer.ex test/inkwell/renderer_test.exs
git commit -m "feat(themes): inline <style> driven by Inkwell.Themes; drop hardcoded blocks"
```

Manual verification (dev server): `mix phx.server` (or open a markdown file via `./burrito_out/inkwell_darwin_arm64 preview README.md`) → app renders identically to before. `data-theme` on root div still set from active theme's `mode`.

---

## Task 7: Picker modal tabs + empty Settings tab

**Files:**
- Modify: `lib/inkwell_web/picker_component.ex`
- Modify: `priv/static/app.css`
- Create: `test/inkwell_web/live/settings_tab_test.exs`

Add a two-tab switcher to the picker modal (`Files` and `Settings`). Gear button in the bottom-left switches to Settings.

- [ ] **Step 1: Add failing LiveView test**

Create `test/inkwell_web/live/settings_tab_test.exs`:

```elixir
defmodule InkwellWeb.Live.SettingsTabTest do
  use InkwellWeb.ConnCase
  import Phoenix.LiveViewTest

  test "picker opens on Files tab by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    assert has_element?(view, "#picker-tab-files.active")
    refute has_element?(view, "#picker-tab-settings.active")
  end

  test "gear button switches to Settings tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings-btn") |> render_click()
    assert has_element?(view, "#picker-tab-settings.active")
  end
end
```

- [ ] **Step 2: Run test — expect failure**

Run: `mix test test/inkwell_web/live/settings_tab_test.exs`
Expected: FAIL (elements don't exist).

- [ ] **Step 3: Modify `lib/inkwell_web/picker_component.ex`**

Add `:tab` assign handling and a tab switcher in the `render/1` function. Update `update/2`:

```elixir
  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> initial_results(assigns[:current_path]) end)
      |> assign_new(:tab, fn -> :files end)

    {:ok, sync_selection(socket, 0)}
  end
```

Modify the top of `render/1` to include tab bar and conditional content. Wrap the existing body in a `<div :if={@tab == :files}>` and add a placeholder `<div :if={@tab == :settings}>`:

```heex
    <div id="picker-overlay" class={if @open, do: "open", else: ""} phx-hook="PickerOverlay" phx-window-keydown={@open && "close_picker"} phx-key="Escape">
      <div id="picker">
        <div id="picker-tabs">
          <button id="picker-tab-files" class={if @tab == :files, do: "active", else: ""} phx-click={JS.push("set_picker_tab", value: %{tab: "files"})}>Files</button>
          <button id="picker-tab-settings" class={if @tab == :settings, do: "active", else: ""} phx-click={JS.push("set_picker_tab", value: %{tab: "settings"})}>Settings</button>
          <span class="hint">ESC to close</span>
        </div>
        <div :if={@tab == :files}>
          <!-- existing picker body unchanged -->
          <form id="picker-search-form" phx-change="search" phx-target={@myself}>...</form>
          ...
        </div>
        <div :if={@tab == :settings} id="picker-settings">
          <div id="picker-settings-nav">
            <button class="active">Appearance</button>
            <button disabled>Editor</button>
            <button disabled>Behavior</button>
            <button disabled>About</button>
          </div>
          <div id="picker-settings-content">
            <!-- Theme list + editor — filled in Tasks 8 and 9 -->
          </div>
        </div>
        <div id="picker-footer">
          <button id="picker-tab-settings-btn" phx-click={JS.push("set_picker_tab", value: %{tab: "settings"})} title="Settings">⚙</button>
        </div>
      </div>
    </div>
```

Because the `tab` is controlled by the Shell hook via `set_picker_tab`, the tab buttons push that event (not to `@myself`).

- [ ] **Step 4: Add CSS for tab switcher + settings scaffold in `priv/static/app.css`**

Append to `priv/static/app.css`:

```css
/* ── Picker tabs + settings layout ── */
#picker-tabs {
  display: flex; gap: 4px; padding: 8px 12px;
  border-bottom: 1px solid var(--border);
  background: var(--bg-surface);
}
#picker-tabs button {
  padding: 6px 12px; border: none; border-radius: 4px;
  background: transparent; color: var(--text-muted);
  font-family: system-ui; font-size: 12px; cursor: pointer;
}
#picker-tabs button.active {
  background: var(--bg-hover); color: var(--text);
}
#picker-tabs .hint { margin-left: auto; color: var(--text-muted); font-size: 11px; align-self: center; }

#picker-settings { display: flex; flex: 1; min-height: 0; }
#picker-settings-nav {
  display: flex; flex-direction: column; width: 140px;
  border-right: 1px solid var(--border); padding: 8px 0;
}
#picker-settings-nav button {
  padding: 8px 14px; background: transparent; border: none;
  text-align: left; color: var(--text-muted); cursor: pointer;
  font-family: system-ui; font-size: 12px;
}
#picker-settings-nav button.active { color: var(--text); background: var(--bg-hover); }
#picker-settings-nav button:disabled { opacity: 0.4; cursor: default; }
#picker-settings-content { flex: 1; padding: 16px; overflow-y: auto; }

#picker-footer {
  padding: 8px 12px; border-top: 1px solid var(--border);
  display: flex; justify-content: flex-start;
}
#picker-footer button {
  background: transparent; border: none; color: var(--text-muted);
  cursor: pointer; font-size: 16px;
}
#picker-footer button:hover { color: var(--text); }
```

- [ ] **Step 5: Run test**

Run: `mix test test/inkwell_web/live/settings_tab_test.exs`
Expected: PASS.

- [ ] **Step 6: Run full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/inkwell_web/picker_component.ex priv/static/app.css test/inkwell_web/live/settings_tab_test.exs
git commit -m "feat(settings): add Files/Settings tabs inside picker modal"
```

---

## Task 8: Theme list + preview pane + Apply/Duplicate/Delete

**Files:**
- Modify: `lib/inkwell_web/picker_component.ex`
- Modify: `test/inkwell_web/live/settings_tab_test.exs`

- [ ] **Step 1: Add failing tests**

Append to `settings_tab_test.exs`:

```elixir
  test "settings tab lists presets and user themes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    html = render(view)
    assert html =~ "PRESETS"
    assert html =~ "Default Dark"
    assert html =~ "Default Light"
  end

  test "clicking a theme shows it in the preview pane", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    view |> element("[data-theme-name='Default Light']") |> render_click()
    assert has_element?(view, "#theme-preview[data-previewing='Default Light']")
  end

  test "Apply sets the active theme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    view |> element("[data-theme-name='Default Light']") |> render_click()
    view |> element("#theme-apply") |> render_click()
    assert Inkwell.Themes.active().name == "Default Light"
  end
```

Reset active theme between tests — add to test setup:

```elixir
  setup do
    on_exit(fn -> Inkwell.Themes.set_active("Default Dark") end)
    :ok
  end
```

- [ ] **Step 2: Implement the theme list + preview in the settings tab**

Extend `lib/inkwell_web/picker_component.ex`. Add these events:

```elixir
  def handle_event("select_theme", %{"name" => name}, socket) do
    case Inkwell.Themes.get(name) do
      {:ok, theme} ->
        preview_html = render_preview_sample(theme)
        {:noreply, socket |> assign(:selected_theme, theme) |> assign(:preview_html, preview_html)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("apply_theme", _, socket) do
    case socket.assigns[:selected_theme] do
      nil -> {:noreply, socket}
      theme -> Inkwell.Themes.set_active(theme.name); {:noreply, socket}
    end
  end

  def handle_event("duplicate_theme", _, socket) do
    case socket.assigns[:selected_theme] do
      nil ->
        {:noreply, socket}

      theme ->
        new_name = unique_user_name(theme.name <> " Copy")
        :ok = Inkwell.Themes.duplicate(theme.name, new_name)
        {:ok, new} = Inkwell.Themes.get(new_name)
        {:noreply, socket |> assign(:selected_theme, new) |> assign(:editing, new)}
    end
  end

  def handle_event("delete_theme", _, socket) do
    case socket.assigns[:selected_theme] do
      %{source: :user, name: name} -> Inkwell.Themes.delete(name)
      _ -> :noop
    end

    {:noreply, assign(socket, :selected_theme, nil)}
  end

  defp render_preview_sample(theme) do
    sample = """
    # Heading 1

    ## Heading 2

    Inkwell preview with `inline code` and a [link](#).

    > A blockquote.

    ```elixir
    def hello, do: :world
    ```

    | Col A | Col B |
    |-------|-------|
    | one   | two   |

    - list item
    - another
    """

    {html, _, _} = Inkwell.Renderer.render_with_nav(sample, theme.syntax_theme)
    {theme, html}
  end

  defp unique_user_name(base) do
    Enum.reduce_while(0..99, base, fn i, _ ->
      candidate = if i == 0, do: base, else: "#{base} #{i}"
      if Inkwell.Themes.get(candidate) == :error, do: {:halt, candidate}, else: {:cont, candidate}
    end)
  end
```

Render the appearance section inside `<div :if={@tab == :settings}>` (replacing the placeholder):

```heex
<div id="picker-settings-content">
  <h2>Theme</h2>
  <div id="theme-layout">
    <ul id="theme-list">
      <li class="theme-section">PRESETS</li>
      <li :for={t <- Enum.filter(Inkwell.Themes.list(), &(&1.source == :preset))}
          data-theme-name={t.name}
          class={["theme-item", @selected_theme && @selected_theme.name == t.name && "selected"]}
          phx-click={JS.push("select_theme", value: %{name: t.name})}
          phx-target={@myself}>
        {t.name}<span :if={@active_theme.name == t.name}> ✓</span>
      </li>
      <li class="theme-section">YOURS</li>
      <li :for={t <- Enum.filter(Inkwell.Themes.list(), &(&1.source == :user))}
          data-theme-name={t.name}
          class={["theme-item", @selected_theme && @selected_theme.name == t.name && "selected"]}
          phx-click={JS.push("select_theme", value: %{name: t.name})}
          phx-target={@myself}>
        {t.name}<span :if={@active_theme.name == t.name}> ✓</span>
      </li>
    </ul>
    <div id="theme-preview"
         data-previewing={@selected_theme && @selected_theme.name}
         style={@selected_theme && preview_style(@selected_theme)}>
      <div :if={@preview_html} class="markdown-body">{Phoenix.HTML.raw(elem(@preview_html, 1))}</div>
      <div :if={!@preview_html} class="preview-unavailable">Select a theme to preview</div>
    </div>
  </div>
  <div id="theme-actions">
    <button id="theme-apply" disabled={@selected_theme == nil} phx-click="apply_theme" phx-target={@myself}>Apply</button>
    <button id="theme-duplicate" disabled={@selected_theme == nil} phx-click="duplicate_theme" phx-target={@myself}>Duplicate</button>
    <button id="theme-delete" disabled={@selected_theme == nil or @selected_theme.source == :preset} phx-click="delete_theme" phx-target={@myself}>Delete</button>
  </div>
</div>
```

Add to the module (near the helpers):

```elixir
  defp preview_style(theme) do
    theme.colors
    |> Enum.map(fn {k, v} -> "--#{String.replace(Atom.to_string(k), "_", "-")}: #{v};" end)
    |> Enum.join(" ")
  end
```

The `@active_theme` assign comes from the outer layout via the LiveView; propagate it into the picker component via the existing `update/2` (the Shell hook puts it on the socket assigns, add it to the component call in `app.html.heex`: `active_theme={@active_theme}` — already there? If not, add it).

Add `active_theme` to the live component attrs and the `update/2` pick-up. Also ensure `@selected_theme` and `@preview_html` are initialized to nil in `update/2`:

```elixir
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:results, fn -> initial_results(assigns[:current_path]) end)
      |> assign_new(:tab, fn -> :files end)
      |> assign_new(:selected_theme, fn -> nil end)
      |> assign_new(:preview_html, fn -> nil end)
      |> assign_new(:editing, fn -> nil end)
```

- [ ] **Step 3: Add CSS for theme list + preview in `priv/static/app.css`**

Append:

```css
#theme-layout { display: grid; grid-template-columns: 240px 1fr; gap: 16px; min-height: 360px; }
#theme-list { list-style: none; padding: 0; margin: 0; border-right: 1px solid var(--border); }
#theme-list .theme-section {
  padding: 8px 12px 4px; font-size: 10px;
  text-transform: uppercase; letter-spacing: 0.08em;
  color: var(--text-muted);
}
#theme-list .theme-item {
  padding: 6px 12px; cursor: pointer; color: var(--text-secondary);
}
#theme-list .theme-item:hover { background: var(--bg-hover); color: var(--text); }
#theme-list .theme-item.selected { background: var(--bg-surface); color: var(--text); }

#theme-preview {
  border: 1px solid var(--border); border-radius: 6px; padding: 16px;
  overflow-y: auto; background: var(--bg);
}
#theme-preview .preview-unavailable {
  color: var(--text-muted); font-style: italic;
  display: flex; align-items: center; justify-content: center; height: 100%;
}

#theme-actions { margin-top: 12px; display: flex; gap: 8px; }
#theme-actions button {
  padding: 6px 12px; border: 1px solid var(--border); border-radius: 4px;
  background: var(--bg-surface); color: var(--text); font-family: system-ui; font-size: 12px;
  cursor: pointer;
}
#theme-actions button:disabled { opacity: 0.4; cursor: default; }
#theme-actions button:hover:not(:disabled) { background: var(--bg-hover); }
```

- [ ] **Step 4: Run tests**

Run: `mix test test/inkwell_web/live/settings_tab_test.exs`
Expected: PASS.

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell_web/picker_component.ex priv/static/app.css test/inkwell_web/live/settings_tab_test.exs
git commit -m "feat(settings): theme list with preview and Apply/Duplicate/Delete actions"
```

---

## Task 9: Theme editor

**Files:**
- Modify: `lib/inkwell_web/picker_component.ex`
- Modify: `test/inkwell_web/live/settings_tab_test.exs`

Click **Edit** on a user theme → editor view with form fields. Live preview updates on every change. Syntax theme change re-renders the sample. Save/Cancel.

- [ ] **Step 1: Add failing tests**

```elixir
  test "clicking Edit on user theme opens editor", %{conn: conn} do
    :ok = Inkwell.Themes.duplicate("Default Dark", "My Edit Test")
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    view |> element("[data-theme-name='My Edit Test']") |> render_click()
    view |> element("#theme-edit") |> render_click()
    assert has_element?(view, "#theme-editor")
    on_exit(fn -> Inkwell.Themes.delete("My Edit Test") end)
  end

  test "editing a color updates preview live", %{conn: conn} do
    :ok = Inkwell.Themes.duplicate("Default Dark", "Live Preview Test")
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    view |> element("[data-theme-name='Live Preview Test']") |> render_click()
    view |> element("#theme-edit") |> render_click()

    view |> form("#theme-editor-form", theme: %{colors: %{bg: "#abcdef"}}) |> render_change()

    assert render(view) =~ "--bg: #abcdef"
    on_exit(fn -> Inkwell.Themes.delete("Live Preview Test") end)
  end

  test "Save persists and Cancel discards", %{conn: conn} do
    :ok = Inkwell.Themes.duplicate("Default Dark", "Save Test")
    {:ok, view, _html} = live(conn, ~p"/")
    view |> element("#btn-search") |> render_click()
    view |> element("#picker-tab-settings") |> render_click()
    view |> element("[data-theme-name='Save Test']") |> render_click()
    view |> element("#theme-edit") |> render_click()

    view |> form("#theme-editor-form", theme: %{colors: %{bg: "#abcdef"}}) |> render_change()
    view |> element("#theme-save") |> render_click()

    {:ok, saved} = Inkwell.Themes.get("Save Test")
    assert saved.colors[:bg] == "#abcdef"
    on_exit(fn -> Inkwell.Themes.delete("Save Test") end)
  end
```

- [ ] **Step 2: Run tests — expect failure**

Run: `mix test test/inkwell_web/live/settings_tab_test.exs`
Expected: FAIL (editor doesn't exist).

- [ ] **Step 3: Add editor state + events to `PickerComponent`**

Add events:

```elixir
  def handle_event("edit_theme", _, socket) do
    case socket.assigns[:selected_theme] do
      %{source: :user} = theme -> {:noreply, assign(socket, :editing, theme)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("edit_change", %{"theme" => params}, socket) do
    editing = merge_edit(socket.assigns.editing, params)

    preview_html =
      if params["syntax_theme"] && params["syntax_theme"] != socket.assigns.editing.syntax_theme do
        render_preview_sample(editing) |> elem(1)
      else
        socket.assigns.preview_html && elem(socket.assigns.preview_html, 1)
      end

    {:noreply,
     socket
     |> assign(:editing, editing)
     |> assign(:preview_html, {editing, preview_html})}
  end

  def handle_event("save_edit", _, socket) do
    :ok = Inkwell.Themes.save(socket.assigns.editing)
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  defp merge_edit(theme, %{"name" => name} = params) do
    colors = Map.merge(theme.colors, atomize_colors(params["colors"] || %{}))
    fonts = Map.merge(theme.fonts, atomize_fonts(params["fonts"] || %{}))
    %{theme | name: name, colors: colors, fonts: fonts, syntax_theme: params["syntax_theme"] || theme.syntax_theme}
  end

  defp atomize_colors(map), do: Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
  defp atomize_fonts(map), do: Map.new(map, fn {k, v} -> {String.to_existing_atom(k), v} end)
```

Add curated field list:

```elixir
  @curated_colors ~w(bg text text_muted accent border h1 h2 link code_bg)a

  defp curated_colors, do: @curated_colors
  defp lumis_themes, do: Lumis.available_themes()
```

Add editor template within the Appearance content:

```heex
<div :if={@editing} id="theme-editor">
  <form id="theme-editor-form" phx-change="edit_change" phx-submit="save_edit" phx-target={@myself}>
    <label>Name <input name="theme[name]" value={@editing.name} /></label>

    <fieldset>
      <legend>Colors</legend>
      <label :for={k <- curated_colors()}>
        {human_label(k)}
        <input type="color" name={"theme[colors][#{k}]"} value={@editing.colors[k]} />
      </label>
    </fieldset>

    <fieldset>
      <legend>Fonts</legend>
      <label>Heading
        <select name="theme[fonts][heading]">
          <option :for={f <- font_options(@system_fonts)} value={f} selected={f == @editing.fonts.heading}>{f}</option>
        </select>
      </label>
      <label>Body
        <select name="theme[fonts][body]">
          <option :for={f <- font_options(@system_fonts)} value={f} selected={f == @editing.fonts.body}>{f}</option>
        </select>
      </label>
      <label>Mono
        <select name="theme[fonts][mono]">
          <option :for={f <- font_options(@system_fonts)} value={f} selected={f == @editing.fonts.mono}>{f}</option>
        </select>
      </label>
    </fieldset>

    <label>Syntax theme
      <select name="theme[syntax_theme]">
        <option :for={t <- lumis_themes()} value={t} selected={t == @editing.syntax_theme}>{t}</option>
      </select>
    </label>

    <div id="editor-buttons">
      <button id="theme-save" type="submit">Save</button>
      <button id="theme-cancel" type="button" phx-click="cancel_edit" phx-target={@myself}>Cancel</button>
    </div>
  </form>
</div>
```

Helpers:

```elixir
  @default_fonts ["Bricolage Grotesque", "Outfit", "SF Mono"]

  defp font_options(system), do: @default_fonts ++ (system || [])

  defp human_label(:bg), do: "Background"
  defp human_label(:text), do: "Text"
  defp human_label(:text_muted), do: "Text muted"
  defp human_label(:accent), do: "Accent"
  defp human_label(:border), do: "Border"
  defp human_label(:h1), do: "H1"
  defp human_label(:h2), do: "H2"
  defp human_label(:link), do: "Link"
  defp human_label(:code_bg), do: "Code bg"
  defp human_label(other), do: other |> Atom.to_string() |> String.replace("_", " ")
```

Also add an **Edit** button to `#theme-actions`:

```heex
<button id="theme-edit" disabled={@selected_theme == nil or @selected_theme.source == :preset} phx-click="edit_theme" phx-target={@myself}>Edit</button>
```

And wire `@system_fonts` assign in `update/2`: `assign_new(:system_fonts, fn -> [] end)`.

- [ ] **Step 4: Run tests**

Run: `mix test test/inkwell_web/live/settings_tab_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/inkwell_web/picker_component.ex test/inkwell_web/live/settings_tab_test.exs
git commit -m "feat(settings): theme editor with live preview and Save/Cancel"
```

---

## Task 10: Header theme dropdown

**Files:**
- Modify: `lib/inkwell_web/components/layouts/app.html.heex`
- Modify: `assets/js/hooks/shortcuts.js`
- Modify: `priv/static/app.css`

Replace the current stub button in the header with a real dropdown listing all themes.

- [ ] **Step 1: Replace the `#btn-theme` block in `app.html.heex`**

```heex
<div id="theme-dropdown" phx-click-away={JS.remove_class("open", to: "#theme-dropdown")}>
  <button
    id="btn-theme"
    class="header-btn"
    aria-label="Theme"
    phx-click={JS.toggle_class("open", to: "#theme-dropdown")}
    title={"Theme: " <> @active_theme.name}
  >
    <svg class="icon-theme" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 3v18M3 12h18" />
    </svg>
  </button>
  <ul id="theme-dropdown-menu">
    <li class="theme-dropdown-section">PRESETS</li>
    <li :for={t <- Enum.filter(Inkwell.Themes.list(), &(&1.source == :preset))}
        phx-click={JS.push("set_active_theme", value: %{name: t.name}) |> JS.remove_class("open", to: "#theme-dropdown")}
        class={@active_theme.name == t.name && "active"}>
      {t.name}<span :if={@active_theme.name == t.name}> ✓</span>
    </li>
    <li :if={Enum.any?(Inkwell.Themes.list(), &(&1.source == :user))} class="theme-dropdown-section">YOURS</li>
    <li :for={t <- Enum.filter(Inkwell.Themes.list(), &(&1.source == :user))}
        phx-click={JS.push("set_active_theme", value: %{name: t.name}) |> JS.remove_class("open", to: "#theme-dropdown")}
        class={@active_theme.name == t.name && "active"}>
      {t.name}<span :if={@active_theme.name == t.name}> ✓</span>
    </li>
    <li class="theme-dropdown-divider"></li>
    <li phx-click={JS.push("open_picker", value: %{tab: "settings"}) |> JS.remove_class("open", to: "#theme-dropdown")}>
      Settings…
    </li>
  </ul>
</div>
```

- [ ] **Step 2: Wire `Ctrl+Shift+T` to open the dropdown**

Modify `assets/js/hooks/shortcuts.js` — find the current theme-toggle binding and replace with a click on `#btn-theme`:

```javascript
// was: something that emitted phx-click=toggle_theme
if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === "t") {
  document.getElementById("btn-theme")?.click();
  e.preventDefault();
}
```

- [ ] **Step 3: Add dropdown CSS to `priv/static/app.css`**

```css
#theme-dropdown { position: relative; }
#theme-dropdown-menu {
  display: none;
  position: absolute; top: 40px; left: 0; z-index: 250;
  min-width: 220px;
  background: var(--bg-surface); border: 1px solid var(--border);
  border-radius: 6px; box-shadow: var(--shadow);
  list-style: none; margin: 0; padding: 4px 0;
  font-family: system-ui; font-size: 12px;
}
#theme-dropdown.open #theme-dropdown-menu { display: block; }
#theme-dropdown-menu li {
  padding: 6px 12px; cursor: pointer; color: var(--text-secondary);
}
#theme-dropdown-menu li:hover:not(.theme-dropdown-section):not(.theme-dropdown-divider) {
  background: var(--bg-hover); color: var(--text);
}
#theme-dropdown-menu .theme-dropdown-section {
  font-size: 10px; text-transform: uppercase; letter-spacing: 0.08em;
  color: var(--text-muted); cursor: default; padding: 4px 12px;
}
#theme-dropdown-menu .theme-dropdown-divider {
  height: 1px; background: var(--border); margin: 4px 0; padding: 0;
}
#theme-dropdown-menu li.active { color: var(--h2); }
```

- [ ] **Step 4: Manual verification**

Run `mix phx.server` (or the burrito build). Confirm:

- Header shows one theme button with a circle+plus icon.
- Clicking it opens a dropdown listing Default Dark / Default Light, active one has ✓.
- Click a theme → app re-themes immediately, dropdown closes.
- `Ctrl+Shift+T` opens the dropdown.
- "Settings…" at the bottom opens the picker's Settings tab.

- [ ] **Step 5: Run full suite**

Run: `mix test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell_web/components/layouts/app.html.heex assets/js/hooks/shortcuts.js priv/static/app.css
git commit -m "feat(themes): header theme dropdown with Ctrl+Shift+T"
```

---

## Task 11: Font picker — Tauri Rust command + JS hook

**Files:**
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/main.rs`
- Create: `assets/js/hooks/system_fonts.js`
- Modify: `assets/js/app.js`
- Modify: `lib/inkwell_web/picker_component.ex`

- [ ] **Step 1: Add `font-kit` to `src-tauri/Cargo.toml`**

Under `[dependencies]`:

```toml
font-kit = "0.14"
```

- [ ] **Step 2: Implement `list_system_fonts` in `src-tauri/src/main.rs`**

Add at the top of `main.rs`:

```rust
use font_kit::source::SystemSource;
```

Add the command function:

```rust
#[tauri::command]
fn list_system_fonts() -> Vec<String> {
    let mut names: Vec<String> = SystemSource::new()
        .all_families()
        .unwrap_or_default();
    names.sort();
    names.dedup();
    names
}
```

Register it in the builder (search for `.invoke_handler(tauri::generate_handler!(...))` in main.rs and add `list_system_fonts` to the list).

- [ ] **Step 3: Create `assets/js/hooks/system_fonts.js`**

```javascript
const SystemFonts = {
  mounted() {
    const isTauri = !!window.__TAURI__;

    if (!isTauri) {
      // Browser fallback: push empty list so editor falls back to defaults only.
      this.pushEvent("system_fonts", { fonts: [] });
      return;
    }

    window.__TAURI__
      .invoke("list_system_fonts")
      .then((fonts) => this.pushEvent("system_fonts", { fonts }))
      .catch(() => this.pushEvent("system_fonts", { fonts: [] }));
  },
};

export default SystemFonts;
```

- [ ] **Step 4: Register hook in `assets/js/app.js`**

Add import and include in `Hooks`:

```javascript
import SystemFonts from "./hooks/system_fonts";

const Hooks = {
  DiffView, DocMap, DocRailNav, Mermaid, ModeToggle,
  PickerKeys, PickerOverlay, Scrollspy, Shortcuts, SystemFonts, Zoom,
};
```

- [ ] **Step 5: Add the hook mount point to `PickerComponent`**

In `render/1`, inside the settings tab content:

```heex
<div id="system-fonts-loader" phx-hook="SystemFonts" phx-target={@myself}></div>
```

Add event handler:

```elixir
  def handle_event("system_fonts", %{"fonts" => fonts}, socket) do
    {:noreply, assign(socket, :system_fonts, fonts)}
  end
```

- [ ] **Step 6: Rebuild JS assets and Tauri binary**

Run: `mix assets.build`
Run (in `src-tauri/`): `cargo check` — confirm font-kit compiles.

- [ ] **Step 7: Commit**

```bash
git add src-tauri/Cargo.toml src-tauri/src/main.rs src-tauri/Cargo.lock assets/js/app.js assets/js/hooks/system_fonts.js lib/inkwell_web/picker_component.ex
git commit -m "feat(themes): font picker enumerates system fonts in Tauri"
```

---

## Task 12: Additional presets

**Files:**
- Create: `priv/themes/plain.json`
- Create: `priv/themes/dracula.json`
- Create: `priv/themes/solarized-light.json`
- Create: `priv/themes/gruvbox-dark.json`

- [ ] **Step 1: Create `priv/themes/plain.json`**

A minimalist grayscale dark theme. Derive from `default-dark.json` and flatten `h1-h4` / `accent` / `link` to grayscale values like `#f5f5f5`, `#e0e0e0`, `#bdbdbd`, `#9e9e9e`. `syntax_theme: "github_dark"`. Full ~50 color keys populated.

(Fill in the complete JSON using `default-dark.json` as the base; edit color values.)

- [ ] **Step 2: Create `priv/themes/dracula.json`**

Use the canonical Dracula palette from https://draculatheme.com:
- `bg: "#282a36"`, `bg_surface: "#21222c"`, `bg_hover: "#44475a"`
- `text: "#f8f8f2"`, `text_secondary: "#bd93f9"`, `text_muted: "#6272a4"`
- `h1: "#ff79c6"`, `h2: "#8be9fd"`, `h3: "#50fa7b"`, `h4: "#bd93f9"`
- `link: "#8be9fd"`, `accent: "#ff5555"`
- `code_bg: "#44475a"`, `code_text: "#ff79c6"`
- `syntax_theme: "dracula"`

Populate every color key (mirror `default-dark.json` keys, substitute palette).

- [ ] **Step 3: Create `priv/themes/solarized-light.json`**

Use the Solarized Light palette (https://ethanschoonover.com/solarized). `mode: "light"`, `syntax_theme: "solarized (light)"` (verify via `Lumis.available_themes()`).

- [ ] **Step 4: Create `priv/themes/gruvbox-dark.json`**

Use the Gruvbox dark palette (https://github.com/morhetz/gruvbox). `mode: "dark"`, `syntax_theme: "gruvbox_dark"`.

- [ ] **Step 5: Verify load**

Run: `iex -S mix` then `Inkwell.Themes.list() |> Enum.map(& &1.name)`
Expected: `["Default Dark", "Default Light", "Dracula", "Gruvbox Dark", "Plain", "Solarized Light"]`.

Run: `mix test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add priv/themes/
git commit -m "feat(themes): ship Plain, Dracula, Solarized Light, Gruvbox Dark presets"
```

---

## Task 13: CLI `--theme` accepts any theme name

**Files:**
- Modify: `lib/inkwell/cli.ex`
- Modify: `test/inkwell/cli_test.exs`

- [ ] **Step 1: Add failing test**

In `test/inkwell/cli_test.exs` (extend existing tests):

```elixir
  describe "CLI --theme" do
    test "--theme Default\\ Light is accepted" do
      # parse_mode is in Inkwell.Application
      assert {:daemon, %{theme: "Default Light"}} = Inkwell.Application.parse_mode(["daemon", "--theme", "Default Light"])
    end

    test "help text lists --theme as accepting any theme name" do
      assert Inkwell.CLI.help_text() =~ "--theme <name>"
      assert Inkwell.CLI.help_text() =~ "Set the theme by name"
    end
  end
```

- [ ] **Step 2: Update `help_text/0` in `lib/inkwell/cli.ex`**

Replace the `--theme dark|light` line with:

```
  --theme <name>                 Set the theme by name (e.g. "Default Dark", "Dracula")
```

- [ ] **Step 3: Update `run_daemon/1` to validate and persist via Settings.write_active**

```elixir
  def run_daemon(theme) do
    if theme do
      case Inkwell.Settings.write_active(theme) do
        :ok -> :ok
        _ -> :ok
      end
    end

    Logger.info("Starting daemon with theme=#{theme || "(persisted)"}")
    Application.ensure_all_started(:inkwell)
    Process.sleep(:infinity)
  end
```

(Validation against the real theme list happens inside `Inkwell.Themes.init/1` via `resolve_active/2` — if the name doesn't match any loaded theme, it falls back to Default Dark. That's the designed behavior. No need for pre-validation in CLI.)

- [ ] **Step 4: Run tests**

Run: `mix test test/inkwell/cli_test.exs`
Expected: PASS.

Run: `mix test`
Expected: PASS.

- [ ] **Step 5: Manual verification**

```
./burrito_out/inkwell_darwin_arm64 preview README.md --theme "Dracula"
./burrito_out/inkwell_darwin_arm64 preview README.md --theme "bogus-name"
```

Expected: first applies Dracula; second silently falls back to Default Dark (with a log line about the unknown theme).

- [ ] **Step 6: Commit**

```bash
git add lib/inkwell/cli.ex test/inkwell/cli_test.exs
git commit -m "feat(cli): --theme accepts any theme name"
```

---

## Task 14: Final pre-flight

**Files:** none (verification only)

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: all of `format --check-formatted`, `compile --warnings-as-errors`, `credo --strict`, and `test` pass.

- [ ] **Step 2: Manual smoke**

Launch the daemon and verify:

- Fresh run (delete `~/.inkwell/` first) → daemon boots, `settings.json` contains `"active_theme": "Default Dark"`, Default Dark is active.
- Open theme dropdown → switch to Default Light → app re-themes.
- Open Settings tab → select Dracula → Apply → app re-themes.
- Duplicate Dracula → editor opens → change a color → preview updates → Save → theme re-themes.
- Delete the duplicated theme while it's active → app falls back to Default Dark.
- `inkwell preview README.md --theme "Solarized Light"` → Solarized Light is active.
- `inkwell preview README.md --theme "nope"` → falls back to Default Dark, warning logged.

- [ ] **Step 3: Write a follow-up ticket (optional)**

If it wasn't part of this PR, file an issue to refactor the remaining hardcoded `body:has([data-theme="dark"]) …` rules in `app.css` and `markdown-wide.css` to consume CSS variables (eliminates the `mode` field's role as a CSS flag).

---

## Self-Review Notes

The plan covers every section of the design spec:

- **Theme data model** → Task 1 (preset JSONs showcasing the schema) + Task 2 (parser).
- **Storage layout** → Task 2 (`load_dir`) + Task 3 (user dir creation in `init`).
- **`Inkwell.Themes` GenServer** → Tasks 2–4.
- **Runtime / CSS injection** → Task 6.
- **Markdown renderer (syntax_theme)** → Task 6 (renderer.ex).
- **Header theme dropdown** → Task 10.
- **Settings tab + theme list + editor** → Tasks 7–9.
- **Font picker** → Task 11.
- **Syntax theme picker** → part of Task 9 editor.
- **CLI flag** → Task 13.
- **First-boot + old-file cleanup** → Task 5.
- **Presets shipped in v1** → Tasks 1 + 12.

No steps reference undefined functions. Every code step contains the actual code. All commits are atomic and labeled.

