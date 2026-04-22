import SwiftUI

// MARK: - Helpers

private enum DropZone: Equatable {
    case before(UUID)
    case after(UUID)
    case child(UUID)
}

private struct FlatRow: Identifiable {
    let item: TodoItem
    let level: Int
    let hasChildren: Bool
    let doneChildren: Int
    let totalChildren: Int
    var id: UUID { item.id }
}

private func orderSiblings(_ siblings: [TodoItem]) -> [TodoItem] {
    let cal = Calendar.current
    func bucket(_ t: TodoItem) -> Int { t.isStarred ? 0 : 1 }
    return siblings.sorted { a, b in
        if bucket(a) != bucket(b) { return bucket(a) < bucket(b) }
        switch (a.dueDate, b.dueDate) {
        case (let da?, let db?): return cal.startOfDay(for: da) < cal.startOfDay(for: db)
        case (.some, .none):     return true
        case (.none, .some):     return false
        case (.none, .none):     return a.manualOrder < b.manualOrder
        }
    }
}

private func flattenTodos(
    _ todos: [TodoItem],
    parentId: UUID?,
    level: Int,
    activeOnly: Bool
) -> [FlatRow] {
    let children = todos.filter { $0.parentId == parentId }
    let filtered = (activeOnly && parentId == nil) ? children.filter { !$0.isCompleted } : children
    let sorted = orderSiblings(filtered)
    var out: [FlatRow] = []
    for c in sorted {
        let directChildren = todos.filter { $0.parentId == c.id }
        out.append(FlatRow(
            item: c,
            level: level,
            hasChildren: !directChildren.isEmpty,
            doneChildren: directChildren.filter { $0.isCompleted }.count,
            totalChildren: directChildren.count
        ))
        if c.isExpanded && !directChildren.isEmpty {
            out.append(contentsOf: flattenTodos(todos, parentId: c.id, level: level + 1, activeOnly: false))
        }
    }
    return out
}

private func formatDueDate(_ date: Date) -> String {
    let cal = Calendar.current
    if cal.isDateInToday(date) { return "hoje" }
    if cal.isDateInYesterday(date) { return "ontem" }
    if let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()), cal.isDate(date, inSameDayAs: tomorrow) {
        return "amanhã"
    }
    let formatter = DateFormatter()
    let daysAway = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: date)).day ?? 0
    formatter.dateFormat = daysAway < 365 ? "d MMM" : "d MMM yyyy"
    formatter.locale = Locale(identifier: "pt_BR")
    return formatter.string(from: date)
}

// MARK: - TasksView

struct TasksView: View {
    @Environment(PersistenceStore.self) private var store

    @State private var newTaskTitle = ""
    @State private var selectedID: UUID?
    @State private var editingID: UUID?
    @State private var editingDraft = ""
    @State private var hoveredID: UUID?
    @State private var showCompleted = false
    @State private var draggedID: UUID?
    @State private var dropZone: DropZone?
    @FocusState private var newTaskFocused: Bool
    @FocusState private var editingFocused: Bool

    private var flatActive: [FlatRow] {
        flattenTodos(store.todos, parentId: nil, level: 0, activeOnly: true)
    }

    private var flatCompleted: [FlatRow] {
        let completedRoots = store.todos
            .filter { $0.parentId == nil && $0.isCompleted }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        var out: [FlatRow] = []
        for root in completedRoots {
            let directChildren = store.todos.filter { $0.parentId == root.id }
            out.append(FlatRow(
                item: root, level: 0,
                hasChildren: !directChildren.isEmpty,
                doneChildren: directChildren.filter { $0.isCompleted }.count,
                totalChildren: directChildren.count
            ))
            if root.isExpanded {
                out.append(contentsOf: flattenTodos(store.todos, parentId: root.id, level: 1, activeOnly: false))
            }
        }
        return out
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                NewTaskInput(
                    text: $newTaskTitle,
                    focused: $newTaskFocused,
                    onSubmit: createTask
                )
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 12)

