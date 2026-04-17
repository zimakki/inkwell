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
  var zoomModal = null;
  var zoomModalBackdrop = null;
  var zoomModalViewport = null;
  var zoomModalCanvas = null;
  var zoomModalTitle = null;
  var zoomModalState = {
    isOpen: false,
    type: null,
    source: null,
    scale: 1,
    fitScale: 1,
    minScale: 0.2,
    maxScale: 12,
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    pointerId: null,
    dragStartX: 0,
    dragStartY: 0,
    startX: 0,
    startY: 0,
    scrollTop: 0
  };

  // ── Document zoom (Cmd+/-/0) ──
  var ZOOM_MIN = 0.5;
  var ZOOM_MAX = 3.0;
  var ZOOM_STEP = 1.2;
  var currentZoom = (function() {
    var stored = parseFloat(localStorage.getItem('inkwell-zoom'));
    if (!isFinite(stored) || stored < ZOOM_MIN || stored > ZOOM_MAX) return 1.0;
    return stored;
  })();

  function applyZoom() {
    if (ctn) ctn.style.zoom = String(currentZoom);
  }

  function setZoom(next) {
    var clamped = Math.max(ZOOM_MIN, Math.min(ZOOM_MAX, next));
    if (clamped === currentZoom) return;
    currentZoom = clamped;
    localStorage.setItem('inkwell-zoom', String(currentZoom));
    applyZoom();
  }

  applyZoom();

  // ── View mode state ──
  var currentMode = (function() {
    var dataMode = document.body.dataset.mode;
    if (dataMode && (dataMode === 'diff' || dataMode === 'live' || dataMode === 'static')) {
      return dataMode;
    }
    var stored = localStorage.getItem('inkwell-mode');
    if (stored && (stored === 'diff' || stored === 'live' || stored === 'static')) {
      return stored;
    }
    return 'diff';
  })();
  var baselineBlocks = [];
  var pendingHtml = null;
  var pendingHeadings = null;
  var pendingAlerts = null;
  var diffDebounceTimer = null;
  var isFirstWsMessage = true;

  mermaid.initialize({ startOnLoad: false, theme: currentTheme === 'dark' ? 'dark' : 'default' });

  // ── Build mode toggle ──
  var modeIcons = { static: '\u23F8', live: '\u21BB', diff: '\u25D1' };
  var modeToggle = document.createElement('div');
  modeToggle.id = 'mode-toggle';
  ['static', 'live', 'diff'].forEach(function(mode) {
    var btn = document.createElement('button');
    btn.className = 'mode-btn' + (mode === currentMode ? ' mode-btn--active' : '');
    btn.innerHTML = '<span class="mode-icon">' + modeIcons[mode] + '</span> ' + mode.charAt(0).toUpperCase() + mode.slice(1);
    btn.dataset.mode = mode;
    btn.addEventListener('click', function() { switchMode(mode); });
    var tip = document.createElement('span');
    tip.className = 'header-tooltip';
    tip.textContent = mode === 'static' ? 'Freeze view' : mode === 'live' ? 'Auto-update on save' : 'Highlight changes';
    btn.appendChild(tip);
    modeToggle.appendChild(btn);
  });

  // Info button to show/re-show welcome card
  var modeInfoBtn = document.createElement('button');
  modeInfoBtn.className = 'mode-info-btn';
  modeInfoBtn.innerHTML = 'i';
  modeInfoBtn.title = 'About view modes';
  modeToggle.appendChild(modeInfoBtn);

  var headerActions = document.getElementById('header-actions');
  if (headerActions && currentPath) {
    headerActions.insertBefore(modeToggle, headerActions.firstChild);
  }

  // ── Welcome card ──
  var modeWelcomeCard = null;

  function buildWelcomeCard() {
    if (modeWelcomeCard) { modeWelcomeCard.remove(); modeWelcomeCard = null; return; }
    var card = document.createElement('div');
    card.id = 'mode-welcome-card';
    card.innerHTML =
      '<div class="welcome-inner">' +
        '<span class="welcome-wave">\uD83D\uDC4B</span>' +
        '<div class="welcome-body">' +
          '<div class="welcome-title">View Modes</div>' +
          '<div class="welcome-modes">' +
            '<div><strong>' + modeIcons.static + ' Static</strong> \u2014 Freeze the current view</div>' +
            '<div><strong>' + modeIcons.live + ' Live</strong> \u2014 Auto-update when the file changes</div>' +
            '<div><strong style="color:#a6e3a1;">' + modeIcons.diff + ' Diff</strong> \u2014 Highlight what changed <span class="welcome-default">(default)</span></div>' +
          '</div>' +
          '<div class="welcome-actions"><button class="welcome-dismiss">Got it</button></div>' +
        '</div>' +
      '</div>';
    card.querySelector('.welcome-dismiss').addEventListener('click', function() {
      card.remove();
      modeWelcomeCard = null;
      localStorage.setItem('inkwell-mode-welcomed', 'true');
    });
    modeWelcomeCard = card;
    modeToggle.appendChild(card);
  }

  modeInfoBtn.addEventListener('click', function(e) {
    e.stopPropagation();
    buildWelcomeCard();
  });

  // Show on first visit
  if (currentPath && !localStorage.getItem('inkwell-mode-welcomed')) {
    setTimeout(buildWelcomeCard, 300);
  }

  // ── Build global accept FAB ──
  var diffFab = document.createElement('div');
  diffFab.id = 'diff-accept-fab';
  diffFab.innerHTML = '<div class="diff-summary"></div><div class="diff-separator"></div><button class="accept-all-btn"><span>\u2713 Accept</span> <span class="shortcut">\u2318\u23CE</span></button>';
  document.body.appendChild(diffFab);
  diffFab.querySelector('.accept-all-btn').addEventListener('click', function() {
    acceptAll();
  });

  function renderMermaid() {
    var blocks = ctn.querySelectorAll('pre.mermaid');
    if (blocks.length > 0) {
      blocks.forEach(function(el) { el.removeAttribute('data-processed'); });
      mermaid.run({ nodes: blocks });
    }
  }

  function buildZoomModal() {
    if (zoomModal) return;

    zoomModal = document.createElement('div');
    zoomModal.id = 'zoom-modal';
    zoomModal.setAttribute('aria-hidden', 'true');
    zoomModal.innerHTML =
      '<div id="zoom-modal-backdrop"></div>' +
      '<div id="zoom-modal-dialog" role="dialog" aria-modal="true" aria-label="Zoomed content">' +
        '<div id="zoom-modal-toolbar">' +
          '<div id="zoom-modal-title"></div>' +
          '<div id="zoom-modal-actions">' +
            '<button type="button" class="zoom-modal-btn" data-action="zoom-in" aria-label="Zoom in">+</button>' +
            '<button type="button" class="zoom-modal-btn" data-action="zoom-out" aria-label="Zoom out">\u2212</button>' +
            '<button type="button" class="zoom-modal-btn zoom-modal-btn-reset" data-action="reset">Reset</button>' +
            '<button type="button" class="zoom-modal-btn zoom-modal-btn-close" data-action="close" aria-label="Close">\u00D7</button>' +
          '</div>' +
        '</div>' +
        '<div id="zoom-modal-viewport">' +
          '<div id="zoom-modal-canvas"></div>' +
        '</div>' +
      '</div>';

    document.body.appendChild(zoomModal);

    zoomModalBackdrop = document.getElementById('zoom-modal-backdrop');
    zoomModalViewport = document.getElementById('zoom-modal-viewport');
    zoomModalCanvas = document.getElementById('zoom-modal-canvas');
    zoomModalTitle = document.getElementById('zoom-modal-title');

    zoomModalBackdrop.addEventListener('click', function() {
      closeZoomModal();
    });

    zoomModal.addEventListener('click', function(e) {
      var actionEl = e.target.closest('[data-action]');
      if (!actionEl) return;
      e.preventDefault();
      var action = actionEl.dataset.action;
      if (action === 'zoom-in') {
        stepZoom(1.25);
      } else if (action === 'zoom-out') {
        stepZoom(0.8);
      } else if (action === 'reset') {
        resetZoomModal();
      } else if (action === 'close') {
        closeZoomModal();
      }
    });

    zoomModalViewport.addEventListener('wheel', function(e) {
      if (!zoomModalState.isOpen) return;
      e.preventDefault();

      var delta = e.deltaY;
      var multiplier = delta < 0 ? 1.1 : 0.9;
      if (e.ctrlKey) multiplier = delta < 0 ? 1.08 : 0.92;
      zoomAroundPoint(e.clientX, e.clientY, zoomModalState.scale * multiplier);
    }, { passive: false });

    zoomModalViewport.addEventListener('pointerdown', function(e) {
      if (!zoomModalState.isOpen || e.button !== 0) return;
      if (!zoomModalCanvas.firstElementChild) return;
      e.preventDefault();
      zoomModalState.pointerId = e.pointerId;
      zoomModalState.dragStartX = e.clientX;
      zoomModalState.dragStartY = e.clientY;
      zoomModalState.startX = zoomModalState.x;
      zoomModalState.startY = zoomModalState.y;
      zoomModalViewport.classList.add('is-dragging');
      zoomModalViewport.setPointerCapture(e.pointerId);
    });

    zoomModalViewport.addEventListener('pointermove', function(e) {
      if (zoomModalState.pointerId !== e.pointerId) return;
      zoomModalState.x = zoomModalState.startX + (e.clientX - zoomModalState.dragStartX);
      zoomModalState.y = zoomModalState.startY + (e.clientY - zoomModalState.dragStartY);
      applyZoomModalTransform();
    });

    function stopDragging(e) {
      if (zoomModalState.pointerId !== e.pointerId) return;
      zoomModalState.pointerId = null;
      zoomModalViewport.classList.remove('is-dragging');
      if (zoomModalViewport.hasPointerCapture(e.pointerId)) {
        zoomModalViewport.releasePointerCapture(e.pointerId);
      }
    }

    zoomModalViewport.addEventListener('pointerup', stopDragging);
    zoomModalViewport.addEventListener('pointercancel', stopDragging);

    window.addEventListener('resize', function() {
      if (!zoomModalState.isOpen) return;
      fitZoomModalContent();
    });
  }

  function clampZoomScale(scale) {
    return Math.min(zoomModalState.maxScale, Math.max(zoomModalState.minScale, scale));
  }

  function applyZoomModalTransform() {
    zoomModalCanvas.style.width = zoomModalState.width + 'px';
    zoomModalCanvas.style.height = zoomModalState.height + 'px';
    zoomModalCanvas.style.transform =
      'translate(' + zoomModalState.x + 'px, ' + zoomModalState.y + 'px) scale(' + zoomModalState.scale + ')';
  }

  function fitZoomModalContent() {
    if (!zoomModalViewport || !zoomModalCanvas.firstElementChild) return;

    var rect = zoomModalViewport.getBoundingClientRect();
    var padding = 40;
    var availableWidth = Math.max(rect.width - padding * 2, 120);
    var availableHeight = Math.max(rect.height - padding * 2, 120);

    zoomModalState.fitScale = Math.min(
      availableWidth / zoomModalState.width,
      availableHeight / zoomModalState.height
    );

    if (!isFinite(zoomModalState.fitScale) || zoomModalState.fitScale <= 0) {
      zoomModalState.fitScale = 1;
    }

    zoomModalState.minScale = Math.min(0.2, zoomModalState.fitScale);

    resetZoomModal();
  }

  function resetZoomModal() {
    if (!zoomModalState.isOpen) return;
    var rect = zoomModalViewport.getBoundingClientRect();
    zoomModalState.scale = zoomModalState.fitScale;
    zoomModalState.x = (rect.width - zoomModalState.width * zoomModalState.scale) / 2;
    zoomModalState.y = (rect.height - zoomModalState.height * zoomModalState.scale) / 2;
    applyZoomModalTransform();
  }

  function zoomAroundPoint(clientX, clientY, nextScale) {
    if (!zoomModalState.isOpen) return;

    var rect = zoomModalViewport.getBoundingClientRect();
    var pointX = clientX - rect.left;
    var pointY = clientY - rect.top;
    var clampedScale = clampZoomScale(nextScale);
    var contentX = (pointX - zoomModalState.x) / zoomModalState.scale;
    var contentY = (pointY - zoomModalState.y) / zoomModalState.scale;

    zoomModalState.scale = clampedScale;
    zoomModalState.x = pointX - contentX * clampedScale;
    zoomModalState.y = pointY - contentY * clampedScale;
    applyZoomModalTransform();
  }

  function stepZoom(multiplier) {
    if (!zoomModalState.isOpen) return;
    var rect = zoomModalViewport.getBoundingClientRect();
    zoomAroundPoint(rect.left + rect.width / 2, rect.top + rect.height / 2, zoomModalState.scale * multiplier);
  }

  function getMermaidDimensions(svg, fallbackRect) {
    var viewBox = svg.viewBox && svg.viewBox.baseVal;
    if (viewBox && viewBox.width > 0 && viewBox.height > 0) {
      return { width: viewBox.width, height: viewBox.height };
    }

    var width = svg.width && svg.width.baseVal ? svg.width.baseVal.value : 0;
    var height = svg.height && svg.height.baseVal ? svg.height.baseVal.value : 0;
    if (width > 0 && height > 0) {
      return { width: width, height: height };
    }

    return {
      width: Math.max(fallbackRect.width, 1),
      height: Math.max(fallbackRect.height, 1)
    };
  }

  function openZoomModalForMermaid(preEl) {
    var svg = preEl.querySelector('svg');
    if (!svg) return;

    var clone = svg.cloneNode(true);
    var sourceRect = svg.getBoundingClientRect();
    var size = getMermaidDimensions(svg, sourceRect);

    clone.removeAttribute('width');
    clone.removeAttribute('height');
    clone.style.width = '100%';
    clone.style.height = '100%';
    clone.style.display = 'block';

    openZoomModal({
      type: 'mermaid',
      title: 'Diagram',
      source: preEl,
      node: clone,
      width: size.width,
      height: size.height
    });
  }

  function openZoomModalForImage(imgEl) {
    var clone = document.createElement('img');
    clone.src = imgEl.currentSrc || imgEl.src;
    clone.alt = imgEl.alt || '';
    clone.decoding = 'async';
    clone.style.width = '100%';
    clone.style.height = '100%';
    clone.style.display = 'block';
    clone.style.objectFit = 'contain';

    function finishOpen() {
      openZoomModal({
        type: 'image',
        title: imgEl.alt ? imgEl.alt : 'Image',
        source: imgEl,
        node: clone,
        width: clone.naturalWidth || imgEl.naturalWidth || imgEl.width || 1,
        height: clone.naturalHeight || imgEl.naturalHeight || imgEl.height || 1
      });
    }

    if (imgEl.complete && imgEl.naturalWidth > 0) {
      finishOpen();
      return;
    }

    clone.addEventListener('load', finishOpen, { once: true });
  }

  function openZoomModal(config) {
    buildZoomModal();

    zoomModalCanvas.innerHTML = '';
    zoomModalCanvas.appendChild(config.node);
    zoomModalTitle.textContent = config.title;

    zoomModalState.isOpen = true;
    zoomModalState.type = config.type;
    zoomModalState.source = config.source;
    zoomModalState.width = Math.max(config.width, 1);
    zoomModalState.height = Math.max(config.height, 1);
    zoomModalState.scale = 1;
    zoomModalState.x = 0;
    zoomModalState.y = 0;
    zoomModalState.scrollTop = window.scrollY || document.documentElement.scrollTop || document.body.scrollTop || 0;

    zoomModal.classList.add('open');
    zoomModal.setAttribute('aria-hidden', 'false');
    document.body.classList.add('zoom-modal-open');

    fitZoomModalContent();
  }

  function closeZoomModal() {
    if (!zoomModalState.isOpen || !zoomModal) return;

    zoomModalState.isOpen = false;
    zoomModalState.type = null;
    zoomModalState.source = null;
    zoomModalState.pointerId = null;
    zoomModal.classList.remove('open');
    zoomModal.setAttribute('aria-hidden', 'true');
    zoomModalViewport.classList.remove('is-dragging');
    document.body.classList.remove('zoom-modal-open');
    zoomModalCanvas.innerHTML = '';
    window.scrollTo(0, zoomModalState.scrollTop);
  }

  ctn.addEventListener('click', function(e) {
    var image = e.target.closest('img');
    if (image && ctn.contains(image)) {
      e.preventDefault();
      openZoomModalForImage(image);
      return;
    }

    var mermaidPre = e.target.closest('pre.mermaid');
    if (mermaidPre && ctn.contains(mermaidPre) && mermaidPre.querySelector('svg')) {
      e.preventDefault();
      openZoomModalForMermaid(mermaidPre);
    }
  });

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
      while (mark.firstChild) {
        parent.insertBefore(mark.firstChild, mark);
      }
      parent.removeChild(mark);
      parent.normalize();
    }
    findMatches = [];
    findCurrentIndex = -1;
  }

  function reapplyFindHighlights() {
    if (findBar && findBar.classList.contains('open') && findBarInput && findBarInput.value) {
      clearTimeout(findDebounceTimer);
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
        // Skip SVG internals — wrapping SVG text in <mark> breaks diagram rendering
        if (node.parentNode.closest && node.parentNode.closest('svg')) return NodeFilter.FILTER_REJECT;
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
        mark.textContent = text.substring(idx, idx + lowerQuery.length);
        frag.appendChild(mark);
        findMatches.push(mark);
        lastIdx = idx + lowerQuery.length;
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
    if (findCurrentIndex < 0) findCurrentIndex = 0;
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

  function getFindBarSelectionSeed() {
    if (!window.getSelection || document.activeElement === findBarInput) return '';

    var selection = window.getSelection();
    if (!selection || selection.isCollapsed) return '';

    var seed = selection.toString().trim();
    if (!seed || seed.length > 200) return '';
    if (seed.indexOf('\n') !== -1 || seed.indexOf('\r') !== -1) return '';

    return seed;
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

  // ── Diff helpers ──
  function extractBlocks(container) {
    var blocks = [];
    var children = container.children;
    for (var i = 0; i < children.length; i++) {
      var el = children[i];
      blocks.push({
        tag: el.tagName.toLowerCase(),
        textContent: el.textContent.replace(/\s+/g, ' ').trim(),
        outerHTML: el.outerHTML
      });
    }
    return blocks;
  }

  function lcs(a, b, eq) {
    var m = a.length, n = b.length;
    var dp = [];
    for (var i = 0; i <= m; i++) {
      dp[i] = [];
      for (var j = 0; j <= n; j++) {
        if (i === 0 || j === 0) {
          dp[i][j] = 0;
        } else if (eq(a[i - 1], b[j - 1])) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }
    var result = [];
    var i = m, j = n;
    while (i > 0 && j > 0) {
      if (eq(a[i - 1], b[j - 1])) {
        result.unshift({ ai: i - 1, bi: j - 1 });
        i--; j--;
      } else if (dp[i - 1][j] > dp[i][j - 1]) {
        i--;
      } else {
        j--;
      }
    }
    return result;
  }

  function computeBlockDiff(oldBlocks, newBlocks) {
    var matched = lcs(oldBlocks, newBlocks, function(a, b) {
      return a.tag === b.tag && a.textContent === b.textContent;
    });

    var result = [];
    var oi = 0, ni = 0, mi = 0;

    while (oi < oldBlocks.length || ni < newBlocks.length) {
      if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
        result.push({ type: 'unchanged', oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
        oi++; ni++; mi++;
      } else if (mi < matched.length && oi < matched[mi].ai && ni < matched[mi].bi) {
        var oldEnd = matched[mi].ai;
        var newEnd = matched[mi].bi;
        while (oi < oldEnd && ni < newEnd) {
          if (oldBlocks[oi].tag === newBlocks[ni].tag) {
            result.push({ type: 'modified', oldBlock: oldBlocks[oi], newBlock: newBlocks[ni], oldIndex: oi, newIndex: ni });
          } else {
            result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
            result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
          }
          oi++; ni++;
        }
        while (oi < oldEnd) {
          result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
          oi++;
        }
        while (ni < newEnd) {
          result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
          ni++;
        }
      } else if (oi < oldBlocks.length && (mi >= matched.length || oi < matched[mi].ai)) {
        result.push({ type: 'removed', oldBlock: oldBlocks[oi], oldIndex: oi });
        oi++;
      } else if (ni < newBlocks.length) {
        result.push({ type: 'added', newBlock: newBlocks[ni], newIndex: ni });
        ni++;
      }
    }

    return result;
  }

  function computeWordDiff(oldText, newText) {
    var oldWords = oldText.split(/(\s+)/);
    var newWords = newText.split(/(\s+)/);

    var matched = lcs(oldWords, newWords, function(a, b) { return a === b; });

    var spans = [];
    var oi = 0, ni = 0, mi = 0;

    while (oi < oldWords.length || ni < newWords.length) {
      if (mi < matched.length && matched[mi].ai === oi && matched[mi].bi === ni) {
        spans.push({ type: 'same', text: newWords[ni] });
        oi++; ni++; mi++;
      } else {
        var removedStart = oi;
        while (oi < oldWords.length && (mi >= matched.length || oi < matched[mi].ai)) {
          oi++;
        }
        if (oi > removedStart) {
          spans.push({ type: 'removed', text: oldWords.slice(removedStart, oi).join('') });
        }
        var addedStart = ni;
        while (ni < newWords.length && (mi >= matched.length || ni < matched[mi].bi)) {
          ni++;
        }
        if (ni > addedStart) {
          spans.push({ type: 'added', text: newWords.slice(addedStart, ni).join('') });
        }
      }
    }

    return spans;
  }

  function buildWordDiffHTML(oldText, newText) {
    var spans = computeWordDiff(oldText, newText);
    var html = '';
    spans.forEach(function(span) {
      var escaped = span.text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      if (span.type === 'same') {
        html += escaped;
      } else if (span.type === 'added') {
        html += '<span class="inkwell-diff-word-added">' + escaped + '</span>';
      } else if (span.type === 'removed') {
        html += '<span class="inkwell-diff-word-removed">' + escaped + '</span>';
      }
    });
    return html;
  }

  function createElementFromHTML(htmlString) {
    var temp = document.createElement('div');
    temp.innerHTML = htmlString;
    return temp.firstElementChild;
  }

  function addPerBlockAcceptBtn(el, diffIndex) {
    var btn = document.createElement('button');
    btn.className = 'inkwell-diff-accept-btn';
    btn.innerHTML = '\u2713';
    btn.title = 'Accept this change';
    btn.addEventListener('click', function(e) {
      e.stopPropagation();
      acceptBlock(el, diffIndex);
    });
    el.appendChild(btn);
  }

  function parseContentPayload(data) {
    if (typeof data === 'string') {
      try {
        var parsed = JSON.parse(data);
        if (parsed.html !== undefined) {
          return { html: parsed.html, headings: parsed.headings || [], alerts: parsed.alerts || [] };
        }
      } catch(e) {}
      return { html: data, headings: [], alerts: [] };
    }
    return { html: data.html, headings: data.headings || [], alerts: data.alerts || [] };
  }

  function applyDiff(html, headings, alerts) {
    var tempDiv = document.createElement('div');
    tempDiv.innerHTML = html;
    var newBlocks = extractBlocks(tempDiv);

    var diff = computeBlockDiff(baselineBlocks, newBlocks);

    var scrollEl = ctn.parentElement || document.documentElement;
    var scrollPos = scrollEl.scrollTop;

    ctn.innerHTML = '';
    diff.forEach(function(entry, idx) {
      var el;
      if (entry.type === 'unchanged') {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        ctn.appendChild(el);
      } else if (entry.type === 'added') {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        el.classList.add('inkwell-diff-added');
        el.dataset.diffIndex = idx;
        addPerBlockAcceptBtn(el, idx);
        ctn.appendChild(el);
      } else if (entry.type === 'removed') {
        el = createElementFromHTML(entry.oldBlock.outerHTML);
        el.classList.add('inkwell-diff-removed');
        el.dataset.diffIndex = idx;
        addPerBlockAcceptBtn(el, idx);
        ctn.appendChild(el);
      } else if (entry.type === 'modified') {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        el.classList.add('inkwell-diff-modified');
        el.dataset.diffIndex = idx;
        var oldText = entry.oldBlock.textContent;
        var newText = entry.newBlock.textContent;
        el.innerHTML = buildWordDiffHTML(oldText, newText);
        addPerBlockAcceptBtn(el, idx);
        ctn.appendChild(el);
      }
    });

    renderMermaid();
    updateDocNav(headings, alerts);
    reapplyFindHighlights();
    updateFab();

    scrollEl.scrollTop = scrollPos;
  }

  function clearDiffHighlights() {
    var highlighted = ctn.querySelectorAll('.inkwell-diff-added, .inkwell-diff-removed, .inkwell-diff-modified');
    highlighted.forEach(function(el) {
      if (el.classList.contains('inkwell-diff-removed')) {
        el.remove();
      } else {
        el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified');
        el.style.borderLeft = '';
        el.style.background = '';
        el.style.paddingLeft = '';
        var btn = el.querySelector('.inkwell-diff-accept-btn');
        if (btn) btn.remove();
        var wordSpans = el.querySelectorAll('.inkwell-diff-word-added, .inkwell-diff-word-removed');
        wordSpans.forEach(function(span) {
          if (span.classList.contains('inkwell-diff-word-removed')) {
            span.remove();
          } else {
            span.replaceWith(document.createTextNode(span.textContent));
          }
        });
      }
    });
  }

  function acceptBlock(el, diffIndex) {
    if (el.classList.contains('inkwell-diff-removed')) {
      el.style.transition = 'opacity 0.2s ease';
      el.style.opacity = '0';
      setTimeout(function() { el.remove(); updateFab(); }, 200);
    } else {
      var btn = el.querySelector('.inkwell-diff-accept-btn');
      if (btn) btn.remove();
      var wordSpans = el.querySelectorAll('.inkwell-diff-word-removed');
      wordSpans.forEach(function(span) { span.remove(); });
      var addedSpans = el.querySelectorAll('.inkwell-diff-word-added');
      addedSpans.forEach(function(span) {
        span.replaceWith(document.createTextNode(span.textContent));
      });
      el.classList.add('inkwell-diff-fade-out');
      setTimeout(function() {
        el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified', 'inkwell-diff-fade-out');
        el.style.borderLeft = '';
        el.style.background = '';
        el.style.paddingLeft = '';
        el.removeAttribute('data-diff-index');
        updateFab();
      }, 200);
    }
    setTimeout(function() {
      baselineBlocks = extractBlocks(ctn);
    }, 250);
  }

  function acceptAll() {
    var highlighted = ctn.querySelectorAll('.inkwell-diff-added, .inkwell-diff-removed, .inkwell-diff-modified');
    highlighted.forEach(function(el) {
      if (el.classList.contains('inkwell-diff-removed')) {
        el.remove();
      } else {
        var btn = el.querySelector('.inkwell-diff-accept-btn');
        if (btn) btn.remove();
        var wordSpans = el.querySelectorAll('.inkwell-diff-word-removed');
        wordSpans.forEach(function(span) { span.remove(); });
        var addedSpans = el.querySelectorAll('.inkwell-diff-word-added');
        addedSpans.forEach(function(span) {
          span.replaceWith(document.createTextNode(span.textContent));
        });
        el.classList.remove('inkwell-diff-added', 'inkwell-diff-modified');
        el.style.borderLeft = '';
        el.style.background = '';
        el.style.paddingLeft = '';
        el.removeAttribute('data-diff-index');
      }
    });
    baselineBlocks = extractBlocks(ctn);
    updateFab();
  }

  function updateFab() {
    var added = ctn.querySelectorAll('.inkwell-diff-added').length;
    var modified = ctn.querySelectorAll('.inkwell-diff-modified').length;
    var removed = ctn.querySelectorAll('.inkwell-diff-removed').length;
    var total = added + modified + removed;

    if (total === 0 || currentMode !== 'diff') {
      diffFab.classList.remove('visible');
      return;
    }

    var summaryParts = [];
    if (added > 0) summaryParts.push('<span class="added">+' + added + '</span>');
    if (modified > 0) summaryParts.push('<span class="modified">~' + modified + '</span>');
    if (removed > 0) summaryParts.push('<span class="removed">-' + removed + '</span>');

    diffFab.querySelector('.diff-summary').innerHTML = summaryParts.join(' ');
    diffFab.classList.add('visible');
  }

  function switchMode(newMode) {
    var oldMode = currentMode;
    currentMode = newMode;
    localStorage.setItem('inkwell-mode', newMode);

    var btns = modeToggle.querySelectorAll('.mode-btn');
    btns.forEach(function(btn) {
      if (btn.dataset.mode === newMode) {
        btn.classList.add('mode-btn--active');
      } else {
        btn.classList.remove('mode-btn--active');
      }
    });

    if (newMode === 'live') {
      clearDiffHighlights();
      if (pendingHtml !== null) {
        ctn.innerHTML = pendingHtml;
        renderMermaid();
        updateDocNav(pendingHeadings || [], pendingAlerts || []);
        reapplyFindHighlights();
        pendingHtml = null;
        pendingHeadings = null;
        pendingAlerts = null;
      }
      baselineBlocks = extractBlocks(ctn);
      updateFab();
    } else if (newMode === 'static') {
      // Freeze — keep current DOM as-is
    } else if (newMode === 'diff') {
      baselineBlocks = extractBlocks(ctn);
      if (pendingHtml !== null && oldMode === 'static') {
        applyDiff(pendingHtml, pendingHeadings, pendingAlerts);
        pendingHtml = null;
        pendingHeadings = null;
        pendingAlerts = null;
      }
      updateFab();
    }
  }

  // ── Handle content updates with nav data ───────
  function handleContentUpdate(data) {
    var payload = parseContentPayload(data);

    // First message after connect/reconnect — always set as baseline (handles file switching)
    if (isFirstWsMessage) {
      isFirstWsMessage = false;
      ctn.innerHTML = payload.html;
      renderMermaid();
      updateDocNav(payload.headings, payload.alerts);
      reapplyFindHighlights();
      baselineBlocks = extractBlocks(ctn);
      clearDiffHighlights();
      updateFab();
      return;
    }

    if (currentMode === 'static') {
      pendingHtml = payload.html;
      pendingHeadings = payload.headings;
      pendingAlerts = payload.alerts;
      return;
    }

    if (currentMode === 'live') {
      ctn.innerHTML = payload.html;
      renderMermaid();
      updateDocNav(payload.headings, payload.alerts);
      reapplyFindHighlights();
      baselineBlocks = extractBlocks(ctn);
      return;
    }

    // Diff mode — debounce rapid saves
    pendingHtml = payload.html;
    pendingHeadings = payload.headings;
    pendingAlerts = payload.alerts;
    if (diffDebounceTimer) clearTimeout(diffDebounceTimer);
    diffDebounceTimer = setTimeout(function() {
      applyDiff(pendingHtml, pendingHeadings, pendingAlerts);
      pendingHtml = null;
      pendingHeadings = null;
      pendingAlerts = null;
      diffDebounceTimer = null;
    }, 300);
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
    if (zoomModalState.isOpen) closeZoomModal();
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
    if (zoomModalState.isOpen) {
      if (e.key === 'Escape') {
        e.preventDefault();
        closeZoomModal();
        return;
      }
      if (e.key === '0' && !e.metaKey && !e.ctrlKey && !e.altKey) {
        e.preventDefault();
        resetZoomModal();
        return;
      }
    }

    if ((e.metaKey || e.ctrlKey) && e.key === 'Enter') {
      if (currentMode === 'diff' && diffFab.classList.contains('visible')) {
        e.preventDefault();
        acceptAll();
        return;
      }
    }
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
      if (!findBar) return; // no find bar on empty/browse pages — let native handle it
      e.preventDefault();
      var seed = getFindBarSelectionSeed();
      if (seed) {
        findBarInput.value = seed;
        if (!findBar.classList.contains('open')) openFindBar();
        findBarInput.focus();
        findBarInput.select();
        clearTimeout(findDebounceTimer);
        performSearch();
      } else if (findBar.classList.contains('open')) {
        findBarInput.focus();
        findBarInput.select();
      } else {
        openFindBar();
      }
      return;
    }
    if ((e.ctrlKey || e.metaKey) && (e.key === '=' || e.key === '+' || e.key === '-' || e.key === '0')) {
      var active = document.activeElement;
      if (active && (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA' || active.isContentEditable)) return;
      e.preventDefault();
      if (e.key === '0') setZoom(1.0);
      else if (e.key === '-') setZoom(currentZoom / ZOOM_STEP);
      else setZoom(currentZoom * ZOOM_STEP);
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
    isFirstWsMessage = true;
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

  // Initialize baseline for diff mode
  if (currentPath && ctn) {
    baselineBlocks = extractBlocks(ctn);
  }
})();
