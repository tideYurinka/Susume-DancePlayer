part of 'overlay.dart';

/// 浮层几何存取实现：读当前持久化几何、写几何、订阅恢复流。
abstract interface class OverlayGeometryStore {
  /// 读当前持久化几何（null = 未自定义）。
  OverlayPlacements? read();

  /// 写几何（null = 清除自定义，回落宿主默认位）。
  void write(OverlayPlacements? value);

  /// 订阅持久化面的恢复流（持久化恢复 → 几何消费方）；实现可静默不订阅，
  /// 此时恢复流恒空。
  void listen(
    void Function(OverlayPlacements? value) onChanged, {
    required bool fireImmediately,
  });
}
