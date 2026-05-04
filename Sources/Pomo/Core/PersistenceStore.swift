import Foundation
import Observation

@Observable
@MainActor
final class PersistenceStore {

    private(set) var sessions: [Session] = []
    private(set) var weeklyAggregates: [WeeklyAggregate] = []
    private(set) var monthlyAggregates: [MonthlyAggregate] = []
    private(set) var todos: [TodoItem] = []
    private(set) var inflight: InflightSession?

    private let storeURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storeURL = appSupport.appendingPathComponent("Pomo", isDirectory: true)
        try? FileManager.default.createDirectory(at: storeURL, withIntermediateDirectories: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    // MARK: - Inflight session

    func setInflight(_ session: InflightSession) {
        inflight = session
        save(session, to: "inflight.json")
    }

    func clearInflight() {
        inflight = nil
        let url = storeURL.appendingPathComponent("inflight.json")
        try? FileManager.default.removeItem(at: url)
    }

    func finalizeInflight(endedAt: Date) {
        guard let inf = inflight, inf.actualDuration > 0 else {
            clearInflight()
            return
        }
        var session = Session(
            startedAt: inf.startedAt, endedAt: endedAt,
            kind: inf.kind, plannedDuration: inf.plannedDuration,
            actualDuration: inf.actualDuration
        )
        session.id = inf.id
        insert(session: session)
        clearInflight()
    }

    // MARK: - Write

    func insert(session: Session) {
        sessions.append(session)
        saveSessions()
    }

    func deleteSession(id: UUID) {
        sessions.removeAll { $0.id == id }
        saveSessions()
    }

    func replaceWeeklyAggregates(_ aggs: [WeeklyAggregate]) {
        weeklyAggregates = aggs
        saveWeekly()
    }

    func replaceMonthlyAggregates(_ aggs: [MonthlyAggregate]) {
        monthlyAggregates = aggs
        saveMonthly()
    }

    func deleteSessions(ids: Set<UUID>) {
        sessions.removeAll { ids.contains($0.id) }
        saveSessions()
    }

    func deleteWeeklyAggregates(ids: Set<UUID>) {
        weeklyAggregates.removeAll { ids.contains($0.id) }
        saveWeekly()
    }

    // MARK: - Todos

    @discardableResult
    func addTodo(title: String, parentId: UUID? = nil) -> TodoItem? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let siblings = todos.filter { $0.parentId == parentId }
        let nextOrder = (siblings.map(\.manualOrder).max() ?? -1) + 1
        var item = TodoItem(title: trimmed, parentId: parentId)
        item.manualOrder = nextOrder
        todos.append(item)
        saveTodos()
        return item
    }

    func updateTodoTitle(id: UUID, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].title = trimmed
        saveTodos()
    }

    func toggleStarred(id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isStarred.toggle()
        saveTodos()
    }

    func setDueDate(id: UUID, date: Date?) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].dueDate = date.map { Calendar.current.startOfDay(for: $0) }
        saveTodos()
    }

    func setExpanded(id: UUID, expanded: Bool) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[i].isExpanded = expanded
        saveTodos()
    }

    func toggleCompleted(id: UUID) {
        guard let i = todos.firstIndex(where: { $0.id == id }) else { return }
        if todos[i].isCompleted {
            todos[i].isCompleted = false
            todos[i].completedAt = nil
        } else {
            let now = Date()
            let descendants = allDescendantIDs(of: id)
            for descID in descendants {
                if let j = todos.firstIndex(where: { $0.id == descID }) {
                    todos[j].isCompleted = true
                    todos[j].completedAt = now
                }
            }
            todos[i].isCompleted = true
            todos[i].completedAt = now
        }
        saveTodos()
    }

    func deleteTodo(id: UUID) {
        let toRemove = Set([id] + allDescendantIDs(of: id))
        todos.removeAll { toRemove.contains($0.id) }
        saveTodos()
    }

    func moveTodo(id: UUID, newParentId: UUID?, insertBeforeId: UUID?) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        if let np = newParentId, isDescendantOrSelf(np, of: id) { return }
        todos[idx].parentId = newParentId
        var siblings = todos.filter { $0.parentId == newParentId && $0.id != id }
        if let beforeId = insertBeforeId, let pos = siblings.firstIndex(where: { $0.id == beforeId }) {
            siblings.insert(todos[idx], at: pos)
        } else {
            siblings.append(todos[idx])
        }
        for (order, sibling) in siblings.enumerated() {
            if let j = todos.firstIndex(where: { $0.id == sibling.id }) {
                todos[j].manualOrder = order
            }
        }
        saveTodos()
    }

    func indentTodo(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }) else { return }
        let parentId = todos[idx].parentId
        let siblings = todos
            .filter { $0.parentId == parentId }
            .sorted { $0.manualOrder < $1.manualOrder }
        guard let pos = siblings.firstIndex(where: { $0.id == id }), pos > 0 else { return }
        let newParentId = siblings[pos - 1].id
        moveTodo(id: id, newParentId: newParentId, insertBeforeId: nil)
        if let j = todos.firstIndex(where: { $0.id == newParentId }) {
            todos[j].isExpanded = true
        }
        saveTodos()
    }

    func outdentTodo(id: UUID) {
        guard let idx = todos.firstIndex(where: { $0.id == id }),
              let currentParentId = todos[idx].parentId,
              let parentIdx = todos.firstIndex(where: { $0.id == currentParentId })
        else { return }
        let grandParentId = todos[parentIdx].parentId
        moveTodo(id: id, newParentId: grandParentId, insertBeforeId: nil)
    }

    private func allDescendantIDs(of id: UUID) -> [UUID] {
        let directChildren = todos.filter { $0.parentId == id }.map(\.id)
        return directChildren + directChildren.flatMap { allDescendantIDs(of: $0) }
    }

    private func isDescendantOrSelf(_ candidateId: UUID, of rootId: UUID) -> Bool {
        var current: UUID? = candidateId
        while let cur = current {
            if cur == rootId { return true }
            current = todos.first(where: { $0.id == cur })?.parentId
        }
        return false
    }

    // MARK: - Persist

    private func load() {
        sessions = load(from: "sessions.json") ?? []
        weeklyAggregates = load(from: "weekly.json") ?? []
        monthlyAggregates = load(from: "monthly.json") ?? []
        todos = load(from: "tasks.json") ?? []
        if let orphan: InflightSession = load(from: "inflight.json") {
            inflight = orphan
            finalizeInflight(endedAt: orphan.lastTickAt)
        }
    }

    private func load<T: Decodable>(from filename: String) -> T? {
        let url = storeURL.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func saveSessions() { save(sessions, to: "sessions.json") }
    private func saveWeekly()   { save(weeklyAggregates, to: "weekly.json") }
    private func saveMonthly()  { save(monthlyAggregates, to: "monthly.json") }
    private func saveTodos()    { save(todos, to: "tasks.json") }

    private func save<T: Encodable>(_ value: T, to filename: String) {
        let url = storeURL.appendingPathComponent(filename)
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
