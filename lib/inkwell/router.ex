defmodule Inkwell.Router do
  use Plug.Router

  plug(Plug.Static, at: "/css", from: {:inkwell, "priv/static"})
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
      <link rel="stylesheet" href="/css/markdown-wide.css">
      <script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"></script>
      <style>
        #page-header { cursor: pointer; user-select: none; position: relative; }
        #page-header h3::after { content: ' ▾'; font-size: 0.7em; opacity: 0.5; }

        /* ── Picker overlay ── */
        #picker-overlay {
          position: fixed; top: 0; left: 0; width: 100%; height: 100%;
          background: rgba(0,0,0,0.6); z-index: 1000;
          display: none; align-items: center; justify-content: center;
        }
        #picker-overlay.open { display: flex; }

        #picker {
          width: 90vw; height: 85vh; max-width: 1400px;
          background: var(--bg); border-radius: 8px;
          border: 1px solid var(--border);
          display: flex; flex-direction: column;
          font-family: 'SF Mono', monospace; font-size: 13px;
          color: var(--text); overflow: hidden;
          box-shadow: 0 20px 60px rgba(0,0,0,0.5);
        }

        #picker-search {
          padding: 12px 16px; border-bottom: 1px solid var(--border);
          display: flex; align-items: center; gap: 8px;
        }
        #picker-search-icon { color: var(--text-muted); }
        #picker-search input {
          flex: 1; background: none; border: none; outline: none;
          color: var(--h2); font-size: 14px; font-family: inherit;
        }
        #picker-search input::placeholder { color: var(--text-muted); }
        #picker-search .hint { color: var(--text-muted); font-size: 11px; }

        #picker-body {
          display: flex; flex: 1; min-height: 0;
        }

        #picker-list {
          width: 35%; border-right: 1px solid var(--border);
          overflow-y: auto; display: flex; flex-direction: column;
        }

        .picker-section {
          padding: 8px 12px 4px; font-size: 10px;
          text-transform: uppercase; letter-spacing: 0.08em;
          color: var(--text-muted); font-family: system-ui;
        }

        .picker-item {
          padding: 6px 12px; cursor: pointer;
          border-left: 3px solid transparent;
        }
        .picker-item:hover { background: var(--bg-hover); }
        .picker-item.selected {
          background: var(--bg-surface);
          border-left-color: var(--h2);
        }
        .picker-item-title {
          color: var(--text); font-size: 13px; font-weight: 500;
          font-family: system-ui;
        }
        .picker-item.selected .picker-item-title { color: var(--text); }
        .picker-item:not(.selected) .picker-item-title { color: var(--text-secondary); }
        .picker-item-file {
          color: var(--text-muted); font-size: 11px; margin-top: 2px;
        }

        #picker-status {
          margin-top: auto; padding: 8px 12px;
          border-top: 1px solid var(--border);
          font-size: 11px; color: var(--text-muted); font-family: system-ui;
        }

        #picker-preview {
          width: 65%; overflow-y: auto; padding: 24px 32px;
          font-family: 'Outfit', system-ui, sans-serif;
        }
        #picker-preview .preview-unavailable {
          color: var(--text-muted); font-style: italic;
          display: flex; align-items: center; justify-content: center;
          height: 100%;
        }
      </style>
    </head>
    <body>
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

      <script>
        (function() {
          var ctn = document.getElementById('page-ctn');
          var headerTitle = document.getElementById('header-title');
          var pickerOverlay = document.getElementById('picker-overlay');
          var pickerInput = document.getElementById('picker-input');
          var pickerListItems = document.getElementById('picker-list-items');
          var pickerStatus = document.getElementById('picker-status');
          var pickerPreview = document.getElementById('picker-preview');
          var ws, pingInterval, reconnectTimer;
          var currentPath = "#{safe_current_path}";
          var currentFiles = [];
          var selectedIndex = 0;
          var searchTimer = null;
          var escapeDiv = document.createElement('div');
          var previewTimer = null;
          var previewController = null;

          mermaid.initialize({ startOnLoad: false, theme: '#{theme}' === 'dark' ? 'dark' : 'default' });

          function renderMermaid() {
            var blocks = ctn.querySelectorAll('pre.mermaid');
            if (blocks.length > 0) {
              blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
              mermaid.run({ nodes: blocks });
            }
          }

          // ── Picker ────────────────────────────────────

          function openPicker() {
            pickerOverlay.classList.add('open');
            pickerInput.value = '';
            pickerInput.focus();
            selectedIndex = 0;
            loadSearch('');
          }

          function closePicker() {
            pickerOverlay.classList.remove('open');
            pickerInput.blur();
            currentFiles = [];
            pickerListItems.innerHTML = '';
            pickerPreview.innerHTML = '<div class="preview-unavailable">Select a file to preview</div>';
          }

          function loadSearch(query) {
            if (previewController) { previewController.abort(); previewController = null; }
            fetch('/search?current=' + encodeURIComponent(currentPath) + '&q=' + encodeURIComponent(query))
              .then(function(r) { return r.json(); })
              .then(function(files) {
                currentFiles = files;
                selectedIndex = 0;
                renderFileList();
                loadPreview();
              })
              .catch(function() {});
          }

          function renderFileList() {
            var html = '';
            var currentSection = null;
            currentFiles.forEach(function(f, i) {
              if (f.section !== currentSection) {
                currentSection = f.section;
                var label = f.section === 'recent' ? 'Recent' : (f.path.split('/').slice(-2, -1)[0] + '/');
                html += '<div class="picker-section">' + label + '</div>';
              }
              var cls = i === selectedIndex ? 'picker-item selected' : 'picker-item';
              var title = f.title || f.filename;
              html += '<div class="' + cls + '" data-index="' + i + '">'
                + '<div class="picker-item-title">' + escapeHtml(title) + '</div>'
                + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
                + '</div>';
            });
            pickerListItems.innerHTML = html;
            pickerStatus.textContent = currentFiles.length + ' files \u00b7 \u2191\u2193 navigate \u00b7 \u21b5 open';

            var sel = pickerListItems.querySelector('.selected');
            if (sel) sel.scrollIntoView({ block: 'nearest' });
          }

          function loadPreview() {
            if (previewTimer) clearTimeout(previewTimer);
            if (!currentFiles.length) {
              pickerPreview.innerHTML = '<div class="preview-unavailable">No files found</div>';
              return;
            }
            previewTimer = setTimeout(function() {
              var file = currentFiles[selectedIndex];
              if (!file) return;
              if (previewController) previewController.abort();
              previewController = new AbortController();
              fetch('/preview?current=' + encodeURIComponent(currentPath) + '&path=' + encodeURIComponent(file.path), { signal: previewController.signal })
                .then(function(r) {
                  if (!r.ok) throw new Error('Preview failed');
                  return r.text();
                })
                .then(function(html) {
                  pickerPreview.innerHTML = html;
                })
                .catch(function(e) {
                  if (e.name !== 'AbortError') {
                    pickerPreview.innerHTML = '<div class="preview-unavailable">Preview unavailable</div>';
                  }
                });
            }, 100);
          }

          function updateSelection(oldIdx, newIdx) {
            var items = pickerListItems.querySelectorAll('.picker-item');
            if (items[oldIdx]) items[oldIdx].classList.remove('selected');
            if (items[newIdx]) {
              items[newIdx].classList.add('selected');
              items[newIdx].scrollIntoView({ block: 'nearest' });
            }
          }

          function selectFile() {
            var file = currentFiles[selectedIndex];
            if (!file) return;
            fetch('/switch?current=' + encodeURIComponent(currentPath) + '&path=' + encodeURIComponent(file.path))
              .then(function(r) {
                if (!r.ok) throw new Error('Switch failed');
                return r.json();
              })
              .then(function(data) {
                currentPath = data.path;
                headerTitle.textContent = data.filename;
                document.title = data.filename;
                history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
                reconnectSocket();
                closePicker();
              });
          }

          function escapeHtml(str) {
            escapeDiv.textContent = str;
            return escapeDiv.innerHTML;
          }

          // ── Picker events ─────────────────────────────

          pickerInput.addEventListener('input', function() {
            if (searchTimer) clearTimeout(searchTimer);
            searchTimer = setTimeout(function() {
              loadSearch(pickerInput.value);
            }, 150);
          });

          pickerInput.addEventListener('keydown', function(e) {
            if (e.key === 'ArrowDown') {
              e.preventDefault();
              if (selectedIndex < currentFiles.length - 1) {
                var old = selectedIndex;
                selectedIndex++;
                updateSelection(old, selectedIndex);
                loadPreview();
              }
            } else if (e.key === 'ArrowUp') {
              e.preventDefault();
              if (selectedIndex > 0) {
                var old = selectedIndex;
                selectedIndex--;
                updateSelection(old, selectedIndex);
                loadPreview();
              }
            } else if (e.key === 'Enter') {
              e.preventDefault();
              selectFile();
            }
          });

          pickerListItems.addEventListener('click', function(e) {
            var item = e.target.closest('.picker-item');
            if (item) {
              var idx = parseInt(item.dataset.index, 10);
              if (idx === selectedIndex) {
                selectFile();
              } else {
                var old = selectedIndex;
                selectedIndex = idx;
                updateSelection(old, selectedIndex);
                loadPreview();
              }
            }
          });

          pickerOverlay.addEventListener('click', function(e) {
            if (e.target === pickerOverlay) closePicker();
          });

          // ── Global keyboard ───────────────────────────

          document.getElementById('page-header').addEventListener('click', function() {
            if (pickerOverlay.classList.contains('open')) {
              pickerInput.focus();
            } else {
              openPicker();
            }
          });

          document.addEventListener('keydown', function(e) {
            if (e.key === 'Escape' && pickerOverlay.classList.contains('open')) {
              closePicker();
              return;
            }
            if (e.ctrlKey && e.key === 'p') {
              e.preventDefault();
              if (pickerOverlay.classList.contains('open')) {
                pickerInput.focus();
              } else {
                openPicker();
              }
              return;
            }
            if (e.ctrlKey && e.shiftKey && e.key === 'T') {
              fetch('/toggle-theme').then(function(r) { return r.json(); }).then(function(data) {
                var el = document.querySelector('[data-theme]');
                el.dataset.theme = data.theme;
                mermaid.initialize({ startOnLoad: false, theme: data.theme === 'dark' ? 'dark' : 'default' });
                renderMermaid();
              });
            }
          });

          // ── WebSocket ─────────────────────────────────

          function reconnectSocket() {
            if (reconnectTimer) {
              clearTimeout(reconnectTimer);
              reconnectTimer = null;
            }
            if (ws) ws.close();
            connect();
          }

          function connect() {
            ws = new WebSocket('ws://' + location.host + '/ws?path=' + encodeURIComponent(currentPath));
            ws.onmessage = function(e) {
              if (e.data === 'pong') return;
              ctn.innerHTML = e.data;
              renderMermaid();
            };
            ws.onclose = function() {
              if (pingInterval) { clearInterval(pingInterval); pingInterval = null; }
              reconnectTimer = setTimeout(connect, 1000);
            };
            ws.onopen = function() {
              if (pingInterval) clearInterval(pingInterval);
              pingInterval = setInterval(function() {
                if (ws.readyState === 1) ws.send('ping');
              }, 30000);
            };
          }
          connect();
          renderMermaid();
        })();
      </script>
    </body>
    </html>
    """
  end
end
