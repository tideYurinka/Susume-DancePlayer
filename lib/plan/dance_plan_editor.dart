import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import '../persistence/practice_plan_providers.dart';
import 'plan_editor_scaffold.dart';
import 'plan_wheel.dart';
import 'plan_wheel_picker.dart';
import 'practice_reminders_provider.dart';
import 'system_push_provider.dart';

/// 计划编辑共用控件：舞详情计划区与「各舞计划」
/// 管理页共用同一批控件与同一条写路径——DDL 编辑页（日期 / 提前 N 天滚轮见
/// `plan_wheel_picker.dart`）、两个开关、准备清单编辑器。

/// 计划区统一的写路径：执行 [action]（拿到注入的 store），成功即作废该舞
/// DDL 与随舞曲库开关读面，并经 [invalidatePlanReadFaces] 作废计划读面；
/// 失败如实提示（存储静默承接，内存态不回滚）。
Future<void> runPlanWrite(
  BuildContext context,
  WidgetRef ref,
  String videoId,
  Future<bool> Function(PracticePlanStore store) action,
) async {
  final written = await action(ref.read(practicePlanStoreProvider));
  if (!context.mounted) return;
  if (!written) {
    showPlanWriteFailure(context);
    return;
  }
  ref.invalidate(dancePlanDdlProvider(videoId));
  ref.invalidate(dancePlanSocialLibraryProvider(videoId));
  ref.invalidate(dancePlanReviewRemindersProvider(videoId));
  invalidatePlanReadFaces(ref);
}

/// 计划写成功后作废的三个读面：条目、事件与提醒评估。两条计划写路径共用；
/// 提醒读面随之立即重评（红点与提醒集合同步，重评幂等）。
void invalidatePlanReadFaces(WidgetRef ref) {
  ref.invalidate(practicePlanEntriesProvider);
  ref.invalidate(practicePlanEventsProvider);
  ref.invalidate(practiceRemindersProvider);
}

/// 计划写失败提示：存储静默承接，内存态不回滚，如实提示用户。
void showPlanWriteFailure(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('计划保存失败')));
}

/// 首次设「提前 N 天」时系统询问通知权限：只在此前未设提前量时弹；
/// 被拒后保存照常（降级为仅应用内提醒）。详情页与管理页共用这一条权限口径。
Future<void> ensureDancePlanReminderPermission(
  WidgetRef ref, {
  required DanceDdl? ddl,
  required DanceDdl? previous,
}) async {
  if (ddl?.leadDays == null || previous?.leadDays != null) return;
  await ref.read(planPushPlannerProvider).ensureReminderPermission();
}

/// 计划编辑页的返回值：DDL + 两个开关（管理页一次编辑三样；详情页只用
/// [ddl]）。日期是常驻滚轮，保存必带 DDL。
class DancePlanEditorResult {
  const DancePlanEditorResult({
    required this.ddl,
    required this.socialLibrary,
    required this.reviewReminders,
  });

  final DanceDdl ddl;
  final bool socialLibrary;
  final bool reviewReminders;
}

/// 两个开关（随舞曲库 / 复习提醒）：详情页内嵌与管理页编辑框共用。默认翻转
/// 即经 [runPlanWrite] 落盘并作废读面；调用方给出回调时只上抛新值（管理页
/// 编辑框在保存时统一落盘）。
class DancePlanSwitchTiles extends ConsumerWidget {
  const DancePlanSwitchTiles({
    super.key,
    required this.videoId,
    required this.socialLibrary,
    required this.reviewReminders,
    this.onSocialLibraryChanged,
    this.onReviewRemindersChanged,
  });

  final String videoId;
  final bool socialLibrary;
  final bool reviewReminders;

