import AppKit
import SwiftUI
import ThirdTimerCore
import UserNotifications

@main
struct ThirdTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            Text(model.snapshot.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var hotKey: HotKey?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        hotKey = HotKey {
            Task { @MainActor in AppModel.shared.toggle() }
        }

        if AppModel.canNotify {
            UNUserNotificationCenter.current().delegate = self
        }
        Task { @MainActor in AppModel.shared.requestNotificationPermission() }

        // `--window` also shows the panel in an ordinary window, for screenshots and checks.
        if CommandLine.arguments.contains("--window") {
            Task { @MainActor in self.showPanelWindow() }
        }
    }

    // Show the end-of-break banner even while the panel is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    @MainActor
    private func showPanelWindow() {
        let host = NSHostingController(rootView: PanelView().environmentObject(AppModel.shared))
        let window = NSWindow(contentViewController: host)
        window.title = "Third Timer"
        window.styleMask = [.titled, .closable]
        window.level = .floating
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
