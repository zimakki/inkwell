defmodule Inkwell.Daemon do
  @moduledoc "Manages daemon lifecycle, port discovery, health checks, and idle shutdown."
  use GenServer
  require Logger

  @idle_timeout :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def client_connected, do: GenServer.cast(__MODULE__, :client_connected)
  def client_disconnected, do: GenServer.cast(__MODULE__, :client_disconnected)

  def status_info do
    GenServer.call(__MODULE__, :status_info)
  end

  def alive? do
    case read_port() do
      {:ok, port} ->
        case http_request(:get, "http://localhost:#{port}/health") do
          {:ok, 200, _body} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  def ensure_started(opts \\ []) do
    theme = Keyword.get(opts, :theme, "dark")

    if alive?() do
      {:ok, read_port!()}
    else
      cmd = daemon_command(theme)

      case System.cmd("sh", ["-c", cmd]) do
        {_out, 0} -> wait_until_alive()
        {out, code} -> {:error, {:spawn_failed, code, out}}
      end
    end
  end

  def stop do
    with {:ok, port} <- read_port(),
         {:ok, 200, _} <- http_request(:post, "http://localhost:#{port}/stop") do
      :ok
    else
      _ -> {:error, :not_running}
    end
  end

  def read_port do
    path = portfile()

    with true <- File.exists?(path),
         {:ok, content} <- File.read(path),
         {port, ""} <- Integer.parse(String.trim(content)) do
      {:ok, port}
    else
      _ -> {:error, :missing}
    end
  end

  def read_port! do
    {:ok, port} = read_port()
    port
  end

  def pidfile, do: Path.join(state_dir(), "pid")
  def portfile, do: Path.join(state_dir(), "port")
  def logfile, do: Path.join(state_dir(), "daemon.log")

  @impl true
  def init(_state) do
    File.mkdir_p!(state_dir())
    File.write!(pidfile(), System.pid())
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :refresh_port_info, 100)
    Logger.info("Daemon started (pid=#{System.pid()})")
    {:ok, %{port: nil, ws_count: 0, idle_timer: nil}}
  end

  @impl true
  def handle_call(:status_info, _from, state) do
    info = %{
      running: true,
      pid: System.pid(),
      port: state.port,
      websocket_clients: state.ws_count,
      watched_files: Inkwell.Watcher.watched_files()
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast(:client_connected, state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    {:noreply, %{state | ws_count: state.ws_count + 1, idle_timer: nil}}
  end

  @impl true
  def handle_cast(:client_disconnected, state) do
    ws_count = max(state.ws_count - 1, 0)

    state =
      if ws_count == 0 do
        %{
          state
          | ws_count: ws_count,
            idle_timer: Process.send_after(self(), :idle_shutdown, @idle_timeout)
        }
      else
        %{state | ws_count: ws_count}
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_port_info, state) do
    case bandit_pid() do
      nil ->
        Process.send_after(self(), :refresh_port_info, 100)
        {:noreply, state}

      pid ->
        case ThousandIsland.listener_info(pid) do
          {:ok, {_, port}} ->
            File.write!(portfile(), Integer.to_string(port))
            Logger.info("Listening on port #{port}")
            {:noreply, %{state | port: port}}

          _ ->
            Process.send_after(self(), :refresh_port_info, 100)
            {:noreply, state}
        end
    end
  end

  @impl true
  def handle_info(:idle_shutdown, state) do
    if state.ws_count == 0 do
      Logger.info(
        "Idle shutdown triggered (no WebSocket clients for #{div(@idle_timeout, 60_000)} minutes)"
      )

      System.stop(0)
    end

    {:noreply, %{state | idle_timer: nil}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(reason, _state) do
    Logger.info("Daemon shutting down (reason=#{inspect(reason)})")
    File.rm(pidfile())
    File.rm(portfile())
    :ok
  end

  defp wait_until_alive(deadline \\ System.monotonic_time(:millisecond) + 30_000) do
    cond do
      alive?() ->
        {:ok, read_port!()}

      System.monotonic_time(:millisecond) > deadline ->
        {:error, :timeout}

      true ->
        Process.sleep(100)
        wait_until_alive(deadline)
    end
  end

  defp state_dir do
    Path.join(System.user_home!(), ".inkwell")
  end

  defp current_executable do
    cond do
      (burrito_bin = System.get_env("__BURRITO_BIN_PATH")) && File.exists?(burrito_bin) ->
        burrito_bin

      burrito?() ->
        # In a Burrito release, resolve from /proc/self/exe or PATH
        System.find_executable("inkwell") ||
          raise "Unable to locate inkwell executable"

      (script = List.to_string(:escript.script_name())) != "" ->
        Path.expand(script, File.cwd!())

      File.exists?(Path.expand("_build/dev/bin/inkwell", File.cwd!())) ->
        Path.expand("_build/dev/bin/inkwell", File.cwd!())

      exec = System.find_executable("inkwell") ->
        exec

      true ->
        raise "Unable to locate inkwell executable"
    end
  end

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

  defp http_request(method, url) do
    # Ensure :inets/:ssl are started — needed in escript mode where app: nil
    # skips extra_applications. No-op when already running.
    :inets.start()
    :ssl.start()

    request =
      case method do
        :get -> {String.to_charlist(url), []}
        :post -> {String.to_charlist(url), [], ~c"application/json", ~c""}
      end

    http_opts = [timeout: 5_000, connect_timeout: 3_000]

    case :httpc.request(method, request, http_opts, body_format: :binary) do
      {:ok, {{_, status, _}, _headers, body}} -> {:ok, status, body}
      error -> error
    end
  end

  defp shell_escape(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp bandit_pid do
    Inkwell.Supervisor
    |> Supervisor.which_children()
    |> Enum.find_value(fn
      {Inkwell.BanditServer, pid, _type, _modules} -> pid
      _ -> nil
    end)
  end

  defp escript? do
    List.to_string(:escript.script_name()) != ""
  end

  defp burrito? do
    Inkwell.Application.release?() and not escript?()
  end

  defp project_root(exec) do
    candidates = [File.cwd!(), Path.dirname(exec)]

    Enum.find_value(candidates, :error, fn path ->
      if File.exists?(Path.join(path, "mix.exs")), do: {:ok, path}, else: false
    end)
  end
end
