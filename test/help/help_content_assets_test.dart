import 'dart:io';

import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_copy.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/help_assets_fixture.dart';

/// 内容校验测试：直接读仓库里的 `assets/help/`
/// 真资产，断言内容本身合规——每个条目目录恰一个带一级标题的 Markdown、
/// 正文引用的图片都存在且单张 ≤300 KB、`onboarding.yaml` 可解析、每个引导
/// 单元与引导步都有文案、正文里的折叠块与 HTML 写法合规。编译期保底撤掉之后
/// 由它接替。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 单张图片的进包预算。
  const int imageBudgetBytes = 300 * 1024;

  final guideDirectories = _entryDirectories(helpGuideAssetDir);
  final tutorialDirectories = _entryDirectories(helpTutorialsAssetDir);
  final entryDirectories = [...guideDirectories, ...tutorialDirectories];

  test('两个分组都扫到条目，磁盘上的每个条目目录都已登记', () async {
    expect(guideDirectories, isNotEmpty);
    expect(tutorialDirectories, hasLength(4));

    final content = await loadHelpContent(rootBundle);
    expect(
      content.manualChapters.map((d) => d.directory).toList()..sort(),
      guideDirectories.map(_normalize).toList()..sort(),
      reason: '使用手册的分组条目与磁盘目录一一对应（新增目录要补 pubspec 一行）',
    );
    expect(
      content.tutorials.map((d) => d.directory).toList()..sort(),
      tutorialDirectories.map(_normalize).toList()..sort(),
      reason: '教程分组条目与磁盘目录一一对应（新增目录要补 pubspec 一行）',
    );
    expect(
      content.tutorials.map((d) => d.id),
      contains(downloadVideoTutorialId),
      reason: '导入前图卡引用的教程 id 必须真的被扫到（两处走偏即失败）',
    );
  });

  test('关于页内容不进帮助条目表：帮助装载只认手册与教程两组', () async {
    final content = await loadHelpContent(rootBundle);

    expect(
      content.allDocuments.map((d) => d.id),
      isNot(contains('汐荧_yurinka')),
      reason: '贡献者的个人介绍不是帮助条目',
    );
  });

  test('每个条目目录恰一个 Markdown 且有一级标题', () async {
    final content = await loadHelpContent(rootBundle);
    for (final directory in entryDirectories) {
      final markdown = _markdownFilesIn(directory);
      expect(markdown, hasLength(1), reason: '$directory 里应恰有一个 Markdown');
      final source = markdown.single.readAsStringSync();
      expect(
        RegExp(r'^# .+', multiLine: true).hasMatch(source),
        isTrue,
        reason: '${markdown.single.path} 缺 `# ` 一级标题',
      );
    }

    for (final entry in content.allDocuments) {
      expect(entry.title, isNotNull, reason: '${entry.directory} 缺一级标题');
      expect(
        entry.listDescription,
        isNotEmpty,
        reason: '${entry.directory} 缺一句说明',
      );
    }
  });

  test('正文引用的图片都存在且单张 ≤300 KB', () {
    for (final directory in entryDirectories) {
      final markdownFiles = _markdownFilesIn(directory);
      expect(markdownFiles, hasLength(1), reason: '$directory 里应恰有一个 Markdown');
      final file = markdownFiles.single;
      final source = file.readAsStringSync();
      for (final match in RegExp(
        r'!\[[^\]]*\]\(([^)]+)\)',
      ).allMatches(source)) {
        final image = match.group(1)!;
        final imageFile = File('$directory/$image');
        expect(
          imageFile.existsSync(),
          isTrue,
          reason: '${file.path} 引用的 $image 不在盘上',
        );
        expect(
          imageFile.lengthSync(),
          lessThanOrEqualTo(imageBudgetBytes),
          reason: '$image 超出单张 300 KB 的进包预算',
        );
      }
    }
  });

  test('被一次性图文引用的教程至少有一个二级标题', () async {
    final content = await loadHelpContent(rootBundle);
    for (final step in helpGuideSteps) {
      final documentId = step.sourceDocumentId;
      if (documentId == null) continue;
      final entry = content.document(documentId);
      expect(entry, isNotNull, reason: documentId);
      expect(
        entry!.firstSectionMarkdown,
        isNotEmpty,
        reason: '$documentId 缺二级标题，一次性图文卡正文将为空',
      );
    }
  });

  test('每个条目的正文都通过折叠块与 HTML 校验：真资产全绿，末尾那段不算写坏', () {
    for (final directory in entryDirectories) {
      final file = _markdownFilesIn(directory).single;
      final issues = helpMarkdownIssues(
        entryName: helpDocumentIdOfDirectory(_normalize(directory)),
        markdown: file.readAsStringSync(),
      );
      expect(
        issues,
        isEmpty,
        reason:
            '${file.path} 写坏的地方：\n${issues.map((i) => i.message).join('\n')}',
      );
    }
  });

  test('正文里的链接落点都成立：本文锚点唯一命中，跨条目链接有目标且目标锚点唯一命中', () async {
    final content = await loadHelpContent(rootBundle);
    for (final entry in content.allDocuments) {
      final markdownFile = _markdownFilesIn(entry.directory).single;
      expect(
        entry.headings.map((h) => h.text),
        contains(entry.title),
        reason: '${markdownFile.path} 的标题表应含一级标题',
      );
      final issues = helpLinkIssues(content: content, entry: entry);
      expect(
        issues,
        isEmpty,
        reason:
            '${markdownFile.path} 的链接写坏：\n'
            '${issues.map((i) => i.message).join('\n')}',
      );
    }
  });

  test('onboarding.yaml 里没有残留的作者批注', () {
    final source = File(onboardingCopyAssetKey).readAsStringSync();
    expect(
      source.contains('TODO'),
      isFalse,
      reason: '随包文案里还留着作者批注；批注会写坏 YAML 并让引导静默全空',
    );
    expect(source.contains('#'), isFalse, reason: '随包文案里不该有注释：验收要求是文件内不再有任何批注');
  });

  test('onboarding.yaml 可解析，且每个引导单元 id 与步 id 都有文案', () {
    final copy = parseGuideCopy(
      File(onboardingCopyAssetKey).readAsStringSync(),
    );
    for (final unit in helpGuideUnits) {
      expect(copy.unit(unit.id)?.title, isNotEmpty, reason: unit.id);
      expect(copy.unit(unit.id)?.description, isNotEmpty, reason: unit.id);
    }
    for (final step in helpGuideSteps) {
      final stepCopy = copy.step(step.id);
      expect(stepCopy, isNotNull, reason: step.id);
      // 一次性图文可由 sourceDocumentId 取正文，其余步必须有那一句话。
      if (step.sourceDocumentId == null) {
        expect(stepCopy!.message, isNotEmpty, reason: step.id);
      }
    }
    for (final step in helpDrillSteps) {
      final stepCopy = copy.step(step.id);
      expect(stepCopy, isNotNull, reason: step.id);
      expect(stepCopy!.message, isNotEmpty, reason: step.id);
      for (final sub in step.subChecks) {
        expect(stepCopy.subChecks[sub.id], isNotEmpty, reason: sub.id);
      }
    }
  });

  test('条目正文里没有残留的待补占位', () {
    for (final directory in entryDirectories) {
      final file = _markdownFilesIn(directory).single;
      expect(
        file.readAsStringSync(),
        isNot(contains('TODO（Ready-for-human）')),
        reason: '${file.path} 还留着没写完的占位',
      );
    }
  });

  test('对比练习的取景段：小节在场、关键行为词在场，旧说法退场', () async {
    final content = await loadHelpContent(rootBundle);
    final markdown = content.document('对比练习')!.markdown;

    final start = markdown.indexOf('## 取景');
    expect(start, isNonNegative, reason: '对比练习有「取景」小节');
    final rest = markdown.substring(start + 1);
    final nextSection = rest.indexOf('\n## ');
    final framing = nextSection < 0 ? rest : rest.substring(0, nextSection);

    // 结构层契约：这一小节讲的是取景调整与复位。
    for (final text in const ['取景调整', '复位']) {
      expect(framing, contains(text), reason: '取景段缺「$text」');
    }
    // 旧形状的代表性说法退场。
    for (final text in const ['取景微调', '取景基线']) {
      expect(framing, isNot(contains(text)), reason: '取景段还留着旧说法「$text」');
    }
  });
}

/// [groupDirectory] 下的一级子目录（每个即一个条目目录）。
List<String> _entryDirectories(String groupDirectory) => [
  for (final entity in Directory(groupDirectory).listSync())
    if (entity is Directory) entity.path,
]..sort();

/// 条目目录里的全部 Markdown 文件。
List<File> _markdownFilesIn(String directory) => [
  for (final entity in Directory(directory).listSync())
    if (entity is File && entity.path.endsWith('.md')) entity,
]..sort((a, b) => a.path.compareTo(b.path));

String _normalize(String path) => path.replaceAll('\\', '/');
