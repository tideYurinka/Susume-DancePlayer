/// 计划事件的两个整页编辑器：随舞事件与团内检查。两者都是被 push 的独立
/// 路由，保存经 store 落盘由页面侧的 `_persistEventResult` 负责。
library;

import 'package:flutter/material.dart';

import '../core/local_day.dart';
import '../persistence/practice_plan.dart';
import '../persistence/team_check_gate.dart';
import 'dance_plan_editor.dart';
import 'plan_editor_scaffold.dart';
import 'plan_wheel.dart';
import 'plan_wheel_picker.dart';

/// 编辑页里可勾选的一支舞：视频 id、标题与初始勾选态。
class PlanEditorDance {
  const PlanEditorDance({
    required this.videoId,
    required this.title,
    required this.checked,
  });

  final String videoId;
  final String title;
  final bool checked;
}

/// 删除事件的返回哨兵（路由结果类型只有 Object 能同时装 [PlanEvent] 与它）。
class EventDeleted {
  const EventDeleted();
}

/// 关联舞勾选行（随舞 / 团检共用）：勾选框 + 可选的行内附加控件（团检的达标门）。
Widget planEditorDanceRow({
  required String videoId,
  required String title,
  required bool checked,
  required ValueChanged<bool> onCheckedChanged,
  Widget? gate,
}) {
  return Column(
    children: [
      CheckboxListTile(
        key: Key('plan_event_dance_$videoId'),
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(title),
        value: checked,
        onChanged: (value) => onCheckedChanged(value == true),
      ),
      ?gate,
    ],
  );
}

/// 随舞事件编辑页：日期滚轮、开始时间滚轮
/// （时列首档「不设」）、名称 / 地点、提前 N 天滚轮（首档「不提醒」）、备注、
/// 关联舞清单（勾选；新建默认带入随舞曲库开关为「开」的舞，由调用方算好传入）
/// 与准备清单。滚轮只产出合法值，无格式报错分支。
class EventEditorPage extends StatefulWidget {
  const EventEditorPage({
    super.key,
    required this.day,
    required this.dances,
    required this.initial,
  });

  /// 事件日（新建的默认日期）。
  final DateTime day;

  /// 可勾选的舞。
  final List<PlanEditorDance> dances;

  final PlanEvent? initial;

  @override
  State<EventEditorPage> createState() => EventEditorPageState();
}

class EventEditorPageState extends State<EventEditorPage> {
  late final DateTime _today = localDay(DateTime.now());
  late DateTime _date = planDateWheelClampDay(
    widget.initial?.date ?? widget.day,
    today: _today,
  );
  late int? _minutes = tryParseHhMm(widget.initial?.startTime ?? '');
  late final TextEditingController _location = TextEditingController(
    text: widget.initial?.location ?? '',
  );
  late final TextEditingController _remark = TextEditingController(
    text: widget.initial?.remark ?? '',
  );
  late int? _leadDays = widget.initial?.leadDays;
  late final List<String> _danceIds = [
    for (final dance in widget.dances)
      if (dance.checked) dance.videoId,
  ];
  late final List<PlanChecklistItem> _checklist = [
    ...?widget.initial?.checklist,
  ];

