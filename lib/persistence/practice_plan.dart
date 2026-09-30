import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../annotation/learning_segment_attributes.dart';
import '../core/atomic_json_file.dart';
import 'team_check_gate.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';
import 'plan_calendar.dart';
import 'practice_plan_settlement.dart';

// 存储串与剩余天数 / 临期口径在 `plan_calendar.dart`（零 Flutter 纯件，
// 舞库紧急层共用）；此处 re-export，既有取用不受影响。
export 'plan_calendar.dart'
    show
        planDayKey,
        tryParsePlanDay,
        planRemainingDays,
        planIsNearDeadline,
        kPlanNearDeadlineDays;

/// 计划文档：设备级全局私密 JSON
/// （`practice_plan.json`），与练舞统计同款的存储三件套（Storage / Store /
/// providers 见 `practice_plan_providers.dart`）。本文件承载按舞（videoId）
/// 的 DDL：日期、场合标签、备注、提前 N 天、准备清单（每项 = 文本 + 勾选态）
/// 与落档（结论 + 判定日期）。剩余天数、临期口径与落档判定纯件在
/// `practice_plan_settlement.dart`。
///
/// 计划数据**完全私密**：不进公开标记文件、不进分享包，只随整机备份迁移。

/// DDL 默认提供的场合标签（可自定义，20）。
const List<String> kPlanOccasionPresets = ['约舞', '演出'];

/// `HH:mm` 文本 → 当日分钟数；格式或范围（00–23 : 00–59）非法返回 null。
/// 存储读侧与页面编辑框共用的唯一校验口径。
int? tryParseHhMm(String raw) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// 准备清单项的字段 id 枚举（穷尽 switch 的论域）。
enum PlanChecklistItemField { text, checked }

/// 准备清单项：一行文字加一个勾。
@immutable
class PlanChecklistItem {
  const PlanChecklistItem({
    required this.text,
    this.checked = false,
    this.extra = const {},
  });

  final String text;
  final bool checked;

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 归一：文本去首尾空白；空白项视为待丢弃。
  PlanChecklistItem get normalized =>
      PlanChecklistItem(text: text.trim(), checked: checked, extra: extra);

  /// 文本去空白后为空。
  bool get isBlank => text.trim().isEmpty;

  static final RecordCodec<PlanChecklistItem, PlanChecklistItemField> codec =
      RecordCodec<PlanChecklistItem, PlanChecklistItemField>(
        ids: PlanChecklistItemField.values,
        decl: (id) => switch (id) {
          PlanChecklistItemField.text => FieldDecl(
            key: 'text',
            read: (json) => json['text'] is String ? json['text'] : null,
            write: (v) => v.text,
            equal: (a, b) => a.text == b.text,
          ),
          PlanChecklistItemField.checked => FieldDecl(
            key: 'checked',
            read: (json) => json['checked'] == true,
            write: (v) => v.checked,
            equal: (a, b) => a.checked == b.checked,
          ),
        },
        required: const {PlanChecklistItemField.text},
        build: (values) => PlanChecklistItem(
          text: values[PlanChecklistItemField.text]! as String,
          checked: values[PlanChecklistItemField.checked]! as bool,
        ),
        extraOf: (v) => v.extra,
        withExtra: (v, extra) =>
            PlanChecklistItem(text: v.text, checked: v.checked, extra: extra),
      );

  Map<String, dynamic> toJson() => codec.encode(this);

  static PlanChecklistItem? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    return codec.tryDecode(raw);
  }

  @override
  bool operator ==(Object other) =>
      other is PlanChecklistItem && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// DDL 字段 id 枚举（穷尽 switch 的论域）。
enum DanceDdlField { date, occasion, remark, leadDays, checklist, settlement }

/// 落档结论：按时 = 到期时全部学习段为掌握，否则逾期。
enum DdlSettlementOutcome { onTime, overdue }

/// 落档字段 id 枚举（穷尽 switch 的论域）。
enum DdlSettlementField { outcome, judgedOn }

/// 一支舞 DDL 的落档：结论 + 判定日期（本地日）。只写一次——判定落档后
/// 段状态再变化不改写；改期整条重置（见 store 的 setDdl）。
@immutable
class DdlSettlement {
  const DdlSettlement({required this.outcome, required this.judgedOn});

  final DdlSettlementOutcome outcome;

  /// 判定日期（本地日零点，28）。
  final DateTime judgedOn;

  static final RecordCodec<DdlSettlement, DdlSettlementField> codec =
      RecordCodec<DdlSettlement, DdlSettlementField>(
        ids: DdlSettlementField.values,
        decl: (id) => switch (id) {
          DdlSettlementField.outcome => FieldDecl(
            key: 'outcome',
            read: (json) {
              final raw = json['outcome'];
              for (final outcome in DdlSettlementOutcome.values) {
                if (raw == outcome.name) return outcome;
              }
              return null;
            },
            write: (v) => v.outcome.name,
            equal: (a, b) => a.outcome == b.outcome,
          ),
          DdlSettlementField.judgedOn => FieldDecl(
            key: 'judgedOn',
            read: (json) => tryParsePlanDay(json['judgedOn']),
            write: (v) => planDayKey(v.judgedOn),
            equal: (a, b) => a.judgedOn == b.judgedOn,
          ),
        },
        required: const {
          DdlSettlementField.outcome,
          DdlSettlementField.judgedOn,
        },
        build: (values) => DdlSettlement(
          outcome: values[DdlSettlementField.outcome]! as DdlSettlementOutcome,
          judgedOn: values[DdlSettlementField.judgedOn]! as DateTime,
        ),
        // 落档无未知键承载面：结构内只有两个声明字段，无保底区。
        extraOf: (v) => const {},
        withExtra: (v, extra) => v,
      );

  /// 结构读取；结论或日期缺失/非法返回 null（该 DDL 按未落档兜底）。
  static DdlSettlement? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    return codec.tryDecode(Map<String, Object?>.from(raw));
  }

  Map<String, dynamic> toJson() => codec.encode(this);

  @override
  bool operator ==(Object other) =>
      other is DdlSettlement && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// 一支舞的 DDL：日期（本地日）、场合标签、备注、提前 N 天（可空）、准备
/// 清单与落档（可空 = 未判定 / 未到期不预判）。
@immutable
class DanceDdl {
  const DanceDdl({
    required this.date,
    this.occasion = '',
    this.remark = '',
    this.leadDays,
    this.checklist = const [],
    this.settlement,
    this.extra = const {},
  });

