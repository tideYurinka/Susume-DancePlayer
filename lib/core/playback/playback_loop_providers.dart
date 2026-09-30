/// 循环层注入点（provider 随域归属）。
///
/// 循环层（区间/学习段循环与前导）是播放内核**之上**的薄层，故与内核注入点
/// [playbackEngineProvider]（`playback_engine_providers.dart`）分住两库——
/// 那个中立 home 的语义是「播放内核本身」，不被内核之上的薄层冲淡。
///
/// 依赖方向（单向）：只依赖 flutter_riverpod 与同目录循环层实现、内核注入
/// 点，零 import player 侧中枢或域模块；反向不可。
library;

import 'dart:async' show unawaited;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'playback_engine_providers.dart';
import 'playback_loop_layer.dart';

/// 学习段/AB 区间循环薄层（同一播放内核接缝，由激活段驱动）。
final playbackLoopLayerProvider = Provider<PlaybackLoopLayer>((ref) {
  final layer = PlaybackLoopLayer(ref.watch(playbackEngineProvider));
  ref.onDispose(() {
    unawaited(layer.dispose());
  });
  return layer;
});

/// 学习段循环遍数事件源（倍速步进消费）。
final learningSegmentLoopCountStreamProvider = Provider<Stream<int>>((ref) {
  return ref.watch(playbackLoopLayerProvider).loopCountStream;
});
