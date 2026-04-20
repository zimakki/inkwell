# Theme Configurability — Design Spec

**Date:** 2026-04-19
**Status:** Draft

## Problem

Inkwell ships two hardcoded themes (`dark`, `light`), toggled from a button in the header. Users can't pick other themes or customize colors, fonts, or the code-block syntax theme. The current machinery (hardcoded CSS blocks in `priv/static/markdown-wide.css`, the plain-text `~/.inkwell/theme` file, the `dark → onedark` / `light → onelight` mapping in `Inkwell.Renderer`) is not extensible.

## Solution

Replace the two-theme toggle with a full theme system:

- Themes are JSON files. A set of presets ships with Inkwell; users can duplicate and edit to create their own.
- The active theme's CSS custom properties are injected as an inline `<style>` block at page render.
- The existing header sun/moon button becomes a dropdown listing all themes (presets + user themes) for quick switching.
- A new **Settings** tab inside the existing file-picker modal provides full management: list, apply, duplicate, edit (with live preview), rename, delete.
- The `--theme` CLI flag accepts any theme name.

First boot creates a fresh `settings.json` pointing at `Default Dark`; no migration from the current plain-text `~/.inkwell/theme` file, which is just deleted.

## Architecture

### Theme data model

Each theme is one JSON file:

```json
{
  "name": "Dracula",
  "mode": "dark",
  "syntax_theme": "dracula",
  "fonts": {
    "heading": "Bricolage Grotesque",
    "body": "Outfit",
    "mono": "SF Mono"
  },
  "colors": {
    "bg": "#282a36",
    "bg_surface": "#21222c",
    "bg_hover": "#44475a",
    "text": "#f8f8f2",
    "text_secondary": "#bd93f9",
    "text_muted": "#6272a4",
    "h1": "#ff79c6",
    "h2": "#8be9fd",
    "h3": "#50fa7b",
    "h4": "#bd93f9",
    "link": "#8be9fd",
    "link_hover": "#6272a4",
    "accent": "#ff5555",
    "border": "#44475a",
    "border_subtle": "#21222c",
    "blockquote_bar": "#ff5555",
    "code_bg": "#44475a",
    "code_text": "#ff79c6",
    "mark_bg": "rgba(255, 121, 198, 0.2)",
    "mark_text": "#ff79c6"
    /* …remaining ~35 keys; full list documented alongside the default-dark.json preset */
  }
}
```

- `name` — display string and filename source (slugified to `dracula.json`).
- `mode` — `"light"` or `"dark"`. Used purely as a CSS-compatibility hint: the root layout emits `data-theme="<mode>"` so the existing hardcoded `body:has([data-theme="dark"]) …` rules in `app.css` and `markdown-wide.css` continue to work. Does not split the theme's colors — a theme still defines one flat set of colors.
- `syntax_theme` — a Lumis theme name (must be in `Lumis.available_themes/0`).
- `fonts.heading` / `body` / `mono` — `font-family` strings; rendered with safe fallback chains.
- `colors.*` — snake_case keys map 1:1 to CSS custom properties (`bg_surface` → `--bg-surface`). Flat; no nesting.

No schema version, no `id`, no light/dark split of color data. `mode` is a flag, not a variant axis. Themes are identified by name.

### Storage layout

```
priv/themes/                    # shipped presets (read-only, bundled)
  ├── default-dark.json
  ├── default-light.json
  ├── plain.json
  ├── dracula.json
  ├── solarized-light.json
  └── gruvbox-dark.json

~/.inkwell/themes/              # user themes (read-write)
  └── <name>.json

~/.inkwell/settings.json        # replaces ~/.inkwell/theme
  { "active_theme": "Default Dark" }
```

Name rules (enforced on save / rename / duplicate):

- User theme names cannot collide with preset names (case-insensitive).
- User theme names cannot collide with each other.

### New module: `Inkwell.Themes`

