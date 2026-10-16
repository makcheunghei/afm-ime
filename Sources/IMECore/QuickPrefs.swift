import Foundation

public enum QuickCandidateLayout: String, CaseIterable, Identifiable {
    case vertical, horizontal
    public var id: String { rawValue }
    public var title: String { self == .vertical ? "直排" : "橫排" }
}

/// 速成的開關獨立於拼音；設定中心寫入 IME 的 defaults domain。
public enum QuickPrefs {
    public static let fullCharsetKey = "AFMQuickFullCharsetEnabled"
    public static let learningKey = "AFMQuickLearningEnabled"
    public static let aiKey = "AFMQuickAIEnabled"
    public static let cloudKey = "AFMQuickCloudEnabled"
    public static let translationCloudKey = "AFMQuickTranslationCloudEnabled"
    public static let learningDataKey = "AFMQuickUserCounts"
    public static let candidateLayoutKey = "AFMQuickCandidateLayout"
    public static let appearanceChanged = Notification.Name("moe.bemly.AfmIME.quickAppearanceChanged")

    public static func candidateLayout(defaults: UserDefaults = .standard) -> QuickCandidateLayout {
        QuickCandidateLayout(rawValue: defaults.string(forKey: candidateLayoutKey) ?? "") ?? .vertical
    }

    public static func postAppearanceChange() {
        DistributedNotificationCenter.default().postNotificationName(appearanceChanged,
            object: nil, userInfo: nil, deliverImmediately: true)
    }

    public static var fullCharsetEnabled: Bool { UserDefaults.standard.bool(forKey: fullCharsetKey) }
    public static var learningEnabled: Bool { UserDefaults.standard.bool(forKey: learningKey) }
    public static var aiEnabled: Bool { UserDefaults.standard.bool(forKey: aiKey) }
    public static var cloudEnabled: Bool { UserDefaults.standard.bool(forKey: cloudKey) }
    public static var translationCloudEnabled: Bool { UserDefaults.standard.bool(forKey: translationCloudKey) }
}
