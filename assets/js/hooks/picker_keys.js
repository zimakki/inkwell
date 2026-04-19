// PickerKeys hook: intercepts arrow/enter on the picker input so the cursor
// doesn't jump to start/end of the text while the user is navigating, then
// forwards the key to the component server-side as a "nav" event.
const NAV_KEYS = new Set(["ArrowUp", "ArrowDown", "Enter", "Escape"]);

export default {
  mounted() {
    this.handler = (e) => {
      if (!NAV_KEYS.has(e.key)) return;
      e.preventDefault();
      // The component listens for `nav` on the input itself via phx-keydown,
      // so the LiveView event already fires. We just need to swallow the
      // default arrow/enter behaviour.
    };
    this.el.addEventListener("keydown", this.handler);
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("keydown", this.handler);
  },
};
