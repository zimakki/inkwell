defmodule InkwellWeb.EmptyLive do
  @moduledoc "Empty state shown when no file is open."

  use InkwellWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    # Auto-open the picker via the shared Shell hook so picker_open's
    # source of truth stays in one place. send/2 dispatches after
    # on_mount has finished, where the :open_picker handler is wired.
    send(self(), :open_picker)

    {:ok,
     socket
     |> assign(filename: nil)
     |> assign(rel_dir: "")
     |> assign(page_title: "Inkwell")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-ctn"></div>
    """
  end
end
