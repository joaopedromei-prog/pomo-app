import Foundation

enum SessionKind: String, Codable {
    case focusPomodoro
    case stopwatch
}

struct Session: Codable, Identifiable {
    var id: UUID
    var startedAt: Date
    var endedAt: Date
    var kind: SessionKind
    var plannedDuration: Int  // seconds; 0 for stopwatch
    var actualDuration: Int   // effective seconds (pause-aware)

    init(startedAt: Date, endedAt: Date, kind: SessionKind,
         plannedDuration: Int, actualDuration: Int) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.kind = kind
        self.plannedDuration = plannedDuration
        self.actualDuration = actualDuration
    }
}
