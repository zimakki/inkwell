use std::env;
use std::fs;
use std::path::PathBuf;

fn ensure_sidecar_placeholder() {
    let target = env::var("TARGET").unwrap_or_default();

    let sidecar_name = match target.as_str() {
        "aarch64-apple-darwin" => Some("inkwell-aarch64-apple-darwin"),
        "x86_64-apple-darwin" => Some("inkwell-x86_64-apple-darwin"),
        "x86_64-unknown-linux-gnu" => Some("inkwell-x86_64-unknown-linux-gnu"),
        "x86_64-pc-windows-msvc" => Some("inkwell-x86_64-pc-windows-msvc.exe"),
        _ => None,
    };

    let Some(sidecar_name) = sidecar_name else {
        return;
    };

    let sidecar_path = PathBuf::from("binaries").join(sidecar_name);
    if sidecar_path.exists() {
        return;
    }

    if let Some(parent) = sidecar_path.parent() {
        fs::create_dir_all(parent).expect("failed to create binaries directory");
    }

    fs::write(&sidecar_path, []).expect("failed to create placeholder sidecar");
}

fn main() {
    ensure_sidecar_placeholder();
    tauri_build::build()
}
