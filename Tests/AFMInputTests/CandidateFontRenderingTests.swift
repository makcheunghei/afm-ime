import AppKit
import SwiftUI
import Testing
import IMECore
@testable import afm_input

/// ImageRenderer 只繪製離屏影像，不開啟視窗或控制使用者輸入。
@Suite(.serialized)
@MainActor
struct CandidateFontRenderingTests {
    @Test func extendedCandidatesRenderInBothLayouts() throws {
        let dictionary = try QuickDictionary(url: URL(fileURLWithPath: "Data/quick.json"))
        let items = dictionary.candidates(for: "ap", fullCharset: true).enumerated().map {
            CandidateItem(index: $0.offset, text: $0.element, isAI: false)
        }
        for layout in QuickCandidateLayout.allCases {
            for start in [9, 18] {
                let view = QuickCandidateView(items: items, selectedIndex: start + 6, pageStart: start, pageSize: 9,
                    association: false, layout: layout, maximumWidth: 1000, fontSize: 15, onSelect: { _ in })
                    .background(Color.white).environment(\.colorScheme, .light)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                #expect(image.width > 0 && image.height > 0)
                if let folder = ProcessInfo.processInfo.environment["AFM_CANDIDATE_RENDER_DIR"] {
                    let url = URL(fileURLWithPath: folder).appendingPathComponent("ap-\(layout.rawValue)-page-\(start / 9 + 1).png")
                    let data = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
                    try data.write(to: url)
                }
            }
        }
    }
}
