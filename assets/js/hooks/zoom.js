// Zoom hook: click an <img> or a <pre class="mermaid"> (after it's been
// rendered to SVG) to open a pan-and-zoom modal. Ported from the pre-Phoenix
// app.js so behaviour is identical: pinch/wheel zoom around cursor, drag to
// pan, +/-/Reset/Close toolbar buttons, ESC to close, scroll position +
// focus restored on close.

const State = {
  modal: null,
  backdrop: null,
  viewport: null,
  canvas: null,
  title: null,
  built: false,

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
  scrollTop: 0,
  triggerElement: null,
};

function build() {
  if (State.built) return;
  State.built = true;

  const modal = document.createElement("div");
  modal.id = "zoom-modal";
  modal.setAttribute("aria-hidden", "true");
  modal.innerHTML =
    '<div id="zoom-modal-backdrop"></div>' +
    '<div id="zoom-modal-dialog" role="dialog" aria-modal="true" aria-label="Zoomed content">' +
    '<div id="zoom-modal-toolbar">' +
    '<div id="zoom-modal-title"></div>' +
    '<div id="zoom-modal-actions">' +
    '<button type="button" class="zoom-modal-btn" data-action="zoom-in" aria-label="Zoom in">+</button>' +
    '<button type="button" class="zoom-modal-btn" data-action="zoom-out" aria-label="Zoom out">\u2212</button>' +
    '<button type="button" class="zoom-modal-btn zoom-modal-btn-reset" data-action="reset">Reset</button>' +
    '<button type="button" class="zoom-modal-btn zoom-modal-btn-close" data-action="close" aria-label="Close">\u00D7</button>' +
    "</div>" +
    "</div>" +
    '<div id="zoom-modal-viewport">' +
    '<div id="zoom-modal-canvas"></div>' +
    "</div>" +
    "</div>";

  document.body.appendChild(modal);

  State.modal = modal;
  State.backdrop = modal.querySelector("#zoom-modal-backdrop");
  State.viewport = modal.querySelector("#zoom-modal-viewport");
  State.canvas = modal.querySelector("#zoom-modal-canvas");
  State.title = modal.querySelector("#zoom-modal-title");

  State.backdrop.addEventListener("click", close);

  modal.addEventListener("click", (e) => {
    const actionEl = e.target.closest("[data-action]");
    if (!actionEl) return;
    e.preventDefault();
    const action = actionEl.dataset.action;
    if (action === "zoom-in") stepZoom(1.25);
    else if (action === "zoom-out") stepZoom(0.8);
    else if (action === "reset") resetTransform();
    else if (action === "close") close();
  });

  State.viewport.addEventListener(
    "wheel",
    (e) => {
      if (!State.isOpen) return;
      e.preventDefault();
      const multiplier = e.deltaY < 0 ? (e.ctrlKey ? 1.08 : 1.1) : (e.ctrlKey ? 0.92 : 0.9);
      zoomAroundPoint(e.clientX, e.clientY, State.scale * multiplier);
    },
    { passive: false },
  );

  State.viewport.addEventListener("pointerdown", (e) => {
    if (!State.isOpen || e.button !== 0) return;
    if (!State.canvas.firstElementChild) return;
    e.preventDefault();
    State.pointerId = e.pointerId;
    State.dragStartX = e.clientX;
    State.dragStartY = e.clientY;
    State.startX = State.x;
    State.startY = State.y;
    State.viewport.classList.add("is-dragging");
    State.viewport.setPointerCapture(e.pointerId);
  });

  State.viewport.addEventListener("pointermove", (e) => {
    if (State.pointerId !== e.pointerId) return;
    State.x = State.startX + (e.clientX - State.dragStartX);
    State.y = State.startY + (e.clientY - State.dragStartY);
    applyTransform();
  });

  const stopDrag = (e) => {
    if (State.pointerId !== e.pointerId) return;
    State.pointerId = null;
    State.viewport.classList.remove("is-dragging");
    if (State.viewport.hasPointerCapture(e.pointerId)) {
      State.viewport.releasePointerCapture(e.pointerId);
    }
  };
  State.viewport.addEventListener("pointerup", stopDrag);
  State.viewport.addEventListener("pointercancel", stopDrag);

  window.addEventListener("resize", () => {
    if (!State.isOpen) return;
    fitContent();
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && State.isOpen) {
      e.preventDefault();
      close();
    }
  });
}

function clamp(scale) {
  return Math.min(State.maxScale, Math.max(State.minScale, scale));
}

function applyTransform() {
  State.canvas.style.width = State.width + "px";
  State.canvas.style.height = State.height + "px";
  State.canvas.style.transform = `translate(${State.x}px, ${State.y}px) scale(${State.scale})`;
}

function fitContent() {
  if (!State.viewport || !State.canvas.firstElementChild) return;
  const rect = State.viewport.getBoundingClientRect();
  const padding = 40;
  const availableW = Math.max(rect.width - padding * 2, 120);
  const availableH = Math.max(rect.height - padding * 2, 120);

  State.fitScale = Math.min(availableW / State.width, availableH / State.height);
  if (!isFinite(State.fitScale) || State.fitScale <= 0) State.fitScale = 1;
  State.minScale = Math.min(0.2, State.fitScale);

  resetTransform();
}

