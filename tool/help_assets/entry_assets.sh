#!/usr/bin/env bash
# 帮助条目配图的共用件：--out 护栏与 pubspec.yaml 同分组登记。
# 仅供同目录下的 make_static.sh / make_animated.sh 在 `set -euo pipefail`
# 之后 source，不独立运行；函数里的 exit 即调用脚本退出。

[[ "${BASH_SOURCE[0]}" != "$0" ]] || {
  echo "entry_assets.sh 只供 make_static.sh / make_animated.sh source，不独立运行" >&2; exit 2; }

# 合法产出 = 三类条目目录（guide / tutorials / about）下一级的 .webp。
readonly HELP_ASSET_OUT_RE='^assets/(help/(guide|tutorials)|about)/[^/]+/[^/]+\.webp$'

# 校验 --out：必须落在条目目录里，且条目目录已存在（先有正文条目，再有配图）。
require_asset_out() {
  local out="$1"
  [[ -n "$out" ]] || { echo "--out 必填（条目目录下的 .webp 路径）" >&2; exit 2; }
  [[ "$out" =~ $HELP_ASSET_OUT_RE ]] || {
    echo "--out 必须落在条目目录里：assets/help/guide/<NN-名称>/、assets/help/tutorials/<NN-名称>/ 或 assets/about/<NN-名称>/ 下的 .webp，当前：$out" >&2; exit 2; }
  [[ -d "$(dirname "$out")" ]] || {
    echo "条目目录不存在：$(dirname "$out")（图与正文同放，先建好条目目录）" >&2; exit 2; }
}

# 把条目目录登记进 pubspec.yaml：按所属分组插进同段末（guide→guide 段末、
# tutorials→tutorials 段末、about→about 段末）；该组在 pubspec.yaml 里没有
# 落点时退回 assets/help/ 段末，两处都没有则报错，不假装登记成功。
# 幂等（已登记则跳过）。
register_asset_dir() {
  local dir="$1" line group=''
  line="    - $dir/"
  if grep -qxF "$line" pubspec.yaml; then
    return 0
  fi
  case "$dir" in
    assets/help/guide/*) group='assets/help/guide/' ;;
    assets/help/tutorials/*) group='assets/help/tutorials/' ;;
    assets/about/*) group='assets/about/' ;;
  esac
  awk -v line="$line" -v group="$group" '
    {
      lines[NR] = $0
      if (group != "" && $0 ~ ("^[[:space:]]*- " group)) last_group = NR
      if ($0 ~ /^[[:space:]]*- assets\/help\//) last_help = NR
    }
    END {
      anchor = (last_group != "") ? last_group : last_help
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == anchor) print line
      }
    }
  ' pubspec.yaml > pubspec.yaml.tmp && mv pubspec.yaml.tmp pubspec.yaml
  if ! grep -qxF "$line" pubspec.yaml; then
    echo "pubspec.yaml 里没有 ${group} 段也没有 assets/help/ 段，未能登记：$dir" >&2
    return 1
  fi
  echo "已登记进 pubspec.yaml：$dir"
}
