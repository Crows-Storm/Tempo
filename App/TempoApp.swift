import SwiftUI

@main
struct TempoApp: App {
    @NSApplicationDelegateAdaptor(TempoDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        AppSettings.load().language.apply()
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(model)
                .modelContainer(model.container)
                .tempoChrome(model)
        }
        .defaultSize(width: 1080, height: 720)
        .commands { TempoCommands(model: model) }
    }
}

final class TempoDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.load().appearance.apply()
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestBundlePath"] != nil || environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "app.tempo.macos"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
