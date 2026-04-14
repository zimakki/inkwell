use std::sync::Mutex;
use tauri::{AppHandle, Manager};
use tauri_plugin_updater::Update;

#[derive(Clone)]
pub enum UpdateBannerState {
    None,
    Available {
        version: String,
        current_version: String,
    },
    Downloading {
        downloaded: u64,
        total: Option<u64>,
    },
    ReadyToRestart,
    Error(String),
    Dismissed,
}

pub struct PendingUpdate {
    pub update: Mutex<Option<Update>>,
    pub banner_state: Mutex<UpdateBannerState>,
}

impl PendingUpdate {
    pub fn new() -> Self {
        Self {
            update: Mutex::new(None),
            banner_state: Mutex::new(UpdateBannerState::None),
        }
    }
}

// ── Style constants ──────────────────────────────────────────────────────────

const BANNER_STYLE: &str = "\
    position:relative;display:flex;align-items:center;\
    padding:0 3rem;height:40px;gap:12px;\
    background:var(--bg-hover);border-bottom:1px solid var(--border);\
    font-family:system-ui,sans-serif;font-size:13px;\
    color:var(--text-secondary);z-index:9999;\
    animation:inkwell-slide-down 200ms ease;\
";

const ACCENT_BTN_STYLE: &str = "\
    background:var(--accent,#89b4fa);color:#1e1e2e;\
    border:none;border-radius:12px;padding:4px 14px;\
    font-size:12px;font-weight:600;cursor:pointer;\
    font-family:system-ui,sans-serif;\
";

const TEXT_BTN_STYLE: &str = "\
    background:none;border:none;color:var(--text-muted);\
    font-size:12px;cursor:pointer;padding:4px 8px;\
    font-family:system-ui,sans-serif;\
";

const PROGRESS_BAR_STYLE: &str = "\
    position:absolute;bottom:0;left:0;height:3px;\
    background:var(--accent,#89b4fa);transition:width 150ms ease;\
";

// ── Animation CSS ────────────────────────────────────────────────────────────

fn keyframes_css() -> String {
    "@keyframes inkwell-slide-down{\
        from{transform:translateY(-100%)}\
        to{transform:translateY(0)}\
    }"
    .to_string()
}

// ── Banner JS generators ─────────────────────────────────────────────────────

fn banner_js_available(version: &str, current_version: &str) -> String {
    let v = js_escape(version);
    let cv = js_escape(current_version);
    format!(
        r#"(function(){{
  var old=document.getElementById('inkwell-update-banner');
  if(old)old.remove();
  var style=document.getElementById('inkwell-keyframes');
  if(!style){{
    style=document.createElement('style');
    style.id='inkwell-keyframes';
    style.textContent='{kf}';
    document.head.appendChild(style);
  }}
  var b=document.createElement('div');
  b.id='inkwell-update-banner';
  b.setAttribute('style','{bs}');
  b.innerHTML='<span>Update available: <strong>{v}</strong> <span style="color:var(--text-muted);font-size:11px;">(current: {cv})</span></span>'
    +'<button style="{abs}" onclick="window.__TAURI_INTERNALS__.invoke(\'accept_update\')">Update</button>'
    +'<button style="{tbs}" onclick="window.__TAURI_INTERNALS__.invoke(\'dismiss_update\')">Later</button>';
  document.body.insertBefore(b,document.body.firstChild);
  window.__inkwell_update_progress=function(downloaded,total){{
    var b=document.getElementById('inkwell-update-banner');
    if(!b)return;
    var bar=b.querySelector('[data-progress]');
    if(!bar)return;
    if(total&&total>0){{
      bar.style.width=(downloaded/total*100).toFixed(1)+'%';
      var pct=b.querySelector('[data-pct]');
      if(pct)pct.textContent=(downloaded/total*100).toFixed(0)+'%';
    }}
  }};
}})();"#,
        kf = keyframes_css(),
        bs = BANNER_STYLE,
        abs = ACCENT_BTN_STYLE,
        tbs = TEXT_BTN_STYLE,
        v = v,
        cv = cv,
    )
}

fn banner_js_downloading(downloaded: u64, total: Option<u64>) -> String {
    let pct = match total {
        Some(t) if t > 0 => format!("{:.0}%", downloaded as f64 / t as f64 * 100.0),
        _ => "…".to_string(),
    };
    let bar_width = match total {
        Some(t) if t > 0 => format!("{:.1}%", downloaded as f64 / t as f64 * 100.0),
        _ => "0%".to_string(),
    };
    format!(
        r#"(function(){{
  var old=document.getElementById('inkwell-update-banner');
  if(old)old.remove();
  var style=document.getElementById('inkwell-keyframes');
  if(!style){{
    style=document.createElement('style');
    style.id='inkwell-keyframes';
    style.textContent='{kf}';
    document.head.appendChild(style);
  }}
  var b=document.createElement('div');
  b.id='inkwell-update-banner';
  b.setAttribute('style','{bs}');
  b.innerHTML='<span>Downloading update\u2026</span>'
    +'<span data-pct style="color:var(--text-muted);font-size:12px;">{pct}</span>'
    +'<div data-progress style="{pbs}width:{bw};"></div>';
  document.body.insertBefore(b,document.body.firstChild);
}})();"#,
        kf = keyframes_css(),
        bs = BANNER_STYLE,
        pbs = PROGRESS_BAR_STYLE,
        pct = pct,
        bw = bar_width,
    )
}

