#!/usr/bin/env bash
# 一次性生成测试版签名用的那把测试 keystore（ADR-0003）。
#
# 测试版与正式版各持一把钥：这样测试包之间能原地覆盖升级，而正式版的升级凭据
# 不落到测试者手里。本脚本写两样东西——
#   ${SUSUME_TEST_KEYSTORE:-~/.susume/susume-test.jks}   测试 keystore
#   android/key-test.properties                          指向它的凭据（gitignored）
# 口令由你输入，不进 shell 历史。**这把钥丢了或换了，已装测试版的测试者就只能
# 卸载重装**，请与正式钥一样备份。
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "${repo_root}"

keystore="${SUSUME_TEST_KEYSTORE:-${HOME}/.susume/susume-test.jks}"
key_alias="${SUSUME_TEST_KEY_ALIAS:-susume-test}"

if [ -e "${keystore}" ]; then
  echo "已存在测试 keystore：${keystore}" >&2
  echo "要换一把请先自己备份并删除它——换钥等于让测试者卸载重装。" >&2
  exit 1
fi

read -r -s -p "测试 keystore 口令（store 与 key 共用，同正式那把的惯例）：" password
echo
read -r -s -p "再输一遍：" password_again
echo
if [ -z "${password}" ] || [ "${password}" != "${password_again}" ]; then
  echo "两次输入不一致或为空，未生成任何东西。" >&2
  exit 1
fi

mkdir -p "$(dirname "${keystore}")"
keytool -genkeypair -v \
  -keystore "${keystore}" \
  -storetype PKCS12 \
  -alias "${key_alias}" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Susume Test, O=Susume, C=CN" \
  -storepass "${password}" \
  -keypass "${password}"

umask 077
cat > android/key-test.properties <<EOF
storeFile=${keystore}
keyAlias=${key_alias}
storePassword=${password}
keyPassword=${password}
EOF
chmod 600 android/key-test.properties

cat <<EOF

好了：
  keystore      ${keystore}
  凭据          android/key-test.properties（gitignored）

本机构建测试包：  tool/build_test_apk.sh

要在 CI 上出测试包（.github/workflows/test-apk.yml），把下面两样加到仓库：
  secret  ANDROID_TEST_KEYSTORE_BASE64 = 以下输出
  secret  ANDROID_TEST_KEYSTORE_PASSWORD = 刚才那把钥的口令
  variable ANDROID_TEST_KEY_ALIAS = ${key_alias}

EOF
base64 -w0 "${keystore}"
echo
