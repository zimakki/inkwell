// DocRailNav hook: intercepts clicks on .doc-rail-link, looks up the heading
// by data-target, and smooth-scrolls it into view. Native anchor jumps don't
// animate and don't account for sticky headers; this gives a consistent feel.
// Also closes the mobile doc-map sheet if it's the click origin.

export default {
  mounted() {
    this.handler = (e) => {
      const link = e.target.closest(".doc-rail-link");
      if (!link || !this.el.contains(link)) return;

      const targetId = link.dataset.target;
      if (!targetId) return;

      // Scope to #page-ctn — picker preview duplicates heading IDs.
      const target = document.querySelector(`#page-ctn [id="${CSS.escape(targetId)}"]`);
      if (!target) return;

      e.preventDefault();

      const sheet = document.getElementById("doc-map-sheet");
      const sheetIsOpen = sheet && sheet.classList.contains("open");

      if (sheetIsOpen) {
        sheet.classList.remove("open");
        const backdrop = document.getElementById("doc-map-backdrop");
        if (backdrop) backdrop.classList.remove("open");
        // Wait for the slide-down animation before scrolling so the user can
        // see where they land.
        setTimeout(() => target.scrollIntoView({ behavior: "smooth", block: "start" }), 250);
      } else {
        target.scrollIntoView({ behavior: "smooth", block: "start" });
      }
    };
    this.el.addEventListener("click", this.handler);
  },
  destroyed() {
    if (this.handler) this.el.removeEventListener("click", this.handler);
  },
};
