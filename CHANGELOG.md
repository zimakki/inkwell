# Changelog

All notable changes to Inkwell will be documented in this file.

## [0.3.11] - 2026-05-20

### Fixed
- **Diff view: changed Markdown tables now render in full.** In diff mode, editing a table used to collapse it to a blank line. A modified block's word-level diff flattened it to plain text, and the browser discards loose text inside a `<table>` (it isn't valid table content), so every cell vanished. Tables — along with lists, code blocks, and blockquotes — now keep their structure and are highlighted as a whole when they change. Inline word-level diffing still applies to paragraphs and headings.
- **Diff view: the "Accept all" button is back.** The floating Accept-all control (with its +added / ~modified / -removed summary) was dropped during the Phoenix/LiveView migration and never recreated, leaving only the Cmd/Ctrl+Enter shortcut to accept changes. It now reappears whenever diff mode has pending changes and hides once they're accepted.

## [0.3.10] - 2026-05-07

### Fixed
- **Tauri desktop app: PDF export now shows a native Save dialog.** On macOS (and other Wry-based platforms), WKWebView's PDFKit intercepted `application/pdf` responses and displayed them inline, ignoring the `Content-Disposition: attachment` header — so clicking **Save as PDF** opened a PDF viewer instead of a save dialog. The fix routes the click through a dedicated `save_export_pdf` Tauri command: the Rust side fetches the PDF bytes from the daemon's local HTTP endpoint, then shows an OS file-save dialog via `tauri-plugin-dialog`. In a regular browser (not Tauri), the anchor navigation is unchanged and the browser's own save dialog still fires. No general filesystem write capability is granted to the webview — only the path the user selects in the dialog is written.

## [0.3.9] - 2026-05-06

### Added
- New **Export** action in the header (printer icon, Ctrl/Cmd+Shift+E) opens a modal with two presets — **Save as PDF** and **Print** — replacing the broken Cmd+P → Save-as-PDF path. Save-as-PDF defaults to keeping the current theme (dark backgrounds preserved) and renders a clickable Table of Contents page; Print defaults to printer-friendly white background with page numbers in the bottom margin. Each preset's settings (theme, TOC on/off, page numbers, page size A4/Letter/Legal, margins Normal/Narrow/None) are individually overridable. Save-as-PDF downloads a real PDF rendered headlessly via the new `chromic_pdf` dependency; Print opens a new tab that auto-triggers the browser print dialog. The Export icon is hidden on the empty / browse views — it requires a file open.
- New `/print` and `/export.pdf` HTTP routes power both flows. The `/print` view is rendered through a chrome-free minimal layout that loads only `print.css`, so the document body never bleeds into surrounding app shell.
- New `Inkwell.Pdf` module: probes for Chrome at boot (macOS / Linux / Windows known paths, plus PATH fallback and `INKWELL_CHROME_PATH` env-var override), caches the result, and lazy-starts the ChromicPDF supervisor on first export so daemon boot stays fast for users who never export.
- `Inkwell.Renderer.render_with_nav/2` accepts an optional `:syntax_theme` so the print path can force light syntax-highlighting colors when the user picks the printer-friendly preset, regardless of the app's current theme.

