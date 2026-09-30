#!/usr/bin/env python3
"""发布前的守卫（release-and-update 票 04；document-version-policy 票 06 加两条）。

流水线在**动手构建之前**调用本脚本。任一条守卫不成立，进程以非零退出，
失败信息以守卫名开头（`release_guard[<守卫>]: ...`），流水线据此一眼看出是
哪一条拦下的：

    tag-version               tag 名与 `pubspec.yaml` 的 version 名不一致
    build-number-conflict     构建号与远端已发布的相同（忘记递增 `n`）
    build-number-downgrade    构建号小于远端已发布的（降级）
    document-chain-coverage   某份文档的版本链没有从地板无缝连到本版/已分发版本
    document-floor-ratchet    某份文档的地板被抬高（只许不动或降低）

另有两个兜底失败名，分别对应"守卫自己的输入坏了"，不静默放行：
`pubspec-version`、`remote-manifest`、`document-registry`、`document-baseline`。

用法:
    tool/release_guard.py --tag v0.1.0 --remote-manifest /tmp/remote-latest.json
    tool/release_guard.py --documents-only

- 版本名与构建号的真源只有 `pubspec.yaml` 的 `x.y.z+n`（与
  `tool/release_manifest.py` 同一口径）；`RELEASE_GUARD_PUBSPEC` 只给测试
  指向临时夹具。
- 远端已发布的构建号从 `--remote-manifest` 指向的版本清单读；文件不存在或
  为空表示远端还没有发布过（首次发布），此时冲突与降级两条守卫没有可比对象，
  直接放行并在输出里说明。
- 文件存在但清单不可解析、或 `build_number` 缺失/不是正整数时一律失败：远端
  状态坏了不能当成"没有远端"，否则守卫会被静默绕过。
- 两条文档守卫**不依赖 Flutter**：直接解析 `lib/` 下的版本链声明与登记表
  （`RELEASE_GUARD_LIB` / `RELEASE_GUARD_REGISTRY` 只给测试指向临时夹具），
  逐份对照 `tool/document_version_baseline.json` 里登记的上一轮记录——链尾
  （哪些版本号曾随发布分发）与地板。`--documents-only` 让它们可以脱离 tag
  单独跑。
"""

import argparse
import json
import os
import re
import sys

_REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_VERSION_RE = re.compile(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)

# 版本链声明与登记表的源码形状（dart format 后的稳定写法）。守卫在装 Flutter
# 之前跑，因此只能从源码里读出「地板 + 各级迁移的 from」这两件事实。
_REGISTRY_ENTRY_RE = re.compile(
    r"'([A-Za-z0-9_]+)'\s*:\s*([A-Za-z0-9_]+)\.versionPolicy"
)
_POLICY_RE = re.compile(
    r"versionPolicy\s*=\s*DocumentVersionPolicy\(\s*(.*?)\)\s*;", re.DOTALL
)
_FLOOR_RE = re.compile(r"\bfloor:\s*(\d+)")
_STEP_RE = re.compile(r"MigrationStep\(\s*(\d+)\s*,")
_CLASS_RE = re.compile(r"\bclass\s+([A-Za-z0-9_]+)")

TAG_VERSION = "tag-version"
BUILD_NUMBER_CONFLICT = "build-number-conflict"
BUILD_NUMBER_DOWNGRADE = "build-number-downgrade"
REMOTE_MANIFEST = "remote-manifest"
PUBSPEC_VERSION = "pubspec-version"
DOCUMENT_CHAIN_COVERAGE = "document-chain-coverage"
DOCUMENT_FLOOR_RATCHET = "document-floor-ratchet"
DOCUMENT_REGISTRY = "document-registry"
DOCUMENT_BASELINE = "document-baseline"


def fail(guard, message):
    sys.stderr.write("release_guard[%s]: %s\n" % (guard, message))
    raise SystemExit(1)


def pubspec_version():
    """从 `pubspec.yaml` 的 `version: x.y.z+n` 读出版本名与构建号（整数）。"""
    path = os.environ.get(
        "RELEASE_GUARD_PUBSPEC", os.path.join(_REPO_ROOT, "pubspec.yaml")
    )
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as exc:
        fail(PUBSPEC_VERSION, "读不到 %s: %s" % (path, exc))
    match = _VERSION_RE.search(text)
    if not match:
        fail(PUBSPEC_VERSION, "%s 里没有 `version: x.y.z+n`" % path)
    return match.group(1), int(match.group(2))


def remote_build_number(path):
    """远端已发布的构建号；文件不存在或为空返回 None（首次发布）。"""
    if not os.path.exists(path) or os.path.getsize(path) == 0:
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            manifest = json.load(handle)
    except (OSError, ValueError) as exc:
        fail(REMOTE_MANIFEST, "读远端清单 %s 失败: %s" % (path, exc))
    if not isinstance(manifest, dict):
        fail(REMOTE_MANIFEST, "远端清单 %s 不是 JSON 对象" % path)
    value = manifest.get("build_number")
    if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
        fail(
            REMOTE_MANIFEST,
            "远端清单 %s 的 build_number 不是正整数: %r" % (path, value),
        )
    return value