                if flatActive.isEmpty && flatCompleted.isEmpty {
                    EmptyTaskState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(flatActive) { row in
                                rowView(row)
                            }
                            if !flatCompleted.isEmpty {
                                CompletedSection(
                                    rows: flatCompleted,
                                    expanded: $showCompleted,
                                    hoveredID: $hoveredID,
                                    selectedID: $selectedID,
                                    editingID: $editingID,
                                    editingDraft: $editingDraft,
                                    editingFocused: $editingFocused,
                                    store: store
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) { handleSpaceKey() }
        .background {
            Group {
                Button("delete") { _ = handleDeleteKey() }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                Button("indent") { _ = handleIndent() }
                    .keyboardShortcut("]", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                Button("outdent") { _ = handleOutdent() }
                    .keyboardShortcut("[", modifiers: .command)
                    .opacity(0).frame(width: 0, height: 0)
                Button("subtask") { _ = handleAddSubtask() }
                    .keyboardShortcut(.return, modifiers: .option)
                    .opacity(0).frame(width: 0, height: 0)
            }
        }
        .onChange(of: store.todos) { _, _ in
            if let sel = selectedID, !store.todos.contains(where: { $0.id == sel }) {
                selectedID = nil
            }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func rowView(_ row: FlatRow) -> some View {
        TaskRowView(
            row: row,
            isSelected: selectedID == row.id,
            isEditing: editingID == row.id,
            editingDraft: $editingDraft,
            editingFocused: $editingFocused,
            dropZone: dropZone,
            onSelect: { selectedID = row.id },
            onStartEdit: {
                editingID = row.id
                editingDraft = row.item.title
                editingFocused = true
            },
            onCommitEdit: {
                store.updateTodoTitle(id: row.id, title: editingDraft)
                editingID = nil
            },
            onCancelEdit: { editingID = nil },
            onToggleComplete: { store.toggleCompleted(id: row.id) },
            onToggleStar: { store.toggleStarred(id: row.id) },
            onSetDueDate: { date in store.setDueDate(id: row.id, date: date) },
            onToggleExpand: { store.setExpanded(id: row.id, expanded: !row.item.isExpanded) },
            onDelete: { store.deleteTodo(id: row.id) },
            onAddSubtask: { addSubtask(to: row.id) }
        )
        .padding(.leading, CGFloat(row.level) * 20)
        .onDrag {
            draggedID = row.id
            return NSItemProvider(object: row.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: TaskDropDelegate(
            targetRow: row,
            allRows: flatActive,
            draggedID: $draggedID,
            dropZone: $dropZone,
            store: store
        ))
    }

    // MARK: - Actions

    private func createTask() {
        guard !newTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.addTodo(title: newTaskTitle)
        newTaskTitle = ""
    }

    private func addSubtask(to parentId: UUID) {
        guard let item = store.addTodo(title: "Nova subtarefa", parentId: parentId) else { return }
        store.setExpanded(id: parentId, expanded: true)
        selectedID = item.id
        editingID = item.id
        editingDraft = ""
        editingFocused = true
    }

    private func handleDeleteKey() -> KeyPress.Result {
        guard let id = selectedID, editingID == nil else { return .ignored }
        let rows = flatActive
        let idx = rows.firstIndex(where: { $0.id == id })
        store.deleteTodo(id: id)
        if let idx = idx {
            let nextIdx = idx < rows.count - 1 ? idx + 1 : idx - 1
            selectedID = nextIdx >= 0 ? rows[nextIdx].id : nil
        }
        return .handled
    }

    private func handleSpaceKey() -> KeyPress.Result {
        guard let id = selectedID, editingID == nil else { return .ignored }
        store.toggleCompleted(id: id)
        return .handled
    }

    private func handleIndent() -> KeyPress.Result {
        guard let id = selectedID, editingID == nil else { return .ignored }
        store.indentTodo(id: id)
        return .handled
    }

    private func handleOutdent() -> KeyPress.Result {
        guard let id = selectedID, editingID == nil else { return .ignored }
        store.outdentTodo(id: id)
        return .handled
    }

    private func handleAddSubtask() -> KeyPress.Result {
        guard let id = selectedID, editingID == nil else { return .ignored }
        addSubtask(to: id)
        return .handled
    }
}

// MARK: - Drop Delegate

private struct TaskDropDelegate: DropDelegate {
    let targetRow: FlatRow
    let allRows: [FlatRow]
    @Binding var draggedID: UUID?
    @Binding var dropZone: DropZone?
    let store: PersistenceStore

    func validateDrop(info: DropInfo) -> Bool { draggedID != nil && draggedID != targetRow.id }

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != targetRow.id else { return }
        let rowHeight: CGFloat = 38
        let y = info.location.y
        if y < 7 {
            dropZone = .before(targetRow.id)
        } else if y > rowHeight - 7 {
            dropZone = .after(targetRow.id)
        } else {
            dropZone = .child(targetRow.id)
        }
    }

    func dropExited(info: DropInfo) { dropZone = nil }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedID else { return false }
        defer { draggedID = nil; dropZone = nil }
        switch dropZone {
        case .before(let tid):
            let siblings = allRows.filter { $0.item.parentId == targetRow.item.parentId }
            let beforeIdx = siblings.firstIndex(where: { $0.id == tid })
            let insertBefore = beforeIdx.map { siblings[$0].id }
            store.moveTodo(id: dragged, newParentId: targetRow.item.parentId, insertBeforeId: insertBefore)
        case .after(let tid):
            let siblings = allRows.filter { $0.item.parentId == targetRow.item.parentId }
            if let afterIdx = siblings.firstIndex(where: { $0.id == tid }),
               afterIdx + 1 < siblings.count {
                store.moveTodo(id: dragged, newParentId: targetRow.item.parentId, insertBeforeId: siblings[afterIdx + 1].id)
            } else {
                store.moveTodo(id: dragged, newParentId: targetRow.item.parentId, insertBeforeId: nil)
            }
        case .child(let tid):
            store.moveTodo(id: dragged, newParentId: tid, insertBeforeId: nil)
            store.setExpanded(id: tid, expanded: true)
        case nil:
            break
        }
        return true
    }
}

// MARK: - TaskRowView

private struct TaskRowView: View {
    let row: FlatRow
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingDraft: String
    var editingFocused: FocusState<Bool>.Binding
    let dropZone: DropZone?
    let onSelect: () -> Void
    let onStartEdit: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void
    let onToggleComplete: () -> Void
    let onToggleStar: () -> Void
    let onSetDueDate: (Date?) -> Void
    let onToggleExpand: () -> Void
    let onDelete: () -> Void
    let onAddSubtask: () -> Void

    private var item: TodoItem { row.item }

    private var isDropChild: Bool { dropZone == .child(item.id) }
    private var isDropBefore: Bool { dropZone == .before(item.id) }
    private var isDropAfter: Bool { dropZone == .after(item.id) }

    var body: some View {
        ZStack(alignment: .top) {
            if isDropBefore {
                Rectangle().fill(Color(white: 0.55)).frame(height: 2)
                    .offset(y: -3)
                    .zIndex(10)
            }

            HStack(spacing: 8) {
                // Connector lines overlay handled via padding — the chevron or placeholder
                if row.hasChildren {
                    Button(action: onToggleExpand) {
                        Image(systemName: item.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.45))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 14)
                }

                // Checkbox
                Button(action: onToggleComplete) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(item.isCompleted ? Color(white: 0.65) : Color(white: 0.35))
                }
                .buttonStyle(.plain)

                // Title or edit field
                if isEditing {
                    TextField("", text: $editingDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color(white: 0.80))
                        .focused(editingFocused)
                        .onSubmit(onCommitEdit)
                        .onKeyPress(.escape) {
                            onCancelEdit()
                            return .handled
                        }
                } else {
                    Text(item.title)
                        .font(.system(size: 13))
                        .foregroundStyle(item.isCompleted ? Color(white: 0.35) : Color(white: 0.73))
                        .strikethrough(item.isCompleted, color: Color(white: 0.35))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2, perform: onStartEdit)
                        .onTapGesture(count: 1, perform: onSelect)
                }

                // Progress counter
                if row.hasChildren {
                    Text("\(row.doneChildren)/\(row.totalChildren)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(white: 0.40))
                }

                Spacer(minLength: 4)

                // Due date badge
                if let due = item.dueDate {
                    DueDateBadge(date: due)
                }

                // Star
                Button(action: onToggleStar) {
                    Image(systemName: item.isStarred ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(item.isStarred ? Color(white: 0.73) : Color(white: 0.30))
                }
                .buttonStyle(.plain)

                // Due date picker
                DueDateButton(currentDate: item.dueDate, onPick: onSetDueDate)

                // Add subtask — always visible
                Button(action: onAddSubtask) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.30))
                }
                .buttonStyle(.plain)
                .help("Adicionar subtarefa (⌥Enter)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isDropChild ? Color(white: 0.18) : isSelected ? Color(white: 0.14) : Color(white: 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isDropChild ? Color(white: 0.40) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button(role: .destructive, action: onDelete) {
                    Label("Apagar", systemImage: "trash")
                }
            }
            // Connector lines for indentation
            .overlay(alignment: .leading) {
                if row.level > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<row.level, id: \.self) { _ in
                            Rectangle()
                                .fill(Color(white: 0.18))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                                .padding(.leading, 9)
                                .padding(.trailing, 10)
                        }
                    }
                }
            }

            if isDropAfter {
                Rectangle().fill(Color(white: 0.55)).frame(height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 3)
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.12), value: dropZone)
    }
}