Started under the application supervisor. Reads all theme JSON files once at boot, pre-computes each theme's CSS string (`:root { --bg: …; --text: …; }`), and holds the `%{name => %{json: …, css: …}}` map in memory for the lifetime of the app. Also reads the active theme name from `~/.inkwell/settings.json`.

| Function | Purpose |
|---|---|
| `list/0` | `[%{name, source: :preset | :user, …}]` — presets then user themes |
| `get/1` | fetch a theme struct by name |
| `active/0` | the active theme struct |
| `active_css/0` | the pre-computed CSS string for the active theme (inline `<style>` body) |
| `set_active/1` | set active — updates in-memory state, writes `settings.json`, broadcasts on PubSub |
| `save/1` | write a user theme (editor calls this) — errors on name collision |
| `duplicate/2` | `duplicate("Dracula", "My Dracula")` — copy preset or user theme into user dir |
| `rename/2` | rename a user theme — update file, update `active` if it matched |
| `delete/1` | delete a user theme — cannot delete presets; if active, fall back to `Default Dark` |

Choice of in-memory store (GenServer vs `:persistent_term` vs ETS) is an implementation detail resolved in the plan.

**Edge cases:**
- `settings.json` missing → default to `"Default Dark"`.
- Active name doesn't match any file → fall back to `"Default Dark"`, log warning.
- Malformed JSON in any theme file → skip + log; theme doesn't appear in the list.

### Runtime / CSS injection

The root layout (`root.html.heex`) emits one inline `<style>` block using `Inkwell.Themes.active_css()`:

```html
<style>
  :root {
    --bg: #faf9f6;
    --text: #2b2b2b;
    /* … all ~50 custom properties */
  }
</style>
```

`priv/static/markdown-wide.css` is refactored to remove the two large blocks that *declare* the theme values — the top-level `body { --bg: … }` block and the `body:has([data-theme="dark"]) { … }` block. Everything else in `markdown-wide.css` and `app.css` stays unchanged, including the ~15 hardcoded `body:has([data-theme="dark"]) .some-selector { color: #… }` rules that currently override specific non-variable properties (doc rail link colors, mobile FAB background, welcome card, diff view accents). Those rules keep working because the root layout still sets `data-theme="<mode>"` from the active theme's `mode` field. Refactoring those hardcoded colors to CSS variables is future cleanup, not required for this feature.

Theme changes flow through `Phoenix.PubSub` on the existing `"theme"` topic; `InkwellWeb.LiveHooks.Shell` subscribes and re-renders on `{:theme_changed, _}` (as it does today). Because the inline `<style>` block is part of the rendered HTML, a LiveView re-render applies the new theme without a page reload.

### Markdown renderer

`Inkwell.Renderer.render_with_nav/1` reads `syntax_theme` from the active theme instead of today's hardcoded `dark → onedark` / `light → onelight` map. When the active theme's `syntax_theme` changes, `Inkwell.Watcher.rebroadcast_all/0` triggers a re-render of all open files (same mechanism used today on theme toggle).

### Header: theme dropdown

Replaces the existing `#btn-toggle-theme` sun/moon button in `app.html.heex`.

- Button shows the active theme's name (or an icon + the name).
- Click or `Ctrl+Shift+T` opens a dropdown listing all themes, grouped:
  - **Presets** (shipped)
  - **Yours** (user themes, if any)
  - **Settings…** at the bottom — switches the picker modal to the Settings tab.
- Active theme has a checkmark.
- Clicking a name: calls `Inkwell.Themes.set_active/1`; broadcast re-renders the app.

### Settings tab in the picker modal

The `PickerComponent` modal gains a tab switcher:

- **Files** tab — current picker behavior, unchanged.
- **Settings** tab — new. The gear button in the picker's bottom-left switches to this tab.

Settings tab has a left nav sized for future growth: **Appearance** (only section populated in v1), **Editor**, **Behavior**, **About** (scaffolded but empty).

**Appearance → Theme** layout:

