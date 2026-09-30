/// 跨发布版本夹具生成器。
///
/// 夹具网格 = 「发布版 × 文档」：`test/fixtures/cross_release/<发布版>/<文档>.json`
/// 各一份真实文件。**地板夹具（v0.1.0）一次性手钉**、键名按 tag v0.1.0 的
/// 真实 schema 构造，不由本脚本改写；此后每一格由本脚本从地板夹具沿该文档
/// 的版本政策升到该发布版的版本号机械产出，因此同一发布版重复运行幂等。
///
/// 本脚本是**纯 Dart**（零 Flutter 依赖），只 import 零 Flutter 依赖的
/// 版本政策件与两份有迁移链的文档；链为空的地板由 v0.1.0 夹具的 `version`
/// 提供（不新增第二处版本事实）。构建前或 CI 里可直接：
///
///   dart run tool/generate_cross_release_fixtures.dart            # 全部发布版
///   dart run tool/generate_cross_release_fixtures.dart v0.1.3     # 单个发布版
///
/// 生成结果只写测试夹具目录，不进产品路径。
library;

import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/core/document_version_policy.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';

/// 夹具根目录（相对仓库根）。
const String crossReleaseFixturesRoot = 'test/fixtures/cross_release';

/// 地板发布版：该版夹具一次性手钉，本脚本只读不写。
const String floorRelease = 'v0.1.0';

/// 发布版次序（历史事实：`git tag` 的 v0.1.0–v0.1.3）。
const List<String> crossReleaseReleases = [
  'v0.1.0',
  'v0.1.1',
  'v0.1.2',
  'v0.1.3',
];

/// 被抬过版本的文档 → 发布版 → 该发布版落盘的版本号（历史事实，逐 tag
/// 源码核对）。未列出的文档在所有发布版都停在地板。
///
/// 核对来源：`git show v0.1.3:lib/persistence/marker_document.dart`
/// 的 `schemaVersion = 8`（v0.1.0–v0.1.2 为 7）。
const Map<String, Map<String, int>> _releaseBumps = {
  'markers': {'v0.1.3': 8},
};

/// 一份文档的迁移链政策（只有真正有链的文档需要；本脚本只静态 import
/// 零 Flutter 依赖的两份，其余六份链为空、无需政策参与升位）。
DocumentVersionPolicy? _chainPolicy(String docKey) => switch (docKey) {
  'markers' => MarkersDocument.versionPolicy,
  'local' => LocalDocument.versionPolicy,
  _ => null,
};

/// 把地板发布版夹具沿 [policy] 升到 [target] 版本（步骤只改形状，版本号
/// 由本函数每级写一次，与政策自身的升位口径一致）。[target] 必须落在
/// 地板与本版之间。
Map<String, Object?> _advanceTo(
  DocumentVersionPolicy policy,
  Map<String, Object?> floorJson,
  int target,
) {
  if (target < policy.floor || target > policy.currentVersion) {
    throw StateError(
      '目标版本 $target 不在政策链 [${policy.floor}..${policy.currentVersion}] 内',
    );
  }
  var json = floorJson;
  for (var v = policy.floor; v < target; v++) {
    json = {...policy.steps[v - policy.floor].up(json), 'version': v + 1};
  }
  return json;
}

/// 某一发布版里某份文档的版本号：有抬版本记录的按记录，否则停在地板。
int _versionAt(String docKey, String release, int floor) =>
    _releaseBumps[docKey]?[release] ?? floor;

String _encode(Map<String, Object?> json) =>
    '${const JsonEncoder.withIndent('  ').convert(json)}\n';

/// 把版本网格写进 [repositoryRoot]，返回写出的仓库相对路径（已排序）。
///
/// [releaseSelection] 为空时写全部发布版；地板发布版（v0.1.0）只读手钉
/// 夹具、不重写。内容未变的文件不重写（幂等的可观察形式：工作区无抖动）。
Set<String> generateCrossReleaseFixtures({
  required Directory repositoryRoot,
  Set<String> releaseSelection = const {},
}) {
  final root = Directory('${repositoryRoot.path}/$crossReleaseFixturesRoot');
  final floorDir = Directory('${root.path}/$floorRelease');
  if (!floorDir.existsSync()) {
    throw StateError('地板夹具目录不存在：${floorDir.path}');
  }
  final docKeys =
      floorDir
          .listSync()
          .whereType<File>()
          .map((file) => file.uri.pathSegments.last)
          .where((name) => name.endsWith('.json'))
          .map((name) => name.substring(0, name.length - '.json'.length))
          .toList()
        ..sort();

  final selected = releaseSelection.isEmpty
      ? crossReleaseReleases.toSet()
      : releaseSelection;
  final written = <String>{};
  for (final release in crossReleaseReleases.where(selected.contains)) {
    if (release == floorRelease) continue;
    final releaseDir = Directory('${root.path}/$release')
      ..createSync(recursive: true);
    for (final docKey in docKeys) {
      final floorJson = jsonDecode(
        File('${floorDir.path}/$docKey.json').readAsStringSync(),
      ) as Map<String, Object?>;
      final floor = floorJson['version'];
      if (floor is! int) {
        throw StateError('$floorRelease/$docKey.json 的 version 不是整数');
      }
      final target = _versionAt(docKey, release, floor);
      final Map<String, Object?> cell;
      if (target == floor) {
        cell = floorJson;
      } else {
        final policy = _chainPolicy(docKey);
        if (policy == null) {
          throw StateError(
            '$release 的 $docKey 版本为 $target（高于地板 $floor），'
            '但该文档的政策链未被本脚本导入；请在 _chainPolicy 里补上。',
          );
        }
        if (policy.floor != floor) {
          throw StateError(
            '$docKey 的地板夹具 version=$floor 与政策地板 ${policy.floor} 不一致',
          );
        }
        cell = _advanceTo(policy, floorJson, target);
      }
      final file = File('${releaseDir.path}/$docKey.json');
      final encoded = _encode(cell);
      if (!file.existsSync() || file.readAsStringSync() != encoded) {
        file.writeAsStringSync(encoded);
      }
      written.add('$crossReleaseFixturesRoot/$release/$docKey.json');
    }
  }
  return written;
}

void main(List<String> args) {
  final releaseSelection = args.toSet();
  final unknown = releaseSelection.difference(crossReleaseReleases.toSet());
  if (unknown.isNotEmpty) {
    stderr.writeln('未知发布版：${unknown.join(', ')}');
    exitCode = 2;
    return;
  }
  final written = generateCrossReleaseFixtures(
    repositoryRoot: Directory.current,
    releaseSelection: releaseSelection,
  );
  stdout.writeln('跨发布版本夹具：写出 ${written.length} 格');
}
