// PickerOverlay hook:
//   - Clicking on the overlay (outside the inner #picker box) closes the picker.
//   - When the overlay has the .open class, locks background scroll by adding
//     body.picker-open. Mirrors the body.zoom-modal-open pattern used by the
//     zoom modal.
export default {
  mounted() {
    this.wasOpen = false;
    this.handler = (e) => {
      if (e.target === this.el) {
        this.pushEvent("close_picker", {});
      }
    };
    this.el.addEventListener("click", this.handler);
    this.sync();
  },
  updated() {
    this.sync();
    this.scrollSelectedIntoView();
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("click", this.handler);
    document.body.classList.remove("picker-open");
  },
  sync() {
    const isOpen = this.el.classList.contains("open");
    if (isOpen) {
      document.body.classList.add("picker-open");
    } else {
      document.body.classList.remove("picker-open");
    }
    if (isOpen && !this.wasOpen) {
      const input = this.el.querySelector("#picker-input");
      if (input) input.focus();
    }
    this.wasOpen = isOpen;
  },
  scrollSelectedIntoView() {
    const selected = this.el.querySelector(".picker-item.selected");
    if (selected) selected.scrollIntoView({ block: "nearest" });
  },
};
