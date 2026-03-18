defmodule Inkwell.WsHandler do
  @moduledoc "WebSocket handler that receives file updates and pushes them to browser clients."
  @behaviour WebSock
  require Logger

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path) |> Path.expand()
    Registry.register(Inkwell.Registry, {:ws_clients, path}, [])
    Inkwell.Watcher.ensure_file(path)
    Inkwell.Daemon.client_connected()
    Logger.debug("WebSocket connected for #{path}")
    {html, headings, alerts} = path |> File.read!() |> Inkwell.Renderer.render_with_nav()
    payload = Jason.encode!(%{html: html, headings: headings, alerts: alerts})
    {:push, {:text, payload}, %{path: path}}
  end

  @impl true
  def handle_in({"ping", _opts}, state), do: {:push, {:text, "pong"}, state}
  def handle_in(_message, state), do: {:ok, state}

  @impl true
  def handle_info({:reload, html}, state) do
    {:push, {:text, html}, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    Logger.debug("WebSocket disconnected for #{state.path}")
    Inkwell.Daemon.client_disconnected()
    :ok
  end
end
