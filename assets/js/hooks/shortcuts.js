// Shortcuts hook: global keyboard shortcuts. Lives on the page header so
// it's mounted exactly once per LiveView. Each shortcut preventDefaults the
// browser's native binding (otherwise Ctrl+P opens print, Ctrl+Shift+T
// reopens the last closed tab) and pushes a LiveView event.
//
// Bindings:
//   Ctrl/Cmd + P              → open_picker
//   Ctrl/Cmd + Shift + T      → toggle_theme

export default {
  mounted() {
    this.handler = (e) => {
      const mod = e.metaKey || e.ctrlKey;
      if (!mod) return;

      const key = e.key.toLowerCase();

      if (key === "p" && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        this.pushEvent("open_picker", {});
        return;
      }

      if (key === "t" && e.shiftKey && !e.altKey) {
        e.preventDefault();
        this.pushEvent("toggle_theme", {});
      }
    };
    document.addEventListener("keydown", this.handler);
  },
  destroyed() {
    if (this.handler) document.removeEventListener("keydown", this.handler);
  },
};
