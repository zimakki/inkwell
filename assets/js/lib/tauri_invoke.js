// Thin shim for Tauri 2's invoke() — avoids adding @tauri-apps/api as an npm dep.
// Tauri 2 exposes window.__TAURI_INTERNALS__.invoke(cmd, args) from the host.
export async function invoke(cmd, args = {}) {
  return window.__TAURI_INTERNALS__.invoke(cmd, args);
}
