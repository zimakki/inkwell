defmodule Inkwell.Watcher do
  @moduledoc "Filesystem watcher that monitors directories and broadcasts file changes."
  use GenServer
  require Logger

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
      case File.read(path) do
        {:ok, content} ->
          content |> Inkwell.Renderer.render() |> broadcast(path)

        {:error, reason} ->
          Logger.warning("Failed to read #{path}: #{inspect(reason)}")
      end
    end)
  end

  def broadcast(html, path) do
    Registry.dispatch(Inkwell.Registry, {:ws_clients, path}, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:reload, html})
    end)
  end

  @impl true
  def init(dir) do
    Registry.register(Inkwell.Registry, {:watcher, dir}, [])
    {:ok, watcher} = FileSystem.start_link(dirs: [dir])
    FileSystem.subscribe(watcher)
    Logger.info("Watching directory: #{dir}")
    {:ok, %{dir: dir, watcher: watcher, files: MapSet.new()}}
  end

  @impl true
  def handle_call({:watch_file, path}, _from, state) do
    {:reply, :ok, %{state | files: MapSet.put(state.files, path)}}
  end

  @impl true
  def handle_call(:watched_files, _from, state) do
    {:reply, MapSet.to_list(state.files), state}
  end

  @impl true
  def handle_info({:file_event, _pid, {changed_path, events}}, state) do
    expanded = Path.expand(changed_path)

    if MapSet.member?(state.files, expanded) and :modified in events do
      Logger.debug("File changed: #{expanded}")

      case File.read(expanded) do
        {:ok, content} ->
          content |> Inkwell.Renderer.render() |> broadcast(expanded)

        {:error, reason} ->
          Logger.warning("Failed to read #{expanded}: #{inspect(reason)}")
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
