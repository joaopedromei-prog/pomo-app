import Foundation

struct MonthlyAggregate: Codable, Identifiable {
    var id: UUID
    var monthStart: Date
    var totalFocusSeconds: Int
    var sessionCount: Int

    init(monthStart: Date, totalFocusSeconds: Int, sessionCount: Int) {
        self.id = UUID()
        self.monthStart = monthStart
        self.totalFocusSeconds = totalFocusSeconds
        self.sessionCount = sessionCount
    }
}
