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
     |> assign(page_title: "Inkwell")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="empty-state">
      Open a file to get started
    </div>
    """
  end
end
