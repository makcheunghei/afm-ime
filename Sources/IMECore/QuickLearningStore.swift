import Foundation
import CoreFoundation
import Darwin

public struct QuickLearningEntry: Identifiable, Equatable {
    public let code: String
    public let text: String
    public let count: Int

    public var id: String { "\(code)\u{1F}\(text)" }

    public init(code: String, text: String, count: Int) {
        self.code = code
        self.text = text
        self.count = count
    }
}

public struct QuickLearningImportResult: Equatable {
    public let added: Int
    public let updated: Int
    public let skipped: Int

    public init(added: Int, updated: Int, skipped: Int) {
        self.added = added
        self.updated = updated
        self.skipped = skipped
    }
}

public enum QuickLearningImportError: Error, LocalizedError {
    case invalidDocument
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidDocument: return "請使用 version 為 1、mode 為 quick，並包含 selections 陣列的速成記錄檔。"
        case .storageUnavailable: return "未能儲存速成學習記錄，請稍後再試。"
        }
    }
}

/// Cross-process serialized storage for Quick selection counts.
public final class QuickLearningStore {
    private let defaults: UserDefaults
    private let lockURL: URL

    public init(defaults: UserDefaults = .standard, lockURL: URL? = nil) {
        self.defaults = defaults
        if let lockURL {
            self.lockURL = lockURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.lockURL = support.appendingPathComponent("AFM輸入法", isDirectory: true)
                .appendingPathComponent("quick-learning.lock")
        }
    }

    public func entries() -> [QuickLearningEntry] {
        withLockedStorage { values in
            values.flatMap { code, texts in
                texts.map { QuickLearningEntry(code: code, text: $0.key, count: $0.value) }
            }.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                if $0.code != $1.code { return $0.code < $1.code }
                return $0.text < $1.text
            }
        } ?? []
    }

    public func counts(for code: String) -> [String: Int] {
        withLockedStorage { $0[code] ?? [:] } ?? [:]
    }

    @discardableResult
    public func record(code: String, text: String) -> Bool {
        guard QuickDictionary.isCode(code), !text.isEmpty else { return false }
        return withLockedStorage(write: true) { values in
            let old = values[code, default: [:]][text, default: 0]
            values[code, default: [:]][text] = old == Int.max ? Int.max : old + 1
            return true
        } ?? false
    }

    @discardableResult
    public func remove(code: String, text: String) -> Bool {
        withLockedStorage(write: true) { values in
            values[code]?.removeValue(forKey: text)
            if values[code]?.isEmpty == true { values.removeValue(forKey: code) }
            return true
        } ?? false
    }

    @discardableResult
    public func clear() -> Bool {
        withLockedStorage(write: true) { values in
            values.removeAll()
            return true
        } ?? false
    }

    public func importJSON(_ data: Data, dictionary: QuickDictionary) throws -> QuickLearningImportResult {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let document = object as? [String: Any],
              document["mode"] as? String == "quick",
              let version = document["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version.doubleValue == 1,
              let selections = document["selections"] as? [Any] else {
            throw QuickLearningImportError.invalidDocument
        }

        var parsed: [String: [String: Int]] = [:]
        var skipped = 0
        for item in selections {
            guard let row = item as? [String: Any],
                  let code = row["code"] as? String, QuickDictionary.isCode(code),
                  let text = row["text"] as? String, !text.isEmpty,
                  dictionary.candidates(for: code).contains(text)
                    || dictionary.candidates(for: code, fullCharset: true).contains(text),
                  let rawCount = row["count"] as? NSNumber,
                  let count = Self.positiveInteger(rawCount) else {
                skipped += 1
                continue
            }
            if parsed[code]?[text] != nil { skipped += 1 }
            parsed[code, default: [:]][text] = max(parsed[code]?[text] ?? 0, count)
        }

        guard let result = withLockedStorage(write: true, { values -> QuickLearningImportResult in
            var added = 0
            var updated = 0
            for (code, texts) in parsed {
                for (text, count) in texts {
                    let old = values[code]?[text]
                    if let old {
                        if count > old {
                            values[code, default: [:]][text] = count
                            updated += 1
                        } else {
                            skipped += 1
                        }
                    } else {
                        values[code, default: [:]][text] = count
                        added += 1
                    }
                }
            }
            return QuickLearningImportResult(added: added, updated: updated, skipped: skipped)
        }) else { throw QuickLearningImportError.storageUnavailable }
        return result
    }

    private func withLockedStorage<T>(write: Bool = false, _ body: (inout [String: [String: Int]]) -> T) -> T? {
        let directory = lockURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { return nil }
        defer { _ = flock(descriptor, LOCK_UN) }

        guard defaults.synchronize() else { return nil }
        var values = Self.validStorage(defaults.object(forKey: QuickPrefs.learningDataKey))
        let result = body(&values)
        if write {
            defaults.set(values, forKey: QuickPrefs.learningDataKey)
            guard defaults.synchronize() else { return nil }
        }
        return result
    }

    private static func validStorage(_ object: Any?) -> [String: [String: Int]] {
        guard let raw = object as? [String: Any] else { return [:] }
        var result: [String: [String: Int]] = [:]
        for (code, value) in raw where QuickDictionary.isCode(code) {
            guard let rawTexts = value as? [String: Any] else { continue }
            var texts: [String: Int] = [:]
            for (text, rawCount) in rawTexts {
                guard !text.isEmpty, let number = rawCount as? NSNumber,
                      let count = Self.nonnegativeInteger(number) else { continue }
                texts[text] = count
            }
            if !texts.isEmpty { result[code] = texts }
        }
        return result
    }

    private static func positiveInteger(_ number: NSNumber) -> Int? {
        guard let value = nonnegativeInteger(number), value > 0 else { return nil }
        return value
    }

    private static func nonnegativeInteger(_ number: NSNumber) -> Int? {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let type = String(cString: number.objCType)
        guard ["c", "s", "i", "l", "q", "C", "S", "I", "L", "Q"].contains(type),
              let value = Int(number.stringValue), value >= 0 else { return nil }
        return value
    }
}
