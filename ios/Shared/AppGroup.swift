import Foundation

enum AppGroup {
    /// 主 App 与键盘扩展共享数据的 App Group。
    /// 修改 Bundle ID 时，需要同步修改：
    /// - 本文件
    /// - project.yml 中两个 target 的 entitlements
    /// - Apple Developer 后台注册的 App Group
    static let identifier = "group.com.kingzcheung.xime"

    static let settingsChangedNotification = Notification.Name("com.kingzcheung.xime.settingsChanged")

    static var defaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }

    /// Rime 用户数据目录（App Group 容器内，主 App 与键盘扩展均可读写）。
    static func rimeUserDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            return nil
        }
        return container.appendingPathComponent("rime-user", isDirectory: true)
    }

    /// Rime 共享数据目录（词典、schema 等，由主 App 负责写入）。
    static func rimeSharedDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            return nil
        }
        return container.appendingPathComponent("rime-shared", isDirectory: true)
    }

    /// 主 App 部署成功后写入的版本标记。
    /// 键盘扩展据此判断能否安全启用 librime，避免在扩展里做全量部署。
    static let rimeDeployedVersionKey = "rime.deployedVersion"
    static let rimeDeployedAtKey = "rime.deployedAt"

    /// 当前进程是否能访问 App Group 容器。
    /// 免费签名或 entitlements 被剥离时为 false，此时走键盘内置数据模式。
    static var hasContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) != nil
    }

    static var isRimeDeployed: Bool {
        defaults.string(forKey: rimeDeployedVersionKey) != nil
    }
}
