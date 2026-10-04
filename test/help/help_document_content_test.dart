import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/help_fold_broken_cases.dart';

/// 帮助文档正文装载：输入侧是假资产包，输出侧是
/// 一个条目的渲染模型。断言只落在**可观察的装载结果**上——原文、一级标题、
/// 图片资产 key、缺内容时的降级。
void main() {
  const directory = 'assets/help/tutorials/01-下载视频';
  const markdownKey = '$directory/下载视频.md';

  test('按 id 取条目正文：原文照录，一级标题与存在的同目录图片解析出来', () async {
    const source = '''
# 下载视频

第一段说明。

## 方法一

1. 第一步
2. 第二步
![示意图](download_video.jpg)

普通**粗体**与裸网址 https://example.com/a
''';
    final bundle = FakeHelpAssetBundle(
      {markdownKey: source},
      binary: {'$directory/download_video.jpg': onePixelPng},
    );

    final content = await loadHelpDocumentContent(
      bundle,
      id: '下载视频',
      directory: directory,
    );

    expect(content.id, '下载视频');
    expect(content.directory, directory);
    expect(content.markdown, source, reason: '装载不加工原文（不做任何规范化预处理）');
    expect(content.title, '下载视频');
    expect(content.imageAssets, {'$directory/download_video.jpg'});
  });

  test('一次性图文切片：取第一个二级标题那一节，引言与其后的方法不出现', () async {
    const source = '''
# 下载视频

把舞蹈视频存到手机相册，再导入 App 练习。

## 方法一

> 注意：建议使用方法三

1. 第一步
![示意图](download_video.jpg)

## 方法二

方法二的正文。
''';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle(
        {markdownKey: source},
        binary: {'$directory/download_video.jpg': onePixelPng},
      ),
      id: '下载视频',
      directory: directory,
    );

    expect(
      content.firstSectionMarkdown,
      '## 方法一\n\n> 注意：建议使用方法三\n\n1. 第一步\n![示意图](download_video.jpg)',
      reason: '从第一个二级标题那一行起、到下一个二级标题之前，文字一字不改',
    );
  });

  test('一次性图文切片：只有一个二级标题时切到篇末', () async {
    const source = '''
# 标题

引言。

## 唯一方法

1. 第一步
2. 第二步
''';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '标题',
      directory: directory,
    );

    expect(content.firstSectionMarkdown, '## 唯一方法\n\n1. 第一步\n2. 第二步');
  });

  test('一次性图文切片：一个二级标题都没有时正文为空', () async {
    const source = '''
# 标题

只有引言与一段正文。
''';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '标题',
      directory: directory,
    );

    expect(content.firstSectionMarkdown, isEmpty);
  });

  test('目录里没有正文：正文为空串、标题为空，不抛错', () async {
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle(const {}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.markdown, isEmpty);
    expect(content.title, isNull);
    expect(content.imageAssets, isEmpty);
  });

  test('去标题正文：一级标题在首行，只去掉那一行', () async {
    const source = '''
# 下载视频

第一段。
''';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.markdown, source, reason: '原文一个字不改写');
    expect(content.bodyMarkdown, '\n第一段。\n');
  });

  test('去标题正文：一级标题不在首行，只去掉那一行', () async {
    const source = '''
前言。

   # 下载视频

第一段。
''';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.bodyMarkdown, '前言。\n\n\n第一段。\n');
    expect(content.title, '下载视频');
  });

  test('去标题正文：没有一级标题，正文保持原文', () async {
    const source = '## 小节\n\n正文。\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.title, isNull);
    expect(content.bodyMarkdown, source);
  });

  test('去标题正文：只有标题没有正文，去标题后为空', () async {
    const source = '# 下载视频\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.title, '下载视频');
    expect(content.bodyMarkdown, isEmpty);
  });

  test('正文没有一级标题：标题为空，正文照常', () async {
    const source = '## 只有二级标题\n\n正文照常。\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.title, isNull);
    expect(content.markdown, source);
  });

  test('正文引用的图片不在盘上：不进图片集（渲染时跳过、不留空框）', () async {
    const source = '# 标题\n\n![缺图](missing.png)\n\n![在盘](there.png)\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle(
        {markdownKey: source},
        binary: {'$directory/there.png': onePixelPng},
      ),
      id: '下载视频',
      directory: directory,
    );

    expect(content.imageAssets, {'$directory/there.png'});
  });

  test('带 scheme 的图片地址不属于本方言，不解析成资产 key', () async {
    const source = '# 标题\n\n![网图](https://example.com/a.png)\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({markdownKey: source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.imageAssets, isEmpty);
  });

  test('图片名带 ./ 前缀：按目录内相对路径归位到同目录资产', () async {
    const source = '# 标题\n\n![截图](./shot.png)\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle(
        {markdownKey: source},
        binary: {'$directory/shot.png': onePixelPng},
      ),
      id: '下载视频',
      directory: directory,
    );

    expect(content.imageAssets, {'$directory/shot.png'});
  });

  test('目录里的 md 文件名不参与 id：换成任意名字仍取到同一条', () async {
    const source = '# 下载视频\n\n正文。\n';
    final content = await loadHelpDocumentContent(
      FakeHelpAssetBundle({'$directory/随便什么名字.md': source}),
      id: '下载视频',
      directory: directory,
    );

    expect(content.markdown, source);
    expect(content.title, '下载视频');
  });

  group('折叠块切段（`<details>` + `<summary>`）', () {
    test('独立成段的折叠块切出来：前后普通段照旧，块内 Markdown 一字不改', () {
      const source =
          '开头一段。\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '非常感谢\n'
          '\n'
          '- 甲\n'
          '- 乙\n'
          '</details>\n'
          '\n'
          '结尾一段。\n';

      final segments = helpMarkdownSegments(source);

      expect(segments, hasLength(3));
      expect((segments[0] as HelpTextSegment).markdown, '开头一段。\n');
      final fold = segments[1] as HelpFoldSegment;
      expect(fold.title, '帮助作者');
      expect(
        fold.markdown,
        '非常感谢\n\n- 甲\n- 乙',
        reason: '块内是整块 Markdown，文字一字不改',
      );
      expect((segments[2] as HelpTextSegment).markdown, '\n结尾一段。');
    });

    test('折叠块的标记本身不出现在普通段里', () {
      const source = '<details>\n<summary>标题</summary>\n正文。\n</details>\n';
      final segments = helpMarkdownSegments(source);
      expect(segments, hasLength(1));
      expect(segments.single, isA<HelpFoldSegment>());
    });

    test('一篇里的多个折叠块各自成段', () {
      const source =
          '<details>\n<summary>甲</summary>\n甲正文。\n</details>\n'
          '\n'
          '<details>\n<summary>乙</summary>\n乙正文。\n</details>\n';
      final segments = helpMarkdownSegments(source);
      expect(
        [for (final segment in segments) (segment as HelpFoldSegment).title],
        ['甲', '乙'],
      );
    });

    /// 不认的写法（清单与内容校验用例共用 `helpFoldBrokenCases`）：整块 HTML
    /// 留在普通段里（渲染件照旧丢弃根级 HTML）。
    void expectNotRecognized(String source) {
      final segments = helpMarkdownSegments(source);
      expect(
        segments.whereType<HelpFoldSegment>(),
        isEmpty,
        reason: '不应识别成折叠块',
      );
      expect(
        segments.whereType<HelpTextSegment>().map((s) => s.markdown).join(),
        contains('<details>'),
        reason: '未识别的块原样留在正文里',
      );
    }

    for (final broken in helpFoldBrokenCases.entries) {
      test('${broken.key}：不认', () => expectNotRecognized(broken.value));
    }

    test('折叠块里的图片进图片集：块内引用照常解析到同目录资产', () async {
      const source =
          '# 标题\n'
          '\n'
          '<details>\n'
          '<summary>赞赏</summary>\n'
          '![赞赏码](reward.png)\n'
          '</details>\n';
      final content = await loadHelpDocumentContent(
        FakeHelpAssetBundle(
          {markdownKey: source},
          binary: {'$directory/reward.png': onePixelPng},
        ),
        id: '下载视频',
        directory: directory,
      );

      expect(content.imageAssets, {'$directory/reward.png'});
      expect(
        content.bodySegments.whereType<HelpFoldSegment>().single.markdown,
        '![赞赏码](reward.png)',
      );
    });

    test('一次性图文切片里的折叠块跟着它所在的那一节走', () async {
      const source =
          '# 标题\n'
          '\n'
          '## 方法一\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '正文。\n'
          '</details>\n'
          '\n'
          '## 方法二\n'
          '\n'
          '后面的方法。\n';
      final content = await loadHelpDocumentContent(
        FakeHelpAssetBundle({markdownKey: source}),
        id: '标题',
        directory: directory,
      );

      expect(
        [
          for (final segment in content.firstSectionSegments)
            if (segment is HelpFoldSegment) segment.title,
        ],
        ['帮助作者'],
      );
    });

    test('折叠块内的二级标题不算节边界：切片含整块，到块外的下一个二级标题为止', () async {
      const source =
          '# 标题\n'
          '\n'
          '## 方法一\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '## 块内小节\n'
          '块内正文。\n'
          '</details>\n'
          '\n'
          '## 方法二\n'
          '\n'
          '后面的方法。\n';
      final content = await loadHelpDocumentContent(
        FakeHelpAssetBundle({markdownKey: source}),
        id: '标题',
        directory: directory,
      );

      final fold = content.firstSectionSegments
          .whereType<HelpFoldSegment>()
          .single;
      expect(fold.title, '帮助作者');
      expect(fold.markdown, '## 块内小节\n块内正文。');
      expect(
        content.firstSectionMarkdown,
        '## 方法一\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '## 块内小节\n'
        '块内正文。\n'
        '</details>',
        reason: '切片按块外的二级标题收口，块内标题不当边界',
      );
    });
  });
}
