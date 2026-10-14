import Foundation
import CoreFoundation

/// Immutable lookup data for the Quick (速成) input method.
public struct QuickDictionary {
    public let candidates: [String: [String]]
    public let fullCandidates: [String: [String]]
    public let associationData: [String: [String]]
    public let roots: [String: String]

    public init(
        candidates: [String: [String]],
        fullCandidates: [String: [String]] = [:],
        associations: [String: [String]] = [:],
        roots: [String: String] = [:]
    ) {
        self.candidates = Self.deduplicated(candidates)
        self.fullCandidates = Self.deduplicated(fullCandidates)
        self.associationData = Self.deduplicated(associations)
        self.roots = roots
    }

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let document = object as? [String: Any],
              let version = document["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version.doubleValue == 1,
              let rawCandidates = document["candidates"] else {
            throw QuickDictionaryError.invalidDocument
        }

        let candidates = try Self.readCandidateMap(rawCandidates, keyValidator: Self.isCode)
        let full: [String: [String]]
        if let rawFull = document["fullCandidates"] {
            full = try Self.readCandidateMap(rawFull, keyValidator: Self.isCode)
        } else {
            full = candidates
        }
        let associations: [String: [String]]
        if let rawAssociations = document["associations"] {
            associations = try Self.readCandidateMap(rawAssociations, keyValidator: { !$0.isEmpty })
        } else {
            associations = [:]
        }
        let roots: [String: String]
        if let rawRoots = document["roots"] {
            guard let map = rawRoots as? [String: Any] else { throw QuickDictionaryError.invalidDocument }
            var parsed: [String: String] = [:]
            for (letter, glyph) in map {
                guard Self.isRootLetter(letter), let glyph = glyph as? String, !glyph.isEmpty else {
                    throw QuickDictionaryError.invalidDocument
                }
                parsed[letter] = glyph
            }
            roots = parsed
        } else {
            roots = [:]
        }

        self.candidates = candidates
        self.fullCandidates = full
        self.associationData = associations
        self.roots = roots
    }

    public func candidates(for code: String, fullCharset: Bool = false) -> [String] {
        guard Self.isCode(code) else { return [] }
        if fullCharset, let values = fullCandidates[code] { return values }
        return candidates[code] ?? []
    }

    public func associations(after prefix: String) -> [String] {
        associationData[prefix] ?? []
    }

    public static func isCode(_ code: String) -> Bool {
        let bytes = code.utf8
        return (1...2).contains(bytes.count) && bytes.allSatisfy { (97...122).contains($0) }
    }

    private static func isRootLetter(_ value: String) -> Bool {
        value.utf8.count == 1 && value.utf8.first.map { (97...122).contains($0) } == true
    }

    private static func readCandidateMap(
        _ value: Any,
        keyValidator: (String) -> Bool
    ) throws -> [String: [String]] {
        guard let map = value as? [String: Any] else { throw QuickDictionaryError.invalidDocument }
        var result: [String: [String]] = [:]
        for (key, rawValues) in map {
            guard keyValidator(key), let values = rawValues as? [Any] else {
                throw QuickDictionaryError.invalidDocument
            }
            var strings: [String] = []
            for raw in values {
                guard let text = raw as? String, !text.isEmpty else {
                    throw QuickDictionaryError.invalidDocument
                }
                strings.append(text)
            }
            result[key] = stableUnique(strings)
        }
        return result
    }

    private static func deduplicated(_ map: [String: [String]]) -> [String: [String]] {
        map.mapValues(stableUnique)
    }

    private static func stableUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

public enum QuickDictionaryError: Error {
    case invalidDocument
}
