import AppKit
import CoreText

/// 保留系統的香港中文字形，只為系統缺少的擴展漢字補上 App 內後備字型。
/// 字型只登記於目前程序，不安裝或更改其他應用程式的字型。
public enum CandidateFont {
    private struct Key: Hashable {
        let size: CGFloat
        let weight: CGFloat
    }
    private static let lock = NSLock()
    private static var cache: [Key: NSFont] = [:]

    private static let fallback: CTFontDescriptor? = {
        let relative = "Fonts/HanaMinB.ttf"
        let urls = [
            Bundle.main.resourceURL?.appendingPathComponent(relative),
            // 設定中心在引擎 Contents/PlugIns 內，與引擎共用一份字型檔案。
            Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Contents/Resources/" + relative),
            URL(fileURLWithPath: "Data/" + relative),
        ].compactMap { $0 }
        guard let url = urls.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            DebugLog.error("候選後備字型缺失")
            return nil
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return descriptor
    }()

    public static func system(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(size: size, weight: weight.rawValue)
        if let font = cache[key] { return font }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let fallback else { return base }
        let defaults = CTFontCopyDefaultCascadeListForLanguages(base as CTFont, ["zh-HK"] as CFArray)
            as? [CTFontDescriptor] ?? []
        let cascade = defaults.filter {
            let name = CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String ?? ""
            return !name.contains("LastResort")
        } + [fallback]
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontCascadeListAttribute: cascade] as CFDictionary)
        let font = CTFontCreateCopyWithAttributes(base as CTFont, size, nil, descriptor) as NSFont
        cache[key] = font
        return font
    }
}