def document_paths():
    """文档守卫的三个输入；`RELEASE_GUARD_*` 只给测试指向临时夹具。"""
    lib = os.environ.get("RELEASE_GUARD_LIB", os.path.join(_REPO_ROOT, "lib"))
    registry = os.environ.get(
        "RELEASE_GUARD_REGISTRY",
        os.path.join(lib, "persistence", "document_version_registry.dart"),
    )
    baseline = os.environ.get(
        "RELEASE_GUARD_BASELINE",
        os.path.join(_REPO_ROOT, "tool", "document_version_baseline.json"),
    )
    return lib, registry, baseline


def document_policies(lib):
    """扫 `lib/` 下每份文档的 `versionPolicy` 声明 → 类名 : (声明体, 文件)。"""
    policies = {}
    for dirpath, _, filenames in os.walk(lib):
        for filename in sorted(filenames):
            if not filename.endswith(".dart"):
                continue
            path = os.path.join(dirpath, filename)
            try:
                text = open(path, encoding="utf-8").read()
            except OSError as exc:
                fail(DOCUMENT_REGISTRY, "读不到 %s: %s" % (path, exc))
            classes = [(m.start(), m.group(1)) for m in _CLASS_RE.finditer(text)]
            for match in _POLICY_RE.finditer(text):
                owner = None
                for position, name in classes:
                    if position < match.start():
                        owner = name
                    else:
                        break
                if owner is None:
                    fail(
                        DOCUMENT_REGISTRY,
                        "%s 里有一处 versionPolicy 声明不属于任何类" % path,
                    )
                policies[owner] = (match.group(1), path)
    return policies


def registry_documents(registry):
    """登记表 `文档键 : 类名.versionPolicy` → 有序的 (键, 类名) 列表。"""
    try:
        text = open(registry, encoding="utf-8").read()
    except OSError as exc:
        fail(DOCUMENT_REGISTRY, "读不到 %s: %s" % (registry, exc))
    entries = _REGISTRY_ENTRY_RE.findall(text)
    if not entries:
        fail(DOCUMENT_REGISTRY, "%s 里没有读到任何登记项" % registry)
    keys = [key for key, _ in entries]
    if len(set(keys)) != len(keys):
        fail(DOCUMENT_REGISTRY, "%s 里有重复的文档键" % registry)
    return entries


def document_declarations(lib, registry):
    """登记表引用的每份文档 → 键 : (地板, 各级迁移的 from, 声明文件)。"""
    policies = document_policies(lib)
    declarations = {}
    for key, owner in registry_documents(registry):
        if owner not in policies:
            fail(
                DOCUMENT_REGISTRY,
                "登记项 %s 指向 %s.versionPolicy，但 %s 下找不到该声明"
                % (key, owner, lib),
            )
        body, path = policies[owner]
        match = _FLOOR_RE.search(body)
        if not match:
            fail(
                DOCUMENT_CHAIN_COVERAGE,
                "%s（%s.versionPolicy，%s）没有声明地板" % (key, owner, path),
            )
        floor = int(match.group(1))
        if floor < 1:
            fail(DOCUMENT_CHAIN_COVERAGE, "%s 的地板 %d 不是正整数" % (key, floor))
        step_froms = [int(raw) for raw in _STEP_RE.findall(body)]
        declarations[key] = (floor, step_froms, path)
    return declarations


def check_chain_coverage(declarations, baseline):
    """每份文档的链必须从地板逐级无缝连到（基准登记的）本版。"""
    for key, (floor, step_froms, _) in declarations.items():
        for index, raw in enumerate(step_froms):
            if raw != floor + index:
                fail(
                    DOCUMENT_CHAIN_COVERAGE,
                    "%s 的版本链在 v%d → v%d 这一级断开：期望 from=%d，实为 %d"
                    "（链必须从地板无缝连到本版，缺一级即失败）"
                    % (key, floor + index, floor + index + 1, floor + index, raw),
                )
        version = floor + len(step_froms)
        recorded = baseline.get(key)
        if recorded is not None and version != recorded["version"]:
            if version < recorded["version"]:
                fail(
                    DOCUMENT_CHAIN_COVERAGE,
                    "%s 的链尾只有 v%d，但 v%d 曾随发布分发——链必须从地板无缝"
                    "连到已分发过的版本（缺一级即失败）"
                    % (key, version, recorded["version"]),
                )
            fail(
                DOCUMENT_CHAIN_COVERAGE,
                "%s 的链尾已到 v%d，但基准清单还记着 v%d——本版须在同一提交里"
                "登记进基准" % (key, version, recorded["version"]),
            )


