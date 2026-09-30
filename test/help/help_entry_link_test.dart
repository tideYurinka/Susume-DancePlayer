import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/contributor_assets_fixture.dart';
import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/help_assets_fixture.dart';

/// 跨条目链接：正文里的相对路径链接解析成
/// 「条目 id + 锚点」。断言只落在解析结果上——目标条目 id、锚点、以及解析
/// 不到时的 null（调用方按外部链接处理）。
void main() {
  const manualDirectory = '$helpGuideAssetDir/02-控制界面概述';
  const segmentDirectory = '$helpGuideAssetDir/04-分段';
  const segmentDocument =
      '# 分段\n'
      '\n'
      '分段说明。\n'
      '\n'
      '## 调进度\n'
      '\n'
      '拖动即可。\n'
      '\n'
      '## 调进度的细节\n'
      '\n'
      '细节。\n';

  final bundle = FakeHelpAssetBundle({
    onboardingCopyAssetKey: helpOnboardingStub,
    '$manualDirectory/控制界面概述.md':
        '# 控制界面概述\n'
        '\n'
        '一行一段。\n',
    '$segmentDirectory/分段.md': segmentDocument,
    '$downloadVideoTutorialDirectory/下载视频.md': '# 下载视频\n\n正文。\n',
    contributorIntroAsset(sampleContributor.id): '# 汐荧_yurinka\n\n自述。\n',
  });

  Future<HelpEntryLink?> resolve(String href) async {
    final content = await loadHelpContent(bundle);
    return resolveHelpEntryLink(
      content: content,
      directory: manualDirectory,
      href: href,
    );
  }

  test('相对路径归一到帮助条目目录，得到目标条目 id', () async {
    final link = await resolve('../04-分段/分段.md');
    expect(link, isNotNull);
    expect(link!.documentId, '分段');
    expect(link.anchor, isNull);
  });

  test('`#` 之后交给既有的锚点解析：slug 精确命中', () async {
    final link = await resolve('../04-分段/分段.md#调进度');
    expect(link?.documentId, '分段');
    expect(link?.anchor, '调进度');
  });

  test('`#` 之后交给既有的锚点解析：原文前缀唯一命中也算', () async {
    final link = await resolve('../04-分段/分段.md#调进度的细');
    expect(link?.documentId, '分段');
    expect(link?.anchor, '调进度的细');
  });

  test('目标可以是手册与教程两组里任意一个已被扫到的条目', () async {
    expect(
      (await resolve('../../tutorials/01-下载视频/下载视频.md'))?.documentId,
      '下载视频',
    );
  });

  test('关于页的内容不是帮助条目：指向贡献者个人介绍的相对链接解析不到', () async {
    final content = await loadHelpContent(bundle);
    expect(content.document('汐荧_yurinka'), isNull, reason: '关于页内容不进帮助条目表');
    expect(
      await resolve('../../../about/yurinka/个人介绍.md'),
      isNull,
      reason: '解析不到即按外部链接处理',
    );
  });

  test('渲染器交回百分号转义的地址：先解回再解析', () async {
    final link = await resolve(
      '../04-%E5%88%86%E6%AE%B5/%E5%88%86%E6%AE%B5.md#%E8%B0%83%E8%BF%9B%E5%BA%A6',
    );
    expect(link?.documentId, '分段');
    expect(link?.anchor, '调进度');
  });

  test('解析不到条目：返回 null（按外部链接处理）', () async {
    // 写错目录（不在任何分组下、或指向未扫到的条目）解析不到。
    expect(await resolve('../99-不存在的章/不存在.md'), isNull);
    expect(await resolve('../../guide/99-不存在的章/不存在.md'), isNull);
    // 不是仓内相对 Markdown 路径的也不算。
    expect(await resolve('../04-分段/分段.txt'), isNull);
  });

  test('条目身份按目录定：文件名只提供 `.md` 形状', () async {
    final link = await resolve('../04-分段/任意名字.md');
    expect(link?.documentId, '分段');
  });

  test('锚点在目标条目里找不到、或命中多条：返回 null', () async {
    expect(await resolve('../04-分段/分段.md#没有的小节'), isNull);
    // 「调」前缀命中「调进度」与「调进度的细节」两条标题，不算命中。
    expect(await resolve('../04-分段/分段.md#调'), isNull);
  });

  test('外部网址与本文内锚点不归它管：返回 null', () async {
    expect(await resolve('https://example.com/a.md'), isNull);
    expect(await resolve('#调进度'), isNull);
    expect(await resolve(''), isNull);
  });

  group('内容校验', () {
    const sourceDirectory = '$helpGuideAssetDir/02-控制界面概述';
    const targetDirectory = '$helpGuideAssetDir/04-分段';
    const entryName = '控制界面概述';

    Future<List<HelpMarkdownIssue>> issuesOf(String markdown) async {
      final content = await loadHelpContent(
        FakeHelpAssetBundle({
          onboardingCopyAssetKey: helpOnboardingStub,
          '$sourceDirectory/控制界面概述.md': markdown,
          '$targetDirectory/分段.md':
              '# 分段\n'
              '\n'
              '## 调进度\n'
              '\n'
              '正文。\n'
              '\n'
              '## 调进度的细节\n'
              '\n'
              '正文。\n',
        }),
      );
      return helpLinkIssues(
        content: content,
        entry: content.document(entryName)!,
      );
    }

    test('写了跨条目链接、本文锚点与外部网址的正文全部放行', () async {
      final issues = await issuesOf(
        '# 控制界面概述\n'
        '\n'
        '见[《分段》](../04-分段/分段.md)与[调进度](../04-分段/分段.md#调进度)，'
        '还有[官网](https://example.com/a.md)。\n'
        '\n'
        '![图](../99-不存在/图.md)\n',
      );
      expect(issues, isEmpty, reason: '${issues.map((i) => i.message)}');
    });

    test('不是 `.md` 结尾的相对地址不属于本方言：不拦，运行时按外部链接复制', () async {
      final issues = await issuesOf(
        '# 控制界面概述\n'
        '\n'
        '见[图片](images/a.png)、[许可](./LICENSE)与[别的](a/b)。\n',
      );
      expect(issues, isEmpty, reason: '${issues.map((i) => i.message)}');
    });

    test('跨条目链接写错目录：报出条目名与行号', () async {
      final issues = await issuesOf(
        '# 控制界面概述\n'
        '\n'
        '见[《分段》](../99-不存在的章/不存在.md)。\n',
      );
      expect(issues, hasLength(1));
      expect(issues.single.line, 3);
      expect(issues.single.message, contains(entryName));
      expect(issues.single.reason, contains('不存在'));
    });

    test('锚点在目标条目里找不到、或命中多条：各报一条', () async {
      for (final anchor in ['没有的小节', '调']) {
        final issues = await issuesOf(
          '# 控制界面概述\n'
          '\n'
          '见[《分段》](../04-分段/分段.md#$anchor)。\n',
        );
        expect(issues, hasLength(1), reason: anchor);
        expect(issues.single.line, 3, reason: anchor);
      }
    });

    test('本文内锚点找不到目标标题：报出条目名与行号', () async {
      final issues = await issuesOf(
        '# 控制界面概述\n'
        '\n'
        '见[那一节](#没有的小节)。\n',
      );
      expect(issues, hasLength(1));
      expect(issues.single.line, 3);
      expect(issues.single.reason, contains('没有的小节'));
    });
  });
}
