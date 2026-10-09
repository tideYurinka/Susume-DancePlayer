/// 投屏本地预览（画面开关）域：投屏态画面区那只看画面、不发声的**兄弟播放**。
///
/// ## 它是什么
///
/// 投屏态的画面区默认**黑底 + 一行指路提示**（源片不上屏——电视上那份才是正
/// 的）；顶栏那枚**画面开关**打开后切到**静音本地预览**：
///
/// - **兄弟内核**：预览跑在[castPreviewEngineProvider]给出的**第二只播放内核**
///   上，与主内核（源侧播放、遥控镜像那条路）并列。两只互不驱动——播放控件
///   遥控电视、不反向驱动预览，预览的播放态也不驱动控件；
/// - **静音起播**：预览内核打开即 [PlaybackEngine.setMuted] 为真（声音归电视，
///   手机这边出声就是回声）；
/// - **起播位置 = 接收端上报位置**：开关打开那一刻问一次投屏会话要当前位置，
///   定位过去再播——预览对的是电视上正在放的那一帧。设备这一问答不上来就
///   从头起（静默降级，不拿一次探测把投屏整条收掉）；没有「对齐」之类的
///   第二个动作；
/// - **只在投屏态内**：离开投屏态（断开 / 换视频 / 离开播放页都经既有复位）
///   即收起并停住——触发点与投屏运行域同一处边沿（只听「离开投屏态」）。
///
/// ## 边界
///
/// 本域不构控件（画面件归 `cast_picture_area.dart`），不读构建上下文；投屏
/// 会话与递出通道仍归投屏运行域（本域只经 [CastRunModel.reportedPosition] 问
/// 位置，不持有会话）。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/media_kit_playback_engine.dart';
import '../core/playback/playback_engine.dart';
import '../player_session/player_session.dart';
import 'cast_run.dart' show castRunProvider;

/// 投屏本地预览的播放内核：与主内核（`playbackEngineProvider`）**并列的兄弟
/// 实例**，同一接缝、独立生命周期。懒建——画面开关从没打开过就不建实例
/// （与练习片段回放的 `practiceClipEngineProvider` 同款手法）。ProviderScope
/// 销毁时释放内核资源。
///
/// **它不自己持屏幕唤醒**（`holdsScreenAwake: false`）：投屏期那一次常亮由
/// 投屏侧**单持**（`lib/cast/cast_screen_awake.dart`，票 #39）。两处都持的话，
/// 画面开关一开一关、预览播完，画面件那次释放会打在同一处平台开关上，把投屏
/// 期该有的常亮一并关掉——「不重复持有、不打架」正是这一条。
final castPreviewEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = MediaKitPlaybackEngine(holdsScreenAwake: false);
  ref.onDispose(engine.dispose);
  return engine;
});

/// 画面开关状态：false = 黑底 + 指路提示，true = 静音本地预览。
///
/// 状态与播放动作收在一处（[CastPreviewModel]）：顶栏那枚槽读它取激活位，
/// 画面区读它决定画什么。
class CastPreviewModel extends Notifier<bool> {
  /// 在途意图代际号：收起 / 离开投屏态 / 再开一次都会作废在途的打开动作，
  /// 迟到的 `open`/`play` 不会把已经收起的面又点亮。
  int _generation = 0;

  @override
  bool build() {
    // 离开投屏态即收预览：与投屏运行域同一处边沿（断开 / 换视频 / 离开播放页
    // 都经 [PlayerSessionModel.reset]）。
    ref.listen(playerSessionProvider, (previous, next) {
      final wasCasting = previous?.isCast ?? false;
      if (wasCasting && !next.isCast) unawaited(_stop());
    });
    return false;
  }

  /// 打开画面开关：问一次接收端当前位置 → 静音起播。没在投屏（或期间断开）
  /// 即不起——开关只在投屏态顶栏在场。起不来（源读不出等）就回黑底 + 指路
  /// 提示，**不把异常抛给点按那一下**（投屏本身照旧）。
  Future<void> show({required Uri source}) async {
    if (state) return;
    final cast = ref.read(castRunProvider.notifier);
    if (cast.receiver == null) return;
    final generation = ++_generation;
    final position = await cast.reportedPosition();
    if (generation != _generation || cast.receiver == null) return;
    final engine = ref.read(castPreviewEngineProvider);
    try {
      await engine.setMuted(true);
      await engine.open(source);
      await engine.seek(position ?? Duration.zero);
      await engine.play();
    } on Object {
      state = false;
      return;
    }
    if (generation != _generation) {
      await _pauseQuietly(engine);
      return;
    }
    state = true;
  }

  /// 切换画面开关：开 ↔ 关。顶栏那枚工具与画面区读的是同一份状态。
  Future<void> toggle({required Uri source}) =>
      state ? hide() : show(source: source);

  /// 收起画面开关：停住预览（黑底 + 指路提示回来），不动主内核那边。
  Future<void> hide() async {
    if (!state) return;
    _generation++;
    state = false;
    await _pauseQuietly(ref.read(castPreviewEngineProvider));
  }

  /// 离开投屏态：无论开关开着还是在途打开，都停住。
  Future<void> _stop() async {
    final wasOpen = state;
    _generation++;
    state = false;
    if (wasOpen) await _pauseQuietly(ref.read(castPreviewEngineProvider));
  }

  /// 停预览：收尾失败不阻断收起（开关与画面面已经翻过去了——与投屏侧的
  /// 「收尾不再抛」同一口径）。
  Future<void> _pauseQuietly(PlaybackEngine engine) async {
    try {
      await engine.pause();
    } on Object {
      // 停不下来的预览不阻断收起；它下一帧就被移出画面树。
    }
  }
}

/// 画面开关注入点（唯一实例）。
final castPreviewProvider = NotifierProvider<CastPreviewModel, bool>(
  CastPreviewModel.new,
);
