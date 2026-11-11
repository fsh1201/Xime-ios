#if canImport(RimeBridgeC)
import Foundation
import RimeBridgeC

/// librime 的 Swift 适配层。
/// 默认工程不链接 RimeBridgeC，因此本文件不会参与编译；
/// 按 docs/RIME_INTEGRATION.md 构建并加入 RimeBridge 后自动启用。
final class LibrimeRimeEngine: RimeEngine {
    let name = "librime"
    let isAvailable = true

    private var session: OpaquePointer?
    private var rawInput = ""

    /// 初始化 librime 并同步执行部署；调用方应放到后台线程。
    /// 仅在 App Group 可用时使用；免费签名模式由键盘使用内置预编译数据。
    static func deploy(fullCheck: Bool) -> Bool {
        guard let paths = RimePaths.resolve(), paths.usesAppGroup else {
            return false
        }

        try? FileManager.default.createDirectory(
            at: paths.shared,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: paths.user,
            withIntermediateDirectories: true
        )

        return paths.shared.path.withCString { sharedPath in
            paths.user.path.withCString { userPath in
                xime_rime_deploy(sharedPath, userPath, fullCheck)
            }
        }
    }

    init?() {
        guard let paths = RimePaths.resolve() else {
            return nil
        }

        try? FileManager.default.createDirectory(
            at: paths.user,
            withIntermediateDirectories: true
        )
        if paths.usesAppGroup {
            try? FileManager.default.createDirectory(
                at: paths.shared,
                withIntermediateDirectories: true
            )
        }

        let created = paths.shared.path.withCString { sharedPath in
            paths.user.path.withCString { userPath in
                paths.usesAppGroup
                    ? xime_rime_create(sharedPath, userPath)
                    : xime_rime_create_passive(sharedPath, userPath)
            }
        }

        guard let created else {
            return nil
        }
        session = created

        RimePreferences.selectedSchema.withCString { schema in
            xime_rime_free_string(xime_rime_select_schema(created, schema))
        }
    }

    func selectSchema(_ id: String) {
        rawInput = ""
        guard let session else { return }
        id.withCString { schema in
            xime_rime_free_string(xime_rime_select_schema(session, schema))
        }
    }

    deinit {
        xime_rime_destroy(session)
    }

    func reset() {
        rawInput = ""
        guard let session else { return }
        xime_rime_reset(session)
    }

    func processKey(_ key: RimeKey) -> RimeOutput {
        guard let session else { return .empty }

        let output: RimeOutput
        switch key {
        case .character(let character):
            if let scalar = character.unicodeScalars.first,
               scalar.isASCII, scalar.value >= 0x20 {
                rawInput.append(character)
            }
            // 与 Android 端保持一致：字母统一发送小写 keysym，大写用 Shift 修饰。
            guard let scalar = character.lowercased().unicodeScalars.first?.value else {
                return .empty
            }
            let modifiers: Int32 = character.isUppercase ? 1 : 0
            output = consume(
                xime_rime_process_key_fast(session, Int32(scalar), modifiers)
            )
        case .backspace:
            if !rawInput.isEmpty {
                rawInput.removeLast()
            }
            output = consume(xime_rime_process_key_fast(session, 0xFF08, 0))
        case .space:
            output = consume(xime_rime_process_key_fast(session, 0x20, 0))
            rawInput = ""
        case .enter:
            output = consume(xime_rime_process_key_fast(session, 0xFF0D, 0))
            rawInput = ""
        case .escape:
            output = consume(xime_rime_process_key_fast(session, 0xFF1B, 0))
            rawInput = ""
        }

        if output.commit?.isEmpty == false {
            rawInput = ""
        }

        return RimeOutput(
            commit: output.commit,
            composition: rawInput,
            candidates: [],
            asciiMode: output.asciiMode,
            candidatesStale: true
        )
    }

    func selectCandidate(at index: Int) -> RimeOutput {
        guard let session else { return .empty }
        let output = consume(xime_rime_select_candidate(session, Int32(index)))
        rawInput = output.composition.filter { !$0.isWhitespace }
        return output
    }

    func refreshCandidates() -> RimeOutput {
        guard let session else { return .empty }
        return consume(xime_rime_context(session))
    }

    func allCandidates(limit: Int) -> [RimeCandidate] {
        guard let session else { return [] }
        guard let pointer = xime_rime_all_candidates(session, Int32(limit)) else {
            return []
        }
        defer { xime_rime_free_string(pointer) }

        let json = String(cString: pointer)
        guard
            let data = json.data(using: .utf8),
            let result = try? JSONDecoder().decode(AllCandidatesResult.self, from: data)
        else {
            return []
        }
        return result.candidates.map {
            RimeCandidate(id: $0.index, text: $0.text, comment: $0.comment)
        }
    }

    func selectCandidateGlobal(at index: Int) -> RimeOutput {
        guard let session else { return .empty }
        let output = consume(xime_rime_select_candidate_global(session, Int32(index)))
        rawInput = output.composition.filter { !$0.isWhitespace }
        return output
    }

    func changePage(backward: Bool) -> RimeOutput {
        guard let session else { return .empty }
        return consume(xime_rime_change_page(session, backward))
    }

    func commitComposition() -> RimeOutput {
        rawInput = ""
        guard let session else { return .empty }
        return consume(xime_rime_commit(session))
    }

    func setOption(_ name: String, value: Bool) {
        guard let session else { return }
        name.withCString { optionName in
            let result = xime_rime_set_option(session, optionName, value)
            xime_rime_free_string(result)
        }
    }

    private func consume(_ pointer: UnsafeMutablePointer<CChar>?) -> RimeOutput {
        guard let pointer else { return .empty }
        defer { xime_rime_free_string(pointer) }

        let json = String(cString: pointer)
        guard
            let data = json.data(using: .utf8),
            let bridge = try? JSONDecoder().decode(BridgeResult.self, from: data)
        else {
            return .empty
        }

        return RimeOutput(
            commit: bridge.commit?.isEmpty == false ? bridge.commit : nil,
            composition: bridge.preedit ?? "",
            candidates: bridge.candidates.enumerated().map { pair in
                RimeCandidate(
                    id: pair.offset,
                    text: pair.element.text,
                    comment: pair.element.comment
                )
            },
            pageNumber: bridge.pageNo,
            hasPreviousPage: bridge.pageNo > 0,
            hasMorePages: !bridge.isLastPage,
            asciiMode: bridge.asciiMode,
            candidatesStale: bridge.stale ?? false
        )
    }
}

private struct BridgeResult: Decodable {
    let commit: String?
    let preedit: String?
    let candidates: [BridgeCandidate]
    let pageNo: Int
    let isLastPage: Bool
    let asciiMode: Bool
    let stale: Bool?
}

private struct BridgeCandidate: Decodable {
    let text: String
    let comment: String?
}

private struct AllCandidatesResult: Decodable {
    let candidates: [AllCandidate]
}

private struct AllCandidate: Decodable {
    let index: Int
    let text: String
    let comment: String?
}
#endif
