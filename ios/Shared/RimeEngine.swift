import Foundation

struct RimeCandidate: Identifiable, Equatable {
    let id: Int
    let text: String
    let comment: String?
}

struct RimeOutput: Equatable {
    var commit: String?
    var composition: String = ""
    var candidates: [RimeCandidate] = []
    var pageNumber: Int = 0
    var hasPreviousPage: Bool = false
    var hasMorePages: Bool = false
    var asciiMode: Bool = false

    static let empty = RimeOutput()
}

enum RimeKey: Equatable {
    case character(Character)
    case backspace
    case space
    case enter
    case escape
}

/// 键盘只依赖这个协议；librime 接入后替换工厂实现即可。
protocol RimeEngine: AnyObject {
    var name: String { get }
    var isAvailable: Bool { get }
    func reset()
    func processKey(_ key: RimeKey) -> RimeOutput
    func selectCandidate(at index: Int) -> RimeOutput
    func changePage(backward: Bool) -> RimeOutput
    func commitComposition() -> RimeOutput
    func setOption(_ name: String, value: Bool)
}

/// 未链接 librime 时的回退实现：字母/数字/符号直接上屏。
final class PassthroughRimeEngine: RimeEngine {
    let name = "Passthrough"
    let isAvailable = false

    func reset() {}

    func processKey(_ key: RimeKey) -> RimeOutput {
        switch key {
        case .character(let character):
            return RimeOutput(commit: String(character))
        case .space:
            return RimeOutput(commit: " ")
        case .enter:
            return RimeOutput(commit: "\n")
        case .backspace, .escape:
            return .empty
        }
    }

    func selectCandidate(at index: Int) -> RimeOutput { .empty }
    func changePage(backward: Bool) -> RimeOutput { .empty }
    func commitComposition() -> RimeOutput { .empty }
    func setOption(_ name: String, value: Bool) {}
}

enum RimeEngineFactory {
    static var engineName: String {
        #if canImport(RimeBridgeC)
        if !AppGroup.hasContainer {
            return "librime（内置数据）"
        }
        return AppGroup.isRimeDeployed ? "librime" : "librime（未部署）"
        #else
        return "Passthrough（未链接 librime）"
        #endif
    }

    static var isLibrimeAvailable: Bool {
        #if canImport(RimeBridgeC)
        return true
        #else
        return false
        #endif
    }

    static func make() -> RimeEngine {
        #if canImport(RimeBridgeC)
        // 有 App Group 时需要主 App 先完成部署；
        // 没有 App Group 时键盘直接使用 bundle 内置的预编译数据。
        if !AppGroup.hasContainer || AppGroup.isRimeDeployed {
            if let engine = LibrimeRimeEngine() {
                return engine
            }
        }
        #endif
        return PassthroughRimeEngine()
    }

    /// 在主 App 里执行部署。fullCheck 为 true 时重建词典，耗时较长；
    /// 键盘扩展不要调用，避免阻塞输入。
    static func deploy(fullCheck: Bool) -> Bool {
        #if canImport(RimeBridgeC)
        return LibrimeRimeEngine.deploy(fullCheck: fullCheck)
        #else
        return false
        #endif
    }
}
