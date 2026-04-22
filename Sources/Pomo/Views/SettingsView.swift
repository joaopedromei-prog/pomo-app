import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @Environment(TimerEngine.self) private var engine

    @AppStorage("focusMinutes") private var focusMinutes = 60
    @AppStorage("shortBreakMinutes") private var shortBreakMinutes = 10
    @AppStorage("longBreakMinutes") private var longBreakMinutes = 20
    @AppStorage("cyclesBeforeLongBreak") private var cyclesBeforeLongBreak = 4
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    @State private var launchAtLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {

                SettingsSection(title: "Durações") {
                    DurationRow(label: "Foco", value: $focusMinutes, range: 5...120, step: 5)
                    DurationRow(label: "Descanso curto", value: $shortBreakMinutes, range: 1...30, step: 1)
                    DurationRow(label: "Descanso longo", value: $longBreakMinutes, range: 5...60, step: 5)
                    DurationRow(label: "Ciclos até descanso longo", value: $cyclesBeforeLongBreak, range: 2...8, step: 1, unit: "ciclos")
                }

                SettingsSection(title: "Notificações") {
                    Toggle("Som ao final do ciclo", isOn: $soundEnabled)
                    Toggle("Notificação do sistema", isOn: $notificationsEnabled)
                }

                SettingsSection(title: "Sistema") {
                    Toggle("Abrir ao iniciar o Mac", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, new in
                            toggleLaunchAtLogin(new)
                        }
                }

            }
            .padding(24)
        }
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            syncEngineSettings()
        }
        .onChange(of: focusMinutes)           { _, _ in syncEngineSettings() }
        .onChange(of: shortBreakMinutes)      { _, _ in syncEngineSettings() }
        .onChange(of: longBreakMinutes)       { _, _ in syncEngineSettings() }
        .onChange(of: cyclesBeforeLongBreak)  { _, _ in syncEngineSettings() }
        .onChange(of: soundEnabled)           { _, _ in syncEngineSettings() }
        .onChange(of: notificationsEnabled)   { _, _ in syncEngineSettings() }
    }

    private func syncEngineSettings() {
        engine.focusDuration = focusMinutes * 60
        engine.shortBreakDuration = shortBreakMinutes * 60
        engine.longBreakDuration = longBreakMinutes * 60
        engine.cyclesBeforeLongBreak = cyclesBeforeLongBreak
        engine.soundEnabled = soundEnabled
        engine.notificationsEnabled = notificationsEnabled
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enable
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            VStack(spacing: 14) {
                content()
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct DurationRow: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var unit = "min"

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            HStack(spacing: 8) {
                Button {
                    if value - step >= range.lowerBound { value -= step }
                } label: { Image(systemName: "minus").frame(width: 20) }
                .buttonStyle(.plain)

                Text("\(value) \(unit)")
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minWidth: 64, alignment: .center)

                Button {
                    if value + step <= range.upperBound { value += step }
                } label: { Image(systemName: "plus").frame(width: 20) }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
        }
    }
}
