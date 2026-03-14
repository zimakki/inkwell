(function() {
  var ctn = document.getElementById('page-ctn');
  var headerTitle = document.getElementById('header-title');
  var pickerOverlay = document.getElementById('picker-overlay');
  var pickerInput = document.getElementById('picker-input');
  var pickerListItems = document.getElementById('picker-list-items');
  var pickerStatus = document.getElementById('picker-status');
  var pickerPreview = document.getElementById('picker-preview');
  var btnOpenFile = document.getElementById('btn-open-file');
  var btnOpenFolder = document.getElementById('btn-open-folder');
  var pickerPathBar = document.getElementById('picker-path');
  var ws, pingInterval, reconnectTimer;
  var currentPath = document.body.dataset.currentPath || null;
  var initialBrowseDir = document.body.dataset.browseDir || null;
  var currentTheme = document.querySelector('[data-theme]').dataset.theme;
  var currentFiles = [];
  var selectedIndex = 0;
  var searchTimer = null;
  var escapeDiv = document.createElement('div');
  var previewTimer = null;
  var previewController = null;
  var browseDir = null;
  var repoInfo = null;

  mermaid.initialize({ startOnLoad: false, theme: currentTheme === 'dark' ? 'dark' : 'default' });

  function renderMermaid() {
    var blocks = ctn.querySelectorAll('pre.mermaid');
    if (blocks.length > 0) {
      blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
      mermaid.run({ nodes: blocks });
    }
  }

  // ── Picker ────────────────────────────────────

  function openPicker() {
    // If we entered via folder browse, always reopen in that context
    browseDir = initialBrowseDir || null;
    pickerOverlay.classList.add('open');
    pickerInput.value = '';
    pickerInput.focus();
    selectedIndex = 0;
    renderPathBar();
    loadSearch('');
  }

  function closePicker() {
    pickerOverlay.classList.remove('open');
    pickerInput.blur();
    currentFiles = [];
    browseDir = null;
    pickerListItems.innerHTML = '';
    pickerPreview.innerHTML = '<div class="preview-unavailable">Select a file to preview</div>';
  }

  function loadSearch(query) {
    if (previewController) { previewController.abort(); previewController = null; }
    var url;
    if (browseDir) {
      url = '/browse?dir=' + encodeURIComponent(browseDir) + '&q=' + encodeURIComponent(query);
    } else {
      var params = 'q=' + encodeURIComponent(query);
      if (currentPath) {
        params = 'current=' + encodeURIComponent(currentPath) + '&' + params;
      }
      url = '/search?' + params;
    }
    pickerStatus.textContent = 'Searching...';
    pickerListItems.innerHTML = '<div class="picker-hint loading">Loading files</div>';
    fetch(url)
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (browseDir) {
          // Browse mode still returns flat array
          currentFiles = data;
          repoInfo = null;
        } else {
          // Structured response
          currentFiles = (data.recent || []).concat(data.siblings || []);
          if (data.repository && data.repository.files) {
            repoInfo = { name: data.repository.name, total: data.repository.total };
            currentFiles = currentFiles.concat(data.repository.files);
          } else {
            repoInfo = null;
          }
        }
        selectedIndex = 0;
        renderPathBar();
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
        var label;
        var cls = 'picker-section';
        if (f.section === 'recent') {
          label = 'Recent';
        } else if (f.section === 'browse' && browseDir) {
          label = 'Browse: ' + browseDir;
        } else if (f.section === 'repository' && repoInfo) {
          label = 'Repository (' + repoInfo.name + ')';
          cls = 'picker-section repo';
        } else {
          label = f.path.split('/').slice(-2, -1)[0] + '/';
        }
        html += '<div class="' + cls + '">' + escapeHtml(label) + '</div>';
      }
      var itemCls = i === selectedIndex ? 'picker-item selected' : 'picker-item';
      var title = f.title || f.filename;

      if (f.rel_path) {
        var relDir = f.rel_path.split('/').slice(0, -1).join('/');
        html += '<div class="' + itemCls + '" data-index="' + i + '">'
          + '<div class="picker-item-title-row">'
          + '<span class="picker-item-title">' + escapeHtml(title) + '</span>'
          + (relDir ? '<span class="picker-item-dir">' + escapeHtml(relDir + '/') + '</span>' : '')
          + '</div>'
          + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
          + '</div>';
      } else {
        html += '<div class="' + itemCls + '" data-index="' + i + '">'
          + '<div class="picker-item-title">' + escapeHtml(title) + '</div>'
          + '<div class="picker-item-file">' + escapeHtml(f.filename) + '</div>'
          + '</div>';
      }
    });

    // Truncation hint for repository section
    if (repoInfo && repoInfo.total > 0) {
      var repoFilesShown = currentFiles.filter(function(f) { return f.section === 'repository'; }).length;
      if (repoFilesShown < repoInfo.total) {
        html += '<div class="picker-hint">Showing ' + repoFilesShown + ' of ' + repoInfo.total + ' files — type to search all</div>';
      }
    }

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
      var previewCurrent = currentPath || file.path;
      var source = '';
      if (browseDir) source = '&source=browse';
      else if (file.section === 'repository') source = '&source=repository';
      var url = '/preview?current=' + encodeURIComponent(previewCurrent) + '&path=' + encodeURIComponent(file.path) + source;
      fetch(url, { signal: previewController.signal })
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

    // Empty state: no currentPath, do full page navigation
    if (!currentPath && !browseDir) {
      window.location = '/?path=' + encodeURIComponent(file.path);
      return;
    }

    var switchCurrent = currentPath || file.path;
    var source = '';
    if (browseDir) {
      source = '&source=browse';
    } else if (file.section === 'repository') {
      source = '&source=repository';
    }
    var url = '/switch?current=' + encodeURIComponent(switchCurrent) + '&path=' + encodeURIComponent(file.path) + source;
    fetch(url)
      .then(function(r) {
        if (!r.ok) throw new Error('Switch failed');
        return r.json();
      })
      .then(function(data) {
        currentPath = data.path;
        headerTitle.textContent = data.filename;
        document.title = data.filename;
        history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
        if (data.html) {
          ctn.innerHTML = data.html;
          renderMermaid();
        }
        reconnectSocket();
        closePicker();
      });
  }

  function renderPathBar() {
    var dirPath = browseDir || (currentPath ? currentPath.split('/').slice(0, -1).join('/') : '');
    var segments = dirPath.split('/').filter(Boolean);
    var html = '';

    if (browseDir) {
      html += '<span class="path-back" id="path-back-btn" title="Back to recent files">&#8592;</span>';
      html += '<span class="path-label">browsing</span>';
    } else {
      html += '<span class="path-label">in</span>';
    }

    html += '<span class="path-sep">/</span>';
    for (var i = 0; i < segments.length; i++) {
      html += '<span class="path-seg">' + escapeHtml(segments[i]) + '</span>';
      if (i < segments.length - 1) {
        html += '<span class="path-sep">/</span>';
      }
    }
    pickerPathBar.innerHTML = html;
    // Scroll to the end so the deepest segment is visible
    pickerPathBar.scrollLeft = pickerPathBar.scrollWidth;

    // Bind back button if in browse mode
    var backBtn = document.getElementById('path-back-btn');
    if (backBtn) {
      backBtn.addEventListener('click', function() {
        browseDir = null;
        pickerInput.value = '';
        loadSearch('');
      });
    }
  }

  function escapeHtml(str) {
    escapeDiv.textContent = str;
    return escapeDiv.innerHTML;
  }

  // ── Browse buttons ──────────────────────────────

  btnOpenFile.addEventListener('click', function(e) {
    e.stopPropagation();
    fetch('/pick-file')
      .then(function(r) {
        if (r.status === 204) return null;
        if (!r.ok) throw new Error('Pick failed');
        return r.json();
      })
      .then(function(data) {
        if (!data) return;
        // Empty state: no currentPath, do full page navigation
        if (!currentPath) {
          window.location = '/?path=' + encodeURIComponent(data.path);
          return;
        }
        // Switch to the picked file directly
        browseDir = '__pick__';
        var url = '/switch?current=' + encodeURIComponent(currentPath) + '&path=' + encodeURIComponent(data.path) + '&source=browse';
        return fetch(url).then(function(r) {
          if (!r.ok) throw new Error('Switch failed');
          return r.json();
        }).then(function(switchData) {
          currentPath = switchData.path;
          headerTitle.textContent = switchData.filename;
          document.title = switchData.filename;
          history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
          reconnectSocket();
          closePicker();
        });
      })
      .catch(function() {});
  });

  btnOpenFolder.addEventListener('click', function(e) {
    e.stopPropagation();
    fetch('/pick-directory')
      .then(function(r) {
        if (r.status === 204) return null;
        if (!r.ok) throw new Error('Pick failed');
        return r.json();
      })
      .then(function(data) {
        if (!data) return;
        browseDir = data.dir;
        initialBrowseDir = data.dir;
        selectedIndex = 0;
        pickerInput.value = '';
        renderPathBar();
        loadSearch('');
        pickerInput.focus();
      })
      .catch(function() {});
  });

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
        currentTheme = data.theme;
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
  var noFile = document.body.dataset.noFile;

  if (noFile) {
    // Empty state — auto-open picker with recent files
    pickerOverlay.classList.add('open');
    pickerInput.focus();
    selectedIndex = 0;
    renderPathBar();
    loadSearch('');
  } else if (initialBrowseDir) {
    browseDir = initialBrowseDir;
    pickerOverlay.classList.add('open');
    pickerInput.focus();
    selectedIndex = 0;
    renderPathBar();
    loadSearch('');
  } else if (currentPath) {
    connect();
  }
  renderMermaid();
})();
