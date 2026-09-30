import 'dart:io';

import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_copy.dart';
import 'package:dance_learning_app/help/help_documents.dart';

/// 测试共用的真资产引导文案：直接从仓库里的随包文件解析（断言取自装载结果，
/// 不在测试里复抄一份字面量）。内容契约由 `help_copy_assets_test` 单独守住。
final GuideCopy realGuideCopy = parseGuideCopy(
  File(onboardingCopyAssetKey).readAsStringSync(),
);

String guideStepMessage(String stepId) => realGuideCopy.step(stepId)!.message;

/// 编辑态上手第②步的第一句（判据句，多处在断）。
const String editorIntroLoopSentence = '点这一段就循环练这一段';

/// 某步的多行文案按行拆开（一次性图文的逐行简介）。
List<String> guideStepMessageLines(String stepId) =>
    guideStepMessage(stepId).split('\n');

String guideUnitTitle(String unitId) => realGuideCopy.unit(unitId)!.title!;

String guideUnitDescription(String unitId) =>
    realGuideCopy.unit(unitId)!.description!;

/// 某步一次性图文按首启分支取的按钮标签。
String guideCardActionLabel(String stepId, FirstRunChoice choice) =>
    realGuideCopy.step(stepId)!.cardActionLabels[choice]!;

/// 首启欢迎卡「开始新手教程」那枚按钮的标签。
final String welcomeTourLabel = guideCardActionLabel(
  'first_run_welcome',
  FirstRunChoice.tour,
);

/// 首启欢迎卡「跳过教程」那枚按钮的标签。
final String welcomeSkipLabel = guideCardActionLabel(
  'first_run_welcome',
  FirstRunChoice.skip,
);

/// 某手势演练步末步子勾片的标签。
String guideSubCheckLabel(String drillStepId, String subCheckId) =>
    realGuideCopy.step(drillStepId)!.subChecks[subCheckId]!;
