import 'package:dance_learning_app/cast/system_mirror.dart';

/// 脚本化的假系统镜像跳转：记录被调用的次数与**被调用的那一刻**（顺序类
/// 用例的观测点——`onOpen` 里回看投屏会话与递出通道是否已收干净），并可按
/// 需给出「两级设置都没接住」这一态（调用方据此给短暂提示）。
/// 照 `fake_cast_delivery_channel.dart` 的既有范式。
class FakeSystemMirrorLauncher implements SystemMirrorLauncher {
  FakeSystemMirrorLauncher({this.opened = true});

  /// [open] 的返回值：false = 系统投屏设置与显示设置都没接住。
  bool opened;

  /// [open] 的调用次数。
  int openCalls = 0;

  /// [open] 被调用的那一刻回调（顺序类用例在此回看投屏侧的状态）。
  void Function()? onOpen;

  @override
  Future<bool> open() async {
    openCalls++;
    onOpen?.call();
    return opened;
  }
}
