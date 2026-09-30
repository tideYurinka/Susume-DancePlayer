#!/usr/bin/env python3
"""生成版本清单 latest.json（release-and-update 票 03）。

发布流水线在构建出 arm64 release 包之后调用本脚本，把包的真实字节数与
`pubspec.yaml` 的版本号写成固定地址的版本清单；下载页与 App 的更新检查
读同一份清单，因此五个字段的口径只在这里定义一次。

用法:
    tool/release_manifest.py --size 81234567 --tag v0.1.0 --out latest.json

- 版本名与构建号的真源只有 `pubspec.yaml` 的 `x.y.z+n`，本脚本不接受覆盖。
- 更新说明取自 `--tag` 指定 tag 的注解消息（`git tag -a`）；轻量 tag 或
  不存在的 tag 一律失败——发布必须有注解说明。
- 包地址写死在公开自定义域上，形如
  `releases/<版本名>/susume-<版本名>-arm64.apk`（spec「对象布局与缓存」）。

`MANIFEST_PUBSPEC` / `MANIFEST_GIT_DIR` 只给测试指向临时仓库夹具，生产
不设。
"""

import argparse
import json
import os
import re
import subprocess
import sys

PUBLIC_ORIGIN = "https://dl.yurinka.top"
"""清单与包对象的公开自定义域（spec 契约里写死的固定地址）。"""

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_VERSION_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)


def fail(message):
    sys.stderr.write("release_manifest: %s\n" % message)
    raise SystemExit(1)


def pubspec_version():
    """从 `pubspec.yaml` 的 `version: x.y.z+n` 读出版本名与构建号。"""
    path = os.environ.get("MANIFEST_PUBSPEC", os.path.join(_REPO_ROOT, "pubspec.yaml"))
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as exc:
        fail("读不到 %s: %s" % (path, exc))
    match = _VERSION_RE.search(text)
    if not match:
        fail("%s 里没有 `version: x.y.z+n`" % path)
    return match.group(1), match.group(2)


def tag_notes(tag):
    """该 tag 的注解消息；tag 不存在或不是注解 tag 都失败。"""
    git_dir = os.environ.get("MANIFEST_GIT_DIR") or _REPO_ROOT
    kind = subprocess.run(
        ["git", "-C", git_dir, "cat-file", "-t", "refs/tags/" + tag],
        capture_output=True,
        text=True,
    )
    if kind.returncode != 0 or kind.stdout.strip() != "tag":
        fail("tag %s 不存在或不是 `git tag -a` 注解 tag" % tag)
    notes = subprocess.run(
        ["git", "-C", git_dir, "tag", "-l", "--format=%(contents)", tag],
        capture_output=True,
        text=True,
    )
    if notes.returncode != 0:
        fail("读 tag %s 的注解失败: %s" % (tag, notes.stderr.strip()))
    message = notes.stdout.strip()
    if not message:
        fail("tag %s 的注解消息为空" % tag)
    return message


def positive_int(raw, what):
    try:
        value = int(raw)
    except (TypeError, ValueError):
        fail("%s 不是整数: %r" % (what, raw))
    if value <= 0:
        fail("%s 必须为正数: %d" % (what, value))
    return value


def main():
    parser = argparse.ArgumentParser(description="生成版本清单 latest.json")
    parser.add_argument("--size", required=True, help="安装包字节数")
    parser.add_argument("--tag", required=True, help="发布 tag 名")
    parser.add_argument("--out", required=True, help="写出的清单路径")
    args = parser.parse_args()

    version_name, build_number = pubspec_version()
    manifest = {
        "build_number": positive_int(build_number, "构建号"),
        "version_name": version_name,
        "size": positive_int(args.size, "安装包字节数"),
        "apk_url": "%s/releases/%s/susume-%s-arm64.apk"
        % (PUBLIC_ORIGIN, version_name, version_name),
        "notes": tag_notes(args.tag),
    }
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, ensure_ascii=False)
        handle.write("\n")


if __name__ == "__main__":
    main()
