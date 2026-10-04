import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_copy.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 引导文案内容契约：直接读仓库里的随包资产，
/// 断言内容本身合规——每个引导单元与引导步都有文案、一次性图文的按钮键与
/// 声明的首启分支一一对应、演出层固定字串齐全、首启欢迎图文带运营群号。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GuideCopy copy;
  setUpAll(() async {
    copy = (await loadHelpContent(rootBundle)).guideCopy;
  });

  test('14 个引导单元都有标题与说明', () {
    expect(helpGuideUnits, hasLength(14));
    for (final unit in helpGuideUnits) {
      expect(copy.unit(unit.id)?.title, isNotEmpty, reason: unit.id);
      expect(copy.unit(unit.id)?.description, isNotEmpty, reason: unit.id);
    }
  });

  test('引导步的文案一条不缺（含手势演练步与末步子勾片）', () {
    final subChecks = [for (final step in helpDrillSteps) ...step.subChecks];
    // 24 条引导步 + 3 条手势演练步 + 3 枚末步子勾片。
    expect(
      helpGuideSteps.length + helpDrillSteps.length + subChecks.length,
      30,
    );

    for (final step in helpGuideSteps) {
      final stepCopy = copy.step(step.id);
      expect(stepCopy, isNotNull, reason: step.id);
      expect(stepCopy!.title, isNotEmpty, reason: step.id);
      // 一次性图文可由 sourceDocumentId 取正文，其余步必须有那一句话。
      if (step.sourceDocumentId == null) {
        expect(stepCopy.message, isNotEmpty, reason: step.id);
      }
      for (final choice in step.cardChoices) {
        expect(
          stepCopy.cardActionLabels[choice],
          isNotEmpty,
          reason: '${step.id} 缺分支 ${choice.name} 的按钮文案',
        );
      }
    }

    for (final step in helpDrillSteps) {
      final stepCopy = copy.step(step.id);
      expect(stepCopy, isNotNull, reason: step.id);
      expect(stepCopy!.message, isNotEmpty, reason: step.id);
      for (final sub in step.subChecks) {
        expect(
          stepCopy.subChecks[sub.id],
          isNotEmpty,
          reason: '${step.id} 缺子勾 ${sub.id} 的文案',
        );
      }
    }
  });

  test('引导与使用手册不再有「激活」的旧说法', () async {
    final onboarding = await rootBundle.loadString(
      onboardingCopyAssetKey,
      cache: false,
    );
    expect(onboarding.contains('激活'), isFalse, reason: onboarding);
    // 编辑态上手那一页：标题不出现「激活」，判据仍是「点这一段就循环练这一段」，
    // 长按圈选只带一句提示、不进必做判据。
    final step = copy.step('editor_intro_segment')!;
    expect(step.title!.contains('激活'), isFalse);
    expect(step.message.contains('长按'), isTrue);
    expect(copy.unit(editorIntroUnitId)!.description!.contains('激活'), isFalse);
    // 使用手册：点一下与长按拖动各做什么。
    final manual = await rootBundle.loadString(
      '$helpGuideAssetDirectory/00-Susume使用概览/Susume使用概览.md',
      cache: false,
    );
    expect(manual.contains('激活'), isFalse, reason: manual);
    expect(manual.contains('点一下'), isTrue);
    expect(manual.contains('长按'), isTrue);
  });

  test('一次性图文的按钮键集合与声明的首启分支一一对应', () {
    final cardSteps = [
      for (final step in helpGuideSteps)
        if (step.cardChoices.isNotEmpty) step,
    ];
    expect(cardSteps, isNotEmpty, reason: '首启一次性图文在册');
    for (final step in cardSteps) {
      final stepCopy = copy.step(step.id);
      expect(stepCopy, isNotNull, reason: step.id);
      expect(
        stepCopy!.cardActionLabels.keys.toSet(),
        step.cardChoices.toSet(),
        reason: '${step.id} 的按钮键与声明的首启分支一一对应',
      );
    }
  });

  test('演出层固定字串齐全', () {
    for (final text in [
      copy.ui.next,
      copy.ui.skip,
      copy.ui.guideUnitsTitle,
      copy.ui.resetAll,
      copy.ui.resetDialogTitle,
      copy.ui.resetDialogBody,
      copy.ui.resetDialogCancel,
      copy.ui.resetDialogConfirm,
    ]) {
      expect(text, isNotEmpty);
    }
  });

  test('首启欢迎图文正文带运营群号', () {
    expect(copy.step('first_run_welcome')!.message, contains('QQ群1102058156'));
  });
}
