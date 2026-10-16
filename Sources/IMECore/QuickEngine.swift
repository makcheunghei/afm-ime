import Foundation

/// Exact-code lookup and optional, per-code user ordering for Quick candidates.
public final class QuickEngine {
    private let dictionary: QuickDictionary
    private let learningStore: QuickLearningStore
    public var roots: [String: String] { dictionary.roots }

    public init(dictionary: QuickDictionary, defaults: UserDefaults = .standard, learningStore: QuickLearningStore? = nil) {
        self.dictionary = dictionary
        self.learningStore = learningStore ?? QuickLearningStore(defaults: defaults)
    }

    public func candidates(for code: String, fullCharset: Bool = false, learning: Bool = false) -> [String] {
        let original = dictionary.candidates(for: code, fullCharset: fullCharset)
        guard learning, !original.isEmpty else { return original }
        let codeCounts = learningStore.counts(for: code)
        guard !codeCounts.isEmpty else { return original }

        let positions = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1, $0) })
        return original.sorted { lhs, rhs in
            let leftCount = codeCounts[lhs] ?? 0
            let rightCount = codeCounts[rhs] ?? 0
            let leftLearned = leftCount > 0
            let rightLearned = rightCount > 0
            if leftLearned != rightLearned { return leftLearned }
            if !leftLearned { return positions[lhs, default: 0] < positions[rhs, default: 0] }
            if leftCount != rightCount { return leftCount > rightCount }
            return positions[lhs, default: 0] < positions[rhs, default: 0]
        }
    }

    public func associations(after text: String) -> [String] {
        dictionary.associations(after: text)
    }

    public func recordSelection(code: String, text: String, enabled: Bool) {
        guard enabled else { return }
        guard QuickDictionary.isCode(code),
              (dictionary.candidates(for: code).contains(text)
                || dictionary.candidates(for: code, fullCharset: true).contains(text)) else { return }

        learningStore.record(code: code, text: text)
    }
}