  final ValueChanged<bool>? onSocialLibraryChanged;
  final ValueChanged<bool>? onReviewRemindersChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void apply(
      ValueChanged<bool>? callback,
      bool enabled,
      Future<bool> Function(PracticePlanStore store, bool enabled) write,
    ) {
      if (callback != null) {
        callback(enabled);
        return;
      }
      runPlanWrite(context, ref, videoId, (store) => write(store, enabled));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          key: const Key('dance_plan_social_library'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('随舞曲库'),
          subtitle: const Text('关掉后不被新建随舞事件默认带入'),
          value: socialLibrary,
          onChanged: (enabled) => apply(
            onSocialLibraryChanged,
            enabled,
            (store, value) =>
                store.setSocialLibrary(videoId: videoId, enabled: value),
          ),
        ),
        SwitchListTile(
          key: const Key('dance_plan_review_reminders'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('复习提醒'),
          subtitle: const Text('关掉后这支舞不做应用内复习提醒'),
          value: reviewReminders,
          onChanged: (enabled) => apply(
            onReviewRemindersChanged,
            enabled,
            (store, value) =>
                store.setReviewReminders(videoId: videoId, enabled: value),
          ),
        ),
      ],
    );
  }
}

/// 准备清单编辑器：既有项逐行打勾 + 行尾删除；底部一行输入框 + 「加入」。
/// 详情页把回调接到即时写盘，管理页编辑框接到本地状态。
class DancePlanChecklistEditor extends StatelessWidget {
  const DancePlanChecklistEditor({
    super.key,
    required this.items,
    required this.keyPrefix,
    required this.onToggle,
    required this.onRemove,
    required this.onAdd,
  });

  final List<PlanChecklistItem> items;

  /// 控件键前缀：详情页 `dance_plan_`、管理页编辑框 `plan_manage_`。
  final String keyPrefix;

  final void Function(int index, bool checked) onToggle;
  final void Function(int index) onRemove;
  final void Function(String text) onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          Row(
            children: [
              Checkbox(
                key: Key('${keyPrefix}check_$i'),
                value: items[i].checked,
                onChanged: (checked) => onToggle(i, checked == true),
              ),
              Expanded(child: Text(items[i].text)),
              IconButton(
                key: Key('${keyPrefix}check_remove_$i'),
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  semanticLabel: '删除该清单项',
                ),
                onPressed: () => onRemove(i),
              ),
            ],
          ),
        _ChecklistInputRow(keyPrefix: keyPrefix, onAdd: onAdd),
      ],
    );
  }
}

/// 清单加项输入行：回车与「加入」同一条路径；空白文本静默不建。
class _ChecklistInputRow extends StatefulWidget {
  const _ChecklistInputRow({required this.keyPrefix, required this.onAdd});

  final String keyPrefix;
  final void Function(String text) onAdd;

  @override
  State<_ChecklistInputRow> createState() => _ChecklistInputRowState();
}

class _ChecklistInputRowState extends State<_ChecklistInputRow> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final text = _controller.text;
    _controller.clear();
    widget.onAdd(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: Key('${widget.keyPrefix}checklist_input'),
            controller: _controller,
            decoration: const InputDecoration(hintText: '清单加一项'),
            onSubmitted: (_) => _add(),
          ),
        ),
        TextButton(
          key: Key('${widget.keyPrefix}checklist_add'),
          onPressed: _add,
          child: const Text('加入'),
        ),
      ],
    );
  }
}

/// DDL 编辑页：日期滚轮（年 / 月 / 日，新建默认今天）+ 场合标签、备注、
/// 提前 N 天滚轮（首档「不提醒」）。[showPlanExtras] = true 时（管理页）追加
/// 准备清单编辑与两个开关，返回三样；详情页只用 [DancePlanEditorResult.ddl]。
/// 滚轮只产出合法值，无格式报错分支。
class DanceDdlEditorPage extends StatefulWidget {
  const DanceDdlEditorPage({
    super.key,
    required this.videoId,
    required this.initial,
    this.title = '设截止（DDL）',
    this.showPlanExtras = false,
    this.socialLibrary = true,
    this.reviewReminders = true,
    this.checklistKeyPrefix = 'dance_plan_',
    this.today,
  });

  final String videoId;
  final DanceDdl? initial;
  final String title;

  final bool showPlanExtras;
  final bool socialLibrary;
  final bool reviewReminders;
  final String checklistKeyPrefix;

  /// 滚轮年列基准日（装配层传设备时钟读面）；默认今天。
  final DateTime? today;

