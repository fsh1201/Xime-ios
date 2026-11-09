import Foundation

/// 把 App bundle 里的 rime/ 数据复制到 App Group 共享目录。
/// 主 App 在首次部署或数据版本变化时调用；键盘扩展只读共享目录，
/// 避免重复部署和内存占用。
enum RimeDataInstaller {
    /// bundle 内 rime 数据的版本号。更新 assets/rime 后递增。
    static let dataVersion = "1"

    private static let markerName = ".installed"

    static func installIfNeeded() {
        install(force: false)
    }

    static func install(force: Bool) {
        guard
            let sharedDirectory = AppGroup.rimeSharedDirectory(),
            let userDirectory = AppGroup.rimeUserDirectory()
        else {
            return
        }

        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: sharedDirectory, withIntermediateDirectories: true)

        let marker = sharedDirectory.appendingPathComponent(markerName)
        if !force,
           let installed = try? String(contentsOf: marker, encoding: .utf8),
           installed.trimmingCharacters(in: .whitespacesAndNewlines) == dataVersion {
            return
        }

        guard let bundled = Bundle.main.url(forResource: "rime", withExtension: nil) else {
            return
        }

        guard let items = try? fileManager.contentsOfDirectory(
            at: bundled,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for item in items {
            let destination = sharedDirectory.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try? fileManager.copyItem(at: item, to: destination)
        }

        try? dataVersion.write(to: marker, atomically: true, encoding: .utf8)
    }
}
