import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 首尾线落点解析模块面直测：SetVideoRange（含端标拖动会话
/// 与离散提交）在提交时模块内解析落点——节拍网格覆盖区（首拍..末拍）内吸
/// 最近真实拍点、覆盖区外与异常态（无界占位/异常网格）自由落点；端标本体
/// 即区间边界，合法域 = 首尾可拖范围与归一化钳制（setVideoRange 纯函数
/// 收口），不适用分段线的开区间触界检查；拖动 moveTo 返回写后真实落点。
class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

void main() {
  const total = Duration(minutes: 1);
  // 覆盖区 0..40s、拍点每 0.5s 一拍（真实拍点 = 0/0.5/1/…/40s）；40s 之外
  // 为覆盖区外（首尾线可拖出网格生成区直到片尾 60s）。
  const lastBeat = Duration(seconds: 40);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late _RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = _RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  /// 就绪网格：覆盖区 0..40s（不覆盖全片），与占位均匀实现同拍距。
  void injectReadyGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 40));
  }

  group('SetVideoRange：提交时模块内真实拍点吸附', () {
    test('覆盖区内请求写入就近真实拍点（离散提交）', () {
      injectReadyGrid();
      final outcome = editor().submit(
        SetVideoRange(start: const Duration(seconds: 10, milliseconds: 300)),
      );

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(seconds: 10, milliseconds: 500),
        reason: '10.3s → 就近真实拍点 10.5s（距 10.5s 0.2s、距 10s 0.3s）',
      );
    });

    test('覆盖区内相邻拍点请求幂等原样落位（步进直接提交目标）', () {
      injectReadyGrid();
      final outcome = editor().submit(
        SetVideoRange(start: const Duration(seconds: 10, milliseconds: 500)),
      );

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(seconds: 10, milliseconds: 500),
      );
    });

    test('覆盖区外请求自由落点（不回拉到末拍）', () {
      injectReadyGrid();
      final outcome = editor().submit(
        SetVideoRange(end: const Duration(seconds: 50, milliseconds: 300)),
      );

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 50, milliseconds: 300),
        reason: '50.3s 在覆盖区（0..40s）外：自由落点原样保留',
      );
    });

    test('占位网格（非就绪）：请求位置自由落点直通', () {
      final outcome = editor().submit(
        SetVideoRange(end: const Duration(seconds: 50, milliseconds: 300)),
      );

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 50, milliseconds: 300),
      );
    });

    test('异常态（无网格语义）：请求位置自由落点直通', () {
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      final outcome = editor().submit(
        SetVideoRange(end: const Duration(seconds: 50, milliseconds: 300)),
      );

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 50, milliseconds: 300),
        reason: '异常态无网格语义：自由落点，不经吸附',
      );
    });

    test('端标恰落末拍：写入成立（端标即区间边界，不适用开区间触界检查）', () {
      injectReadyGrid();
      final outcome = editor().submit(SetVideoRange(end: lastBeat));

      expect(outcome.applied, isTrue);
      expect(container.read(annotationTimelineProvider).rangeEnd, lastBeat);
    });
  });

  group('端标拖动会话：moveTo 返回写后真实落点', () {
    test('覆盖区内原始指针位置逐帧请求，返回吸附后边界落点', () {
      injectReadyGrid();
      final session = editor().beginRangeDrag(VideoRangeBoundary.end);

      expect(
        session.moveTo(const Duration(seconds: 20, milliseconds: 300)),
        const Duration(seconds: 20, milliseconds: 500),
      );
      expect(
        container.read(annotationTimelineProvider).rangeEnd,
        const Duration(seconds: 20, milliseconds: 500),
      );

      // 同位帧：无净变化返回 null 且不写。
      expect(
        session.moveTo(const Duration(seconds: 20, milliseconds: 500)),
        isNull,
      );
      session.end();
    });

    test('覆盖区外逐帧请求自由落点，返回原样落点', () {
      injectReadyGrid();
      final session = editor().beginRangeDrag(VideoRangeBoundary.start);

      expect(
        session.moveTo(const Duration(seconds: 45, milliseconds: 300)),
        const Duration(seconds: 45, milliseconds: 300),
      );
      expect(
        container.read(annotationTimelineProvider).rangeStart,
        const Duration(seconds: 45, milliseconds: 300),
      );
      session.end();
    });
  });

  group('吸附后归一化钳制照旧', () {
    test('覆盖区外自由落点写入后 start<end 不变式保持', () {
      injectReadyGrid();
      // rangeEnd 当前 60s：start 请求 50.3s（覆盖区 0..40s 外自由落点）
      // 原样写入，归一化钳制保证 start<end（setVideoRange 纯函数既有
      // 契约，落点解析不越接管）。
      final outcome = editor().submit(
        SetVideoRange(start: const Duration(seconds: 50, milliseconds: 300)),
      );

      expect(outcome.applied, isTrue);
      final timeline = container.read(annotationTimelineProvider);
      expect(
        timeline.rangeStart,
        const Duration(seconds: 50, milliseconds: 300),
      );
      expect(timeline.rangeEnd, greaterThan(timeline.rangeStart));
    });
  });
}
