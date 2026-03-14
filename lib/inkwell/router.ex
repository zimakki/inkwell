defmodule Inkwell.Router do
  @moduledoc "HTTP router serving the preview UI, APIs, and WebSocket upgrades."
  use Plug.Router
  require Logger

  plug(Plug.Static, at: "/static", from: {:inkwell, "priv/static"})
  plug(:match)
  plug(:dispatch)

  get "/" do
    conn = Plug.Conn.fetch_query_params(conn)

    cond do
      conn.query_params["path"] ->
        file_path = Path.expand(conn.query_params["path"])

        if File.exists?(file_path) do
          Inkwell.Watcher.ensure_file(file_path)
          Inkwell.History.push(file_path)

          theme = :persistent_term.get(:inkwell_theme, "dark")
          html = file_path |> File.read!() |> Inkwell.Renderer.render()
          filename = Path.basename(file_path)
          page = html_page(html, filename, theme, file_path)

          conn
          |> put_resp_content_type("text/html")
          |> send_resp(200, page)
        else
          send_resp(conn, 404, "File not found")
        end

      conn.query_params["dir"] ->
        dir = Path.expand(conn.query_params["dir"])
        theme = :persistent_term.get(:inkwell_theme, "dark")
        page = browse_page(theme, dir)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, page)

      true ->
        theme = :persistent_term.get(:inkwell_theme, "dark")
        page = empty_page(theme)

        conn
        |> put_resp_content_type("text/html")
        |> send_resp(200, page)
    end
  end

  get "/health" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{ok: true}))
  end

  get "/status" do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(Inkwell.Daemon.status_info()))
  end

  post "/stop" do
    conn = send_resp(conn, 200, "Stopping")

    spawn(fn ->
      Process.sleep(100)
      System.stop(0)
    end)

    conn
  end

  get "/open" do
    conn = Plug.Conn.fetch_query_params(conn)
    path = conn.query_params["path"]
    theme = conn.query_params["theme"]

    Logger.debug("Opening file: #{path}")

    case open_file_payload(path, theme) do
      {:ok, payload} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(payload))

      {:error, {status, message}} ->
        send_resp(conn, status, message)
    end
  end

  get "/ws" do
    conn = Plug.Conn.fetch_query_params(conn)

    with {:ok, path} <- fetch_query_path(conn, "path"),
         true <- File.exists?(path) do
      conn
      |> WebSockAdapter.upgrade(Inkwell.WsHandler, [path: path], timeout: :infinity)
      |> halt()
    else
      {:error, reason} -> send_resp(conn, 400, reason)
      false -> send_resp(conn, 404, "File not found")
    end
  end

  get "/switch" do
    conn = Plug.Conn.fetch_query_params(conn)
    source = conn.query_params["source"]

    with {:ok, current_path} <- fetch_query_path(conn, "current"),
         {:ok, new_path} <- fetch_query_path(conn, "path"),
         true <- authorized?(current_path, new_path, source) do
      Inkwell.Watcher.ensure_file(new_path)
      Inkwell.History.push(new_path)

      html = new_path |> File.read!() |> Inkwell.Renderer.render()

      rel = compute_rel_path(new_path)
      rel_dir = rel |> Path.dirname() |> then(fn "." -> ""; d -> d end)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(
        200,
        Jason.encode!(%{
          path: new_path,
          filename: Path.basename(new_path),
          rel_dir: rel_dir,
          html: html
        })
      )
    else
      {:error, reason} -> send_resp(conn, 400, reason)
      false -> send_resp(conn, 403, "Path not in allowed file set")
    end
  end

  get "/toggle-theme" do
    current = :persistent_term.get(:inkwell_theme, "dark")
    new_theme = if current == "dark", do: "light", else: "dark"
    :persistent_term.put(:inkwell_theme, new_theme)
    Logger.debug("Theme toggled: #{current} -> #{new_theme}")
    Inkwell.Watcher.rebroadcast_all()

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{theme: new_theme}))
  end

  get "/search" do
    conn = Plug.Conn.fetch_query_params(conn)
    query = conn.query_params["q"] || ""

    results =
      case conn.query_params["current"] do
        nil -> Inkwell.Search.list_recent()
        "" -> Inkwell.Search.list_recent()
        current -> Inkwell.Search.search(Path.expand(current), query)
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(results))
  end

  get "/preview" do
    conn = Plug.Conn.fetch_query_params(conn)
    source = conn.query_params["source"]

    with {:ok, current_path} <- fetch_query_path(conn, "current"),
         {:ok, path} <- fetch_query_path(conn, "path"),
         true <- authorized?(current_path, path, source) do
      html = path |> File.read!() |> Inkwell.Renderer.render()

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, html)
    else
      {:error, reason} -> send_resp(conn, 400, reason)
      false -> send_resp(conn, 403, "Path not in allowed file set")
    end
  end

  get "/browse" do
    conn = Plug.Conn.fetch_query_params(conn)

    case conn.query_params["dir"] do
      nil ->
        send_resp(conn, 400, "Missing dir parameter")

      dir ->
        query = conn.query_params["q"] || ""
        results = Inkwell.Search.search_directory(dir, query)

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(results))
    end
  end

  get "/pick-file" do
    case Inkwell.FileDialog.pick_file() do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{path: path, filename: Path.basename(path)}))

      :cancel ->
        send_resp(conn, 204, "")

      {:error, reason} ->
        send_resp(conn, 500, reason)
    end
  end

  get "/pick-directory" do
    case Inkwell.FileDialog.pick_directory() do
      {:ok, dir} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{dir: dir}))

      :cancel ->
        send_resp(conn, 204, "")

      {:error, reason} ->
        send_resp(conn, 500, reason)
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp open_file_payload(path, theme) do
    cond do
      is_nil(path) ->
        {:error, {400, "Missing path parameter"}}

      not markdown_file?(path) ->
        {:error, {400, "Path must be a markdown file (.md or .markdown)"}}

      not File.exists?(path) ->
        {:error, {404, "File not found"}}

      true ->
        {:ok, Inkwell.open_file(path, theme: theme)}
    end
  end

  defp authorized?(_current_path, new_path, "browse") do
    File.exists?(new_path) and markdown_file?(new_path)
  end

  defp authorized?(current_path, new_path, "repository") do
    File.exists?(new_path) and markdown_file?(new_path) and
      case Inkwell.GitRepo.find_root(current_path) do
        {:ok, root} -> String.starts_with?(new_path, root <> "/") or new_path == root
        :error -> false
      end
  end

  defp authorized?(current_path, new_path, _source) do
    File.exists?(new_path) and
      markdown_file?(new_path) and
      Inkwell.Search.allowed_path?(current_path, new_path)
  end

  defp compute_rel_path(path) do
    case Inkwell.GitRepo.find_root(path) do
      {:ok, root} ->
        Path.relative_to(path, root)

      :error ->
        Path.basename(path)
    end
  end

  defp markdown_file?(path) do
    String.ends_with?(path, ".md") or String.ends_with?(path, ".markdown")
  end

  defp fetch_query_path(conn, name) do
    case conn.query_params[name] do
      nil -> {:error, "Missing #{name} parameter"}
      path -> {:ok, Path.expand(path)}
    end
  end

  defp browse_page(theme, browse_dir) do
    safe_dir = Plug.HTML.html_escape(browse_dir)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Inkwell</title>
      <link rel="stylesheet" href="/static/markdown-wide.css">
      <link rel="stylesheet" href="/static/app.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
    </head>
    <body data-browse-dir="#{safe_dir}">
      <div data-theme="#{theme}">
        <div id="page-header">
          <div id="header-file-info">
            <div id="header-title"><span id="header-filename">Inkwell</span> <span id="header-caret">&#9662;</span></div>
            <div id="header-dir"></div>
          </div>
        </div>
        <div id="page-ctn"></div>
      </div>

      <div id="picker-overlay">
        <div id="picker">
          <div id="picker-search">
            <span id="picker-search-icon">&#9906;</span>
            <input type="text" id="picker-input" placeholder="Search files and titles..." autocomplete="off" />
            <button id="btn-open-file" class="picker-btn" title="Open a markdown file">Open File</button>
            <button id="btn-open-folder" class="picker-btn" title="Browse a folder">Open Folder</button>
            <span class="hint">ESC to close</span>
          </div>
          <div id="picker-path"></div>
          <div id="picker-body">
            <div id="picker-list">
              <div id="picker-list-items"></div>
              <div id="picker-status"></div>
            </div>
            <div id="picker-preview">
              <div class="preview-unavailable">Select a file to preview</div>
            </div>
          </div>
        </div>
      </div>

      <script src="/static/app.js"></script>
    </body>
    </html>
    """
  end

  defp empty_page(theme) do
    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Inkwell</title>
      <link rel="stylesheet" href="/static/markdown-wide.css">
      <link rel="stylesheet" href="/static/app.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
    </head>
    <body data-no-file="true">
      <div data-theme="#{theme}">
        <div id="page-header">
          <div id="header-file-info">
            <div id="header-title"><span id="header-filename">Inkwell</span> <span id="header-caret">&#9662;</span></div>
            <div id="header-dir"></div>
          </div>
        </div>
        <div id="page-ctn">
          <div style="display:flex;align-items:center;justify-content:center;height:60vh;color:var(--text-muted);font-family:system-ui;font-size:15px;">
            Open a file to get started
          </div>
        </div>
      </div>

      <div id="picker-overlay">
        <div id="picker">
          <div id="picker-search">
            <span id="picker-search-icon">&#9906;</span>
            <input type="text" id="picker-input" placeholder="Search files and titles..." autocomplete="off" />
            <button id="btn-open-file" class="picker-btn" title="Open a markdown file">Open File</button>
            <button id="btn-open-folder" class="picker-btn" title="Browse a folder">Open Folder</button>
            <span class="hint">ESC to close</span>
          </div>
          <div id="picker-path"></div>
          <div id="picker-body">
            <div id="picker-list">
              <div id="picker-list-items"></div>
              <div id="picker-status"></div>
            </div>
            <div id="picker-preview">
              <div class="preview-unavailable">Select a file to preview</div>
            </div>
          </div>
        </div>
      </div>

      <script src="/static/app.js"></script>
    </body>
    </html>
    """
  end

  defp html_page(content, filename, theme, current_path) do
    safe_filename = Plug.HTML.html_escape(filename)
    safe_current_path = Plug.HTML.html_escape(current_path)

    rel_path = compute_rel_path(current_path)
    safe_rel_dir = rel_path |> Path.dirname() |> then(fn "." -> ""; d -> d end) |> Plug.HTML.html_escape()

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>#{safe_filename}</title>
      <link rel="stylesheet" href="/static/markdown-wide.css">
      <link rel="stylesheet" href="/static/app.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
    </head>
    <body data-current-path="#{safe_current_path}" data-rel-dir="#{safe_rel_dir}">
      <div data-theme="#{theme}">
        <div id="page-header">
          <div id="header-actions">
            <button id="btn-toggle-theme" class="header-btn" aria-label="Toggle theme">
              <svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
              <svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12.79A9 9 0 1111.21 3 7 7 0 0021 12.79z"/></svg>
              <span class="header-tooltip">Ctrl+Shift+T</span>
            </button>
            <button id="btn-search" class="header-btn" aria-label="Search files">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
              <span class="header-tooltip">Ctrl+P</span>
            </button>
          </div>
          <div id="header-separator"></div>
          <div id="header-file-info">
            <div id="header-title"><span id="header-filename">#{safe_filename}</span> <span id="header-caret">&#9662;</span></div>
            <div id="header-dir"></div>
          </div>
        </div>
        <div id="page-ctn">
          #{content}
        </div>
      </div>

      <div id="picker-overlay">
        <div id="picker">
          <div id="picker-search">
            <span id="picker-search-icon">&#9906;</span>
            <input type="text" id="picker-input" placeholder="Search files and titles..." autocomplete="off" />
            <button id="btn-open-file" class="picker-btn" title="Open a markdown file">Open File</button>
            <button id="btn-open-folder" class="picker-btn" title="Browse a folder">Open Folder</button>
            <span class="hint">ESC to close</span>
          </div>
          <div id="picker-path"></div>
          <div id="picker-body">
            <div id="picker-list">
              <div id="picker-list-items"></div>
              <div id="picker-status"></div>
            </div>
            <div id="picker-preview">
              <div class="preview-unavailable">Select a file to preview</div>
            </div>
          </div>
        </div>
      </div>

      <script src="/static/app.js"></script>
    </body>
    </html>
    """
  end
end
