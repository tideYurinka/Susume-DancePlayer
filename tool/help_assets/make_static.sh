#!/usr/bin/env bash
# 真机截图加标注 → 帮助条目配图（WebP，宽 1080，单张 ≤200 KB）。
# 产出落在条目自己的资产目录里，文件名与条目正文的 `![…](文件名)` 一字一致；
# 产出成功后自动把该条目目录登记进 pubspec.yaml 的同分组段末（幂等）。
# 护栏与登记实现在同目录的 entry_assets.sh 里，source 引入；拷贝本脚本时把它一起带上。
#
# 用法：
#   tool/help_assets/make_static.sh --input shot.png \
#     --out assets/help/guide/03-节拍/beat_panel.webp \
#     --annotate "点这里打开节拍面板|50%|90%"
#   不给 --input 时从真机抓屏（此时须导出真机序列号：export ADB_SERIAL=<serial>，
#   也可用 --device 覆盖）。
#
# --annotate 参数格式：文字|横坐标|纵坐标（坐标为成图宽高的百分比），
# 可重复多次。
# --out 必须落在三类条目目录之一：assets/help/guide/<NN-名称>/、
# assets/help/tutorials/<NN-名称>/、assets/about/<NN-名称>/，且条目目录须已存在。
# 规格不达标（宽度 ≠ 1080 或 >200 KB）时脚本报错退出。
set -euo pipefail

OUT_WIDTH=1080
MAX_BYTES=$((200 * 1024))

input='' out='' device="${ADB_SERIAL:-}"
font="$(fc-match -f '%{file}' ':lang=zh' 2>/dev/null || true)"
annotates=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) input="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    --device) device="$2"; shift 2 ;;
    --font) font="$2"; shift 2 ;;
    --annotate) annotates+=("$2"); shift 2 ;;
    *) echo "未知参数：$1" >&2; exit 2 ;;
  esac
done

source "$(dirname "${BASH_SOURCE[0]}")/entry_assets.sh"
require_asset_out "$out"
[[ -n "$font" && -f "$font" ]] || { echo "找不到中文字体（fc-match :lang=zh）" >&2; exit 1; }

work="$(mktemp -d)"
trap 'trash-put "$work" 2>/dev/null || true' EXIT

if [[ -z "$input" ]]; then
  [[ -n "$device" ]] || {
    echo "不给 --input 时须指定设备：导出真机序列号（export ADB_SERIAL=<serial>）或用 --device" >&2
    exit 2; }
  echo "从真机 $device 抓屏…"
  adb -s "$device" exec-out screencap -p > "$work/raw.png"
  input="$work/raw.png"
fi
[[ -f "$input" ]] || { echo "输入不存在：$input" >&2; exit 1; }

# 标注：文字画在成图百分比坐标处（黄字黑描边）。百分比坐标在缩放后的
# 成图尺寸上换算成像素（annotate 只吃像素几何）。
read -r in_w in_h < <(identify -format '%w %h\n' "$input")
out_h=$(( in_h * OUT_WIDTH / in_w ))
px() { awk -v p="$1" -v base="$2" 'BEGIN { printf "%d", base * p / 100 }'; }
draw_args=(-pointsize 44 -fill yellow -stroke black -strokewidth 2)
for spec in "${annotates[@]}"; do
  IFS='|' read -r text x y <<<"$spec"
  draw_args+=(-annotate "+$(px "$x" "$OUT_WIDTH")+$(px "$y" "$out_h")" "$text")
done

ok=0
for quality in 90 80 70 60 50 40 30; do
  tmp="$work/attempt_$quality.webp"
  convert "$input" -resize "${OUT_WIDTH}x" -background none \
    -font "$font" "${draw_args[@]}" -quality "$quality" "$tmp"
  if [[ $(stat -c%s "$tmp") -le $MAX_BYTES ]]; then
    mv "$tmp" "$out"; ok=1; break
  fi
done
[[ $ok -eq 1 ]] || { echo "压缩到最低质量仍超 ${MAX_BYTES} 字节：$out" >&2; exit 1; }

width="$(identify -format '%w' "$out")"
size="$(stat -c%s "$out")"
if [[ "$width" != "$OUT_WIDTH" ]]; then
  echo "规格不达标：宽度 $width ≠ $OUT_WIDTH（$out）" >&2; exit 1
fi
echo "静图就绪：$out（宽 $width，$size 字节）"

register_asset_dir "$(dirname "$out")"
