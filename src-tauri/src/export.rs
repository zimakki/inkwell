use tauri::AppHandle;
use tauri_plugin_dialog::DialogExt;

#[tauri::command]
pub async fn save_export_pdf(
    app: AppHandle,
    export_url: String,
    default_name: String,
    daemon_port: u16,
) -> Result<(), String> {
    if !export_url.starts_with("/export.pdf") {
        return Err("invalid export_url".into());
    }

    let url = format!("http://127.0.0.1:{}{}", daemon_port, export_url);

    let bytes = reqwest::get(&url)
        .await
        .map_err(|e| format!("fetch failed: {e}"))?
        .error_for_status()
        .map_err(|e| format!("daemon returned non-2xx: {e}"))?
        .bytes()
        .await
        .map_err(|e| format!("read body failed: {e}"))?;

    let chosen = app
        .dialog()
        .file()
        .set_file_name(&default_name)
        .add_filter("PDF", &["pdf"])
        .blocking_save_file();

    let path = match chosen {
        Some(p) => p,
        None => return Ok(()),
    };

    let real_path = path
        .into_path()
        .map_err(|e| format!("invalid save path: {e}"))?;

    std::fs::write(&real_path, &bytes).map_err(|e| format!("write failed: {e}"))?;

    Ok(())
}
