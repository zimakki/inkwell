# Inkwell

[![CI](https://github.com/zimakki/inkwell/actions/workflows/ci.yml/badge.svg)](https://github.com/zimakki/inkwell/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-0.2.22-blue)](https://github.com/zimakki/inkwell/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A live markdown preview daemon for your terminal. Inkwell runs a lightweight background server that watches your markdown files and pushes real-time updates to a browser preview.

<!-- TODO: Add screenshot/GIF of the preview UI here -->

## Features

### Instant Live Preview

Save a file and see it in the browser immediately — no refresh needed. Inkwell pushes re-rendered HTML over WebSocket the moment a file changes on disk.

### Smart File Navigation

Hit `Ctrl+P` to open the file picker with fuzzy search across filenames, H1 titles, and file paths. Results are grouped into sections:

- **Recent** — your 20 most recently opened files
- **Sibling** — other `.md` files in the same directory
- **Repository** — every markdown file in the git repo, discovered automatically

Select any result to see a rendered preview before opening it.

### Rich Markdown Rendering

Full GitHub Flavored Markdown support including tables, task lists, strikethrough, autolinks, and footnotes. Plus:

- **Syntax highlighting** — theme-aware colors for code blocks (powered by [MDEx](https://github.com/leandrocp/mdex))
- **Mermaid diagrams** — fenced `mermaid` blocks render as diagrams automatically
- **Dark and light themes** — toggle anytime with `Ctrl+Shift+T`

### Lightweight Daemon Architecture

One server per user, shared across all your editors and terminals. The daemon starts on first use, binds to a random port, and shuts itself down after 10 minutes of inactivity. No configuration needed.

### Desktop App

A native macOS app built with Tauri. When installed, Inkwell opens previews in its own window via `inkwell://` deep links instead of your browser.

### Cross-Platform

Pre-built binaries for macOS (Apple Silicon + Intel) and Linux x86_64 via [Burrito](https://github.com/burrito-elixir/burrito) self-extracting releases.

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
| `Cmd+F` / `Ctrl+F` | Open find-in-document search |
| `Enter` / `Shift+Enter` | Next / previous match |
| `Ctrl+Shift+T` | Toggle dark/light theme |
| `Esc` | Close file picker / find bar |
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
mix test                       # Run tests (162 tests)
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

## Bonus: Neovim Integration

Add this to your Neovim config to preview markdown files with `<leader>mp` or the `:InkwellPreview` command:

```lua
local function preview_current_markdown()
  local cmd = vim.g.inkwell_cmd or "inkwell"
  local file = vim.fn.expand "%:p"

  local job_id = vim.fn.jobstart({ cmd, "preview", file }, { detach = true })

  if job_id <= 0 then
    vim.notify("Failed to start Inkwell. Is `" .. cmd .. "` installed and on your PATH?", vim.log.levels.ERROR)
  end
end

vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function(args)
    vim.api.nvim_buf_create_user_command(args.buf, "InkwellPreview", preview_current_markdown, {
      desc = "Preview the current markdown file in Inkwell",
    })

    vim.keymap.set("n", "<leader>mp", preview_current_markdown, {
      buffer = args.buf,
      desc = "Preview in Inkwell",
    })
  end,
})
```

Set `vim.g.inkwell_cmd` if your binary is installed somewhere other than `$PATH`.

## Thanks

Inkwell is built on top of some excellent open-source libraries:

- [MDEx](https://github.com/leandrocp/mdex) — fast Markdown-to-HTML with syntax highlighting, GFM, and more
- [Bandit](https://github.com/mtrudel/bandit) — pure Elixir HTTP server
- [Plug](https://github.com/elixir-plug/plug) — composable web middleware
- [WebSock](https://github.com/phoenixframework/websock) — WebSocket handling
- [FileSystem](https://github.com/falood/file_system) — cross-platform filesystem watcher
- [Burrito](https://github.com/burrito-elixir/burrito) — self-extracting binary releases for Elixir
- [Tauri](https://github.com/tauri-apps/tauri) — lightweight desktop app framework
- [Mermaid](https://github.com/mermaid-js/mermaid) — diagrams from text

## License

[MIT](LICENSE)

## Links

- [GitHub](https://github.com/zimakki/inkwell)