```
┌── Theme list ──┐  ┌── Preview pane ────────────┐
│ PRESETS        │  │ # Heading 1                │
│  Default Dark  │  │ ## H2                      │
│  Default Light │  │ paragraph with `inline`    │
│  Dracula ✓     │  │ > blockquote               │
│  Plain         │  │ ```elixir                  │
│  Solarized …   │  │ def hello, do: :world      │
│                │  │ ```                        │
│ YOURS          │  │ | table header | col |     │
│  My Theme      │  │ |--------------|-----|     │
│                │  │ - list item                │
│ + New Theme    │  │ [link]                     │
└────────────────┘  └────────────────────────────┘
[Apply] [Duplicate] [Edit] [Delete]
```

- Clicking a theme shows it in the preview pane. The app's active theme doesn't change until **Apply**.
- Preview pane is a fixed sample markdown snippet rendered via MDEx, wrapped in a `<div data-theme="{mode}" style="--bg: …; --text: …; …">` that sets the theme's CSS variables inline and mirrors the `data-theme` attribute so the few mode-specific rules resolve correctly within the preview.
- **Apply** — `Inkwell.Themes.set_active/1`.
- **Duplicate** — prompt for new name, `Inkwell.Themes.duplicate/2`, open in editor.
- **Edit** — only enabled for user themes. Opens editor view (below).
- **Delete** — only enabled for user themes. Confirm. If active, active falls back to `Default Dark`.
- **+ New Theme** — equivalent to duplicating `Default Dark` as `"Untitled"` and opening the editor.

### Theme editor

Replaces the list/preview area within the Settings tab when the user clicks Edit.

