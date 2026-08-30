use core_foundation::base::{CFRelease, FromVoid, TCFType};
use core_foundation::string::CFString;
use std::ffi::c_void;
use std::path::PathBuf;
use std::sync::Mutex;
use tauri::{AppHandle, Manager};

const APP_GROUP_ID: &str = "TEAMID.com.go2shellnext.group";
const NOTIFICATION_NAME: &str = "com.go2shellnext.app.openShell";
const PATH_KEY: &str = "requestedPath";
const REQUESTED_AT_KEY: &str = "requestedAt";
const SHOW_UI_KEY: &str = "showUI";
const QUIT_KEY: &str = "quitApp";

type CFNotificationCenterRef = *mut c_void;
type CFIndex = i64;

extern "C" {
    fn CFNotificationCenterGetDarwinNotifyCenter() -> CFNotificationCenterRef;
    fn CFNotificationCenterAddObserver(
        center: CFNotificationCenterRef,
        observer: *mut c_void,
        callback: extern "C" fn(
            center: CFNotificationCenterRef,
            observer: *mut c_void,
            name: core_foundation::string::CFStringRef,
            object: *const c_void,
            user_info: *const c_void,
        ),
        name: core_foundation::string::CFStringRef,
        object: *const c_void,
        suspension_behavior: CFIndex,
    );

    fn CFPreferencesCopyAppValue(
        key: core_foundation::string::CFStringRef,
        application_id: core_foundation::string::CFStringRef,
    ) -> *const c_void;
    fn CFPreferencesSetAppValue(
        key: core_foundation::string::CFStringRef,
        value: *const c_void,
        application_id: core_foundation::string::CFStringRef,
    );
    fn CFPreferencesAppSynchronize(application_id: core_foundation::string::CFStringRef) -> bool;
}

lazy_static::lazy_static! {
    static ref PENDING_PATH: Mutex<Option<std::sync::mpsc::Sender<PathBuf>>> = Mutex::new(None);
    static ref PENDING_QUIT: Mutex<bool> = Mutex::new(false);
    static ref PENDING_SHOW_UI: Mutex<bool> = Mutex::new(false);
}

struct DarwinNotification {
    name: CFString,
    center: CFNotificationCenterRef,
}

impl DarwinNotification {
    fn new(name: &str) -> Self {
        Self {
            name: CFString::new(name),
            center: unsafe { CFNotificationCenterGetDarwinNotifyCenter() },
        }
    }

    fn add_observer(&self, callback: extern "C" fn(
        CFNotificationCenterRef,
        *mut c_void,
        core_foundation::string::CFStringRef,
        *const c_void,
        *const c_void,
    )) {
        unsafe {
            CFNotificationCenterAddObserver(
                self.center,
                std::ptr::null_mut(),
                callback,
                self.name.as_concrete_TypeRef(),
                std::ptr::null(),
                1,
            );
        }
    }
}

fn read_shared_defaults(key: &str) -> Option<String> {
    let suite_name = CFString::new(APP_GROUP_ID);
    let key_cf = CFString::new(key);

    unsafe {
        let value = CFPreferencesCopyAppValue(
            key_cf.as_concrete_TypeRef(),
            suite_name.as_concrete_TypeRef(),
        );

        if value.is_null() {
            return None;
        }

        let cf_str: &CFString = &CFString::from_void(value as *mut c_void);
        let result = cf_str.to_string();
        CFRelease(value as *mut c_void);
        Some(result)
    }
}

fn clear_shared_default(key: &str) {
    let suite_name = CFString::new(APP_GROUP_ID);
    let key_cf = CFString::new(key);

    unsafe {
        CFPreferencesSetAppValue(
            key_cf.as_concrete_TypeRef(),
            std::ptr::null(),
            suite_name.as_concrete_TypeRef(),
        );
        CFPreferencesAppSynchronize(suite_name.as_concrete_TypeRef());
    }
}

extern "C" fn on_darwin_notification(
    _center: CFNotificationCenterRef,
    _observer: *mut c_void,
    _name: core_foundation::string::CFStringRef,
    _object: *const c_void,
    _user_info: *const c_void,
) {
    if read_shared_defaults(QUIT_KEY) == Some("true".to_string()) {
        clear_shared_default(QUIT_KEY);
        *PENDING_QUIT.lock().unwrap() = true;
        return;
    }

    if read_shared_defaults(SHOW_UI_KEY) == Some("true".to_string()) {
        clear_shared_default(SHOW_UI_KEY);
        *PENDING_SHOW_UI.lock().unwrap() = true;
        return;
    }

    if let Some(path) = read_shared_defaults(PATH_KEY) {
        clear_shared_default(PATH_KEY);
        let path_buf = PathBuf::from(&path);
        if let Some(ref tx) = *PENDING_PATH.lock().unwrap() {
            let _ = tx.send(path_buf);
        }
    }
}

/// Reads and clears an "Open Shell Here" request written by the FinderSync extension
/// right before it launched us. Returns None when there is no request or it is older
/// than `max_age_secs`, so a stale request can never hijack a direct launch.
pub fn consume_pending_requested_path(max_age_secs: u64) -> Option<PathBuf> {
    let path = read_shared_defaults(PATH_KEY)?;
    let timestamp: f64 = read_shared_defaults(REQUESTED_AT_KEY)?.parse().ok()?;
    clear_shared_default(PATH_KEY);
    clear_shared_default(REQUESTED_AT_KEY);

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs_f64();
    if now - timestamp > max_age_secs as f64 || path.is_empty() {
        return None;
    }
    Some(PathBuf::from(path))
}

pub fn listen_for_finder_requests(app_handle: AppHandle) {
    let (tx, rx) = std::sync::mpsc::channel::<PathBuf>();
    *PENDING_PATH.lock().unwrap() = Some(tx);

    let notification = DarwinNotification::new(NOTIFICATION_NAME);
    notification.add_observer(on_darwin_notification);

    let cf_run_loop_mode = CFString::new("kCFRunLoopDefaultMode");
    loop {
        unsafe {
            core_foundation::runloop::CFRunLoopRunInMode(
                cf_run_loop_mode.as_concrete_TypeRef(),
                0.5,
                0,
            );
        }

        if *PENDING_QUIT.lock().unwrap() {
            app_handle.exit(0);
            return;
        }

        if *PENDING_SHOW_UI.lock().unwrap() {
            *PENDING_SHOW_UI.lock().unwrap() = false;
            if let Some(window) = app_handle.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }

        while let Ok(path) = rx.try_recv() {
            let s = crate::terminal::get_cached_settings(&app_handle);
            crate::terminal::open_terminal_at(&path, &s, &app_handle);
        }
    }
}