  /// 截止日（本地日零点）。
  final DateTime date;

  /// 场合标签（约舞 / 演出，或自定义文本）。
  final String occasion;

  /// 备注（道具、交接提醒）。
  final String remark;

  /// 「提前 N 天」系统提醒；null = 未设。
  final int? leadDays;

  final List<PlanChecklistItem> checklist;

  /// 到期落档（按时 / 逾期 + 判定日期）；null = 未落档。
  final DdlSettlement? settlement;

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 归一：标签与备注去首尾空白、清单丢弃空白项。
  DanceDdl get normalized => DanceDdl(
    date: date,
    occasion: occasion.trim(),
    remark: remark.trim(),
    leadDays: leadDays,
    checklist: [
      for (final item in checklist)
        if (!item.isBlank) item.normalized,
    ],
    extra: extra,
  );

  /// 整体替换语义之外的逐字段改写（改期 / 清单增删勾的 store 动作共用；
  /// 落档不在其中——它由 store 按「同日保留、改期重置」的口径单独经
  /// [withSettlement] 改写）。
  DanceDdl copyWith({
    DateTime? date,
    String? occasion,
    String? remark,
    int? leadDays,
    List<PlanChecklistItem>? checklist,
    Map<String, Object?>? extra,
  }) => DanceDdl(
    date: date ?? this.date,
    occasion: occasion ?? this.occasion,
    remark: remark ?? this.remark,
    leadDays: leadDays ?? this.leadDays,
    checklist: checklist ?? this.checklist,
    settlement: settlement,
    extra: extra ?? this.extra,
  );

  /// 换落档值（null = 重置为未落档）：补判写入与改期重置都经这一处。
  DanceDdl withSettlement(DdlSettlement? settlement) => DanceDdl(
    date: date,
    occasion: occasion,
    remark: remark,
    leadDays: leadDays,
    checklist: checklist,
    settlement: settlement,
    extra: extra,
  );

  DanceDdl _withExtra(Map<String, Object?> extra) => DanceDdl(
    date: date,
    occasion: occasion,
    remark: remark,
    leadDays: leadDays,
    checklist: checklist,
    settlement: settlement,
    extra: extra,
  );

  static final RecordCodec<DanceDdl, DanceDdlField>
  codec = RecordCodec<DanceDdl, DanceDdlField>(
    ids: DanceDdlField.values,
    decl: (id) => switch (id) {
      DanceDdlField.date => FieldDecl(
        key: 'date',
        read: (json) => tryParsePlanDay(json['date']),
        write: (v) => planDayKey(v.date),
        equal: (a, b) => a.date == b.date,
      ),
      DanceDdlField.occasion => FieldDecl(
        key: 'occasion',
        read: (json) => json['occasion'] is String ? json['occasion'] : '',
        write: (v) => v.occasion,
        equal: (a, b) => a.occasion == b.occasion,
      ),
      DanceDdlField.remark => FieldDecl(
        key: 'remark',
        read: (json) => json['remark'] is String ? json['remark'] : '',
        write: (v) => v.remark,
        equal: (a, b) => a.remark == b.remark,
      ),
      DanceDdlField.leadDays => FieldDecl(
        key: 'leadDays',
        read: (json) =>
            json['leadDays'] is num ? (json['leadDays'] as num).toInt() : null,
        write: (v) => v.leadDays ?? omitField,
        equal: (a, b) => a.leadDays == b.leadDays,
      ),
      DanceDdlField.checklist => FieldDecl(
        key: 'checklist',
        read: (json) => <PlanChecklistItem>[
          for (final raw in json['checklist'] as List? ?? const [])
            ?PlanChecklistItem.tryFromJson(raw),
        ],
        write: (v) => [for (final item in v.checklist) item.toJson()],
        equal: (a, b) => _listEquals(a.checklist, b.checklist),
      ),
      DanceDdlField.settlement => FieldDecl(
        key: 'settlement',
        read: (json) => DdlSettlement.tryFromJson(json['settlement']),
        write: (v) => v.settlement == null ? omitField : v.settlement!.toJson(),
        equal: (a, b) => a.settlement == b.settlement,
      ),
    },
    build: (values) => DanceDdl(
      date: values[DanceDdlField.date]! as DateTime,
      occasion: values[DanceDdlField.occasion]! as String,
      remark: values[DanceDdlField.remark]! as String,
      leadDays: values[DanceDdlField.leadDays] as int?,
      checklist: values[DanceDdlField.checklist]! as List<PlanChecklistItem>,
      settlement: values[DanceDdlField.settlement] as DdlSettlement?,
    ),
    extraOf: (v) => v.extra,
    withExtra: (v, extra) => v._withExtra(extra),
  );

  /// 结构读取；日期缺失或非法返回 null（该舞按没有 DDL 兜底），陌生键收进
  /// 保底区原样带回。
  static DanceDdl? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    if (tryParsePlanDay(json['date']) == null) return null;
    return codec.decode(json);
  }

  Map<String, dynamic> toJson() => codec.encode(this);

  @override
  bool operator ==(Object other) =>
      other is DanceDdl && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// JSON 值收窄为 List：非 List（含缺失）按空表兜底——单条事件字段损坏
/// 只丢该字段，不放大成整份文档读取失败。
List<Object?> _asListOrNull(Object? raw) => raw is List ? raw : const [];

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<V>(Map<String, V> a, Map<String, V> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (b[entry.key] != entry.value) return false;
  }
  return true;
}

/// 舞计划条目的字段 id 枚举（穷尽 switch 的论域）。
enum DancePlanEntryField {
  videoId,
  ddl,
  socialLibrary,
  reviewReminders,
  reminderState,
}

/// 复习提醒状态的字段 id 枚举（穷尽 switch 的论域）。
enum DanceReminderStateField { lastRemindedOn, sincePracticeOn, level }

/// 每支舞的复习提醒状态：触发一次落下一条——上次
/// 提醒的本地日（同日一次）、触发依据的最近练习本地日（再练习 = 该日前移
/// 即重新计时）与触发时的档位（档位变化即重新计时）。缺项 = 从未提醒过。
@immutable
class DanceReminderState {
  const DanceReminderState({
    required this.lastRemindedOn,
    required this.sincePracticeOn,
    required this.level,
    this.extra = const {},
  });

  /// 上次提醒的本地日。
  final DateTime lastRemindedOn;

  /// 触发依据的最近练习本地日；null = 触发时从未练过。
  final DateTime? sincePracticeOn;

