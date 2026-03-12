# Burrito Distribution Design

## Context

Inkwell is distributed as an escript built on Linux CI (Ubuntu). It depends on two packages with native code:

- **mdex** (Rust NIF via RustlerPrecompiled) — markdown parsing and syntax highlighting
- **file_system** (`mac_listener` C binary) — filesystem watching on macOS

Escripts fundamentally cannot load NIFs — the BEAM cannot resolve filesystem paths for `.so`/`.dylib` files inside a zip archive. This means the Linux-built escript ships Linux NIFs that fail on macOS, and even a macOS-built escript would fail to load them at runtime.

The fix is to switch from escript to Burrito, which wraps a `mix release` into a self-extracting binary that bundles ERTS and all `priv/` directories. NIFs just work because the payload is extracted to a real filesystem path.

## Targets

- `darwin_arm64` — macOS Apple Silicon
- `darwin_amd64` — macOS Intel
- `linux_amd64` — Linux x86_64
- `linux_arm64` — Linux aarch64

## Changes

### 1. mix.exs

Add Burrito dependency and release configuration:

```elixir
{:burrito, "~> 1.0", only: [:dev, :prod]}
```

Add `releases/0` to `project/0`:

```elixir
releases: releases()
```

```elixir
defp releases do
  [
    inkwell: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          darwin_arm64: [os: :darwin, cpu: :aarch64],
          darwin_amd64: [os: :darwin, cpu: :x86_64],
          linux_amd64: [os: :linux, cpu: :x86_64],
          linux_arm64: [os: :linux, cpu: :aarch64]
        ]
      ]
    ]
  ]
end
```

Remove the `escript` config from `project/0` to avoid confusion — it produces a binary that can't load NIFs and shouldn't be used for distribution. Developers should use `mix run --no-halt` instead.

### 2. CLI Entry Point — Conditional Supervision Tree

Burrito uses `mix release` which starts the OTP app via `Inkwell.Application`. The current escript entry point (`main/1`) won't be called. Instead, CLI args come from `:init.get_plain_arguments()`.

**Critical design decision:** Client commands (`preview`, `stop`, `status`) must NOT start the full supervision tree. They are HTTP clients that talk to an already-running daemon. Starting Bandit, Registry, Daemon GenServer, etc. would conflict with the running daemon instance (PID/port file collisions, port binding conflicts).

Modify `Application.start/2` to parse args first and conditionally choose children:

```elixir
def start(_type, _args) do
  args = :init.get_plain_arguments() |> Enum.map(&List.to_string/1)
  {mode, parsed_args} = parse_mode(args)

  children = case mode do
    :daemon ->
      # Full supervision tree — this IS the daemon
      :persistent_term.put(:inkwell_theme, parsed_args[:theme] || "dark")
      [
        {Registry, keys: :duplicate, name: Inkwell.Registry},
        {Inkwell.History, []},
        {Inkwell.Daemon, []},
        {DynamicSupervisor, strategy: :one_for_one, name: Inkwell.WatcherSupervisor},
        Supervisor.child_spec({Bandit, plug: Inkwell.Router, port: 0}, id: Inkwell.BanditServer)
      ]

    :client ->
      # Minimal tree — just need :inets/:ssl for HTTP calls
      :inets.start()
      :ssl.start()
      []
  end

  {:ok, pid} = Supervisor.start_link(children, strategy: :one_for_one, name: Inkwell.Supervisor)

  # For client commands, run the command then halt
  case mode do
    :client -> Inkwell.CLI.run_client_command(parsed_args)
    :daemon -> :ok
  end

  {:ok, pid}
end
```

The `run_client_command/1` function handles `preview`, `stop`, `status`, and `usage`, calling `System.halt()` when done. For daemon mode, the release keeps the VM alive (no `Process.sleep(:infinity)` needed).

### 3. Update run_daemon/1

