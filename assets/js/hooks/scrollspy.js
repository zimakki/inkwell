// Scrollspy hook (attached to #doc-rail):
//   - Observes h1/h2/h3/h4 inside #page-ctn (the article) and toggles
//     .doc-rail-active on the matching link.
//   - Intercepts clicks on .doc-rail-link inside this.el to smooth-scroll
//     to the heading. Native anchor jumps don't animate; this gives a
//     consistent feel and respects sticky headers.
const HEADING_SELECTOR = "#page-ctn h1, #page-ctn h2, #page-ctn h3, #page-ctn h4";

export default {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) this.markActive(entry.target.id);
        });
      },
      { rootMargin: "0px 0px -75% 0px" },
    );
    this.observe();

    // Re-observe whenever the article content changes (LiveView push_event).
    this.onArticleReload = () => this.observe();
    document.addEventListener("inkwell:article-reloaded", this.onArticleReload);

    this.clickHandler = (e) => {
      const link = e.target.closest(".doc-rail-link");
      if (!link || !this.el.contains(link)) return;

      const targetId = link.dataset.target;
      if (!targetId) return;

      // Scope the lookup to #page-ctn — the picker preview pane renders the
      // same markdown server-side and produces duplicate heading IDs;
      // document.getElementById would otherwise return the hidden picker copy.
      const target = document.querySelector(`#page-ctn [id="${CSS.escape(targetId)}"]`);
      if (!target) return;

      e.preventDefault();
      target.scrollIntoView({ behavior: "smooth", block: "start" });
    };
    this.el.addEventListener("click", this.clickHandler);
  },

  updated() {
    this.observe();
  },

  destroyed() {
    this.observer?.disconnect();
    if (this.onArticleReload) {
      document.removeEventListener("inkwell:article-reloaded", this.onArticleReload);
    }
    if (this.clickHandler) this.el.removeEventListener("click", this.clickHandler);
  },

  observe() {
    if (!this.observer) return;
    this.observer.disconnect();
    document.querySelectorAll(HEADING_SELECTOR).forEach((h) => this.observer.observe(h));
  },

  markActive(id) {
    document
      .querySelectorAll("#doc-rail .doc-rail-link, #doc-map-content .doc-rail-link")
      .forEach((a) => a.classList.toggle("doc-rail-active", a.dataset.target === id));
  },
};
