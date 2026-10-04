import 'dart:io';

import 'package:dance_learning_app/about/contributor_roster.dart';
import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/contributor_assets_fixture.dart';
import '../helpers/fake_help_asset_bundle.dart';

/// 贡献者名单的装载：走既有的可注入资产包测试缝（假资产跑真枚举、真解析
/// YAML、真读 Markdown）。断言只落在**装载结果**上——名单顺序、每位贡献者的
/// 显示名与角色、他自己那份个人介绍正文、头像在不在盘上，以及名单为空 /
/// 缺文件 / 多一位时的降级；随包真资产由本件末尾一组直接读盘校验。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('装载', () {
    test('名单按资产里的顺序逐位取出：id、显示名与角色', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle({
          contributorRosterAsset: contributorRosterYaml([
            ContributorFixture('zeta', '末位', '插画'),
            ContributorFixture('alpha', '首位', '项目发起者'),
          ]),
          contributorIntroAsset('zeta'): '# 末位\n\n插画自述。\n',
          contributorIntroAsset('alpha'): '# 首位\n\n发起自述。\n',
        }),
      );

      expect(roster.contributors.map((c) => c.id).toList(), [
        'zeta',
        'alpha',
      ], reason: '按资产里的顺序，不按 id 重排');
      expect(roster.contributors.map((c) => c.displayName).toList(), [
        '末位',
        '首位',
      ]);
      expect(roster.contributors.map((c) => c.role).toList(), ['插画', '项目发起者']);
    });

    test('每位贡献者取到自己的个人介绍正文：标题、折叠段与引用的图都从他自己目录读', () async {
      final rewardKey = '${contributorDirectory('alpha')}/reward.png';
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle(
          {
            contributorRosterAsset: contributorRosterYaml([
              ContributorFixture('alpha', '首位', '项目发起者'),
              ContributorFixture('zeta', '末位', '插画'),
            ]),
            contributorIntroAsset('alpha'):
                '# 首位\n'
                '\n'
                '发起自述。\n'
                '\n'
                '<details>\n'
                '<summary>赞赏</summary>\n'
                '![赞赏码](reward.png)\n'
                '</details>\n',
          },
          binary: {rewardKey: onePixelPng},
        ),
      );

      final alpha = roster.contributors.first;
      expect(alpha.intro.title, '首位');
      expect(
        alpha.intro.bodyMarkdown,
        isNot(contains('# 首位')),
        reason: '一级标题不进正文',
      );
      expect(
        alpha.intro.bodySegments.whereType<HelpFoldSegment>(),
        hasLength(1),
      );
      expect(alpha.intro.imageAssets, contains(rewardKey));
      expect(
        roster.contributors[1].intro.markdown,
        isEmpty,
        reason: '另一位没写正文，不影响前面那位',
      );
    });

    test('头像文件在盘上才给出：约定名 avatar.webp；不在盘上时为 null', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle(
          {
            contributorRosterAsset: contributorRosterYaml([
              ContributorFixture('alpha', '首位', '项目发起者'),
              ContributorFixture('zeta', '末位', '插画'),
            ]),
            contributorIntroAsset('alpha'): '# 首位\n\n自述。\n',
            contributorIntroAsset('zeta'): '# 末位\n\n自述。\n',
          },
          binary: {contributorAvatarAsset('alpha'): onePixelPng},
        ),
      );

      expect(
        roster.contributors.first.avatarAsset,
        contributorAvatarAsset('alpha'),
      );
      expect(
        roster.contributors[1].avatarAsset,
        isNull,
        reason: '盘上没有头像就不给出一个坏 key',
      );
    });

    test('名单里的「头像」可改文件名：按它找；文件不在盘上仍为 null', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle(
          {
            contributorRosterAsset: contributorRosterYaml([
              ContributorFixture('alpha', '首位', '项目发起者', avatar: 'me.webp'),
              ContributorFixture('zeta', '末位', '插画', avatar: 'me.webp'),
            ]),
            contributorIntroAsset('alpha'): '# 首位\n\n自述。\n',
            contributorIntroAsset('zeta'): '# 末位\n\n自述。\n',
          },
          binary: {contributorAvatarAsset('alpha', 'me.webp'): onePixelPng},
        ),
      );

      expect(
        roster.contributors.first.avatarAsset,
        contributorAvatarAsset('alpha', 'me.webp'),
      );
      expect(roster.contributors[1].avatarAsset, isNull);
    });

    test('名单为空：空列表 / 缺整份资产 / 坏 YAML 都按空名单处理，不崩', () async {
      for (final assets in <Map<String, String>>[
        {contributorRosterAsset: 'contributors: []\n'},
        {contributorRosterAsset: '不是一个映射'},
        const {},
      ]) {
        final roster = await loadContributorRoster(FakeHelpAssetBundle(assets));
        expect(roster.contributors, isEmpty, reason: '$assets');
      }
    });

    test('缺 id 的记录跳过：定位不到他的目录；其余记录照常', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle({
          contributorRosterAsset:
              'contributors:\n'
              '  - 显示名: 无名\n'
              '    角色: 插画\n'
              '  - id: alpha\n'
              '    显示名: 首位\n'
              '    角色: 项目发起者\n',
          contributorIntroAsset('alpha'): '# 首位\n\n自述。\n',
        }),
      );

      expect(roster.contributors.map((c) => c.id).toList(), ['alpha']);
    });

    test('多一位：新的一位取到自己的目录与头像，已在的那位不受影响', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle(
          {
            contributorRosterAsset: contributorRosterYaml([
              ContributorFixture('alpha', '首位', '项目发起者'),
              ContributorFixture('zeta', '末位', '插画', avatar: 'me.webp'),
              ContributorFixture('omega', '第三位', '测试'),
            ]),
            contributorIntroAsset('alpha'): '# 首位\n\n自述。\n',
            contributorIntroAsset('omega'): '# 第三位\n\n第三份自述。\n',
          },
          binary: {
            contributorAvatarAsset('alpha'): onePixelPng,
            contributorAvatarAsset('zeta', 'me.webp'): onePixelPng,
          },
        ),
      );

      expect(roster.contributors.map((c) => c.id).toList(), [
        'alpha',
        'zeta',
        'omega',
      ]);
      expect(
        roster.contributors[0].avatarAsset,
        contributorAvatarAsset('alpha'),
      );
      expect(
        roster.contributors[1].avatarAsset,
        contributorAvatarAsset('zeta', 'me.webp'),
      );
      expect(roster.contributors[2].intro.title, '第三位');
      expect(roster.contributors[2].avatarAsset, isNull);
    });

    test('缺个人介绍：他仍按名单顺序在场，正文为空', () async {
      final roster = await loadContributorRoster(
        FakeHelpAssetBundle({
          contributorRosterAsset: contributorRosterYaml([
            ContributorFixture('alpha', '首位', '项目发起者'),
          ]),
        }),
      );

      expect(roster.contributors.single.displayName, '首位');
      expect(roster.contributors.single.intro.markdown, isEmpty);
      expect(roster.contributors.single.intro.bodySegments, isEmpty);
    });
  });

  group('随包资产', () {
    test('名单与磁盘上每位贡献者的目录一一对应', () async {
      final roster = await loadContributorRoster(rootBundle);
      expect(roster.contributors, isNotEmpty, reason: '关于页至少要有一位贡献者');

      final onDisk = [
        for (final entity in Directory(aboutContentAssetDir).listSync())
          if (entity is Directory) entity.path.replaceAll('\\', '/'),
      ]..sort();
      expect(
        roster.contributors.map((c) => contributorDirectory(c.id)).toList()
          ..sort(),
        onDisk,
        reason: '名单与磁盘目录一一对应（新增一位要补 YAML 与 pubspec 各一行）',
      );
    });

    test('每位贡献者的显示名、角色与他那份个人介绍都在', () async {
      final roster = await loadContributorRoster(rootBundle);

      for (final contributor in roster.contributors) {
        expect(contributor.displayName, isNotEmpty, reason: contributor.id);
        expect(contributor.role, isNotEmpty, reason: contributor.id);
        expect(
          contributor.intro.title,
          isNotEmpty,
          reason: '${contributor.id} 的个人介绍缺一级标题',
        );
        expect(
          contributor.intro.bodySegments,
          isNotEmpty,
          reason: '${contributor.id} 缺个人介绍正文',
        );
      }
    });

    test('个人介绍的一级标题就是他的显示名：改显示名不必动正文结构', () async {
      final roster = await loadContributorRoster(rootBundle);

      for (final contributor in roster.contributors) {
        expect(
          contributor.intro.title,
          contributor.displayName,
          reason: '${contributor.id} 的个人介绍一级标题应写成显示名（个人介绍页顶层档头与它同一处口径）',
        );
      }
    });

    test('给出的头像 key 一定在盘上；个人介绍引用的图都在盘上', () async {
      final roster = await loadContributorRoster(rootBundle);

      for (final contributor in roster.contributors) {
        final avatar = contributor.avatarAsset;
        if (avatar != null) {
          expect(
            File(avatar).existsSync(),
            isTrue,
            reason: '${contributor.id} 给出的头像不在盘上',
          );
        }
        for (final match in RegExp(
          r'!\[[^\]]*\]\(([^)]+)\)',
        ).allMatches(contributor.intro.markdown)) {
          final imageKey = '${contributor.intro.directory}/${match.group(1)!}';
          expect(
            contributor.intro.imageAssets,
            contains(imageKey),
            reason: '${contributor.id} 的个人介绍引用了 $imageKey，盘上没有',
          );
        }
      }
    });

    test('真随包资产的个人介绍正文里引用的 reward.png 被解析进他的图片集', () async {
      const contributorId = 'yurinka';
      const rewardKey = '$aboutContentAssetDir/$contributorId/reward.png';

      final roster = await loadContributorRoster(rootBundle);
      final contributor = roster.contributor(contributorId);
      expect(contributor, isNotNull, reason: '真名单里有 $contributorId');
      expect(
        File(rewardKey).existsSync(),
        isTrue,
        reason: '这张图确实随包（不读正文文本，只看磁盘）',
      );
      expect(
        contributor!.intro.imageAssets,
        contains(rewardKey),
        reason: '正文里引用的图归位进他这一份的图片集，渲染侧才画得出来',
      );
    });

    test('真资产里的折叠块被识别：块内引用的图归位到他自己的图片集', () async {
      final roster = await loadContributorRoster(rootBundle);

      // 折叠块写在哪一位、叫什么标题、引用哪张图都由作者自己定，这里只断言
      // 装载把每一块都切对了。
      final folds = <(Contributor, HelpFoldSegment)>[
        for (final contributor in roster.contributors)
          for (final segment in contributor.intro.bodySegments)
            if (segment is HelpFoldSegment) (contributor, segment),
      ];
      expect(folds, isNotEmpty, reason: '真资产里必须有折叠块，否则这条断言空转');

      for (final (contributor, fold) in folds) {
        expect(fold.title, isNotEmpty, reason: '${contributor.id} 的折叠块缺标题');

        // 切对了的标志：块内引用的图按目录解析得到资产；装载只登记在盘上的图，
        // 所以块内每张图都应落进他这一份的图片集。
        for (final match in RegExp(
          r'!\[[^\]]*\]\(([^)]+)\)',
        ).allMatches(fold.markdown)) {
          final assetKey = '${contributor.intro.directory}/${match.group(1)!}';
          expect(
            contributor.intro.imageAssets,
            contains(assetKey),
            reason: '${contributor.id} 的折叠块引用了 $assetKey，装载没归位',
          );
        }
      }
    });
  });
}
