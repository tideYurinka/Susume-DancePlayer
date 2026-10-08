#!/usr/bin/env bash
# 投屏渲染计时入口（Android 目标，一键）：在**已连接的安卓目标**（真机或模拟器）
# 上用已链接的 ffmpeg 包跑完整滤镜图，量墙钟、留档编码器与热状态、把产物可播性
# 一并记下。
#
# 用法（仓库根目录）：
#   tool/cast_render_bench.sh -d <serial> [--runs 3] [--out <本机目录>] [--no-build]
#                              [--encoder <名>] [--exec <命令 JSON>]
#
# --encoder 默认 h264_mediacodec（本关卡要量的硬编那一档）；换成包内某个软件编码器
# （如 mpeg4）只为在没有硬编的目标上验滤镜图与流程——那样的读数**不是**真机吞吐结论。
# --runs/--encoder 只在会重新打包时生效（配 --no-build 时它们跟着上一次的包）。
#
# 它**不动任何生产文件**：打包时用 `-t` 换入口（tool/cast_render_bench.dart），
# 生产 main.dart 与本入口互不引用。命令与判定全部来自
# tool/cast_render_bench/bench_core.dart，与宿主对照
# （tool/cast_render_bench_host.dart）同一份滤镜图。
#
# 产出（默认 /tmp/cast_render_bench_device/）：
#   inputs/                  固定输入三件套（宿主生成，含 sha256 清单）
#   inputs_manifest.json
#   device_report.json      设备侧全部读数（墙钟、产物、编码器、性能点线索）
#   device_env.txt          机型/系统/ABI/编码器服务快照
#   thermal.log             跑过程中每 15s 一次的热状态采样
#   logcat.txt              flutter 日志（含 CAST_BENCH 行）
set -euo pipefail

DEVICE=""
RUNS=3
OUT=""
DO_BUILD=1
BUDGET=3600
EXEC_FILE=

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="${2:?缺设备序列号}"; shift 2 ;;
    --runs) RUNS="${2:?缺次数}"; shift 2 ;;
    --out) OUT="${2:?缺目录}"; shift 2 ;;
    --no-build) DO_BUILD=0; shift ;;
    --budget) BUDGET="${2:?缺秒数}"; shift 2 ;;
    --exec) EXEC_FILE="${2:?缺 JSON 文件}"; shift 2 ;;
    --encoder) ENCODER="${2:?缺编码器名}"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${OUT:-/tmp/cast_render_bench_device}"
PKG="top.yurinka.susume.debug"
ACTIVITY="top.yurinka.susume.MainActivity"
APK="$ROOT/build/app/outputs/flutter-apk/app-prod-debug.apk"
REMOTE_INPUTS="/data/local/tmp/cast_bench_inputs"

ADB=(adb)
[[ -n "$DEVICE" ]] && ADB=(adb -s "$DEVICE")

log() { printf '[bench] %s\n' "$*"; }

if ! "${ADB[@]}" get-state >/dev/null 2>&1; then
  echo "没有可用的安卓目标（adb devices 看一眼）" >&2
  exit 2
fi

mkdir -p "$OUT"

# 1) 固定输入：由宿主入口生成（同一串参数、同一份哈希）
if [[ ! -f "$OUT/inputs_manifest.json" ]]; then
  log "生成固定输入 → $OUT/inputs"
  (cd "$ROOT" && dart run tool/cast_render_bench_host.dart \
      --out "$OUT" --prepare-only)
fi

# 2) 打包：换入口，不动生产入口
if [[ "$DO_BUILD" == 1 ]]; then
  log "打包计时入口（debug，flavor 默认 prod）"
  (cd "$ROOT" && flutter build apk --debug \
      -t tool/cast_render_bench.dart \
      --dart-define=CAST_BENCH_RUNS="$RUNS" \
      --dart-define=CAST_BENCH_ENCODER="$ENCODER")
fi

