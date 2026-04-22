// FindBar hook — restores the pre-0.3.0 find-in-document feature.
//
// Opens on a `inkwell:open-find` CustomEvent (dispatched by the Shortcuts
// hook when Cmd+F / Ctrl+F is pressed). Walks the #page-ctn article, wraps
// every case-insensitive match in <span class="find-match">, and maintains
// an active match that the user navigates with Enter / Shift+Enter. Esc or
// the ✕ button clears highlights and closes the bar.
//
// Re-applies the current query after every DiffView article_reload so
// highlights survive file saves.

const MAX_MATCHES = 500;
const SKIP_TAGS = new Set(["PRE", "CODE", "SCRIPT", "STYLE", "NOSCRIPT"]);
const DEBOUNCE_MS = 120;

function isInsideSkippedAncestor(node) {
  let el = node.parentElement;
  while (el) {
    if (SKIP_TAGS.has(el.tagName)) return true;
    if (el.classList && el.classList.contains("find-match")) return true;
    el = el.parentElement;
  }
  return false;
}

export default {
  mounted() {
    this.input = this.el.querySelector("#find-bar-input");
    this.counter = this.el.querySelector("#find-bar-count");
    this.query = "";
    this.matches = [];
    this.activeIndex = -1;
    this.isOpen = false;
    this.debounceTimer = null;

    this.onOpenEvent = (e) => {
      const seed = (e.detail && e.detail.seed) || "";
      this.open(seed);
    };
    document.addEventListener("inkwell:open-find", this.onOpenEvent);

    this.onReload = () => {
      if (!this.isOpen || !this.query) return;
      // Defer one tick so DiffView has finished mutating #page-ctn.
      setTimeout(() => this.runSearch(this.query, { keepActive: false }), 50);
    };
    document.addEventListener("inkwell:article-reloaded", this.onReload);

    this.onKeydown = (e) => {
      if (!this.isOpen) return;
      if (e.key === "Escape") {
        e.preventDefault();
        this.close();
      }
    };
    document.addEventListener("keydown", this.onKeydown);

    this.input.addEventListener("input", () => {
      clearTimeout(this.debounceTimer);
      const q = this.input.value;
      this.debounceTimer = setTimeout(() => this.runSearch(q), DEBOUNCE_MS);
    });

    this.input.addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        this.navigate(e.shiftKey ? -1 : +1);
      }
    });

    this.el.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-action]");
      if (!btn) return;
      e.preventDefault();
      const action = btn.dataset.action;
      if (action === "next") this.navigate(+1);
      else if (action === "prev") this.navigate(-1);
      else if (action === "close") this.close();
    });
  },

  destroyed() {
    document.removeEventListener("inkwell:open-find", this.onOpenEvent);
    document.removeEventListener("inkwell:article-reloaded", this.onReload);
    document.removeEventListener("keydown", this.onKeydown);
    clearTimeout(this.debounceTimer);
    this.clearHighlights();
  },

  open(seed) {
    this.isOpen = true;
    this.el.classList.add("open");
    this.el.setAttribute("aria-hidden", "false");

    const trimmed = (seed || "").slice(0, 200);
    if (trimmed) {
      this.input.value = trimmed;
    }
    this.input.focus();
    this.input.select();
    if (this.input.value) this.runSearch(this.input.value);
  },

  close() {
    this.isOpen = false;
    this.el.classList.remove("open");
    this.el.setAttribute("aria-hidden", "true");
    this.clearHighlights();
    this.query = "";
    this.matches = [];
    this.activeIndex = -1;
    this.updateCounter();
    this.input.blur();
  },

  clearHighlights() {
    const container = document.getElementById("page-ctn");
    if (!container) return;
    const spans = container.querySelectorAll(".find-match");
    spans.forEach((span) => {
      const parent = span.parentNode;
      if (!parent) return;
      while (span.firstChild) parent.insertBefore(span.firstChild, span);
      parent.removeChild(span);
      parent.normalize();
    });
  },

  runSearch(query, opts = {}) {
    this.query = query || "";
    this.clearHighlights();
    this.matches = [];
    this.activeIndex = -1;

    if (!this.query) {
      this.updateCounter();
      return;
    }

    const container = document.getElementById("page-ctn");
    if (!container) {
      this.updateCounter();
      return;
    }

    const needle = this.query.toLowerCase();
    const walker = document.createTreeWalker(container, NodeFilter.SHOW_TEXT, {
      acceptNode(node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        if (isInsideSkippedAncestor(node)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });

    const textNodes = [];
    let n;
    while ((n = walker.nextNode())) textNodes.push(n);

    for (const textNode of textNodes) {
      if (this.matches.length >= MAX_MATCHES) break;
      const value = textNode.nodeValue;
      const lower = value.toLowerCase();
      let cursor = 0;
      const parts = [];
      let matchesInNode = 0;
      let idx;
      while ((idx = lower.indexOf(needle, cursor)) !== -1) {
        if (this.matches.length + matchesInNode >= MAX_MATCHES) break;
        if (idx > cursor) parts.push(document.createTextNode(value.slice(cursor, idx)));
        const span = document.createElement("span");
        span.className = "find-match";
        span.textContent = value.slice(idx, idx + this.query.length);
        parts.push(span);
        matchesInNode += 1;
        cursor = idx + this.query.length;
      }
      if (matchesInNode === 0) continue;
      if (cursor < value.length) parts.push(document.createTextNode(value.slice(cursor)));

      const parent = textNode.parentNode;
      const fragment = document.createDocumentFragment();
      parts.forEach((p) => fragment.appendChild(p));
      parent.replaceChild(fragment, textNode);

      parts.forEach((p) => {
        if (p.classList && p.classList.contains("find-match")) {
          this.matches.push(p);
        }
      });
    }

    if (this.matches.length > 0) {
      this.activeIndex = 0;
      this.setActive(0, { scroll: opts.keepActive !== false });
    }
    this.updateCounter();
  },

  navigate(direction) {
    if (this.matches.length === 0) return;
    const next =
      (this.activeIndex + direction + this.matches.length) % this.matches.length;
    this.setActive(next, { scroll: true });
  },

  setActive(index, { scroll } = {}) {
    if (this.activeIndex >= 0 && this.matches[this.activeIndex]) {
      this.matches[this.activeIndex].classList.remove("active");
    }
    this.activeIndex = index;
    const current = this.matches[index];
    if (!current) return;
    current.classList.add("active");
    if (scroll) {
      current.scrollIntoView({ block: "center", behavior: "smooth" });
    }
    this.updateCounter();
  },

  updateCounter() {
    if (!this.counter) return;
    if (this.matches.length === 0) {
      this.counter.textContent = "0 of 0";
      return;
    }
    const prefix = `${this.activeIndex + 1} of ${this.matches.length}`;
    this.counter.textContent =
      this.matches.length >= MAX_MATCHES ? `${prefix}+` : prefix;
  },
};
