defmodule Inkwell.Watcher do
  @moduledoc "Filesystem watcher that monitors directories and broadcasts file changes."
  use GenServer
  require Logger

  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)
    GenServer.start_link(__MODULE__, dir, name: {:via, Registry, {Inkwell.WatcherRegistry, dir}})
  end

  def resolve_path(path) do
    path
    |> Path.expand()
    |> resolve_symlinks()
  end

  defp resolve_symlinks(path) do
    parts = Path.split(path)

    {init, rest} =
      case parts do
        ["/" | tail] -> {"/", tail}
        other -> {"", other}
      end

    Enum.reduce(rest, init, fn part, acc ->
      current = Path.join(acc, part)

      case :file.read_link(String.to_charlist(current)) do
        {:ok, target} ->
          target = List.to_string(target)

          full_target =
            if Path.type(target) == :absolute do
              target
            else
              Path.expand(target, acc)
            end

          # Recursively resolve — the target path may itself contain symlinks
          resolve_symlinks(full_target)

        {:error, _} ->
          current
      end
    end)
  end

  def ensure_file(path) do
    path = resolve_path(path)
    dir = Path.dirname(path)

    pid =
      case Registry.lookup(Inkwell.WatcherRegistry, dir) do
        [{pid, _}] ->
          pid

        [] ->
          spec = {__MODULE__, dir: dir}

          case DynamicSupervisor.start_child(Inkwell.WatcherSupervisor, spec) do
            {:ok, pid} -> pid
            {:error, {:already_started, pid}} -> pid
          end
      end

    GenServer.call(pid, {:watch_file, path, self()})
  end

  def watched_files do
    Inkwell.WatcherSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.flat_map(fn
      {_id, pid, _type, _modules} when is_pid(pid) -> GenServer.call(pid, :watched_files)
      _ -> []
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def rebroadcast_all do
    watched_files()
    |> Enum.each(fn path ->
      case File.read(path) do
        {:ok, content} ->
          {html, headings, alerts} = Inkwell.Renderer.render_with_nav(content)
          broadcast_nav(html, headings, alerts, path)

        {:error, reason} ->
          Logger.warning("Failed to read #{path}: #{inspect(reason)}")
      end
    end)
  end

  def broadcast_nav(html, headings, alerts, path) do
    payload_map = %{html: html, headings: headings, alerts: alerts}

    Phoenix.PubSub.broadcast(
      Inkwell.PubSub,
      "file:" <> path,
      {:reload, payload_map}
    )
  end

  @impl true
  def init(dir) do
    base = %{dir: dir, watcher: nil, files: %{}, refs: %{}}

    case FileSystem.start_link(dirs: [dir]) do
      {:ok, watcher} ->
        FileSystem.subscribe(watcher)
        Logger.info("Watching directory: #{dir}")
        {:ok, %{base | watcher: watcher}}

      {:error, reason} ->
        Logger.warning("File watcher unavailable for #{dir}: #{inspect(reason)}")
        {:ok, base}

      :ignore ->
        Logger.warning("File watcher unavailable for #{dir}: fs backend not supported")
        {:ok, base}
    end
  end

  @impl true
  def handle_call({:watch_file, path, subscriber}, _from, state) do
    state =
      state
      |> add_subscriber(path, subscriber)
      |> ensure_monitor(subscriber)

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:watched_files, _from, state) do
    {:reply, Map.keys(state.files), state}
  end

  defp add_subscriber(state, path, pid) do
    subscribers = Map.get(state.files, path, MapSet.new()) |> MapSet.put(pid)
    %{state | files: Map.put(state.files, path, subscribers)}
  end

  defp ensure_monitor(state, pid) do
    if Map.has_key?(state.refs, pid) do
      state
    else
      ref = Process.monitor(pid)
      %{state | refs: Map.put(state.refs, pid, ref)}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {changed_path, events}}, state) do
    expanded = resolve_path(changed_path)

    if Map.has_key?(state.files, expanded) and
         Enum.any?(events, &(&1 in [:modified, :renamed, :created])) do
      Logger.debug("File changed: #{expanded}")

      Inkwell.Search.invalidate_title(expanded)

      case File.read(expanded) do
        {:ok, content} ->
          {html, headings, alerts} = Inkwell.Renderer.render_with_nav(content)
          broadcast_nav(html, headings, alerts, expanded)

        {:error, reason} ->
          Logger.warning("Failed to read #{expanded}: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    files =
      state.files
      |> Enum.map(fn {path, subs} -> {path, MapSet.delete(subs, pid)} end)
      |> Enum.reject(fn {_path, subs} -> MapSet.size(subs) == 0 end)
      |> Map.new()

    refs = Map.delete(state.refs, pid)
    state = %{state | files: files, refs: refs}

    if map_size(files) == 0 do
      Logger.info("Watcher for #{state.dir} stopping — no remaining subscribers")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
