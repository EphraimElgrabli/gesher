import GesherPlatform
import Foundation

public enum NoteDocumentDecoder {
    private static let documentAllowedKeys: Set<String> = ["paragraphs"]
    private static let paragraphAllowedKeys: Set<String> = [
        "style", "runs", "checked", "indent", "table", "quote",
    ]
    private static let runAllowedKeys: Set<String> = [
        "text", "bold", "italic", "underline", "strikethrough", "link", "highlight",
    ]

    public static func validateUnknownKeys(in data: Data) throws {
        guard !data.isEmpty else {
            throw PlatformError.invalidArgument("Document data is empty.")
        }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw PlatformError.invalidArgument("Invalid JSON document: \(error.localizedDescription)")
        }

        guard let docDict = json as? [String: Any] else {
            throw PlatformError.invalidArgument("Document JSON root must be an object with a 'paragraphs' array.")
        }

        let unknownDocKeys = Set(docDict.keys).subtracting(documentAllowedKeys)
        if let unknown = unknownDocKeys.sorted().first {
            throw PlatformError.invalidArgument("Unknown document property '\(unknown)'.")
        }

        guard let paragraphs = docDict["paragraphs"] as? [Any] else {
            throw PlatformError.invalidArgument("Property 'paragraphs' must be an array.")
        }

        for (pIndex, pItem) in paragraphs.enumerated() {
            guard let pDict = pItem as? [String: Any] else {
                throw PlatformError.invalidArgument("Paragraph at index \(pIndex) must be an object.")
            }
            let unknownPKeys = Set(pDict.keys).subtracting(paragraphAllowedKeys)
            if let unknown = unknownPKeys.sorted().first {
                throw PlatformError.invalidArgument(
                    "Unknown paragraph property '\(unknown)' at paragraph index \(pIndex)."
                )
            }

            if let runs = pDict["runs"] as? [Any] {
                for (rIndex, rItem) in runs.enumerated() {
                    guard let rDict = rItem as? [String: Any] else {
                        throw PlatformError.invalidArgument(
                            "Run at paragraph \(pIndex), run \(rIndex) must be an object."
                        )
                    }
                    let unknownRKeys = Set(rDict.keys).subtracting(runAllowedKeys)
                    if let unknown = unknownRKeys.sorted().first {
                        throw PlatformError.invalidArgument(
                            "Unknown run property '\(unknown)' at paragraph \(pIndex), run \(rIndex)."
                        )
                    }
                }
            }
        }
    }

    public static func decode(from data: Data) throws -> NoteDocument {
        guard !data.isEmpty else {
            throw PlatformError.invalidArgument("Document data is empty.")
        }
        try validateUnknownKeys(in: data)
        let decoder = JSONDecoder()
        let document: NoteDocument
        do {
            document = try decoder.decode(NoteDocument.self, from: data)
        } catch {
            throw PlatformError.invalidArgument("Document decoding failed: \(error.localizedDescription)")
        }
        try document.validate()
        return document
    }
}
