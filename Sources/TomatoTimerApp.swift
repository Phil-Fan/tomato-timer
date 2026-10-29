import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    private var floatingBall: FloatingBallController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let ball = FloatingBallController(model: model)
        floatingBall = ball
        ball.setVisible(model.settings.showFloatingBall)
        ball.observeVisibility()

        if model.settings.notificationsEnabled {
            Task { _ = await NotificationScheduler.requestAuthorization() }
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        floatingBall?.collapse()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct TomatoTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: appDelegate.model)
                .frame(width: 320)
        } label: {
            Text(appDelegate.model.engine.menuBarLabel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
