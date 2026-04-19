// DocMap hook: opens/closes the mobile doc-map bottom sheet. The FAB is the
// host element. When clicked it adds .open to #doc-map-sheet and
// #doc-map-backdrop. Backdrop click and downward swipe close the sheet.

const SHEET_SELECTOR = "#doc-map-sheet";
const BACKDROP_SELECTOR = "#doc-map-backdrop";

export default {
  mounted() {
    this.sheet = document.querySelector(SHEET_SELECTOR);
    this.backdrop = document.querySelector(BACKDROP_SELECTOR);

    this.onOpen = () => this.open();
    this.el.addEventListener("click", this.onOpen);

    if (this.backdrop) {
      this.onBackdropClick = () => this.close();
      this.backdrop.addEventListener("click", this.onBackdropClick);
    }

    if (this.sheet) {
      this.touchStartY = 0;
      this.touchCurrentY = 0;

      this.onTouchStart = (e) => {
        this.touchStartY = e.touches[0].clientY;
        this.touchCurrentY = this.touchStartY;
        this.sheet.style.transition = "none";
      };
      this.onTouchMove = (e) => {
        this.touchCurrentY = e.touches[0].clientY;
        const dy = this.touchCurrentY - this.touchStartY;
        if (dy > 0) this.sheet.style.transform = `translateY(${dy}px)`;
      };
      this.onTouchEnd = () => {
        this.sheet.style.transition = "";
        const dy = this.touchCurrentY - this.touchStartY;
        if (dy > 80) this.close();
        else this.sheet.style.transform = "";
      };

      this.sheet.addEventListener("touchstart", this.onTouchStart, { passive: true });
      this.sheet.addEventListener("touchmove", this.onTouchMove, { passive: true });
      this.sheet.addEventListener("touchend", this.onTouchEnd);
    }
  },

  destroyed() {
    if (this.onOpen) this.el.removeEventListener("click", this.onOpen);
    if (this.backdrop && this.onBackdropClick) {
      this.backdrop.removeEventListener("click", this.onBackdropClick);
    }
    if (this.sheet) {
      if (this.onTouchStart) this.sheet.removeEventListener("touchstart", this.onTouchStart);
      if (this.onTouchMove) this.sheet.removeEventListener("touchmove", this.onTouchMove);
      if (this.onTouchEnd) this.sheet.removeEventListener("touchend", this.onTouchEnd);
    }
  },

  open() {
    if (!this.sheet) return;
    this.sheet.classList.add("open");
    if (this.backdrop) this.backdrop.classList.add("open");
  },

  close() {
    if (!this.sheet) return;
    this.sheet.style.transform = "";
    this.sheet.classList.remove("open");
    if (this.backdrop) this.backdrop.classList.remove("open");
  },
};
