import { invoke } from "./tauri_invoke";

function isTauri() {
  return typeof window !== "undefined" && !!window.__TAURI_INTERNALS__;
}

async function invokeSavePdf(href, defaultName) {
  const port = parseInt(window.location.port, 10) || 80;
  await invoke("save_export_pdf", {
    exportUrl: href,
    defaultName,
    daemonPort: port,
  });
}

function deriveDefaultName(href) {
  try {
    const u = new URL(href, window.location.origin);
    const p = u.searchParams.get("path");
    if (!p) return null;
    return p.split("/").pop() + ".pdf";
  } catch {
    return null;
  }
}

export function installPdfExportBridge() {
  if (!isTauri()) return;

  document.addEventListener(
    "click",
    (e) => {
      const a = e.target.closest && e.target.closest('a[href^="/export.pdf"]');
      if (!a) return;
      e.preventDefault();
      e.stopPropagation();
      const href = a.getAttribute("href");
      const defaultName =
        a.getAttribute("download") || deriveDefaultName(href) || "export.pdf";
      invokeSavePdf(href, defaultName).catch((err) =>
        console.error("save_export_pdf failed:", err)
      );
    },
    true
  );
}
