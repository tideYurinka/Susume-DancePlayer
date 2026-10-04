/// 八拍矫正：可用性与预览位置的
/// 强拍谓词。全部为会话级内存态，不落盘；锚点数据本体在公开 beat 段
/// （见 `marker_document.dart` 与 `beat_track_state.dart`）。
///
/// 契约：[beatCorrectionAvailableProvider] 是入口
/// 与落锚工具的共同置灰门；[previewDownbeatProvider] /
/// [previewAnchorOccupiedProvider] / [hasEightBeatAnchorsProvider] 是待命态
/// 工具可用性谓词。
///
/// 依赖方向（单向）：只依赖 beat_track_state 小库、共享内核接缝与标注落点
/// 纯函数，零 import 中枢；反向不可。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/downbeat_snap.dart'
    show DownbeatLanding, resolveDownbeatLanding;
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatPhaseProvider;
import '../core/beat_grid.dart' show BeatGridReads;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;

/// 八拍矫正可用（真实拍点可用**且有强拍**）：就绪门读
/// [BeatGridReads.hasRealBeats]，强拍存在性读
/// [BeatGridReads.hasStrongBeats]——入口按钮与待命态落锚工具的共同置灰门：
/// 占位（分析中/未开始）与异常
///（无节拍数据）置灰不可用；就绪但网格**无强拍**（识别退化）同样置灰：
/// 锚点只能落在强拍上，无强拍即无合法落点、修正无意义（只收强拍）。
final beatCorrectionAvailableProvider = Provider<bool>((ref) {
  final grid = ref.watch(beatGridProvider);
  return grid.hasRealBeats && grid.hasStrongBeats;
});

/// 预览位置（播放头/预览线）就近的**强拍落点**；无就绪网格或无强拍返回
/// null。解析缝 = `annotation/downbeat_snap.dart` 的 [resolveDownbeatLanding]
/// ——与模块内落锚落点解析**同一纯函数**（时刻与拍序号同源给出，widget 不
/// 自行从时刻反查序号；落点解析规则收进纯域/模块，widget 只读）。
final previewDownbeatProvider = Provider<DownbeatLanding?>((ref) {
  if (!ref.watch(beatGridProvider).hasRealBeats) return null;
  final engine = ref.watch(playbackEngineProvider);
  final position = ref.watch(playbackPositionProvider).value ?? engine.position;
  return resolveDownbeatLanding(position, grid: ref.watch(beatGridProvider));
});

/// 预览位置**已有八拍锚点**（待命态「添加八拍线」置灰谓词；
/// 「删除八拍线」与本谓词同一份互斥置灰来源——预览位置无锚点才能加、
/// 已有锚点才能删）。
final previewAnchorOccupiedProvider = Provider<bool>((ref) {
  final downbeat = ref.watch(previewDownbeatProvider);
  if (downbeat == null) return false;
  return ref.watch(beatPhaseProvider).anchors.contains(downbeat.beatIndex);
});

/// **已有任意八拍锚点**（待命态「清除所有锚点」的可用谓词）：
/// 无锚点即置灰（不会点了没反应）。读面 = 相位源的
/// 规范化锚点集合（与落锚/删锚同一来源；占位/异常无 beat 段恒空 → 置灰）。
final hasEightBeatAnchorsProvider = Provider<bool>((ref) {
  return ref.watch(beatPhaseProvider).anchors.isNotEmpty;
});
