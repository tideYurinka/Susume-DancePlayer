import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 条目图标接线：行图标按条目 id
/// 查常量表，已登记条目与在盘条目 id 一一覆盖、图标两两不重复；缺登记时用
/// **调用方直接给出的兜底图标**——帮助中心的手册分组给手册那枚、教程分组给教程
/// 那枚，新加条目不登记也照常取到图标。条目 id 由目录名现算、目录名带数字前缀。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('条目图标', () {
    late HelpContent content;
    setUpAll(() async {
      content = await loadHelpContent(rootBundle);
    });

    test('图标两两不重复', () {
      final icons = helpEntryIcons.values.toList();
      expect(icons.toSet(), hasLength(icons.length));
    });

    test('「问题反馈」那枚图标区别于教程兜底与操作类教程', () {
      expect(Icons.feedback_outlined, isNot(helpTutorialEntryFallbackIcon));
      expect(Icons.feedback_outlined, isNot(helpEntryIcons['下载视频']));
      expect(Icons.feedback_outlined, isNot(helpEntryIcons['免费视频变清晰']));
    });

    test('在盘的帮助条目 id 都已登记进图标表', () {
      for (final entry in [...content.manualChapters, ...content.tutorials]) {
        expect(helpEntryIcons, contains(entry.id), reason: entry.id);
      }
      // 「节拍」章与播放器节拍提示槽同一枚图标。
      expect(helpEntryIcons['节拍'], Icons.graphic_eq);
      // 「分段」章与播放器「自动分段」槽同一枚图标。
      expect(helpEntryIcons['分段'], Icons.view_week);
    });

    test('缺登记的条目：兜底图标由调用方给，手册与教程各取自己那枚', () {
      expect(
        helpEntryIcon('未来新章', fallbackIcon: helpManualEntryFallbackIcon),
        Icons.menu_book_outlined,
      );
      expect(
        helpEntryIcon('未来新教程', fallbackIcon: helpTutorialEntryFallbackIcon),
        Icons.school_outlined,
      );
      // 已登记的条目不受兜底图标影响。
      expect(
        helpEntryIcon('下载视频', fallbackIcon: helpManualEntryFallbackIcon),
        Icons.file_download_outlined,
      );
    });

    test('条目目录名带数字前缀，id 取目录名去数字前缀；两组各自排好序', () {
      for (final group in [content.manualChapters, content.tutorials]) {
        for (final entry in group) {
          expect(
            entry.directory.split('/').last,
            matches(RegExp(r'^\d+-')),
            reason: '目录名要带数字前缀定序',
          );
          expect(
            entry.id,
            helpDocumentIdOfDirectory(entry.directory),
            reason: 'id 由目录名现算（生产口径与展示口径同一处取得）',
          );
        }
        final prefixes = [
          for (final entry in group)
            int.parse(
              RegExp(r'^(\d+)')
                  .firstMatch(entry.directory.split('/').last)!
                  .group(1)!,
            ),
        ];
        expect(prefixes, List<int>.from(prefixes)..sort(), reason: '按数字前缀升序');
      }
    });
  });
}
