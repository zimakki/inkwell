(function() {
  var ctn = document.getElementById('page-ctn');
  var headerFilename = document.getElementById('header-filename');
  var headerDir = document.getElementById('header-dir');
  var pickerOverlay = document.getElementById('picker-overlay');
  var pickerInput = document.getElementById('picker-input');
  var pickerListItems = document.getElementById('picker-list-items');
  var pickerStatus = document.getElementById('picker-status');
  var pickerPreview = document.getElementById('picker-preview');
  var btnOpenFile = document.getElementById('btn-open-file');
  var btnOpenFolder = document.getElementById('btn-open-folder');
  var pickerPathBar = document.getElementById('picker-path');
  var btnToggleTheme = document.getElementById('btn-toggle-theme');
  var btnSearch = document.getElementById('btn-search');
  var docRail = document.getElementById('doc-rail');
  var docMapFab = document.getElementById('doc-map-fab');
  var docMapBackdrop = document.getElementById('doc-map-backdrop');
  var docMapSheet = document.getElementById('doc-map-sheet');
  var docMapContent = document.getElementById('doc-map-content');
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
  var scrollSpyObserver = null;
  var findBar = null;
  var findBarInput = null;
  var findBarCount = null;
  var findMatches = [];
  var findCurrentIndex = -1;
  var findDebounceTimer = null;

  mermaid.initialize({ startOnLoad: false, theme: currentTheme === 'dark' ? 'dark' : 'default' });

  function renderMermaid() {
    var blocks = ctn.querySelectorAll('pre.mermaid');
    if (blocks.length > 0) {
      blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
      mermaid.run({ nodes: blocks });
    }
  }

  // ── Find-in-document bar ────────────────────────
  function buildFindBar() {
    var pageBody = document.getElementById('page-body');
    if (!pageBody) return; // no page-body on empty/browse pages

    var bar = document.createElement('div');
    bar.id = 'find-bar';
    bar.innerHTML =
      '<svg id="find-bar-icon" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>' +
      '<input id="find-bar-input" type="text" placeholder="Find in document\u2026" autocomplete="off" spellcheck="false">' +
      '<span id="find-bar-count"></span>' +
      '<button class="find-bar-btn" id="find-bar-prev" aria-label="Previous match"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="18 15 12 9 6 15"/></svg></button>' +
      '<button class="find-bar-btn" id="find-bar-next" aria-label="Next match"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="6 9 12 15 18 9"/></svg></button>' +
      '<button class="find-bar-btn" id="find-bar-close" aria-label="Close search"><svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg></button>';

    pageBody.insertBefore(bar, pageBody.firstChild);

    findBar = bar;
    findBarInput = document.getElementById('find-bar-input');
    findBarCount = document.getElementById('find-bar-count');

    findBarInput.addEventListener('input', function() {
      clearTimeout(findDebounceTimer);
      findDebounceTimer = setTimeout(performSearch, 150);
    });

    findBarInput.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (e.shiftKey) {
          navigateMatch(-1);
        } else {
          navigateMatch(1);
        }
      }
      if (e.key === 'Escape') {
        e.preventDefault();
        closeFindBar();
      }
    });

    document.getElementById('find-bar-prev').addEventListener('click', function() { navigateMatch(-1); });
    document.getElementById('find-bar-next').addEventListener('click', function() { navigateMatch(1); });
    document.getElementById('find-bar-close').addEventListener('click', function() { closeFindBar(); });
  }

  buildFindBar();

  function clearHighlights() {
    var marks = ctn.querySelectorAll('mark.find-match');
    for (var i = 0; i < marks.length; i++) {
      var mark = marks[i];
      var parent = mark.parentNode;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    }
    findMatches = [];
    findCurrentIndex = -1;
  }

  function reapplyFindHighlights() {
    if (findBar && findBar.classList.contains('open') && findBarInput && findBarInput.value) {
      performSearch();
    }
  }

  function performSearch() {
    clearHighlights();
    var query = findBarInput ? findBarInput.value : '';
    if (!query) {
      if (findBarCount) findBarCount.textContent = '';
      return;
    }

    var lowerQuery = query.toLowerCase();
    var walker = document.createTreeWalker(ctn, NodeFilter.SHOW_TEXT, {
      acceptNode: function(node) {
        var parent = node.parentNode;
        if (!parent) return NodeFilter.FILTER_REJECT;
        var tag = parent.tagName;
        if (tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });

    var textNodes = [];
    while (walker.nextNode()) {
      textNodes.push(walker.currentNode);
    }

    for (var i = 0; i < textNodes.length; i++) {
      var node = textNodes[i];
      var text = node.textContent;
      var lowerText = text.toLowerCase();
      var idx = lowerText.indexOf(lowerQuery);
      if (idx === -1) continue;

      var parent = node.parentNode;
      var frag = document.createDocumentFragment();
      var lastIdx = 0;

      while (idx !== -1) {
        if (idx > lastIdx) {
          frag.appendChild(document.createTextNode(text.substring(lastIdx, idx)));
        }
        var mark = document.createElement('mark');
        mark.className = 'find-match';
        mark.textContent = text.substring(idx, idx + query.length);
        frag.appendChild(mark);
        findMatches.push(mark);
        lastIdx = idx + query.length;
        idx = lowerText.indexOf(lowerQuery, lastIdx);
      }

      if (lastIdx < text.length) {
        frag.appendChild(document.createTextNode(text.substring(lastIdx)));
      }

      parent.replaceChild(frag, node);
    }

    if (findMatches.length > 0) {
      findCurrentIndex = 0;
      findMatches[0].classList.add('active');
      findMatches[0].scrollIntoView({ block: 'center', behavior: 'smooth' });
    }

    updateFindCount();
  }

  function updateFindCount() {
    if (!findBarCount) return;
    if (findMatches.length === 0) {
      findBarCount.textContent = findBarInput && findBarInput.value ? '0 results' : '';
    } else {
      findBarCount.textContent = (findCurrentIndex + 1) + ' of ' + findMatches.length;
    }
  }

  function navigateMatch(direction) {
    if (findMatches.length === 0) return;
    findMatches[findCurrentIndex].classList.remove('active');
    findCurrentIndex = (findCurrentIndex + direction + findMatches.length) % findMatches.length;
    findMatches[findCurrentIndex].classList.add('active');
    findMatches[findCurrentIndex].scrollIntoView({ block: 'center', behavior: 'smooth' });
    updateFindCount();
  }

  function openFindBar() {
    if (!findBar) return;
    findBar.classList.add('open');
    findBarInput.focus();
    findBarInput.select();
  }

  function closeFindBar() {
    if (!findBar) return;
    findBar.classList.remove('open');
    clearHighlights();
    if (findBarInput) findBarInput.value = '';
    if (findBarCount) findBarCount.textContent = '';
  }

  // ── Alert metadata ─────────────────────────────
  var alertIcons = {
    warning: '\u26A0\uFE0F',
    note: '\u{1F4DD}',
    tip: '\u{1F4A1}',
    important: '\u2757',
    caution: '\u{1F6A8}'
  };
  var alertColors = {
    warning: '#e6a700',
    note: '#7aa2f7',
    tip: '#73daca',
    important: '#bb9af7',
    caution: '#ff757f'
  };

  // ── Doc Navigation Rail ─────────────────────────
  function updateDocNav(headings, alerts) {
    if (!docRail) return;
    var hasNav = (headings && headings.length > 0) || (alerts && alerts.length > 0);

    if (!hasNav) {
      docRail.innerHTML = '';
      docRail.classList.remove('visible');
      if (docMapFab) docMapFab.classList.remove('visible');
      return;
    }

    var html = buildNavHtml(headings, alerts);
    docRail.innerHTML = html;
    docRail.classList.add('visible');

    // Mobile FAB
    if (docMapFab) {
      docMapFab.classList.add('visible');
      var warnCount = alerts ? alerts.filter(function(a) { return a.type === 'warning'; }).length : 0;
      docMapFab.innerHTML = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="3" y1="6" x2="21" y2="6"/><line x1="3" y1="12" x2="21" y2="12"/><line x1="3" y1="18" x2="21" y2="18"/></svg>'
        + '<span class="doc-fab-label">Map</span>'
        + (warnCount > 0 ? '<span class="doc-fab-badge">' + warnCount + '</span>' : '');
    }

    // Update mobile sheet content too
    if (docMapContent) {
      docMapContent.innerHTML = buildNavHtml(headings, alerts);
    }

    bindNavClicks(docRail);
    if (docMapContent) bindNavClicks(docMapContent);
    initScrollSpy();
  }

  function buildNavHtml(headings, alerts) {
    var html = '';
    if (headings && headings.length > 0) {
      html += '<div class="doc-rail-section"><div class="doc-rail-title">Contents</div>';
      headings.forEach(function(h) {
        var cls = 'doc-rail-link';
        if (h.level === 3) cls += ' doc-rail-h3';
        html += '<a class="' + cls + '" href="#' + escapeHtml(h.id) + '" data-target="' + escapeHtml(h.id) + '">'
          + escapeHtml(h.text) + '</a>';
      });
      html += '</div>';
    }
    if (alerts && alerts.length > 0) {
      html += '<div class="doc-rail-section doc-rail-alerts"><div class="doc-rail-title">Alerts</div>';
      alerts.forEach(function(a) {
        var icon = alertIcons[a.type] || '';
        var color = alertColors[a.type] || 'inherit';
        html += '<a class="doc-rail-link doc-rail-alert" href="#' + escapeHtml(a.id) + '" data-target="' + escapeHtml(a.id) + '" style="color:' + color + '">'
          + '<span class="doc-rail-alert-icon">' + icon + '</span> '
          + escapeHtml(a.title) + '</a>';
      });
      html += '</div>';
    }
    return html;
  }

  function bindNavClicks(container) {
    container.addEventListener('click', function(e) {
      var link = e.target.closest('.doc-rail-link');
      if (!link) return;
      e.preventDefault();
      var targetId = link.dataset.target;
      var target = document.getElementById(targetId);
      if (!target) return;

      // Close mobile sheet if open
      if (docMapSheet && docMapSheet.classList.contains('open')) {
        closeDocMapSheet();
        setTimeout(function() { scrollToTarget(target); }, 300);
      } else {
        scrollToTarget(target);
      }
    });
  }

  function scrollToTarget(target) {
    target.scrollIntoView({ behavior: 'smooth', block: 'start' });
    // Flash highlight
    target.classList.add('doc-highlight');
    setTimeout(function() { target.classList.remove('doc-highlight'); }, 1200);
  }

  // ── ScrollSpy ──────────────────────────────────
  function initScrollSpy() {
    if (scrollSpyObserver) {
      scrollSpyObserver.disconnect();
      scrollSpyObserver = null;
    }
    if (!ctn) return;

    var headingEls = ctn.querySelectorAll('h2[id], h3[id]');
    if (headingEls.length === 0) return;

    scrollSpyObserver = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          setActiveRailLink(entry.target.id);
        }
      });
    }, {
      rootMargin: '-10% 0px -80% 0px',
      threshold: 0
    });

    headingEls.forEach(function(el) {
      scrollSpyObserver.observe(el);
    });
  }

  function setActiveRailLink(id) {
    // Desktop rail
    if (docRail) {
      var links = docRail.querySelectorAll('.doc-rail-link');
      links.forEach(function(l) { l.classList.remove('doc-rail-active'); });
      var active = docRail.querySelector('[data-target="' + id + '"]');
      if (active) active.classList.add('doc-rail-active');
    }
    // Mobile sheet
    if (docMapContent) {
      var mLinks = docMapContent.querySelectorAll('.doc-rail-link');
      mLinks.forEach(function(l) { l.classList.remove('doc-rail-active'); });
      var mActive = docMapContent.querySelector('[data-target="' + id + '"]');
      if (mActive) mActive.classList.add('doc-rail-active');
    }
  }

  // ── Mobile Bottom Sheet ────────────────────────
  var sheetTouchStartY = 0;
  var sheetTouchCurrentY = 0;

  function openDocMapSheet() {
    if (!docMapSheet) return;
    docMapBackdrop.classList.add('open');
    docMapSheet.classList.add('open');
  }

  function closeDocMapSheet() {
    if (!docMapSheet) return;
    docMapSheet.style.transform = '';
    docMapSheet.classList.remove('open');
    docMapBackdrop.classList.remove('open');
  }

  if (docMapFab) {
    docMapFab.addEventListener('click', function() {
      openDocMapSheet();
    });
  }

  if (docMapBackdrop) {
    docMapBackdrop.addEventListener('click', function() {
      closeDocMapSheet();
    });
  }

  if (docMapSheet) {
    docMapSheet.addEventListener('touchstart', function(e) {
      sheetTouchStartY = e.touches[0].clientY;
      sheetTouchCurrentY = sheetTouchStartY;
      docMapSheet.style.transition = 'none';
    }, { passive: true });

    docMapSheet.addEventListener('touchmove', function(e) {
      sheetTouchCurrentY = e.touches[0].clientY;
      var dy = sheetTouchCurrentY - sheetTouchStartY;
      if (dy > 0) {
        docMapSheet.style.transform = 'translateY(' + dy + 'px)';
      }
    }, { passive: true });

    docMapSheet.addEventListener('touchend', function() {
      docMapSheet.style.transition = '';
      var dy = sheetTouchCurrentY - sheetTouchStartY;
      if (dy > 80) {
        closeDocMapSheet();
      } else {
        docMapSheet.style.transform = '';
      }
    });
  }

  // ── Handle content updates with nav data ───────
  function handleContentUpdate(data) {
    if (typeof data === 'string') {
      // Try to parse as JSON (new format)
      try {
        var parsed = JSON.parse(data);
        if (parsed.html !== undefined) {
          ctn.innerHTML = parsed.html;
          renderMermaid();
          updateDocNav(parsed.headings || [], parsed.alerts || []);
          return;
        }
      } catch(e) {
        // Not JSON, treat as raw HTML (legacy)
      }
      ctn.innerHTML = data;
      renderMermaid();
      return;
    }
    // Object with html/headings/alerts
    ctn.innerHTML = data.html;
    renderMermaid();
    updateDocNav(data.headings || [], data.alerts || []);
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
    pickerStatus.textContent = 'Searching\u2026';
    pickerListItems.innerHTML = '<div class="picker-skeleton">'
      + Array(8).fill('<div class="picker-skeleton-row"><div class="skeleton-bone title"></div><div class="skeleton-bone file"></div></div>').join('')
      + '</div>';
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
          + '<div class="picker-item-title">' + escapeHtml(title) + '</div>'
          + '<div class="picker-item-file">' + escapeHtml(f.filename)
          + (relDir ? '<span class="picker-item-dir">' + escapeHtml(relDir + '/') + '</span>' : '')
          + '</div>'
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
        headerFilename.textContent = data.filename;
        if (headerDir) headerDir.textContent = data.rel_dir || '';
        document.title = data.filename;
        history.replaceState(null, '', '/?path=' + encodeURIComponent(currentPath));
        if (data.html) {
          handleContentUpdate(data);
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
          headerFilename.textContent = switchData.filename;
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

  // ── Global keyboard & header actions ──────────

  function toggleTheme() {
    fetch('/toggle-theme').then(function(r) { return r.json(); }).then(function(data) {
      var el = document.querySelector('[data-theme]');
      el.dataset.theme = data.theme;
      currentTheme = data.theme;
      mermaid.initialize({ startOnLoad: false, theme: data.theme === 'dark' ? 'dark' : 'default' });
      renderMermaid();
    });
  }

  document.getElementById('header-file-info').addEventListener('click', function() {
    if (pickerOverlay.classList.contains('open')) {
      pickerInput.focus();
    } else {
      openPicker();
    }
  });

  if (btnToggleTheme) {
    btnToggleTheme.addEventListener('click', function(e) {
      e.stopPropagation();
      toggleTheme();
    });
  }

  if (btnSearch) {
    btnSearch.addEventListener('click', function(e) {
      e.stopPropagation();
      if (pickerOverlay.classList.contains('open')) {
        pickerInput.focus();
      } else {
        openPicker();
      }
    });
  }

  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
      if (findBar && findBar.classList.contains('open')) {
        closeFindBar();
        return;
      }
      if (docMapSheet && docMapSheet.classList.contains('open')) {
        closeDocMapSheet();
        return;
      }
      if (pickerOverlay.classList.contains('open')) {
        closePicker();
        return;
      }
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
      toggleTheme();
    }
    if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
      e.preventDefault();
      if (findBar && findBar.classList.contains('open')) {
        findBarInput.focus();
        findBarInput.select();
      } else {
        openFindBar();
      }
      return;
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
      handleContentUpdate(e.data);
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
  // Populate header directory breadcrumb from server-rendered data
  if (headerDir) {
    headerDir.textContent = document.body.dataset.relDir || '';
  }

  // Load initial nav data from server-rendered attribute
  var initialNav = document.body.dataset.nav;
  if (initialNav) {
    try {
      var navData = JSON.parse(initialNav);
      updateDocNav(navData.headings || [], navData.alerts || []);
    } catch(e) {}
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
