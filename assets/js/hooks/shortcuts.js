// Shortcuts hook: global keyboard shortcuts. Lives on the page header so
// it's mounted exactly once per LiveView. Each shortcut preventDefaults the
// browser's native binding (otherwise Ctrl+P opens print, Ctrl+Shift+T
// reopens the last closed tab, Cmd+F opens the browser's find-in-page)
// and dispatches the corresponding LiveView event or CustomEvent.
//
// Bindings:
//   Ctrl/Cmd + P              → open_picker (LiveView event)
//   Ctrl/Cmd + Shift + T      → toggle_theme (LiveView event)
//   Ctrl/Cmd + F              → inkwell:open-find (CustomEvent, seeded with
//                                the current text selection if any)

function isEditableTarget(target) {
  if (!target) return false;
  const tag = target.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA") return true;
  return !!(target.closest && target.closest('[contenteditable="true"]'));
}

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
        return;
      }

      if (key === "f" && !e.shiftKey && !e.altKey) {
        if (isEditableTarget(e.target)) return;
        e.preventDefault();
        const seed = (window.getSelection && window.getSelection().toString()) || "";
        document.dispatchEvent(
          new CustomEvent("inkwell:open-find", { detail: { seed } })
        );
      }
    };
    document.addEventListener("keydown", this.handler);
  },
  destroyed() {
    if (this.handler) document.removeEventListener("keydown", this.handler);
  },
};
