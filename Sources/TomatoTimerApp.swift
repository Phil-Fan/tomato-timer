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

        model.updates.startAutomaticChecks()
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
            HStack(spacing: 4) {
                Image(systemName: appDelegate.model.engine.menuBarSymbol)

                if !appDelegate.model.engine.menuBarText.isEmpty {
                    Text(appDelegate.model.engine.menuBarText)
                        .monospacedDigit()
                }

                if appDelegate.model.updates.pendingRelease != nil {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.blue)
                        .help("有新版本可以更新")
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: appDelegate.model)
        }
    }
}