  @override
  State<DanceDdlEditorPage> createState() => _DanceDdlEditorPageState();
}

class _DanceDdlEditorPageState extends State<DanceDdlEditorPage> {
  late final DateTime _today = localDay(widget.today ?? DateTime.now());
  late DateTime _date = planDateWheelClampDay(
    widget.initial?.date ?? _today,
    today: _today,
  );
  late final TextEditingController _occasion = TextEditingController(
    text: widget.initial?.occasion ?? kPlanOccasionPresets.first,
  );
  late final TextEditingController _remark = TextEditingController(
    text: widget.initial?.remark ?? '',
  );
  late int? _leadDays = widget.initial?.leadDays;
  late final List<PlanChecklistItem> _checklist = [
    ...?widget.initial?.checklist,
  ];
  late bool _socialLibrary = widget.socialLibrary;
  late bool _reviewReminders = widget.reviewReminders;

  @override
  void dispose() {
    _occasion.dispose();
    _remark.dispose();
    super.dispose();
  }

  /// 场合预设（约舞 / 演出）：点一下即代入标签框，仍可自由改写。
  Widget _occasionPresets() {
    return Wrap(
      spacing: 8,
      children: [
        for (final preset in kPlanOccasionPresets)
          ChoiceChip(
            key: Key('dance_plan_occasion_preset_$preset'),
            label: Text(preset),
            selected: _occasion.text == preset,
            onSelected: (_) => setState(() => _occasion.text = preset),
          ),
      ],
    );
  }

  void _save() {
    Navigator.of(context).pop(
      DancePlanEditorResult(
        ddl: DanceDdl(
          date: _date,
          occasion: _occasion.text.trim(),
          remark: _remark.text.trim(),
          leadDays: _leadDays,
          checklist: _checklist,
          extra: widget.initial?.extra ?? const {},
        ),
        socialLibrary: _socialLibrary,
        reviewReminders: _reviewReminders,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlanEditorScaffold(
      pageKey: const Key('dance_plan_dialog'),
      title: widget.title,
      saveKey: const Key('dance_plan_dialog_save'),
      onSave: _save,
      children: [
        const Text('日期'),
        PlanDateWheelField(
          key: const Key('dance_plan_dialog_date'),
          value: _date,
          today: _today,
          onChanged: (day) => setState(() => _date = day),
          columnPrefix: 'dance_plan_dialog_date',
        ),
        const SizedBox(height: 12),
        _occasionPresets(),
        TextField(
          key: const Key('dance_plan_dialog_occasion'),
          controller: _occasion,
          decoration: const InputDecoration(labelText: '场合'),
        ),
        TextField(
          key: const Key('dance_plan_dialog_remark'),
          controller: _remark,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 12),
        const Text('提前 N 天提醒'),
        PlanLeadWheelField(
          key: const Key('dance_plan_dialog_lead'),
          days: _leadDays,
          onChanged: (days) => setState(() => _leadDays = days),
          columnKey: const Key('dance_plan_dialog_lead_wheel'),
        ),
        if (widget.showPlanExtras) ...[
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('准备清单')),
          DancePlanChecklistEditor(
            items: _checklist,
            keyPrefix: widget.checklistKeyPrefix,
            onToggle: (index, checked) => setState(() {
              _checklist[index] = PlanChecklistItem(
                text: _checklist[index].text,
                checked: checked,
                extra: _checklist[index].extra,
              );
            }),
            onRemove: (index) => setState(() => _checklist.removeAt(index)),
            onAdd: (text) {
              final trimmed = text.trim();
              if (trimmed.isEmpty) return;
              setState(() => _checklist.add(PlanChecklistItem(text: trimmed)));
            },
          ),
          DancePlanSwitchTiles(
            videoId: widget.videoId,
            socialLibrary: _socialLibrary,
            reviewReminders: _reviewReminders,
            onSocialLibraryChanged: (enabled) =>
                setState(() => _socialLibrary = enabled),
            onReviewRemindersChanged: (enabled) =>
                setState(() => _reviewReminders = enabled),
          ),
        ],
      ],
    );
  }
}
