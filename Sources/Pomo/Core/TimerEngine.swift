import Foundation
import Observation

enum TimerMode: String, CaseIterable {
    case pomodoro = "Pomodoro"
    case stopwatch = "Cronômetro"
}

enum TimerPhase {
    case idle
    case focus
    case shortBreak
    case longBreak
    case stopwatchRunning
}

@Observable
@MainActor
final class TimerEngine {

    // MARK: - Published state
    private(set) var phase: TimerPhase = .idle
    private(set) var mode: TimerMode = .pomodoro
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var remainingSeconds = 60 * 60
    private(set) var elapsedSeconds = 0
    private(set) var cyclesCompleted = 0
    private(set) var isAlarmActive = false

    // MARK: - Settings (kept in sync from SettingsView)
    var focusDuration = 60 * 60 {
        didSet { if !isRunning && (phase == .idle || phase == .focus) { remainingSeconds = focusDuration } }
    }
    var shortBreakDuration = 10 * 60
    var longBreakDuration = 20 * 60
    var cyclesBeforeLongBreak = 4
    var soundEnabled = true
    var notificationsEnabled = true

    // MARK: - Session callback
    var onSessionComplete: ((SessionData) -> Void)?

    func applyFocusDuration() {
        guard !isRunning && (phase == .idle || phase == .focus) else { return }
        remainingSeconds = focusDuration
    }

    // MARK: - Private
    private var timer: Timer?
    private var sessionStartDate: Date?
    private(set) var effectiveElapsed = 0

    struct SessionData {
        let startedAt: Date
        let endedAt: Date
        let kind: SessionKind
        let plannedDuration: Int
        let actualDuration: Int
    }

    // MARK: - Public control

    func dismissAlarm() {
        NotificationManager.shared.stopAlarm()
        isAlarmActive = false
    }

    func start() {
        dismissAlarm()
        if isPaused {
            isPaused = false
            startTicking()
            return
        }

        sessionStartDate = Date()
        effectiveElapsed = 0

        if mode == .stopwatch {
            phase = .stopwatchRunning
            elapsedSeconds = 0
            isRunning = true
            startTicking()
        } else {
            if phase == .idle || phase == .stopwatchRunning {
                phase = .focus
                remainingSeconds = focusDuration
            }
            isRunning = true
            startTicking()
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        stopTicking()
    }

    func reset() {
        dismissAlarm()
        stopTicking()
        isRunning = false
        isPaused = false
        phase = .idle
        remainingSeconds = focusDuration
        elapsedSeconds = 0
        effectiveElapsed = 0
        sessionStartDate = nil
    }

    func skip() {
        dismissAlarm()
        stopTicking()
        isRunning = false
        isPaused = false
        effectiveElapsed = 0
        sessionStartDate = nil
        advancePhase(completed: false)
    }

    func stopStopwatch() {
        guard phase == .stopwatchRunning else { return }
        stopTicking()
        isRunning = false
        if elapsedSeconds > 0, let start = sessionStartDate {
            let data = SessionData(startedAt: start, endedAt: Date(),
                                   kind: .stopwatch, plannedDuration: 0,
                                   actualDuration: effectiveElapsed)
            onSessionComplete?(data)
            fireNotification(for: .stopwatchRunning)
        }
        sessionStartDate = nil
        effectiveElapsed = 0
        phase = .idle
        elapsedSeconds = 0
    }

    func switchMode(to newMode: TimerMode) {
        guard !isRunning else { return }
        mode = newMode
        phase = .idle
        remainingSeconds = newMode == .pomodoro ? focusDuration : 0
        elapsedSeconds = 0
    }

    // MARK: - Private helpers

    private func startTicking() {
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        effectiveElapsed += 1

        if phase == .stopwatchRunning {
            elapsedSeconds += 1
        } else {
            if remainingSeconds > 0 { remainingSeconds -= 1 }
            elapsedSeconds += 1
            if remainingSeconds <= 0 {
                completeCurrentPhase()
            }
        }
    }

    private func completeCurrentPhase() {
        stopTicking()
        isRunning = false

        if phase == .focus, let start = sessionStartDate {
            let data = SessionData(startedAt: start, endedAt: Date(),
                                   kind: .focusPomodoro, plannedDuration: focusDuration,
                                   actualDuration: effectiveElapsed)
            onSessionComplete?(data)
            cyclesCompleted += 1
            fireNotification(for: .focus)
        } else if phase == .shortBreak || phase == .longBreak {
            fireNotification(for: phase)
        }

        sessionStartDate = nil
        effectiveElapsed = 0
        advancePhase(completed: true)
    }

    private func advancePhase(completed: Bool) {
        switch phase {
        case .focus:
            if completed && cyclesCompleted % cyclesBeforeLongBreak == 0 {
                phase = .longBreak
                remainingSeconds = longBreakDuration
            } else if completed {
                phase = .shortBreak
                remainingSeconds = shortBreakDuration
            } else {
                phase = .idle
                remainingSeconds = focusDuration
            }
        case .shortBreak, .longBreak:
            phase = .focus
            remainingSeconds = focusDuration
        default:
            phase = .idle
            remainingSeconds = focusDuration
        }
    }

    private func fireNotification(for completedPhase: TimerPhase) {
        if soundEnabled {
            NotificationManager.shared.startAlarm()
            isAlarmActive = true
        }
        guard notificationsEnabled else { return }
        switch completedPhase {
        case .focus:
            NotificationManager.shared.notify(
                title: "Sessão de foco concluída!",
                body: cyclesCompleted % cyclesBeforeLongBreak == 0
                    ? "Hora do descanso longo. Você merece."
                    : "Hora de um descanso curto."
            )
        case .shortBreak, .longBreak:
            NotificationManager.shared.notify(
                title: "Descanso encerrado",
                body: "Pronto para focar novamente?"
            )
        case .stopwatchRunning:
            NotificationManager.shared.notify(
                title: "Cronômetro parado",
                body: formatSeconds(elapsedSeconds) + " de foco registrados."
            )
        default:
            break
        }
    }

    // MARK: - Helpers for UI

    var progressFraction: Double {
        switch phase {
        case .focus:
            guard focusDuration > 0 else { return 0 }
            return Double(focusDuration - remainingSeconds) / Double(focusDuration)
        case .shortBreak:
            guard shortBreakDuration > 0 else { return 0 }
            return Double(shortBreakDuration - remainingSeconds) / Double(shortBreakDuration)
        case .longBreak:
            guard longBreakDuration > 0 else { return 0 }
            return Double(longBreakDuration - remainingSeconds) / Double(longBreakDuration)
        default:
            return 0
        }
    }

    var phaseLabel: String {
        switch phase {
        case .idle: return mode == .stopwatch ? "Pronto" : "Pronto"
        case .focus: return "FOCO"
        case .shortBreak: return "DESCANSO"
        case .longBreak: return "DESCANSO LONGO"
        case .stopwatchRunning: return "CRONÔMETRO"
        }
    }
}

func formatSeconds(_ seconds: Int) -> String {
    let h = seconds / 3600
    let m = (seconds % 3600) / 60
    let s = seconds % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    } else {
        return String(format: "%02d:%02d", m, s)
    }
}
