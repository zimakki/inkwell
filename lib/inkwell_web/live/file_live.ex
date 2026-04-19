defmodule InkwellWeb.FileLive do
  @moduledoc "Renders a single markdown file and subscribes to PubSub for live reloads."

  use InkwellWeb, :live_view
  require Logger

  @impl true
  def mount(%{"path" => path}, _session, socket) do
    resolved = Inkwell.Watcher.resolve_path(path)

    if File.exists?(resolved) do
      Inkwell.Watcher.ensure_file(resolved)
      Inkwell.History.push(resolved)

      if connected?(socket) do
        Phoenix.PubSub.subscribe(Inkwell.PubSub, "file:" <> resolved)
        Inkwell.Daemon.client_connected()
      end

      {html, headings, alerts} =
        resolved
        |> File.read!()
        |> Inkwell.Renderer.render_with_nav()

      filename = Path.basename(resolved)
      rel_dir = compute_rel_dir(resolved)

      {:ok,
       socket
       |> assign(path: resolved)
       |> assign(filename: filename)
       |> assign(rel_dir: rel_dir)
       |> assign(html: html)
       |> assign(headings: headings)
       |> assign(alerts: alerts)
       |> assign(page_title: filename)}
    else
      {:ok, push_navigate(socket, to: ~p"/")}
    end
  end

  def mount(_params, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:reload, payload}, socket) do
    # The article body has phx-update="ignore" — see render/1 — so morphdom won't
    # touch it after mount. We push the new HTML to the DiffView hook which then
    # applies it according to the user's chosen mode (static / live / diff).
    {:noreply,
     socket
     |> assign(headings: payload.headings)
     |> assign(alerts: payload.alerts)
     |> push_event("article_reload", payload)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-body">
      <div id="article-mermaid" phx-hook="Mermaid">
        <div id="article-zoom" phx-hook="Zoom">
          <article id="page-ctn" phx-hook="DiffView" phx-update="ignore">
            {Phoenix.HTML.raw(@html)}
          </article>
        </div>
      </div>
      <aside id="doc-rail" class={doc_rail_class(@headings, @alerts)} phx-hook="Scrollspy">
        <div :if={@headings != []} class="doc-rail-section">
          <div class="doc-rail-title">Contents</div>
          <a
            :for={h <- @headings}
            class={["doc-rail-link", h.level == 3 && "doc-rail-h3" || nil]}
            href={"#" <> h.id}
            data-target={h.id}
          >
            {h.text}
          </a>
        </div>
        <div :if={@alerts != []} class="doc-rail-section doc-rail-alerts">
          <div class="doc-rail-title">Alerts</div>
          <a
            :for={a <- @alerts}
            class={["doc-rail-link", "doc-rail-alert", "doc-rail-alert-#{a.type}"]}
            href={"#" <> a.id}
            data-target={a.id}
          >
            {a.title}
          </a>
        </div>
      </aside>
    </div>

    <%= if @headings != [] or @alerts != [] do %>
      <button
        id="doc-map-fab"
        class="visible"
        aria-label="Document map"
        phx-hook="DocMap"
      >
        <svg
          viewBox="0 0 24 24"
          width="22"
          height="22"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <line x1="3" y1="6" x2="21" y2="6" />
          <line x1="3" y1="12" x2="21" y2="12" />
          <line x1="3" y1="18" x2="21" y2="18" />
        </svg>
        <span class="doc-fab-label">Map</span>
      </button>

      <div id="doc-map-backdrop"></div>
      <div id="doc-map-sheet">
        <div id="doc-map-handle"></div>
        <div id="doc-map-content" phx-hook="DocRailNav">
          <div :if={@headings != []} class="doc-rail-section">
            <div class="doc-rail-title">Contents</div>
            <a
              :for={h <- @headings}
              class={["doc-rail-link", h.level == 3 && "doc-rail-h3" || nil]}
              href={"#" <> h.id}
              data-target={h.id}
            >
              {h.text}
            </a>
          </div>
          <div :if={@alerts != []} class="doc-rail-section doc-rail-alerts">
            <div class="doc-rail-title">Alerts</div>
            <a
              :for={a <- @alerts}
              class={["doc-rail-link", "doc-rail-alert", "doc-rail-alert-#{a.type}"]}
              href={"#" <> a.id}
              data-target={a.id}
            >
              {a.title}
            </a>
          </div>
        </div>
      </div>
    <% end %>
    """
  end

  defp doc_rail_class([], []), do: ""
  defp doc_rail_class(_headings, _alerts), do: "visible"

  defp compute_rel_dir(path) do
    case Inkwell.GitRepo.find_root(path) do
      {:ok, root} ->
        rel = Path.relative_to(path, root)

        case Path.dirname(rel) do
          "." -> ""
          d -> d
        end

      :error ->
        ""
    end
  end
end