  /// 触发时的舞档位；null = 未练（无段或全未练）。
  final LearningMastery? level;

  /// 陌生键保底区（逐层保底）：读入时原样带回、写回原样（不参与
  /// 相等）。
  final Map<String, Object?> extra;

  static final RecordCodec<DanceReminderState, DanceReminderStateField> codec =
      RecordCodec<DanceReminderState, DanceReminderStateField>(
        ids: DanceReminderStateField.values,
        decl: (id) => switch (id) {
          DanceReminderStateField.lastRemindedOn => FieldDecl(
            key: 'lastRemindedOn',
            read: (json) => tryParsePlanDay(json['lastRemindedOn']),
            write: (v) => planDayKey(v.lastRemindedOn),
            equal: (a, b) => a.lastRemindedOn == b.lastRemindedOn,
          ),
          DanceReminderStateField.sincePracticeOn => FieldDecl(
            key: 'sincePracticeOn',
            read: (json) => tryParsePlanDay(json['sincePracticeOn']),
            write: (v) => v.sincePracticeOn == null
                ? omitField
                : planDayKey(v.sincePracticeOn!),
            equal: (a, b) => a.sincePracticeOn == b.sincePracticeOn,
          ),
          DanceReminderStateField.level => FieldDecl(
            key: 'level',
            read: (json) => learningMasteryFromName(json['level']),
            write: (v) => v.level?.name ?? omitField,
            equal: (a, b) => a.level == b.level,
          ),
        },
        required: const {DanceReminderStateField.lastRemindedOn},
        build: (values) => DanceReminderState(
          lastRemindedOn:
              values[DanceReminderStateField.lastRemindedOn]! as DateTime,
          sincePracticeOn:
              values[DanceReminderStateField.sincePracticeOn] as DateTime?,
          level: values[DanceReminderStateField.level] as LearningMastery?,
        ),
        extraOf: (v) => v.extra,
        withExtra: (v, extra) => DanceReminderState(
          lastRemindedOn: v.lastRemindedOn,
          sincePracticeOn: v.sincePracticeOn,
          level: v.level,
          extra: extra,
        ),
      );

  /// 结构读取；日期缺失或非法返回 null（按从未提醒过兜底），陌生键收进
  /// 保底区原样带回。
  static DanceReminderState? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    return codec.tryDecode(Map<String, Object?>.from(raw));
  }

  Map<String, dynamic> toJson() => codec.encode(this);

  @override
  bool operator ==(Object other) =>
      other is DanceReminderState && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// 按舞的一条计划条目：舞标识 + 该舞的 DDL（可缺席 = 没有目标）+
/// 随舞曲库开关（缺项 = 开）+ 复习提醒开关（缺项 = 开）+
/// 复习提醒状态（缺项 = 从未提醒）。
@immutable
class DancePlanEntry {
  const DancePlanEntry({
    required this.videoId,
    this.ddl,
    this.socialLibrary = true,
    this.reviewReminders = true,
    this.reminderState,
    this.extra = const {},
  });

  final String videoId;

  /// 该舞的 DDL；null = 没有设过（或已清除）。
  final DanceDdl? ddl;

  /// 随舞曲库开关：false = 关（不被新建随舞事件默认带入、不被随舞临近
  /// 提醒催）；缺项按开。
  final bool socialLibrary;

  /// 复习提醒开关：false = 关（不参与遗忘复习与随舞临近提醒）；
  /// 缺项按开。
  final bool reviewReminders;

  /// 复习提醒状态；null = 从未提醒。
  final DanceReminderState? reminderState;

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  DancePlanEntry _withExtra(Map<String, Object?> extra) => DancePlanEntry(
    videoId: videoId,
    ddl: ddl,
    socialLibrary: socialLibrary,
    reviewReminders: reviewReminders,
    reminderState: reminderState,
    extra: extra,
  );

  /// 整体替换语义之外的逐字段改写（DDL 写面与开关翻转的 store 动作共用，
  /// 重建条目不再手携未变字段）。
  DancePlanEntry copyWith({
    String? videoId,
    DanceDdl? ddl,
    bool clearDdl = false,
    bool? socialLibrary,
    bool? reviewReminders,
    DanceReminderState? reminderState,
    bool clearReminderState = false,
    Map<String, Object?>? extra,
  }) => DancePlanEntry(
    videoId: videoId ?? this.videoId,
    ddl: clearDdl ? null : (ddl ?? this.ddl),
    socialLibrary: socialLibrary ?? this.socialLibrary,
    reviewReminders: reviewReminders ?? this.reviewReminders,
    reminderState: clearReminderState
        ? null
        : (reminderState ?? this.reminderState),
    extra: extra ?? this.extra,
  );

  static final RecordCodec<DancePlanEntry, DancePlanEntryField> codec =
      RecordCodec<DancePlanEntry, DancePlanEntryField>(
        ids: DancePlanEntryField.values,
        decl: (id) => switch (id) {
          DancePlanEntryField.videoId => FieldDecl(
            key: 'videoId',
            read: (json) => json['videoId'] is String ? json['videoId'] : '',
            write: (v) => v.videoId,
            equal: (a, b) => a.videoId == b.videoId,
          ),
          DancePlanEntryField.ddl => FieldDecl(
            key: 'ddl',
            read: (json) => DanceDdl.tryFromJson(json['ddl']),
            write: (v) => v.ddl == null ? omitField : v.ddl!.toJson(),
            equal: (a, b) => (a.ddl == b.ddl),
          ),
          DancePlanEntryField.socialLibrary => FieldDecl(
            key: 'socialLibrary',
            read: (json) => json['socialLibrary'] != false,
            write: (v) => v.socialLibrary ? omitField : false,
            equal: (a, b) => a.socialLibrary == b.socialLibrary,
          ),
          DancePlanEntryField.reviewReminders => FieldDecl(
            key: 'reviewReminders',
            read: (json) => json['reviewReminders'] != false,
            write: (v) => v.reviewReminders ? omitField : false,
            equal: (a, b) => a.reviewReminders == b.reviewReminders,
          ),
          DancePlanEntryField.reminderState => FieldDecl(
            key: 'reminderState',
            read: (json) =>
                DanceReminderState.tryFromJson(json['reminderState']),
            write: (v) =>
                v.reminderState == null ? omitField : v.reminderState!.toJson(),
            equal: (a, b) => a.reminderState == b.reminderState,
          ),
        },
        build: (values) => DancePlanEntry(
          videoId: values[DancePlanEntryField.videoId]! as String,
          ddl: values[DancePlanEntryField.ddl] as DanceDdl?,
          socialLibrary: values[DancePlanEntryField.socialLibrary]! as bool,
          reviewReminders: values[DancePlanEntryField.reviewReminders]! as bool,
          reminderState:
              values[DancePlanEntryField.reminderState] as DanceReminderState?,
        ),
        extraOf: (v) => v.extra,
        withExtra: (v, extra) => v._withExtra(extra),
      );

