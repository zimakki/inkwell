// DiffView hook: owns the article body. The article uses phx-update="ignore"
// so LiveView never morphs it after the initial mount. Subsequent file-change
// updates arrive via the "article_reload" push_event from FileLive; this hook
// applies them according to the user's chosen mode (static / live / diff).
//
// In "diff" mode it computes a block-level LCS diff against the previous
// content, then a word-level LCS diff for any modified blocks, and renders the
// result with .inkwell-diff-* CSS classes. Per-block accept buttons revert a
// single change; a floating "Accept all" FAB (#diff-accept-fab) summarises the
// pending changes and accepts everything visible, as does Cmd+Enter (Ctrl+Enter).

import {
  buildWordDiffHTML,
  computeBlockDiff,
  createElementFromHTML,
  extractBlocks,
} from "../lib/diff";
import { readMode } from "./mode_toggle";

// Blocks whose content model is plain inline text — safe to replace innerHTML
// with a flattened word-level diff. Structured blocks (table, ul/ol, pre,
// blockquote) lose their child structure if flattened this way; a <table> in
// particular vanishes entirely because the parser foster-parents any non-cell
// content out of it, leaving only stray whitespace. Those render whole instead.
const WORD_DIFF_TAGS = new Set(["p", "h1", "h2", "h3", "h4", "h5", "h6"]);

