#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::sync::Mutex;
use std::thread;
use std::time::{Duration, Instant};
use tauri::menu::{AboutMetadataBuilder, MenuBuilder, SubmenuBuilder};
use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;
use tauri_plugin_updater::{Update, UpdaterExt};

const CHECK_FOR_UPDATES_MENU_ID: &str = "check-for-updates";

#[derive(Clone, Copy, PartialEq, Eq)]
enum UpdateCheckMode {
    Startup,
    Manual,
}

fn inkwell_dir() -> PathBuf {
    dirs::home_dir()
        .expect("could not determine home directory")
        .join(".inkwell")
}

fn read_port() -> Option<u16> {
    let port_file = inkwell_dir().join("port");
    fs::read_to_string(port_file)
        .ok()
        .and_then(|s| s.trim().parse().ok())
}

fn daemon_healthy(port: u16) -> bool {
    reqwest::blocking::Client::new()
        .get(format!("http://localhost:{}/health", port))
        .timeout(Duration::from_secs(2))
        .send()
        .map(|r| r.status().is_success())
        .unwrap_or(false)
}

fn find_running_daemon() -> Option<u16> {
    read_port().filter(|&port| daemon_healthy(port))
}

fn wait_for_daemon(timeout: Duration) -> Result<u16, String> {
    let start = Instant::now();

    loop {
        if let Some(port) = find_running_daemon() {
            return Ok(port);
        }

        if start.elapsed() > timeout {
            return Err(format!(
                "Daemon did not start within {} seconds. Check ~/.inkwell/daemon.log",
                timeout.as_secs()
            ));
        }

        thread::sleep(Duration::from_millis(250));
    }
}

fn markdown_path_from_url(url: &tauri::Url) -> Option<String> {
    if url.scheme() == "inkwell" {
        return url
            .query_pairs()
            .find(|(key, _)| key == "path")
            .map(|pair| pair.1.to_string());
    }

    if url.scheme() == "file" {
        let path = url.to_file_path().ok()?;
        let path = path.to_string_lossy().to_string();

        if path.ends_with(".md") || path.ends_with(".markdown") {
            return Some(path);
        }
    }

    None
}

