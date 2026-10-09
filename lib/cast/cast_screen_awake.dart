/// **投屏期的屏幕唤醒**接缝（票 #39）：投屏这一段时间里让这一屏保持常亮。
///
/// ## 为什么是投屏侧自己持
///
/// 本仓唯一的屏幕常亮来自播放内核的画面件：media_kit_video 的 `Video` 控件
/// 内部持一个**引用计数式**的唤醒
/// （`media_kit_video/src/utils/wakelock.dart` 的 `Wakelock`，经
/// `wakelock_plus` 落到平台）。投屏态的画面区被投屏画面覆盖件换掉——连源画面
/// 件都不挂（见 `player/picture_layer.dart` 的 `PictureLayerInput.pictureOverride`），
/// 于是投屏态一个唤醒持有者都没有，屏幕照常熄灭。
///
/// **内核不能独立于画面件持唤醒**（这一票先探明的结论）：那份唤醒是画面件
/// State 自己的——类没有从 `package:media_kit_video/media_kit_video.dart`
/// 导出（import 它的 `src/` 是实现细节、也不被静态检查放行），计数住在它内部；
/// `PlaybackEngine` 接缝上没有唤醒这一面；mpv 的 `stop-screensaver` 也没接到
/// Android 的 `FLAG_KEEP_SCREEN_ON` 上（它管的是 X11 / Wayland / cocoa 那几
/// 套屏保）。故本票取**在投屏态进出边沿自持**：本接缝就是那份唤醒的持有者。
///
/// ## 进出各只有一处
///
/// [hold] 在进投屏态那一下（`player/cast_run.dart` 起投成功、状态翻成
/// 「正投某台接收端」那一行），[release] 与投屏会话的**既有复位一处**同一处
/// （同一文件的 `_teardown`：断开 / 换视频 / 离开播放页 / 起投失败的零残留
/// 都经它）——不在断开、换视频、离开页面各写一遍。
///
/// 另有一处**帧末的再确认**（[reassert]，投屏态画面区挂载时叫一次）：起投那
/// 一刻持有的唤醒会被**退场的源画面件**踩掉——它在投屏态入场那一帧收尾时才
/// dispose，dispose 时放开自己那份唤醒，打的是**同一个**平台开关（那个开关
/// 不是引用计数的）。这不是第二个持有者，也不动计数，只是把同一份持有在正确
/// 的时机重新按一遍；理由与顺序见 [reassert] 的注释。
///
/// ## 计数语义与画面件一致
///
/// [hold] / [release] 是**引用计数**式（与画面件那份 `Wakelock` 同款）：重复
/// [hold] 只真的拿一次；[release] 只在计数归零那一刻才真的放开；一份都没持
/// 时的 [release] 是空操作——**绝不因为一次多余的释放把别的持有者（画面件）
/// 的唤醒关掉**。真实现见 `wakelock_cast_screen_awake.dart`（[wakelockScreenAwakeToggle]），
/// 它与画面件用的是**同一条**平台能力。
///
/// ## 不引前台服务、不延长投屏的寿命
///
/// 唤醒只在投屏会话活着时持有：会话与递出通道同寿命（都随既有复位一处收），
/// 屏幕常亮不构成让投屏比播放页活得久的理由。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'wakelock_cast_screen_awake.dart';

/// 投屏期屏幕唤醒接缝。测试注入记录拿 / 放次数的脚本化替身
/// （`test/helpers/fake_cast_screen_awake.dart`）。
abstract interface class CastScreenAwake {
  /// 拿一次唤醒：第一次真的持有（屏幕常亮），重复调用是空操作。
  ///
  /// **不抛**：平台没有这门能力（非 Android 宿主、插件不在）时静默降级、
  /// 投屏照旧——一次拿不到唤醒不该把投屏挡下来（与画面件那份唤醒同款）。
  Future<void> hold();

  /// 放一次唤醒：计数归零才真的放开（恢复系统行为）；未持有时是空操作。
  ///
  /// **不抛**（同 [hold]）：收尾那一下不能被一次失败的释放挡住。
  Future<void> release();

  /// **再确认一次**此刻的持有：持有着的话就再打一次平台的「开」。
  ///
  /// 为什么需要它（实测出来的顺序问题，不是补充功能）：投屏态的画面区是在
  /// **源画面件退场那一帧**接管的，而那个画面件在同一帧**收尾**时才真的
  /// dispose——它 dispose 时会放开自己那份唤醒（media_kit 画面件内部那份
  /// `Wakelock`，打的是**同一个**平台开关，而那个开关**不是引用计数的**）。
  /// 于是「起投那一刻持的唤醒」会被它踩掉：屏幕照旧会熄。平台开关既然不是
  /// 引用计数的，唯一稳的时机就是**源画面件退场之后再确认一次**（投屏态画面
  /// 件挂上那一帧的帧末，见 `player/cast_picture_area.dart`）。
  ///
  /// 这与 [hold] 不是一回事：[hold] 是**计数 +1**（第二次不再打平台），
  /// [reassert] 是**再打一次平台的开**（只在计数 > 0 时；计数为 0 时是空操作
  /// ——那说明唤醒本来就该是放开的）。它不新增持有者：持有者仍只有投屏运行域
  /// 一处，[reassert] 只是把同一份持有重新按一遍。
  Future<void> reassert();
}

/// 唤醒的**计数语义**：与画面件那份 `Wakelock` 同款。
///
/// [toggle] 是真的落到平台的那一下（true = 持有、false = 放开）；本类把
/// 「现在有几份在持」收成一份计数——重复持有只开一次、计数归零才关。生产
/// 装配给的 [toggle] 是 `wakelock_plus`（[wakelockScreenAwakeToggle]），测试
/// 注入一个记录调用的替身，于是「重复持有只拿一次」是可断言的。
class RefCountedCastScreenAwake implements CastScreenAwake {
  RefCountedCastScreenAwake(this._toggle);

  final Future<void> Function(bool on) _toggle;

  int _count = 0;

  /// 现在有几份持有（读数，供测试与排查；界面不读它）。
  int get count => _count;

  @override
  Future<void> hold() async {
    _count++;
    if (_count > 1) return;
    await _toggle(true);
  }

  @override
  Future<void> release() async {
    if (_count == 0) return;
    _count--;
    if (_count > 0) return;
    await _toggle(false);
  }

  @override
  Future<void> reassert() async {
    // 计数为 0 = 这一刻本来就不该常亮（持有者已经离开），别凭空开一次。
    if (_count == 0) return;
    await _toggle(true);
  }
}

/// 唤醒接缝的注入点：真实实现就是 [RefCountedCastScreenAwake] 配上
/// `wakelock_plus` 那一下（与画面件那份唤醒同一条平台能力）；测试 override
/// 注入脚本化替身。
final castScreenAwakeProvider = Provider<CastScreenAwake>(
  (ref) => RefCountedCastScreenAwake(wakelockScreenAwakeToggle),
);
