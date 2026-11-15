import GesherKit
import GesherPlatform
import Foundation
import NotesCore

private let noteParam = Param.string("note", "Note title or id.", required: true)
private let ifRevisionParam = Param.string(
    "ifRevision", "Fail with revision_conflict if the note changed since this revision.")

extension NotesContext {
    func checklist(_ note: NoteSummarySnapshot, revision: String? = nil) throws -> ChecklistOut {
        let items = try write.checklistItems(id: note.id)
        let current = try revision ?? read.fetchNote(id: note.id).revision
        return ChecklistOut(
            note: note.id, title: note.title, revision: current,
            items: items.enumerated().map { ChecklistItemOut(number: $0 + 1, text: $1.text, checked: $1.checked) })
    }

    /// Items by 1-based number or by text (exact, normalized, then unique prefix/words).
    func setChecklist(_ selectors: [String], checked: Bool, note selector: String, ifRevision: String?) throws
        -> ChecklistOut
    {
        let note = try writableNote(selector)
        let items = try write.checklistItems(id: note.id)
        guard !items.isEmpty else {
            throw AgentError(
                code: "no_checklist", message: "The note has no checklist items.", hint: "Add some with checklist add.")
        }
        let numbered = items.enumerated().map { (number: String($0 + 1), item: $1) }
        let chosen = try selectors.map { selector -> ChecklistItemSnapshot in
            if let number = Int(selector) {
                guard (1...items.count).contains(number) else {
                    throw AgentError.invalid("Checklist item \(number) does not exist; the note has \(items.count).")
                }
                return items[number - 1]
            }
            return try EntityResolver.resolve(
                selector, in: numbered, type: "checklist item", id: \.number, name: \.item.text,
                detail: { $0.item.checked ? "checked" : "unchecked" }
            ).item
        }
        let states = Dictionary(chosen.map { ($0.paragraph, checked) }, uniquingKeysWith: { first, _ in first })
        let saved = try write.setChecklist(id: note.id, states: states, ifRevision: ifRevision)
        return try checklist(note, revision: saved.revision)
    }
}

enum ListChecklist: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
    }

    static let path = ["checklist", "list"]
    static let summary = "List a note's checklist items with their number and checked state."
    static let params: [Param] = [.string("note", "Note title or id.", required: true, positional: true)]
    static let examples = ["checklist list Groceries"]

    static func run(_ input: Input, _ context: NotesContext) throws -> ChecklistOut {
        try context.checklist(context.note(input.note, in: context.notes()))
    }

    static func pretty(_ output: ChecklistOut) -> String? {
        output.items.map { "\($0.number). [\($0.checked ? "x" : " ")] \($0.text)" }.joined(separator: "\n")
    }
}

enum AddChecklistItems: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var item: [String]
        var checked: Bool
        var top: Bool
        var ifRevision: String?
    }

    static let path = ["checklist", "add"]
    static let summary = "Add checklist items to a note (at the end, or below the title with top)."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        noteParam,
        .list("item", "Item texts, one per checklist line.", required: true, positional: true),
        .boolean("checked", "Add the items already checked."),
        .boolean("top", "Insert below the title instead of at the end."),
        ifRevisionParam,
    ]
    static let examples = ["checklist add --note Groceries milk eggs 'olive oil'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> ChecklistOut {
        let note = try context.writableNote(input.note)
        let paragraphs = try input.item.map { text -> NoteDocument.Paragraph in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("\n") else {
                throw AgentError.invalid("Checklist items must be non-empty single lines.")
            }
            return .init(style: .checklist, runs: NoteMarkdown.inline(trimmed), checked: input.checked)
        }
        let saved = try context.write.insertContent(
            id: note.id, document: NoteDocument(paragraphs: paragraphs), at: input.top ? .afterTitle : .end,
            ifRevision: input.ifRevision)
        return try context.checklist(note, revision: saved.revision)
    }
}

enum CheckChecklistItems: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var item: [String]
        var ifRevision: String?
    }

    static let path = ["checklist", "check"]
    static let summary = "Check checklist items, chosen by text or by number from checklist list."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        noteParam, .list("item", "Item texts or numbers.", required: true, positional: true), ifRevisionParam,
    ]
    static let examples = ["checklist check --note Groceries milk 3"]

    static func run(_ input: Input, _ context: NotesContext) throws -> ChecklistOut {
        try context.setChecklist(input.item, checked: true, note: input.note, ifRevision: input.ifRevision)
    }
}

enum UncheckChecklistItems: AgentOperation {
    struct Input: Decodable, Sendable {
        var note: String
        var item: [String]
        var ifRevision: String?
    }

    static let path = ["checklist", "uncheck"]
    static let summary = "Uncheck checklist items, chosen by text or by number."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        noteParam, .list("item", "Item texts or numbers.", required: true, positional: true), ifRevisionParam,
    ]
    static let examples = ["checklist uncheck --note Groceries milk"]

    static func run(_ input: Input, _ context: NotesContext) throws -> ChecklistOut {
        try context.setChecklist(input.item, checked: false, note: input.note, ifRevision: input.ifRevision)
    }
}
