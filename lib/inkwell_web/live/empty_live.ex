defmodule InkwellWeb.EmptyLive do
  @moduledoc "Empty state shown when no file is open."

  use InkwellWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    theme = :persistent_term.get(:inkwell_theme, "dark")

    {:ok,
     socket
     |> assign(theme: theme)
     |> assign(filename: nil)
     |> assign(rel_dir: "")
     |> assign(picker_open: false)
     |> assign(page_title: "Inkwell")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-ctn">
      <div class="empty-state">
        Open a file to get started
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("open_picker", _, socket), do: {:noreply, assign(socket, picker_open: true)}
  def handle_event("close_picker", _, socket), do: {:noreply, assign(socket, picker_open: false)}

  @impl true
  def handle_info({:picker_selected, path}, socket) do
    {:noreply, push_navigate(socket, to: ~p"/files?#{[path: path]}")}
  end
end
