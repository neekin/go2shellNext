import FinderSync
import AppKit

@objc(FinderSyncExt)
class FinderSyncExt: FIFinderSync {

    private let appGroupIdentifier = "TEAMID.com.go2shellnext.group"
    private let notificationName = "com.go2shellnext.app.openShell"
    private let hostBundleIdentifier = "com.go2shellnext.app"

    override init() {
        super.init()
        let home = FileManager.default.homeDirectoryForCurrentUser
        FIFinderSyncController.default().directoryURLs = Set([home])
    }

    override var toolbarItemName: String {
        return "Go2ShellNext"
    }

    override var toolbarItemImage: NSImage {
        if let img = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Go2ShellNext") {
            let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            return img.withSymbolConfiguration(config) ?? img
        }
        return NSImage(named: NSImage.actionTemplateName)!
    }

    override var toolbarItemToolTip: String {
        return "Open terminal at the current folder"
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Shell Here",
            action: #selector(didClickOpenShell),
            keyEquivalent: ""
        )
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(didClickSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Go2ShellNext",
            action: #selector(didClickQuit),
            keyEquivalent: ""
        )
        quitItem.target = self
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Host app helpers

    private func hostAppURL() -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: hostBundleIdentifier)
    }

    private func hostIsRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == hostBundleIdentifier
        }
    }

    /// The extension cannot post a Darwin notification to a process that is not
    /// running, so launch the host app and hand it the request via launch arguments.
    private func launchHostApp(arguments: [String]) {
        guard let url = hostAppURL() else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = arguments
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    // MARK: - Request passing

    /// macOS requires FinderSync extensions to be sandboxed, and our app group
    /// uses a placeholder team id, so UserDefaults(suiteName:) sharing is NOT
    /// reliable. Pass requests as plain JSON files instead: try the app group
    /// container first, then fall back to the extension's own container tmp —
    /// the unsandboxed host app reads both locations.
    private var requestFileURLs: [URL] {
        var urls: [URL] = []
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(group.appendingPathComponent("request.json"))
        }
        urls.append(FileManager.default.temporaryDirectory.appendingPathComponent("request.json"))
        return urls
    }

    private func writeRequest(action: String, path: String?) {
        var request: [String: Any] = [
            "action": action,
            "requestedAt": Date().timeIntervalSince1970,
        ]
        if let path = path {
            request["path"] = path
        }
        guard let data = try? JSONSerialization.data(withJSONObject: request) else { return }
        for url in requestFileURLs {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func postOpenShellNotification() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(notificationName as CFString),
            nil, nil, true
        )
    }

    // MARK: - Actions

    @objc func didClickOpenShell() {
        let controller = FIFinderSyncController.default()

        var targetURL: URL?

        if let selectedURLs = controller.selectedItemURLs(), !selectedURLs.isEmpty {
            let firstSelected = selectedURLs[0]
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: firstSelected.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    targetURL = firstSelected
                } else {
                    targetURL = firstSelected.deletingLastPathComponent()
                }
            }
        }

        if targetURL == nil {
            targetURL = controller.targetedURL()
        }

        if targetURL == nil {
            targetURL = FileManager.default.homeDirectoryForCurrentUser
        }

        guard let url = targetURL else { return }

        writeRequest(action: "open", path: url.path)

        if hostIsRunning() {
            postOpenShellNotification()
        } else {
            launchHostApp(arguments: ["--open-dir=\(url.path)"])
        }
    }

    @objc func didClickSettings() {
        writeRequest(action: "settings", path: nil)

        if hostIsRunning() {
            postOpenShellNotification()
        } else {
            launchHostApp(arguments: ["--settings"])
        }
    }

    @objc func didClickQuit() {
        guard hostIsRunning() else { return }
        writeRequest(action: "quit", path: nil)
        postOpenShellNotification()
    }
}