The current `CLI.run_daemon/1` calls `Application.ensure_all_started(:inkwell)` because in escript mode, the OTP app is not auto-started. In a Burrito release, the application is already started by the boot script. This function becomes unnecessary for Burrito — the supervision tree starts in `Application.start/2` based on the CLI args.

Remove `run_daemon/1` or keep it as a no-op fallback for the `mix run -e` dev path. The dev path (`mix run --no-halt -e 'Inkwell.CLI.run_daemon("dark")'`) still needs it, but the release path does not.

### 4. Daemon Executable Detection

Update `current_executable/0` in `Inkwell.Daemon` to detect Burrito:

```elixir
defp current_executable do
  cond do
    # Burrito binary
    (burrito_bin = System.get_env("BURRITO_BIN_PATH")) && File.exists?(burrito_bin) ->
      burrito_bin

    # Escript (legacy, dev)
    (script = List.to_string(:escript.script_name())) != "" ->
      Path.expand(script, File.cwd!())

    # Dev build
    File.exists?(Path.expand("_build/dev/bin/inkwell", File.cwd!())) ->
      Path.expand("_build/dev/bin/inkwell", File.cwd!())

    # PATH lookup
    exec = System.find_executable("inkwell") ->
      exec

    true ->
      raise "Unable to locate inkwell executable"
  end
end
```

The `BURRITO_BIN_PATH` env var is set by the Burrito wrapper and points to the original binary on disk. The `File.exists?` guard protects against stale paths if the binary was moved.

Update `daemon_command/1` to add a Burrito detection path:

```elixir
defp daemon_command(theme) do
  exec = current_executable()

  cond do
    burrito?() or escript?() ->
      "nohup #{shell_escape(exec)} daemon --theme #{shell_escape(theme)} >>#{shell_escape(logfile())} 2>&1 &"

    match?({:ok, _}, project_root(exec)) ->
      {:ok, root} = project_root(exec)
      "cd #{shell_escape(root)} && nohup mix run --no-halt -e 'Inkwell.CLI.run_daemon(\"#{theme}\")' >>#{shell_escape(logfile())} 2>&1 &"

    true ->
      "nohup #{shell_escape(exec)} daemon --theme #{shell_escape(theme)} >>#{shell_escape(logfile())} 2>&1 &"
  end
end

defp burrito? do
  System.get_env("BURRITO_BIN_PATH") != nil
end
```

**Daemon cold-start note:** The first invocation of a Burrito binary extracts the payload to `~/.cache/burrito/` (or platform equivalent). Subsequent runs of the same version skip extraction. The daemon's `wait_until_alive` timeout (30s) should be sufficient, but the first-run extraction delay should be expected.

### 5. Release Workflow — Per-Platform CI Matrix

Use per-platform runners instead of cross-compilation from a single host. This avoids NIF target selection issues — RustlerPrecompiled downloads NIFs based on the host's `:erlang.system_info(:system_architecture)`, which won't match the cross-compilation target.

```yaml
jobs:
  tag:
    # ... unchanged — extract version, create tag on branch push ...

  build:
    needs: [tag]
    if: # ... same condition as before ...
    strategy:
      matrix:
        include:
          - os: macos-14        # ARM
            target: darwin_arm64
          - os: macos-13        # Intel
            target: darwin_amd64
          - os: ubuntu-latest
            target: linux_amd64
          - os: ubuntu-24.04-arm  # ARM runner
            target: linux_arm64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: "1.19"
          otp-version: "27"
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.15.2  # Pinned — Burrito 1.5.0 requires this version
      - run: mix deps.get --only prod
        env: { MIX_ENV: prod }
      - run: mix release
        env:
          MIX_ENV: prod
          BURRITO_TARGET: ${{ matrix.target }}
      - uses: actions/upload-artifact@v4
        with:
          name: inkwell_${{ matrix.target }}
          path: burrito_out/inkwell_${{ matrix.target }}

  release:
    needs: [tag, build]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
      - name: Compute SHA256s
        run: |
          for f in inkwell_*/inkwell_*; do
            name=$(basename "$f")
            sha=$(sha256sum "$f" | awk '{print $1}')
            echo "${name}_sha256=$sha" >> "$GITHUB_OUTPUT"
          done
        id: sha
      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ needs.tag.outputs.version }}
          files: inkwell_*/inkwell_*
          # ... release body ...

  update-tap:
    needs: [tag, release]
    # ... update formula with per-platform SHA256 values ...
```

