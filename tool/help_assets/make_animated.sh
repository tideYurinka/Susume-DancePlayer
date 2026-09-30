#!/usr/bin/env bash
# 真机录屏 → 帮助条目配图（无声 WebP 动图，宽 720，3–12 秒，字幕烧进画面，
# 单条 ≤1 MB）。产出落在条目自己的资产目录里，文件名与条目正文的
# `![…](文件名)` 一字一致；产出成功后自动把该条目目录登记进 pubspec.yaml 的
# 同分组段末（幂等）。
# 护栏与登记实现在同目录的 entry_assets.sh 里，source 引入；拷贝本脚本时把它一起带上。
#
# 用法：
#   tool/help_assets/make_animated.sh --input rec.mp4 \
#     --out assets/help/guide/01-快捷手势/two_level_seek.webp \
#     --subtitle "双指滑：三倍速快进快退" --start 2 --duration 6
#   不给 --input 时从真机录屏（此时须导出真机序列号：export ADB_SERIAL=<serial>，
#   也可用 --device 覆盖；--record-seconds 限时）。
#
# --out 必须落在三类条目目录之一：assets/help/guide/<NN-名称>/、
# assets/help/tutorials/<NN-名称>/、assets/about/<NN-名称>/，且条目目录须已存在。
# 规格由脚本执行并校验：字幕必填（烧进画面）、时长不在 3–12 秒、
# 宽度 ≠ 720 或产出超 1 MB 都会报错退出，不产出半成品。
set -euo pipefail

OUT_WIDTH=720
MIN_SECONDS=3
MAX_SECONDS=12
MAX_BYTES=$((1024 * 1024))

input='' out='' subtitle='' device="${ADB_SERIAL:-}"
start=0 duration=8 fps=12 record_seconds=20
font="$(fc-match -f '%{file}' ':lang=zh' 2>/dev/null || true)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --subtitle) subtitle="$2"; shift 2 ;;
    --device) device="$2"; shift 2 ;;
    --font) font="$2"; shift 2 ;;
    --start) start="$2"; shift 2 ;;
    --duration) duration="$2"; shift 2 ;;
    --fps) fps="$2"; shift 2 ;;
    --record-seconds) record_seconds="$2"; shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

source "$(dirname "${BASH_SOURCE[0]}")/entry_assets.sh"
require_asset_out "$out"
awk -v d="$duration" -v lo="$MIN_SECONDS" -v hi="$MAX_SECONDS" \
  'BEGIN { exit !(d >= lo && d <= hi) }' || {
  echo "--duration 必须在 ${MIN_SECONDS}–${MAX_SECONDS} 秒：$duration" >&2; exit 2; }
[[ -n "$font" && -f "$font" ]] || { echo "找不到中文字体（fc-match :lang=zh）" >&2; exit 1; }
[[ -n "$subtitle" ]] || { echo "--subtitle 必填（规格：字幕烧进画面）" >&2; exit 2; }

work="$(mktemp -d)"
trap 'trash-put "$work" 2>/dev/null || true' EXIT

if [[ -z "$input" ]]; then
  [[ -n "$device" ]] || {
    echo "不给 --input 时须指定设备：导出真机序列号（export ADB_SERIAL=<serial>）或用 --device" >&2
    exit 2; }
  echo "从真机 $device 录屏 ${record_seconds} 秒…"
  adb -s "$device" exec-out screenrecord --time-limit "$record_seconds" \
    > "$work/raw.mp4"
  input="$work/raw.mp4"
fi
[[ -f "$input" ]] || { echo "输入不存在：$input" >&2; exit 1; }

# 字幕烧进画面（drawtext 的转义：冒号、单引号、反斜杠、百分号）；
# -an 去音轨。libwebp_anim 逐帧按输入时间戳封装动图。
escaped="${subtitle//\\/\\\\}"
escaped="${escaped//:/\\:}"
escaped="${escaped//\'/\\\'}"
escaped="${escaped//%/\\%}"
filters=("scale=${OUT_WIDTH}:-2" "fps=$fps"
  "drawtext=fontfile=${font}:text='${escaped}':fontsize=36:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=h-text_h-40")
filter_chain="$(IFS=,; echo "${filters[*]}")"

ok=0
for quality in 70 60 50 40 30; do
  tmp="$work/attempt_$quality.webp"
  ffmpeg -hide_banner -loglevel error -y \
    -ss "$start" -t "$duration" -i "$input" \
    -vf "$filter_chain" -an \
    -c:v libwebp_anim -lossless 0 -q:v "$quality" -loop 0 \
    "$tmp"
  if [[ $(stat -c%s "$tmp") -le $MAX_BYTES ]]; then
    mv "$tmp" "$out"; ok=1; break
  fi
done
[[ $ok -eq 1 ]] || { echo "压缩到最低质量仍超 ${MAX_BYTES} 字节：$out" >&2; exit 1; }

# 规格校验：宽 720、帧数对应的时长在 3–12 秒、无音轨、≤1 MB、
# 动图封装完整（ANMF 帧块数与 identify 读到的帧数一致）。
width="$(identify -format '%w\n' "$out[0]")"
out_frames="$(identify "$out" | wc -l)"
anmf_frames="$(python3 - "$out" <<'PYEOF'
import struct, sys
d = open(sys.argv[1], 'rb').read()
assert d[0:4] == b'RIFF' and d[8:12] == b'WEBP', 'not a webp file'
i, n = 12, 0
while i < len(d):
    fourcc = d[i:i+4]
    size = struct.unpack('<I', d[i+4:i+8])[0]
    if fourcc == b'ANMF':
        n += 1
    i += 8 + size + (size & 1)
print(n)
PYEOF
)"
size="$(stat -c%s "$out")"
seconds="$(awk -v n="$out_frames" -v fps="$fps" 'BEGIN { printf "%.2f", n / fps }')"

fail=0
[[ "$width" == "$OUT_WIDTH" ]] || { echo "规格不达标：宽度 $width ≠ $OUT_WIDTH" >&2; fail=1; }
awk -v s="$seconds" -v lo="$MIN_SECONDS" -v hi="$MAX_SECONDS" \
  'BEGIN { exit !(s >= lo && s <= hi) }' || {
  echo "规格不达标：产出时长 ${seconds}s 不在 ${MIN_SECONDS}–${MAX_SECONDS} 秒" >&2; fail=1; }
[[ "$anmf_frames" == "$out_frames" ]] || {
  echo "规格不达标：动图封装不完整（ANMF $anmf_frames 帧 ≠ 读取 $out_frames 帧）" >&2; fail=1; }
[[ "$size" -le $MAX_BYTES ]] || { echo "规格不达标：$size 字节超 ${MAX_BYTES}" >&2; fail=1; }
[[ $fail -eq 0 ]] || exit 1

echo "动图就绪：$out（宽 $width，${seconds}s，无音轨，$size 字节）"

register_asset_dir "$(dirname "$out")"
