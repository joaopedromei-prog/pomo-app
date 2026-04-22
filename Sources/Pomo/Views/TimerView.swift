import SwiftUI

// MARK: - Digit card (static, no animation)

private struct DigitCard: View {
    let value: Int
    let digitCount: Int
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let fontSize: CGFloat

    private var displayText: String {
        String(format: "%0\(digitCount)d", value)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.1))

            Text(displayText)
                .font(.system(size: fontSize, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(white: 0.73))
                .monospacedDigit()
        }
        .frame(width: cardWidth, height: cardHeight)
    }
}

// MARK: - Clock display — always MM:SS, no hours, no animation

private struct ClockDisplay: View {
    let totalSeconds: Int
    let containerWidth: CGFloat
    let sessionMaxSeconds: Int

    private var minuteValue: Int { totalSeconds / 60 }
    private var secondValue: Int { totalSeconds % 60 }

    private var minuteDigits: Int {
        let maxMin = sessionMaxSeconds > 0 ? sessionMaxSeconds / 60 : minuteValue
        return maxMin >= 100 ? 3 : 2
    }

    private var sizing: (cardWidth: CGFloat, cardHeight: CGFloat, fontSize: CGFloat) {
        let spacing: CGFloat = 12
        let colonWidth: CGFloat = 28
        let gaps = spacing * 2
        let margin: CGFloat = 40
        let totalDigits = CGFloat(minuteDigits + 2)
        let digitCellWidth = max(32, (containerWidth - gaps - colonWidth - margin) / totalDigits)
        let cardW = digitCellWidth * CGFloat(minuteDigits)
        let cardH = digitCellWidth * (180.0 / 116.0)
        let fs = cardH * (130.0 / 180.0)
        return (cardW, cardH, fs)
    }

    var body: some View {
        let s = sizing
        let secCardW = s.cardWidth / CGFloat(minuteDigits) * 2
        HStack(spacing: 12) {
            DigitCard(value: minuteValue, digitCount: minuteDigits,
                      cardWidth: s.cardWidth, cardHeight: s.cardHeight, fontSize: s.fontSize)
            colonView(size: s.fontSize)
            DigitCard(value: secondValue, digitCount: 2,
                      cardWidth: secCardW, cardHeight: s.cardHeight, fontSize: s.fontSize)
        }
    }

    private func colonView(size: CGFloat) -> some View {
        Text(":")
            .font(.system(size: max(18, size * 0.32), weight: .thin))
            .foregroundStyle(Color(white: 0.28))
            .offset(y: -4)
    }
}

// MARK: - Main Timer View