### Known limitations
- Mermaid diagrams print as their raw source text. Mermaid is rendered client-side from a CDN script in the regular preview; the print page deliberately omits both. v2 may pre-render diagrams server-side.
- Diff / Live view modes are not reproduced in the printed output. Both are implemented client-side via the `DiffView` JS hook over a LiveView socket; the print route is a stateless HTTP request, so it always renders the canonical static rendering of the current file content.
- Page numbers (`n / N` in the bottom margin) only appear in the **Print** preset. They are rendered via `@page { @bottom-center }`, which requires a non-zero `@page` margin — but the **Save as PDF** + Keep-theme path collapses `@page` margin to zero so the theme background can fill the paper edge-to-edge (Chrome's PDF generator does not paint html/body backgrounds through the @page margin area). The PDF preset defaults page numbers OFF so this is invisible by default; users who explicitly enable page numbers with keep theme will see edge-to-edge bg but no `n / N` footer.

## [0.3.8] - 2026-04-22

### Added
- Images referenced by relative paths in markdown (e.g. `![pic](./img/foo.png)`) now render in the preview. Previously they 404'd because the browser resolved the relative path against the page URL and no route served local files. The renderer now rewrites relative `<img>` URLs to `/raw?path=<abs>` at render time, and a new `RawFileController` (`GET /raw?path=`) streams the file from disk with a content-type derived from the extension. Absolute `http(s)://` and `/…` URLs are left untouched.

## [0.3.7] - 2026-04-21

### Fixed
- GitHub-style alert blocks (`> [!NOTE]`, `[!TIP]`, `[!WARNING]`, `[!IMPORTANT]`, `[!CAUTION]`) now render with a colored left border, tinted background, and bold type label. Previously the MDEx `alerts: true` extension emitted the class structure and `Inkwell.DocNav` indexed them into the right-rail sidebar, but `priv/static/markdown-wide.css` had zero selectors for those classes, so inline alerts rendered as plain paragraphs. Regression dates back to the 0.3.0 Phoenix rewrite.
- `Cmd+F` / `Ctrl+F` find-in-document restored. Opens an in-page find bar with incremental highlighting, `Enter` / `Shift+Enter` for next/previous with wrap-around, a live match counter, `Esc` to close, and automatic re-apply after WebSocket file-change updates. Input is seeded with the current text selection. Feature originally shipped in 0.2.22 but was not ported during the 0.3.0 Phoenix rewrite — `#find-bar` CSS had been dormant in `priv/static/app.css:745-773` with no JS hook or markup to attach to.

## [0.3.6] - 2026-04-21

### Added
- README now features new product media covering the file picker, diff mode with per-block accept, rails + TOC scrollspy, Mermaid rendering, the click-to-zoom modal, and browse mode. Three animated GIFs (`live-reload.gif`, `picker-search.gif`, `diff-accept.gif`) demonstrate the signature motion-driven features in place of static screenshots. Two reusable demo documents (`.github/demo/showcase.md` and `.github/demo/live-reload.md`) power repeatable captures.
- Feature copy expanded to cover render modes (Static / Live / Diff with `Cmd+Enter` accept-all), GitHub-style alerts with sidebar indexing, auto-generated table of contents with scrollspy, the mobile Doc Map sheet, click-to-zoom for images and Mermaid, native Open File / Open Folder dialogs, persistent recent files, and stable heading anchors.
- Keyboard shortcuts table now lists `Cmd+Enter` / `Ctrl+Enter` for the diff accept-all binding.

### Changed
- "How It Works" supervision tree in the README updated to match the current Phoenix + LiveView application tree — previous diagram referenced a removed `History` Agent and a non-existent `WsHandler`.

## [0.3.5] - 2026-04-21

### Added
- README now showcases light and dark theme previews side-by-side.

## [0.3.4] - 2026-04-20

### Fixed
- File paths in the picker no longer bleed out of the list at narrow widths. The directory portion now truncates with an ellipsis while the filename stays visible.
- Paths under your home directory now render with `~` for a more compact picker list.

## [0.3.3] - 2026-04-20

### Fixed
- Desktop app now actually shows the file it was asked to open. `inkwell <file>` from the CLI, drag-and-drop onto the window, and Finder "Open With Inkwell" all routed the webview to `/?path=...`, which is `EmptyLive` — the path was dropped on the floor. They now navigate to `/files?path=...` (`FileLive`).
- `Inkwell.preview_url/1` updated to the same `/files?path=` route for consistency with the CLI and webview.

## [0.3.2] - 2026-04-19

### Added
- Recently opened files now persist across daemon restarts. Backed by SQLite at `~/.inkwell/inkwell.db` via a new `Inkwell.Library` Ash domain (resource: `RecentFile`, with `list_recent!/0` and `push_recent!/1` code interfaces).

### Changed
- `Inkwell.History` (ephemeral Agent) removed; callers migrated to `Inkwell.Library.list_recent!/0` and `Inkwell.Library.push_recent!/1`.
- Daemon now runs pending Ecto migrations on boot. If migration fails, the daemon refuses to start. Recovery: remove `~/.inkwell/inkwell.db` and restart.

## [0.3.1] - 2026-04-19

### Changed
- `inkwell <path>` now classifies the argument at runtime: a file is previewed, a directory opens the picker. No more `preview` subcommand required for files.
- `inkwell preview <file>` still works but now prints a deprecation warning to stderr; it will be removed in a future release.
- Missing paths produce a single clear error ("no such file or directory") regardless of whether the user intended a file or a directory.
- Symlinks are followed transparently.
- Opening Inkwell with no file (the `/` route) now auto-opens the file picker instead of showing an "Open a file to get started" empty state.

## [0.3.0] - 2026-04-19

### Changed
- **Web layer rewritten on Phoenix + LiveView.** The stand-alone Plug router, WsHandler, StaticAssets module, and hand-rolled Registry have been removed. Routes, live-reload, pub/sub, and asset digests now ride on `InkwellWeb.Endpoint` (Bandit) with a shared `live_session :shell` and `InkwellWeb.LiveHooks.Shell` on_mount hook.
- Theme toggle is a PubSub broadcast on the `"theme"` topic; every live view reacts without re-render contortions.
- File-change pushes go through `Phoenix.PubSub` on `"file:#{path}"` instead of the old per-file Registry group.

### Added
- `EmptyLive` (`/`), `BrowseLive` (`/browse`), and `FileLive` (`/files`) replace the Plug handlers, with a shared root + app layout.
- `InkwellWeb.PickerComponent` — file picker as a LiveComponent with keyboard navigation, preview pane, scroll lock, section grouping (Recent / In this folder / Repository), and modal focus management.
- `FileDialogController` for `/pick-file` and `/pick-directory` (native file/folder dialogs from the server).
- `HealthController`, `StopController` — `/health`, `/status`, `/stop` ported to Phoenix controllers; `/health` now includes the daemon version for Tauri's compatibility check.
- LiveView JS hooks for Mermaid (with proper lifecycle), image/diagram Zoom (modal with pan/pinch/drag/keyboard), and Scrollspy navigation.
- esbuild-bundled front-end assets (Hex `esbuild`, no Node required), wired via `assets.setup`, `assets.build`, and `assets.deploy` aliases.
- LCS-based article diff view with per-block accept UI.
- Mobile bottom sheet for the document outline (doc map).
- Global keyboard shortcuts and a 3-way mode toggle for preview / diff / outline.
- Theme persists across daemon restarts (`~/.inkwell/theme`).
- `mix precommit` alias running format, deps.unlock, compile --warnings-as-errors, credo --strict, and tests.

### Fixed
- Daemon now detects live-client disconnects via `Process.monitor` instead of polling, so idle-shutdown math stays honest.
- Headings get `scroll-margin-top` so sticky headers don't hide them after in-page navigation.

### Performance
- Watcher supervisor uses a Registry lookup for O(1) "is this directory already watched?" checks.

### Security
- Mermaid CDN pinned to 11.12.0 with SRI integrity hash.

## [0.2.29] - 2026-04-17

### Added
- Click-to-zoom modal for Mermaid diagrams and inline images.

### Fixed
- Accessibility fixes, pointer-capture correctness, and link preservation in the zoom modal after review.

## [0.2.28] - 2026-04-17

### Added
- Find bar seeds its query with the current text selection when opened.

### Performance
- Static asset digests computed at compile time.

### Fixed
- Static assets correctly fingerprinted for cache-busting.

## [0.2.27] - 2026-04-17

### Added
- `Cmd`+`+` / `Cmd`+`-` / `Cmd`+`0` zoom the document view (Ctrl on Linux/Windows).

## [0.2.26] - 2026-04-15

### Changed
- New gold pen-nib app icon replaces the default Tauri logo; icon set regenerated from a master SVG.

## [0.2.25] - 2026-04-15

### Added
- Article diff view: `--mode` CLI flag, diff engine, accept UX, and associated CSS.

### Changed
- Update flow unified around Tauri's updater: removed the Elixir `Updater`, `UpdateChecker`, and `GitHub` modules and the `inkwell update` CLI command.
- Release pipeline no longer builds a standalone CLI binary. The `inkwell-cli` Homebrew formula is deprecated with a migration notice; the cask uses a `binary` stanza directly.

### Fixed
- `computeBlockDiff` no longer loops forever when the new block list is longer than the old one.
- WebSocket handler and filesystem watcher now resolve symlinks in their path registration, including intermediate symlinked directories.

## [0.2.24] - 2026-04-15

### Added
- In-webview update banner and toast with `accept_update`, `dismiss_update`, and `restart_after_update` Tauri commands.
- `tauri-plugin-process` dependency to support post-update restart.

### Changed
- Native `osascript` update dialogs replaced by the webview banner, which re-injects itself after navigation so it survives route changes.

## [0.2.23] - 2026-04-14

### Added
- Standard macOS menu items for Hide, Hide Others, Show All, Minimize, and Close Window.

### Fixed
- Tauri detects a stale daemon after the app updates and replaces it instead of hanging.
- `mix bump` no longer rewrites `mix.exs` — it reads the VERSION file dynamically.

## [0.2.22] - 2026-04-01

### Added
- Find-in-document: `Cmd`+`F` / `Ctrl`+`F` opens an in-page find bar with prev/next navigation, wrap-around, and `Esc` to close.
- Find highlights re-apply automatically on WebSocket content updates.

### Fixed
- SVG safety, `Cmd`+`F` fallback path, and a debounce race in the find implementation.
- DOM safety, Unicode handling, navigation guard, and find-bar positioning issues after code review.

## [0.2.21] - 2026-03-31

### Added
- macOS Edit menu with native Undo, Redo, Cut, Copy, Paste, and Select All shortcuts
- Find-in-page support via Cmd+F (macOS) / Ctrl+F (Linux/Windows) using native browser find
- `mix bump` task to sync the VERSION file into mix.exs, Cargo.toml, tauri.conf.json, and Cargo.lock in one command
- VERSION file as the single source of truth for the project version
