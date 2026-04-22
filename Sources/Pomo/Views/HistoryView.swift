import SwiftUI
import Charts

enum HistoryPeriod: String, CaseIterable {
    case day = "Dia"
    case week = "Semana"
    case month = "Mês"
    case year = "Ano"
}

struct FocusBar: Identifiable {
    let id: String
    let label: String
    let date: Date
    let hours: Double
}

struct HistoryView: View {
    @Environment(PersistenceStore.self) private var store
    @State private var period: HistoryPeriod = .day
    @State private var hoveredBar: FocusBar?
    @State private var tooltipPos: CGPoint = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(totalLabel)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(subtitleLabel)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $period) {
                    ForEach(HistoryPeriod.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 20)

            let bars = buildBars()
            if bars.allSatisfy({ $0.hours == 0 }) {
                ContentUnavailableView(
                    "Nenhuma sessão ainda",
                    systemImage: "timer",
                    description: Text("Inicie um Pomodoro ou cronômetro para registrar horas de foco.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(bars) { bar in
                    BarMark(
                        x: .value("Data", bar.label),
                        y: .value("Horas", bar.hours)
                    )
                    .foregroundStyle(Color.primary)
                    .cornerRadius(3)
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.secondary.opacity(0.3))
                        AxisValueLabel {
                            if let h = value.as(Double.self) {
                                Text("\(Int(h))h")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Color.clear
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let loc):
                                    if let frame = proxy.plotFrame {
                                        let xInPlot = loc.x - geo[frame].origin.x
                                        if let label: String = proxy.value(atX: xInPlot) {
                                            hoveredBar = bars.first { $0.label == label }
                                        } else {
                                            hoveredBar = nil
                                        }
                                    }
                                    tooltipPos = loc
                                case .ended:
                                    hoveredBar = nil
                                }
                            }
                    }
                }
                .overlay(alignment: .topLeading) {
                    if let bar = hoveredBar {
                        BarTooltip(bar: bar)
                            .offset(x: max(4, tooltipPos.x - 50), y: max(4, tooltipPos.y - 68))
                            .allowsHitTesting(false)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Labels

    private var totalLabel: String {
        let total = currentPeriodTotal()
        let h = Int(total); let m = Int((total - Double(h)) * 60)
        let formatted = h > 0 ? "\(h)h \(m)min" : "\(m)min"
        switch period {
        case .day:   return "\(formatted) hoje"
        case .week:  return "\(formatted) esta semana"
        case .month: return "\(formatted) este mês"
        case .year:  return "\(formatted) este ano"
        }
    }

    private var subtitleLabel: String {
        let cal = Calendar.current
        let now = Date()
        let prefix: String
        let avg: Double

        switch period {
        case .day:
            prefix = "Média diária"
            guard let start = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now)) else { return "Sem sessões registradas" }
            var total = 0.0; var nonZeroDays = 0
            for offset in 0..<30 {
                guard let date = cal.date(byAdding: .day, value: offset, to: start),
                      let next = cal.date(byAdding: .day, value: 1, to: date) else { continue }
                let h = Double(store.sessions.filter { $0.endedAt >= date && $0.endedAt < next }
                    .reduce(0) { $0 + $1.actualDuration }) / 3600.0
                if h > 0 { total += h; nonZeroDays += 1 }
            }
            guard nonZeroDays > 0 else { return "Sem sessões registradas" }
            avg = total / Double(nonZeroDays)

        case .week:
            prefix = "Média semanal"
            guard let yearAgo = cal.date(byAdding: .year, value: -1, to: now) else { return "Sem sessões registradas" }
            var weekBuckets: [Date: Double] = [:]
            for s in store.sessions where s.endedAt >= yearAgo {
                guard let ws = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.endedAt)) else { continue }
                weekBuckets[ws, default: 0] += Double(s.actualDuration) / 3600.0
            }
            for a in store.weeklyAggregates where a.weekStart >= yearAgo {
                weekBuckets[a.weekStart, default: 0] += Double(a.totalFocusSeconds) / 3600.0
            }
            let nonZeroW = weekBuckets.values.filter { $0 > 0 }
            guard !nonZeroW.isEmpty else { return "Sem sessões registradas" }
            avg = nonZeroW.reduce(0, +) / Double(nonZeroW.count)

        case .month:
            prefix = "Média mensal"
            guard let yearAgo = cal.date(byAdding: .year, value: -1, to: now) else { return "Sem sessões registradas" }
            var monthBuckets: [Date: Double] = [:]
            for s in store.sessions where s.endedAt >= yearAgo {
                guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: s.endedAt)) else { continue }
                monthBuckets[ms, default: 0] += Double(s.actualDuration) / 3600.0
            }
            for a in store.weeklyAggregates where a.weekStart >= yearAgo {
                guard let ms = cal.date(from: cal.dateComponents([.year, .month], from: a.weekStart)) else { continue }
                monthBuckets[ms, default: 0] += Double(a.totalFocusSeconds) / 3600.0
            }
            for a in store.monthlyAggregates where a.monthStart >= yearAgo {
                monthBuckets[a.monthStart, default: 0] += Double(a.totalFocusSeconds) / 3600.0
            }
            let nonZeroM = monthBuckets.values.filter { $0 > 0 }
            guard !nonZeroM.isEmpty else { return "Sem sessões registradas" }
            avg = nonZeroM.reduce(0, +) / Double(nonZeroM.count)

        case .year:
            prefix = "Média anual"
            let nonZero = buildBars().filter { $0.hours > 0 }
            guard !nonZero.isEmpty else { return "Sem sessões registradas" }
            avg = nonZero.reduce(0) { $0 + $1.hours } / Double(nonZero.count)
        }

        let h = Int(avg); let m = Int((avg - Double(h)) * 60)
        return "\(prefix): \(h > 0 ? "\(h)h \(m)min" : "\(m)min")"
    }

    private func currentPeriodTotal() -> Double {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .day:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return Double(store.sessions.filter { $0.endedAt >= start && $0.endedAt < end }
                .reduce(0) { $0 + $1.actualDuration }) / 3600.0
        case .week:
            let ws = weekStart(of: now, cal: cal)
            let we = cal.date(byAdding: .weekOfYear, value: 1, to: ws)!
            let s1 = store.sessions.filter { $0.endedAt >= ws && $0.endedAt < we }.reduce(0) { $0 + $1.actualDuration }
            let s2 = store.weeklyAggregates.filter { $0.weekStart >= ws && $0.weekStart < we }.reduce(0) { $0 + $1.totalFocusSeconds }
            return Double(s1 + s2) / 3600.0
        case .month:
            let ms = monthStart(of: now, cal: cal)
            let me = cal.date(byAdding: .month, value: 1, to: ms)!
            let s1 = store.sessions.filter { $0.endedAt >= ms && $0.endedAt < me }.reduce(0) { $0 + $1.actualDuration }
            let s2 = store.weeklyAggregates.filter { $0.weekStart >= ms && $0.weekStart < me }.reduce(0) { $0 + $1.totalFocusSeconds }
            let s3 = store.monthlyAggregates.filter { $0.monthStart >= ms && $0.monthStart < me }.reduce(0) { $0 + $1.totalFocusSeconds }
            return Double(s1 + s2 + s3) / 3600.0
        case .year:
            let year = cal.component(.year, from: now)
            guard let ys = cal.date(from: DateComponents(year: year)),
                  let ye = cal.date(byAdding: .year, value: 1, to: ys) else { return 0 }
            let s1 = store.sessions.filter { $0.endedAt >= ys && $0.endedAt < ye }.reduce(0) { $0 + $1.actualDuration }
            let s2 = store.weeklyAggregates.filter { $0.weekStart >= ys && $0.weekStart < ye }.reduce(0) { $0 + $1.totalFocusSeconds }
            let s3 = store.monthlyAggregates.filter { $0.monthStart >= ys && $0.monthStart < ye }.reduce(0) { $0 + $1.totalFocusSeconds }
            return Double(s1 + s2 + s3) / 3600.0
        }
    }

    // MARK: - Chart data

    private func buildBars() -> [FocusBar] {
        let cal = Calendar.current
        let now = Date()
        let fmt = DateFormatter()

        switch period {
        case .day:
            guard let start = cal.date(byAdding: .day, value: -13, to: cal.startOfDay(for: now)) else { return [] }
            fmt.dateFormat = "dd/MM"
            return (0..<14).compactMap { offset in
                guard let date = cal.date(byAdding: .day, value: offset, to: start),
                      let next = cal.date(byAdding: .day, value: 1, to: date) else { return nil }
                let secs = store.sessions.filter { $0.endedAt >= date && $0.endedAt < next }
                    .reduce(0) { $0 + $1.actualDuration }
                return FocusBar(id: fmt.string(from: date), label: fmt.string(from: date),
                                date: date, hours: Double(secs) / 3600.0)
            }

        case .week:
            guard let start = cal.date(byAdding: .weekOfYear, value: -11, to: weekStart(of: now, cal: cal)) else { return [] }
            fmt.dateFormat = "dd/MM"
            return (0..<12).compactMap { offset in
                guard let ws = cal.date(byAdding: .weekOfYear, value: offset, to: start),
                      let we = cal.date(byAdding: .weekOfYear, value: 1, to: ws) else { return nil }
                let s1 = store.sessions.filter { $0.endedAt >= ws && $0.endedAt < we }.reduce(0) { $0 + $1.actualDuration }
                let s2 = store.weeklyAggregates.filter { $0.weekStart >= ws && $0.weekStart < we }.reduce(0) { $0 + $1.totalFocusSeconds }
                return FocusBar(id: fmt.string(from: ws), label: fmt.string(from: ws),
                                date: ws, hours: Double(s1 + s2) / 3600.0)
            }

        case .month:
            guard let start = cal.date(byAdding: .month, value: -11, to: monthStart(of: now, cal: cal)) else { return [] }
            fmt.dateFormat = "MMM yy"
            return (0..<12).compactMap { offset in
                guard let ms = cal.date(byAdding: .month, value: offset, to: start),
                      let me = cal.date(byAdding: .month, value: 1, to: ms) else { return nil }
                let s1 = store.sessions.filter { $0.endedAt >= ms && $0.endedAt < me }.reduce(0) { $0 + $1.actualDuration }
                let s2 = store.weeklyAggregates.filter { $0.weekStart >= ms && $0.weekStart < me }.reduce(0) { $0 + $1.totalFocusSeconds }
                let s3 = store.monthlyAggregates.filter { $0.monthStart >= ms && $0.monthStart < me }.reduce(0) { $0 + $1.totalFocusSeconds }
                return FocusBar(id: fmt.string(from: ms), label: fmt.string(from: ms),
                                date: ms, hours: Double(s1 + s2 + s3) / 3600.0)
            }

        case .year:
            let years = allYearsPresent()
            return years.compactMap { year in
                guard let ys = cal.date(from: DateComponents(year: year)),
                      let ye = cal.date(byAdding: .year, value: 1, to: ys) else { return nil }
                let s1 = store.sessions.filter { $0.endedAt >= ys && $0.endedAt < ye }.reduce(0) { $0 + $1.actualDuration }
                let s2 = store.weeklyAggregates.filter { $0.weekStart >= ys && $0.weekStart < ye }.reduce(0) { $0 + $1.totalFocusSeconds }
                let s3 = store.monthlyAggregates.filter { $0.monthStart >= ys && $0.monthStart < ye }.reduce(0) { $0 + $1.totalFocusSeconds }
                return FocusBar(id: "\(year)", label: "\(year)", date: ys,
                                hours: Double(s1 + s2 + s3) / 3600.0)
            }
        }
    }

    private func allYearsPresent() -> [Int] {
        var years = Set<Int>()
        let cal = Calendar.current
        store.sessions.forEach { years.insert(cal.component(.year, from: $0.endedAt)) }
        store.weeklyAggregates.forEach { years.insert(cal.component(.year, from: $0.weekStart)) }
        store.monthlyAggregates.forEach { years.insert(cal.component(.year, from: $0.monthStart)) }
        if years.isEmpty { years.insert(cal.component(.year, from: Date())) }
        return years.sorted()
    }

    private func weekStart(of date: Date, cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)) ?? date
    }

    private func monthStart(of date: Date, cal: Calendar) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}

// MARK: - BarTooltip

private struct BarTooltip: View {
    let bar: FocusBar

    private var formatted: String {
        let h = Int(bar.hours)
        let m = Int((bar.hours - Double(h)) * 60)
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bar.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color(white: 0.55))
            Text("Tempo de foco: \(formatted)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.92))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.13))
                .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 4)
        )
        .fixedSize()
    }
}
