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
      inkwell preview <file.md> [--theme dark]
      inkwell stop
      inkwell status
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
