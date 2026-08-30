use std::path::Path;
use std::process::Command;
use std::sync::Mutex;
use tauri::AppHandle;

use crate::settings;

static CACHED_SETTINGS: Mutex<Option<Settings>> = Mutex::new(None);

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Settings {
    pub terminal: String,
    pub custom_command: String,
    pub open_in_tab: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            terminal: "Terminal".to_string(),
            custom_command: String::new(),
            open_in_tab: false,
        }
    }
}

pub fn get_cached_settings(handle: &AppHandle) -> Settings {
    let mut cached = CACHED_SETTINGS.lock().unwrap();
    if cached.is_none() {
        *cached = Some(settings::load_settings_from_file(handle));
    }
    cached.clone().unwrap()
}

pub fn invalidate_settings_cache() {
    *CACHED_SETTINGS.lock().unwrap() = None;
}

pub fn open_terminal_at_finder(handle: &AppHandle) {
    let s = get_cached_settings(handle);

    match s.terminal.as_str() {
        "Terminal" => open_terminal_app_finder(&s.custom_command, s.open_in_tab),
        "iTerm" => open_iterm2_finder(&s.custom_command, s.open_in_tab),
        name => {
            if let Some(finder_path) = get_finder_path() {
                let path = Path::new(&finder_path);
                let escaped = shell_escape(path);
                open_generic_terminal(name, &escaped, &s.custom_command);
            }
        }
    }
}

pub fn open_terminal_at(path: &Path, settings: &Settings, _app_handle: &AppHandle) {
    let escaped_path = shell_escape(path);
    match settings.terminal.as_str() {
        "Terminal" => open_terminal_app(&escaped_path, &settings.custom_command, settings.open_in_tab),
        "iTerm" => open_iterm2(&escaped_path, &settings.custom_command, settings.open_in_tab),
        name => open_generic_terminal(name, &escaped_path, &settings.custom_command),
    }
}

fn get_finder_path() -> Option<String> {
    let script = r#"
tell application "Finder"
    try
        set theFolder to target of front window as alias
        return POSIX path of theFolder
    on error
        return POSIX path of (home as alias)
    end try
end tell
"#;
    let output = Command::new("osascript")
        .arg("-e")
        .arg(script)
        .output()
        .ok()?;
    if output.status.success() {
        let path = String::from_utf8_lossy(&output.stdout).trim().to_string();
        if !path.is_empty() {
            return Some(path);
        }
    }
    None
}

fn shell_escape(path: &Path) -> String {
    let s = path.to_string_lossy().to_string();
    if s.contains(' ')
        || s.contains('&')
        || s.contains('|')
        || s.contains(';')
        || s.contains('<')
        || s.contains('>')
        || s.contains('(')
        || s.contains(')')
        || s.contains('$')
        || s.contains('`')
        || s.contains('\\')
        || s.contains('"')
        || s.contains('\'')
        || s.contains('!')
        || s.contains('*')
        || s.contains('?')
        || s.contains('[')
        || s.contains(']')
        || s.contains('{')
        || s.contains('}')
        || s.contains('^')
        || s.contains('#')
        || s.contains('~')
    {
        format!("'{}'", s.replace("'", "'\\''"))
    } else {
        s
    }
}

fn open_terminal_app_finder(custom_command: &str, open_in_tab: bool) {
    let cd_part = "cd (POSIX path of (target of front window of application \"Finder\" as alias))";
    let full_cmd = if custom_command.is_empty() {
        cd_part.to_string()
    } else {
        format!("{} && {}", cd_part, custom_command)
    };

    let script = if open_in_tab {
        format!(
            "tell application \"Finder\"\nset finderPath to POSIX path of (target of front window as alias)\nend tell\ntell application \"Terminal\"\nactivate\nif (count of windows) > 0 then\ntell application \"System Events\" to keystroke \"t\" using command down\ndo script \"cd \" & quoted form of finderPath{} in front window\nelse\ndo script \"cd \" & quoted form of finderPath{}\nend if\nend tell",
            if custom_command.is_empty() { "".to_string() } else { format!(" && {}", custom_command) },
            if custom_command.is_empty() { "".to_string() } else { format!(" && {}", custom_command) }
        )
    } else {
        format!(
            "tell application \"Finder\"\nset finderPath to POSIX path of (target of front window as alias)\nend tell\ntell application \"Terminal\"\nactivate\ndo script \"cd \" & quoted form of finderPath{} & \"\"\nend tell",
            if custom_command.is_empty() { "".to_string() } else { format!(" && {}", custom_command) }
        )
    };

    let _ = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .spawn();
}

