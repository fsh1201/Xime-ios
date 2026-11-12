import Foundation

/// 从 rime 数据里的 english.dict.yaml 提供英文单词前缀候选。
enum EnglishLexicon {
    static let words: [String] = load()

    static func suggestions(for typed: String, limit: Int) -> [String] {
        guard !typed.isEmpty else { return [] }
        let prefix = typed.lowercased()
        var result: [String] = []
        var seen = Set<String>()

        for word in words where word.hasPrefix(prefix) {
            let display = matchCase(typed, word)
            if seen.insert(display).inserted {
                result.append(display)
                if result.count >= limit {
                    break
                }
            }
        }
        return result
    }

    private static func matchCase(_ typed: String, _ word: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        return word.prefix(1).uppercased() + String(word.dropFirst())
    }

    private static func load() -> [String] {
        let direct = Bundle.main.bundleURL
            .appendingPathComponent("rime", isDirectory: true)
            .appendingPathComponent("english.dict.yaml")

        let url: URL?
        if FileManager.default.fileExists(atPath: direct.path) {
            url = direct
        } else {
            url = Bundle.main.url(
                forResource: "english.dict",
                withExtension: "yaml",
                subdirectory: "rime"
            ) ?? Bundle.main.url(
                forResource: "english.dict",
                withExtension: "yaml"
            )
        }

        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var words: [String] = []
        var seen = Set<String>()
        var inEntries = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine)
            if line == "..." {
                inEntries = true
                continue
            }
            guard inEntries, !line.hasPrefix("#") else { continue }

            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let first = fields.first else { continue }

            let word = String(first).trimmingCharacters(in: .whitespaces)
            guard
                !word.isEmpty,
                word.allSatisfy({ $0.isLetter || $0 == "'" }),
                word.unicodeScalars.allSatisfy({ $0.isASCII })
            else {
                continue
            }

            if seen.insert(word).inserted {
                words.append(word)
            }
        }

        return words
    }
}
