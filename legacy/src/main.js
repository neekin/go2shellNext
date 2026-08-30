import { invoke } from "@tauri-apps/api/core";

async function loadSettings() {
    try {
        const settings = await invoke('get_settings');
        document.getElementById('terminal-select').value = settings.terminal || 'Terminal';
        document.getElementById('custom-command').value = settings.custom_command || '';
        document.getElementById('open-in-tab').checked = settings.open_in_tab || false;
    } catch (e) {
        console.error('Failed to load settings:', e);
    }
}

async function saveSettings() {
    const settings = {
        terminal: document.getElementById('terminal-select').value,
        custom_command: document.getElementById('custom-command').value,
        open_in_tab: document.getElementById('open-in-tab').checked,
    };

    try {
        await invoke('save_settings', { settings });
        const status = document.getElementById('save-status');
        status.textContent = 'Settings saved!';
        setTimeout(() => { status.textContent = ''; }, 2000);
    } catch (e) {
        console.error('Failed to save settings:', e);
        document.getElementById('save-status').textContent = 'Failed to save settings';
    }
}

async function openAppFolder() {
    try {
        await invoke('reveal_app');
    } catch (e) {
        console.error('Failed to reveal app:', e);
    }
}

document.getElementById('save-btn').addEventListener('click', saveSettings);
document.getElementById('open-app-folder').addEventListener('click', openAppFolder);

loadSettings();
