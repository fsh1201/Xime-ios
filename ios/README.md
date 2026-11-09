# Xime iOS（最小骨架）

这是 Xime 安卓输入法的 iOS 迁移起点，不是完整移植。

当前已经包含：

- `Xime` 主 App（SwiftUI，设置壳）
- `XimeKeyboard` 键盘扩展（`UIInputViewController` + SwiftUI 键盘）
- App Group 共享设置（主 App 改设置，键盘实时生效）
- 基础 QWERTY / 数字 / 符号键盘，支持上屏、退格、回车、地球键切换
- `RimeEngine` 抽象与 `PassthroughRimeEngine` 回退实现
- librime 的 C 桥接源码与 XCFramework 构建脚本（第二阶段使用，默认不参与编译）
- 主 App 的 Rime 部署状态与“重新部署”入口（链接 librime 后生效）
- 迁移路线图与模块映射：`docs/PORTING_PLAN.md`
- librime 接入说明：`docs/RIME_INTEGRATION.md`

## 环境要求

- macOS + Xcode 15 或更高版本
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)：`brew install xcodegen`
- Apple Developer 账号（真机运行需要；模拟器通常不需要付费账号）

当前仓库是在 Linux 环境里生成的，**没有在 Xcode 中编译验证过**；librime 的 C 桥接与候选链路已用 Linux 构建验证。第一次在 Mac 上打开时，请先按下面的步骤生成工程并处理签名。

## 快速开始

```bash
cd ios
xcodegen generate
open Xime.xcodeproj
```

在 Xcode 中：

1. 选中 `Xime` target → Signing & Capabilities → 选择你的 Team。
2. 对 `XimeKeyboard` 重复一次。
3. 如果使用自己的 Bundle ID，同时修改：
   - `project.yml` 中的 `PRODUCT_BUNDLE_IDENTIFIER`
   - `Shared/AppGroup.swift` 中的 `AppGroup.identifier`
   - `project.yml` 中两个 target 的 `com.apple.security.application-groups`
4. 选择 `Xime` scheme，运行到模拟器或真机。

> 如果只想在模拟器里快速看键盘，可以暂时删除两个 target 的 entitlements。此时 `SharedStore` 会回退到 `UserDefaults.standard`，键盘仍可输入，但主 App 与键盘不再共享设置。

在 Linux 上验证 Rime 桥接链路（不生成 iOS 产物，首次会下载 Boost）：

```bash
./ios/scripts/verify-rime-linux.sh
```

启用键盘：

1. 先运行一次主 App（让系统注册键盘扩展）。
2. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → Xime。
3. 在任意输入框中长按地球键切换到 Xime。

## 目录结构

```
ios/
├── project.yml                  XcodeGen 工程定义
├── App/                         主 App（设置、启用引导）
├── Keyboard/                    键盘扩展（UIInputViewController + SwiftUI）
├── Shared/                      App Group、共享设置、RimeEngine 抽象
├── RimeBridge/                  librime C 桥接（第二阶段）
│   └── tests/                   Linux 端到端验证程序
├── scripts/build-rime-ios.sh    librime XCFramework 构建脚本
├── scripts/enable-rime.sh       把 XCFramework 接入 project.yml
├── scripts/verify-rime-linux.sh Linux 下构建 librime 并验证候选链路
└── docs/
    ├── PORTING_PLAN.md          分阶段迁移路线图
    └── RIME_INTEGRATION.md      librime 接入步骤
```

## 当前限制

- **默认工程未链接 librime**：候选链路已在 Linux 上验证通过，但 iOS 侧仍需在 macOS 构建 `XimeRime.xcframework` 并执行 `scripts/enable-rime.sh`。未启用时使用 `PassthroughRimeEngine`，只做 ASCII 直通上屏。
- 键盘扩展受 iOS 内存限制（通常 40–60 MB），不能照搬 Android 的 ONNX 离线语音/预测模型。
- 键盘扩展不能 JIT；QuickJS 插件运行时需要改用可编译到 iOS 的 QuickJS C 版本或 JavaScriptCore。
- 悬浮键盘、覆盖其他 App 的输入法等 Android 能力在 iOS 上不可用或不一致。
- 未实现 T9、手写、主题市场、插件市场、WebDAV、剪贴板同步、语音输入。
- App 内目前无法直接跳转到“键盘设置”页；iOS 只提供应用设置页，键盘启用仍需用户手动操作。

## 下一步

P1 的桥接与候选链路已完成并在 Linux 上验证。剩余工作是在 macOS 上编译 iOS 版 librime 依赖、生成 `XimeRime.xcframework`，然后执行 `scripts/enable-rime.sh` 并在模拟器/真机完成验收。详见 `docs/PORTING_PLAN.md`。

## 许可

与主项目一致，GPLv3。注意：GPLv3 与 App Store 的分发条款存在冲突，上架前需要单独评估；侧载/企业分发不受同样的限制。
