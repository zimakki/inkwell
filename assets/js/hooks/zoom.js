export default {
  mounted() {
    this.handler = (event) => {
      const target = event.target.closest("img, svg");
      if (!target) return;
      this.openModal(target);
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("click", this.handler);
  },
  openModal(el) {
    const overlay = document.createElement("div");
    overlay.className = "zoom-overlay";
    overlay.setAttribute("role", "dialog");
    overlay.setAttribute("aria-modal", "true");

    const clone = el.cloneNode(true);
    clone.removeAttribute("phx-hook");

    overlay.appendChild(clone);
    overlay.addEventListener("click", () => overlay.remove());
    document.body.appendChild(overlay);

    const close = (e) => {
      if (e.key === "Escape") {
        overlay.remove();
        document.removeEventListener("keydown", close);
      }
    };
    document.addEventListener("keydown", close);
  },
};
