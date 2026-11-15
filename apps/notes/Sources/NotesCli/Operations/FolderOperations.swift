import GesherKit
import GesherPlatform
import Foundation
import NotesCore

enum ListAccounts: AgentOperation {
    static let path = ["account", "list"]
    static let summary = "List Notes accounts (iCloud, On My Mac, ...); the default one is marked."
    static let params: [Param] = []
    static let examples = ["account list"]

    static func run(_ input: NoInput, _ context: NotesContext) throws -> [String: [AccountOut]] {
        ["accounts": try context.read.fetchAccounts().map(AccountOut.init)]
    }
}

enum ListFolders: AgentOperation {
    struct Input: Decodable, Sendable {
        var account: String?
    }

    static let path = ["folder", "list"]
    static let summary =
        "List folders with note counts, nesting paths, smart folders and Recently Deleted."
    static let params: [Param] = [.string("account", "Only folders of this account (name or id).")]
    static let examples = ["folder list", "folder list --account iCloud"]

    static func run(_ input: Input, _ context: NotesContext) throws -> [String: [FolderOut]] {
        var folders = try context.read.fetchFolders()
        if let selector = input.account {
            let account = try EntityResolver.resolve(
                selector, in: context.read.fetchAccounts(), type: "account", id: \.id, name: \.title)
            folders = folders.filter { $0.accountID == account.id }
        }
        let paths = FolderPaths(folders)
        return ["folders": folders.map { FolderOut($0, paths: paths) }]
    }
}

/// Batch: several folders in one call, each created and verified independently.
enum CreateFolders: AgentOperation {
    struct Input: Decodable, Sendable {
        var name: [String]
        var parent: String?
        var account: String?
    }

    static let path = ["folder", "create"]
    static let summary = "Create one or more folders, optionally inside a parent folder."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .list("name", "Folder names to create.", required: true, positional: true),
        .string("parent", "Parent folder (name, 'Parent/Child' path or id). Default: top level."),
        .string("account", "Account for top-level folders (name or id). Default: the default account."),
    ]
    static let examples = ["folder create Recipes", "folder create 'Q1' 'Q2' --parent Work"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<FolderOut> {
        let parent = try input.parent.map { try context.folder($0) }
        let account = try input.account.map { selector in
            try EntityResolver.resolve(
                selector, in: context.read.fetchAccounts(), type: "account", id: \.id, name: \.title)
        }
        return Batch.run(input.name, label: { $0 }) { name in
            FolderOut(try context.write.createFolder(title: name, accountID: account?.id, parentID: parent?.id))
        }
    }
}

enum RenameFolder: AgentOperation {
    struct Input: Decodable, Sendable {
        var folder: String
        var name: String
    }

    static let path = ["folder", "rename"]
    static let summary = "Rename a folder."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("folder", "Folder name, path or id.", required: true, positional: true),
        .string("name", "New name.", required: true),
    ]
    static let examples = ["folder rename Recipes --name Cooking"]

    static func run(_ input: Input, _ context: NotesContext) throws -> FolderOut {
        let folder = try context.folder(input.folder, policy: .exactName)
        return FolderOut(try context.write.renameFolder(id: folder.id, title: input.name))
    }
}

enum MoveFolder: AgentOperation {
    struct Input: Decodable, Sendable {
        var folder: String
        var parent: String?
    }

    static let path = ["folder", "move"]
    static let summary = "Move a folder into another folder of the same account, or to the top level."
    static let effect = OperationEffect.write
    static let idempotent = true
    static let params: [Param] = [
        .string("folder", "Folder name, path or id.", required: true, positional: true),
        .string("parent", "New parent folder. Omit to move the folder to the top level."),
    ]
    static let examples = ["folder move Q1 --parent Archive", "folder move Archive/Q1"]

    static func run(_ input: Input, _ context: NotesContext) throws -> FolderOut {
        let folder = try context.folder(input.folder, policy: .exactName)
        let parent = try input.parent.map { try context.folder($0) }
        let moved = try context.write.moveFolder(id: folder.id, parentID: parent?.id)
        return FolderOut(moved, paths: FolderPaths(try context.read.fetchFolders()))
    }
}

/// Batch, destructive: exact names or ids only. Notes inside go to Recently Deleted first.
enum DeleteFolders: AgentOperation {
    struct Input: Decodable, Sendable {
        var folder: [String]
    }

    static let path = ["folder", "delete"]
    static let summary =
        "Delete folders by exact name or id; their notes move to Recently Deleted (a smart folder's notes stay). "
        + "Folders with subfolders are refused."
    static let effect = OperationEffect.destructive
    static let params: [Param] = [
        .list("folder", "Folder names, paths or ids.", required: true, positional: true)
    ]
    static let examples = ["folder delete 'Old ideas'"]

    static func run(_ input: Input, _ context: NotesContext) throws -> BatchResult<DeletedFolder> {
        Batch.run(input.folder, label: { $0 }) { selector in
            let folder = try context.folder(selector, policy: .exactName)
            let moved = try context.write.deleteFolder(id: folder.id)
            return DeletedFolder(id: folder.id, name: folder.title, notesMovedToRecentlyDeleted: moved)
        }
    }
}

enum CreateSmartFolder: AgentOperation {
    struct Input: Decodable, Sendable {
        var name: String
        var tags: [String]
        var match: String
        var account: String?
    }

    static let path = ["smart-folder", "create"]
    static let summary =
        "Create a smart folder that shows notes with given tags (all or any); delete it with folder_delete."
    static let effect = OperationEffect.write
    static let params: [Param] = [
        .string("name", "Smart folder name.", required: true, positional: true),
        .list("tags", "Existing tags, with or without '#'.", required: true),
        .choice("match", ["all", "any"], "Notes need all of the tags, or any.", default: "any"),
        .string("account", "Account (name or id). Default: the default account."),
    ]
    static let examples = ["smart-folder create Travel --tags travel --tags trips --match any"]

    static func run(_ input: Input, _ context: NotesContext) throws -> FolderOut {
        let account = try input.account.map { selector in
            try EntityResolver.resolve(
                selector, in: context.read.fetchAccounts(), type: "account", id: \.id, name: \.title)
        }
        return FolderOut(
            try context.write.createSmartFolder(
                title: input.name, tags: input.tags, matchAll: input.match == "all", accountID: account?.id))
    }
}
