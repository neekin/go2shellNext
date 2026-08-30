use tauri::{AppHandle, Manager};
use std::fs;
use std::path::PathBuf;

use crate::terminal::Settings;

const SETTINGS_FILE: &str = "settings.json";

fn settings_dir(app: &AppHandle) -> PathBuf {
    let app_data = app.path().app_data_dir().unwrap_or_else(|_| {
        dirs::home_dir().unwrap_or_default().join(".go2shellnext")
    });
    if !app_data.exists() {
        let _ = fs::create_dir_all(&app_data);
    }
    migrate_legacy_settings(&app_data);
    app_data
}

/// Settings used to live under the old `com.go2shell.app` identifier; carry them
/// over once so users don't have to reconfigure after the rename.
fn migrate_legacy_settings(app_data: &PathBuf) {
    let target = app_data.join(SETTINGS_FILE);
    if target.exists() {
        return;
    }
    let legacy = dirs::home_dir()
        .map(|h| h.join("Library/Application Support/com.go2shell.app"))
        .unwrap_or_default();
    let legacy_settings = legacy.join(SETTINGS_FILE);
    if legacy_settings.exists() {
        let _ = fs::copy(&legacy_settings, &target);
    }
}

fn settings_path(app: &AppHandle) -> PathBuf {
    settings_dir(app).join(SETTINGS_FILE)
}

pub fn load_settings_from_file(app: &AppHandle) -> Settings {
    let path = settings_path(app);
    if path.exists() {
        if let Ok(data) = fs::read_to_string(&path) {
            if let Ok(settings) = serde_json::from_str::<Settings>(&data) {
                return settings;
            }
        }
    }
    Settings::default()
}

#[tauri::command]
pub fn get_settings(app: AppHandle) -> Settings {
    load_settings_from_file(&app)
}

#[tauri::command]
pub fn save_settings(app: AppHandle, settings: Settings) -> Result<(), String> {
    crate::terminal::invalidate_settings_cache();
    let path = settings_path(&app);
    let data = serde_json::to_string_pretty(&settings).map_err(|e| e.to_string())?;
    fs::write(&path, data).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn open_extension_settings() -> Result<(), String> {
    std::process::Command::new("open")
        .arg("x-apple.systempreferences:com.apple.Extensions-Settings.extension")
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn check_finder_extension() -> bool {
    std::process::Command::new("pluginkit")
        .args(["-m", "-p", "com.apple.FinderSync"])
        .output()
        .map(|o| String::from_utf8_lossy(&o.stdout).contains("go2shellnext"))
        .unwrap_or(false)
}

#[tauri::command]
pub fn restart_finder() -> Result<(), String> {
    std::process::Command::new("killall")
        .arg("Finder")
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
pub fn reveal_app(app: AppHandle) -> Result<(), String> {
    let exe_path = std::env::current_exe()
        .map_err(|e| e.to_string())?;
    let app_path = exe_path.ancestors()
        .nth(3)
        .unwrap_or(&exe_path)
        .to_path_buf();
    std::process::Command::new("open")
        .arg("-R")
        .arg(&app_path)
        .spawn()
        .map_err(|e| e.to_string())?;
    Ok(())
}
