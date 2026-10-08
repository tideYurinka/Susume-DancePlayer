/// 「接收端上报的播放状态 → 回前台要做的那一件事」的**穷尽映射**（票 #41）。
///
/// 回前台时投屏运行域问一次接收端「现在什么状态」，再按本表续上本机界面。
/// **接收端是权威**：本机不自己记「刚才是不是我按的暂停」，也不拿退后台那一刻
/// 的旧状态去猜——一次网络往返问回来的那一个取值决定这一次做什么。
///
/// 三条纪律：
///
/// - **逐值一位，不留零处理分支**：本文件用**穷尽 `switch` 表达式**取道
///   （不是 `Map` ——漏行只能靠测试兜），新增一个接收端状态取值即编译报错；
///   `test/cast/cast_playback_follow_test.dart` 再逐值钉住「报什么续什么」。
/// - **不做兜底成一条**：暂停与仍在播各是一件事（票 #41 的正是「paused 一支
///   不留空操作」），只有「过渡中 / 问不到」才是真的「不猜、一位不动」。
/// - **纯件**：不读 provider、不碰会话与内核；译文怎么落地由投屏运行域
///   （`player/cast_run.dart`）负责。
library;

import 'cast_session.dart' show CastPlaybackState;

/// 接收端上报状态 → 回前台那件事。
enum CastPlaybackFollow {
  /// 接收端**在播**：本机界面同步为播放态。**不重推接收端**——它已经在播，
  /// 这一趟只把本机追上去。
  syncPlaying,

  /// 接收端**暂停**：本机界面同步为暂停态，**不自动抢播**——要复播由用户按
  /// （电视是自己停在那一帧等着的，本机替它决定复播就是把界面骗到与电视不同）。
  syncPaused,

  /// 接收端**已停 / 片子被卸**：走既有失败收口（断开 + 停服 + 回编辑态 +
  /// 短暂提示）——与遥控失败、退后台按不停同一条收场，不另开第二条失败路径。
  failSession,

  /// **过渡中 / 问不到**：一位不动。设备正在换状态时不猜；问不到（设备没报
  /// 或报了个我们不认识的词）同样不猜——按「探测不到一律按不显示处理」的同一
  /// 口径静默降级，不拿一次问话把投屏整条收掉。
  hold,
}

/// 取道：接收端上报状态 → 那件事。**穷尽 `switch`**：加取值即编译期报错。
CastPlaybackFollow castPlaybackFollowOf(CastPlaybackState state) =>
    switch (state) {
      CastPlaybackState.playing => CastPlaybackFollow.syncPlaying,
      CastPlaybackState.paused => CastPlaybackFollow.syncPaused,
      CastPlaybackState.stopped => CastPlaybackFollow.failSession,
      CastPlaybackState.noMedia => CastPlaybackFollow.failSession,
      CastPlaybackState.transitioning => CastPlaybackFollow.hold,
      CastPlaybackState.unknown => CastPlaybackFollow.hold,
    };
