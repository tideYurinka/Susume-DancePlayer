/// 引导文案：模型、单元行文案与 `assets/help/onboarding.yaml` 的解析。
///
/// 文案文件坏掉（读不出 / 不是 YAML / 结构不对）即**引导文案视为全空**：相关
/// 引导步不出场，帮助中心与其它功能照常；装载侧的断言把原因打出来。
library;

import 'package:yaml/yaml.dart';

import 'content_registry.dart';

/// 一个引导单元的文案（标题 + 一句说明）：缺一条即 null，新手引导页取该
/// 单元首步的文案兜底。
class GuideUnitCopy {
  const GuideUnitCopy({this.title, this.description});

  final String? title;
  final String? description;
}

/// 一条引导步的文案：标题（重看列表与一次性图文卡用）、那一句话、**一次性
/// 图文**的按钮标签（按首启分支取值配对，不按位置配对）、手势演练末步的子勾
/// 片标签。
class GuideStepCopy {
  const GuideStepCopy({
    this.title,
    this.message = '',
    this.cardActionLabels = const {},
    this.subChecks = const {},
  });

  final String? title;

  /// 那一句话；一次性图文步可由 [GuideStep.sourceDocumentId] 取正文，此时为空。
  final String message;

  /// 一次性图文按钮的标签：首启分支取值 → 文案。
  final Map<FirstRunChoice, String> cardActionLabels;

  /// 子勾片标签：子勾 id → 文案。
  final Map<String, String> subChecks;
}

/// 演出层与新手引导页的固定字串。
class GuideUiCopy {
  const GuideUiCopy({
    required this.next,
    required this.skip,
    required this.guideUnitsTitle,
    required this.resetAll,
    required this.resetDialogTitle,
    required this.resetDialogBody,
    required this.resetDialogCancel,
    required this.resetDialogConfirm,
  });

  final String next;
  final String skip;
  final String guideUnitsTitle;
  final String resetAll;
  final String resetDialogTitle;
  final String resetDialogBody;
  final String resetDialogCancel;
  final String resetDialogConfirm;

  /// 文案缺失时的兜底：全部为空串（引导步此时本就不出场）。
  static const GuideUiCopy empty = GuideUiCopy(
    next: '',
    skip: '',
    guideUnitsTitle: '',
    resetAll: '',
    resetDialogTitle: '',
    resetDialogBody: '',
    resetDialogCancel: '',
    resetDialogConfirm: '',
  );
}

/// 引导文案全集：单元查表 + 引导步查表 + 固定字串。
class GuideCopy {
  const GuideCopy({required this.units, required this.steps, required this.ui});

  final Map<String, GuideUnitCopy> units;
  final Map<String, GuideStepCopy> steps;
  final GuideUiCopy ui;

  /// 文案全空：文件读不出或解析失败时的唯一降级结果。
  static const GuideCopy empty = GuideCopy(
    units: {},
    steps: {},
    ui: GuideUiCopy.empty,
  );

  /// 该步的文案；缺一条即 null（该步不出场、不被消耗）。
  GuideStepCopy? step(String stepId) => steps[stepId];

  /// [step] 的文案是否**齐全**：有那一条文案，且它声明的每个一次性图文按钮
  /// 都有标签。缺任意一条即该步不出场、不被消耗。
  bool hasStepCopy(GuideStep step) {
    final copy = steps[step.id];
    if (copy == null) return false;
    return step.cardChoices.every(copy.cardActionLabels.containsKey);
  }

  /// 该单元的文案；缺标题或说明时页面按步文案兜底。
  GuideUnitCopy? unit(String unitId) => units[unitId];
}

/// 新手引导页一行的文案：单元自有文案优先，缺标题或说明时取该单元**首步**
/// 的文案兜底。
({String title, String description}) guideUnitRowCopy(
  GuideCopy copy,
  GuideUnit unit,
) {
  final unitCopy = copy.unit(unit.id);
  final steps = guideStepsOfUnit(unit.id);
  final stepCopy = steps.isEmpty ? null : copy.step(steps.first.id);
  return (
    title: unitCopy?.title ?? stepCopy?.title ?? '',
    description: unitCopy?.description ?? stepCopy?.message ?? '',
  );
}

