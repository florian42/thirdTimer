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
            // A system symbol and plain text, like other menu bar items. Digits keep
            // one width, so the item does not shift its neighbours every second.
            let snap = model.snapshot
            HStack(spacing: 4) {
                Image(systemName: Mood.of(snap).symbol)
                Text(snap.menuTitle).monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var hotKey: HotKey?
    private var window: NSWindow?
    private var walkthrough: Walkthrough?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar only: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        hotKey = HotKey { AppModel.shared.toggle() }

        if AppModel.canNotify {
            UNUserNotificationCenter.current().delegate = self
        }
        AppModel.shared.requestNotificationPermission()

        // `--window` also shows the panel in an ordinary window, for screenshots and checks.
        if CommandLine.arguments.contains("--window") || CommandLine.arguments.contains("--walkthrough") {
            showPanelWindow()
        }
        // `--walkthrough` plays a scripted day of use with captions, for recording.
        if CommandLine.arguments.contains("--walkthrough") {
            walkthrough = Walkthrough()
            walkthrough?.start()
        }
    }

    // Show the end-of-break banner even while the panel is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

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
