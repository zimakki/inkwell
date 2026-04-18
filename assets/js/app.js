import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

import Mermaid from "./hooks/mermaid";
import Zoom from "./hooks/zoom";
import Scrollspy from "./hooks/scrollspy";

const Hooks = { Mermaid, Zoom, Scrollspy };

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const liveSocket = new LiveSocket("/live", Socket, {
  params: { _csrf_token: csrfToken },
  hooks: Hooks,
});

topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", () => topbar.show(300));
window.addEventListener("phx:page-loading-stop", () => topbar.hide());

liveSocket.connect();
window.liveSocket = liveSocket;
