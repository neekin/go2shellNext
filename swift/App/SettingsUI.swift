import SwiftUI
import AppKit

struct SettingsView: View {
    @State private var terminal = SettingsStore.load().terminal
    @State private var customCommand = SettingsStore.load().customCommand
    @State private var openInTab = SettingsStore.load().openInTab
    @State private var statusText = ""
    @State private var statusWorkItem: DispatchWorkItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 2) {
                Text("Go2ShellNext")
                    .font(.system(size: 22, weight: .bold))
                Text("Open terminal from Finder")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            setupGuide

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Default Terminal", selection: $terminal) {
                        ForEach(SettingsStore.terminals, id: \.value) { t in
                            Text(t.label).tag(t.value)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Command (optional)")
                        TextField("e.g. vim .", text: $customCommand)
                            .textFieldStyle(.roundedBorder)
                        Text("Executed after cd-ing to the target directory")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Open in new tab (if supported)", isOn: $openInTab)

                    HStack {
                        Button("Save Settings") { save() }
                            .buttonStyle(.borderedProminent)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(label: Text("Usage")) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Click the Go2ShellNext icon in Finder toolbar → terminal opens at front Finder folder", systemImage: "terminal")
                    Label("Hold ⌥ and launch Go2ShellNext.app → shows this settings window", systemImage: "option")
                    Label("Right-click in Finder → Open Shell Here / Settings… / Quit", systemImage: "contextualmenu.and.cursorarrow")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var setupGuide: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.accentColor.opacity(0.15))
                Text("⌘")
                    .font(.system(size: 20, weight: .medium))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text("Add to Finder Toolbar")
                    .font(.headline)
                Text("Hold ⌘ and drag Go2ShellNext.app onto the Finder toolbar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Reveal Go2ShellNext.app") { revealApp() }
                    .font(.caption)
                    .buttonStyle(.link)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5))
        )
    }

    private func save() {
        var settings = AppSettings()
        settings.terminal = terminal
        settings.customCommand = customCommand
        settings.openInTab = openInTab
        SettingsStore.save(settings)

        statusText = "Settings saved!"
        statusWorkItem?.cancel()
        let clear = DispatchWorkItem { statusText = "" }
        statusWorkItem = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: clear)
    }

    private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let hostingView = NSHostingView(rootView: SettingsView())
        var size = hostingView.fittingSize
        if size.width < 300 || size.height < 200 {
            size = NSSize(width: 440, height: 485)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Go2ShellNext Settings"
        window.contentView = hostingView
        window.center()
        // The controller owns the window across show/close cycles.
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }
}
