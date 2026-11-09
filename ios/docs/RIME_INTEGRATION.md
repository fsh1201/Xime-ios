# 接入 librime

本文描述第二阶段：把 librime 编成 iOS 静态 XCFramework，并让键盘扩展通过 `RimeBridgeC` 使用。

> 当前最小骨架默认不链接 librime。`Shared/LibrimeRimeEngine.swift` 被 `#if canImport(RimeBridgeC)` 包裹，因此未接入时不会参与编译。

## 1. 初始化子模块

```bash
git submodule update --init --recursive
```

至少需要：

- `app/src/main/jni/librime`
- `app/src/main/jni/snappy`
- `app/src/main/jni/librime-lua`
- `app/src/main/jni/librime-lua-deps`
- `app/src/main/jni/librime-octagram`
- `app/src/main/jni/librime-predict`
- `app/src/main/assets/rime`

## 2. 准备 iOS 版依赖

librime 依赖：

- boost（header-only 部分 + 少量库）
- yaml-cpp
- leveldb
- marisa-trie
- opencc
- snappy
- glog

需要分别为 `arm64`（真机）和 `arm64`/`x86_64`（模拟器）编译静态库。建议使用 [ios-cmake](https://github.com/leetal/ios-cmake) 工具链，或者直接使用现成的 librime iOS XCFramework 产物，再补上本项目需要的模块（lua / octagram / predict / t9 / correction）。

本仓库的 `ios/scripts/build-rime-ios.sh` 负责：

1. 构建 `RimeBridgeC` 静态库；
2. 把 `RimeBridgeC` 与你提供的 librime 静态库合并；
3. 生成 `ios/RimeBridge/build/XimeRime.xcframework`。

它不会替你编译 librime 依赖，需要先设置：

```bash
export RIME_LIBS_DEVICE="/path/device/librime.a;/path/device/libyaml-cpp.a;..."
export RIME_LIBS_SIMULATOR="/path/sim/librime.a;/path/sim/libyaml-cpp.a;..."
./ios/scripts/build-rime-ios.sh
```

## 3. 把 XCFramework 加入工程

构建完成后执行：

```bash
./ios/scripts/enable-rime.sh
cd ios && xcodegen generate
```

脚本会在 `Xime` 和 `XimeKeyboard` 两个 target 中加入：

```yaml
    dependencies:
      - framework: RimeBridge/build/XimeRime.xcframework
        embed: false
        link: true
```

静态库不能 `embed`，否则会被重复打包。若 `project.yml` 结构已被改动、脚本拒绝执行，请手动添加上述片段。

此时 `canImport(RimeBridgeC)` 为真，`LibrimeRimeEngine` 会自动参与编译，`RimeEngineFactory` 会优先返回它。若链接时报 `std::__1` 未定义，在对应 target 的 `OTHER_LDFLAGS` 中加 `-lc++`。

## 4. 放置 Rime 数据

主 App 的 `RimeDataInstaller` 会在首次启动时把 App bundle 里的 `rime/` 复制到 App Group 的 `rime-shared` 目录。

需要把 Rime 数据作为文件夹资源加入 `Xime` target。例如在 `project.yml` 中：

```yaml
    sources:
      - path: App
      - path: Shared
      - path: ../app/src/main/assets/rime
        type: folder
        buildPhase: resources
```

目录结构建议：

```
<App Group 容器>/
├── rime-shared/        # schema、词典、opencc 等只读数据
│   └── .installed      # 安装标记
└── rime-user/          # 用户词典、配置、同步文件
```

## 5. 首次部署

部署已由主 App 的 `RimeDeploymentModel` 接管：

- `ContentView.task` 在启动时调用 `deployIfNeeded()`；
- `RimeDataInstaller` 根据共享目录里 `.installed` 记录的 `dataVersion` 决定是否重新复制 bundle 中的 `rime/`；
- 首次安装或数据版本变化时，`RimeEngineFactory.deploy(fullCheck: true)` 在后台线程调用 `xime_rime_deploy`，完成后把版本写入 App Group 的 `UserDefaults`；
- 设置页显示“部署中 / 已部署 / 失败”，并提供“重新部署”按钮；
- 键盘扩展只有在 `AppGroup.isRimeDeployed` 为真时才创建 `LibrimeRimeEngine`，并通过 `xime_rime_create` 做 `fullCheck: false` 的增量维护；未部署或创建失败时 `RimeEngineFactory` 自动回退到 `PassthroughRimeEngine`。

如果直接让键盘扩展做全量部署，很容易触发内存/时间限制，导致键盘被系统结束。

## 6. 当前桥接 API

`ios/RimeBridge/include/RimeBridgeC.h`：

```c
bool xime_rime_deploy(const char *shared_data_dir,
                      const char *user_data_dir,
                      bool full_check);

xime_rime_session *xime_rime_create(const char *shared_data_dir,
                                    const char *user_data_dir);
void xime_rime_destroy(xime_rime_session *session);
void xime_rime_reset(xime_rime_session *session);

char *xime_rime_process_key(xime_rime_session *session, int keycode, int modifiers);
char *xime_rime_select_candidate(xime_rime_session *session, int index);
char *xime_rime_select_schema(xime_rime_session *session, const char *schema_id);
char *xime_rime_change_page(xime_rime_session *session, bool backward);
char *xime_rime_commit(xime_rime_session *session);
char *xime_rime_delete_backward(xime_rime_session *session);
char *xime_rime_set_option(xime_rime_session *session, const char *name, bool value);
char *xime_rime_status(xime_rime_session *session);

void xime_rime_free_string(char *value);
```

返回值是 JSON：

```json
{
  "commit": "",
  "preedit": "ni hao",
  "candidates": [
    {"text": "你好", "comment": null}
  ],
  "pageNo": 0,
  "isLastPage": true,
  "asciiMode": false
}
```

对应 Swift 侧：

- `Shared/LibrimeRimeEngine.swift`：把 JSON 转成 `RimeOutput`
- `Keyboard/KeyboardViewModel.swift`：组合、候选、上屏
- `Keyboard/KeyboardViewController.swift`：`setMarkedText` / `insertText` / `unmarkText`

## 7. 需要补齐的桥接能力

当前 C API 只覆盖最小输入链路。完整对齐还需要：

- 翻页：`page_up` / `page_down`（已由 `change_page` 覆盖）
- 删除候选：`delete_candidate`
- schema 列表：`get_schema_list`（`select_schema` 已提供）
- 用户词典：导入、导出、同步
- 选项：简繁、全角/半角、ASCII 模式、标点
- 部署状态回调
- 日志级别
- T9 / 预测 / 纠错模块注册
- 崩溃保护：librime 在扩展里异常会直接杀掉键盘进程，需要在主 App 做数据校验和备份

## 8. 键盘扩展内存注意事项

- 只加载当前 schema 需要的词典；
- 避免在扩展里保留大 buffer、图片和模型；
- 用 `os_proc_available_memory()` 做内存预算；
- 把预测/语音/插件等重活放到主 App 或在线服务；
- 真机测试低内存设备（如 3GB/4GB 机型）。

## 9. 验证清单

- [ ] 键盘扩展能创建 Rime session
- [ ] 输入 `nihao` 出现候选
- [ ] 选择候选能上屏
- [ ] 空格选首候选
- [ ] 退格能删除组合
- [ ] 切换 schema 后候选变化
- [ ] 重启键盘后用户词典保留
- [ ] 低内存设备不崩溃
- [ ] 主 App 首次部署成功

## 10. Linux 验证记录

在 Linux 上用 `app/src/main/jni/librime` 及其依赖源码构建 `rime-static`，并链接 `RimeBridgeC` 做了端到端验证（2026-11）。可复现命令：

```bash
./ios/scripts/verify-rime-linux.sh            # 默认 pinyin_simp
./ios/scripts/verify-rime-linux.sh wubi86_pinyin
```

验证程序：`ios/RimeBridge/tests/rime_bridge_test.cpp`。覆盖：

- `xime_rime_deploy(shared, user, true)` 成功部署；
- 输入 `nihao` 时 `preedit` 从 `n`、`ni`、`ni h` 逐步变成 `ni hao`；
- 最后一帧候选包含 `你好 / 拟好 / 你 / 拟 / 尼`；
- `xime_rime_select_candidate(0)` 返回 `"commit":"你好"`；
- 空格选首候选同样返回 `你好`；
- 退格把 `ni` 删成 `n`，候选同步收缩；
- 输入 `a` 后 `page down` 把 `pageNo` 从 0 切到 1，`page up` 再切回 0；
- 用户目录会生成 `pinyin_simp.userdb` / `wubi86.userdb` 与 `installation.yaml`，说明用户词典已落盘。

两个已知提示：

- `error creating translator: 'lua_translator'`：当前没有编译 `librime-lua`，依赖 Lua 的 schema 会缺这个翻译器，但拼音候选正常。接入插件后消失。
- `neither pack source file 'user_simp.dict.yaml' nor a prebuilt table exists`：首次部署时用户词典尚未生成，属正常日志。

构建注意：Android 工程的 `FindBoost.cmake` 通过 `build/boost/libs/*` 推断 Boost 头文件路径，只覆盖依赖闭包内的库。用源码直接构建时，需要额外把 `boost/libs/*/include` 全部加入 include 路径，否则会缺少 `boost/vmd/is_empty.hpp`。验证脚本已在 `RimeBridge/tests/linux/CMakeLists.txt` 中处理。
