defmodule InkwellWeb.EmptyLive do
  @moduledoc "Empty state shown when no file is open."

  use InkwellWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(filename: nil)
     |> assign(rel_dir: "")
     |> assign(page_title: "Inkwell")
     |> assign(picker_open: true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-ctn"></div>
    """
  end
end
