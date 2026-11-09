import CoreFoundation
import Foundation

struct KeyboardSettings: Equatable {
    var hapticsEnabled: Bool
    var candidateBarEnabled: Bool
    var keyboardHeight: Double

    static let `default` = KeyboardSettings(
        hapticsEnabled: true,
        candidateBarEnabled: true,
        keyboardHeight: 280
    )
}

/// 跨进程设置的唯一入口。
/// 主 App 写入后通过 Darwin notification 通知键盘扩展重新读取。
enum SharedStore {
    private enum Key {
        static let haptics = "keyboard.haptics"
        static let candidateBar = "keyboard.candidateBar"
        static let keyboardHeight = "keyboard.height"
    }

    static func load() -> KeyboardSettings {
        let defaults = AppGroup.defaults
        // 键盘扩展是独立进程，读取前刷新一次共享域。
        defaults.synchronize()
        let fallback = KeyboardSettings.default
        return KeyboardSettings(
            hapticsEnabled: defaults.object(forKey: Key.haptics) as? Bool ?? fallback.hapticsEnabled,
            candidateBarEnabled: defaults.object(forKey: Key.candidateBar) as? Bool ?? fallback.candidateBarEnabled,
            keyboardHeight: defaults.object(forKey: Key.keyboardHeight) as? Double ?? fallback.keyboardHeight
        )
    }

    static func save(_ settings: KeyboardSettings) {
        let defaults = AppGroup.defaults
        defaults.set(settings.hapticsEnabled, forKey: Key.haptics)
        defaults.set(settings.candidateBarEnabled, forKey: Key.candidateBar)
        defaults.set(settings.keyboardHeight, forKey: Key.keyboardHeight)
        // 键盘扩展是独立进程，尽快落盘，避免收到 Darwin 通知后读到旧值。
        defaults.synchronize()
        notifyChange()
    }

    static func notifyChange() {
        let name = (AppGroup.identifier + ".settingsChanged") as CFString
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name),
            nil,
            nil,
            true
        )
        NotificationCenter.default.post(name: AppGroup.settingsChangedNotification, object: nil)
    }

    static func startObserving() {
        let name = (AppGroup.identifier + ".settingsChanged") as CFString
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            ximeDarwinNotificationCallback,
            CFNotificationName(name),
            nil,
            .deliverImmediately
        )
    }
}

private func ximeDarwinNotificationCallback(
    _ center: CFNotificationCenter?,
    _ observer: UnsafeMutableRawPointer?,
    _ name: CFNotificationName?,
    _ object: UnsafeRawPointer?,
    _ userInfo: CFDictionary?
) {
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: AppGroup.settingsChangedNotification, object: nil)
    }
}