```
Name:  [My Theme_________________]

Colors (curated ~12)            |  Preview
  Background       [#faf9f6 ⬛] |  # Heading 1
  Text             [#2b2b2b ⬛] |  ## H2
  Text muted       [#888888 ⬛] |  paragraph with `inline`
  Accent           [#dc2626 ⬛] |  > blockquote
  Border           [#d6d3cc ⬛] |  ```elixir
  H1               [#b45309 ⬛] |  def hello, do: :world
  H2               [#1e40af ⬛] |  ```
  Link             [#2563eb ⬛] |  | table | … |
  Code bg          [#eae8e1 ⬛] |

Fonts
  Heading          [Bricolage Grotesque ▾]
  Body             [Outfit              ▾]
  Mono             [SF Mono             ▾]

Syntax theme       [onelight ▾]

[Save]  [Cancel]
```

- **Curated color fields:** ~12 high-impact variables exposed in the UI. The full set of ~50 keys lives in the saved JSON (populated from the source theme on duplicate). Power users hand-edit the JSON file for the remaining ~38.
- **Live preview:** color and font edits update the preview pane's inline CSS variables instantly (pure CSS, no server round-trip). Syntax theme changes require re-rendering the sample markdown via MDEx (a cheap LiveView round-trip).
- **Save** — `Inkwell.Themes.save/1` writes the JSON and, if the theme is active, re-broadcasts so the app refreshes.
- **Cancel** — discards unsaved edits, returns to the theme list.

### Font picker

**Tauri (desktop):** a Tauri command written in Rust enumerates system fonts (via `font-kit` or equivalent). A LiveView JS hook invokes this command on mount and `push_event`s the list to the server. The font dropdowns show:

- Default fonts first (Bricolage Grotesque, Outfit, SF Mono — the fonts Inkwell already uses).
- System fonts alphabetically below a divider.

**Browser (dev):** the dropdown shows only the default fonts. No enumeration, no free-text, no curated list. Users who want custom fonts run in Tauri.

The JSON stores the family string verbatim. CSS applies it with a safe fallback: `font-family: "<value>", system-ui, sans-serif;` (mono chain for mono).

### Syntax theme picker

Dropdown populated at compile time from `Lumis.available_themes/0` (~30 options like `onedark`, `onelight`, `github_dark`, `dracula`, `solarized`, etc.). Stored in `theme.syntax_theme`.

### CLI `--theme` flag

Today accepts `dark | light` only, writes to `~/.inkwell/theme`. New behavior:

- Accepts any theme name loaded by `Inkwell.Themes.list/0` (case-insensitive match on display name).
- Unknown name → prints valid theme names to stderr, exits non-zero.
- Writes the active theme into `~/.inkwell/settings.json`.

### Migration

Nothing to migrate from. On boot, if `~/.inkwell/settings.json` is missing or invalid, write `{ "active_theme": "Default Dark" }`. If the old `~/.inkwell/theme` file is present, delete it. Nobody has custom themes yet — everyone starts on `Default Dark`.

## Presets shipped in v1

- **Default Dark** — exact port of today's dark palette
- **Default Light** — exact port of today's light palette
- **Plain** — minimal grayscale, no accents
- **Dracula**
- **Solarized Light**
- **Gruvbox Dark**

## Security

- Theme JSON files are read from `priv/themes/` (bundled) and `~/.inkwell/themes/` (user-owned). No external URLs, no `@font-face` loading, no arbitrary CSS — only a known set of color and font values are interpolated into the `<style>` block.
- All values are emitted using a strict allow-list (hex / `rgb()` / `rgba()` / `hsl()` / CSS identifiers for fonts; no raw string pass-through). A malformed color or font value skips that property (variable falls back to default).
- Filesystem writes scoped to `~/.inkwell/`. Slugified names prevent path traversal.
- No new attack surface in the daemon's HTTP layer.

## Testing

- `test/inkwell/themes_test.exs` — loading (valid/invalid JSON, collisions, presets vs user), `list/get/active/set_active/save/duplicate/rename/delete`, edge cases.
- `test/inkwell/settings_test.exs` — extend to cover `settings.json` read/write and first-boot creation (including deleting any old `theme` file).
- `test/inkwell/renderer_test.exs` — verify `Inkwell.Renderer` reads `syntax_theme` from the active theme.
- `test/inkwell/cli_test.exs` — extend to cover `--theme <name>` with valid and unknown names.
- `test/inkwell_web/picker_component_test.exs` — extend (or add `settings_tab_test.exs`) to cover tab switching, theme list render, Apply / Duplicate / Delete, editor save/cancel, live preview updates.
- All existing tests continue to pass, including the current theme-toggle test (updated to exercise the new dropdown).

## Verification

```bash
mix test
mix format --check-formatted
mix compile --warnings-as-errors
```

Additionally, manual verification in the Tauri app:

- First boot: `~/.inkwell/settings.json` is created with `Default Dark`; old `~/.inkwell/theme` file (if present) is deleted.
- Dropdown: open with `Ctrl+Shift+T`, switch through presets, confirm app re-themes.
- Settings tab: apply, duplicate, edit (live preview updates), save, rename, delete, active-theme fallback on delete.
- CLI: `inkwell preview README.md --theme "Dracula"` applies Dracula; bogus name errors out listing valid options.
- Font picker: enumerates system fonts in Tauri; shows defaults only in browser.

## Rollout phases

Each phase leaves the app in a working state:

1. `Inkwell.Themes` module + port today's dark/light to `priv/themes/default-*.json`. CSS refactor. Active theme injected via inline `<style>`. `settings.json` replaces the old `theme` file (old file is deleted on first boot).
2. Settings tab scaffold in picker modal (empty Settings tab, gear button switches).
3. Theme list + preview pane + Apply / Duplicate / Delete.
4. Theme editor (curated fields, live preview, Save / Cancel).
5. Header sun/moon button replaced by theme dropdown.
6. Font picker (Tauri Rust command + LiveView hook + browser default-only fallback).
7. Additional presets (Plain, Dracula, Solarized Light, Gruvbox Dark).
8. CLI `--theme` flag accepts any theme name.

## Open questions

None at spec time. Any implementation-level choices (in-memory store mechanism, Tauri Rust command shape, exact curated-editor field list) are resolved in the implementation plan.
