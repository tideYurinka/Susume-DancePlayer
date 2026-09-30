/// 贡献者名单装载：随包资产 → 上屏模型。
///
/// 名单住在关于页自己的资产目录 `assets/about/`：一份 `contributors.yaml`
/// 一位一条记录，每位贡献者一个以其 id 命名的目录，目录里放他自己那份个人
/// 介绍 Markdown（与帮助文档同一套方言与渲染模型）与约定名为 `avatar.webp`
/// 的头像。资产包注入复用 [helpAssetBundleProvider] 那一条，不新增同形注入点。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../help/help_documents.dart';

/// 贡献者名单资产的 key。
const String contributorRosterAssetKey = 'assets/about/contributors.yaml';

/// 关于页内容的资产根目录：名单一份 YAML，每位贡献者一个以其 id 命名的目录。
const String aboutContentAssetDirectory = 'assets/about';

/// 头像在贡献者自己目录下的约定文件名。
const String contributorAvatarFileName = 'avatar.webp';

/// 一位贡献者。
class Contributor {
  const Contributor({
    required this.id,
    required this.displayName,
    required this.role,
    required this.avatarAsset,
    required this.intro,
  });

  /// 稳定 id：显示名改了也不用动它；他的目录名与个人介绍落点都取它。
  final String id;

  /// 名单里的主标题。
  final String displayName;

  /// 名单里的副标题。
  final String role;

  /// 头像资产 key；盘上没有时为 null（渲染侧据此画占位件，不画坏图）。
  final String? avatarAsset;

  /// 他的个人介绍正文；目录里没有 Markdown 时正文为空。
  final HelpDocumentContent intro;
}

/// 贡献者名单：按资产里的顺序排列。
class ContributorRoster {
  const ContributorRoster({required this.contributors});

  final List<Contributor> contributors;

  /// 按稳定 id 查一位贡献者；找不到为 null。
  Contributor? contributor(String id) {
    for (final contributor in contributors) {
      if (contributor.id == id) return contributor;
    }
    return null;
  }
}

/// 名单装载的读面（与帮助内容共用同一个资产包注入点）。
final contributorRosterProvider = FutureProvider<ContributorRoster>(
  (ref) => loadContributorRoster(ref.watch(helpAssetBundleProvider)),
);

/// 装载贡献者名单：解析 YAML 的 `contributors` 列表（顺序即上屏顺序），逐位
/// 取他的显示名与角色，读他自己的个人介绍，并只把盘上确实存在的头像收进
/// [Contributor.avatarAsset]。
///
/// 名单读不出 / YAML 坏掉即名单视为空；某一条缺 id 时跳过该条（定位不到他的
/// 目录），不牵连其余；缺正文按「没有正文」处理。降级都在开发期由断言打出原因。
Future<ContributorRoster> loadContributorRoster(AssetBundle bundle) async {
  final keys = await loadAssetKeys(bundle);
  final contributors = <Contributor>[];
  for (final record in await _loadRecords(bundle)) {
    if (record.id.isEmpty) continue;
    contributors.add(
      Contributor(
        id: record.id,
        displayName: record.displayName,
        role: record.role,
        avatarAsset: _existingAvatarAsset(record, keys),
        intro: await loadHelpDocumentContent(
          bundle,
          id: record.id,
          directory: '$aboutContentAssetDirectory/${record.id}',
        ),
      ),
    );
  }
  return ContributorRoster(contributors: contributors);
}

/// 名单里一条记录的原文取值。
class _RosterRecord {
  const _RosterRecord({
    required this.id,
    required this.displayName,
    required this.role,
    required this.avatarFileName,
  });

  final String id;
  final String displayName;
  final String role;

  /// 记录里 `头像` 给的文件名；缺这一键时为空串（按约定名找）。
  final String avatarFileName;
}

/// 解析名单资产里的记录；读不出 / 结构不对时按空名单处理。
Future<List<_RosterRecord>> _loadRecords(AssetBundle bundle) async {
  try {
    final source = await bundle.loadString(
      contributorRosterAssetKey,
      cache: false,
    );
    final yaml = loadYaml(source);
    if (yaml is! YamlMap) {
      throw const FormatException('名单根节点不是一个映射');
    }
    final list = yaml['contributors'];
    if (list == null) return const [];
    if (list is! YamlList) {
      throw const FormatException('contributors 不是一个列表');
    }
    return [
      for (final item in list)
        if (item is YamlMap)
          _RosterRecord(
            id: _text(item['id']),
            displayName: _text(item['显示名']),
            role: _text(item['角色']),
            avatarFileName: _text(item['头像']),
          ),
    ];
  } on Object catch (error) {
    assert(() {
      debugPrint('贡献者名单装载失败，按空名单处理：$error');
      return true;
    }());
    return const [];
  }
}

/// 一条记录里的一个文本取值；缺这一键时为空串。
String _text(Object? value) => value is String ? value : '';

/// 头像资产 key：记录给的文件名（缺时取约定名）拼他自己的目录；盘上没有这个
/// 文件时返回 null——调用方据此画占位件。
String? _existingAvatarAsset(_RosterRecord record, List<String> keys) {
  final fileName = record.avatarFileName.isEmpty
      ? contributorAvatarFileName
      : record.avatarFileName;
  final key = '$aboutContentAssetDirectory/${record.id}/$fileName';
  return keys.contains(key) ? key : null;
}
