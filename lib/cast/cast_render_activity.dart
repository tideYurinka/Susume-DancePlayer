/// **投屏渲染进行中**这个事实的注入点。
///
/// 它是投屏态的「渲染进行中」门（票 #35）读的那个事实：另一次**投屏渲染**
/// 还在跑（当前倍速档起渲、或投屏态里后台渲其余倍速档）——此时起投会与它
/// 抢同一条渲染链，入口置灰、按下去只解释原因。渲染编排域（渲染执行器与
/// 准备面板那条链）在起渲时 [CastRenderActivity.begin]、收工（成功、失败、
/// 取消都算）时 [CastRenderActivity.end]，本域不猜。
///
/// 缺省 false = 没有在飞的渲染。本接缝只承载这一位事实，不认识渲染执行器、
/// 命令参数与进度——那些归渲染编排域。今天没有任何生产写入方（渲染链尚未
/// 落地）：置灰分支因此永远走不到，但它的行为已被
/// `test/player/cast_entry_gate_test.dart` 与 `cast_mode_test.dart` 逐条钉住。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 渲染活动事实：一对开合入口（与装载门 `LoadGateModel.begin/settle` 同形）。
class CastRenderActivity extends Notifier<bool> {
  @override
  bool build() => false;

  /// 起渲：有渲染在飞。
  void begin() => state = true;

  /// 收工：成功、失败、取消都算，回「没有在飞的渲染」。
  void end() => state = false;
}

/// 投屏渲染活动事实的注入点。
final castRenderInProgressProvider = NotifierProvider<CastRenderActivity, bool>(
  CastRenderActivity.new,
);
