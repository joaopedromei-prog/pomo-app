import Foundation

struct AggregationService {

    @MainActor
    static func run(store: PersistenceStore) {
        Task.detached(priority: .background) {
            let calendar = Calendar.current
            let now = Date()
            guard let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now),
                  let oneYearAgo = calendar.date(byAdding: .year, value: -1, to: now) else { return }

            // Snapshot under MainActor
            let allSessions = await MainActor.run { store.sessions }
            let allWeekly   = await MainActor.run { store.weeklyAggregates }
            let allMonthly  = await MainActor.run { store.monthlyAggregates }

            // --- Phase 1: Sessions older than 30d → WeeklyAggregate ---
            let oldSessions = allSessions.filter { $0.endedAt < thirtyDaysAgo }
            guard !oldSessions.isEmpty else { return }

            var weekBuckets: [Date: (seconds: Int, count: Int)] = [:]
            for session in oldSessions {
                guard let weekStart = calendar.date(
                    from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.endedAt)
                ) else { continue }
                let existing = weekBuckets[weekStart] ?? (0, 0)
                weekBuckets[weekStart] = (existing.seconds + session.actualDuration, existing.count + 1)
            }

            var updatedWeekly = allWeekly
            var deletedSessionIDs = Set<UUID>()

            for (weekStart, data) in weekBuckets {
                if let idx = updatedWeekly.firstIndex(where: { $0.weekStart == weekStart }) {
                    updatedWeekly[idx].totalFocusSeconds += data.seconds
                    updatedWeekly[idx].sessionCount += data.count
                } else {
                    updatedWeekly.append(WeeklyAggregate(weekStart: weekStart,
                                                          totalFocusSeconds: data.seconds,
                                                          sessionCount: data.count))
                }
            }
            deletedSessionIDs = Set(oldSessions.map { $0.id })

            let idsToDelete = deletedSessionIDs
            let weeklyToSave = updatedWeekly
            await MainActor.run {
                store.deleteSessions(ids: idsToDelete)
                store.replaceWeeklyAggregates(weeklyToSave)
            }

            // --- Phase 2: Weekly older than 1 year → MonthlyAggregate ---
            let oldWeekly = updatedWeekly.filter { $0.weekStart < oneYearAgo }
            guard !oldWeekly.isEmpty else { return }

            var monthBuckets: [Date: (seconds: Int, count: Int)] = [:]
            for agg in oldWeekly {
                guard let monthStart = calendar.date(
                    from: calendar.dateComponents([.year, .month], from: agg.weekStart)
                ) else { continue }
                let existing = monthBuckets[monthStart] ?? (0, 0)
                monthBuckets[monthStart] = (existing.seconds + agg.totalFocusSeconds, existing.count + agg.sessionCount)
            }

            var updatedMonthly = allMonthly
            var deletedWeeklyIDs = Set<UUID>()

            for (monthStart, data) in monthBuckets {
                if let idx = updatedMonthly.firstIndex(where: { $0.monthStart == monthStart }) {
                    updatedMonthly[idx].totalFocusSeconds += data.seconds
                    updatedMonthly[idx].sessionCount += data.count
                } else {
                    updatedMonthly.append(MonthlyAggregate(monthStart: monthStart,
                                                            totalFocusSeconds: data.seconds,
                                                            sessionCount: data.count))
                }
            }
            deletedWeeklyIDs = Set(oldWeekly.map { $0.id })

            let weeklyIDsToDelete = deletedWeeklyIDs
            let monthlyToSave = updatedMonthly
            await MainActor.run {
                store.deleteWeeklyAggregates(ids: weeklyIDsToDelete)
                store.replaceMonthlyAggregates(monthlyToSave)
            }
        }
    }
}
