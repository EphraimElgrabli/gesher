import Foundation
import XCTest

@testable import GesherPlatform

final class LocalFilePolicyTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/qa")

    func refusal(_ path: String) -> String? {
        LocalFilePolicy.refusal(URL(fileURLWithPath: path), home: home)
    }

    func testRegularUserFilesAreAllowed() {
        for path in [
            "/Users/qa/Desktop/receipt.pdf", "/Users/qa/Documents/Trip/map.png", "/Users/qa/Downloads/notes.txt",
            "/Users/qa/Library/Mobile Documents/com~apple~CloudDocs/plan.key.pdf", "/Volumes/USB/photo.jpg",
            "/Users/Shared/flyer.png", "/private/var/folders/ab/T/upload.png", "/tmp/scan.jpg",
        ] {
            XCTAssertNil(refusal(path), path)
        }
    }

    func testHiddenAndLibraryPathsAreRefused() {
        for path in [
            "/Users/qa/.ssh/id_ed25519.pub", "/Users/qa/.aws/config", "/Users/qa/.config/gh/hosts.yml",
            "/Users/qa/.zshrc", "/Users/qa/project/.env", "/Users/qa/project/.git/config",
            "/Users/qa/Library/Keychains/login.keychain-db", "/Users/qa/Library/Application Support/x.db",
            "/Users/qa/Library/Mobile Documents/other/file.txt",
        ] {
            XCTAssertNotNil(refusal(path), path)
        }
    }

    func testCredentialFilesAreRefusedAnywhere() {
        for path in [
            "/Users/qa/Desktop/id_rsa", "/Users/qa/Desktop/server.pem", "/Users/qa/Desktop/cert.p12",
            "/Users/qa/Documents/passwords.kdbx", "/Users/qa/Downloads/credentials.json",
            "/Users/qa/Desktop/AuthKey_ABC.p8",
        ] {
            XCTAssertNotNil(refusal(path), path)
        }
    }

    func testSystemAndOtherUsersFilesAreRefused() {
        for path in [
            "/etc/hosts", "/private/etc/master.passwd", "/Library/Keychains/System.keychain", "/Users/b/a.txt",
        ] {
            XCTAssertNotNil(refusal(path), path)
        }
    }

    func testExportDirectories() throws {
        func folder(_ path: String) -> String? {
            LocalFilePolicy.refusal(URL(fileURLWithPath: path, isDirectory: true), home: home, file: false)
        }
        XCTAssertNil(folder("/Users/qa/Downloads"))
        XCTAssertNil(folder("/Users/qa/Desktop/id_cards"))
        for path in ["/Users/qa/Library/LaunchAgents", "/Users/qa/.config", "/Users/qa/.ssh", "/etc", "/Users/b"] {
            XCTAssertNotNil(folder(path), path)
        }
        XCTAssertThrowsError(try LocalFilePolicy.exportDirectory("~/Library/LaunchAgents")) {
            XCTAssertEqual(($0 as? AgentError)?.code, "file_not_allowed")
            XCTAssertEqual(($0 as? AgentError)?.exitCode, 64)
        }
    }

    func testAttachableResolvesSymlinksAndReportsCode() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("policy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let secretFolder = root.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: secretFolder, withIntermediateDirectories: true)
        let secret = secretFolder.appendingPathComponent("key.txt")
        try Data("x".utf8).write(to: secret)
        let plain = root.appendingPathComponent("photo.txt")
        try Data("x".utf8).write(to: plain)
        let link = root.appendingPathComponent("innocent.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: secret)

        XCTAssertEqual(try LocalFilePolicy.attachable(plain.path, home: root).lastPathComponent, "photo.txt")
        XCTAssertThrowsError(try LocalFilePolicy.attachable(link.path, home: root)) {
            XCTAssertEqual(($0 as? AgentError)?.code, "file_not_allowed")
        }
        XCTAssertThrowsError(try LocalFilePolicy.attachable(root.appendingPathComponent("missing.txt").path)) {
            XCTAssertEqual(($0 as? AgentError)?.code, "invalid_argument")
        }
        XCTAssertThrowsError(try LocalFilePolicy.attachable(root.path)) {
            XCTAssertEqual(($0 as? AgentError)?.code, "invalid_argument")
        }
    }
}

final class PrivateStorageTests: XCTestCase {
    func testBackupsAreReadableOnlyByTheUser() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("private-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("backups")
        try PrivateStorage.createDirectory(folder)
        let file = folder.appendingPathComponent("b.json")
        try PrivateStorage.write(Data("{}".utf8), to: file)
        func mode(_ url: URL) throws -> Int {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
        }
        XCTAssertEqual(try mode(folder), 0o700)
        XCTAssertEqual(try mode(file), 0o600)
    }
}
