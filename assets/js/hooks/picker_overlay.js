// PickerOverlay hook:
//   - Clicking on the overlay (outside the inner #picker box) closes the picker.
//   - When the overlay has the .open class, locks background scroll by adding
//     body.picker-open. Mirrors the body.zoom-modal-open pattern used by the
//     zoom modal.
export default {
  mounted() {
    this.handler = (e) => {
      if (e.target === this.el) {
        this.pushEvent("close_picker", {});
      }
    };
    this.el.addEventListener("click", this.handler);
    this.syncScrollLock();
  },
  updated() {
    this.syncScrollLock();
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("click", this.handler);
    document.body.classList.remove("picker-open");
  },
  syncScrollLock() {
    if (this.el.classList.contains("open")) {
      document.body.classList.add("picker-open");
    } else {
      document.body.classList.remove("picker-open");
    }
  },
};
