// Mermaid hook: renders <pre class="mermaid">…source…</pre> blocks into SVG.
// Mermaid 11+ does not auto-render after the initial DOMContentLoaded pass for
// content morphed in by LiveView, so we explicitly call mermaid.run() on mount
// and after every patch. The original source is stashed on each node so re-
// renders (e.g. after a file save) can restore it before mermaid replaces the
// children with SVG.
export default {
  mounted() {
    this.runMermaid();
    this.onRerender = () => this.runMermaid();
    document.addEventListener("inkwell:rerender-mermaid", this.onRerender);
  },
  updated() {
    this.runMermaid();
  },
  destroyed() {
    if (this.onRerender) document.removeEventListener("inkwell:rerender-mermaid", this.onRerender);
  },
  runMermaid() {
    if (!window.mermaid) {
      console.warn("[Mermaid hook] window.mermaid is not loaded");
      return;
    }

    if (!window.__inkwell_mermaid_initialized) {
      const theme =
        document.querySelector("[data-theme]")?.dataset?.theme === "light"
          ? "default"
          : "dark";

      window.mermaid.initialize({
        startOnLoad: false,
        securityLevel: "loose",
        theme,
      });
      window.__inkwell_mermaid_initialized = true;
    }

    const nodes = Array.from(this.el.querySelectorAll(".mermaid"));
    if (nodes.length === 0) return;

    nodes.forEach((node) => {
      if (!node.dataset.source) {
        node.dataset.source = node.textContent;
      }

      if (node.getAttribute("data-processed") === "true") {
        node.innerHTML = node.dataset.source;
        node.removeAttribute("data-processed");
      }
    });

    window.mermaid.run({ nodes }).catch((err) => {
      console.error("[Mermaid hook] render failed", err);
    });
  },
};