fn navigate_to_url(app: &tauri::AppHandle, url: String) -> Result<(), String> {
    if let Some(window) = app.get_webview_window("main") {
        window
            .navigate(url.parse::<tauri::Url>().map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        let _ = window.set_focus();
        return Ok(());
    }

    Err("Main window not found".into())
}

fn navigate_current(app: &tauri::AppHandle, current_path: Option<&str>) -> Result<(), String> {
    let port = read_port().ok_or_else(|| "Daemon port not available".to_string())?;
    let url = match current_path {
        Some(path) => format!(
            "http://localhost:{}/?path={}",
            port,
            urlencoding::encode(path)
        ),
        None => format!("http://localhost:{}", port),
    };

    navigate_to_url(app, url)
}

fn navigate_to_file(
    app: &tauri::AppHandle,
    current_path: &Mutex<Option<String>>,
    path: &str,
) -> Result<(), String> {
    *current_path.lock().unwrap() = Some(path.to_string());
    navigate_current(app, Some(path))
}

fn show_error(app: &tauri::AppHandle, title: &str, message: &str) {
    show_error_dialog(app, title, message);
}

#[cfg(target_os = "macos")]
fn build_app_menu<R: Runtime>(app: &AppHandle<R>) -> tauri::Result<tauri::menu::Menu<R>> {
    let about_metadata = AboutMetadataBuilder::new()
        .name(Some(app.package_info().name.clone()))
        .version(Some(app.package_info().version.to_string()))
        .build();

    let app_menu = SubmenuBuilder::new(app, app.package_info().name.clone())
        .about(Some(about_metadata))
        .separator()
        .text(CHECK_FOR_UPDATES_MENU_ID, "Check for Updates...")
        .separator()
        .quit()
        .build()?;

    MenuBuilder::new(app).item(&app_menu).build()
}

#[cfg(target_os = "macos")]
fn run_osascript(script: &str, args: &[&str]) -> Result<String, String> {
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .args(args)
        .output()
        .map_err(|error| error.to_string())?;

    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

#[cfg(target_os = "macos")]
fn show_info_dialog<R: Runtime>(_app: &AppHandle<R>, title: &str, message: &str) {
    let _ = run_osascript(
        r#"on run argv
set dialogMessage to item 1 of argv
set dialogTitle to item 2 of argv
display dialog dialogMessage with title dialogTitle buttons {"OK"} default button "OK" with icon note
return "OK"
end run"#,
        &[message, title],
    );
}

#[cfg(not(target_os = "macos"))]
fn show_info_dialog<R: Runtime>(_app: &AppHandle<R>, _title: &str, _message: &str) {}

#[cfg(target_os = "macos")]
fn show_error_dialog<R: Runtime>(_app: &AppHandle<R>, title: &str, message: &str) {
    let _ = run_osascript(
        r#"on run argv
set dialogMessage to item 1 of argv
set dialogTitle to item 2 of argv
display dialog dialogMessage with title dialogTitle buttons {"OK"} default button "OK" with icon stop
return "OK"
end run"#,
        &[message, title],
    );
}

#[cfg(not(target_os = "macos"))]
fn show_error_dialog<R: Runtime>(_app: &AppHandle<R>, title: &str, message: &str) {
    eprintln!("{title}: {message}");
}

#[cfg(target_os = "macos")]
fn ask_to_install_update<R: Runtime>(_app: &AppHandle<R>, title: &str, message: &str) -> bool {
    run_osascript(
        r#"on run argv
set dialogMessage to item 1 of argv
set dialogTitle to item 2 of argv
set buttonName to button returned of (display dialog dialogMessage with title dialogTitle buttons {"Later", "Install"} default button "Install" cancel button "Later" with icon note)
return buttonName
end run"#,
        &[message, title],
    )
    .map(|button| button == "Install")
    .unwrap_or(false)
}

// Non-macOS: no native dialog available, so updates are never auto-installed.
// To support Linux/Windows in the future, implement platform-specific dialogs here.
#[cfg(not(target_os = "macos"))]
fn ask_to_install_update<R: Runtime>(_app: &AppHandle<R>, _title: &str, _message: &str) -> bool {
    false
}

fn update_prompt_message(update: &Update) -> String {
    let mut message = format!(
        "Inkwell {} is available. You’re currently on {}.",
        update.version, update.current_version
    );

    if let Some(body) = update
        .body
        .as_deref()
        .map(str::trim)
        .filter(|body| !body.is_empty())
    {
        message.push_str("\n\nRelease notes:\n");
        message.push_str(body);
    }

    message.push_str("\n\nInstall the update now?");
    message
}

static UPDATE_CHECK_IN_PROGRESS: AtomicBool = AtomicBool::new(false);

fn trigger_update_check<R: Runtime>(app: AppHandle<R>, mode: UpdateCheckMode) {
    if UPDATE_CHECK_IN_PROGRESS.swap(true, Ordering::SeqCst) {
        return;
    }

    tauri::async_runtime::spawn(async move {
        if let Err(error) = run_update_check(&app, mode).await {
            if mode == UpdateCheckMode::Manual {
                show_error_dialog(&app, "Update Check Failed", &error);
            } else {
                eprintln!("Startup update check failed: {error}");
            }
        }
        UPDATE_CHECK_IN_PROGRESS.store(false, Ordering::SeqCst);
    });
}

async fn run_update_check<R: Runtime + 'static>(
    app: &AppHandle<R>,
    mode: UpdateCheckMode,
) -> Result<(), String> {
    if mode == UpdateCheckMode::Startup {
        tokio::time::sleep(Duration::from_secs(10)).await;
    }

    let updater = app.updater().map_err(|error| error.to_string())?;
    let maybe_update = updater.check().await.map_err(|error| error.to_string())?;

    match maybe_update {
        Some(update) => install_update(app, update, mode).await,
        None => {
            if mode == UpdateCheckMode::Manual {
                let app = app.clone();
                tauri::async_runtime::spawn_blocking(move || {
                    show_info_dialog(
                        &app,
                        "No Updates Available",
                        "You’re already running the latest version of Inkwell.",
                    );
                })
                .await
                .map_err(|error| error.to_string())?;
            }

            Ok(())
        }
    }
}

async fn install_update<R: Runtime + 'static>(
    app: &AppHandle<R>,
    update: Update,
    mode: UpdateCheckMode,
) -> Result<(), String> {
    let message = update_prompt_message(&update);
    let app_clone = app.clone();
    let should_install = tauri::async_runtime::spawn_blocking(move || {
        ask_to_install_update(&app_clone, "Update Available", &message)
    })
    .await
    .map_err(|error| error.to_string())?;

    if !should_install {
        return Ok(());
    }

    if mode == UpdateCheckMode::Manual {
        let app_clone = app.clone();
        tauri::async_runtime::spawn_blocking(move || {
            show_info_dialog(
                &app_clone,
                "Installing Update",
                "Inkwell is downloading the update and will close when installation begins.",
            );
        })
        .await
        .map_err(|error| error.to_string())?;
    }

    update
        .download_and_install(|_, _| {}, || {})
        .await
        .map_err(|error| error.to_string())
}