// MARK: - NewTaskInput

private struct NewTaskInput: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle")
                .font(.system(size: 14))
                .foregroundStyle(Color(white: 0.35))
            TextField("Nova tarefa", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.85))
                .focused(focused)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - DueDateButton

private struct DueDateButton: View {
    let currentDate: Date?
    let onPick: (Date?) -> Void
    @State private var showCustom = false
    @State private var customDate = Date()

    var body: some View {
        Menu {
            Button("Hoje") { onPick(Date()) }
            Button("Amanhã") { onPick(Calendar.current.date(byAdding: .day, value: 1, to: Date())) }
            Button("Próxima semana") { onPick(Calendar.current.date(byAdding: .day, value: 7, to: Date())) }
            Button("Escolher data...") { customDate = currentDate ?? Date(); showCustom = true }
            if currentDate != nil {
                Divider()
                Button("Remover data", role: .destructive) { onPick(nil) }
            }
        } label: {
            Image(systemName: currentDate == nil ? "calendar" : "calendar.badge.checkmark")
                .font(.system(size: 12))
                .foregroundStyle(Color(white: 0.35))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .popover(isPresented: $showCustom) {
            VStack(spacing: 12) {
                DatePicker("", selection: $customDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .frame(width: 260)
                Button("Aplicar") {
                    onPick(customDate)
                    showCustom = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }
}

// MARK: - DueDateBadge

private struct DueDateBadge: View {
    let date: Date

    private var isOverdue: Bool {
        date < Calendar.current.startOfDay(for: Date())
    }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        Text(formatDueDate(date))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle((isOverdue || isToday) ? Color(white: 0.85) : Color(white: 0.45))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOverdue ? Color(white: 0.22) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(white: 0.25), lineWidth: isOverdue ? 0 : 1)
                    )
            )
    }
}

// MARK: - CompletedSection

private struct CompletedSection: View {
    let rows: [FlatRow]
    @Binding var expanded: Bool
    @Binding var hoveredID: UUID?
    @Binding var selectedID: UUID?
    @Binding var editingID: UUID?
    @Binding var editingDraft: String
    var editingFocused: FocusState<Bool>.Binding
    let store: PersistenceStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                    Text("CONCLUÍDAS (\(rows.filter { $0.level == 0 }.count))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .tracking(1.5)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 12)

            if expanded {
                ForEach(rows) { row in
                    TaskRowView(
                        row: row,
                        isSelected: selectedID == row.id,
                        isEditing: editingID == row.id,
                        editingDraft: $editingDraft,
                        editingFocused: editingFocused,
                        dropZone: nil,
                        onSelect: { selectedID = row.id },
                        onStartEdit: {
                            editingID = row.id
                            editingDraft = row.item.title
                        },
                        onCommitEdit: {
                            store.updateTodoTitle(id: row.id, title: editingDraft)
                            editingID = nil
                        },
                        onCancelEdit: { editingID = nil },
                        onToggleComplete: { store.toggleCompleted(id: row.id) },
                        onToggleStar: { store.toggleStarred(id: row.id) },
                        onSetDueDate: { date in store.setDueDate(id: row.id, date: date) },
                        onToggleExpand: { store.setExpanded(id: row.id, expanded: !row.item.isExpanded) },
                        onDelete: { store.deleteTodo(id: row.id) },
                        onAddSubtask: {}
                    )
                    .padding(.leading, CGFloat(row.level) * 20)
                }
            }
        }
    }
}

// MARK: - EmptyState

private struct EmptyTaskState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.system(size: 40))
                .foregroundStyle(Color(white: 0.22))
            Text("Sem tarefas")
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(white: 0.35))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
