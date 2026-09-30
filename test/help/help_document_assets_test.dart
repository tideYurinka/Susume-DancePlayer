import 'dart:io';

import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/help_assets_fixture.dart';

/// 真资产的装载契约：直接读仓库里的 `assets/help/`，
/// 断言「下载视频」教程按 id 装载得到，一级标题、正文引用的图片与一字不改的
/// 原文都在。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HelpContent content;
  setUpAll(() async {
    content = await loadHelpContent(rootBundle);
  });

  test('真资产按 id 取到「下载视频」教程：原文、一级标题、图片非空', () {
    final document = content.document(downloadVideoTutorialId);

    expect(document, isNotNull);
    expect(document!.directory, downloadVideoTutorialDirectory);
    expect(document.title, '下载视频');
    expect(document.displayTitle, '下载视频');
    expect(document.markdown, isNotEmpty);
    expect(document.imageAssets, isNotEmpty);
  });

  test('真资产：装载拿到的正文与磁盘文件一字不差（不加工原文）', () {
    final onDisk = File(
      '$downloadVideoTutorialDirectory/下载视频.md',
    ).readAsStringSync();

    expect(content.document(downloadVideoTutorialId)!.markdown, onDisk);
  });

  test('真资产：问题反馈的条目名取正文一级标题，正文与磁盘一字不差', () {
    final entry = content.document('问题反馈');
    expect(entry, isNotNull);
    expect(entry!.title, '问题反馈', reason: '条目名取正文一级标题');
    expect(entry.displayTitle, '问题反馈');
    expect(
      entry.markdown,
      File('$feedbackTutorialDirectory/问题反馈.md').readAsStringSync(),
      reason: '作者写的正文一字不改',
    );
  });
}