fn open_iterm2_finder(custom_command: &str, open_in_tab: bool) {
    let cmd_suffix = if custom_command.is_empty() {
        "".to_string()
    } else {
        format!(" && {}", custom_command)
    };

    let script = if open_in_tab {
        format!(
            "tell application \"Finder\"\nset finderPath to POSIX path of (target of front window as alias)\nend tell\ntell application \"iTerm2\"\nactivate\ntry\nset currentWindow to front window\ntell currentWindow\nset newTab to (create tab with default profile)\ntell current session of newTab\nwrite text \"cd \" & quoted form of finderPath & \"{}\"\nend tell\nend tell\non error\nset currentWindow to (create window with default profile)\ntell current session of currentWindow\nwrite text \"cd \" & quoted form of finderPath & \"{}\"\nend tell\nend try\nend tell",
            cmd_suffix, cmd_suffix
        )
    } else {
        format!(
            "tell application \"Finder\"\nset finderPath to POSIX path of (target of front window as alias)\nend tell\ntell application \"iTerm2\"\nactivate\ntry\ntell front window\nset newSession to (create window with default profile)\ntell current session of newSession\nwrite text \"cd \" & quoted form of finderPath & \"{}\"\nend tell\nend tell\non error\nset currentWindow to (create window with default profile)\ntell current session of currentWindow\nwrite text \"cd \" & quoted form of finderPath & \"{}\"\nend tell\nend try\nend tell",
            cmd_suffix, cmd_suffix
        )
    };

    let _ = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .spawn();
}

fn open_terminal_app(path: &str, custom_command: &str, open_in_tab: bool) {
    let cd_cmd = format!("cd {}", path);
    let full_cmd = if custom_command.is_empty() {
        cd_cmd
    } else {
        format!("{} && {}", cd_cmd, custom_command)
    };

    let script = if open_in_tab {
        format!(
            "tell application \"Terminal\"\nactivate\nif (count of windows) > 0 then\ntell application \"System Events\" to keystroke \"t\" using command down\ndo script \"{}\" in front window\nelse\ndo script \"{}\"\nend if\nend tell",
            full_cmd, full_cmd
        )
    } else {
        format!(
            "tell application \"Terminal\"\nactivate\ndo script \"{}\"\nend tell",
            full_cmd
        )
    };

    let _ = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .spawn();
}

fn open_iterm2(path: &str, custom_command: &str, open_in_tab: bool) {
    let cd_cmd = format!("cd {}", path);
    let full_cmd = if custom_command.is_empty() {
        cd_cmd
    } else {
        format!("{} && {}", cd_cmd, custom_command)
    };

    let script = if open_in_tab {
        format!(
            "tell application \"iTerm2\"\nactivate\ntry\nset currentWindow to front window\ntell currentWindow\nset newSession to (create tab with default profile)\ntell current session of newSession\nwrite text \"{}\"\nend tell\nend tell\non error\nset currentWindow to (create window with default profile)\ntell current session of currentWindow\nwrite text \"{}\"\nend tell\nend try\nend tell",
            full_cmd, full_cmd
        )
    } else {
        format!(
            "tell application \"iTerm2\"\nactivate\ntry\ntell front window\nset newSession to (create window with default profile)\ntell current session of newSession\nwrite text \"{}\"\nend tell\nend tell\non error\nset currentWindow to (create window with default profile)\ntell current session of currentWindow\nwrite text \"{}\"\nend tell\nend try\nend tell",
            full_cmd, full_cmd
        )
    };

    let _ = Command::new("osascript")
        .arg("-e")
        .arg(&script)
        .spawn();
}

fn open_generic_terminal(name: &str, path: &str, custom_command: &str) {
    let _ = Command::new("open")
        .arg("-a")
        .arg(name)
        .arg("--args")
        .arg("--directory")
        .arg(path)
        .spawn()
        .or_else(|_| {
            Command::new("open")
                .arg("-a")
                .arg(name)
                .arg(path)
                .spawn()
        });

    if !custom_command.is_empty() {
        let cd_cmd = format!("cd {}", path);
        let full_cmd = format!("{} && {}", cd_cmd, custom_command);
        let script = format!(
            "tell application \"{}\"\nactivate\ndelay 0.5\ndo script \"{}\" in front window\nend tell",
            name, full_cmd
        );
        let _ = Command::new("osascript")
            .arg("-e")
            .arg(&script)
            .spawn();
    }
}
