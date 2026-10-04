#!/usr/bin/env bash
# 构建测试版 APK（ADR-0003）。
#
# 测试版是**另一份安装身份**（applicationId `top.yurinka.susume.test`）：它与正式
# 版并存、数据不互通，不读版本清单、不进下载页。这个脚本只做本机出包这一件事：
# 带上 `--flavor beta`、注入构建标识、产出 arm64 那一份。
#
# 它不碰正式 keystore：测试版用 android/key-test.properties 指的那把测试钥签名。
# 缺这份凭据时直接失败——不回落正式钥，也不回落 debug 签名（后者逐机生成，会
# 让测试者只能卸载重装）。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

if [ ! -f android/key-test.properties ]; then
  cat >&2 <<'EOF'
缺 android/key-test.properties：测试版用它自己的测试 keystore 签名。

一次性生成（口令由你设，生成后请像正式钥一样备份好——换了它，已装测试版的
测试者只能卸载重装）：

  tool/gen_test_keystore.sh
EOF
  exit 1
fi

# 构建标识：作者要能分辨同一版本名的两次测试包（走 device.json 与关于页，
# 不进用户可见的版本号）。工作区有改动时缀 -dirty，免得两个不同的包同名。
build_id=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  build_id="${build_id}-dirty"
fi

apk="build/app/outputs/flutter-apk/app-arm64-v8a-beta-release.apk"

flutter pub get
# `--split-per-abi` + 单一 target-platform 只产出 arm64 那一份（与正式发布同一条
# 形状）；`-P force-version-code-ignoring-abi=true` 消掉 split 给 versionCode 加的
# ABI 偏移，让构建号仍只有 pubspec.yaml 一个真源。
flutter build apk --release --flavor beta \
  --target-platform android-arm64 --split-per-abi \
  -P force-version-code-ignoring-abi=true \
  --dart-define=SUSUME_BUILD_ID="${build_id}"

if [ ! -f "${apk}" ]; then
  echo "没有产出预期的测试包：${apk}" >&2
  exit 1
fi

cat <<EOF
测试包：${apk}
  安装身份：top.yurinka.susume.test（与正式版并存，数据不互通）
  构建标识：${build_id}
发给测试者这一份即可；他们手机上原有的正式版不受影响。
EOF
