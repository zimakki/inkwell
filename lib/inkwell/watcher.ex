defmodule Inkwell.Watcher do
  @moduledoc "Filesystem watcher that monitors directories and broadcasts file changes."
  use GenServer
  require Logger

  def start_link(opts) do
    dir = Keyword.fetch!(opts, :dir)
    GenServer.start_link(__MODULE__, dir)
  end

  def resolve_path(path) do
    expanded = Path.expand(path)

    case :file.read_link_all(String.to_charlist(expanded)) do
      {:ok, resolved} -> List.to_string(resolved)
      {:error, _} -> expanded
    end
  end

  def ensure_file(path) do
    path = resolve_path(path)
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
          {html, headings, alerts} = Inkwell.Renderer.render_with_nav(content)
          broadcast_nav(html, headings, alerts, path)

        {:error, reason} ->
          Logger.warning("Failed to read #{path}: #{inspect(reason)}")
      end
    end)
  end

  def broadcast_nav(html, headings, alerts, path) do
    payload =
      Jason.encode!(%{html: html, headings: headings, alerts: alerts})

    Registry.dispatch(Inkwell.Registry, {:ws_clients, path}, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:reload, payload})
    end)
  end

  @impl true
  def init(dir) do
    Registry.register(Inkwell.Registry, {:watcher, dir}, [])

    case FileSystem.start_link(dirs: [dir]) do
      {:ok, watcher} ->
        FileSystem.subscribe(watcher)
        Logger.info("Watching directory: #{dir}")
        {:ok, %{dir: dir, watcher: watcher, files: MapSet.new()}}

      {:error, reason} ->
        Logger.warning("File watcher unavailable for #{dir}: #{inspect(reason)}")
        {:ok, %{dir: dir, watcher: nil, files: MapSet.new()}}

      :ignore ->
        Logger.warning("File watcher unavailable for #{dir}: fs backend not supported")
        {:ok, %{dir: dir, watcher: nil, files: MapSet.new()}}
    end
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
    expanded = resolve_path(changed_path)

    if MapSet.member?(state.files, expanded) and
         Enum.any?(events, &(&1 in [:modified, :renamed, :created])) do
      Logger.debug("File changed: #{expanded}")

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
  def handle_info(_msg, state), do: {:noreply, state}
end
