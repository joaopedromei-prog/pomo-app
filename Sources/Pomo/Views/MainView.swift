import SwiftUI

enum AppTab: String, CaseIterable {
    case timer    = "Timer"
    case tasks    = "Tarefas"
    case history  = "Histórico"
    case settings = "Ajustes"

    var icon: String {
        switch self {
        case .timer:    return "timer"
        case .tasks:    return "checklist"
        case .history:  return "chart.bar"
        case .settings: return "gearshape"
        }
    }

    var index: Int { AppTab.allCases.firstIndex(of: self)! }
}

struct MainView: View {
    @State private var selected: AppTab = .timer
    @State private var previous: AppTab = .timer

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabContent(tab)
                        .opacity(selected == tab ? 1 : 0)
                        .offset(x: xOffset(for: tab))
                        .allowsHitTesting(selected == tab)
                        .animation(
                            .spring(response: 0.38, dampingFraction: 0.88),
                            value: selected
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider().opacity(0.2)

            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .frame(height: 56)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 580, minHeight: 640)
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .timer:    TimerView()
        case .tasks:    TasksView()
        case .history:  HistoryView()
        case .settings: SettingsView()
        }
    }

    private func xOffset(for tab: AppTab) -> CGFloat {
        let diff = tab.index - selected.index
        if diff == 0 { return 0 }
        return diff > 0 ? 620 : -620
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            guard tab != selected else { return }
            previous = selected
            selected = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17))
                Text(tab.rawValue.lowercased())
                    .font(.system(size: 10))
            }
            .foregroundStyle(selected == tab ? .primary : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
