defmodule Inkwell.CLI do
  @moduledoc "Command-line interface and escript entry point."
  require Logger

  def main(args) do
    {opts, rest, _invalid} =
      OptionParser.parse(args,
        strict: [
          theme: :string,
          mode: :string,
          help: :boolean,
          version: :boolean
        ],
        aliases: [h: :help, v: :version]
      )

    cond do
      opts[:help] ->
        IO.puts(help_text())

      opts[:version] ->
        IO.puts(version_string())

      true ->
        case rest do
          ["daemon"] ->
            run_daemon(opts[:theme])

          ["preview", file] ->
            emit_preview_deprecation_notice()
            run_preview(file, opts)

          ["stop"] ->
            case Inkwell.Daemon.stop() do
              :ok -> IO.puts("inkwell daemon stopped")
              {:error, :not_running} -> IO.puts("inkwell daemon is not running")
            end

          ["status"] ->
            run_status()

          [path] ->
            case Inkwell.Application.classify_path(path) do
              :file ->
                run_preview(path, opts)

              :directory ->
                case browse(path, opts) do
                  {:ok, url} ->
                    system_open_for_main(url)
                    IO.puts(url)

                  {:error, msg} ->
                    IO.puts("Error: #{msg}")
                    System.halt(1)
                end

              :not_found ->
                IO.puts(format_path_not_found(path))
                System.halt(1)
            end

          [] ->
            IO.puts(help_text())

          _ ->
            usage(1)
        end
    end
  end

  def run_daemon(theme) do
    # Pre-seed :persistent_term so anything reading before the supervision
    # tree finishes booting sees a value. Application.start/2 will overwrite
    # this with the resolved theme (explicit > persisted > "dark").
    if theme do
      :persistent_term.put(:inkwell_theme, theme)
      Inkwell.Settings.write_theme(theme)
    end

    Logger.info("Starting daemon with theme=#{theme || "(persisted)"}")
    Application.ensure_all_started(:inkwell)
    Process.sleep(:infinity)
  end

  @doc "Called by Application.start/2 in client mode. Runs command and halts."
  def run_client_command(%{command: :preview} = parsed) do
    case preview_with_deprecation_notice(parsed) do
      {:ok, url, path} ->
        open_file(url, path)
        IO.puts(url)
        System.halt(0)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  def run_client_command(%{command: :stop}) do
    :inets.start()
    :ssl.start()

    case Inkwell.Daemon.stop() do
      :ok -> IO.puts("inkwell daemon stopped")
      {:error, :not_running} -> IO.puts("inkwell daemon is not running")
    end

    System.halt(0)
  end

  def run_client_command(%{command: :status}) do
    :inets.start()
    :ssl.start()
    run_status()
    System.halt(0)
  end

  def run_client_command(%{command: :browse, dir: dir, theme: theme}) do
    case browse(dir, theme: theme) do
      {:ok, url} ->
        system_open(url)
        IO.puts(url)
        System.halt(0)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  def run_client_command(%{command: :path_not_found, path: path}) do
    IO.puts(format_path_not_found(path))
    System.halt(1)
  end

  def run_client_command(%{command: :help}) do
    IO.puts(help_text())
    System.halt(0)
  end

  def run_client_command(%{command: :version}) do
    IO.puts(version_string())
    System.halt(0)
  end

  def run_client_command(%{command: :usage}) do
    IO.puts(help_text())
    System.halt(0)
  end

  def run_client_command(_) do
    usage(1)
  end

  @doc false
  def format_path_not_found(path) do
    "Error: no such file or directory: #{path}"
  end

  @doc false
  # Shared helper: writes the deprecation notice (if applicable) and delegates
  # to preview/3. Extracted so the notice is testable without System.halt.
  def preview_with_deprecation_notice(parsed, start_daemon \\ &Inkwell.Daemon.ensure_started/1) do
    if Map.get(parsed, :deprecated, false) do
      emit_preview_deprecation_notice()
    end

    preview(parsed.file, [theme: parsed.theme], start_daemon)
  end

  defp emit_preview_deprecation_notice do
    IO.puts(
      :stderr,
      "warning: 'preview' is deprecated and will be removed in a future release; " <>
        "use 'inkwell <file>' instead"
    )
  end

  defp run_preview(file, opts) do
    case preview(file, opts) do
      {:ok, url, path} ->
        open_file(url, path)
        IO.puts(url)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  defp system_open_for_main(url), do: system_open(url)

  @doc false
  def browse(dir, opts, start_daemon \\ &Inkwell.Daemon.ensure_started/1) do
    dir = Path.expand(dir)

    cond do
      not File.exists?(dir) ->
        {:error, "directory not found: #{dir}"}

      not File.dir?(dir) ->
        {:error, "not a directory: #{dir}"}

      true ->
        theme = opts[:theme]

        case start_daemon.(theme: theme) do
          {:error, reason} ->
            {:error, "failed to start inkwell daemon (#{inspect(reason)})"}

          {:ok, port} ->
            effective_theme = theme || Inkwell.Settings.read_theme() || "dark"

            url =
              "http://localhost:#{port}/?dir=#{URI.encode_www_form(dir)}&theme=#{URI.encode_www_form(effective_theme)}"

            {:ok, url}
        end
    end
  end

  @doc false
  def preview(file, opts, start_daemon \\ &Inkwell.Daemon.ensure_started/1) do
    file = Path.expand(file)

    if File.exists?(file) do
      # nil = use the daemon's persisted theme; only forward an explicit value.
      theme = opts[:theme]

      case start_daemon.(theme: theme) do
        {:error, reason} ->
          {:error, "failed to start inkwell daemon (#{inspect(reason)})"}

        {:ok, port} ->
          # FileLive resolves the file, registers it with the watcher, and
          # subscribes to PubSub on mount — no preflight HTTP call needed.
          url = "http://localhost:#{port}/files?path=#{URI.encode_www_form(file)}"
          {:ok, url, file}
      end
    else
      {:error, "file not found: #{file}"}
    end
  end

  @doc """
  Determines whether to open in desktop app or browser.
  Accepts an optional check function for testing.
  """
  def open_target(check_fn \\ &desktop_app_installed?/0) do
    if check_fn.(), do: :desktop, else: :browser
  end

  @doc "Builds an inkwell:// deep link URL for the given file path."
  def deep_link_url(path) do
    "inkwell://open?path=#{URI.encode_www_form(path)}"
  end

  @doc """
  Opens a file in the desktop app (deep link) or falls back to browser.
  Accepts keyword options for dependency injection in tests.
  """
  def open_file(browser_url, file_path, opts \\ []) do
    check_fn = Keyword.get(opts, :check_fn, &desktop_app_installed?/0)
    open_fn = Keyword.get(opts, :open_fn, &system_open/1)

    case open_target(check_fn) do
      :desktop -> open_fn.(deep_link_url(file_path))
      :browser -> open_fn.(browser_url)
    end
  end

  defp run_status do
    if Inkwell.Daemon.alive?() do
      port = Inkwell.Daemon.read_port!()

      case http_get_json("http://localhost:#{port}/status") do
        {:ok, status} ->
          IO.puts("running: true")
          IO.puts("pid: #{status["pid"]}")
          IO.puts("port: #{status["port"]}")
          IO.puts("websocket_clients: #{status["websocket_clients"]}")

          watched =
            status["watched_files"]
            |> List.wrap()
            |> Enum.map(&"  - #{&1}")

          IO.puts("watched_files:")
          Enum.each(watched, &IO.puts/1)

        {:error, reason} ->
          IO.puts("Failed to read daemon status: #{inspect(reason)}")
          System.halt(1)
      end
    else
      IO.puts("running: false")
    end
  end

  @doc "Returns the help text for the CLI."
  def help_text do
    """
    Usage:
      inkwell <directory>            Open file picker for a directory
      inkwell preview <file.md>      Preview a specific markdown file
      inkwell stop                   Stop the daemon
      inkwell status                 Show daemon status

    Options:
      --theme dark|light             Set the theme (default: dark)
      --help, -h                     Show this help message
      --version, -v                  Show the version

    Examples:
      inkwell .                      Browse current directory
      inkwell ~/Documents            Browse a specific directory
      inkwell preview README.md      Preview README.md\
    """
  end

  @doc "Returns the version string in the format 'inkwell X.Y.Z'."
  def version_string do
    version = Application.spec(:inkwell, :vsn) |> to_string()
    "inkwell #{version}"
  end

  defp usage(exit_code) do
    IO.puts(help_text())
    System.halt(exit_code)
  end

  defp http_get_json(url) do
    :inets.start()
    :ssl.start()

    http_opts = [timeout: 5_000, connect_timeout: 3_000]

    case :httpc.request(:get, {String.to_charlist(url), []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} = err -> err
        end

      other ->
        {:error, other}
    end
  end

  @doc """
  Waits for the HTTP server at the given URL to accept TCP connections.
  Returns :ok on success or {:error, :timeout} if the server isn't ready.
  """
  def wait_for_server(url, opts \\ []) do
    uri = URI.parse(url)
    port = uri.port || 80
    retries = Keyword.get(opts, :retries, 50)
    delay = Keyword.get(opts, :delay, 100)

    do_wait_for_server(port, retries, delay)
  end

  defp do_wait_for_server(_port, 0, _delay), do: {:error, :timeout}

  defp do_wait_for_server(port, retries, delay) do
    case :gen_tcp.connect(~c"localhost", port, [], 200) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        Process.sleep(delay)
        do_wait_for_server(port, retries - 1, delay)
    end
  end

  defp desktop_app_installed? do
    case :os.type() do
      {:unix, :darwin} ->
        match?({_, 0}, System.cmd("open", ["-Ra", "Inkwell"], stderr_to_stdout: true))

      {:unix, _} ->
        case System.cmd("xdg-mime", ["query", "default", "x-scheme-handler/inkwell"],
               stderr_to_stdout: true
             ) do
          {output, 0} -> String.trim(output) != ""
          _ -> false
        end

      {:win32, _} ->
        case System.cmd("reg", ["query", "HKEY_CLASSES_ROOT\\inkwell"], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end
    end
  end

  defp system_open(url) do
    cond do
      exec = System.find_executable("open") ->
        Logger.debug("Opening: #{url}")
        System.cmd(exec, [url])

      exec = System.find_executable("xdg-open") ->
        Logger.debug("Opening: #{url}")
        System.cmd(exec, [url])

      exec = System.find_executable("cmd") ->
        Logger.debug("Opening: #{url}")
        System.cmd(exec, ["/c", "start", "", url])

      true ->
        Logger.warning("No open command found (open/xdg-open/cmd)")
        :ok
    end
  end
end