  Map<String, dynamic> toJson() => codec.encode(this);

  @override
  bool operator ==(Object other) =>
      other is DancePlanEntry && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// 计划事件类型：随舞事件与团内检查。
const String kPlanEventTypeSocial = 'socialDanceEvent';

/// 团内检查：日期 + 关联舞清单 + 每舞达标门 + 检查方式。
const String kPlanEventTypeTeamCheck = 'teamCheck';

/// 检查方式：到场排练（无提交标记）与录视频提交。
const String kTeamCheckModeRehearsal = 'rehearsal';
const String kTeamCheckModeVideoSubmission = 'videoSubmission';

/// 存储读侧的检查方式合法性（未知值按到场排练兜底）。
bool _isTeamCheckMode(Object? raw) =>
    raw == kTeamCheckModeRehearsal || raw == kTeamCheckModeVideoSubmission;

/// 存储读侧的达标门表：键非空串、门名合法（未知门名的键按不设丢弃）。
Map<String, String> _readDanceGates(Object? raw) => raw is Map
    ? {
        for (final entry in raw.entries)
          if (entry.key is String &&
              (entry.key as String).isNotEmpty &&
              _isGateName(entry.value))
            entry.key as String: entry.value as String,
      }
    : const {};

/// 门名合法性以达标门枚举为唯一口径。
bool _isGateName(Object? raw) =>
    raw is String && TeamCheckGate.values.any((gate) => gate.name == raw);

/// 存储读侧的 `HH:mm` 合法性（[tryParseHhMm] 同一口径，超界视为未设）。
bool _isHhMm(Object? raw) => raw is String && tryParseHhMm(raw) != null;

/// 计划事件的字段 id 枚举（穷尽 switch 的论域）。
enum PlanEventField {
  id,
  type,
  date,
  startTime,
  location,
  remark,
  danceIds,
  checklist,
  danceGates,
  checkMode,
  submittedOn,
  leadDays,
}

/// 一场计划事件（随舞事件；团内检查）：id、类型、日期、
/// 可选开始时间（本地 `HH:mm` 文本）、可选地点备注、备注、关联舞清单与
/// 准备清单。团检另有：每舞达标门表、检查方式与提交日期（仅录视频提交
/// 用；null = 未提交）。旧事件缺团检字段按 不设 / 到场排练 / 未提交 兜底。
@immutable
class PlanEvent {
  const PlanEvent({
    required this.id,
    required this.date,
    this.type = kPlanEventTypeSocial,
    this.startTime,
    this.location = '',
    this.remark = '',
    this.danceIds = const [],
    this.checklist = const [],
    this.danceGates = const {},
    this.checkMode = kTeamCheckModeRehearsal,
    this.submittedOn,
    this.leadDays,
    this.extra = const {},
  });

  /// 事件 id（文档内唯一；缺失或空串 = 损坏条目，按丢弃兜底）。
  final String id;

  final String type;

  /// 事件日（本地日零点）。
  final DateTime date;

  /// 可选开始时间（`HH:mm` 文本；null = 未设）。
  final String? startTime;

  final String location;

  final String remark;

  /// 关联舞清单（videoId 列表）。
  final List<String> danceIds;

  /// 准备清单（删除事件时随它一起消失）。
  final List<PlanChecklistItem> checklist;

  /// 每舞达标门表（videoId → 门名，仅团内检查用；缺项 = 不设）。
  final Map<String, String> danceGates;

  /// 检查方式（仅团内检查用；缺项 = 到场排练）。
  final String checkMode;

  /// 提交日期（仅录视频提交用；null = 未提交）。
  final DateTime? submittedOn;

  /// 「提前 N 天」系统推送提醒（null = 未设）。
  final int? leadDays;

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 归一：文本去首尾空白、清单丢弃空白项、关联清单去空串去重（保序）、
  /// 达标门表键去空白去空串。
  PlanEvent get normalized {
    final seen = <String>{};
    return PlanEvent(
      id: id.trim(),
      type: type,
      date: date,
      startTime: startTime,
      leadDays: leadDays,
      location: location.trim(),
      remark: remark.trim(),
      danceIds: [
        for (final id in danceIds)
          if (id.trim().isNotEmpty && seen.add(id.trim())) id.trim(),
      ],
      checklist: [
        for (final item in checklist)
          if (!item.isBlank) item.normalized,
      ],
      danceGates: {
        for (final entry in danceGates.entries)
          if (entry.key.trim().isNotEmpty) entry.key.trim(): entry.value,
      },
      checkMode: checkMode,
      submittedOn: submittedOn,
      extra: extra,
    );
  }

  PlanEvent _withExtra(Map<String, Object?> extra) => PlanEvent(
    id: id,
    type: type,
    date: date,
    startTime: startTime,
    leadDays: leadDays,
    location: location,
    remark: remark,
    danceIds: danceIds,
    checklist: checklist,
    danceGates: danceGates,
    checkMode: checkMode,
    submittedOn: submittedOn,
    extra: extra,
  );

  /// 关联舞清单的逐字段改写（删舞与恢复清理摘关联项共用）。
  PlanEvent copyWith({List<String>? danceIds}) => PlanEvent(
    id: id,
    type: type,
    date: date,
    startTime: startTime,
    leadDays: leadDays,
    location: location,
    remark: remark,
    danceIds: danceIds ?? this.danceIds,
    checklist: checklist,
    extra: extra,
  );

