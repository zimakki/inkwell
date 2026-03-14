defmodule Inkwell.CLI do
  @moduledoc "Command-line interface and escript entry point."
  require Logger

  def main(args) do
    {opts, rest, _invalid} =
      OptionParser.parse(args,
        strict: [theme: :string, help: :boolean, version: :boolean, check: :boolean],
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
            run_daemon(Keyword.get(opts, :theme, "dark"))

          ["preview", file] ->
            run_preview(file, opts)

          ["stop"] ->
            case Inkwell.Daemon.stop() do
              :ok -> IO.puts("inkwell daemon stopped")
              {:error, :not_running} -> IO.puts("inkwell daemon is not running")
            end

          ["status"] ->
            run_status()

          ["update"] ->
            run_update_command(Keyword.get(opts, :check, false))

          [] ->
            IO.puts(help_text())

          _ ->
            usage(1)
        end
    end
  end

  def run_daemon(theme) do
    Logger.info("Starting daemon with theme=#{theme}")
    :persistent_term.put(:inkwell_theme, theme)
    Application.ensure_all_started(:inkwell)
    Process.sleep(:infinity)
  end

  @doc "Called by Application.start/2 in client mode. Runs command and halts."
  def run_client_command(%{command: :preview, file: file, theme: theme}) do
    case preview(file, theme: theme) do
      {:ok, url, path} ->
        open_file(url, path)
        IO.puts(url)
        maybe_print_update_notice()
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
        maybe_print_update_notice()
        System.halt(0)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  def run_client_command(%{command: :help}) do
    IO.puts(help_text())
    System.halt(0)
  end

  def run_client_command(%{command: :version}) do
    IO.puts(version_string())
    System.halt(0)
  end

  def run_client_command(%{command: :update, check_only: check_only}) do
    run_update_command(check_only)
    System.halt(0)
  end

  def run_client_command(%{command: :usage}) do
    IO.puts(help_text())
    System.halt(0)
  end

  def run_client_command(_) do
    usage(1)
  end

  defp run_preview(file, opts) do
    case preview(file, opts) do
      {:ok, url, path} ->
        open_file(url, path)
        IO.puts(url)
        maybe_print_update_notice()

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  @doc false
  def browse(dir, opts, start_daemon \\ &Inkwell.Daemon.ensure_started/1) do
    dir = Path.expand(dir)

    cond do
      not File.exists?(dir) ->
        {:error, "directory not found: #{dir}"}

      not File.dir?(dir) ->
        {:error, "not a directory: #{dir}"}

      true ->
        theme = Keyword.get(opts, :theme, "dark")

        case start_daemon.(theme: theme) do
          {:error, reason} ->
            {:error, "failed to start inkwell daemon (#{inspect(reason)})"}

          {:ok, port} ->
            url =
              "http://localhost:#{port}/?dir=#{URI.encode_www_form(dir)}&theme=#{URI.encode_www_form(theme)}"

            {:ok, url}
        end
    end
  end

  @doc false
  def preview(file, opts, start_daemon \\ &Inkwell.Daemon.ensure_started/1) do
    file = Path.expand(file)

    if not File.exists?(file) do
      {:error, "file not found: #{file}"}
    else
      theme = Keyword.get(opts, :theme, "dark")

      case start_daemon.(theme: theme) do
        {:error, reason} ->
          {:error, "failed to start inkwell daemon (#{inspect(reason)})"}

        {:ok, port} ->
          case http_get_json(
                 "http://localhost:#{port}/open?path=#{URI.encode_www_form(file)}&theme=#{URI.encode_www_form(theme)}"
               ) do
            {:ok, payload} -> {:ok, payload["url"], file}
            {:error, reason} -> {:error, "failed to open preview: #{inspect(reason)}"}
          end
      end
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
      inkwell update [--check]       Check for updates or self-update
      inkwell stop                   Stop the daemon
      inkwell status                 Show daemon status

    Options:
      --theme dark|light             Set the theme (default: dark)
      --check                        Check for updates without installing
      --help, -h                     Show this help message
      --version, -v                  Show the version

    Examples:
      inkwell .                      Browse current directory
      inkwell ~/Documents            Browse a specific directory
      inkwell preview README.md      Preview README.md
      inkwell update --check         Check for a newer version\
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

  defp run_update_command(check_only) do
    result =
      if check_only do
        Inkwell.Updater.check()
      else
        Inkwell.Updater.update()
      end

    case result do
      {:update_available, %{current: current, latest: latest, install_method: :homebrew}} ->
        IO.puts("A new version of inkwell is available (#{current} -> #{latest}).")
        IO.puts("Run `#{Inkwell.Updater.brew_upgrade_command()}` to upgrade.")

      {:update_available, %{current: current, latest: latest}} ->
        IO.puts("A new version of inkwell is available (#{current} -> #{latest}).")

      {:up_to_date, %{current: current}} ->
        IO.puts("inkwell #{current} is already up to date.")

      {:homebrew, command} ->
        IO.puts("inkwell was installed with Homebrew.")
        IO.puts("Run `#{command}` to upgrade.")

      {:updated, %{current: current, latest: latest}} ->
        IO.puts("Updated inkwell from #{current} to #{latest}.")

      {:error, reason} ->
        IO.puts(:stderr, "Update failed: #{format_update_error(reason)}")
        System.halt(1)
    end
  end

  defp maybe_print_update_notice do
    with {:ok, %{latest: latest}} <- Inkwell.UpdateChecker.cached_info(),
         current <- Application.spec(:inkwell, :vsn) |> to_string(),
         :gt <- Version.compare(latest, current) do
      install_method =
        Inkwell.Updater.current_executable()
        |> Inkwell.Updater.install_method()

      message =
        case install_method do
          :homebrew ->
            "A new version of inkwell is available (#{current} -> #{latest}). Run '#{Inkwell.Updater.brew_upgrade_command()}' to upgrade."

          :direct ->
            "A new version of inkwell is available (#{current} -> #{latest}). Run `inkwell update` to upgrade."
        end

      IO.puts(:stderr, message)
    end
  rescue
    _ -> :ok
  end

  defp format_update_error({:missing_asset, name}), do: "release asset not found: #{name}"
  defp format_update_error({:missing_checksum, name}), do: "checksum not found for #{name}"
  defp format_update_error(:checksum_mismatch), do: "download checksum mismatch"
  defp format_update_error(:unsupported_platform), do: "unsupported platform"
  defp format_update_error(:missing_tag_name), do: "release metadata is missing tag_name"
  defp format_update_error(other), do: inspect(other)

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
