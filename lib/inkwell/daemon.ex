defmodule Inkwell.Daemon do
  @moduledoc "Manages daemon lifecycle, port discovery, health checks, and idle shutdown."
  use GenServer
  require Logger

  @idle_timeout :timer.minutes(10)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Register the calling process as a connected client. The Daemon monitors
  the caller and automatically removes it when the process exits (covers
  both graceful LiveView terminate AND abrupt browser-close disconnects).
  """
  def client_connected, do: GenServer.call(__MODULE__, {:client_connected, self()})

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
    # nil = caller didn't explicitly request a theme; let the spawned daemon
    # fall back to its persisted preference.
    theme = Keyword.get(opts, :theme)

    File.mkdir_p!(state_dir())
    cleanup_stale_state()

    if alive?() do
      {:ok, read_port!()}
    else
      spawn_with_lock(theme)
    end
  end

  defp cleanup_stale_state do
    cleanup_stale_pidfile()
    cleanup_stale_lockfile()
  end

  defp cleanup_stale_pidfile do
    with {:ok, content} <- File.read(pidfile()),
         pid <- String.trim(content),
         false <- pid_alive?(pid) do
      File.rm(pidfile())
      File.rm(portfile())
    else
      _ -> :ok
    end
  end

  defp cleanup_stale_lockfile do
    case File.stat(lockfile(), time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        if System.os_time(:second) - mtime > 60, do: File.rm(lockfile())

      _ ->
        :ok
    end
  end

  defp spawn_with_lock(theme) do
    case File.open(lockfile(), [:write, :exclusive]) do
      {:ok, file} ->
        try do
          do_spawn(theme)
        after
          File.close(file)
          File.rm(lockfile())
        end

      {:error, :eexist} ->
        # Another invocation is mid-spawn (lockfile exists, < 60s old).
        # Wait for that daemon to come up rather than racing it.
        wait_until_alive()
    end
  end

  defp do_spawn(theme) do
    cmd = daemon_command(theme)

    case System.cmd("sh", ["-c", cmd]) do
      {_out, 0} -> wait_until_alive()
      {out, code} -> {:error, {:spawn_failed, code, out}}
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
  def lockfile, do: Path.join(state_dir(), "starting")

  @doc """
  Returns `true` when the given OS pid (binary) is running. Used to
  detect stale pidfiles left behind by SIGKILL or power loss.
  """
  def pid_alive?(pid) when is_binary(pid) do
    case Integer.parse(pid) do
      {n, ""} when n > 0 ->
        case System.cmd("kill", ["-0", pid], stderr_to_stdout: true) do
          {_, 0} -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  def pid_alive?(_), do: false

  @impl true
  def init(_state) do
    File.mkdir_p!(state_dir())
    File.write!(pidfile(), System.pid())
    Process.flag(:trap_exit, true)
    Process.send_after(self(), :refresh_port_info, 100)
    Logger.info("Daemon started (pid=#{System.pid()})")
    {:ok, %{port: nil, clients: %{}, idle_timer: nil, port_deadline: nil}}
  end

  @impl true
  def handle_call(:status_info, _from, state) do
    info = %{
      running: true,
      pid: System.pid(),
      port: state.port,
      websocket_clients: map_size(state.clients),
      watched_files: Inkwell.Watcher.watched_files()
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call({:client_connected, pid}, _from, state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    ref = Process.monitor(pid)
    {:reply, :ok, %{state | clients: Map.put(state.clients, ref, pid), idle_timer: nil}}
  end

  @impl true
  def handle_info(:refresh_port_info, state) do
    state = ensure_deadline(state, :port_deadline)

    case InkwellWeb.Endpoint.server_info(:http) do
      {:ok, {_ip, port}} when is_integer(port) and port > 0 ->
        File.write!(portfile(), Integer.to_string(port))
        Logger.info("Listening on port #{port}")
        {:noreply, %{state | port: port, port_deadline: nil}}

      _ ->
        schedule_retry_or_give_up(state, :refresh_port_info, :port_deadline, "Phoenix Endpoint")
    end
  end

  @impl true
  def handle_info(:idle_shutdown, state) do
    if map_size(state.clients) == 0 do
      Logger.info(
        "Idle shutdown triggered (no live clients for #{div(@idle_timeout, 60_000)} minutes)"
      )

      System.stop(0)
    end

    {:noreply, %{state | idle_timer: nil}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.clients, ref) do
      {nil, _} ->
        {:noreply, state}

      {_pid, clients} ->
        state =
          if map_size(clients) == 0 do
            %{
              state
              | clients: clients,
                idle_timer: Process.send_after(self(), :idle_shutdown, @idle_timeout)
            }
          else
            %{state | clients: clients}
          end

        {:noreply, state}
    end
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

  defp ensure_deadline(state, key) do
    if Map.get(state, key) do
      state
    else
      Map.put(state, key, System.monotonic_time(:millisecond) + 30_000)
    end
  end

  defp schedule_retry_or_give_up(state, message, deadline_key, label) do
    if System.monotonic_time(:millisecond) > Map.fetch!(state, deadline_key) do
      Logger.error("#{label} failed to bind within 30s; giving up port discovery")
      {:noreply, Map.put(state, deadline_key, nil)}
    else
      Process.send_after(self(), message, 100)
      {:noreply, state}
    end
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
    theme_flag = if theme, do: " --theme #{shell_escape(theme)}", else: ""
    mix_theme_arg = if theme, do: ~s|"#{theme}"|, else: "nil"

    cond do
      burrito?() or escript?() ->
        "nohup #{shell_escape(exec)} daemon#{theme_flag} >>#{shell_escape(logfile())} 2>&1 &"

      match?({:ok, _}, project_root(exec)) ->
        {:ok, root} = project_root(exec)

        "cd #{shell_escape(root)} && nohup mix run --no-halt -e 'Inkwell.CLI.run_daemon(#{mix_theme_arg})' >>#{shell_escape(logfile())} 2>&1 &"

      true ->
        "nohup #{shell_escape(exec)} daemon#{theme_flag} >>#{shell_escape(logfile())} 2>&1 &"
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