struct TimerView: View {
    @Environment(TimerEngine.self) private var engine
    @Environment(PersistenceStore.self) private var store
    @State private var clockWidth: CGFloat = 600
    @State private var slideFromTrailing = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("", selection: Binding(
                    get: { engine.mode },
                    set: { newMode in
                        let modes = TimerMode.allCases
                        if let ni = modes.firstIndex(of: newMode),
                           let ci = modes.firstIndex(of: engine.mode) {
                            slideFromTrailing = ni > ci
                        }
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                            engine.switchMode(to: newMode)
                        }
                    }
                )) {
                    ForEach(TimerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .colorScheme(.dark)
                .padding(.horizontal, 56)
                .padding(.top, 28)

                Spacer()

                Group {
                    Text(engine.phaseLabel)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Color(white: 0.35))
                        .padding(.bottom, 18)

                    ClockDisplay(
                        totalSeconds: displaySeconds,
                        containerWidth: clockWidth,
                        sessionMaxSeconds: engine.mode == .pomodoro ? engine.focusDuration : 0
                    )

                    HStack(spacing: 8) {
                        ForEach(0..<engine.cyclesBeforeLongBreak, id: \.self) { i in
                            Circle()
                                .fill(i < (engine.cyclesCompleted % engine.cyclesBeforeLongBreak)
                                      ? Color(white: 0.65) : Color(white: 0.22))
                                .frame(width: 7, height: 7)
                        }
                    }
                    .padding(.top, 20)
                    .opacity(engine.mode == .pomodoro ? 1 : 0)

                    Text(todayFocusLabel.isEmpty ? " " : todayFocusLabel)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color(white: 0.3))
                        .padding(.top, 12)
                        .opacity(todayFocusLabel.isEmpty ? 0 : 1)
                }
                .id(engine.mode)
                .transition(.asymmetric(
                    insertion: .move(edge: slideFromTrailing ? .trailing : .leading).combined(with: .opacity),
                    removal:   .move(edge: slideFromTrailing ? .leading  : .trailing).combined(with: .opacity)
                ))

                Spacer()

                HStack(spacing: 36) {
                    if engine.isRunning {
                        labeledButton(icon: "xmark", label: "encerrar") {
                            engine.reset()
                        }
                        .keyboardShortcut(.escape, modifiers: [])
                        if engine.mode == .pomodoro {
                            labeledButton(icon: "forward.fill", label: "pular") {
                                engine.skip()
                            }
                            .keyboardShortcut(.rightArrow, modifiers: [.command])
                        } else {
                            labeledButton(icon: "stop.fill", label: "parar") {
                                engine.stopStopwatch()
                            }
                        }
                    } else {
                        labeledButton(icon: "play.fill", label: "iniciar", primary: true) {
                            engine.start()
                        }
                        .keyboardShortcut(.space, modifiers: [])
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: engine.isRunning)
                .padding(.bottom, 36)
            }
        }
        .overlay {
            if engine.isAlarmActive {
                ZStack {
                    Color.black.opacity(0.75).ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "alarm.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color(white: 0.85))
                            .symbolEffect(.pulse)
                        Text("SESSÃO CONCLUÍDA")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(Color(white: 0.55))
                        Button {
                            engine.dismissAlarm()
                        } label: {
                            Text("Parar Alarme")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 28)
                                .padding(.vertical, 12)
                                .background(Color(white: 0.88))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.return, modifiers: [])
                    }
                }
                .transition(.opacity)
                .animation(.easeIn(duration: 0.2), value: engine.isAlarmActive)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { clockWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, w in clockWidth = w }
            }
        )
        .onAppear { setupCallback() }
    }

    private var displaySeconds: Int {
        engine.mode == .stopwatch ? engine.elapsedSeconds : engine.remainingSeconds
    }

    private var todayFocusSeconds: Int {
        let cal = Calendar.current
        let past = store.sessions
            .filter { cal.isDateInToday($0.endedAt) }
            .reduce(0) { $0 + $1.actualDuration }
        let current = (engine.phase == .focus && engine.isRunning) ? engine.elapsedSeconds : 0
        return past + current
    }

    private var todayFocusLabel: String {
        let t = todayFocusSeconds
        guard t > 0 else { return "" }
        let h = t / 3600
        let m = (t % 3600) / 60
        if h > 0 { return "\(h)h \(m)min hoje" }
        return "\(m)min hoje"
    }

    private func setupCallback() {
        engine.onSessionComplete = { [weak store] data in
            let session = Session(
                startedAt: data.startedAt, endedAt: data.endedAt,
                kind: data.kind, plannedDuration: data.plannedDuration,
                actualDuration: data.actualDuration
            )
            store?.insert(session: session)
        }
    }

    @ViewBuilder
    private func labeledButton(icon: String, label: String, primary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: primary ? 22 : 16, weight: .regular))
                    .frame(width: primary ? 60 : 44, height: primary ? 60 : 44)
                    .foregroundStyle(primary ? Color.black : Color(white: 0.65))
                    .background(
                        Circle()
                            .fill(primary ? Color(white: 0.85) : Color.clear)
                            .overlay(
                                Circle().stroke(Color(white: 0.25), lineWidth: primary ? 0 : 1)
                            )
                    )

                Text(label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .buttonStyle(.plain)
    }
}
