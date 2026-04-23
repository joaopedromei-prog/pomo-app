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

                SettingsSection(title: "Teclas de Atalho — Tarefas") {
                    ShortcutRow(label: "Navegar entre tarefas", keys: ["↑ / ↓"])
                    ShortcutRow(label: "Concluir tarefa", keys: ["Espaço"])
                    ShortcutRow(label: "Apagar tarefa", keys: ["⌘", "⌫"])
                    ShortcutRow(label: "Nova subtarefa", keys: ["⌘", "↩"])
                    ShortcutRow(label: "Indentar", keys: ["⌘", "]"])
                    ShortcutRow(label: "Recuar", keys: ["⌘", "["])
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
        engine.applyFocusDuration()
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
            VStack(alignment: .leading, spacing: 14) {
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

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .multilineTextAlignment(.center)
                        .frame(width: 42)
                        .focused($isFocused)
                        .onSubmit { commit() }
                        .onExitCommand { draft = "\(value)"; isFocused = false }
                        .onHover { inside in if inside { NSCursor.iBeam.push() } else { NSCursor.pop() } }

                    Rectangle()
                        .fill(Color(white: 0.22))
                        .frame(width: 1, height: 24)

                    VStack(spacing: 0) {
                        Button { nudge(+1) } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 28, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle()
                            .fill(Color(white: 0.22))
                            .frame(width: 28, height: 1)
                        Button { nudge(-1) } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .frame(width: 28, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundStyle(Color(white: 0.50))
                }
                .padding(.vertical, 2)
                .fixedSize()
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(white: 0.12))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color(white: 0.22), lineWidth: 1))
                )

                Text(unit)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
        .onAppear { draft = "\(value)" }
        .onChange(of: value) { _, new in if !isFocused { draft = "\(new)" } }
        .onChange(of: isFocused) { _, focused in if !focused { commit() } }
    }

    private func nudge(_ direction: Int) {
        let next = value + direction * step
        if range.contains(next) { value = next }
    }

    private func commit() {
        if let v = Int(draft.trimmingCharacters(in: .whitespaces)), range.contains(v) {
            value = v
        } else {
            draft = "\(value)"
        }
    }
}

private struct KeyBadge: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(white: 0.7))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(white: 0.12))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(white: 0.25), lineWidth: 1))
            )
    }
}

private struct ShortcutRow: View {
    let label: String
    let keys: [String]

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { idx, key in
                    if idx > 0 {
                        Text("+")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.35))
                    }
                    KeyBadge(key: key)
                }
            }
        }
    }
}
