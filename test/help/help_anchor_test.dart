import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// 文档内锚点：slug 算法与标题表解析。
/// 断言只落在装载结果与解析结果这些可观察输出上。
void main() {
  group('标题 slug（与 VSCode 预览、GitHub 同一套）', () {
    test('全角标点被去掉，拉丁字母被小写', () {
      expect(helpHeadingSlug('方法三：电脑下载B站视频'), '方法三电脑下载b站视频');
    });

    test('空白变连字符，半角标点也被去掉，下划线保留', () {
      expect(
        helpHeadingSlug('Download Video (Part 2)!'),
        'download-video-part-2',
      );
      expect(helpHeadingSlug('  调进度  '), '调进度');
      expect(helpHeadingSlug('步骤_说明'), '步骤_说明');
    });
  });

  group('标题表解析', () {
    test('按出现顺序给出各级标题的原文与 slug', () {
      final headings = helpHeadings('# 下载视频\n\n正文。\n\n## 方法一\n\n### 细节\n');
      expect(
        [for (final h in headings) (h.text, h.slug)],
        [('下载视频', '下载视频'), ('方法一', '方法一'), ('细节', '细节')],
      );
    });

    test('折叠块内的标题不进标题表：块内收起时不登记锚点', () {
      final headings = helpHeadings(
        '# 下载视频\n'
        '\n'
        '## 方法一\n'
        '\n'
        '<details>\n'
        '<summary>帮助作者</summary>\n'
        '## 块内标题\n'
        '块内正文。\n'
        '</details>\n',
      );
      expect(
        [for (final h in headings) h.text],
        ['下载视频', '方法一'],
        reason: '标题表就是锚点真能落点的那一份',
      );
      expect(resolveHelpAnchor(headings, '块内标题'), isNull);
    });
  });

  group('锚点解析', () {
    final headings = helpHeadings('''
# 下载视频

## 方法一：微信小程序下载

## 方法三：电脑下载B站视频

## 调进度
''');

    test('slug 命中', () {
      expect(resolveHelpAnchor(headings, '方法三电脑下载b站视频'), '方法三电脑下载b站视频');
    });

    test('原文前缀兜底', () {
      expect(resolveHelpAnchor(headings, '方法三'), '方法三电脑下载b站视频');
    });

    test('找不到目标返回 null', () {
      expect(resolveHelpAnchor(headings, '不存在的小节'), isNull);
    });

    test('原文前缀命中多条标题不算命中', () {
      final headings = helpHeadings('## 调进度要点\n\n## 调进度进阶\n');
      expect(resolveHelpAnchor(headings, '调进度'), isNull);
    });
  });
}
