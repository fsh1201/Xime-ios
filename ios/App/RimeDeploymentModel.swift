import Combine
import Foundation

/// 主 App 的 Rime 部署状态机。
/// 部署会重建词典并阻塞当前线程，因此始终放到后台执行；
/// 键盘扩展不触发部署，只读取部署好的共享目录。
final class RimeDeploymentModel: ObservableObject {
    enum Status: Equatable {
        case unavailable
        case idle
        case localMode
        case running
        case succeeded(Date)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    private var currentVersion: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(build)-\(RimeDataInstaller.dataVersion)"
    }

    /// App 启动时调用：只有数据版本变化或从未部署成功时才做全量部署。
    func deployIfNeeded() {
        guard RimeEngineFactory.isLibrimeAvailable else {
            status = .unavailable
            return
        }
        guard AppGroup.hasContainer else {
            status = .localMode
            return
        }

        let defaults = AppGroup.defaults
        if defaults.string(forKey: AppGroup.rimeDeployedVersionKey) == currentVersion {
            let date = defaults.object(forKey: AppGroup.rimeDeployedAtKey) as? Date ?? Date()
            status = .succeeded(date)
            return
        }

        deploy()
    }

    /// 设置页的“重新部署”入口，强制全量检查。
    func redeploy() {
        guard RimeEngineFactory.isLibrimeAvailable else {
            status = .unavailable
            return
        }
        guard AppGroup.hasContainer else {
            status = .localMode
            return
        }
        deploy()
    }

    private func deploy() {
        guard status != .running else { return }
        status = .running

        let version = currentVersion
        Task.detached(priority: .userInitiated) { [weak self] in
            RimeDataInstaller.installIfNeeded()
            let succeeded = RimeEngineFactory.deploy(fullCheck: true)

            await MainActor.run {
                guard let self else { return }
                if succeeded {
                    let date = Date()
                    AppGroup.defaults.set(version, forKey: AppGroup.rimeDeployedVersionKey)
                    AppGroup.defaults.set(date, forKey: AppGroup.rimeDeployedAtKey)
                    self.status = .succeeded(date)
                } else {
                    self.status = .failed("部署失败，请查看设备日志")
                }
            }
        }
    }
}
