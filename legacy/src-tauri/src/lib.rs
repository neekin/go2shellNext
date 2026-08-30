use tauri::{Manager, RunEvent};

mod finder_sync;
mod settings;
mod terminal;

fn show_settings(handle: &tauri::AppHandle) {
    if let Some(window) = handle.get_webview_window("main") {
        window.show().ok();
        window.set_focus().ok();
    }
}

fn open_terminal_at_dir(handle: &tauri::AppHandle, dir: &std::path::Path) {
    let s = terminal::get_cached_settings(handle);
    terminal::open_terminal_at(dir, &s, handle);
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let _ = fix_path_env::fix();

    let app = tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            #[cfg(target_os = "macos")]
            app.set_activation_policy(tauri::ActivationPolicy::Accessory);

            let handle = app.handle().clone();
            std::thread::spawn(move || {
                finder_sync::listen_for_finder_requests(handle);
            });

            let args: Vec<String> = std::env::args().collect();

            if let Some(path_arg) = args.iter().find(|a| a.starts_with("--open-dir=")) {
                // Launched by the FinderSync extension (host app was not running).
                let dir = path_arg.trim_start_matches("--open-dir=");
                open_terminal_at_dir(&app.handle().clone(), std::path::Path::new(dir));
            } else if let Some(path) = finder_sync::consume_pending_requested_path(10) {
                // Fallback: the extension wrote a request right before launching us
                // but the launch arguments did not arrive. Only honor it if it is
                // fresh, so a stale request cannot hijack a direct launch.
                open_terminal_at_dir(&app.handle().clone(), &path);
            } else {
                // Direct launch (double-click, `open`, --settings): show settings.
                show_settings(&app.handle().clone());
            }

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            settings::get_settings,
            settings::save_settings,
            settings::open_extension_settings,
            settings::check_finder_extension,
            settings::restart_finder,
            settings::reveal_app,
        ])
        .build(tauri::generate_context!())
        .expect("error while running Go2ShellNext");

    app.run(|_handle, _event| {
        #[cfg(target_os = "macos")]
        if let RunEvent::Reopen { .. } = _event {
            // Re-launching the app icon while it is already running means the
            // user wants the settings window, not another terminal.
            show_settings(_handle);
        }
    });
}
