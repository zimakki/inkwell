// DiffView hook: owns the article body. The article uses phx-update="ignore"
// so LiveView never morphs it after the initial mount. Subsequent file-change
// updates arrive via the "article_reload" push_event from FileLive; this hook
// applies them according to the user's chosen mode (static / live / diff).
//
// In "diff" mode it computes a block-level LCS diff against the previous
// content, then a word-level LCS diff for any modified blocks, and renders the
// result with .inkwell-diff-* CSS classes. Per-block accept buttons revert a
// single change; Cmd+Enter (or Ctrl+Enter) accepts everything visible.

import {
  buildWordDiffHTML,
  computeBlockDiff,
  createElementFromHTML,
  extractBlocks,
} from "../lib/diff";
import { readMode } from "./mode_toggle";

export default {
  mounted() {
    this.mode = readMode();
    this.baseline = extractBlocks(this.el);

    this.onModeChange = (e) => {
      this.mode = e.detail.mode;
      // Switching out of diff drops any leftover highlights.
      if (this.mode !== "diff") this.clearHighlights();
    };
    document.addEventListener("inkwell:mode-changed", this.onModeChange);

    this.onKeydown = (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
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
        el.innerHTML = buildWordDiffHTML(entry.oldBlock.textContent, entry.newBlock.textContent);
        this.addAcceptButton(el, idx);
        this.el.appendChild(el);
      }
    });

    this.notifyMermaid();
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
      setTimeout(() => el.remove(), 200);
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
  },

  clearHighlights() {
    this.acceptAll();
  },

  notifyMermaid() {
    // Tell the Mermaid hook to re-process any new <pre class="mermaid"> nodes
    // and Scrollspy to re-observe the new headings.
    document.dispatchEvent(new CustomEvent("inkwell:rerender-mermaid"));
    document.dispatchEvent(new CustomEvent("inkwell:article-reloaded"));
  },
};
