import SwiftUI

@main
struct PomoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var engine = TimerEngine()
    @State private var store = PersistenceStore()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(engine)
                .environment(store)
                .onAppear {
                    NotificationManager.shared.requestPermission()
                    AggregationService.run(store: store)
                    loadSettings()
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarView()
                .environment(engine)
        } label: {
            Image(systemName: engine.isRunning && !engine.isPaused ? "timer" : "timer")
                .symbolVariant(.none)
        }
        .menuBarExtraStyle(.menu)
    }

    private func loadSettings() {
        let ud = UserDefaults.standard
        let fm = ud.integer(forKey: "focusMinutes")
        let sb = ud.integer(forKey: "shortBreakMinutes")
        let lb = ud.integer(forKey: "longBreakMinutes")
        let cy = ud.integer(forKey: "cyclesBeforeLongBreak")
        engine.focusDuration        = (fm > 0 ? fm : 60) * 60
        engine.shortBreakDuration   = (sb > 0 ? sb : 10) * 60
        engine.longBreakDuration    = (lb > 0 ? lb : 20) * 60
        engine.cyclesBeforeLongBreak = cy > 0 ? cy : 4
        engine.soundEnabled         = ud.object(forKey: "soundEnabled") == nil ? true : ud.bool(forKey: "soundEnabled")
        engine.notificationsEnabled = ud.object(forKey: "notificationsEnabled") == nil ? true : ud.bool(forKey: "notificationsEnabled")
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