function resetTransform() {
  if (!State.isOpen) return;
  const rect = State.viewport.getBoundingClientRect();
  State.scale = State.fitScale;
  State.x = (rect.width - State.width * State.scale) / 2;
  State.y = (rect.height - State.height * State.scale) / 2;
  applyTransform();
}

function zoomAroundPoint(clientX, clientY, nextScale) {
  if (!State.isOpen) return;
  const rect = State.viewport.getBoundingClientRect();
  const px = clientX - rect.left;
  const py = clientY - rect.top;
  const clamped = clamp(nextScale);
  const cx = (px - State.x) / State.scale;
  const cy = (py - State.y) / State.scale;
  State.scale = clamped;
  State.x = px - cx * clamped;
  State.y = py - cy * clamped;
  applyTransform();
}

function stepZoom(multiplier) {
  if (!State.isOpen) return;
  const rect = State.viewport.getBoundingClientRect();
  zoomAroundPoint(rect.left + rect.width / 2, rect.top + rect.height / 2, State.scale * multiplier);
}

function getMermaidDimensions(svg, fallbackRect) {
  const vb = svg.viewBox && svg.viewBox.baseVal;
  if (vb && vb.width > 0 && vb.height > 0) return { width: vb.width, height: vb.height };

  const w = svg.width && svg.width.baseVal ? svg.width.baseVal.value : 0;
  const h = svg.height && svg.height.baseVal ? svg.height.baseVal.value : 0;
  if (w > 0 && h > 0) return { width: w, height: h };

  return {
    width: Math.max(fallbackRect.width, 1),
    height: Math.max(fallbackRect.height, 1),
  };
}

function openForMermaid(preEl) {
  const svg = preEl.querySelector("svg");
  if (!svg) return;

  const clone = svg.cloneNode(true);
  const sourceRect = svg.getBoundingClientRect();
  const size = getMermaidDimensions(svg, sourceRect);

  clone.removeAttribute("width");
  clone.removeAttribute("height");
  clone.style.width = "100%";
  clone.style.height = "100%";
  clone.style.display = "block";

  open({
    type: "mermaid",
    title: "Diagram",
    source: preEl,
    node: clone,
    width: size.width,
    height: size.height,
  });
}

function openForImage(imgEl) {
  const clone = document.createElement("img");
  clone.src = imgEl.currentSrc || imgEl.src;
  clone.alt = imgEl.alt || "";
  clone.decoding = "async";
  clone.style.width = "100%";
  clone.style.height = "100%";
  clone.style.display = "block";
  clone.style.objectFit = "contain";

  const finish = () => {
    open({
      type: "image",
      title: imgEl.alt ? imgEl.alt : "Image",
      source: imgEl,
      node: clone,
      width: clone.naturalWidth || imgEl.naturalWidth || imgEl.width || 1,
      height: clone.naturalHeight || imgEl.naturalHeight || imgEl.height || 1,
    });
  };

  if (imgEl.complete && imgEl.naturalWidth > 0) {
    finish();
    return;
  }
  clone.addEventListener("load", finish, { once: true });
  clone.addEventListener("error", finish, { once: true });
}

function open(config) {
  build();

  State.canvas.innerHTML = "";
  State.canvas.appendChild(config.node);
  State.title.textContent = config.title;

  State.isOpen = true;
  State.type = config.type;
  State.source = config.source;
  State.width = Math.max(config.width, 1);
  State.height = Math.max(config.height, 1);
  State.scale = 1;
  State.x = 0;
  State.y = 0;
  State.scrollTop =
    window.scrollY ||
    document.documentElement.scrollTop ||
    document.body.scrollTop ||
    0;
  State.triggerElement =
    document.activeElement instanceof HTMLElement ? document.activeElement : null;

  State.modal.classList.add("open");
  State.modal.setAttribute("aria-hidden", "false");
  document.body.classList.add("zoom-modal-open");

  fitContent();

  const closeBtn = State.modal.querySelector('[data-action="close"]');
  if (closeBtn) closeBtn.focus();
}

function close() {
  if (!State.isOpen || !State.modal) return;

  if (
    State.pointerId !== null &&
    State.viewport.hasPointerCapture &&
    State.viewport.hasPointerCapture(State.pointerId)
  ) {
    State.viewport.releasePointerCapture(State.pointerId);
  }

  State.isOpen = false;
  State.type = null;
  State.source = null;
  State.pointerId = null;
  State.modal.classList.remove("open");
  State.modal.setAttribute("aria-hidden", "true");
  State.viewport.classList.remove("is-dragging");
  document.body.classList.remove("zoom-modal-open");
  State.canvas.innerHTML = "";
  window.scrollTo(0, State.scrollTop);

  const trigger = State.triggerElement;
  State.triggerElement = null;
  if (trigger && typeof trigger.focus === "function" && document.contains(trigger)) {
    trigger.focus();
  }
}

export default {
  mounted() {
    this.handler = (e) => {
      const image = e.target.closest("img");
      if (image && this.el.contains(image)) {
        if (image.closest("a[href]")) return;
        e.preventDefault();
        openForImage(image);
        return;
      }

      const mermaidPre = e.target.closest("pre.mermaid");
      if (mermaidPre && this.el.contains(mermaidPre) && mermaidPre.querySelector("svg")) {
        e.preventDefault();
        openForMermaid(mermaidPre);
      }
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("click", this.handler);
  },
};
