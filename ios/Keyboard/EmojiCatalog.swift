import CoreText
import UIKit

/// 生成系统 Emoji 字体支持的全部表情，按码位排序。
enum EmojiCatalog {
    static let all: [String] = build()

    private static let fallback = [
        "😀", "😁", "😂", "🤣", "😊", "😍",
        "🥰", "😘", "😎", "🤔", "😅", "😭",
        "😡", "👍", "👎", "👏", "🙏", "💪",
        "❤️", "🔥", "🎉", "🌹", "🍎", "⚡️",
        "✅", "❌", "⭐️", "☀️", "🌙", "🎵"
    ]

    private static func build() -> [String] {
        guard let font = UIFont(name: "AppleColorEmoji", size: 20) else {
            return fallback
        }
        let ctFont = CTFontCreateWithName(font.fontName as CFString, 20, nil)
        let ranges: [ClosedRange<UInt32>] = [
            0x1F300...0x1F5FF,
            0x1F600...0x1F64F,
            0x1F680...0x1F6FF,
            0x1F900...0x1F9FF,
            0x1FA70...0x1FAFF,
            0x2600...0x26FF,
            0x2700...0x27BF
        ]

        var result: [String] = []
        var seen = Set<String>()

        for range in ranges {
            for code in range {
                guard let scalar = Unicode.Scalar(code) else { continue }
                let emoji = String(Character(scalar)) + "\u{FE0F}"
                guard !seen.contains(emoji) else { continue }

                let chars = Array(emoji.utf16)
                var glyphs = Array(repeating: CGGlyph(0), count: chars.count)
                let ok = chars.withUnsafeBufferPointer { charPtr in
                    glyphs.withUnsafeMutableBufferPointer { glyphPtr in
                        CTFontGetGlyphsForCharacters(
                            ctFont,
                            charPtr.baseAddress!,
                            glyphPtr.baseAddress!,
                            chars.count
                        )
                    }
                }

                if ok && glyphs[0] != 0 {
                    seen.insert(emoji)
                    result.append(emoji)
                }
            }
        }

        return result.isEmpty ? fallback : result
    }
}
