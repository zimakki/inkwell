export default {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const id = entry.target.id;
            document
              .querySelectorAll("#doc-rail a")
              .forEach((a) =>
                a.classList.toggle("doc-rail-active", a.getAttribute("href") === "#" + id)
              );
          }
        });
      },
      { rootMargin: "0px 0px -75% 0px" }
    );

    this.el.querySelectorAll("h1, h2, h3, h4").forEach((h) => this.observer.observe(h));
  },
  updated() {
    if (this.observer) {
      this.observer.disconnect();
      this.el.querySelectorAll("h1, h2, h3, h4").forEach((h) => this.observer.observe(h));
    }
  },
  destroyed() {
    this.observer?.disconnect();
  },
};
