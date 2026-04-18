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
  def terminate(_reason, socket) do
    if connected?(socket), do: Inkwell.Daemon.client_disconnected()
    :ok
  end

  @impl true
  def handle_info({:reload, payload}, socket) do
    {:noreply,
     socket
     |> assign(html: payload.html)
     |> assign(headings: payload.headings)
     |> assign(alerts: payload.alerts)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="page-body">
      <article id="page-ctn">
        {Phoenix.HTML.raw(@html)}
      </article>
      <aside id="doc-rail" class={doc_rail_class(@headings, @alerts)}>
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