# 3) 安装 + 把固定输入推进应用私有目录
log "安装 $APK"
"${ADB[@]}" install -r "$APK" >/dev/null

# 3') 逃生口：只跑一条离线命令（连带日志取回），迭代诊断用，不碰固定输入。
if [[ -n "$EXEC_FILE" ]]; then
  log "离线命令模式：$EXEC_FILE"
  "${ADB[@]}" push "$EXEC_FILE" /data/local/tmp/cast_bench_command.json >/dev/null
  "${ADB[@]}" shell \
    "run-as $PKG sh -c 'mkdir -p files/cast_bench && cp /data/local/tmp/cast_bench_command.json files/cast_bench/command.json && rm -f files/cast_bench/command_result.json'"
  "${ADB[@]}" logcat -c >/dev/null 2>&1 || true
  "${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true
  "${ADB[@]}" shell am start -n "$PKG/$ACTIVITY" >/dev/null
  deadline=$((SECONDS + 900))
  while (( SECONDS < deadline )); do
    if "${ADB[@]}" shell "run-as $PKG cat files/cast_bench/command_result.json" \
        > "$OUT/command_result.json" 2>/dev/null && [[ -s "$OUT/command_result.json" ]]; then
      break
    fi
    sleep 3
  done
  "${ADB[@]}" logcat -d -s flutter:I > "$OUT/logcat.txt" 2>/dev/null || true
  if [[ ! -s "$OUT/command_result.json" ]]; then
    echo "离线命令没写出结果；看 $OUT/logcat.txt" >&2
    exit 1
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$OUT/command_result.json" <<'PYRESULT'
import json, sys
result = json.load(open(sys.argv[1]))
print('label      :', result.get('label'))
print('ok         :', result.get('ok'), '| 返回码', result.get('returnCode'),
      '| 墙钟', result.get('wallClockMs'), 'ms')
print('--- 日志 ---')
print(result.get('logs', ''))
PYRESULT
  fi
  exit 0
fi

log "推送固定输入"
"${ADB[@]}" push "$OUT/inputs/." "$REMOTE_INPUTS/" >/dev/null
"${ADB[@]}" shell \
  "run-as $PKG sh -c 'mkdir -p files/cast_bench_inputs && cp $REMOTE_INPUTS/* files/cast_bench_inputs/'"

for name in source_1080p_30s.mp4 sticker_alpha.png beat_120bpm_30s.wav; do
  local_size=$(stat -c %s "$OUT/inputs/$name")
  remote_size=$("${ADB[@]}" shell \
    "run-as $PKG stat -c %s files/cast_bench_inputs/$name" | tr -d '\r')
  if [[ "$local_size" != "$remote_size" ]]; then
    echo "推送到设备后字节数不一致：$name 本地 $local_size 设备 $remote_size" >&2
    exit 2
  fi
done
log "固定输入已就位（字节数与宿主一致）"

# 4) 环境快照与热采样
{
  echo "=== $(date -Is) 目标环境 ==="
  "${ADB[@]}" shell getprop ro.product.model
  "${ADB[@]}" shell getprop ro.product.cpu.abi
  "${ADB[@]}" shell getprop ro.build.version.release
  "${ADB[@]}" shell getprop ro.build.version.sdk
  "${ADB[@]}" shell getprop ro.hardware
  echo "--- 编解码器服务 ---"
  "${ADB[@]}" shell service list | grep -i -E "codec|media.c2" || true
  echo "--- 平台编码器（若能列出）---"
  "${ADB[@]}" shell dumpsys media.codec 2>&1 | head -40 || true
} > "$OUT/device_env.txt" 2>&1

