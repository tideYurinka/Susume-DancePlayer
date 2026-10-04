import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/help_fold_broken_cases.dart';

/// 内容校验：写坏的折叠块与其它 HTML。判定入口
/// 拿条目名 + 正文原文直接调用，真资产校验与这里的假内容用例走的是同一个
/// [helpMarkdownIssues]；识别口径与装载切段同一份（[helpMarkdownSegments]）。断言只落在可观察结果上——有没有报错、报的是哪一
/// 行、错误信息里有没有条目名。
void main() {
  /// 出错的条目名。
  const entryName = '下载视频';

  List<HelpMarkdownIssue> issuesOf(String markdown) =>
      helpMarkdownIssues(entryName: entryName, markdown: markdown);

  /// 断言 [line]（1 起）那一行被报出，原因含 [reason]，且错误信息里条目名与
  /// 行号都在。
  void expectIssueAt(
    String markdown, {
    required int line,
    required String reason,
  }) {
    final issues = issuesOf(markdown);
    expect(issues, isNotEmpty, reason: '写坏的内容必须报错，不能静默丢弃');
    final hit = issues.where((issue) => issue.line == line);
    expect(
      hit,
      isNotEmpty,
      reason: '第 $line 行应有一条：${issues.map((i) => i.message)}',
    );
    expect(hit.map((issue) => issue.reason), anyElement(contains(reason)));
    expect(hit.first.message, contains(entryName), reason: '错误信息要指出是哪个条目');
    expect(hit.first.message, contains('第 $line 行'), reason: '错误信息要指出行号');
  }

  group('每一类写坏各报一条（条目名 + 行号）', () {
    test('漏 `</details>`', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '非常感谢\n'
        '\n'
        '后面一段。\n',
        line: 3,
        reason: '</details>',
      );
    });

    test('缺 `<summary>`', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '正文。\n'
        '</details>\n',
        line: 3,
        reason: 'summary',
      );
    });

    test('`<summary>` 为空', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>   </summary>\n'
        '正文。\n'
        '</details>\n',
        line: 4,
        reason: 'summary',
      );
    });

    test('`<summary>` 不在紧跟的那一行', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '\n'
        '<summary>标题</summary>\n'
        '正文。\n'
        '</details>\n',
        line: 5,
        reason: '紧跟',
      );
    });

    test('块内出现一至三级标题', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '## 块内小节\n'
        '块内正文。\n'
        '</details>\n',
        line: 5,
        reason: '标题',
      );
    });

    test('正文里出现别的 HTML 标签（含折叠块内）', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '正文 <br> 换行。\n',
        line: 3,
        reason: 'HTML',
      );
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '<div>块内别的标签</div>\n'
        '</details>\n',
        line: 5,
        reason: 'HTML',
      );
    });

    test('正文里出现 HTML 注释', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<!-- 作者注 -->\n'
        '正文。\n',
        line: 3,
        reason: 'HTML',
      );
    });

    test('块内多了一行 `<summary>`（忘写上一块的 `</details>`）', () {
      expectIssueAt(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>甲</summary>\n'
        '正文。\n'
        '<summary>乙</summary>\n'
        '内容二。\n'
        '</details>\n',
        line: 6,
        reason: 'summary',
      );
    });

    test('`</details>` 没有独立成行：报在那一行，且不吞掉后文的写坏', () {
      final issues = issuesOf(
        '# 下载视频\n'
        '\n'
        '<details>\n'
        '<summary>标题</summary>\n'
        '正文。\n'
        '</details >\n'
        '\n'
        '<summary>游离</summary>\n',
      );
      expect(issues.map((issue) => issue.line).toSet(), {
        6,
        8,
      }, reason: '闭合行与它后面游离的 `<summary>` 各报一条：${issues.map((i) => i.message)}');
      expect(
        issues.firstWhere((issue) => issue.line == 6).reason,
        contains('details'),
      );
      expect(
        issues.firstWhere((issue) => issue.line == 8).reason,
        contains('summary'),
      );
    });
  });

  group('未识别的折叠块写法都由校验挡下（与装载切段同一口径）', () {
    test('每一种「不认」写法都报错', () {
      for (final broken in helpFoldBrokenCases.entries) {
        expect(
          issuesOf(broken.value),
          isNotEmpty,
          reason:
              '${broken.key}：未识别的折叠块在 App 里无声消失，校验必须报出：\n'
              '${broken.value}',
        );
      }
    });

    test('没写折叠块就不查折叠块', () {
      expect(issuesOf('# 标题\n\n正文。\n'), isEmpty);
    });
  });

  group('正常内容全部放行', () {
    test('正文里的裸网址、各级标题与文字里的尖括号都不算写坏', () {
      const source =
          '# 下载视频\n'
          '\n'
          '把视频存到手机相册，见 https://example.com/a 与 1 < 2。\n'
          '不等号写得再随意也不算标签：3 < 4 > 1、a <b。\n'
          '\n'
          '## 方法一\n'
          '\n'
          '### 子步骤\n'
          '\n'
          '> 注意：建议使用方法三\n'
          '\n'
          '1. 第一步\n'
          '2. 第二步\n'
          '\n'
          '![示意图](download_video.jpg)\n';

      expect(issuesOf(source), isEmpty);
    });

    test('折叠块内的段落、列表、图片、提示块与链接都放行', () {
      const source =
          '# 下载视频\n'
          '\n'
          '<details>\n'
          '<summary>帮助作者</summary>\n'
          '\n'
          '块内段落与 [链接](https://example.com)。\n'
          '\n'
          '- 甲\n'
          '- 乙\n'
          '\n'
          '![赞赏码](reward.png)\n'
          '\n'
          '> 块内提示\n'
          '\n'
          '</details>\n';

      expect(issuesOf(source), isEmpty);
    });

    test('多个折叠块各自放行', () {
      const source =
          '# 下载视频\n'
          '\n'
          '<details>\n'
          '<summary>甲</summary>\n'
          '甲正文。\n'
          '</details>\n'
          '\n'
          '<details>\n'
          '<summary>乙</summary>\n'
          '乙正文。\n'
          '</details>\n';

      expect(issuesOf(source), isEmpty);
    });
  });
}
