import Foundation

public enum InputMethodMode: String, CaseIterable {
    case pinyin
    case quick

    public var sourceID: String {
        switch self {
        case .pinyin: return "moe.bemly.inputmethod.AfmIME.afmpinyin.hans"
        case .quick: return "moe.bemly.inputmethod.AfmIME.afmquick.hant"
        }
    }

    public var displayName: String { self == .quick ? "AFM速成" : "AFM拼音" }
    public static func from(sourceID: String) -> InputMethodMode? {
        allCases.first { $0.sourceID == sourceID }
    }
}
