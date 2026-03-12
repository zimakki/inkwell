defmodule Inkwell.Watcher do
  use GenServer

  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)
    GenServer.start_link(__MODULE__, dir)
  end

  def ensure_file(path) do
    path = Path.expand(path)
    dir = Path.dirname(path)

    case Registry.lookup(Inkwell.Registry, {:watcher, dir}) do
      [{pid, _}] ->
        GenServer.call(pid, {:watch_file, path})

      [] ->
        spec = {__MODULE__, dir: dir}
        {:ok, pid} = DynamicSupervisor.start_child(Inkwell.WatcherSupervisor, spec)
        GenServer.call(pid, {:watch_file, path})
    end
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
      path |> File.read!() |> Inkwell.Renderer.render() |> broadcast(path)
    end)
  end

  def broadcast(path, html) do
    Registry.dispatch(Inkwell.Registry, {:ws_clients, path}, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:reload, html})
    end)
  end

  @impl true
  def init(dir) do
    Registry.register(Inkwell.Registry, {:watcher, dir}, [])
    {:ok, watcher} = FileSystem.start_link(dirs: [dir])
    FileSystem.subscribe(watcher)
    {:ok, %{dir: dir, watcher: watcher, files: MapSet.new()}}
  end

  @impl true
  def handle_call({:watch_file, path}, _from, state) do
    {:reply, :ok, %{state | files: MapSet.put(state.files, path)}}
  end

  def handle_call(:watched_files, _from, state) do
    {:reply, MapSet.to_list(state.files), state}
  end

  @impl true
  def handle_info({:file_event, _pid, {changed_path, events}}, state) do
    expanded = Path.expand(changed_path)

    if MapSet.member?(state.files, expanded) and :modified in events do
      expanded |> File.read!() |> Inkwell.Renderer.render() |> broadcast(expanded)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
