defmodule InkwellWeb.PickerComponent do
  @moduledoc "File picker overlay: fuzzy-search + click-to-open. Toggled via parent's :picker_open assign."

  use InkwellWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:query, fn -> "" end)
     |> assign_new(:results, fn -> initial_results(assigns[:current_path]) end)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    raw =
      case socket.assigns.current_path do
        nil -> Inkwell.Search.list_recent()
        current -> Inkwell.Search.search(current, q)
      end

    {:noreply, assign(socket, query: q, results: flatten(raw))}
  end

  def handle_event("select", %{"path" => path}, socket) do
    send(self(), {:picker_selected, path})
    {:noreply, socket}
  end

  defp initial_results(nil), do: flatten(Inkwell.Search.list_recent())
  defp initial_results(current), do: flatten(Inkwell.Search.search(current, ""))

  defp flatten(%{recent: recent, siblings: siblings, repository: repo}) do
    repo_files = if repo, do: repo.files, else: []
    recent ++ siblings ++ repo_files
  end

  defp flatten(list) when is_list(list), do: list

  @impl true
  def render(assigns) do
    ~H"""
    <div id="picker-overlay" class={if @open, do: "open", else: ""}>
      <div id="picker">
        <form id="picker-search-form" phx-change="search" phx-target={@myself}>
          <span id="picker-search-icon">&#9906;</span>
          <input
            type="text"
            id="picker-input"
            name="q"
            placeholder="Search files and titles…"
            autocomplete="off"
            value={@query}
            phx-debounce="100"
          />
          <span class="hint">ESC to close</span>
        </form>
        <div id="picker-body">
          <div id="picker-list">
            <div
              :for={item <- @results}
              class="picker-item"
              data-path={item.path}
              phx-click="select"
              phx-value-path={item.path}
              phx-target={@myself}
            >
              <div class="picker-filename">{item.filename}</div>
              <div class="picker-path">{item.path}</div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
