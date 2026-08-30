import AppKit
import CoreGraphics

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var current: AppDelegate?

    let settingsWindowController = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        FinderBridge.startListening()

        let args = CommandLine.arguments
        let optionDown = isOptionKeyDown()
        logDebug("launch args=\(args.dropFirst().joined(separator: " ")) optionDown=\(optionDown) reopened=false")

        if let flag = args.first(where: { $0.hasPrefix("--open-dir=") }) {
            // Launched by the FinderSync extension (host app was not running).
            let path = String(flag.dropFirst("--open-dir=".count))
            logDebug("branch=open-dir path=\(path)")
            DispatchQueue.global().async {
                TerminalOpener.openTerminal(at: path)
            }
        } else if let pending = FinderBridge.consumePendingRequest(maxAge: 10) {
            // The extension wrote a request right before launching us; honor it
            // whether or not the launch arguments arrived. Only fresh requests.
            logDebug("branch=pending action=\(pending.action) path=\(pending.path ?? "-")")
            switch pending.action {
            case "open":
                if let path = pending.path {
                    DispatchQueue.global().async {
                        TerminalOpener.openTerminal(at: path)
                    }
                } else {
                    showSettings()
                }
            default:
                showSettings()
            }
        } else if args.contains("--settings") || optionDown {
            // Hold ⌥ while launching to get the settings window.
            logDebug("branch=settings (flag=\(args.contains("--settings")))")
            showSettings()
        } else {
            // Toolbar-button click or plain double-click: open a terminal at
            // the frontmost Finder window's folder.
            logDebug("branch=finder-front-window")
            DispatchQueue.global().async {
                TerminalOpener.openTerminalAtFinderFrontWindow()
            }
        }
    }

    /// Re-opening the app while it is already running follows the same rules as
    /// a fresh launch: pending extension requests win, ⌥ means settings, and a
    /// plain re-open opens a terminal at the front Finder folder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logDebug("reopen optionDown=\(isOptionKeyDown())")
        if let pending = FinderBridge.consumePendingRequest(maxAge: 10) {
            logDebug("reopen pending action=\(pending.action) path=\(pending.path ?? "-")")
            switch pending.action {
            case "open":
                if let path = pending.path {
                    DispatchQueue.global().async {
                        TerminalOpener.openTerminal(at: path)
                    }
                    return true
                }
            case "quit":
                NSApp.terminate(nil)
                return true
            default:
                showSettings()
                return true
            }
        }

        if isOptionKeyDown() {
            logDebug("reopen branch=settings")
            showSettings()
        } else {
            logDebug("reopen branch=finder-front-window")
            DispatchQueue.global().async {
                TerminalOpener.openTerminalAtFinderFrontWindow()
            }
        }
        return true
    }

    private func logDebug(_ message: String) {
        let url = SettingsStore.fileURL.deletingLastPathComponent()
            .appendingPathComponent("launch_debug.log")
        let line = "\(Date().timeIntervalSince1970): \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController.showWindow(nil)
    }

    /// ⌥ held at launch time means "open settings". Checked via both the event
    /// system and the low-level session state so a quickly released key is
    /// still caught during the brief launch window.
    private func isOptionKeyDown() -> Bool {
        if NSEvent.modifierFlags.contains(.option) {
            return true
        }
        return CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(58)) // kVK_Option
    }
}