def baseline_records(path):
    """上一轮登记：文档键 → {floor, version}；坏输入失败，不静默放行。"""
    if not os.path.exists(path):
        fail(DOCUMENT_BASELINE, "读不到版本基准清单 %s" % path)
    try:
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError) as exc:
        fail(DOCUMENT_BASELINE, "读版本基准清单 %s 失败: %s" % (path, exc))
    if not isinstance(data, dict):
        fail(DOCUMENT_BASELINE, "版本基准清单 %s 不是 JSON 对象" % path)
    records = {}
    for key, value in data.items():
        if (
            not isinstance(value, dict)
            or not isinstance(value.get("floor"), int)
            or isinstance(value.get("floor"), bool)
            or value["floor"] < 1
            or not isinstance(value.get("version"), int)
            or isinstance(value.get("version"), bool)
            or value["version"] < value["floor"]
        ):
            fail(
                DOCUMENT_BASELINE,
                "版本基准清单 %s 的 %s 不是 {floor: 正整数, version: ≥floor}"
                % (path, key),
            )
        records[key] = {"floor": value["floor"], "version": value["version"]}
    return records


def floor_ratchet_problem(key, current, previous, baseline_path):
    """`None` = 放行；否则一条指向该文档的棘轮失败原因（只许不动或降低）。"""
    if previous is None:
        return "%s 是新登记的文档（地板 %d），须在同一提交里写进基准清单 %s" % (
            key,
            current,
            baseline_path,
        )
    if current is None:
        return (
            "%s 已不在登记表里，但基准清单 %s 仍记着地板 %d——文档移除须在同一"
            "提交里更新基准" % (key, baseline_path, previous)
        )
    if current > previous:
        return "%s 的地板被抬高：基准 %d → 当前 %d（地板只许不动或降低）" % (
            key,
            previous,
            current,
        )
    if current < previous:
        return (
            "%s 的地板降低到 %d，但基准清单 %s 仍记着 %d——降低必须与基准更新在"
            "同一提交里" % (key, current, baseline_path, previous)
        )
    return None


def check_floor_ratchet(declarations, baseline, baseline_path):
    """地板只许不动或降低；抬高即失败，降低须同提交更新基准。"""
    floors = {key: floor for key, (floor, _, _) in declarations.items()}
    for key in sorted(set(floors) | set(baseline)):
        problem = floor_ratchet_problem(
            key, floors.get(key), baseline.get(key, {}).get("floor"), baseline_path
        )
        if problem:
            fail(DOCUMENT_FLOOR_RATCHET, problem)


def check_documents():
    """两条文档守卫：覆盖检查与地板棘轮。"""
    lib, registry, baseline_path = document_paths()
    declarations = document_declarations(lib, registry)
    baseline = baseline_records(baseline_path)
    check_chain_coverage(declarations, baseline)
    check_floor_ratchet(declarations, baseline, baseline_path)

    print(
        "release_guard: 通过 %s / %s（%d 份文档）"
        % (DOCUMENT_CHAIN_COVERAGE, DOCUMENT_FLOOR_RATCHET, len(declarations))
    )


def main():
    parser = argparse.ArgumentParser(description="发布前的守卫")
    parser.add_argument("--tag", help="触发发布的 tag 名")
    parser.add_argument(
        "--remote-manifest",
        help="远端 latest.json 的本地副本；不存在表示首次发布",
    )
    parser.add_argument(
        "--documents-only",
        action="store_true",
        help="只跑两条文档守卫（不依赖 tag，可在装 Flutter 之前单独跑）",
    )
    args = parser.parse_args()

    if args.documents_only:
        check_documents()
        return

    if not args.tag:
        parser.error("--tag 必填（或用 --documents-only 只跑文档守卫）")

    version_name, build_number = pubspec_version()

    expected_tag = "v" + version_name
    if args.tag != expected_tag:
        fail(
            TAG_VERSION,
            "tag %s 与 pubspec.yaml 的 version %s+%d 不一致（应为 %s）"
            % (args.tag, version_name, build_number, expected_tag),
        )

    remote = (
        remote_build_number(args.remote_manifest)
        if args.remote_manifest
        else None
    )
    if remote is None:
        print(
            "release_guard: 远端还没有版本清单，按首次发布处理，"
            "跳过 %s / %s" % (BUILD_NUMBER_CONFLICT, BUILD_NUMBER_DOWNGRADE)
        )
    elif remote == build_number:
        fail(
            BUILD_NUMBER_CONFLICT,
            "构建号 %d 已存在于远端——pubspec.yaml 的 n 忘记递增" % build_number,
        )
    elif remote > build_number:
        fail(
            BUILD_NUMBER_DOWNGRADE,
            "构建号 %d 小于远端已有的 %d——不允许降级发布"
            % (build_number, remote),
        )

    print(
        "release_guard: 通过 %s / %s / %s"
        % (TAG_VERSION, BUILD_NUMBER_CONFLICT, BUILD_NUMBER_DOWNGRADE)
    )

    check_documents()


if __name__ == "__main__":
    main()