export default {
  mounted() {
    this.mode = readMode();
    this.baseline = extractBlocks(this.el);
    this.buildFab();

    this.onModeChange = (e) => {
      this.mode = e.detail.mode;
      // Switching out of diff drops any leftover highlights.
      if (this.mode !== "diff") this.clearHighlights();
      this.updateFab();
    };
    document.addEventListener("inkwell:mode-changed", this.onModeChange);

    this.onKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
        if (this.mode !== "diff" || !this.fab.classList.contains("visible")) return;
        e.preventDefault();
        this.acceptAll();
      }
    };
    document.addEventListener("keydown", this.onKeydown);

    this.handleEvent("article_reload", (payload) => this.onReload(payload));
  },

  destroyed() {
    document.removeEventListener("inkwell:mode-changed", this.onModeChange);
    document.removeEventListener("keydown", this.onKeydown);
    if (this.fab) this.fab.remove();
  },

  // The FAB lives on document.body (outside the phx-update="ignore" article) so
  // it survives content reloads. It is created once per mount and removed on
  // destroy to avoid leaking duplicates across LiveView navigations.
  buildFab() {
    const fab = document.createElement("div");
    fab.id = "diff-accept-fab";
    fab.innerHTML =
      '<div class="diff-summary"></div>' +
      '<div class="diff-separator"></div>' +
      '<button class="accept-all-btn"><span>✓ Accept</span> <span class="shortcut">⌘⏎</span></button>';
    fab.querySelector(".accept-all-btn").addEventListener("click", () => this.acceptAll());
    document.body.appendChild(fab);
    this.fab = fab;
  },

  onReload(payload) {
    if (this.mode === "static") return;
    if (this.mode === "live") {
      this.replaceContent(payload.html);
      return;
    }
    this.applyDiff(payload.html);
  },

  replaceContent(html) {
    this.el.innerHTML = html;
    this.baseline = extractBlocks(this.el);
    this.notifyMermaid();
  },

  applyDiff(html) {
    const tempDiv = document.createElement("div");
    tempDiv.innerHTML = html;
    const newBlocks = extractBlocks(tempDiv);
    const diff = computeBlockDiff(this.baseline, newBlocks);

    const scrollEl = this.el.parentElement || document.documentElement;
    const scrollPos = scrollEl.scrollTop;

    this.el.innerHTML = "";
    diff.forEach((entry, idx) => {
      let el;
      if (entry.type === "unchanged") {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        this.el.appendChild(el);
      } else if (entry.type === "added") {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        el.classList.add("inkwell-diff-added");
        el.dataset.diffIndex = idx;
        this.addAcceptButton(el, idx);
        this.el.appendChild(el);
      } else if (entry.type === "removed") {
        el = createElementFromHTML(entry.oldBlock.outerHTML);
        el.classList.add("inkwell-diff-removed");
        el.dataset.diffIndex = idx;
        this.addAcceptButton(el, idx);
        this.el.appendChild(el);
      } else if (entry.type === "modified") {
        el = createElementFromHTML(entry.newBlock.outerHTML);
        el.classList.add("inkwell-diff-modified");
        el.dataset.diffIndex = idx;
        if (WORD_DIFF_TAGS.has(entry.newBlock.tag)) {
          el.innerHTML = buildWordDiffHTML(entry.oldBlock.textContent, entry.newBlock.textContent);
        }
        this.addAcceptButton(el, idx);
        this.el.appendChild(el);
      }
    });

    this.notifyMermaid();
    this.updateFab();
    scrollEl.scrollTop = scrollPos;
  },

  addAcceptButton(el, diffIndex) {
    const btn = document.createElement("button");
    btn.className = "inkwell-diff-accept-btn";
    btn.innerHTML = "\u2713";
    btn.title = "Accept this change";
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      this.acceptBlock(el, diffIndex);
    });
    el.appendChild(btn);
  },

  acceptBlock(el) {
    if (el.classList.contains("inkwell-diff-removed")) {
      el.style.transition = "opacity 0.2s ease";
      el.style.opacity = "0";
      setTimeout(() => {
        el.remove();
        this.updateFab();
      }, 200);
    } else {
      const btn = el.querySelector(".inkwell-diff-accept-btn");
      if (btn) btn.remove();
      el.querySelectorAll(".inkwell-diff-word-removed").forEach((s) => s.remove());
      el.querySelectorAll(".inkwell-diff-word-added").forEach((s) =>
        s.replaceWith(document.createTextNode(s.textContent)),
      );
      el.classList.add("inkwell-diff-fade-out");
      setTimeout(() => {
        el.classList.remove("inkwell-diff-added", "inkwell-diff-modified", "inkwell-diff-fade-out");
        el.removeAttribute("data-diff-index");
        this.updateFab();
      }, 200);
    }
    setTimeout(() => {
      this.baseline = extractBlocks(this.el);
    }, 250);
  },

  acceptAll() {
    const highlighted = this.el.querySelectorAll(
      ".inkwell-diff-added, .inkwell-diff-removed, .inkwell-diff-modified",
    );
    highlighted.forEach((el) => {
      if (el.classList.contains("inkwell-diff-removed")) {
        el.remove();
      } else {
        const btn = el.querySelector(".inkwell-diff-accept-btn");
        if (btn) btn.remove();
        el.querySelectorAll(".inkwell-diff-word-removed").forEach((s) => s.remove());
        el.querySelectorAll(".inkwell-diff-word-added").forEach((s) =>
          s.replaceWith(document.createTextNode(s.textContent)),
        );
        el.classList.remove("inkwell-diff-added", "inkwell-diff-modified");
        el.removeAttribute("data-diff-index");
      }
    });
    this.baseline = extractBlocks(this.el);
    this.updateFab();
  },

  clearHighlights() {
    this.acceptAll();
  },

  // Show/hide the FAB and refresh its +added ~modified -removed summary based on
  // the highlights currently in the article. Hidden unless in diff mode with at
  // least one pending change.
  updateFab() {
    if (!this.fab) return;
    const added = this.el.querySelectorAll(".inkwell-diff-added").length;
    const modified = this.el.querySelectorAll(".inkwell-diff-modified").length;
    const removed = this.el.querySelectorAll(".inkwell-diff-removed").length;

    if (this.mode !== "diff" || added + modified + removed === 0) {
      this.fab.classList.remove("visible");
      return;
    }

    const parts = [];
    if (added > 0) parts.push(`<span class="added">+${added}</span>`);
    if (modified > 0) parts.push(`<span class="modified">~${modified}</span>`);
    if (removed > 0) parts.push(`<span class="removed">-${removed}</span>`);
    this.fab.querySelector(".diff-summary").innerHTML = parts.join(" ");
    this.fab.classList.add("visible");
  },

  notifyMermaid() {
    // Tell the Mermaid hook to re-process any new <pre class="mermaid"> nodes
    // and Scrollspy to re-observe the new headings.
    document.dispatchEvent(new CustomEvent("inkwell:rerender-mermaid"));
    document.dispatchEvent(new CustomEvent("inkwell:article-reloaded"));
  },
};