fn stop_owned_daemon(owns_sidecar: &AtomicBool) {
    if owns_sidecar.swap(false, Ordering::SeqCst) {
        if let Some(port) = read_port() {
            let _ = reqwest::blocking::Client::builder()
                .timeout(Duration::from_secs(2))
                .build()
                .ok()
                .and_then(|client| {
                    client
                        .post(format!("http://localhost:{}/stop", port))
                        .send()
                        .ok()
                });
        }
    }
}

fn main() {
    let owns_sidecar = Arc::new(AtomicBool::new(false));
    let owns_sidecar_clone = owns_sidecar.clone();
    let owns_sidecar_run = owns_sidecar.clone();
    let current_path = Arc::new(Mutex::new(None::<String>));
    let current_path_setup = current_path.clone();
    let current_path_run = current_path.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .on_menu_event(|app, event| {
            if event.id() == CHECK_FOR_UPDATES_MENU_ID {
                trigger_update_check(app.clone(), UpdateCheckMode::Manual);
            }
        })
        .setup(move |app| {
            let shell = app.shell();
            let app_handle = app.handle().clone();

            #[cfg(target_os = "macos")]
            {
                let menu = build_app_menu(&app_handle)?;
                app_handle.set_menu(menu)?;
            }

            let port = if let Some(port) = find_running_daemon() {
                port
            } else {
                let (rx, _child) = match shell
                    .sidecar("inkwell")
                    .and_then(|cmd| cmd.args(["daemon", "--theme", "dark"]).spawn())
                {
                    Ok(result) => result,
                    Err(e) => {
                        let msg = format!(
                            "Failed to start Inkwell daemon: {}\n\nCheck ~/.inkwell/daemon.log",
                            e
                        );
                        show_error(
                            &app_handle,
                            "Sidecar Error",
                            &msg,
                        );
                        return Err(msg.into());
                    }
                };

                owns_sidecar.store(true, Ordering::SeqCst);

                let crash_handle = app_handle.clone();
                let crash_owns = owns_sidecar.clone();
                let crash_current_path = current_path_setup.clone();

                tauri::async_runtime::spawn(async move {
                    let mut process_rx = rx;

                    loop {
                        while let Some(event) = process_rx.recv().await {
                            if let CommandEvent::Terminated(payload) = event {
                                if !crash_owns.load(Ordering::SeqCst) {
                                    return;
                                }

                                eprintln!("Sidecar terminated: {:?}", payload);

                                let shell = crash_handle.shell();

                                match shell
                                    .sidecar("inkwell")
                                    .and_then(|cmd| cmd.args(["daemon", "--theme", "dark"]).spawn())
                                {
                                    Ok((new_rx, _)) => {
                                        eprintln!("Sidecar restarted successfully");

                                        match wait_for_daemon(Duration::from_secs(10)).and_then(
                                            |_| {
                                                let path = crash_current_path.lock().unwrap().clone();
                                                navigate_current(&crash_handle, path.as_deref())
                                            },
                                        ) {
                                            Ok(()) => {
                                                process_rx = new_rx;
                                                break;
                                            }
                                            Err(err) => {
                                                show_error(
                                                    &crash_handle,
                                                    "Recovery Error",
                                                    &format!(
                                                        "Sidecar restarted but failed to restore the UI: {}",
                                                        err
                                                    ),
                                                );
                                                return;
                                            }
                                        }
                                    }
                                    Err(err) => {
                                        show_error(
                                            &crash_handle,
                                            "Recovery Error",
                                            &format!(
                                                "Failed to restart Inkwell daemon: {}\n\nCheck ~/.inkwell/daemon.log",
                                                err
                                            ),
                                        );
                                        return;
                                    }
                                }
                            }
                        }
                    }
                });

                match wait_for_daemon(Duration::from_secs(10)) {
                    Ok(port) => port,
                    Err(msg) => {
                        show_error(&app_handle, "Startup Timeout", &msg);
                        return Err(msg.into());
                    }
                }
            };

            navigate_to_url(&app_handle, format!("http://localhost:{}", port))
                .expect("failed to navigate to inkwell");

            let deep_link_handle = app_handle.clone();
            let deep_link_path = current_path_setup.clone();
            app.deep_link().on_open_url(move |event| {
                for url in event.urls() {
                    if let Some(path) = markdown_path_from_url(&url) {
                        let _ = navigate_to_file(&deep_link_handle, &deep_link_path, &path);
                    }
                }
            });

            if let Ok(Some(urls)) = app.deep_link().get_current() {
                for url in urls {
                    if let Some(path) = markdown_path_from_url(&url) {
                        let _ = navigate_to_file(&app_handle, &current_path_setup, &path);
                    }
                }
            }

            trigger_update_check(app_handle.clone(), UpdateCheckMode::Startup);

            Ok(())
        })
        .on_window_event(move |_window, event| {
            if let tauri::WindowEvent::Destroyed = event {
                stop_owned_daemon(&owns_sidecar_clone);
            }
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(move |app_handle, event| match event {
            tauri::RunEvent::Opened { urls } => {
                for url in urls {
                    if let Some(path) = markdown_path_from_url(&url) {
                        let _ = navigate_to_file(app_handle, &current_path_run, &path);
                    }
                }
            }
            tauri::RunEvent::Exit | tauri::RunEvent::ExitRequested { .. } => {
                stop_owned_daemon(&owns_sidecar_run);
            }
            _ => {}
        });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_url(s: &str) -> tauri::Url {
        tauri::Url::parse(s).unwrap()
    }

    #[test]
    fn test_inkwell_scheme_extracts_path() {
        let url = parse_url("inkwell://open?path=/tmp/readme.md");
        assert_eq!(
            markdown_path_from_url(&url),
            Some("/tmp/readme.md".to_string())
        );
    }

    #[test]
    fn test_inkwell_scheme_without_path_param() {
        let url = parse_url("inkwell://open?other=value");
        assert_eq!(markdown_path_from_url(&url), None);
    }

    #[test]
    fn test_file_scheme_md_extension() {
        let url = parse_url("file:///Users/test/doc.md");
        assert_eq!(
            markdown_path_from_url(&url),
            Some("/Users/test/doc.md".to_string())
        );
    }

    #[test]
    fn test_file_scheme_markdown_extension() {
        let url = parse_url("file:///Users/test/doc.markdown");
        assert_eq!(
            markdown_path_from_url(&url),
            Some("/Users/test/doc.markdown".to_string())
        );
    }

    #[test]
    fn test_file_scheme_non_markdown_returns_none() {
        let url = parse_url("file:///Users/test/image.png");
        assert_eq!(markdown_path_from_url(&url), None);
    }

    #[test]
    fn test_http_scheme_returns_none() {
        let url = parse_url("http://example.com/readme.md");
        assert_eq!(markdown_path_from_url(&url), None);
    }

    #[test]
    fn test_inkwell_dir_is_under_home() {
        let dir = inkwell_dir();
        assert!(dir.ends_with(".inkwell"));
    }
}