fn banner_js_ready() -> String {
    format!(
        r#"(function(){{
  var old=document.getElementById('inkwell-update-banner');
  if(old)old.remove();
  var style=document.getElementById('inkwell-keyframes');
  if(!style){{
    style=document.createElement('style');
    style.id='inkwell-keyframes';
    style.textContent='{kf}';
    document.head.appendChild(style);
  }}
  var b=document.createElement('div');
  b.id='inkwell-update-banner';
  b.setAttribute('style','{bs}');
  b.innerHTML='<span>Update downloaded and ready to install.</span>'
    +'<button style="{abs}" onclick="window.__TAURI_INTERNALS__.invoke(\'restart_after_update\')">Restart Now</button>';
  document.body.insertBefore(b,document.body.firstChild);
}})();"#,
        kf = keyframes_css(),
        bs = BANNER_STYLE,
        abs = ACCENT_BTN_STYLE,
    )
}

fn banner_js_error(msg: &str) -> String {
    let m = js_escape(msg);
    format!(
        r#"(function(){{
  var old=document.getElementById('inkwell-update-banner');
  if(old)old.remove();
  var style=document.getElementById('inkwell-keyframes');
  if(!style){{
    style=document.createElement('style');
    style.id='inkwell-keyframes';
    style.textContent='{kf}';
    document.head.appendChild(style);
  }}
  var b=document.createElement('div');
  b.id='inkwell-update-banner';
  b.setAttribute('style','{bs}');
  b.innerHTML='<span style="color:#f38ba8;">Update failed: {m}</span>'
    +'<button style="{abs}" onclick="window.__TAURI_INTERNALS__.invoke(\'accept_update\')">Retry</button>'
    +'<button style="{tbs}" onclick="window.__TAURI_INTERNALS__.invoke(\'dismiss_update\')">Dismiss</button>';
  document.body.insertBefore(b,document.body.firstChild);
}})();"#,
        kf = keyframes_css(),
        bs = BANNER_STYLE,
        abs = ACCENT_BTN_STYLE,
        tbs = TEXT_BTN_STYLE,
        m = m,
    )
}

fn js_escape(s: &str) -> String {
    s.replace('\\', "\\\\")
        .replace('\'', "\\'")
        .replace('"', "\\\"")
        .replace('\n', "\\n")
        .replace('\r', "\\r")
}

// ── Banner injection ─────────────────────────────────────────────────────────

pub fn inject_update_banner(app: &AppHandle, state: &UpdateBannerState) {
    let Some(wv) = app.get_webview_window("main") else {
        return;
    };

    let js = match state {
        UpdateBannerState::None | UpdateBannerState::Dismissed => {
            // Remove banner if present
            "var b=document.getElementById('inkwell-update-banner');if(b)b.remove();".to_string()
        }
        UpdateBannerState::Available {
            version,
            current_version,
        } => banner_js_available(version, current_version),
        UpdateBannerState::Downloading { downloaded, total } => {
            banner_js_downloading(*downloaded, *total)
        }
        UpdateBannerState::ReadyToRestart => banner_js_ready(),
        UpdateBannerState::Error(msg) => banner_js_error(msg),
    };

    let _ = wv.eval(&js);
}

// ── Toast injection ──────────────────────────────────────────────────────────

pub fn inject_toast(app: &AppHandle, message: &str) {
    let Some(wv) = app.get_webview_window("main") else {
        return;
    };

    let m = js_escape(message);
    let js = format!(
        r#"(function(){{
  var old=document.getElementById('inkwell-toast');
  if(old)old.remove();
  var t=document.createElement('div');
  t.id='inkwell-toast';
  t.textContent='{m}';
  t.setAttribute('style','\
    position:fixed;bottom:24px;left:50%;transform:translateX(-50%);\
    background:var(--bg-hover);border:1px solid var(--border);\
    color:var(--text-secondary);font-family:system-ui,sans-serif;\
    font-size:13px;padding:8px 20px;border-radius:999px;\
    z-index:99999;transition:opacity 500ms ease;\
  ');
  document.body.appendChild(t);
  setTimeout(function(){{t.style.opacity='0';}},2500);
  setTimeout(function(){{if(t.parentNode)t.parentNode.removeChild(t);}},3000);
}})();"#,
        m = m,
    );

    let _ = wv.eval(&js);
}