  static final RecordCodec<PlanEvent, PlanEventField> codec =
      RecordCodec<PlanEvent, PlanEventField>(
        ids: PlanEventField.values,
        decl: (id) => switch (id) {
          PlanEventField.id => FieldDecl(
            key: 'id',
            read: (json) => json['id'] is String ? json['id'] : null,
            write: (v) => v.id,
            equal: (a, b) => a.id == b.id,
          ),
          PlanEventField.type => FieldDecl(
            key: 'type',
            read: (json) =>
                json['type'] is String ? json['type'] : kPlanEventTypeSocial,
            write: (v) => v.type,
            equal: (a, b) => a.type == b.type,
          ),
          PlanEventField.date => FieldDecl(
            key: 'date',
            read: (json) => tryParsePlanDay(json['date']),
            write: (v) => planDayKey(v.date),
            equal: (a, b) => a.date == b.date,
          ),
          PlanEventField.startTime => FieldDecl(
            key: 'startTime',
            read: (json) =>
                _isHhMm(json['startTime']) ? json['startTime'] as String : null,
            write: (v) => v.startTime ?? omitField,
            equal: (a, b) => a.startTime == b.startTime,
          ),
          PlanEventField.location => FieldDecl(
            key: 'location',
            read: (json) => json['location'] is String ? json['location'] : '',
            write: (v) => v.location,
            equal: (a, b) => a.location == b.location,
          ),
          PlanEventField.remark => FieldDecl(
            key: 'remark',
            read: (json) => json['remark'] is String ? json['remark'] : '',
            write: (v) => v.remark,
            equal: (a, b) => a.remark == b.remark,
          ),
          PlanEventField.danceIds => FieldDecl(
            key: 'danceIds',
            read: (json) => <String>[
              for (final raw in _asListOrNull(json['danceIds']))
                if (raw is String) raw,
            ],
            write: (v) => v.danceIds,
            equal: (a, b) => _listEquals(a.danceIds, b.danceIds),
          ),
          PlanEventField.checklist => FieldDecl(
            key: 'checklist',
            read: (json) => <PlanChecklistItem>[
              for (final raw in _asListOrNull(json['checklist']))
                ?PlanChecklistItem.tryFromJson(raw),
            ],
            write: (v) => [for (final item in v.checklist) item.toJson()],
            equal: (a, b) => _listEquals(a.checklist, b.checklist),
          ),
          PlanEventField.danceGates => FieldDecl(
            key: 'danceGates',
            read: (json) => _readDanceGates(json['danceGates']),
            write: (v) => v.danceGates.isEmpty
                ? omitField
                : Map<String, Object?>.of(v.danceGates),
            equal: (a, b) => _mapEquals(a.danceGates, b.danceGates),
          ),
          PlanEventField.checkMode => FieldDecl(
            key: 'checkMode',
            read: (json) => _isTeamCheckMode(json['checkMode'])
                ? json['checkMode'] as String
                : kTeamCheckModeRehearsal,
            write: (v) => v.checkMode,
            equal: (a, b) => a.checkMode == b.checkMode,
          ),
          PlanEventField.submittedOn => FieldDecl(
            key: 'submittedOn',
            read: (json) => tryParsePlanDay(json['submittedOn']),
            write: (v) =>
                v.submittedOn == null ? omitField : planDayKey(v.submittedOn!),
            equal: (a, b) => a.submittedOn == b.submittedOn,
          ),
          PlanEventField.leadDays => FieldDecl(
            key: 'leadDays',
            read: (json) =>
                json['leadDays'] is num ? (json['leadDays'] as num).toInt() : null,
            write: (v) => v.leadDays ?? omitField,
            equal: (a, b) => a.leadDays == b.leadDays,
          ),
        },
        required: const {PlanEventField.id, PlanEventField.date},
        build: (values) => PlanEvent(
          id: values[PlanEventField.id]! as String,
          type: values[PlanEventField.type]! as String,
          date: values[PlanEventField.date]! as DateTime,
          startTime: values[PlanEventField.startTime] as String?,
          location: values[PlanEventField.location]! as String,
          remark: values[PlanEventField.remark]! as String,
          danceIds: values[PlanEventField.danceIds]! as List<String>,
          checklist:
              values[PlanEventField.checklist]! as List<PlanChecklistItem>,
          danceGates: values[PlanEventField.danceGates]! as Map<String, String>,
          checkMode: values[PlanEventField.checkMode]! as String,
          submittedOn: values[PlanEventField.submittedOn] as DateTime?,
          leadDays: values[PlanEventField.leadDays] as int?,
        ),
        extraOf: (v) => v.extra,
        withExtra: (v, extra) => v._withExtra(extra),
      );

  /// 结构读取；id 缺失/空串或日期非法返回 null（整条按损坏丢弃兜底），
  /// 陌生键收进保底区原样带回。
  static PlanEvent? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, Object?>.from(raw);
    final id = json['id'];
    if (id is! String || id.isEmpty) return null;
    if (tryParsePlanDay(json['date']) == null) return null;
    return codec.decode(json);
  }

  Map<String, dynamic> toJson() => codec.encode(this);

  @override
  bool operator ==(Object other) =>
      other is PlanEvent && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

@immutable
class PracticePlanDocument {
  const PracticePlanDocument({
    this.entries = const [],
    this.events = const [],
    this.extra = const {},
  });

  const PracticePlanDocument.empty() : this();

  /// 练习计划的版本链：地板 1，链为空（地板 = 本版）。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 1,
  );

  final List<DancePlanEntry> entries;

  /// 事件列表（随舞事件；的团内检查同住此列表）。
  final List<PlanEvent> events;

  /// 文档级陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  static final ListDocumentCodec<
    PracticePlanDocument,
    DancePlanEntry,
    DancePlanEntryField
  >
  _codec = ListDocumentCodec(
    policy: versionPolicy,
    listKey: 'entries',
    elementCodec: DancePlanEntry.codec,
    empty: PracticePlanDocument.empty,
    // videoId 缺失（读到空串）的条目 = 损坏条目，按丢弃兜底。
    build: (elements) => PracticePlanDocument(
      entries: [
        for (final entry in elements)
          if (entry.videoId.isNotEmpty) entry,
      ],
    ),
    listOf: (doc) => doc.entries,
    extraOf: (doc) => doc.extra,
    withExtra: (doc, extra) =>
        PracticePlanDocument(entries: doc.entries, extra: extra),
  );

  Map<String, dynamic> toJson() => {
    ...extra,
    'version': versionPolicy.currentVersion,
    'entries': [for (final entry in entries) entry.toJson()],
    'events': [for (final event in events) event.toJson()],
  };

