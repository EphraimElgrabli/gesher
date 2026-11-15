import Foundation

/// Text normalization for human selectors: case, diacritics (including Hebrew niqqud and
/// cantillation), width, bidi/format characters, emoji and punctuation are ignored.
public enum NameMatcher {
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var scalars = String.UnicodeScalarView()
        for scalar in folded.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark, .format, .control:
                continue
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                .initialPunctuation, .finalPunctuation, .otherPunctuation, .mathSymbol, .currencySymbol,
                .modifierSymbol, .otherSymbol, .spaceSeparator, .lineSeparator, .paragraphSeparator:
                scalars.append(" ")
            default:
                if scalar.properties.isEmojiPresentation || scalar == "\u{FE0F}" {
                    scalars.append(" ")
                } else {
                    scalars.append(scalar)
                }
            }
        }
        return String(scalars).split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
    }

    /// Edit distance on normalized text, used only to rank "did you mean" suggestions.
    public static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// How far a name selector may be relaxed.
public enum MatchPolicy: Sendable {
    /// id, exact name, then normalized-equal name. Use for destructive operations.
    case exactName
    /// Additionally unique normalized prefix, then all-words / substring match. Default.
    case fuzzy
}

/// Resolves a human selector (a name or an id) to one entity.
///
/// Tiers are tried in order; the first tier with exactly one match wins, a tier with several
/// matches fails with `ambiguous` and the candidates, and no match fails with `not_found` and
/// the closest suggestions:
/// 1. exact id  2. exact name  3. normalized name  4. normalized prefix  5. all words / substring
public enum EntityResolver {
    public static func resolve<Entity>(
        _ selector: String, in entities: [Entity], type: String,
        id: (Entity) -> String, name: (Entity) -> String, detail: ((Entity) -> String?)? = nil,
        policy: MatchPolicy = .fuzzy
    ) throws -> Entity {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AgentError.invalid("The \(type) selector is empty.") }
        func candidate(_ entity: Entity) -> Candidate {
            Candidate(id: id(entity), name: name(entity), detail: detail?(entity))
        }
        if let exact = entities.first(where: { id($0) == trimmed }) { return exact }
        let query = NameMatcher.normalize(trimmed)
        let names = entities.map { NameMatcher.normalize(name($0)) }
        let words = query.split(separator: " ").map(String.init)
        let rawNames = entities.map(name)
        let tierCount = policy == .fuzzy && !query.isEmpty ? 4 : 2
        for tier in 0..<tierCount {
            let matches = entities.indices.filter { index in
                switch tier {
                case 0: return rawNames[index] == trimmed
                case 1: return !query.isEmpty && names[index] == query
                case 2: return names[index].hasPrefix(query)
                default:
                    let nameWords = names[index].split(separator: " ")
                    return names[index].contains(query)
                        || words.allSatisfy { word in nameWords.contains { $0.hasPrefix(word) } }
                }
            }
            if matches.count == 1 { return entities[matches[0]] }
            if matches.count > 1 {
                throw AgentError.ambiguous(type, trimmed, candidates: matches.map { candidate(entities[$0]) })
            }
        }
        throw AgentError.notFound(type, trimmed, suggestions: suggestions(query, entities, names, candidate))
    }

    /// Resolves several selectors, failing on the first unresolvable one. Duplicates collapse.
    public static func resolveAll<Entity>(
        _ selectors: [String], in entities: [Entity], type: String,
        id: (Entity) -> String, name: (Entity) -> String, detail: ((Entity) -> String?)? = nil,
        policy: MatchPolicy = .fuzzy
    ) throws -> [Entity] {
        var seen = Set<String>()
        return try selectors.compactMap { selector in
            let entity = try resolve(
                selector, in: entities, type: type, id: id, name: name, detail: detail, policy: policy)
            return seen.insert(id(entity)).inserted ? entity : nil
        }
    }

    private static func suggestions<Entity>(
        _ query: String, _ entities: [Entity], _ names: [String], _ candidate: (Entity) -> Candidate
    ) -> [Candidate] {
        if entities.count <= 8 { return entities.map(candidate) }
        let ranked = entities.indices.map { ($0, NameMatcher.distance(query, names[$0])) }
            .filter { $0.1 <= max(2, query.count / 2) }
            .sorted { $0.1 < $1.1 }
        return ranked.prefix(5).map { candidate(entities[$0.0]) }
    }
}