Each runner builds only its native target with `BURRITO_TARGET`, ensuring RustlerPrecompiled downloads the correct NIF and `file_system` compiles `mac_listener` only on macOS.

### 6. Homebrew Formula

Update formula to download the prebuilt binary for the user's platform:

```ruby
class Inkwell < Formula
  desc "Live markdown preview daemon"
  homepage "https://github.com/zimakki/inkwell"
  license "MIT"
  version "__VERSION__"

  on_macos do
    on_arm do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_darwin_arm64"
      sha256 "__SHA256_DARWIN_ARM64__"
    end
    on_intel do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_darwin_amd64"
      sha256 "__SHA256_DARWIN_AMD64__"
    end
  end

  on_linux do
    on_arm do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_linux_arm64"
      sha256 "__SHA256_LINUX_ARM64__"
    end
    on_intel do
      url "https://github.com/zimakki/inkwell/releases/download/v__VERSION__/inkwell_linux_amd64"
      sha256 "__SHA256_LINUX_AMD64__"
    end
  end

  # No runtime dependencies — ERTS is bundled by Burrito
  def install
    bin.install Dir.glob("inkwell*").first => "inkwell"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/inkwell 2>&1", 1)
  end
end
```

Key changes:
- **No `depends_on "erlang"`** — Burrito bundles the runtime
- Platform-conditional URLs with per-platform SHA256
- `Dir.glob` for safe binary installation
- Preserves `desc`, `homepage`, `license` fields

The `update-tap` job needs `sed` commands for all 5 placeholders (`__VERSION__`, `__SHA256_DARWIN_ARM64__`, `__SHA256_DARWIN_AMD64__`, `__SHA256_LINUX_ARM64__`, `__SHA256_LINUX_AMD64__`).

### 7. Remove Escript Build

- Remove `escript` config from `mix.exs`
- Remove `mix escript.build` from CI workflow
- Update README install instructions
- Developers use `mix run --no-halt` for local dev

## What Does NOT Change

- All application code (router, watcher, WebSocket handler, renderer, history, search)
- Supervision tree structure (just conditionally started)
- Daemon lifecycle (PID/port files, idle shutdown, health checks)
- `mix run` development workflow
- Test suite

## Verification

1. `BURRITO_TARGET=darwin_arm64 MIX_ENV=prod mix release` produces binary in `burrito_out/`
2. `./burrito_out/inkwell_darwin_arm64 preview README.md` works on macOS ARM
3. `./burrito_out/inkwell_darwin_arm64 daemon --theme dark` starts the daemon
4. Daemon spawning via re-exec works (`nohup inkwell daemon &`)
5. `inkwell stop` and `inkwell status` work as client commands (no full tree)
6. File watching works (`mac_listener` accessible from extracted payload)
7. MDEx rendering works (NIF loads from extracted `priv/native/`)
8. `mix test` still passes
9. CI matrix builds all 4 targets and creates GitHub Release
10. `brew update && brew upgrade inkwell` installs correct platform binary
11. No Erlang runtime required on user machine

## Files to Modify

- `mix.exs` — add Burrito dep, releases config, remove escript config
- `lib/inkwell/application.ex` — conditional supervision tree based on CLI args
- `lib/inkwell/cli.ex` — refactor into client command runner, update/remove `run_daemon/1`
- `lib/inkwell/daemon.ex` — add Burrito detection to `current_executable/0` and `daemon_command/1`
- `.github/workflows/release.yml` — per-platform matrix build with Burrito
- `.github/formula-template.rb` — platform-conditional binary download, remove erlang dep
