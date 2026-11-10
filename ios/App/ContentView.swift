import Foundation
import SwiftUI
import UIKit

struct ContentView: View {
    @State private var settings = SharedStore.load()
    @StateObject private var deployment = RimeDeploymentModel()

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                deploymentSection
                enableSection
                keyboardSection
                aboutSection
            }
            .navigationTitle("Xime")
            .onChange(of: settings) { newValue in
                SharedStore.save(newValue)
            }
            .task { @MainActor in
                deployment.deployIfNeeded()
            }
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("键盘扩展", value: "XimeKeyboard")
            LabeledContent("Rime 引擎", value: RimeEngineFactory.engineName)
            if FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: AppGroup.identifier
            ) == nil {
                Label("App Group 未启用", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("状态")
        } footer: {
            Text(statusFooter)
        }
    }

    private var statusFooter: String {
        guard RimeEngineFactory.isLibrimeAvailable else {
            return "当前未链接 librime，键盘使用 Passthrough 引擎，按键直接上屏。"
        }
        if !AppGroup.hasContainer {
            return "未启用 App Group：键盘使用内置 Rime 数据，主 App 的设置不会同步到键盘。"
        }
        return "已链接 librime：键盘显示候选并上屏中文。"
    }

    private var deploymentSection: some View {
        Section {
            LabeledContent("部署状态", value: deploymentText)
            Button("重新部署") {
                deployment.redeploy()
            }
            .disabled(
                !RimeEngineFactory.isLibrimeAvailable
                    || deployment.status == .running
                    || deployment.status == .localMode
            )
        } header: {
            Text("Rime 部署")
        } footer: {
            Text(
                AppGroup.hasContainer
                    ? "首次部署会编译词典，可能需要几十秒；键盘扩展只做增量维护。"
                    : "未启用 App Group：键盘使用自身内置的预编译 Rime 数据，无需主 App 部署。"
            )
        }
    }

    private var deploymentText: String {
        switch deployment.status {
        case .unavailable:
            return "未链接 librime"
        case .idle:
            return "尚未部署"
        case .localMode:
            return "内置数据模式"
        case .running:
            return "部署中…"
        case .succeeded(let date):
            return "已部署 · \(date.formatted(date: .abbreviated, time: .shortened))"
        case .failed(let message):
            return message
        }
    }

    private var enableSection: some View {
        Section {
            Button("打开系统设置") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        } header: {
            Text("启用键盘")
        } footer: {
            Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → Xime。在输入框中长按地球键即可切换到 Xime。")
        }
    }

    private var keyboardSection: some View {
        Section {
            Toggle("按键震动与声音", isOn: $settings.hapticsEnabled)
            Toggle("显示候选栏", isOn: $settings.candidateBarEnabled)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("键盘高度")
                    Spacer()
                    Text("\(Int(settings.keyboardHeight)) pt")
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.keyboardHeight, in: 220...340, step: 10)
            }
        } header: {
            Text("键盘")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent(
                "版本",
                value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
            )
            LabeledContent("App Group", value: AppGroup.identifier)
        } header: {
            Text("关于")
        } footer: {
            Text("修改 Bundle ID 时，请同步修改 App Group 与两个 target 的 entitlements。")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
