defmodule InkwellWeb.LiveHooks.Shell do
  @moduledoc "on_mount hook for live_session :shell — shared theme + picker state."

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_mount(:default, _params, _session, socket) do
    theme = :persistent_term.get(:inkwell_theme, "dark")

    if connected?(socket), do: Phoenix.PubSub.subscribe(Inkwell.PubSub, "theme")

    socket =
      socket
      |> assign(:theme, theme)
      |> assign(:picker_open, false)
      |> attach_hook(:shell_events, :handle_event, &handle_event/3)
      |> attach_hook(:shell_info, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  defp handle_event("toggle_theme", _params, socket) do
    current = socket.assigns.theme
    new = if current == "dark", do: "light", else: "dark"

    :persistent_term.put(:inkwell_theme, new)
    Phoenix.PubSub.broadcast(Inkwell.PubSub, "theme", {:theme_changed, new})
    Inkwell.Watcher.rebroadcast_all()

    {:halt, assign(socket, :theme, new)}
  end

  defp handle_event("open_picker", _, socket),
    do: {:halt, assign(socket, :picker_open, true)}

  defp handle_event("close_picker", _, socket),
    do: {:halt, assign(socket, :picker_open, false)}

  defp handle_event(_, _, socket), do: {:cont, socket}

  defp handle_info({:theme_changed, theme}, socket) do
    {:halt, assign(socket, :theme, theme)}
  end

  defp handle_info({:picker_selected, path}, socket) do
    {:halt, push_navigate(socket, to: "/files?#{URI.encode_query(path: path)}")}
  end

  defp handle_info(_, socket), do: {:cont, socket}
end
