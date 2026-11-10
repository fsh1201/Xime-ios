#!/usr/bin/env bash
#
# 把已构建好的 RimeBridge XCFramework 接入 XcodeGen 工程。
# 执行前请先运行 scripts/build-rime-ios.sh 生成：
#   ios/RimeBridge/build/XimeRime.xcframework
#
set -euo pipefail

IOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$IOS_DIR/project.yml"
FRAMEWORK="$IOS_DIR/RimeBridge/build/XimeRime.xcframework"

if [[ ! -d "$FRAMEWORK" ]]; then
    echo "错误：找不到 $FRAMEWORK" >&2
    echo "请先在 macOS 上运行 ios/scripts/build-rime-ios.sh。" >&2
    exit 1
fi

if grep -q 'XimeRime.xcframework' "$SPEC"; then
    echo "project.yml 已包含 XimeRime.xcframework，无需重复启用。"
    exit 0
fi

python3 - "$SPEC" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    spec = f.read()

app_old = """    dependencies:
      - target: XimeKeyboard
        embed: true"""
app_new = """    dependencies:
      - target: XimeKeyboard
        embed: true
      - framework: RimeBridge/build/XimeRime.xcframework
        embed: false
        link: true"""

keyboard_old = """    entitlements:
      path: Config/XimeKeyboard.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.kingzcheung.xime"""
keyboard_new = keyboard_old + """

    dependencies:
      - framework: RimeBridge/build/XimeRime.xcframework
        embed: false
        link: true"""

for old, new in ((app_old, app_new), (keyboard_old, keyboard_new)):
    if spec.count(old) != 1:
        raise SystemExit("project.yml 结构与预期不符，请手动添加 RimeBridge 依赖。")
    spec = spec.replace(old, new)

with open(path, "w", encoding="utf-8") as f:
    f.write(spec)
PY

echo "已在 project.yml 中启用 XimeRime.xcframework。"
echo "下一步：cd ios && xcodegen generate"
