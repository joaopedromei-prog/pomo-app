import Foundation

struct TodoItem: Codable, Identifiable, Equatable {
    var id: UUID
    var parentId: UUID?
    var title: String
    var isCompleted: Bool
    var isStarred: Bool
    var dueDate: Date?
    var createdAt: Date
    var completedAt: Date?
    var manualOrder: Int
    var isExpanded: Bool

    init(title: String, parentId: UUID? = nil) {
        id = UUID()
        self.parentId = parentId
        self.title = title
        isCompleted = false
        isStarred = false
        dueDate = nil
        createdAt = Date()
        completedAt = nil
        manualOrder = 0
        isExpanded = true
    }
}
