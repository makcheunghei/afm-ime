import Foundation

/// 速成的開關獨立於拼音；設定中心寫入 IME 的 defaults domain。
public enum QuickPrefs {
    public static let fullCharsetKey = "AFMQuickFullCharsetEnabled"
    public static let learningKey = "AFMQuickLearningEnabled"
    public static let aiKey = "AFMQuickAIEnabled"
    public static let cloudKey = "AFMQuickCloudEnabled"
    public static let learningDataKey = "AFMQuickUserCounts"

    public static var fullCharsetEnabled: Bool { UserDefaults.standard.bool(forKey: fullCharsetKey) }
    public static var learningEnabled: Bool { UserDefaults.standard.bool(forKey: learningKey) }
    public static var aiEnabled: Bool { UserDefaults.standard.bool(forKey: aiKey) }
    public static var cloudEnabled: Bool { UserDefaults.standard.bool(forKey: cloudKey) }
}
