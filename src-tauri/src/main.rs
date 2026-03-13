#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};
use tauri::Manager;
use tauri_plugin_deep_link::DeepLinkExt;
use tauri_plugin_shell::process::CommandEvent;
use tauri_plugin_shell::ShellExt;

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

fn navigate_to_file(app: &tauri::AppHandle, path: &str) {
    if let Some(window) = app.get_webview_window("main") {
        if let Some(port) = read_port() {
            let nav_url = format!(
                "http://localhost:{}/?path={}",
                port,
                urlencoding::encode(path)
            );
            let _ = window.navigate(nav_url.parse().unwrap());
            let _ = window.set_focus();
        }
    }
}

fn show_error(_app: &tauri::AppHandle, title: &str, message: &str) {
    eprintln!("ERROR: {} - {}", title, message);
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

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_deep_link::init())
        .setup(move |app| {
            let shell = app.shell();
            let app_handle = app.handle().clone();

            let port = if let Some(port) = find_running_daemon() {
                port
            } else {
                let (rx, _child) = match shell
                    .sidecar("inkwell")
                    .and_then(|cmd| cmd.args(["daemon", "--theme", "dark"]).spawn())
                {
                    Ok(result) => result,
                    Err(e) => {
                        show_error(
                            &app_handle,
                            "Sidecar Error",
                            &format!(
                                "Failed to start Inkwell daemon: {}\n\nCheck ~/.inkwell/daemon.log",
                                e
                            ),
                        );
                        return Ok(());
                    }
                };

                owns_sidecar.store(true, Ordering::SeqCst);

                let crash_handle = app_handle.clone();
                let crash_owns = owns_sidecar.clone();

                tauri::async_runtime::spawn(async move {
                    let mut rx = rx;

                    while let Some(event) = rx.recv().await {
                        if let CommandEvent::Terminated(payload) = event {
                            if crash_owns.load(Ordering::SeqCst) {
                                eprintln!("Sidecar terminated: {:?}", payload);

                                let shell = crash_handle.shell();

                                if let Ok((new_rx, _)) = shell
                                    .sidecar("inkwell")
                                    .and_then(|cmd| cmd.args(["daemon", "--theme", "dark"]).spawn())
                                {
                                    eprintln!("Sidecar restarted successfully");
                                    let mut new_rx = new_rx;

                                    while let Some(evt) = new_rx.recv().await {
                                        if matches!(evt, CommandEvent::Terminated(_)) {
                                            break;
                                        }
                                    }
                                }
                            }

                            break;
                        }
                    }
                });

                match wait_for_daemon(Duration::from_secs(10)) {
                    Ok(port) => port,
                    Err(msg) => {
                        show_error(&app_handle, "Startup Timeout", &msg);
                        return Ok(());
                    }
                }
            };

            let window = app.get_webview_window("main").unwrap();
            let url = format!("http://localhost:{}", port);
            window
                .navigate(url.parse().unwrap())
                .expect("failed to navigate to inkwell");

            let deep_link_handle = app_handle.clone();
            app.deep_link().on_open_url(move |event| {
                if let Some(url) = event.urls().first() {
                    if let Some(path) = url
                        .query_pairs()
                        .find(|(k, _)| k == "path")
                        .map(|(_, v)| v.to_string())
                    {
                        navigate_to_file(&deep_link_handle, &path);
                    }
                }
            });

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
                    let path = url.path();
                    if path.ends_with(".md") || path.ends_with(".markdown") {
                        navigate_to_file(app_handle, path);
                    }
                }
            }
            tauri::RunEvent::Exit | tauri::RunEvent::ExitRequested { .. } => {
                stop_owned_daemon(&owns_sidecar_run);
            }
            _ => {}
        });
}
