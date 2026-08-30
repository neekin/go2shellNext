import Foundation
import AppKit

/// Bridge between the FinderSync extension and the main app.
///
/// The sandboxed extension hands over requests as small JSON files (it writes
/// the app group container and, as a fallback, its own container tmp — this
/// side reads both) and then either posts a Darwin notification (app already
/// running) or launches us with `--open-dir=<path>` / `--settings`.
enum FinderBridge {
    static let appGroup = "TEAMID.com.go2shellnext.group"
    static let notificationName = "com.go2shellnext.app.openShell" as CFString

    private static let library = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)

    private static var requestFileURLs: [URL] {
        [
            library
                .appendingPathComponent("Group Containers/TEAMID.com.go2shellnext.group", isDirectory: true)
                .appendingPathComponent("request.json"),
            library
                .appendingPathComponent("Containers/com.go2shellnext.app.FinderSyncExt/Data/tmp", isDirectory: true)
                .appendingPathComponent("request.json"),
        ]
    }

    struct Request {
        let action: String
        let path: String?
    }

    static func startListening() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            nil,
            { _, _, _, _, _ in
                // Darwin notifications arrive on the run loop that registered
                // the observer; do the work on the main queue.
                DispatchQueue.main.async {
                    AppDelegate.current?.handleFinderNotification()
                }
            },
            notificationName,
            nil,
            .deliverImmediately
        )
    }

    /// Reads and clears the extension's pending request. Returns nil when there
    /// is none or it is older than `maxAge` seconds, so a stale request can
    /// never hijack a direct launch.
    static func consumePendingRequest(maxAge: TimeInterval) -> Request? {
        for url in requestFileURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let action = object["action"] as? String,
                  let timestamp = object["requestedAt"] as? TimeInterval
            else { continue }

            try? FileManager.default.removeItem(at: url)
            guard Date().timeIntervalSince1970 - timestamp <= maxAge else { continue }
            return Request(action: action, path: object["path"] as? String)
        }
        return nil
    }
}

extension AppDelegate {
    func handleFinderNotification() {
        guard let request = FinderBridge.consumePendingRequest(maxAge: 10) else { return }

        switch request.action {
        case "quit":
            NSApp.terminate(nil)
        case "settings":
            showSettings()
        case "open":
            guard let path = request.path else { return }
            DispatchQueue.global().async {
                TerminalOpener.openTerminal(at: path)
            }
        default:
            break
        }
    }
}
