import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **屏幕朝向**（App 请求的屏幕朝向）：转屏钮动作回调的目标取值。
///
/// 与既有两词严格区分：**显示朝向**（画面在屏幕上横还是竖）与**画面方向**
/// （镜像合成）；本值只表达「App 请求屏幕转为竖屏 / 横屏」。
enum ScreenOrientation {
  /// 竖屏（`[portraitUp]`，绝对）。
  portrait,

  /// 横屏（`[landscapeLeft, landscapeRight]`，两侧都允许）。
  landscape,
}

/// 系统 UI / 方向控制（可注入，widget 测试断言用）。
///
/// 播放器页进入/退出时切换系统 UI 状态；真实实现走 [SystemChrome]，
/// 测试注入 fake 记录调用。
abstract interface class SystemUiController {
  /// 进入播放器模式：沉浸式系统 UI + 允许全方向（随设备自动旋转）。
  Future<void> enterPlayerMode();

  /// 锁竖屏（全局竖屏锁）。
  ///
  /// 译成 `SCREEN_ORIENTATION_PORTRAIT`：绝对，App 说了算，不受系统
  /// 「自动旋转」开关影响。**不改系统 UI 模式**——App 启动与非播放器
  /// 页面都走它，那里不得进入沉浸。
  Future<void> lockPortrait();

  /// 锁定横屏（转屏钮「转为横屏」）。译成两侧都允许的
  /// `SCREEN_ORIENTATION_USER_LANDSCAPE`。
  ///
  /// **粘性**：请求发出后本页内不再请求跟随，物理旋转不再改变屏幕朝向；
  /// 收起控制层不解除锁定（收起不再有任何方向副作用）。
  Future<void> lockLandscape();

  /// 退出播放器模式：恢复系统 UI（edgeToEdge）+ 落回全局竖屏锁。
  Future<void> restoreDefaultUi();
}

/// 真实实现：[SystemChrome]。
class SystemChromeSystemUiController implements SystemUiController {
  const SystemChromeSystemUiController();

  @override
  Future<void> enterPlayerMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 显式允许所有方向：不锁定竖屏，横竖屏自动旋转。
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  @override
  Future<void> lockPortrait() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
  }

  @override
  Future<void> lockLandscape() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  Future<void> restoreDefaultUi() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // 退出播放器落回全局竖屏锁：首页、统计、计划等后续页面一律竖屏。
    await lockPortrait();
  }
}

/// 系统 UI/方向控制（沉浸模式、自动旋转）：测试注入 fake 断言调用。
final systemUiControllerProvider = Provider<SystemUiController>(
  (ref) => const SystemChromeSystemUiController(),
);
