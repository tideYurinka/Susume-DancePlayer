import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart';
import 'package:timezone/timezone.dart' as tz;

import 'system_push.dart';

/// 真机端口：`flutter_local_notifications` + `timezone`。全部走
/// 非精确调度（[AndroidScheduleMode.inexact]），不申请精确闹钟权限；插件
/// 不可用 / 平台通道失败时静默降级（权限按未知、安排与取消吞掉异常），
/// App 其余功能照常（降级为仅应用内提醒）。
class LocalNotificationPushPort implements SystemPushPort {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      initializeTimeZones();
      final granted = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = granted != false;
    } on Object {
      return false;
    }
    return _initialized;
  }

  /// 排程 id 的 32 位数值化（插件侧通知 id 必须是 int）。用 FNV-1a 内容
  /// 映射而不用 `String.hashCode`：后者不保证跨进程 / 跨编译稳定，重启后
  /// 同一 id 必须映射到同一数值，取消与重排才能寻址到旧通知。
  int _numericId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  tz.TZDateTime _tz(DateTime localTime) =>
      tz.TZDateTime.from(localTime, tz.local);

  @override
  Future<bool?> permissionGranted() async {
    if (!await _ensureInitialized()) return null;
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.areNotificationsEnabled();
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _ensureInitialized()) return false;
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      return granted ?? false;
    } on Object {
      return false;
    }
  }

  @override
  Future<void> schedule(PushNotification notification) async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.zonedSchedule(
        id: _numericId(notification.id),
        title: notification.title,
        body: notification.body,
        scheduledDate: _tz(notification.deliverAt),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'plan_push',
            '练舞计划提醒',
            channelDescription: 'DDL、团内检查与随舞事件的系统提醒',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexact,
      );
    } on Object {
      // 非精确调度 / 插件失败都降级为不投递，不阻塞其余功能。
    }
  }

  @override
  Future<void> cancel(String id) async {
    if (!await _ensureInitialized()) return;
    try {
      await _plugin.cancel(id: _numericId(id));
    } on Object {
      // 同上：降级。
    }
  }
}
