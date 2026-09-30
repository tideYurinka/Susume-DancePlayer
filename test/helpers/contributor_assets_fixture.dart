import 'package:dance_learning_app/about/contributor_roster.dart';

/// 关于页内容资产的仓库内路径：名单资产与每位贡献者的目录都从装载模块的常量
/// 现算，测试与生产不会各维护一份路径字面量。
const String contributorRosterAsset = contributorRosterAssetKey;
const String aboutContentAssetDir = aboutContentAssetDirectory;

/// 一位贡献者的目录（目录名取他的 id）。
String contributorDirectory(String id) => '$aboutContentAssetDir/$id';

/// 一位贡献者个人介绍 Markdown 的资产 key（他目录里那唯一一份 `.md`）。
String contributorIntroAsset(String id) =>
    '${contributorDirectory(id)}/个人介绍.md';

/// 一位贡献者头像的资产 key；文件名缺省取装载模块的约定名。
String contributorAvatarAsset(
  String id, [
  String fileName = contributorAvatarFileName,
]) => '${contributorDirectory(id)}/$fileName';

/// 名单 YAML 里的一位贡献者：id、显示名与角色必给，头像文件名可缺（缺时按
/// 约定名 `avatar.webp` 找）。
class ContributorFixture {
  const ContributorFixture(this.id, this.displayName, this.role, {this.avatar});

  final String id;
  final String displayName;
  final String role;
  final String? avatar;
}

/// 假资产里那位贡献者：id 与真资产同一位，显示名与角色给确定值，不带头像。
const ContributorFixture sampleContributor = ContributorFixture(
  'yurinka',
  '汐荧_yurinka',
  '项目发起者',
);

/// 一份名单 YAML：`contributors` 列表按 [records] 的顺序逐条写出。
String contributorRosterYaml(List<ContributorFixture> records) {
  final buffer = StringBuffer('contributors:\n');
  for (final record in records) {
    buffer
      ..writeln('  - id: ${record.id}')
      ..writeln('    显示名: ${record.displayName}')
      ..writeln('    角色: ${record.role}');
    final avatar = record.avatar;
    if (avatar != null) buffer.writeln('    头像: $avatar');
  }
  return buffer.toString();
}
