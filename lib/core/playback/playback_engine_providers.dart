/// 播放内核注入点：中立 home（core/playback），hub 与标注
/// 编辑模块库共同 import——生产环境默认 media_kit 适配器；测试用
/// FakeEngine 覆盖（`overrideWithValue`），见
/// `test/helpers/fake_playback_engine.dart`。
///
/// ProviderScope 销毁时释放内核资源（[PlaybackEngine.dispose]）。
///
/// 依赖方向（单向）：只依赖 flutter_riverpod 与同目录内核实现，零 import
/// player 侧中枢或域模块；反向不可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'media_kit_playback_engine.dart';
import 'playback_engine.dart';

final playbackEngineProvider = Provider<PlaybackEngine>((ref) {
  final engine = MediaKitPlaybackEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// position 流：播放期间持续发出当前播放位置（widget 可直接 watch）。
///
/// 播放内核位置的纯派生读取面，随 [playbackEngineProvider] 同住中立 home；
/// 消费方（控制层、轨道带、播放页、节拍矫正预览位）单向依赖本库。
final playbackPositionProvider = StreamProvider<Duration>((ref) {
  return ref.watch(playbackEngineProvider).positionStream;
});

/// 播放完成事件流（边沿事件）：转发内核的 `completedStream`，属内核面。
final playbackCompletedStreamProvider = Provider<Stream<void>>((ref) {
  return ref.watch(playbackEngineProvider).completedStream;
});
