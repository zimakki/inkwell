defmodule Inkwell.Router do
  @moduledoc "HTTP router serving the preview UI, APIs, and WebSocket upgrades."
  use Plug.Router
  require Logger

  plug(Plug.Static, at: "/static", from: {:inkwell, "priv/static"})
  plug(:match)
  plug(:dispatch)

  get "/" do
    with {:ok, file_path} <- fetch_path_param(conn, "path"),
         true <- File.exists?(file_path) do
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
      {:error, reason} -> send_resp(conn, 400, reason)
      false -> send_resp(conn, 404, "File not found")
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

    with {:ok, current_path} <- fetch_query_path(conn, "current"),
         {:ok, new_path} <- fetch_query_path(conn, "path"),
         true <- File.exists?(new_path),
         true <- Inkwell.Search.allowed_path?(current_path, new_path) do
      Inkwell.Watcher.ensure_file(new_path)
      Inkwell.History.push(new_path)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(%{path: new_path, filename: Path.basename(new_path)}))
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

    with {:ok, current_path} <- fetch_query_path(conn, "current") do
      query = conn.query_params["q"] || ""
      results = Inkwell.Search.search(current_path, query)

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(results))
    else
      {:error, reason} -> send_resp(conn, 400, reason)
    end
  end

  get "/preview" do
    conn = Plug.Conn.fetch_query_params(conn)

    with {:ok, current_path} <- fetch_query_path(conn, "current"),
         {:ok, path} <- fetch_query_path(conn, "path"),
         true <- String.ends_with?(path, ".md"),
         true <- File.exists?(path),
         true <- Inkwell.Search.allowed_path?(current_path, path) do
      html = path |> File.read!() |> Inkwell.Renderer.render()

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, html)
    else
      {:error, reason} -> send_resp(conn, 400, reason)
      false -> send_resp(conn, 403, "Path not in allowed file set")
    end
  end

  match _ do
    send_resp(conn, 404, "Not found")
  end

  defp open_file_payload(path, theme) do
    cond do
      is_nil(path) ->
        {:error, {400, "Missing path parameter"}}

      not String.ends_with?(path, ".md") ->
        {:error, {400, "Path must end with .md"}}

      not File.exists?(path) ->
        {:error, {404, "File not found"}}

      true ->
        {:ok, Inkwell.open_file(path, theme: theme)}
    end
  end

  defp fetch_path_param(conn, name) do
    conn = Plug.Conn.fetch_query_params(conn)
    fetch_query_path(conn, name)
  end

  defp fetch_query_path(conn, name) do
    case conn.query_params[name] do
      nil -> {:error, "Missing #{name} parameter"}
      path -> {:ok, Path.expand(path)}
    end
  end

  defp html_page(content, filename, theme, current_path) do
    safe_filename = Plug.HTML.html_escape(filename)
    safe_current_path = Plug.HTML.html_escape(current_path)

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
    <body data-current-path="#{safe_current_path}">
      <div data-theme="#{theme}">
        <div id="page-header">
          <h3 id="header-title">#{safe_filename}</h3>
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
            <span class="hint">ESC to close</span>
          </div>
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
