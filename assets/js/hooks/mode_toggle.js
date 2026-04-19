// ModeToggle hook: renders a 3-button mode selector (static / live / diff) into
// the element it's attached to. Persists the choice in localStorage and
// dispatches an `inkwell:mode-changed` CustomEvent on document so the DiffView
// hook can react.

const MODES = [
  { id: "static", label: "Static", icon: "\u23F8", title: "Pause updates" },
  { id: "live", label: "Live", icon: "\u21BB", title: "Refresh on save" },
  { id: "diff", label: "Diff", icon: "\u25D1", title: "Highlight what changed" },
];
const STORAGE_KEY = "inkwell-mode";

export function readMode() {
  const stored = localStorage.getItem(STORAGE_KEY);
  if (stored === "static" || stored === "live" || stored === "diff") return stored;
  return "diff";
}

function writeMode(mode) {
  localStorage.setItem(STORAGE_KEY, mode);
  document.dispatchEvent(new CustomEvent("inkwell:mode-changed", { detail: { mode } }));
}

export default {
  mounted() {
    this.render();
    this.el.addEventListener("click", this.onClick.bind(this));
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  },
  render() {
    const current = readMode();
    this.el.innerHTML = MODES.map(
      ({ id, label, icon, title }) =>
        `<button type="button" class="mode-btn ${id === current ? "mode-btn--active" : ""}" data-mode="${id}" title="${title}">` +
        `<span class="mode-icon">${icon}</span> ${label}` +
        `</button>`,
    ).join("");
  },
  onClick(e) {
    const btn = e.target.closest("[data-mode]");
    if (!btn) return;
    const mode = btn.dataset.mode;
    if (!mode || mode === readMode()) return;
    writeMode(mode);
    this.render();
  },
};
