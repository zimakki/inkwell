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
    file = Path.expand(file)

    unless File.exists?(file) do
      IO.puts("Error: file not found: #{file}")
      System.halt(1)
    end

    theme = Keyword.get(opts, :theme, "dark")
    {:ok, port} = Inkwell.Daemon.ensure_started(theme: theme)

    case http_get_json(
           "http://localhost:#{port}/open?path=#{URI.encode_www_form(file)}&theme=#{URI.encode_www_form(theme)}"
         ) do
      {:ok, payload} ->
        open_browser(payload["url"])
        IO.puts(payload["url"])

      {:error, reason} ->
        IO.puts("Failed to open preview: #{inspect(reason)}")
        System.halt(1)
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
    http_opts = [timeout: 5_000, connect_timeout: 3_000]

    case :httpc.request(:get, {String.to_charlist(url), []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, Jason.decode!(body)}
      other -> {:error, other}
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
