#!/usr/bin/env bash
# R2 凭据体检（release-and-update 票 04）。
#
# 用与正式发布完全同一条上传路径真做一次「写入 → 从公开域名回读 → 删除」，
# 让凭据错配在发布之前被发现。只碰 PROBE_KEY 指向的探针对象，且探针键必须
# 以 probe/ 开头，因此不会读也不会写任何发布产物（releases/、latest.json）。
#
# 需要：R2_BUCKET、R2_ACCOUNT_ID、PROBE_KEY；可选 PUBLIC_ORIGIN（默认本项
# 目的公开自定义域）。凭据仍走 AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY。
#
# 退出码 0 表示三步都成立且探针对象已清理；任何一步失败都以非零退出，并在
# stderr 指出失败的阶段（写入 / 回读 / 删除）。
set -uo pipefail

: "${R2_BUCKET:?缺少 R2_BUCKET}"
: "${R2_ACCOUNT_ID:?缺少 R2_ACCOUNT_ID}"
: "${PROBE_KEY:?缺少 PROBE_KEY}"
PUBLIC_ORIGIN="${PUBLIC_ORIGIN:-https://dl.yurinka.top}"

case "$PROBE_KEY" in
  probe/*) ;;
  *)
    echo "凭据体检失败：PROBE_KEY 必须以 probe/ 开头（只允许碰探针对象）：$PROBE_KEY" >&2
    exit 1
    ;;
esac

ENDPOINT="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
OBJECT="s3://${R2_BUCKET}/${PROBE_KEY}"
URL="${PUBLIC_ORIGIN}/${PROBE_KEY}"
BODY="susume-r2-probe $(date -u +%Y-%m-%dT%H:%M:%SZ) ${RANDOM}${RANDOM}"

stage="写入"
uploaded=0

cleanup() {
  if [ "$uploaded" = 1 ]; then
    aws s3 rm "$OBJECT" --endpoint-url "$ENDPOINT" >/dev/null 2>&1 || true
  fi
}
fail() {
  echo "凭据体检失败：${stage} 阶段——$1" >&2
  exit 1
}
trap cleanup EXIT

# 1) 写入：与正式发布同一条 aws s3 cp 路径。no-store 避免回读到中间缓存。
printf '%s' "$BODY" | aws s3 cp - "$OBJECT" \
  --endpoint-url "$ENDPOINT" \
  --content-type text/plain \
  --cache-control no-store ||
  fail "经 S3 兼容接口写入探针对象失败"
uploaded=1

# 2) 回读：必须能从公开自定义域按同一条键取回，且内容与写入的一致。
stage="回读"
readback="$(curl -fsS "$URL")" ||
  fail "从公开域名回读失败：$URL 取不到或不是 2xx"
[ "$readback" = "$BODY" ] ||
  fail "从公开域名回读到的内容与写入的不一致：$URL"

# 3) 删除。
stage="删除"
aws s3 rm "$OBJECT" --endpoint-url "$ENDPOINT" ||
  fail "删除探针对象失败"
uploaded=0

# 4) 确认删干净：公开地址不再返回 2xx。
if curl -fsS "$URL" >/dev/null 2>&1; then
  fail "探针对象删除后仍能从公开域名读到：$URL"
fi

echo "凭据体检通过：写入 / 公开回读 / 删除 三步都成立，探针对象已清理干净（${PROBE_KEY}）"