sample_thermal() {
  {
    echo "=== $(date -Is) ==="
    "${ADB[@]}" shell dumpsys battery 2>/dev/null |
      grep -E "level|temperature|status" || true
    "${ADB[@]}" shell dumpsys thermalservice 2>/dev/null |
      grep -E "Thermal Status|mStatus|Temperature" | head -20 || true
    for zone in /sys/class/thermal/thermal_zone*/temp; do
      [[ -r "$zone" ]] || continue
      echo "host $(dirname "$zone" | xargs basename): $(cat "$zone")"
    done
    nvidia-smi --query-gpu=temperature.gpu,clocks.sm,clocks_event_reasons.active \
      --format=csv,noheader 2>/dev/null || true
  } >> "$OUT/thermal.log" 2>&1
}

: > "$OUT/thermal.log"
sample_thermal
( while true; do sleep 15; sample_thermal; done ) &
THERMAL_PID=$!
trap 'kill "$THERMAL_PID" 2>/dev/null || true' EXIT

# 5) 起跑，等设备侧把报告写出来
"${ADB[@]}" shell svc power stayon true >/dev/null 2>&1 || true
"${ADB[@]}" logcat -c >/dev/null 2>&1 || true
"${ADB[@]}" shell am force-stop "$PKG" >/dev/null 2>&1 || true
# 上一轮的报告与离线命令都留在应用私有目录里：先清掉，免得开始轮询就拿到旧读数、
# 或者被上一次的 command.json 顶掉整轮计时。
"${ADB[@]}" shell \
  "run-as $PKG sh -c 'rm -f files/cast_bench/cast_render_bench_device.json files/cast_bench/command.json files/cast_bench/command_result.json'" \
  >/dev/null 2>&1 || true
log "启动计时入口（每档 $RUNS 遍）"
"${ADB[@]}" shell am start -n "$PKG/$ACTIVITY" >/dev/null

deadline=$((SECONDS + BUDGET))
started=$SECONDS
done_ok=0
while (( SECONDS < deadline )); do
  if "${ADB[@]}" shell "run-as $PKG cat files/cast_bench/cast_render_bench_device.json" \
      > "$OUT/device_report.json" 2>/dev/null && [[ -s "$OUT/device_report.json" ]]; then
    done_ok=1
    break
  fi
  # 进程没了又一直没有报告 = 入口崩了/被系统杀了，早点说话，别耗满预算。
  if (( SECONDS - started > 120 )) && ! "${ADB[@]}" shell pidof "$PKG" >/dev/null 2>&1; then
    echo "计时入口的进程已退出、报告也没写出；看 $OUT/logcat.txt" >&2
    break
  fi
  sleep 10
done

"${ADB[@]}" logcat -d -s flutter:I > "$OUT/logcat.txt" 2>/dev/null || true

if [[ "$done_ok" != 1 ]]; then
  echo "计时入口没在 ${BUDGET}s 内写出报告；看 $OUT/logcat.txt" >&2
  exit 1
fi

# 现场日志一并拉回（冒烟与组件名探针）：出不了片时它们是唯一证据。
for artifact in smoke_1s.log encoder_probe.log; do
  "${ADB[@]}" exec-out "run-as $PKG cat files/cast_bench/$artifact" \
    > "$OUT/$artifact" 2>/dev/null || true
done

log "报告：$OUT/device_report.json"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$OUT/device_report.json" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
summary = report.get('summary', {})
pick = report.get('codecPick')
print('runner      :', report.get('runner'), '| ffmpeg', report.get('ffmpeg'))
print('codecPick   :', pick)
print('inputs      :', report.get('inputs', {}).get('origin'))
for key in ('p1080', 'p720'):
    timing = summary.get(key)
    if not timing:
        print(f'{key:12}: 没有可用读数')
        continue
    print(f"{key:12}: 中位 {timing['medianMs']}ms "
          f"(min {timing['minMs']} / max {timing['maxMs']}, "
          f"{timing['realtimeFactor']:.2f}× 实时)")
print('分辨率系数  :', summary.get('resolutionCoefficient'))
print('被剔除的跑  :', summary.get('rejectedRuns'))
PY
fi
