import '../core/local_day.dart';
import '../persistence/practice_plan.dart';

/// 系统推送：投递能力抽象为端口（查询权限 / 请求
/// 权限 / 安排 / 取消），真实实现基于本地通知插件与时区包
/// （`system_push_local.dart`），测试注入内存替身。排程来源只有两条——
/// 用户设的「提前 N 天」（DDL / 团内检查 / 随舞事件）与自动规则「DDL 剩
/// ≤3 天且非完全掌握」；其余提醒留在应用内。全部排程走非精确
/// 调度（空闲可延后），不申请精确闹钟权限。

/// 投递时刻的当地钟点：日期型目标（DDL、团内检查、
/// 未填开始时间的随舞事件）在目标日减提前天数的当地 09:00 投递。
const int kPushDeliveryHour = 9;

/// 一条系统推送排程：稳定 id、当地投递时刻与文案。
class PushNotification {
  const PushNotification({
    required this.id,
    required this.deliverAt,
    required this.title,
    required this.body,
  });

  /// 排程 id（文档域稳定：`ddl-lead:<videoId>` / `ddl-auto:<videoId>` /
  /// `event-lead:<eventId>`），取消与重排都按它寻址。
  final String id;

  /// 当地投递时刻（已含 09:00 或事件开始时刻口径）。
  final DateTime deliverAt;

  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is PushNotification &&
      other.id == id &&
      other.deliverAt == deliverAt &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, deliverAt, title, body);
}

/// 推送投递端口：查询权限 / 请求权限 / 安排 / 取消。实现负责把
/// [PushNotification.deliverAt] 换算成系统时区下的非精确调度。
abstract interface class SystemPushPort {
  /// 当前是否已授予通知权限；null = 系统无法回答（按未知处理，不阻塞）。
  Future<bool?> permissionGranted();

  /// 请求通知权限，返回是否授予。只在用户设置某条「提前 N 天」提醒时被
  /// 调用；被拒后 App 其余功能照常（降级为仅应用内提醒）。
  Future<bool> requestPermission();

  /// 安排（同 id 重排 = 覆盖）。非精确调度，系统可在空闲时延后。
  Future<void> schedule(PushNotification notification);

  Future<void> cancel(String id);
}

DateTime _leadDay(DateTime day, int leadDays) =>
    localDay(day).subtract(Duration(days: leadDays));

DateTime _atPushHour(DateTime localDay) =>
    DateTime(localDay.year, localDay.month, localDay.day, kPushDeliveryHour);

DateTime? _eventStartTimeOfDay(PlanEvent event) {
  final minutes = event.startTime == null
      ? null
      : tryParseHhMm(event.startTime!);
  if (minutes == null) return null;
  return DateTime(
    event.date.year,
    event.date.month,
    event.date.day,
    minutes ~/ 60,
    minutes % 60,
  );
}

/// 排程标题里的显示名（缺省空表）：`videoId → 显示名`。查不到或查到的名为空
/// 时退回内部标识 [videoId]，不产出空标题。
String _nearTargetTitle(String videoId, Map<String, String> displayNames) {
  final name = displayNames[videoId];
  return '临近目标：${name == null || name.isEmpty ? videoId : name}';
}

/// 一次同步的期望排程全集（纯件、时钟经 [now] 注入）：只含两条来源、
/// 投递时刻在 [now] 之后的条目。目标清除 / 改期 / 删除后的取消与重排由
/// [SystemPushPlanner] 对这份期望做差分得出。
///
/// [displayNames] 是 DDL 两条来源标题的显示名表（缺省空表 = 全部退回
/// [DancePlanEntry.videoId]）；随舞 / 团检事件标题不带显示名，不受它影响。
Map<String, PushNotification> planPushSchedules({
  required List<DancePlanEntry> entries,
  required List<PlanEvent> events,
  required Set<String> fullyMasteredIds,
  required DateTime now,
  Map<String, String> displayNames = const {},
}) {
  final schedules = <String, PushNotification>{};
  void put(
    String id,
    DateTime deliverAt, {
    required String title,
    required String body,
  }) {
    if (!deliverAt.isAfter(now)) return;
    schedules[id] = PushNotification(
      id: id,
      deliverAt: deliverAt,
      title: title,
      body: body,
    );
  }

  for (final entry in entries) {
    final ddl = entry.ddl;
    if (ddl == null) continue;
    final lead = ddl.leadDays;
    if (lead != null) {
      put(
        'ddl-lead:${entry.videoId}',
        _atPushHour(_leadDay(ddl.date, lead)),
        title: _nearTargetTitle(entry.videoId, displayNames),
        body: '距离设定的截止日还有 $lead 天',
      );
    }
    final settled = ddl.settlement != null;
    final remaining = planRemainingDays(dueDay: ddl.date, now: now);
    if (!settled &&
        !fullyMasteredIds.contains(entry.videoId) &&
        planIsNearDeadline(remaining)) {
      put(
        'ddl-auto:${entry.videoId}',
        _atPushHour(localDay(ddl.date)),
        title: _nearTargetTitle(entry.videoId, displayNames),
        body: '截止日临近，还没完全掌握',
      );
    }
  }
  for (final event in events) {
    final lead = event.leadDays;
    if (lead == null) continue;
    final startOfDay = _eventStartTimeOfDay(event);
    final DateTime deliverAt;
    if (startOfDay != null) {
      deliverAt = startOfDay.subtract(Duration(days: lead));
    } else {
      deliverAt = _atPushHour(_leadDay(event.date, lead));
    }
    put(
      'event-lead:${event.id}',
      deliverAt,
      title: event.type == kPlanEventTypeTeamCheck ? '团内检查临近' : '随舞临近',
      body: '距离活动还有 $lead 天',
    );
  }
  return schedules;
}

/// 推送排程协调器：每次同步对「期望排程全集」（[planPushSchedules]）与
/// 上次已同步集合做差分——新增 / 变化的安排、消失 / 变化的取消。同 id 且
/// 同内容的排程不重复调用端口。
class SystemPushPlanner {
  SystemPushPlanner(this._port);

  final SystemPushPort _port;
  Map<String, PushNotification> _synced = const {};
  bool _permissionAsked = false;

  /// 差分同步。权限被拒不阻塞：排程照常交给端口（系统侧不投递），App
  /// 其余功能照常（降级为仅应用内提醒）。[displayNames] 随每次同步传入——
  /// 改名后同名 id 的标题随之变化，差分即取消旧排程、按新名重排。
  Future<void> sync({
    required List<DancePlanEntry> entries,
    required List<PlanEvent> events,
    required Set<String> fullyMasteredIds,
    required DateTime now,
    Map<String, String> displayNames = const {},
  }) async {
    final desired = planPushSchedules(
      entries: entries,
      events: events,
      fullyMasteredIds: fullyMasteredIds,
      now: now,
      displayNames: displayNames,
    );
    for (final id in _synced.keys) {
      if (!desired.containsKey(id) || desired[id] != _synced[id]) {
        await _port.cancel(id);
      }
    }
    for (final entry in desired.entries) {
      if (_synced[entry.key] != entry.value) {
        await _port.schedule(entry.value);
      }
    }
    _synced = desired;
  }

  /// 首次设置「提前 N 天」提醒时的权限请求（每次进程至多弹一次；后续
  /// 调用直接返回当前权限状态）。
  Future<bool> ensureReminderPermission() async {
    if (_permissionAsked) {
      return await _port.permissionGranted() ?? false;
    }
    _permissionAsked = true;
    return _port.requestPermission();
  }
}
