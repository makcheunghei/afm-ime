import Foundation

/// 翻譯覆蓋層不重建底下的速成組字；取消後保留候選、頁碼及高亮。
/// 不持有 UI 或模型 task，可直接用 QuickSession 驗證完整按鍵行為。
public final class QuickTranslationSession {
    public enum Phase: Equatable {
        case idle, loading, ready(String), failed
    }

    public struct Request: Equatable, Sendable {
        public let id: UInt64
        public let compositionGeneration: UInt64
        public let source: String
    }

    private let session: QuickSession
    private var nextID: UInt64 = 0
    public private(set) var request: Request?
    public private(set) var phase: Phase = .idle
    public var isActive: Bool { phase != .idle }

    public init(session: QuickSession) { self.session = session }

    @discardableResult
    public func begin() -> Request? {
        guard !session.isAssociation, !session.rawText.isEmpty else { return nil }
        let source = session.candidates.indices.contains(session.selectedIndex)
            ? session.candidates[session.selectedIndex] : session.rawText
        nextID &+= 1
        let request = Request(id: nextID, compositionGeneration: session.generation, source: source)
        self.request = request
        phase = .loading
        return request
    }

    /// 只有目前請求可套用回覆；取消／重新翻譯／改字後的回覆一律丟棄。
    @discardableResult
    public func complete(_ text: String?, for request: Request) -> Bool {
        guard phase == .loading, self.request == request else { return false }
        guard request.compositionGeneration == session.generation else {
            cancel()
            return false
        }
        let result = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let result, !result.isEmpty, result != request.source {
            phase = .ready(result)
        } else {
            phase = .failed
        }
        return true
    }

    public func cancel() {
        request = nil
        phase = .idle
    }

    /// nil 表示翻譯層已退出，讓同一按鍵繼續交給原速成狀態機。
    public func handle(_ key: QuickKey) -> QuickResult? {
        guard isActive else { return nil }
        guard request?.compositionGeneration == session.generation else {
            cancel()
            return nil
        }
        switch key {
        case .space:
            return QuickResult(consumed: true)
        case .escape:
            cancel()
            return QuickResult(consumed: true)
        case .digit(let digit, shifted: false) where (1...9).contains(digit):
            return digit == 1 ? selectTranslation() : QuickResult(consumed: true)
        default:
            cancel()
            return nil
        }
    }

    public func selectTranslation() -> QuickResult {
        guard request?.compositionGeneration == session.generation else {
            cancel()
            return QuickResult(consumed: true)
        }
        guard case .ready(let text) = phase else { return QuickResult(consumed: true) }
        cancel()
        session.reset()
        return QuickResult(consumed: true, commits: [text])
    }
}
