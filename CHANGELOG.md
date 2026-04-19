# Changelog

All notable changes to Inkwell will be documented in this file.

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
