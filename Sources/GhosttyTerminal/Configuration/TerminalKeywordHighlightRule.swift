import Foundation
import GhosttyKit

/// An ordered, render-only color override. Earlier rules win overlaps.
public struct TerminalKeywordHighlightRule: Hashable, Sendable {
    public enum MatchMode: Hashable, Sendable { case text, regularExpression }
    public var pattern: String
    public var mode: MatchMode
    public var isCaseSensitive: Bool
    /// Nil preserves the terminal foreground. Packed sRGB, 0xRRGGBB.
    public var foregroundRGB: UInt32?
    /// Nil preserves the terminal background. Packed sRGB, 0xRRGGBB.
    public var backgroundRGB: UInt32?

    public init(
        pattern: String, mode: MatchMode = .text, isCaseSensitive: Bool = false, foregroundRGB: UInt32? = nil,
        backgroundRGB: UInt32? = nil
    ) {
        self.pattern = pattern
        self.mode = mode
        self.isCaseSensitive = isCaseSensitive
        self.foregroundRGB = foregroundRGB
        self.backgroundRGB = backgroundRGB
    }

    var regularExpression: String {
        var text = pattern
        if mode == .text {
            // Quote regex syntax explicitly; unlike \\Q…\\E this also handles a literal \\E.
            let special = Set("\\.^$|?*+()[]{}")
            text = String(pattern.flatMap { special.contains($0) ? [Character("\\"), $0] : [$0] })
        }
        // Configuration lines may never contain unescaped line separators.
        text = text.replacingOccurrences(of: "\r", with: #"\r"#).replacingOccurrences(of: "\n", with: #"\n"#)
        return isCaseSensitive ? text : "(?i:\(text))"
    }

    var configurationValue: String {
        func hex(_ color: UInt32?) -> String { color.map { String(format: "%06X", $0) } ?? "-" }
        return hex(foregroundRGB) + "," + hex(backgroundRGB) + ":" + regularExpression
    }

    /// Uses the same Oniguruma compiler as rendering. The result is diagnostic text, not localized UI copy.
    @MainActor
    public func validationIssue() -> String? {
        guard !pattern.isEmpty, pattern.utf8.count <= 16384, !pattern.contains("\0"), (foregroundRGB ?? 0) <= 0xFFFFFF,
            (backgroundRGB ?? 0) <= 0xFFFFFF
        else {
            return "InvalidKeywordRule"
        }
        TerminalController.initializeRuntimeIfNeeded()
        let data = Array(regularExpression.utf8)
        return data.withUnsafeBufferPointer { bytes in
            let issue = ghostty_keyword_highlight_validate(bytes.baseAddress!, UInt(bytes.count))
            guard issue.len > 0, let pointer = issue.ptr else { return nil }
            return String(
                decoding: UnsafeBufferPointer(start: pointer, count: Int(issue.len)).map { UInt8(bitPattern: $0) },
                as: UTF8.self)
        }
    }
}
