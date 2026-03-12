# Inkwell

Live markdown preview daemon built in Elixir. Runs a persistent background server per user, watches markdown files for changes, and serves a browser-based preview UI with real-time WebSocket updates.

## Build & Run

```bash
mix deps.get
mix escript.build        # produces ./inkwell binary
./inkwell preview file.md --theme dark
```

## Test & Format

```bash
mix test
mix format
mix compile --warnings-as-errors
```

## Architecture

OTP supervision tree (`Inkwell.Application`):
- `Registry` (`:duplicate` keys) — pub/sub for per-file WebSocket clients
- `Inkwell.History` (Agent) — recent files list (max 20)
- `Inkwell.Daemon` (GenServer) — daemon lifecycle, PID/port files in `~/.inkwell/`, idle shutdown
- `DynamicSupervisor` (`Inkwell.WatcherSupervisor`) — one `Inkwell.Watcher` GenServer per watched directory
- `Bandit` HTTP server (dynamic port) — serves `Inkwell.Router` (Plug)

Key patterns:
- Registry with `:duplicate` keys for broadcasting file changes to WebSocket clients
- DynamicSupervisor spawns one filesystem watcher per unique directory
- Theme stored in `:persistent_term` (shared across processes)
- IPC via `~/.inkwell/pid` and `~/.inkwell/port` files

## Conventions

- Elixir ~> 1.19, standard `mix format` style
- Escript distribution (`mix escript.build`, main module: `Inkwell.CLI`)
- Static assets in `priv/static/`