  @override
  void dispose() {
    _location.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = _minutes;
    Navigator.of(context).pop(
      PlanEvent(
        id: widget.initial?.id ?? 'ev-${DateTime.now().microsecondsSinceEpoch}',
        date: _date,
        startTime: minutes == null ? null : planHhMmText(minutes),
        leadDays: _leadDays,
        location: _location.text.trim(),
        remark: _remark.text.trim(),
        danceIds: _danceIds,
        checklist: _checklist,
        extra: widget.initial?.extra ?? const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlanEditorScaffold(
      pageKey: const Key('plan_event_dialog'),
      title: widget.initial == null ? '新建随舞' : '编辑随舞',
      saveKey: const Key('plan_event_dialog_save'),
      deleteKey: const Key('plan_event_delete'),
      onDelete: widget.initial == null
          ? null
          : () => Navigator.of(context).pop(const EventDeleted()),
      onSave: _save,
      children: [
        const Text('日期'),
        PlanDateWheelField(
          key: const Key('plan_event_dialog_date'),
          value: _date,
          today: _today,
          onChanged: (day) => setState(() => _date = day),
          columnPrefix: 'plan_event_dialog_date',
        ),
        const SizedBox(height: 12),
        const Text('开始时间'),
        PlanTimeWheelField(
          key: const Key('plan_event_dialog_time'),
          minutes: _minutes,
          onChanged: (minutes) => setState(() => _minutes = minutes),
          columnPrefix: 'plan_event_dialog_time',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('plan_event_dialog_name'),
          controller: _location,
          decoration: const InputDecoration(labelText: '名称 / 地点（可空）'),
        ),
        const SizedBox(height: 12),
        const Text('提前 N 天提醒'),
        PlanLeadWheelField(
          key: const Key('plan_event_dialog_lead'),
          days: _leadDays,
          onChanged: (days) => setState(() => _leadDays = days),
          columnKey: const Key('plan_event_dialog_lead_wheel'),
        ),
        TextField(
          key: const Key('plan_event_dialog_remark'),
          controller: _remark,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 8),
        const Text('关联舞'),
        for (final dance in widget.dances)
          planEditorDanceRow(
            videoId: dance.videoId,
            title: dance.title,
            checked: _danceIds.contains(dance.videoId),
            onCheckedChanged: (checked) => setState(() {
              if (checked) {
                _danceIds.add(dance.videoId);
              } else {
                _danceIds.remove(dance.videoId);
              }
            }),
          ),
        const SizedBox(height: 8),
        const Text('准备清单'),
        DancePlanChecklistEditor(
          items: _checklist,
          keyPrefix: 'plan_event_',
          onToggle: (index, checked) => setState(() {
            _checklist[index] = PlanChecklistItem(
              text: _checklist[index].text,
              checked: checked,
              extra: _checklist[index].extra,
            );
          }),
          onRemove: (index) => setState(() => _checklist.removeAt(index)),
          onAdd: (text) =>
              setState(() => _checklist.add(PlanChecklistItem(text: text))),
        ),
      ],
    );
  }
}

/// 团内检查编辑页：日期滚轮、备注、提前 N 天
/// 滚轮、关联舞清单（每支舞达标门选择器，默认较熟）、检查方式（到场排练 /
/// 录视频提交）；录视频提交类出「已提交」勾与提交日期滚轮（年列首档「不填」）。
/// 滚轮只产出合法值，无格式报错分支。
class TeamCheckEditorPage extends StatefulWidget {
  const TeamCheckEditorPage({
    super.key,
    required this.day,
    required this.dances,
    required this.initial,
  });

  /// 事件日（新建的默认日期）。
  final DateTime day;

  /// 可勾选的舞。
  final List<PlanEditorDance> dances;

  final PlanEvent? initial;

  @override
  State<TeamCheckEditorPage> createState() => TeamCheckEditorPageState();
}

class TeamCheckEditorPageState extends State<TeamCheckEditorPage> {
  late final DateTime _today = localDay(DateTime.now());
  late DateTime _date = planDateWheelClampDay(
    widget.initial?.date ?? widget.day,
    today: _today,
  );
  late final TextEditingController _remark = TextEditingController(
    text: widget.initial?.remark ?? '',
  );
  late DateTime? _submittedOn = widget.initial?.submittedOn;
  late int? _leadDays = widget.initial?.leadDays;
  late final Set<String> _danceIds = {
    for (final dance in widget.dances)
      if (dance.checked) dance.videoId,
  };
  late final Map<String, String> _gates = {
    for (final dance in widget.dances)
      dance.videoId:
          widget.initial?.danceGates[dance.videoId] ??
          kTeamCheckGateDefault.name,
  };
  late String _checkMode = widget.initial?.checkMode ?? kTeamCheckModeRehearsal;
  late bool _submitted = widget.initial?.submittedOn != null;

  @override
  void dispose() {
    _remark.dispose();
    super.dispose();
  }

  void _save() {
    final isVideo = _checkMode == kTeamCheckModeVideoSubmission;
    Navigator.of(context).pop(
      PlanEvent(
        id: widget.initial?.id ?? 'tc-${DateTime.now().microsecondsSinceEpoch}',
        type: kPlanEventTypeTeamCheck,
        date: _date,
        leadDays: _leadDays,
        remark: _remark.text.trim(),
        danceIds: [for (final id in _danceIds) id],
        danceGates: {
          for (final id in _danceIds)
            id: _gates[id] ?? kTeamCheckGateDefault.name,
        },
        checkMode: _checkMode,
        submittedOn: isVideo && _submitted ? _submittedOn : null,
        extra: widget.initial?.extra ?? const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _checkMode == kTeamCheckModeVideoSubmission;
    return PlanEditorScaffold(
      pageKey: const Key('plan_teamcheck_dialog'),
      title: widget.initial == null ? '新建团检' : '编辑团检',
      saveKey: const Key('plan_teamcheck_dialog_save'),
      deleteKey: const Key('plan_teamcheck_delete'),
      onDelete: widget.initial == null
          ? null
          : () => Navigator.of(context).pop(const EventDeleted()),
      onSave: _save,
      children: [
        const Text('日期'),
        PlanDateWheelField(
          key: const Key('plan_teamcheck_dialog_date'),
          value: _date,
          today: _today,
          onChanged: (day) => setState(() => _date = day),
          columnPrefix: 'plan_teamcheck_dialog_date',
        ),
        TextField(
          key: const Key('plan_teamcheck_dialog_remark'),
          controller: _remark,
          decoration: const InputDecoration(labelText: '备注'),
        ),
        const SizedBox(height: 12),
        const Text('提前 N 天提醒'),
        PlanLeadWheelField(
          key: const Key('plan_teamcheck_dialog_lead'),
          days: _leadDays,
          onChanged: (days) => setState(() => _leadDays = days),
          columnKey: const Key('plan_teamcheck_dialog_lead_wheel'),
        ),
        const SizedBox(height: 8),
        RadioGroup<String>(
          groupValue: _checkMode,
          onChanged: (value) =>
              setState(() => _checkMode = value ?? _checkMode),
          child: const Column(
            children: [
              RadioListTile<String>(
                key: Key('plan_teamcheck_mode_rehearsal'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('到场排练'),
                value: kTeamCheckModeRehearsal,
              ),
              RadioListTile<String>(
                key: Key('plan_teamcheck_mode_video'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('录视频提交'),
                value: kTeamCheckModeVideoSubmission,
              ),
            ],
          ),
        ),
        if (isVideo) ...[
          CheckboxListTile(
            key: const Key('plan_teamcheck_submitted'),
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('已提交'),
            value: _submitted,
            onChanged: (checked) =>
                setState(() => _submitted = checked == true),
          ),
          if (_submitted) ...[
            const Text('提交日期'),
            PlanSubmittedDateWheelField(
              key: const Key('plan_teamcheck_submitted_on'),
              value: _submittedOn,
              fallback: _date,
              today: _today,
              onChanged: (day) => setState(() => _submittedOn = day),
              columnPrefix: 'plan_teamcheck_submitted_on',
            ),
          ],
        ],
        const SizedBox(height: 8),
        const Text('关联舞与达标门'),
        for (final dance in widget.dances)
          planEditorDanceRow(
            videoId: dance.videoId,
            title: dance.title,
            checked: _danceIds.contains(dance.videoId),
            onCheckedChanged: (checked) => setState(() {
              if (checked) {
                _danceIds.add(dance.videoId);
              } else {
                _danceIds.remove(dance.videoId);
              }
            }),
            gate: _danceIds.contains(dance.videoId)
                ? DropdownButton<String>(
                    key: Key('plan_teamcheck_gate_${dance.videoId}'),
                    value: _gates[dance.videoId],
                    items: [
                      for (final gate in TeamCheckGate.values)
                        DropdownMenuItem(
                          value: gate.name,
                          child: Text(teamCheckGateLabel(gate)),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _gates[dance.videoId] =
                          value ?? kTeamCheckGateDefault.name;
                    }),
                  )
                : null,
          ),
      ],
    );
  }
}
