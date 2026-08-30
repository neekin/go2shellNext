import Foundation

/// Opens the configured terminal at a directory, ported from the original
/// AppleScript-based implementation.
enum TerminalOpener {
    static func openTerminal(at path: String) {
        let settings = SettingsStore.load()
        let escaped = shellEscape(path)

        switch settings.terminal {
        case "Terminal":
            openTerminalApp(escapedPath: escaped, customCommand: settings.customCommand, openInTab: settings.openInTab)
        case "iTerm":
            openIterm2(path: escaped, customCommand: settings.customCommand, openInTab: settings.openInTab)
        case let name:
            openGenericTerminal(name: name, path: escaped, customCommand: settings.customCommand)
        }
    }

    /// Opens a terminal at the frontmost Finder window's folder (toolbar-button launch).
    static func openTerminalAtFinderFrontWindow() {
        let settings = SettingsStore.load()

        switch settings.terminal {
        case "Terminal":
            openTerminalAppAtFinder(customCommand: settings.customCommand, openInTab: settings.openInTab)
        case "iTerm":
            openIterm2AtFinder(customCommand: settings.customCommand, openInTab: settings.openInTab)
        case let name:
            if let finderPath = getFinderPath() {
                openGenericTerminal(name: name, path: shellEscape(finderPath), customCommand: settings.customCommand)
            }
        }
    }

    private static func getFinderPath() -> String? {
        let script = """
        tell application "Finder"
            try
                set theFolder to target of front window as alias
                return POSIX path of theFolder
            on error
                return POSIX path of (home as alias)
            end try
        end tell
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (path?.isEmpty == false) ? path : nil
        } catch {
            return nil
        }
    }

    private static func openTerminalAppAtFinder(customCommand: String, openInTab: Bool) {
        // The suffix must land INSIDE the AppleScript string literal, otherwise
        // the generated script is a syntax error.
        let cmd = normalizedCustomCommand(customCommand)
        let cmdSuffix = cmd.isEmpty ? "" : " && \(cmd)"

        let script: String
        if openInTab {
            script = """
            tell application "Finder"
            set finderPath to POSIX path of (target of front window as alias)
            end tell
            tell application "Terminal"
            activate
            if (count of windows) > 0 then
            tell application "System Events" to keystroke "t" using command down
            do script "cd " & quoted form of finderPath & "\(cmdSuffix)" in front window
            else
            do script "cd " & quoted form of finderPath & "\(cmdSuffix)"
            end if
            end tell
            """
        } else {
            script = """
            tell application "Finder"
            set finderPath to POSIX path of (target of front window as alias)
            end tell
            tell application "Terminal"
            activate
            do script "cd " & quoted form of finderPath & "\(cmdSuffix)" & ""
            end tell
            """
        }
        runOsaScript(script)
    }

    /// Users often paste leading/trailing separators like `;clear;`; normalize
    /// them away so the `cd && cmd` join stays valid shell.
    private static func normalizedCustomCommand(_ command: String) -> String {
        var cmd = command.trimmingCharacters(in: .whitespacesAndNewlines)
        while cmd.hasPrefix(";") || cmd.hasPrefix("&") {
            cmd = String(cmd.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        while cmd.hasSuffix(";") || cmd.hasSuffix("&") {
            cmd = String(cmd.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cmd
    }

    private static func openIterm2AtFinder(customCommand: String, openInTab: Bool) {
        let cmdSuffix = customCommand.isEmpty ? "" : " && \(customCommand)"

        let script: String
        if openInTab {
            script = """
            tell application "Finder"
            set finderPath to POSIX path of (target of front window as alias)
            end tell
            tell application "iTerm2"
            activate
            try
            set currentWindow to front window
            tell currentWindow
            set newTab to (create tab with default profile)
            tell current session of newTab
            write text "cd " & quoted form of finderPath & "\(cmdSuffix)"
            end tell
            end tell
            on error
            set currentWindow to (create window with default profile)
            tell current session of currentWindow
            write text "cd " & quoted form of finderPath & "\(cmdSuffix)"
            end tell
            end try
            end tell
            """
        } else {
            script = """
            tell application "Finder"
            set finderPath to POSIX path of (target of front window as alias)
            end tell
            tell application "iTerm2"
            activate
            try
            tell front window
            set newSession to (create window with default profile)
            tell current session of newSession
            write text "cd " & quoted form of finderPath & "\(cmdSuffix)"
            end tell
            end tell
            on error
            set currentWindow to (create window with default profile)
            tell current session of currentWindow
            write text "cd " & quoted form of finderPath & "\(cmdSuffix)"
            end tell
            end try
            end tell
            """
        }
        runOsaScript(script)
    }

    static func shellEscape(_ path: String) -> String {
        let special: Set<Character> = [
            " ", "&", "|", ";", "<", ">", "(", ")", "$", "`", "\\", "\"", "'",
            "!", "*", "?", "[", "]", "{", "}", "^", "#", "~",
        ]
        guard path.contains(where: { special.contains($0) }) else { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runOsaScript(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            logDebug("osascript exit=\(process.terminationStatus) stderr=\(stderr.isEmpty ? "-" : stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        } catch {
            logDebug("osascript spawn failed: \(error.localizedDescription)")
        }
    }

    private static func logDebug(_ message: String) {
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

    private static func cdCommand(_ escapedPath: String, _ customCommand: String) -> String {
        let cmd = normalizedCustomCommand(customCommand)
        if cmd.isEmpty {
            return "cd \(escapedPath)"
        }
        return "cd \(escapedPath) && \(cmd)"
    }

    private static func openTerminalApp(escapedPath: String, customCommand: String, openInTab: Bool) {
        let fullCmd = cdCommand(escapedPath, customCommand)

        let script: String
        if openInTab {
            script = """
            tell application "Terminal"
            activate
            if (count of windows) > 0 then
            tell application "System Events" to keystroke "t" using command down
            do script "\(fullCmd)" in front window
            else
            do script "\(fullCmd)"
            end if
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
            activate
            do script "\(fullCmd)"
            end tell
            """
        }
        runOsaScript(script)
    }

    private static func openIterm2(path: String, customCommand: String, openInTab: Bool) {
        let fullCmd = cdCommand(path, customCommand)

        let script: String
        if openInTab {
            script = """
            tell application "iTerm2"
            activate
            try
            set currentWindow to front window
            tell currentWindow
            set newSession to (create tab with default profile)
            tell current session of newSession
            write text "\(fullCmd)"
            end tell
            end tell
            on error
            set currentWindow to (create window with default profile)
            tell current session of currentWindow
            write text "\(fullCmd)"
            end tell
            end try
            end tell
            """
        } else {
            script = """
            tell application "iTerm2"
            activate
            try
            tell front window
            set newSession to (create window with default profile)
            tell current session of newSession
            write text "\(fullCmd)"
            end tell
            end tell
            on error
            set currentWindow to (create window with default profile)
            tell current session of currentWindow
            write text "\(fullCmd)"
            end tell
            end try
            end tell
            """
        }
        runOsaScript(script)
    }

    private static func openGenericTerminal(name: String, path: String, customCommand: String) {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-a", name, "--args", "--directory", path]
        let launched: Bool
        do { try open.run(); launched = true } catch { launched = false }
        if !launched {
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallback.arguments = ["-a", name, path]
            try? fallback.run()
        }

        if !customCommand.isEmpty {
            let fullCmd = cdCommand(path, customCommand)
            runOsaScript("""
            tell application "\(name)"
            activate
            delay 0.5
            do script "\(fullCmd)" in front window
            end tell
            """)
        }
    }
}
