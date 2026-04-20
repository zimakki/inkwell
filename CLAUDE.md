# Inkwell

Live markdown preview daemon built in Elixir. Runs a persistent background server per user, watches markdown files for changes, and serves a browser-based preview UI with real-time WebSocket updates.

## Build & Run

```bash
mix deps.get
mix release              # Burrito produces binaries in burrito_out/
./burrito_out/inkwell_darwin_arm64 preview file.md --theme dark
```

## Test & Format

```bash
mix test
mix format
mix compile --warnings-as-errors
```

## Architecture

Phoenix + LiveView application. Domain code lives under `lib/inkwell/`; the web layer under `lib/inkwell_web/`.

OTP supervision tree (`Inkwell.Application`, daemon mode):
- `Phoenix.PubSub` (name `Inkwell.PubSub`) — broadcasts file-change events on `"file:#{path}"` and theme changes on `"theme"`
- `Inkwell.History` (Agent) — recent files list (max 20)
- `Inkwell.Daemon` (GenServer) — daemon lifecycle, PID/port files in `~/.inkwell/`, idle shutdown after 10 min with no live clients
- `DynamicSupervisor` (`Inkwell.WatcherSupervisor`) — one `Inkwell.Watcher` GenServer per watched directory
- `InkwellWeb.Telemetry`
- `InkwellWeb.Endpoint` — Phoenix Endpoint on Bandit (dynamic port 0)

Web layer (`lib/inkwell_web/`):
- Controllers: `HealthController` (/health, /status), `StopController` (/stop), `FileDialogController` (/pick-file, /pick-directory)
- LiveViews under `live_session :shell` with `on_mount InkwellWeb.LiveHooks.Shell`:
  - `EmptyLive` (`/`) — empty state
  - `BrowseLive` (`/browse?dir=`) — folder browse
  - `FileLive` (`/files?path=`) — single-file preview; subscribes to `"file:#{path}"` for live reload
- LiveComponent: `InkwellWeb.PickerComponent` — file picker overlay rendered in the app layout
- Shared shell hook (`InkwellWeb.LiveHooks.Shell`) — theme + picker_open assigns, `toggle_theme`/`open_picker`/`close_picker` events, `{:theme_changed, _}`/`{:picker_selected, _}` info handlers
- Front-end JS in `assets/js/` (bundled by `esbuild` Hex package, no Node): `Mermaid`, `Zoom`, `Scrollspy` hooks attached in `FileLive`

Key patterns:
- `Phoenix.PubSub` for broadcasting file changes to LiveView sessions
- DynamicSupervisor spawns one filesystem watcher per unique directory
- Theme stored in `:persistent_term` (shared across processes)
- IPC via `~/.inkwell/pid` and `~/.inkwell/port` files
- `secret_key_base` generated and cached at `~/.inkwell/secret` on first prod boot

## Conventions

- Elixir ~> 1.19, standard `mix format` style
- Burrito distribution (`mix release`, self-extracting binaries with bundled ERTS)
- Static assets in `priv/static/`
- Version lives in the `VERSION` file at the project root. To bump:
  1. Update the version string in `VERSION`
  2. Run `mix bump` — this patches `mix.exs`, `src-tauri/Cargo.toml`,
     `src-tauri/tauri.conf.json`, and regenerates `src-tauri/Cargo.lock`
