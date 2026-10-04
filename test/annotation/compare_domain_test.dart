/// 对比练习纯域模块直测：素材与片段
///（`compare_materials.dart`）概念面的纯函数/值对象行为——零框架依赖、
/// 不启动 widget 环境。取景纯域直测在 `framing_selection_test.dart`
///（取景只剩取景选区一条数学）。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart';

MaterialRecord _material({
  String id = 'm1',
  int durationMs = 10000,
  int sourceStartMs = 60000,
}) => MaterialRecord(
  id: id,
  videoId: 'v1',
  createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
  durationMs: durationMs,
  sourceStartMs: sourceStartMs,
  fileName: 'take.mp4',
  sizeBytes: 1,
);

PracticeClip _clip(
  String id, {
  required int sourceStart,
  required int sourceEnd,
  String materialId = 'm1',
  int materialSourceStart = 60000,
}) => PracticeClip(
  id: id,
  materialId: materialId,
  materialSourceStartMs: materialSourceStart,
  inMs: sourceStart - materialSourceStart,
  outMs: sourceEnd - materialSourceStart,
);

/// 有界真实网格（120bpm 均匀节奏、301 拍），八拍点每 8 拍一个。
final _realGrid = _TestGrid(lastBeatIndex: 300);

/// 异常网格（无任何强拍 → 无八拍点）。
final _abnormalGrid = _TestGrid(lastBeatIndex: 9, hasDownbeats: false);

class _TestGrid implements BeatGrid {
  // 性质表态：本 fake 模拟就绪真实网格。
  @override
  BeatGridNature get nature => BeatGridNature.ready;

  _TestGrid({required this.lastBeatIndex, this.hasDownbeats = true});

  @override
  final int? lastBeatIndex;

  final bool hasDownbeats;

  @override
  int get beatsPerBar => 4;

  @override
  Duration beatTime(int index) => Duration(milliseconds: index * 500); // 120bpm

  @override
  int beatIndexAt(Duration time) => time.inMilliseconds ~/ 500;

  @override
  bool isDownbeat(int index) => hasDownbeats && index % beatsPerBar == 0;

  @override
  int get firstDownbeatIndex => 0;

  @override
  Duration beatsDuration(int count, {int from = 0}) =>
      beatTime(from + count) - beatTime(from);

  @override
  List<Duration> beatsInWindow(Duration start, Duration end) => [
    for (var i = beatIndexAt(start); i <= beatIndexAt(end); i++) beatTime(i),
  ];
}

