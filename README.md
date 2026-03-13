# Inkwell

A live markdown preview daemon for your terminal. Inkwell runs a lightweight background server that watches your markdown files and pushes real-time updates to a browser preview.

<!-- TODO: Add screenshot/GIF of the preview UI here -->

## Features

- **Live preview** — edits appear in the browser instantly via WebSocket
- **File picker** — fuzzy search across recent and sibling files (`Ctrl+P`)
- **Dark/light themes** — toggle with `Ctrl+Shift+T`
- **Mermaid diagrams** — rendered automatically in fenced code blocks
- **Single daemon** — one server per user, shared across editors and terminals
- **Idle shutdown** — daemon stops after 10 minutes with no viewers
- **Syntax highlighting** — code blocks highlighted with theme-aware colors

## Installation

### Homebrew Desktop App (macOS)

```bash
brew tap zimakki/tap
brew install --cask inkwell
```

### Homebrew CLI (macOS/Linux)

```bash
brew tap zimakki/tap
brew install inkwell
```

### From Source

Requires Elixir ~> 1.19.

```bash
git clone https://github.com/zimakki/inkwell.git
cd inkwell
mix deps.get
mix escript.build
```

Move the `inkwell` binary to somewhere in your `$PATH`:

```bash
cp inkwell ~/.local/bin/
```

## Quick Start

```bash
inkwell preview README.md
```

This starts the daemon (if not already running), opens the preview in the desktop app when installed or your browser otherwise, and watches the file for changes.

## Usage

```
inkwell preview <file.md> [--theme dark|light]   # Open live preview
inkwell status                                    # Show daemon info
inkwell stop                                      # Stop the daemon
```

The default theme is `dark`. The daemon starts automatically on `preview` and shuts down after 10 minutes of inactivity.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+P` | Open file picker |
| `Ctrl+Shift+T` | Toggle dark/light theme |
| `Esc` | Close file picker |
| `Up/Down` | Navigate file list |
| `Enter` | Open selected file |

## How It Works

Inkwell runs as an OTP application with a supervision tree:

```
Inkwell.Supervisor
├── Registry          — pub/sub for per-file WebSocket clients
├── History           — tracks recently opened files
├── Daemon            — manages lifecycle, PID/port files, idle shutdown
├── WatcherSupervisor — spawns one filesystem watcher per directory
│   └── Watcher       — monitors files, broadcasts changes
└── Bandit            — HTTP server (dynamic port)
    ├── Router        — serves HTML, JSON APIs, static assets
    └── WsHandler     — WebSocket handler for live updates
```

When you run `inkwell preview file.md`:

1. The CLI ensures the daemon is running (spawns it if needed)
2. The file is registered with the daemon via HTTP
3. A filesystem watcher starts for the file's directory
4. The browser opens the preview page
5. A WebSocket connection pushes re-rendered HTML on every file save

State files live in `~/.inkwell/` (pid, port). The daemon binds to a random port to avoid conflicts.

## Development

```bash
mix deps.get          # Install dependencies
mix test              # Run tests (44 tests)
mix format            # Format code
mix escript.build     # Build standalone binary
```

## License

MIT
