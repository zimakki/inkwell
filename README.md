# Inkwell

Inkwell is a standalone live markdown preview daemon extracted from a working single-file Elixir script.

It keeps one long-running server process per user, serves a browser preview UI, watches markdown files for changes, and lets multiple editors or terminals talk to the same daemon.

## Commands

```bash
inkwell preview path/to/file.md --theme dark
inkwell status
inkwell stop
```

`preview` ensures the daemon is running, registers the file with the daemon, and opens the browser preview.

## Development

```bash
mix deps.get
mix compile
mix test
mix escript.build
```

## Architecture

- `Inkwell.Application` starts the OTP supervision tree.
- `Inkwell.Daemon` manages `~/.inkwell/pid`, `~/.inkwell/port`, health checks, and idle shutdown.
- `Inkwell.Watcher` runs one filesystem watcher per directory under a `DynamicSupervisor`.
- `Inkwell.Router` serves the HTML preview shell, search endpoints, health/status routes, and websocket upgrade.
- `Inkwell.WsHandler` tracks websocket clients per markdown file so updates only go to relevant browser tabs.
- `priv/static/markdown-wide.css` is copied from the original Neovim integration.
