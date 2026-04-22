import "phoenix_html";
import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

import DiffView from "./hooks/diff_view";
import DocMap from "./hooks/doc_map";
import DocRailNav from "./hooks/doc_rail_nav";
import FindBar from "./hooks/find_bar";
import Mermaid from "./hooks/mermaid";
import ModeToggle from "./hooks/mode_toggle";
import PickerKeys from "./hooks/picker_keys";
import PickerOverlay from "./hooks/picker_overlay";
import Scrollspy from "./hooks/scrollspy";
import Shortcuts from "./hooks/shortcuts";
import Zoom from "./hooks/zoom";

const Hooks = {
  DiffView,
  DocMap,
  DocRailNav,
  FindBar,
  Mermaid,
  ModeToggle,
  PickerKeys,
  PickerOverlay,
  Scrollspy,
  Shortcuts,
  Zoom,
};

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