  /// 容错读取（版本政策）：顶层非对象、低于地板（政策判空）
  /// 按空态兜底，不崩溃；entries 层走 [ListDocumentCodec]（条目级保底与
  /// 损坏丢弃同款），events 层同口径逐条读（id/日期非法整条丢弃）；文档
  /// 级未知键原样带回。高于本版与版本头读不出都按「认识多少读多少」打开，
  /// 只由写侧 [DocumentVersionPolicy.isWritable] 判不可写。
  factory PracticePlanDocument.fromJson(Object? json) {
    if (json is! Map) return const PracticePlanDocument.empty();
    final map = Map<String, Object?>.from(json);
    final upgraded = PracticePlanDocument.versionPolicy.upgrade(map).json;
    if (upgraded.isEmpty) return const PracticePlanDocument.empty();
    final entriesPart = PracticePlanDocument._codec.decode(
      <String, Object?>{...upgraded}..remove('events'),
    );
    // events 解排任何异常只丢 events，不放大成整份文档兜底为空
    //（否则下次写盘会把既有 DDL 一并清掉）。
    var events = const <PlanEvent>[];
    try {
      events = <PlanEvent>[
        for (final raw in _asListOrNull(upgraded['events']))
          ?PlanEvent.tryFromJson(raw),
      ];
    } on Object {
      events = const [];
    }
    return PracticePlanDocument(
      entries: entriesPart.entries,
      events: events,
      extra: entriesPart.extra,
    );
  }
}

/// `practice_plan.json` 的原始 JSON 读写 seam。store 只经本接口触达磁盘；
/// 测试注入内存 fake（`test/helpers/in_memory_practice_plan_storage.dart`）
/// 与真实实现双跑。
abstract interface class PracticePlanStorage {
  /// 读取整份 JSON；缺失/损坏返回 null。
  Future<Map<String, dynamic>?> loadOrNull();

  /// 整份覆盖写入（原子写）。
  Future<void> save(Map<String, dynamic> json);
}

/// [PracticePlanStorage] 的真实文件实现（设备全局 `practice_plan.json`）。
///
/// [fileFactory] 为文件解析闭包（非现成 Future）：目录解析只在首次真正
/// 读写时发生（与练舞统计同款）。
class AtomicPracticePlanStorage implements PracticePlanStorage {
  AtomicPracticePlanStorage(this._fileFactory);

  final Future<File> Function() _fileFactory;

  AtomicJsonFile? _atomic;
  AtomicJsonFile get _lazy => _atomic ??= AtomicJsonFile(_fileFactory());

  @override
  Future<Map<String, dynamic>?> loadOrNull() => _lazy.readOrNull();

  @override
  Future<void> save(Map<String, dynamic> json) => _lazy.write(json);
}

/// 计划全局 store：`practice_plan.json` 的**唯一读写入口**（设备全局私密
/// 文件）。页面不自己拼 JSON：DDL 的设 / 改 / 清与清单项增删打勾、到期
/// 落档补判都经本 store，写成功即落盘；磁盘错误静默承接（内存态保留，
/// 下次写重试）。
///
/// 落档触发点 = 装载（[PracticePlanStore] 首次读盘）：装载时对
/// 「已过到期日且未落档」的条目按当时段熟练度补判一次（[masteryOf] 提供
/// 各舞的段档位集合，解析失败按未落档跳过、下次装载再试）；已落档条目
/// 不重写（幂等）。
class PracticePlanStore {
  PracticePlanStore(
    this._storage, {
    Future<Set<LearningMastery>?> Function(String videoId)? masteryOf,
    DateTime Function()? clock,
    void Function()? onChanged,
  }) {
    _masteryOf = masteryOf;
    _clock = clock ?? DateTime.now;
    _onChanged = onChanged;
  }
  final PracticePlanStorage _storage;

  /// 各舞学习段档位集合的读入口；null = 不补判（返回的 Set 为 null 同样
  /// 跳过该舞）。
  late final Future<Set<LearningMastery>?> Function(String videoId)? _masteryOf;

  late final DateTime Function() _clock;

  /// 写盘成功后的通知钩子（系统推送排程随之取消 / 重排）；null =
  /// 无订阅。
  late final void Function()? _onChanged;

  Future<void> _chain = Future<void>.value();

  List<DancePlanEntry> _entries = const [];
  List<PlanEvent> _events = const [];
  Map<String, Object?> _docExtra = const {};
  bool _loaded = false;

  /// 盘上文件不可写（高于本版 / 版本头读不出，见
  /// [DocumentVersionPolicy.isWritable]）：读面按「认识多少读多少」打开，
  /// 但本机不写回。
  bool _readOnly = false;

  /// 读该舞的 DDL；无条目 / DDL 缺席 / 日期非法都按「没有 DDL」。
  Future<DanceDdl?> ddlOf(String videoId) async {
    await _ensureLoaded();
    for (final entry in _entries) {
      if (entry.videoId == videoId) return entry.ddl;
    }
    return null;
  }

  /// 读全部计划条目（计划页读面）。首次调用触发装载；之后本进程内的写
  /// （同 store 实例）已同步进内存态，跨进程变更不在此读出。
  Future<List<DancePlanEntry>> entries() async {
    await _ensureLoaded();
    return _entries;
  }

  /// 该舞条目的内存读面（无则 null）。
  DancePlanEntry? _entryOf(String videoId) {
    for (final entry in _entries) {
      if (entry.videoId == videoId) return entry;
    }
    return null;
  }

  /// 设 / 改（整体替换）该舞的 DDL。同日改写（备注 / 清单等）保留既有
  /// 落档——落档只写一次；改期落档重置，由装载按新日期重算（未到期不
  /// 预判）。曲库开关与条目保底区原样带回。
  Future<bool> setDdl({required String videoId, required DanceDdl ddl}) =>
      _enqueue(() async {
        await _ensureLoaded();
        final entry = _entryOf(videoId);
        final existing = entry?.ddl;
        final normalized = ddl.normalized;
        return _write(
          _upsertEntry(
            (entry ?? DancePlanEntry(videoId: videoId)).copyWith(
              videoId: videoId,
              ddl: existing != null && existing.date == normalized.date
                  ? normalized.withSettlement(existing.settlement)
                  : normalized,
              socialLibrary: entry?.socialLibrary ?? true,
            ),
          ),
          _events,
        );
      });

  /// 清除该舞的 DDL（清单随它消失；本来没有也视为成功）。开关关着的舞
  /// 条目保留（只摘掉 DDL），开关开着的舞无 DDL 即条目一并移除。
  Future<bool> clearDdl(String videoId) => _enqueue(() async {
    await _ensureLoaded();
    return _write([
      for (final e in _entries)
        if (e.videoId != videoId)
          e
        else if (!e.socialLibrary)
          e.copyWith(clearDdl: true),
    ], _events);
  });

  /// 读全部计划事件（升序保持落盘次序）。首次调用触发装载。
  Future<List<PlanEvent>> events() async {
    await _ensureLoaded();
    return _events;
  }

