import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_state.dart';
import 'package:dance_learning_app/help/guide_copy.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 引导文案装载：输入侧是假资产包，输出侧是
/// 文案 provider。断言只落在**装载结果与降级表现**上。
void main() {
  group('解析', () {
    test('按 id 取单元与步的文案；按钮按首启分支取值配对，不按文件顺序', () {
      final copy = parseGuideCopy('''
units:
  first_run:
    title: 首启
    description: 单元说明
steps:
  first_run_welcome:
    title: 欢迎
    message: |-
      第一行
      第二行
    actions:
      skip: 先跳过
      tour: 走着瞧
$_uiSection
''');

      expect(copy.unit('first_run')?.title, '首启');
      expect(copy.unit('first_run')?.description, '单元说明');
      final step = copy.step('first_run_welcome')!;
      expect(step.title, '欢迎');
      expect(step.message, '第一行\n第二行');
      // 文件里 skip 写在 tour 前面：取值仍与分支一一对应。
      expect(step.cardActionLabels[FirstRunChoice.tour], '走着瞧');
      expect(step.cardActionLabels[FirstRunChoice.skip], '先跳过');
      expect(copy.ui.next, '继续');
      expect(copy.ui.resetDialogConfirm, '确定');
    });

    test('缺某一步的条目：该步无文案，其余步照常', () {
      final copy = parseGuideCopy('''
units: {}
steps:
  first_run_welcome:
    title: 欢迎
    message: 一句话
$_uiSection
''');
      expect(copy.step('first_run_welcome'), isNotNull);
      expect(copy.step('first_run_import'), isNull);
    });

    test('条目缺「那一句话」这一键：该步视为没有文案', () {
      final copy = parseGuideCopy('''
units: {}
steps:
  first_run_welcome:
    title: 欢迎
$_uiSection
''');
      expect(copy.step('first_run_welcome'), isNull);
    });

    test('未知的首启分支取值按键名报错（结构声明外的按钮不做静默兜底）', () {
      expect(
        () => parseGuideCopy('''
units: {}
steps:
  first_run_welcome:
    message: 一句话
    actions:
      nope: 文案
$_uiSection
'''),
        throwsFormatException,
      );
    });

    test('解析失败：文案视为全空', () async {
      final content = await loadHelpContent(
        FakeHelpAssetBundle({onboardingCopyAssetKey: '不是一个映射'}),
      );
      expect(content.guideCopy.steps, isEmpty);
      expect(content.guideCopy.units, isEmpty);
      expect(content.guideCopy.ui.next, isEmpty);
    });

    test('缺整个段落（units / steps / ui）：整体视为解析失败，文案全空', () async {
      // 只有 steps 有内容、但缺 ui 段：不做「部分可用」的兜底，整体降级。
      for (final source in [
        'steps:\n  first_run_welcome:\n    message: 一句话\n',
        'units: {}\nsteps:\n  first_run_welcome:\n    message: 一句话\n',
        'units: {}\nsteps: {}\n',
      ]) {
        final content = await loadHelpContent(
          FakeHelpAssetBundle({onboardingCopyAssetKey: source}),
        );
        expect(content.guideCopy.steps, isEmpty, reason: source);
        expect(content.guideCopy.ui.next, isEmpty, reason: source);
      }
    });

    test('资产读不出：文案视为全空', () async {
      final content = await loadHelpContent(FakeHelpAssetBundle(const {}));
      expect(content.guideCopy.steps, isEmpty);
    });

    test('单元缺标题或说明：新手引导页行文案取该单元首步兜底', () {
      final copy = parseGuideCopy('''
units:
  badge_roster:
    title: 名册
steps:
  badge_roster_hint:
    title: 兜底标题
    message: 兜底说明
$_uiSection
''');
      final unit = helpGuideUnits.firstWhere(
        (u) => u.id == badgeRosterUnitId,
      );
      final row = guideUnitRowCopy(copy, unit);
      expect(row.title, '名册');
      expect(row.description, '兜底说明');
    });

    test('一次性图文缺某个按钮标签：该步的文案视为不齐全', () {
      final copy = parseGuideCopy('''
units: {}
steps:
  first_run_welcome:
    message: 一句话
    actions:
      tour: 走着瞧
$_uiSection
''');
      final welcome = helpGuideSteps.firstWhere(
        (step) => step.id == 'first_run_welcome',
      );
      expect(copy.step('first_run_welcome'), isNotNull);
      expect(copy.hasStepCopy(welcome), isFalse);
    });
  });

  group('判定面', () {
    test('缺一条文案的引导步不出场、也不被消耗', () async {
      // 只给欢迎一步文案；下载与指认两步没有条目。
      final container = _container('''
units: {}
steps:
  first_run_welcome:
    title: 欢迎
    message: 一句话
    actions:
      tour: 带我看一遍
      skip: 我先自己用
$_uiSection
''');
      addTearDown(container.dispose);

      final first = await container.read(currentGuideStepProvider.future);
      expect(first?.id, 'first_run_welcome');

      // 走完欢迎步、选「带我看一遍」：下一步缺文案，判定面不给出任何步。
      container.read(guideSessionProvider.notifier).markStepDone(first!.id);
      container.read(guideSessionProvider.notifier).choose(
        FirstRunChoice.tour,
      );
      container.invalidate(currentGuideStepProvider);

      expect(await container.read(currentGuideStepProvider.future), isNull);
      expect(
        container.read(guideSessionProvider).stepsDone,
        isNot(contains('first_run_download')),
        reason: '缺文案的步不出场，也不进本会话的已走完集合',
      );
    });

    test('一次性图文缺某个按钮标签：该步也不出场、不被消耗', () async {
      final container = _container('''
units: {}
steps:
  first_run_welcome:
    message: 一句话
    actions:
      tour: 走着瞧
$_uiSection
''');
      addTearDown(container.dispose);

      expect(await container.read(currentGuideStepProvider.future), isNull);
      expect(container.read(guideSessionProvider).stepsDone, isEmpty);
    });

    test('文案文件解析失败：引导文案全空，判定面不给出任何步', () async {
      final container = _container('不是一个映射');
      addTearDown(container.dispose);

      expect(await container.read(currentGuideStepProvider.future), isNull);
    });
  });
}

/// 结构齐全的一份 `ui` 段（每个用例只在被测段落上做变化）。
const String _uiSection = '''
ui:
  next: 继续
  skip: 稍后
  guide_units_title: 引导
  reset_all: 全重置
  reset_dialog_title: 全重置？
  reset_dialog_body: 正文
  reset_dialog_cancel: 取消
  reset_dialog_confirm: 确定''';

ProviderContainer _container(String onboardingYaml) => ProviderContainer(
  overrides: [
    helpAssetBundleProvider.overrideWithValue(
      FakeHelpAssetBundle({onboardingCopyAssetKey: onboardingYaml}),
    ),
    onboardingStorageProvider.overrideWithValue(
      OnboardingStore(InMemoryPrivateJsonStorage()),
    ),
    privateJsonStorageProvider.overrideWithValue(InMemoryPrivateJsonStorage()),
  ],
);
