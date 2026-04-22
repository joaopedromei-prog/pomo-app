import SwiftUI

struct MenuBarView: View {
    @Environment(TimerEngine.self) private var engine

    var body: some View {
        Group {
            Text(statusLine)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            Button("Abrir Pomo") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows {
                    if window.canBecomeMain { window.makeKeyAndOrderFront(nil); break }
                }
            }

            Divider()

            Button("Sair") { NSApp.terminate(nil) }
        }
    }

    private var statusLine: String {
        switch engine.phase {
        case .idle:
            return "Pronto"
        case .focus:
            return "Foco — \(formatSeconds(engine.remainingSeconds))"
        case .shortBreak:
            return "Descanso — \(formatSeconds(engine.remainingSeconds))"
        case .longBreak:
            return "Descanso longo — \(formatSeconds(engine.remainingSeconds))"
        case .stopwatchRunning:
            return "⏱ \(formatSeconds(engine.elapsedSeconds))"
        }
    }
}
