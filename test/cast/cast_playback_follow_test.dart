import 'package:dance_learning_app/cast/cast_playback_follow.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「接收端上报状态 → 回前台那件事」的穷尽映射直测（纯件，不启动 widget、
/// 不跑进程）：每个取值都要有一位（票 #41 的验收第 2 条「不留零处理分支」），
/// 取值增删时这里与 `castPlaybackFollowOf` 的穷尽 switch 一起断。
void main() {
  // 逐值一位：接收端报什么，本机回来时做什么。
  const expected = <CastPlaybackState, CastPlaybackFollow>{
    // 还在播：本机界面追成播放态（接收端已经在播，不重推它）。
    CastPlaybackState.playing: CastPlaybackFollow.syncPlaying,
    // 暂停：本机界面追成暂停态，**不自动抢播**。
    CastPlaybackState.paused: CastPlaybackFollow.syncPaused,
    // 已停 / 片子被卸：走既有失败收口（断开 + 回编辑态 + 短暂提示）。
    CastPlaybackState.stopped: CastPlaybackFollow.failSession,
    CastPlaybackState.noMedia: CastPlaybackFollow.failSession,
    // 过渡中 / 问不到：不猜，一位不动。
    CastPlaybackState.transitioning: CastPlaybackFollow.hold,
    CastPlaybackState.unknown: CastPlaybackFollow.hold,
  };

  test('接收端每个上报取值都有一位（行数与取值数相等）', () {
    expect(
      expected.length,
      CastPlaybackState.values.length,
      reason: '新增上报取值要在本表与 castPlaybackFollowOf 各补一位',
    );
    expect(
      expected.keys.toSet(),
      CastPlaybackState.values.toSet(),
      reason: '逐值一位，不重不漏',
    );
  });

  test('逐值取道：报什么就续什么', () {
    for (final state in CastPlaybackState.values) {
      expect(castPlaybackFollowOf(state), expected[state], reason: '$state');
    }
  });

  test('三种「续上」互不混同：播放 / 暂停 / 失败各是一位，不是兜底', () {
    // 反向钉住「不是所有非停止取值都落到同一个兜底」：paused 与 playing
    // 必须各自有位（票 #41 的正是「paused 一支不留空操作」）。
    expect(
      castPlaybackFollowOf(CastPlaybackState.paused),
      isNot(castPlaybackFollowOf(CastPlaybackState.playing)),
    );
    expect(
      castPlaybackFollowOf(CastPlaybackState.paused),
      isNot(CastPlaybackFollow.hold),
    );
  });
}
