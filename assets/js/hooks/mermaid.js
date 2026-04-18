export default {
  mounted() { this.render(); },
  updated() { this.render(); },
  render() {
    if (!window.mermaid) return;
    this.el.querySelectorAll(".mermaid").forEach((node) => {
      if (node.dataset.processed === "true" && node.dataset.source) {
        node.innerHTML = node.dataset.source;
        delete node.dataset.processed;
      } else if (!node.dataset.source) {
        node.dataset.source = node.innerHTML;
      }
    });
    try {
      window.mermaid.run({ querySelector: ".mermaid", nodes: this.el });
    } catch (e) {
      console.error("mermaid render failed", e);
    }
  },
};