/// 解析引导文案源文本；结构不对抛 [FormatException]（由 [loadHelpContent]
/// 收成「全空」）。首启分支取值的按键名配对，作者调整文件里的先后顺序不影响
/// 按钮与分支的对应。
GuideCopy parseGuideCopy(String source) {
  final document = loadYaml(source);
  if (document is! Map) {
    throw const FormatException('引导文案根节点不是映射');
  }
  return GuideCopy(
    units: _parseUnits(document['units']),
    steps: _parseSteps(document['steps']),
    ui: _parseUi(document['ui']),
  );
}

Map<String, GuideUnitCopy> _parseUnits(Object? node) {
  final map = _requireMap(node, 'units');
  return {
    for (final entry in map.entries)
      entry.key: GuideUnitCopy(
        title: _optionalString(entry.value, 'title', 'units.${entry.key}'),
        description: _optionalString(
          entry.value,
          'description',
          'units.${entry.key}',
        ),
      ),
  };
}

Map<String, GuideStepCopy> _parseSteps(Object? node) {
  final map = _requireMap(node, 'steps');
  final result = <String, GuideStepCopy>{};
  for (final entry in map.entries) {
    final stepNode = _requireMap(entry.value, 'steps.${entry.key}');
    // 没有「那一句话」这一键的条目视为缺文案：该引导步不出场、不被消耗
    // （`first_run_download` 正文取自文档，但同样显式写 message: ''）。
    if (!stepNode.containsKey('message')) continue;
    result[entry.key] = GuideStepCopy(
      title: _optionalString(stepNode, 'title', 'steps.${entry.key}'),
      message: _requireString(
        stepNode['message'],
        'steps.${entry.key}.message',
      ),
      cardActionLabels: _parseActions(stepNode, 'steps.${entry.key}'),
      subChecks: _parseSubChecks(stepNode, 'steps.${entry.key}'),
    );
  }
  return result;
}

Map<FirstRunChoice, String> _parseActions(Object? stepNode, String where) {
  final actions = _optionalMap(stepNode, 'actions', where);
  if (actions == null) return const {};
  final byName = {
    for (final choice in FirstRunChoice.values) choice.name: choice,
  };
  return {
    for (final entry in actions.entries)
      _requireChoice(entry.key, byName, '$where.actions'): _requireString(
        entry.value,
        '$where.actions.${entry.key}',
      ),
  };
}

Map<String, String> _parseSubChecks(Object? stepNode, String where) {
  final subChecks = _optionalMap(stepNode, 'sub_checks', where);
  if (subChecks == null) return const {};
  return {
    for (final entry in subChecks.entries)
      entry.key: _requireString(entry.value, '$where.sub_checks.${entry.key}'),
  };
}

GuideUiCopy _parseUi(Object? node) {
  final map = _requireMap(node, 'ui');
  String read(String key) => _requireString(map[key], 'ui.$key');
  return GuideUiCopy(
    next: read('next'),
    skip: read('skip'),
    guideUnitsTitle: read('guide_units_title'),
    resetAll: read('reset_all'),
    resetDialogTitle: read('reset_dialog_title'),
    resetDialogBody: read('reset_dialog_body'),
    resetDialogCancel: read('reset_dialog_cancel'),
    resetDialogConfirm: read('reset_dialog_confirm'),
  );
}

FirstRunChoice _requireChoice(
  String name,
  Map<String, FirstRunChoice> byName,
  String where,
) {
  final choice = byName[name];
  if (choice == null) {
    throw FormatException('$where: 未知的首启分支取值「$name」');
  }
  return choice;
}

Map<String, Object?> _requireMap(Object? node, String where) {
  if (node is! Map) throw FormatException('$where 不是映射');
  return {for (final entry in node.entries) entry.key.toString(): entry.value};
}

Map<String, Object?>? _optionalMap(Object? stepNode, String key, String where) {
  if (stepNode is! Map) throw FormatException('$where 不是映射');
  final value = stepNode[key];
  if (value == null) return null;
  return _requireMap(value, '$where.$key');
}

String? _optionalString(Object? stepNode, String key, String where) {
  if (stepNode is! Map) throw FormatException('$where 不是映射');
  final value = stepNode[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('$where.$key 不是字符串');
  return value;
}

String _requireString(Object? value, String where) {
  if (value is! String) throw FormatException('$where 不是字符串');
  return value;
}
