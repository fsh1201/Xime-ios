# Xime iOS 迁移路线图

## 1. 迁移不是翻译，而是重写宿主层

Xime 安卓版的核心资产可以复用：

- Rime 的 C/C++ 引擎与词典/schema
- 插件 `.xipk` 与 TypeScript 插件源码
- 主题、配置、Rime 数据的格式
- 输入逻辑与产品设计

不能直接复用：

- Kotlin / Jetpack Compose UI
- Android `InputMethodService`、AIDL、Room、DataStore、OkHttp/Ktor 等宿主 API
- Android JNI 层（需要改成 iOS 的 C/C++ 静态库 + Swift 桥接）
- 依赖 Android 进程模型的离线推理服务

## 2. iOS 架构

```
┌──────────────────────────────┐
│ Xime.app                     │
│  SwiftUI 设置 / schema 管理  │
│  Rime 首次部署               │
│  主题、插件、备份             │
└──────────────┬───────────────┘
               │ App Group 共享容器
┌──────────────▼───────────────┐
│ XimeKeyboard.appex           │
│  UIInputViewController       │
│  SwiftUI / UIKit 键盘        │
│  RimeEngine（librime）       │
│  候选 / 组合 / 上屏          │
└──────────────────────────────┘
```

关键约束：

- 键盘扩展是独立进程，不能直接调用主 App。
- 主 App 与键盘只能通过 App Group 文件/UserDefaults、Darwin notification 通信。
- 键盘扩展内存上限通常 40–60 MB，必须避免一次性加载大模型、大词典和大量图片。
- 键盘扩展不能使用 JIT；QuickJS/JS 运行时需要 AOT 友好的实现或 JavaScriptCore。
- 键盘扩展需要用户开启“完全访问”才能访问网络、剪贴板等能力。

## 3. 模块映射

| Android | iOS 方案 | 说明 |
| --- | --- | --- |
| `XimeInputMethodService` | `KeyboardViewController` | `UIInputViewController` 子类，负责 `textDocumentProxy` 上屏 |
| Compose 键盘 UI | SwiftUI 键盘 | 键盘扩展里用轻量 SwiftUI；复杂动画改用 UIKit |
| Compose 设置 UI | SwiftUI 设置 | `Form` / `NavigationStack` |
| `RimeEngine.kt` + `rime_jni.cc` | `LibrimeRimeEngine.swift` + `RimeBridgeC.cpp` | C ABI 桥接，librime 编成静态 XCFramework |
| `RimeConfigHelper` / schema 管理 | Swift + YAML 解析 | 可先用 Yams，后续按需移植 |
| SharedPreferences/DataStore | App Group `UserDefaults` | 键名保持稳定，便于迁移 |
| Room/SQLite（剪贴板等） | SQLite / GRDB | 剪贴板历史、统计等 |
| OkHttp / Ktor Client | `URLSession` | 网络、WebDAV、插件下载 |
| Ktor embedded server | Network.framework / Bonjour | 无线导入需要重新设计 |
| Coil | `AsyncImage` | 图片加载 |
| Kaml | Yams / Codable | YAML 解析 |
| ZXing | CoreImage `CIQRCodeGenerator` | 二维码 |
| Sora Editor | `UITextView` / CodeEditor | schema 查看/编辑 |
| QuickJS（quickjs-kt） | QuickJS C / JavaScriptCore | 插件运行时，P4 再处理 |
| ONNX Runtime（预测/语音） | 暂缓 | 键盘扩展内存不够；在线 ASR 插件优先 |
| 手写识别 | Core ML / Vision | 需要重新训练或转换模型 |
| Android 分享 Intent | Share Extension / Document Picker | schema 导入 |
| 剪贴板 | `UIPasteboard` | 需要完全访问；iOS 16+ 有粘贴提示 |
| 物理键盘 | `UIKeyCommand` / `pressesBegan` | 后续支持 |

## 4. 分阶段计划

### P0：最小可运行骨架（已完成）

- 主 App + 键盘扩展工程
- App Group 共享设置
- QWERTY / 数字 / 符号键盘
- 上屏、退格、回车、地球键
- RimeEngine 抽象 + Passthrough 回退
- 迁移文档

验收：模拟器/真机能输入 ASCII，主 App 改键盘高度和反馈设置后键盘生效。

### P1：librime 接入（进行中）

已完成：

- `RimeBridgeC` 覆盖部署、创建会话、按键、选候选、翻页、切换 schema、状态查询
- 主 App 通过 `RimeDeploymentModel` 后台执行全量部署，设置页显示状态
- Rime 数据作为 folder resource 打包，`RimeDataInstaller` 负责写入 App Group
- 键盘扩展只在部署成功后启用 librime，否则回退 Passthrough
- 候选栏支持上下页按钮
- Linux 上已用源码构建 librime 并验证 `nihao → 你好`、空格选首候选、退格删组合、候选翻页

待完成：

- 在 macOS 上编译 iOS 版依赖并生成 `XimeRime.xcframework`
- 用 `scripts/enable-rime.sh` 接入工程并在模拟器/真机验收
- 用户词典持久化验证（重启键盘后保留）

验收：键盘输入 `nihao` 能显示候选并上屏「你好」；重启键盘后用户词典保留。

### P2：键盘功能对齐

- T9 / 九宫格
- 数字键盘与符号页完善
- 主题（浅色/深色/强调色）
- 工具栏、快捷操作
- 滑动手势（移动光标、删除、符号）
- 按键音/震动
- 剪贴板历史
- 候选注释、五笔字根提示
- 物理键盘候选栏

### P3：设置与数据

- schema 管理、导入/导出
- 主题编辑
- WebDAV 备份/恢复
- 设置项与安卓版键名对齐
- 本地化（简体/繁体/英文）

### P4：插件系统

- 选型：QuickJS C 或 JavaScriptCore
- 移植 `plugin-core` 的 host API（HTTP、WebSocket、剪贴板、语音、备份）
- `.xipk` 安装/更新/校验
- 插件市场
- 注意键盘扩展内存与执行超时，重活尽量放主 App

### P5：语音与手写

- 在线 ASR 插件优先（FunAsr、Volc 等）
- 离线 ASR 不建议放进键盘扩展；如必须，使用更小模型并做内存预算
- 手写可用 Core ML / Vision 重新实现

### P6：工程化

- 单元测试（RimeBridge、设置、布局计算）
- UI 测试（键盘上屏、候选选择）
- CI（macOS runner + xcodebuild）
- 崩溃日志、性能与内存监控
- 无障碍与 iPad 适配

## 5. 风险与工作量

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| librime iOS 依赖编译 | P1 阻塞 | 先做最小依赖集；参考现有 librime XCFramework 项目 |
| 键盘扩展内存 | 崩溃/被系统回收 | 精简词典、懒加载、避免大图/大模型、监控内存 |
| GPLv3 与 App Store | 无法上架 | 侧载/企业分发，或单独评估授权 |
| 插件运行时 | P4 工作量大 | 先只支持内置功能，插件后置 |
| iOS 输入法限制 | 部分 Android 功能不可实现 | 产品层面裁剪，明确不支持清单 |

以当前代码规模（约 9 万行 Kotlin + 原生依赖），完整对齐是多人月级工作。建议每个阶段独立验收，不要一次性追求功能对齐。
