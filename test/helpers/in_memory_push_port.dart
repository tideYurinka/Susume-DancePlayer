import 'package:dance_learning_app/plan/system_push.dart';

/// 推送端口的内存替身（推送端口 seam）：记录安排与
/// 取消调用，权限行为可脚本化。
class InMemoryPushPort implements SystemPushPort {
  final Map<String, PushNotification> scheduled = {};
  final List<String> cancelled = [];
  int scheduleCalls = 0;
  int requestPermissionCalls = 0;
  bool? permissionGrantedResult;
  bool requestPermissionResult = true;

  @override
  Future<bool?> permissionGranted() async => permissionGrantedResult;

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    return requestPermissionResult;
  }

  @override
  Future<void> schedule(PushNotification notification) async {
    scheduleCalls++;
    scheduled[notification.id] = notification;
  }

  @override
  Future<void> cancel(String id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}
