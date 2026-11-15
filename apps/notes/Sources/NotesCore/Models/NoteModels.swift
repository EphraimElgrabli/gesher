import GesherPlatform
import Foundation

public struct NoteAccountSnapshot: Codable, Sendable {
    public let id: String
    public let title: String
    public let isDefault: Bool

    public init(id: String, title: String, isDefault: Bool = false) {
        self.id = id
        self.title = title
        self.isDefault = isDefault
    }
}

public struct NoteFolderSnapshot: Codable, Sendable {
    public let id: String
    public let title: String
    public let accountID: String
    public let accountTitle: String
    public let noteCount: Int?
    public let parentID: String?
    public let isSmart: Bool
    public let isRecentlyDeleted: Bool
    public let isDeletable: Bool
    /// Native description of a smart folder's filter, when available.
    public let smartDescription: String?

    public init(
        id: String,
        title: String,
        accountID: String,
        accountTitle: String,
        noteCount: Int? = nil,
        parentID: String? = nil,
        isSmart: Bool = false,
        isRecentlyDeleted: Bool = false,
        isDeletable: Bool = true,
        smartDescription: String? = nil
    ) {
        self.id = id
        self.title = title
        self.accountID = accountID
        self.accountTitle = accountTitle
        self.noteCount = noteCount
        self.parentID = parentID
        self.isSmart = isSmart
        self.isRecentlyDeleted = isRecentlyDeleted
        self.isDeletable = isDeletable
        self.smartDescription = smartDescription
    }
}

public struct NoteSnapshot: Codable, Sendable {
    public let id: String
    public let title: String
    public let displayTitle: String?
    public let titleAvailability: String
    public let tables: [NoteTableSnapshot]?
    public let formatting: [NoteTextRun]?
    public let body: String?
    public let snippet: String?
    public let folderID: String
    public let folderTitle: String
    public let accountID: String
    public let isPasswordProtected: Bool
    public let isPinned: Bool
    public let creationDate: String?
    public let modificationDate: String?
    public let revision: String?

    public init(
        id: String,
        title: String,
        snippet: String?,
        displayTitle: String? = nil,
        body: String? = nil,
        formatting: [NoteTextRun]? = nil,
        tables: [NoteTableSnapshot]? = nil,
        folderID: String,
        folderTitle: String,
        accountID: String,
        isPasswordProtected: Bool = false,
        isPinned: Bool = false,
        creationDate: String? = nil,
        modificationDate: String? = nil,
        revision: String? = nil
    ) {
        self.id = id
        self.title = title
        self.titleAvailability = body == nil ? "native_display" : "full_native_body"
        self.displayTitle = displayTitle
        self.tables = tables
        self.formatting = formatting
        self.body = body
        self.snippet = snippet
        self.folderID = folderID
        self.folderTitle = folderTitle
        self.accountID = accountID
        self.isPasswordProtected = isPasswordProtected
        self.isPinned = isPinned
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.revision = revision
    }
}

public struct NoteMutation: Sendable {
    public var title: String?
    public var body: String?
    public var folderID: String?

    public init(title: String? = nil, body: String? = nil, folderID: String? = nil) {
        self.title = title
        self.body = body
        self.folderID = folderID
    }
}

/// A note without its body: cheap to list for hundreds of notes.
public struct NoteSummarySnapshot: Sendable {
    public let id: String
    /// Native list title (may be shortened by Notes for very long first lines).
    public let title: String
    public let snippet: String?
    public let folderID: String
    public let folderTitle: String
    public let accountID: String
    public let isLocked: Bool
    public let isPinned: Bool
    public let isInRecentlyDeleted: Bool
    public let creationDate: Date?
    public let modificationDate: Date?

    public init(
        id: String, title: String, snippet: String?, folderID: String, folderTitle: String, accountID: String,
        isLocked: Bool, isPinned: Bool, isInRecentlyDeleted: Bool, creationDate: Date?, modificationDate: Date?
    ) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.folderID = folderID
        self.folderTitle = folderTitle
        self.accountID = accountID
        self.isLocked = isLocked
        self.isPinned = isPinned
        self.isInRecentlyDeleted = isInRecentlyDeleted
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }
}

/// One note with its body read into paragraphs. Locked notes have no content or revision.
public struct NoteDetailSnapshot: Sendable {
    public let summary: NoteSummarySnapshot
    /// Full title (first body line) when the body is readable.
    public let title: String
    public let content: NoteContent?
    public let revision: String?
    public let tags: [String]
    public let attachments: [NoteAttachmentSnapshot]
}

public struct NoteAttachmentSnapshot: Sendable, Equatable {
    public let id: String
    public let kind: String
    public let name: String?
    /// Web address for link attachments.
    public let url: String?
    /// Local file of the attachment's media inside the Notes container, when present on disk.
    public let path: String?
    public let byteCount: Int?
}

public struct NoteTagSnapshot: Sendable, Equatable {
    public let name: String
    public let noteCount: Int
}

public struct NoteSearchHit: Sendable {
    public let summary: NoteSummarySnapshot
    public let excerpt: String?
}
