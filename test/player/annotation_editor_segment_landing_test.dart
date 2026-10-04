import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatAlignPreviewOffsetProvider, beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        annotationTimelineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 分段线落点解析模块面直测：交互命令提交时模块内解析就近
/// 八拍点（经 core 单一相位源）+ 合法域（时间线开区间）检查——吸附触界或
/// 区间内无合法落点 = EditNoop 静默（不入史不入盘）；拖动会话 moveTo 返回
/// 写后真实落点；不经落点解析的豁免路径（节拍对齐平移、撤销回放）照常。
class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

void main() {
  const total = Duration(minutes: 1);
  // 就绪网格与占位同值：0.5s 一拍、八拍点 = 0/4/8…s。
  const ten30 = Duration(seconds: 10, milliseconds: 300);
  const eight = Duration(seconds: 8);
  const twelve = Duration(seconds: 12);

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

  void injectReadyGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: 60));
  }

  /// 无 downbeat 的就绪网格（拍点在、八拍相位无法派生 → 无合法落点）。
  void injectReadyGridWithoutDownbeats() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(
          BeatTrackState.ready(
            marker_doc.BeatGrid(
              model: 'fake.onnx',
              fps: 100,
              generatedAt: DateTime.utc(2024),
              beats: [
                for (var i = 0; i < 120; i++)
                  marker_doc.BeatPoint(t: 0.5 + i * 0.5, down: false),
              ],
            ),
          ),
        );
  }

  group('AddSegmentLine：提交时模块内八拍点吸附', () {
    test('任意请求位置写入就近八拍点（等距取靠后）', () {
      injectReadyGrid();
      final outcome = editor().submit(AddSegmentLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        twelve,
        reason: '10s+300ms → 就近八拍点 12s（距 12s 1.7s、距 8s 2.3s）',
      );
    });

    test('吸附触界静默：EditNoop、不入史、不入盘、状态未动', () {
      injectReadyGrid();
      final timelineBefore = container.read(annotationTimelineProvider);

      // 预览 500ms 在开区间内，但最近八拍点 = 0 = rangeStart。
      final left = editor().submit(
        AddSegmentLine(at: const Duration(milliseconds: 500)),
      );
      // 预览 59.9s，最近八拍点 = 60s = rangeEnd。
      final right = editor().submit(
        AddSegmentLine(at: const Duration(seconds: 59, milliseconds: 900)),
      );

      expect(left, isA<EditNoop>());
      expect(right, isA<EditNoop>());
      expect(container.read(annotationTimelineProvider), timelineBefore);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);
    });

    test('区间内无合法落点静默：网格无 downbeat（八拍相位不可派生）', () {
      injectReadyGridWithoutDownbeats();
      final outcome = editor().submit(AddSegmentLine(at: ten30));

      expect(outcome, isA<EditNoop>());
      expect(container.read(annotationTimelineProvider).segmentLines, isEmpty);
      expect(sink.saved, isEmpty);
    });

    test('非就绪网格：请求位置经合法域检查后直通（不经吸附，幂等回退）', () {
      // 占位态（未注入就绪网格）：生产入口由就绪置灰门挡住，模块对到达
      // 的请求只做合法域检查、不做吸附。
      final outcome = editor().submit(AddSegmentLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        ten30,
      );
    });
  });

  group('落点错误契约：越界提交 = EditNoop 静默', () {
    test('区间外/触界请求不再抛 ArgumentError、不半写不入史', () {
      final timelineBefore = container.read(annotationTimelineProvider);

      expect(
        editor().submit(AddSegmentLine(at: Duration.zero)),
        isA<EditNoop>(),
      );
      expect(editor().submit(AddSegmentLine(at: total)), isA<EditNoop>());
      expect(
        editor().submit(AddSegmentLine(at: total + const Duration(seconds: 1))),
        isA<EditNoop>(),
      );
      expect(container.read(annotationTimelineProvider), timelineBefore);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);
    });
  });

  group('拖动会话：moveTo 返回写后真实落点', () {
    test('逐帧请求原始指针位置，返回吸附后的线位置驱动预览', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: eight));
      final session = editor().beginLineDrag(0);

      expect(session.moveTo(ten30), twelve);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        twelve,
      );

      // 同位帧：无净变化返回 null 且不写。
      expect(session.moveTo(twelve), isNull);
      session.end();
    });

    test('吸附后越邻钳制丢弃：返回 null、线不动', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: eight));
      editor().submit(AddSegmentLine(at: const Duration(seconds: 16)));
      final session = editor().beginLineDrag(0);

      // 20s 的八拍点越过邻线 16s → moveSegmentLine 钳制丢弃。
      expect(session.moveTo(const Duration(seconds: 20)), isNull);
      expect(
        container.read(annotationTimelineProvider).segmentLines[0].position,
        eight,
      );
      session.end();
    });
  });

  group('豁免路径不经吸附', () {
    test('节拍对齐整体平移照常（不平移到八拍点）', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: eight));
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.3);

      final outcome = editor().submitBeatShift(0.3);

      expect(outcome.applied, isTrue);
      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        const Duration(seconds: 8, milliseconds: 300),
        reason: '整体平移按差值原样落位、不经八拍点吸附',
      );
    });

    test('撤销回放照常（回放值即历史快照、不被吸附改写）', () {
      injectReadyGrid();
      editor().submit(AddSegmentLine(at: eight));
      container.read(beatAlignPreviewOffsetProvider.notifier).set(0.3);
      editor().submitBeatShift(0.3);

      editor().undo();

      expect(
        container.read(annotationTimelineProvider).segmentLines.single.position,
        eight,
      );
    });
  });
}