  /// 新建 / 编辑（按 id 整体替换）一场事件；id 为空的事件不建。
  Future<bool> saveEvent(PlanEvent event) => _enqueue(() async {
    await _ensureLoaded();
    final next = event.normalized;
    if (next.id.isEmpty) return false;
    final events = [..._events];
    final index = events.indexWhere((e) => e.id == next.id);
    if (index < 0) {
      events.add(next);
    } else {
      events[index] = next;
    }
    return _write(_entries, events);
  });

  /// 删除事件，其准备清单随它一起消失；本来没有也视为成功。
  Future<bool> deleteEvent(String id) => _enqueue(() async {
    await _ensureLoaded();
    return _write(_entries, [
      for (final event in _events)
        if (event.id != id) event,
    ]);
  });

  /// 该舞的随舞曲库开关读面（无条目 = 开）。
  Future<bool> socialLibraryEnabledOf(String videoId) async {
    await _ensureLoaded();
    return _entryOf(videoId)?.socialLibrary ?? true;
  }

  /// 显式关掉随舞曲库开关的舞（缺项按开，不在集合内）。
  Future<Set<String>> socialLibraryDisabledIds() async {
    await _ensureLoaded();
    return {
      for (final entry in _entries)
        if (!entry.socialLibrary) entry.videoId,
    };
  }

  /// 翻转该舞的随舞曲库开关（缺项 = 开）。开回且无 DDL 时条目一并移除
  /// （不留空条目）；不存在的舞直接关 = 新建只带开关的条目。
  Future<bool> setSocialLibrary({
    required String videoId,
    required bool enabled,
  }) => _enqueue(() async {
    await _ensureLoaded();
    final entry = _entryOf(videoId);
    if (enabled) {
      if (entry == null || entry.socialLibrary) {
        return _write(_entries, _events);
      }
      final next = entry.copyWith(socialLibrary: true);
      return _write(
        next.ddl == null
            ? [
                for (final e in _entries)
                  if (e.videoId != videoId) e,
              ]
            : _upsertEntry(next),
        _events,
      );
    }
    if (entry != null && !entry.socialLibrary) {
      return _write(_entries, _events);
    }
    return _write(
      _upsertEntry(
        (entry ?? DancePlanEntry(videoId: videoId)).copyWith(
          socialLibrary: false,
        ),
      ),
      _events,
    );
  });

  /// 该舞的复习提醒开关读面（无条目 = 开）。
  Future<bool> reviewRemindersEnabledOf(String videoId) async {
    await _ensureLoaded();
    return _entryOf(videoId)?.reviewReminders ?? true;
  }

  /// 该舞的复习提醒状态读面（无条目 / 缺项 = null，从未提醒过）。
  Future<DanceReminderState?> reminderStateOf(String videoId) async {
    await _ensureLoaded();
    return _entryOf(videoId)?.reminderState;
  }

  /// 落下该舞的复习提醒状态（评估方触发提醒后写回，供冷却与重新
  /// 计时判定）。状态相同不写盘；无条目 = 新建只带状态的条目。
  Future<bool> saveReminderState(String videoId, DanceReminderState state) =>
      _enqueue(() async {
        await _ensureLoaded();
        final entry = _entryOf(videoId);
        if (entry != null && entry.reminderState == state) {
          return true;
        }
        return _write(
          _upsertEntry(
            (entry ?? DancePlanEntry(videoId: videoId)).copyWith(
              reminderState: state,
            ),
          ),
          _events,
        );
      });

  /// 翻转该舞的复习提醒开关（缺项 = 开）。开回且条目再无有效内容
  /// （无 DDL、随舞曲库开）时条目一并移除（不留空条目）；不存在的舞直接
  /// 关 = 新建只带开关的条目。
  Future<bool> setReviewReminders({
    required String videoId,
    required bool enabled,
  }) => _enqueue(() async {
    await _ensureLoaded();
    final entry = _entryOf(videoId);
    if (enabled) {
      if (entry == null || entry.reviewReminders) {
        return _write(_entries, _events);
      }
      final next = entry.copyWith(reviewReminders: true);
      final bare = next.ddl == null && next.socialLibrary;
      return _write(
        bare
            ? [
                for (final e in _entries)
                  if (e.videoId != videoId) e,
              ]
            : _upsertEntry(next),
        _events,
      );
    }
    if (entry != null && !entry.reviewReminders) {
      return _write(_entries, _events);
    }
    return _write(
      _upsertEntry(
        (entry ?? DancePlanEntry(videoId: videoId)).copyWith(
          reviewReminders: false,
        ),
      ),
      _events,
    );
  });

  /// 恢复侧全量替换：按备份原文整份覆盖本机计划
  /// 文档，不合并；原文里的未知键原样落位。原文损坏（版本门 / 结构不符）
  /// 按空态替换，不把损坏 JSON 原样留在盘上。写失败回滚内存态并返回
  /// false（恢复侧据此折成恢复失败），不出现内存与磁盘分叉；成功后照
  /// 装载口径补判一次落档。
  ///
  /// 这是**显式全量替换**语义的写入口，刻意不咨询
  /// [DocumentVersionPolicy.isWritable]：本机现值就是被备份原文覆盖的
  /// 对象（保留这份原文的职责落在原始文件缝的留档，而非本 store）。
  Future<bool> replaceWithJson(Map<String, Object?> json) => _enqueue(() async {
    await _ensureLoaded();
    final document = PracticePlanDocument.fromJson(json);
    final corrupted =
        json.isNotEmpty &&
        document.entries.isEmpty &&
        document.events.isEmpty &&
        document.extra.isEmpty;
    final payload = corrupted
        ? const PracticePlanDocument.empty().toJson()
        : json;
    final previousEntries = _entries;
    final previousEvents = _events;
    final previousExtra = _docExtra;
    _entries = document.entries;
    _events = document.events;
    _docExtra = document.extra;
    try {
      await _storage.save(payload);
    } on Object {
      _entries = previousEntries;
      _events = previousEvents;
      _docExtra = previousExtra;
      return false;
    }
    await _backfillSettlements();
    _onChanged?.call();
    return true;
  });

