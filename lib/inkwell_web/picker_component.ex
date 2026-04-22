defmodule InkwellWeb.PickerComponent do
  @moduledoc "File picker overlay: fuzzy-search + click-to-open. Toggled via parent's :picker_open assign."

  use InkwellWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:scope_dir, fn -> nil end)
      |> assign_new(:results, fn -> initial_results(assigns[:current_path]) end)

    {:ok, sync_selection(socket, 0)}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket) do
    results =
      case {socket.assigns.scope_dir, socket.assigns.current_path} do
        {nil, nil} -> Inkwell.Search.list_recent()
        {nil, current} -> Inkwell.Search.search(current, q)
        {dir, _} -> Inkwell.Search.browse(dir, q)
      end

    {:noreply,
     socket
     |> assign(query: q, results: results)
     |> sync_selection(0)}
  end

  def handle_event("nav", %{"key" => "ArrowDown"}, socket) do
    flat = flat_items(socket.assigns.results)
    next = min(socket.assigns.selected_index + 1, max(length(flat) - 1, 0))
    {:noreply, sync_selection(socket, next)}
  end

  def handle_event("nav", %{"key" => "ArrowUp"}, socket) do
    next = max(socket.assigns.selected_index - 1, 0)
    {:noreply, sync_selection(socket, next)}
  end

  def handle_event("nav", %{"key" => "Enter"}, socket) do
    flat = flat_items(socket.assigns.results)

    case Enum.at(flat, socket.assigns.selected_index) do
      %{path: path} ->
        send(self(), {:picker_selected, path})
        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("nav", %{"key" => "Escape"}, socket) do
    send(self(), :close_picker)
    {:noreply, socket}
  end

  def handle_event("nav", _, socket), do: {:noreply, socket}

  def handle_event("select", %{"path" => path}, socket) do
    send(self(), {:picker_selected, path})
    {:noreply, socket}
  end

  def handle_event("hover", %{"index" => index}, socket) do
    {:noreply, sync_selection(socket, String.to_integer(index))}
  end

  def handle_event("pick_file", _, socket) do
    case dialog_module().pick_file() do
      {:ok, path} -> send(self(), {:picker_selected, path})
      _ -> :noop
    end

    {:noreply, socket}
  end

  def handle_event("pick_directory", _, socket) do
    case dialog_module().pick_directory() do
      {:ok, dir} ->
        results = Inkwell.Search.browse(dir, "")

        {:noreply,
         socket
         |> assign(scope_dir: dir, query: "", results: results)
         |> sync_selection(0)}

      _ ->
        {:noreply, socket}
    end
  end

  defp dialog_module,
    do: Application.get_env(:inkwell, :file_dialog_module, Inkwell.FileDialog)

  defp initial_results(nil), do: Inkwell.Search.list_recent()
  defp initial_results(current), do: Inkwell.Search.search(current, "")

  defp flat_items(%{recent: r, siblings: s, repository: nil}), do: r ++ s

  defp flat_items(%{recent: r, siblings: s, repository: %{files: f}}), do: r ++ s ++ f

  defp current_dir(nil), do: nil
  defp current_dir(path), do: Path.dirname(path)

  defp sync_selection(socket, requested_index) do
    flat = flat_items(socket.assigns.results)
    max_index = max(length(flat) - 1, 0)
    index = if flat == [], do: 0, else: max(0, min(requested_index, max_index))

    preview = if flat == [], do: nil, else: render_preview(Enum.at(flat, index))

    socket
    |> assign(:selected_index, index)
    |> assign(:preview_html, preview)
  end

  defp render_preview(%{path: path}) do
    case File.read(path) do
      {:ok, content} ->
        {html, _, _} = Inkwell.Renderer.render_with_nav(content, base_dir: Path.dirname(path))
        html

      {:error, _} ->
        nil
    end
  end

  defp render_preview(_), do: nil

  @impl true
  def render(assigns) do
    flat = flat_items(assigns.results)
    has_repo = assigns.results.repository != nil
    repo_files = if has_repo, do: assigns.results.repository.files, else: []

    siblings_title =
      case assigns.scope_dir do
        nil -> "In this folder"
        dir -> "In " <> Path.basename(dir)
      end

    sections = [
      {"Recent", assigns.results.recent, 0},
      {siblings_title, assigns.results.siblings, length(assigns.results.recent)},
      {(has_repo && assigns.results.repository.name) || nil, repo_files,
       length(assigns.results.recent) + length(assigns.results.siblings)}
    ]

    assigns = assign(assigns, sections: sections, total: length(flat))

    ~H"""
    <div
      id="picker-overlay"
      class={if @open, do: "open", else: ""}
      phx-hook="PickerOverlay"
      phx-window-keydown={@open && "close_picker"}
      phx-key="Escape"
    >
      <div id="picker">
        <form id="picker-search-form" phx-change="search" phx-target={@myself}>
          <div id="picker-search">
            <span id="picker-search-icon">&#9906;</span>
            <input
              type="text"
              id="picker-input"
              name="q"
              placeholder="Search files and titles…"
              autocomplete="off"
              value={@query}
              phx-debounce="100"
              phx-keydown="nav"
              phx-target={@myself}
              phx-hook="PickerKeys"
            />
            <button
              type="button"
              class="picker-btn"
              phx-click="pick_file"
              phx-target={@myself}
              title="Open a markdown file"
            >
              Open File
            </button>
            <button
              type="button"
              class="picker-btn"
              phx-click="pick_directory"
              phx-target={@myself}
              title="Browse a folder"
            >
              Open Folder
            </button>
            <span class="hint">ESC to close</span>
          </div>
        </form>

        <div :if={current_dir(@current_path)} id="picker-path">
          <span class="path-label">In</span>
          <.path_segments path={current_dir(@current_path)} />
        </div>

        <div id="picker-body">
          <div id="picker-list">
            <.section
              :for={{title, items, offset} <- @sections}
              :if={title && items != []}
              title={title}
              items={items}
              offset={offset}
              selected_index={@selected_index}
              myself={@myself}
            />
            <div id="picker-status">
              {@total} {if @total == 1, do: "result", else: "results"}
            </div>
          </div>
          <div id="picker-preview">
            <div :if={@preview_html} class="markdown-body">
              {Phoenix.HTML.raw(@preview_html)}
            </div>
            <div :if={!@preview_html} class="preview-unavailable">
              No preview available
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :items, :list, required: true
  attr :offset, :integer, required: true
  attr :selected_index, :integer, required: true
  attr :myself, :any, required: true

  defp section(assigns) do
    assigns = assign(assigns, kind: section_kind(assigns.title))

    ~H"""
    <div class="picker-group">
      <div class="picker-section">
        <span class="section-mark">
          <.section_line_icon kind={@kind} />
        </span>
        <span class="picker-section-title">{@title}</span>
        <span class="picker-section-count">{length(@items)}</span>
      </div>
      <div
        :for={{item, i} <- Enum.with_index(@items)}
        class={["picker-item", @offset + i == @selected_index && "selected"]}
        data-path={item.path}
        phx-click="select"
        phx-value-path={item.path}
        phx-mouseenter="hover"
        phx-value-index={@offset + i}
        phx-target={@myself}
      >
        <div class="picker-item-title">{item[:title] || item.filename}</div>
        <.file_path path={item[:rel_path] || item.path} />
      </div>
    </div>
    """
  end

  defp section_kind("Recent"), do: :recent
  defp section_kind("In this folder"), do: :folder
  defp section_kind(_), do: :repo

  attr :kind, :atom, required: true

  defp section_line_icon(%{kind: :recent} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor"
         stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <circle cx="12" cy="12" r="9" />
      <polyline points="12 7 12 12 15.5 14" />
    </svg>
    """
  end

  defp section_line_icon(%{kind: :folder} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor"
         stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z" />
    </svg>
    """
  end

  defp section_line_icon(%{kind: :repo} = assigns) do
    ~H"""
    <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor"
         stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
      <line x1="6" x2="6" y1="3" y2="15" />
      <circle cx="18" cy="6" r="3" />
      <circle cx="6" cy="18" r="3" />
      <path d="M18 9a9 9 0 0 1-9 9" />
    </svg>
    """
  end

  attr :path, :string, required: true

  defp file_path(assigns) do
    path = assigns.path
    dir = Path.dirname(path)
    name = Path.basename(path)

    dir_display =
      case dir do
        "." -> ""
        "/" -> "/"
        d -> tildify(d) <> "/"
      end

    assigns = assign(assigns, dir: dir_display, name: name)

    ~H"""
    <div class="picker-item-file">
      <span :if={@dir != ""} class="picker-item-file-dir">{@dir}</span><span class="picker-item-file-name">{@name}</span>
    </div>
    """
  end

  defp tildify(path) do
    case System.user_home() do
      nil ->
        path

      home ->
        cond do
          path == home -> "~"
          String.starts_with?(path, home <> "/") -> "~" <> String.replace_prefix(path, home, "")
          true -> path
        end
    end
  end

  attr :path, :string, required: true

  defp path_segments(assigns) do
    segs = assigns.path |> String.trim_leading("/") |> String.split("/")
    assigns = assign(assigns, :segs, segs)

    ~H"""
    <span :for={{seg, i} <- Enum.with_index(@segs)}>
      <span :if={i > 0} class="path-sep">/</span>
      <span class="path-seg">{seg}</span>
    </span>
    """
  end
end
