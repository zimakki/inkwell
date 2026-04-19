defmodule InkwellWeb.BrowseLive do
  @moduledoc "Folder browse mode: lists markdown files under a given directory and filters as the user types."

  use InkwellWeb, :live_view

  @impl true
  def mount(%{"dir" => dir}, _session, socket) do
    dir = Path.expand(dir)
    files = Inkwell.Search.search_directory(dir, "")

    {:ok,
     socket
     |> assign(filename: nil)
     |> assign(rel_dir: dir)
     |> assign(dir: dir)
     |> assign(files: files)
     |> assign(query: "")
     |> assign(page_title: "Browse #{Path.basename(dir)}")}
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    files = Inkwell.Search.search_directory(socket.assigns.dir, q)
    {:noreply, assign(socket, files: files, query: q)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-ctn">
      <div class="browse-view">
        <form phx-change="search">
          <input
            type="text"
            name="q"
            placeholder="Search files in this folder"
            autocomplete="off"
            phx-debounce="150"
            value={@query}
          />
        </form>
        <ul class="file-list">
          <li :for={file <- @files} class="file-item">
            <.link navigate={~p"/files?#{[path: file.path]}"}>
              {file.filename}
            </.link>
          </li>
        </ul>
      </div>
    </div>
    """
  end
end
