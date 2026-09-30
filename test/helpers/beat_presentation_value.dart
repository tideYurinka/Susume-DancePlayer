// 测试助手：按既有纯函数入参构造节拍呈现的
// 发布值——widget seam 用例的输入构造器，期望值（数字、游标位置、颜色）
// 仍由各用例独立书写。
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';
import 'package:dance_learning_app/player/beat_animation.dart';
import 'package:dance_learning_app/player/beat_presentation.dart';
import 'package:dance_learning_app/player/metronome_source_registry.dart';

BeatPresentationValue presentationValueFor({
  required BeatGrid grid,
  required Duration position,
  BeatPhase? phase,
  List<Duration> halfBeatLines = const [],
  bool halfBeatEnabled = true,
  bool gridError = false,
  Duration? recordingAnchor,
  Duration? delayAnchor,
  Duration? activeAnchor,
  List<Duration> segmentLines = const [],
  Duration firstLine = Duration.zero,
}) {
  final value = evaluatePresentationValue(
    context: BeatPresentationContext(
      grid: grid,
      phase: phase ?? BeatPhase(grid: grid),
      recordingAnchor: recordingAnchor,
      delayAnchor: delayAnchor,
      activeAnchor: activeAnchor,
      segmentLines: segmentLines,
      firstLine: firstLine,
      source: metronomeSourceEntryOfId(kNormalSourceId),
      slotVolumeOf: (slot) => 1.0,
      halfBeatLines: halfBeatLines,
      halfBeatEnabled: halfBeatEnabled,
      avSyncDelayMs: 0,
      rate: 1,
      playing: true,
      soundEnabled: true,
      gridError: gridError,
      sessionActive: false,
    ),
    position: position,
  );
  if (value == null) {
    throw ArgumentError('该入参无发布值（无锚可数或网格异常）');
  }
  return value;
}
