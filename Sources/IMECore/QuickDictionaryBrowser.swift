import Foundation

public enum QuickDictionarySection: String, CaseIterable {
    case codes
    case associations
}

public struct QuickDictionaryRow: Identifiable, Equatable {
    public let key: String
    public let roots: String
    public let text: String
    public let position: Int
    public let id: String

    public init(section: QuickDictionarySection, key: String, roots: String, text: String, position: Int) {
        self.key = key
        self.roots = roots
        self.text = text
        self.position = position
        self.id = "\(section.rawValue)\u{1F}\(key)\u{1F}\(text)"
    }
}

public struct QuickDictionaryPage {
    public let rows: [QuickDictionaryRow]
    public let totalCount: Int
    public let pageCount: Int

    public init(rows: [QuickDictionaryRow], totalCount: Int, pageCount: Int) {
        self.rows = rows
        self.totalCount = totalCount
        self.pageCount = pageCount
    }
}

public final class QuickDictionaryBrowser {
    private let dictionary: QuickDictionary
    private var cachedRows: [String: [QuickDictionaryRow]] = [:]

    public init(dictionary: QuickDictionary) { self.dictionary = dictionary }

    public func page(
        section: QuickDictionarySection,
        fullCharset: Bool,
        search: String,
        page: Int,
        pageSize: Int = 100
    ) -> QuickDictionaryPage {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheKey = section == .associations ? "associations" : (fullCharset ? "full" : "windows")
        let allRows: [QuickDictionaryRow]
        if let cached = cachedRows[cacheKey] {
            allRows = cached
        } else {
        switch section {
        case .codes:
            let keys = fullCharset ? Set(dictionary.candidates.keys).union(dictionary.fullCandidates.keys) : Set(dictionary.candidates.keys)
            allRows = keys.sorted().flatMap { key in
                dictionary.candidates(for: key, fullCharset: fullCharset).enumerated().map { index, text in
                    QuickDictionaryRow(section: .codes, key: key, roots: key.map { dictionary.roots[String($0)] ?? "" }.joined(), text: text, position: index + 1)
                }
            }
        case .associations:
            allRows = dictionary.associationData.keys.sorted().flatMap { key in
                (dictionary.associationData[key] ?? []).enumerated().map { index, text in
                    QuickDictionaryRow(section: .associations, key: key, roots: key.map { dictionary.roots[String($0)] ?? "" }.joined(), text: text, position: index + 1)
                }
            }
        }
        cachedRows[cacheKey] = allRows
        }

        let filtered = allRows.filter { row in
            guard !query.isEmpty else { return true }
            if query.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) {
                let lower = query.lowercased()
                if section == .codes { return row.key.hasPrefix(lower) }
                return row.key.hasPrefix(lower) || row.text.localizedCaseInsensitiveContains(query)
            }
            if section == .associations { return row.key.contains(query) || row.text.contains(query) }
            return row.text.contains(query)
        }
        let size = max(1, pageSize)
        let pageCount = max(1, filtered.count / size + (filtered.count % size == 0 ? 0 : 1))
        let safePage = max(0, page)
        let start = min(filtered.count, safePage.multipliedReportingOverflow(by: size).overflow ? filtered.count : safePage * size)
        let end = start + min(size, filtered.count - start)
        return QuickDictionaryPage(rows: Array(filtered[start..<end]), totalCount: filtered.count, pageCount: pageCount)
    }
}
