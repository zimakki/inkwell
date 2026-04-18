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
    results =
      case socket.assigns.current_path do
        nil -> Inkwell.Search.list_recent()
        current -> Inkwell.Search.search(current, q)
      end

    {:noreply, assign(socket, query: q, results: results)}
  end

  def handle_event("select", %{"path" => path}, socket) do
    send(self(), {:picker_selected, path})
    {:noreply, socket}
  end

  defp initial_results(nil), do: Inkwell.Search.list_recent()
  defp initial_results(current), do: Inkwell.Search.search(current, "")

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
            <.section title="Recent" items={@results.recent} myself={@myself} />
            <.section title="In this folder" items={@results.siblings} myself={@myself} />
            <.section
              :if={@results.repository}
              title={@results.repository.name}
              items={@results.repository.files}
              myself={@myself}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :myself, :any, required: true

  defp section(assigns) do
    ~H"""
    <div :if={@items != []} class="picker-section">
      <div class="picker-section-title">{@title}</div>
      <div
        :for={item <- @items}
        class="picker-item"
        data-path={item.path}
        phx-click="select"
        phx-value-path={item.path}
        phx-target={@myself}
      >
        <div class="picker-filename">{item.filename}</div>
        <div class="picker-path">{item[:rel_path] || item.path}</div>
      </div>
    </div>
    """
  end
end