  /// 「备份里没有的舞」的清理：保留集之外的舞条目
  /// 整条清掉（DDL、落档、开关随它消失）；事件条目保留，只摘掉保留集之外
  /// 舞的关联项（关联清单允许为空）。条目与事件关联都没有变化时不写盘。
  Future<bool> retainDances(Set<String> videoIds) => _enqueue(() async {
    await _ensureLoaded();
    return _applyLifecycle(
      keptEntries: [
        for (final entry in _entries)
          if (videoIds.contains(entry.videoId)) entry,
      ],
      stripDanceId: (id) => !videoIds.contains(id),
    );
  });

  /// 删舞清理：该舞条目整条移除（DDL、落档、开关
  /// 随它消失）；事件条目保留，只摘掉它的关联项（清单允许为空）。本来没有
  /// 也视为成功（条目与事件关联都没变时不写盘）。
  Future<bool> removeDance(String videoId) => _enqueue(() async {
    await _ensureLoaded();
    return _applyLifecycle(
      keptEntries: [
        for (final entry in _entries)
          if (entry.videoId != videoId) entry,
      ],
      stripDanceId: (id) => id == videoId,
    );
  });

  /// 生命周期写盘共用：条目按过滤结果整份替换、
  /// 事件按 [stripDanceId] 摘关联项。都没有变化（顺序保持下条目长度不变且
  /// 无事件命中）就不动盘，幂等；强制落盘走 [replaceWithJson]。
  Future<bool> _applyLifecycle({
    required List<DancePlanEntry> keptEntries,
    required bool Function(String id) stripDanceId,
  }) {
    final entriesChanged = keptEntries.length != _entries.length;
    final nextEvents = <PlanEvent>[];
    var eventsChanged = false;
    for (final event in _events) {
      final kept = [
        for (final id in event.danceIds)
          if (!stripDanceId(id)) id,
      ];
      if (kept.length == event.danceIds.length) {
        nextEvents.add(event);
      } else {
        eventsChanged = true;
        nextEvents.add(event.copyWith(danceIds: kept));
      }
    }
    if (!entriesChanged && !eventsChanged) return Future<bool>.value(true);
    return _write(keptEntries, nextEvents);
  }

  /// 追加一条清单项（文本按归一口径去空白；空白文本不建）。
  Future<bool> addChecklistItem({
    required String videoId,
    required String text,
  }) {
    final item = PlanChecklistItem(text: text).normalized;
    return _mutateDdl(videoId, (ddl) {
      if (item.isBlank) return ddl;
      return ddl.copyWith(checklist: [...ddl.checklist, item]);
    });
  }

  /// 勾 / 取消勾第 [index] 项；越界为 no-op。
  Future<bool> setChecklistItemChecked({
    required String videoId,
    required int index,
    required bool checked,
  }) => _mutateDdl(videoId, (ddl) {
    if (index < 0 || index >= ddl.checklist.length) return ddl;
    return ddl.copyWith(
      checklist: [
        for (var i = 0; i < ddl.checklist.length; i++)
          if (i == index)
            PlanChecklistItem(
              text: ddl.checklist[i].text,
              checked: checked,
              extra: ddl.checklist[i].extra,
            )
          else
            ddl.checklist[i],
      ],
    );
  });

  /// 删除第 [index] 项；越界为 no-op。
  Future<bool> removeChecklistItem({
    required String videoId,
    required int index,
  }) => _mutateDdl(videoId, (ddl) {
    if (index < 0 || index >= ddl.checklist.length) return ddl;
    return ddl.copyWith(checklist: [...ddl.checklist]..removeAt(index));
  });

  /// 对该舞 DDL 的读改写：无 DDL 时不建条目（返回 false）。
  Future<bool> _mutateDdl(
    String videoId,
    DanceDdl Function(DanceDdl ddl) mutate,
  ) => _enqueue(() async {
    await _ensureLoaded();
    final entry = _entryOf(videoId);
    final ddl = entry?.ddl;
    if (ddl == null) return false;
    return _write(_upsertEntry(entry!.copyWith(ddl: mutate(ddl))), _events);
  });

  /// 条目按原位置替换、不存在则追加（不打乱其余条目的落盘次序）。
  List<DancePlanEntry> _upsertEntry(DancePlanEntry next) {
    final index = _entries.indexWhere((e) => e.videoId == next.videoId);
    if (index < 0) return [..._entries, next];
    return [
      for (var i = 0; i < _entries.length; i++)
        if (i == index) next else _entries[i],
    ];
  }

  /// 写盘：先改内存、再落盘；写失败静默承接（内存态保留、不回滚，下次
  /// 写重试整份落盘，与练舞统计同款）。
  Future<bool> _write(
    List<DancePlanEntry> entries,
    List<PlanEvent> events,
  ) async {
    if (_readOnly) return false;
    _entries = entries;
    _events = events;
    final document = PracticePlanDocument(
      entries: entries,
      events: events,
      extra: _docExtra,
    );
    try {
      await _storage.save(document.toJson());
    } on Object {
      return false;
    }
    _onChanged?.call();
    return true;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final json = await _storage.loadOrNull();
      _readOnly =
          json != null &&
          !PracticePlanDocument.versionPolicy.isWritable(json);
      final document = json == null
          ? const PracticePlanDocument.empty()
          : PracticePlanDocument.fromJson(json);
      _entries = document.entries;
      _events = document.events;
      _docExtra = document.extra;
    } on Object {
      _entries = const [];
      _events = const [];
      _docExtra = const {};
    }
    await _backfillSettlements();
  }

  /// 装载补判：对「已过到期日且未落档」的条目判定一次并整份写回。
  /// 已落档与未到期的条目不动（幂等、不预判）；解析不出段档位的舞留待
  /// 下次装载。写失败静默承接——内存态已更新，下次装载重试整份落盘。
  Future<void> _backfillSettlements() async {
    final resolver = _masteryOf;
    if (resolver == null) return;
    final now = _clock();
    var changed = false;
    final next = List<DancePlanEntry>.of(_entries);
    for (var i = 0; i < next.length; i++) {
      final ddl = next[i].ddl;
      if (ddl == null || ddl.settlement != null) continue;
      if (planRemainingDays(dueDay: ddl.date, now: now) >= 0) continue;
      final Set<LearningMastery>? masteries;
      try {
        masteries = await resolver(next[i].videoId);
      } on Object {
        continue;
      }
      if (masteries == null) continue;
      final settlement = judgeDdlSettlement(
        segmentMasteries: masteries,
        dueDay: ddl.date,
        now: now,
      );
      if (settlement == null) continue;
      next[i] = next[i].copyWith(ddl: ddl.withSettlement(settlement));
      changed = true;
    }
    if (changed) await _write(next, _events);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final run = _chain.then((_) => action());
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}
