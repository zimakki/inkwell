defmodule Inkwell.CLI do
  @moduledoc "Command-line interface and escript entry point."
  require Logger

  def main(args) do
    {opts, rest, _invalid} = OptionParser.parse(args, strict: [theme: :string])

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

      _ ->
        usage(1)
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
      {:ok, url} ->
        open_browser(url)
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
        open_browser(url)
        IO.puts(url)
        System.halt(0)

      {:error, msg} ->
        IO.puts("Error: #{msg}")
        System.halt(1)
    end
  end

  def run_client_command(%{command: :usage}) do
    usage(1)
  end

  def run_client_command(_) do
    usage(1)
  end

  defp run_preview(file, opts) do
    case preview(file, opts) do
      {:ok, url} ->
        open_browser(url)
        IO.puts(url)

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
            {:ok, payload} -> {:ok, payload["url"]}
            {:error, reason} -> {:error, "failed to open preview: #{inspect(reason)}"}
          end
      end
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

  defp usage(exit_code) do
    IO.puts("""
    Usage:
      inkwell <directory>            Open file picker for a directory
      inkwell preview <file.md>      Preview a specific markdown file
      inkwell stop                   Stop the daemon
      inkwell status                 Show daemon status

    Options:
      --theme dark|light             Set the theme (default: dark)

    Examples:
      inkwell .                      Browse current directory
      inkwell ~/Documents            Browse a specific directory
      inkwell preview README.md      Preview README.md
    """)

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

  defp open_browser(url) do
    cond do
      exec = System.find_executable("open") ->
        Logger.debug("Opening browser: #{url}")
        System.cmd(exec, [url])

      exec = System.find_executable("xdg-open") ->
        Logger.debug("Opening browser: #{url}")
        System.cmd(exec, [url])

      true ->
        Logger.warning("No browser command found (open/xdg-open)")
        :ok
    end
  end
end
