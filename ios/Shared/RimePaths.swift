import Foundation

/// Rime 数据目录解析。
/// 有 App Group 时使用共享容器；没有时（免费签名）使用 bundle 内置数据和
/// 扩展自己的 Application Support 目录。
enum RimePaths {
    struct Directories {
        let shared: URL
        let user: URL
        let usesAppGroup: Bool
    }

    static func resolve() -> Directories? {
        if let shared = AppGroup.rimeSharedDirectory(),
           let user = AppGroup.rimeUserDirectory() {
            return Directories(shared: shared, user: user, usesAppGroup: true)
        }

        guard
            let shared = Bundle.main.url(forResource: "rime", withExtension: nil),
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }

        let user = support.appendingPathComponent("Rime", isDirectory: true)
        return Directories(shared: shared, user: user, usesAppGroup: false)
    }
}
