# Inkwell

[![CI](https://github.com/zimakki/inkwell/actions/workflows/ci.yml/badge.svg)](https://github.com/zimakki/inkwell/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.2.12-blue)](https://github.com/zimakki/inkwell/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A live markdown preview daemon for your terminal. Inkwell runs a lightweight background server that watches your markdown files and pushes real-time updates to a browser preview.

<!-- TODO: Add screenshot/GIF of the preview UI here -->

## Features

- **Live preview** — edits appear in the browser instantly via WebSocket
- **File picker** — fuzzy search across recent and sibling files (`Ctrl+P`)
- **Directory browsing** — open any directory to browse and search its markdown files
- **Git repository search** — file picker discovers all `.md` files across your entire git repo
- **Dark/light themes** — toggle with `Ctrl+Shift+T`
- **Mermaid diagrams** — rendered automatically in fenced code blocks
- **Syntax highlighting** — code blocks highlighted with theme-aware colors
- **Desktop app** — native macOS app via Tauri with `inkwell://` deep links
- **Single daemon** — one server per user, shared across editors and terminals
- **Idle shutdown** — daemon stops after 10 minutes with no viewers
- **Cross-platform** — macOS (Apple Silicon + Intel) and Linux x86_64

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
MIX_ENV=prod mix release
```

The binary will be in `burrito_out/`. Move it to somewhere on your `$PATH`:

```bash
cp burrito_out/inkwell_darwin_arm64 ~/.local/bin/inkwell
```

## Quick Start

```bash
inkwell preview README.md     # Preview a single file
inkwell .                     # Browse markdown files in current directory
```

This starts the daemon (if not already running), opens the preview in the desktop app when installed or your browser otherwise, and watches for changes.

## Usage

```
inkwell <directory>            Open file picker for a directory
inkwell preview <file.md>      Preview a specific markdown file
inkwell stop                   Stop the daemon
inkwell status                 Show daemon status
```

### Options

```
--theme dark|light             Set the theme (default: dark)
--help, -h                     Show this help message
--version, -v                  Show the version
```

### Examples

```bash
inkwell .                                 # Browse current directory
inkwell ~/Documents                       # Browse a specific directory
inkwell preview README.md                 # Preview README.md
inkwell preview README.md --theme light   # Preview with light theme
```

The daemon starts automatically on first use and shuts down after 10 minutes of inactivity.

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
mix deps.get                   # Install dependencies
mix test                       # Run tests (120 tests)
mix format                     # Format code
mix compile --warnings-as-errors
MIX_ENV=prod mix release       # Build standalone binary (Burrito)
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/my-feature`)
3. Run tests and formatting (`mix test && mix format --check-formatted`)
4. Commit your changes
5. Open a pull request

Please ensure `mix compile --warnings-as-errors` passes before submitting.

## License

[MIT](LICENSE)

## Links

- [GitHub](https://github.com/zimakki/inkwell)
