import Foundation

struct WeeklyAggregate: Codable, Identifiable {
    var id: UUID
    var weekStart: Date
    var totalFocusSeconds: Int
    var sessionCount: Int

    init(weekStart: Date, totalFocusSeconds: Int, sessionCount: Int) {
        self.id = UUID()
        self.weekStart = weekStart
        self.totalFocusSeconds = totalFocusSeconds
        self.sessionCount = sessionCount
    }
}