void main() {
  group('素材记录值对象', () {
    test('字段齐全、相等按字段声明', () {
      expect(_material(), equals(_material()));
      expect(_material(id: 'm2'), isNot(equals(_material())));
    });

    test('录制完成即建 1:1 在轨片段（截取范围 = 素材全长）', () {
      final material = _material(durationMs: 8000, sourceStartMs: 60000);
      final clip = PracticeClip.fullLength(id: 'c1', material: material);
      expect(clip.inMs, 0);
      expect(clip.outMs, 8000);
      expect(clip.sourceStartMs, 60000);
      expect(clip.sourceEndMs, 68000);
    });
  });

  group('重叠清理（只作用于轨道引用）', () {
    test('完全覆盖 → 旧引用删除', () {
      final clips = [_clip('a', sourceStart: 61000, sourceEnd: 62000)];
      final kept = pruneClipsOverlappedBy(
        clips,
        const IntervalSpan(startMs: 60000, endMs: 63000),
      );
      expect(kept, isEmpty);
    });

    test('部分重叠 → 裁到不重叠（左悬裁右端、右悬裁左端）', () {
      final clips = [
        _clip('head', sourceStart: 60000, sourceEnd: 62000),
        _clip('tail', sourceStart: 64000, sourceEnd: 66000),
        _clip('clean', sourceStart: 70000, sourceEnd: 71000),
      ];
      final kept = pruneClipsOverlappedBy(
        clips,
        const IntervalSpan(startMs: 61000, endMs: 65000),
      );
      expect(kept.map((c) => c.id).toList(), ['head', 'tail', 'clean']);
      expect(kept[0].sourceStartMs, 60000);
      expect(kept[0].sourceEndMs, 61000);
      expect(kept[1].sourceStartMs, 65000);
      expect(kept[1].sourceEndMs, 66000);
      expect(kept[2].sourceStartMs, 70000);
      expect(kept[2].sourceEndMs, 71000);
    });

    test('无重叠 → 原样保留', () {
      final clips = [_clip('a', sourceStart: 60000, sourceEnd: 61000)];
      final kept = pruneClipsOverlappedBy(
        clips,
        const IntervalSpan(startMs: 62000, endMs: 63000),
      );
      expect(kept.single.sourceStartMs, 60000);
      expect(kept.single.sourceEndMs, 61000);
    });

    test('新片段完全落入旧引用（无法裁成单一不重叠区间）→ 旧引用删除', () {
      final clips = [_clip('a', sourceStart: 60000, sourceEnd: 63000)];
      final kept = pruneClipsOverlappedBy(
        clips,
        const IntervalSpan(startMs: 61000, endMs: 62000),
      );
      expect(kept, isEmpty);
    });

    test('素材记录永不被清理改动（函数不触素材表）', () {
      final material = _material();
      pruneClipsOverlappedBy([
        _clip('a', sourceStart: 61000, sourceEnd: 62000),
      ], const IntervalSpan(startMs: 60000, endMs: 63000));
      expect(material, equals(_material()), reason: '重叠清理只作用于轨道引用，素材不动');
    });
  });

  group('截取吸附', () {
    test('就绪网格：吸到最近拍点（八拍点，经相位求值）', () {
      // 网格 500ms/拍、八拍点每 8 拍一个（4000ms 间隔）；素材内偏移
      // 2100 + 素材源起点 60000 = 62100 → 就近八拍点 64000 → 偏移 4000。
      final snapped = snapTrimOffsetMs(
        offsetInMaterialMs: 2100,
        materialSourceStartMs: 60000,
        materialDurationMs: 10000,
        phase: BeatPhase(grid: _realGrid),
      );
      expect(snapped, 4000);
    });

    test('带八拍锚点：落点跟锚点重定相后的八拍点', () {
      // 锚点设在拍 4（2000ms，强拍）→ 其后八拍点 = 2000ms 起每 4000ms：
      // …62000、66000；同一请求位置落 62000（无锚时落 64000）。
      final snapped = snapTrimOffsetMs(
        offsetInMaterialMs: 2100,
        materialSourceStartMs: 60000,
        materialDurationMs: 10000,
        phase: BeatPhase(grid: _realGrid, anchors: [4]),
      );
      expect(snapped, 2000);
    });

    test('占位/无界均匀网格同级派生（周期算术照常吸点）', () {
      final snapped = snapTrimOffsetMs(
        offsetInMaterialMs: 2100,
        materialSourceStartMs: 0,
        materialDurationMs: 10000,
        phase: BeatPhase(grid: const UniformBeatGrid()),
      );
      // 120bpm 占位：拍 500ms、八拍点 4000ms → 就近点 4000ms。
      expect(snapped, 4000);
    });

    test('异常网格（无八拍点）自由：原样返回', () {
      final snapped = snapTrimOffsetMs(
        offsetInMaterialMs: 6213,
        materialSourceStartMs: 60000,
        materialDurationMs: 10000,
        phase: BeatPhase(grid: _abnormalGrid),
      );
      expect(snapped, 6213);
    });

    test('钳在素材时长内', () {
      final snapped = snapTrimOffsetMs(
        offsetInMaterialMs: 9900,
        materialSourceStartMs: 60000,
        materialDurationMs: 10000,
        phase: BeatPhase(grid: _realGrid),
      );
      // 69900 → 就近八拍点 68000 → 偏移 8000（未越时长上限）。
      expect(snapped, 8000);
      final overflow = snapTrimOffsetMs(
        offsetInMaterialMs: 9950,
        materialSourceStartMs: 60000,
        materialDurationMs: 9000,
        phase: BeatPhase(grid: _abnormalGrid),
      );
      expect(overflow, 9000);
    });
  });

  group('激活互斥决策', () {
    test('激活练习片段 → 清除学习段与临时衔接段激活', () {
      final next = applyCompareActivation(
        current: const CompareActivationState(
          learningOrders: {0},
          transitionActive: true,
        ),
        requested: const PracticeClipLoop(clipId: 'c1'),
      );
      expect(next.practiceClipId, 'c1');
      expect(next.learningOrders, isEmpty);
      expect(next.transitionActive, isFalse);
    });

    test('激活学习段 → 清除练习片段与临时衔接段激活', () {
      final next = applyCompareActivation(
        current: const CompareActivationState(practiceClipId: 'c1'),
        requested: const LearningSegmentLoop(orders: {1}),
      );
      expect(next.learningOrders, {1});
      expect(next.practiceClipId, isNull);
      expect(next.transitionActive, isFalse);
    });

    test('激活临时衔接段 → 清除练习片段与学习段激活', () {
      final next = applyCompareActivation(
        current: const CompareActivationState(learningOrders: {0, 1}),
        requested: const TransitionSegmentLoop(),
      );
      expect(next.transitionActive, isTrue);
      expect(next.learningOrders, isEmpty);
      expect(next.practiceClipId, isNull);
    });

    test('清除请求 → 激活源回到空（保持单值不变形）', () {
      final next = applyCompareActivation(
        current: const CompareActivationState(practiceClipId: 'c1'),
        requested: null,
      );
      expect(next.isEmpty, isTrue);
    });

    test('进度拖出片段范围 → 清除片段激活（端点仍属范围）', () {
      const range = IntervalSpan(startMs: 1000, endMs: 5000);
      expect(
        clipActivationAfterSeek(
          active: const PracticeClipLoop(clipId: 'c1'),
          positionMs: 3000,
          clipRange: range,
        ),
        isNotNull,
      );
      expect(
        clipActivationAfterSeek(
          active: const PracticeClipLoop(clipId: 'c1'),
          positionMs: 1000,
          clipRange: range,
        ),
        isNotNull,
      );
      expect(
        clipActivationAfterSeek(
          active: const PracticeClipLoop(clipId: 'c1'),
          positionMs: 5001,
          clipRange: range,
        ),
        isNull,
      );
    });
  });
}
