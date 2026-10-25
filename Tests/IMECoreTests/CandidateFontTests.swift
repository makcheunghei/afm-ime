import AppKit
import CoreText
import Testing
@testable import IMECore

struct CandidateFontTests {
    @Test func apExtendedCharactersHaveRealGlyphsInBothWeights() {
        for weight in [NSFont.Weight.regular, .semibold] {
            let font = CandidateFont.system(size: 15, weight: weight)
            let text = "昆匙悶曬昵曨恳惖巼昽𨳍𨶙㦔㫐㬩𢘇𢙶𢛝𢛩𢜏𢟪𢠶𢡙𢡥𢢤𢣮𢤃𣅒𣅪𣅬𣅸𣇌𣇤𣈀𣌫𣍑𧂓𨳶𨳷𨴥𨴮𨵖𨶃𨶡"
            #expect(missingGlyphs(text, font: font).isEmpty)
            let normal = glyphRuns("懸香港 ABC", font: font)
            #expect(normal.allSatisfy { !fontName($0).contains("HanaMin") })
        }
    }

    @Test func entireQuickDictionaryHasNoPlaceholderGlyphs() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "Data/quick.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var scalars = Set<Unicode.Scalar>()
        for key in ["candidates", "fullCandidates", "associations"] {
            let map = try #require(json[key] as? [String: [String]])
            for words in map.values { for word in words { scalars.formUnion(word.unicodeScalars) } }
        }
        let text = String(String.UnicodeScalarView(scalars.sorted { $0.value < $1.value }))
        for weight in [NSFont.Weight.regular, .semibold] {
            let missing = missingGlyphs(text, font: CandidateFont.system(size: 15, weight: weight))
            #expect(missing.isEmpty, "缺少字形：\(missing.unicodeScalars.prefix(20).map { String(format: "U+%X", $0.value) })")
        }
    }

    private func glyphRuns(_ text: String, font: NSFont) -> [CTRun] {
        CTLineGetGlyphRuns(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))) as! [CTRun]
    }

    private func fontName(_ run: CTRun) -> String {
        let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
        return CTFontCopyPostScriptName(font) as String
    }

    private func missingGlyphs(_ text: String, font: NSFont) -> String {
        var missing = ""
        for run in glyphRuns(text, font: font) {
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            if fontName(run).contains("LastResort") || glyphs.contains(0) {
                let range = CTRunGetStringRange(run)
                missing += (text as NSString).substring(with: NSRange(location: range.location, length: range.length))
            }
        }
        return missing
    }
}
