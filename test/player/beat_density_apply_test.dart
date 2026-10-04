import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show
        BeatTrackState,
        beatGridProvider,
        beatPhaseProvider,
        beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationSaveSinkStateProvider,
        annotationTimelineProvider,
        layoutLockedProvider;
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录 diff 的假保存编排（编辑器 → sink 链路断言用）。
class RecordingSink implements AnnotationSaveSink {
  final diffs = <AnnotationSectionDiff>[];

  @override
  void save(AnnotationSectionDiff diff) => diffs.add(diff);

  @override
  Future<void> flush() async {}
}

/// 节拍倍频应用 seam 测试：
/// 倍频写定 + 八拍锚点就地烘焙的整链（一次段级提交 / 一步撤销 / 落盘
/// diff / 正交性 / 门禁），仿 beat_alignment_apply_test 模板。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late FakePlaybackEngine engine;

  /// 就绪网格文档：9 个原拍点 0.5..4.5s 步长 0.5s，downbeat 在原序号
  /// 0/4/8；[anchors] 为八拍锚点集合（原样档派生网格拍序号）。
  void seedReadyGrid({double shift = 0, List<int> anchors = const []}) {
    final track = BeatTrackState.ready(
      BeatGrid(
        model: 'madmom_downbeat_rnn_full.onnx',
        fps: 100,
        generatedAt: DateTime.utc(2026, 9, 17),
        shift: shift,
        anchors: anchors,
        beats: const [
          BeatPoint(t: 0.5, down: true),
          BeatPoint(t: 1.0, down: false),
          BeatPoint(t: 1.5, down: false),
          BeatPoint(t: 2.0, down: false),
          BeatPoint(t: 2.5, down: true),
          BeatPoint(t: 3.0, down: false),
          BeatPoint(t: 3.5, down: false),
          BeatPoint(t: 4.0, down: false),
          BeatPoint(t: 4.5, down: true),
        ],
      ),
    );
    container.read(beatTrackStateProvider.notifier).replace(track);
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);
  AnnotationTimeline timeline() => container.read(annotationTimelineProvider);
  BeatGrid docGrid() => container.read(beatTrackStateProvider).grid!;
  int historyLength() => container.read(annotationEditHistoryProvider).length;

  group('submitBeatDensity（倍频应用命令）', () {
    test('非就绪网格抛 StateError（占位/异常不适用）', () {
      expect(() => editor().submitBeatDensity(2), throwsStateError);
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());
      expect(() => editor().submitBeatDensity(2), throwsStateError);
    });

    test('快方向 ×2：锚点序号按倍率重写、锚点时刻与八拍点判定都不变', () {
      seedReadyGrid(anchors: const [4, 8]);
      final anchorTimeBefore = container.read(beatGridProvider).beatTime(4);

      final outcome = editor().submitBeatDensity(2);
      expect(outcome.applied, isTrue);
      expect(docGrid().density, 2);
      // 锚点全保，序号 ×2（派生网格拍序号）。
      expect(docGrid().anchors, [8, 16]);
      // 锚点时刻不变（同一段音乐）。
      expect(container.read(beatGridProvider).beatTime(8), anchorTimeBefore);
      // 「它是不是八拍点」判定不变（新相位源下锚点仍是八拍点）。
      expect(container.read(beatPhaseProvider).isEightBeatPoint(8), isTrue);
    });

    test('慢方向 ×½：只保住落在新强拍上的锚点，丢弃不留越界或非强拍残留', () {
      seedReadyGrid(anchors: const [4, 8]);
      final outcome = editor().submitBeatDensity(0.5);
      expect(outcome.applied, isTrue);
      expect(docGrid().density, 0.5);
      // 原序号 4（2.5s）不在新强拍集（新 down 位 = 派生 0/4 → 原序号
      // 0/8），被丢弃；原序号 8 落在新强拍上、重写为派生序号 4。
      expect(docGrid().anchors, [4]);
      // 残留检查：全部在新派生网格界内且是 down 位。
      final derived = container.read(beatGridProvider);
      for (final anchor in docGrid().anchors) {
        expect(derived.isDownbeat(anchor), isTrue);
      }
      expect(container.read(beatPhaseProvider).anchors, [4]);
    });

    test('快方向丢弃的恰是落不到新强拍的：全部锚点在新网格 down 位上', () {
      seedReadyGrid(anchors: const [4, 8]);
      editor().submitBeatDensity(4);
      final derived = container.read(beatGridProvider);
      for (final anchor in docGrid().anchors) {
        expect(derived.isDownbeat(anchor), isTrue);
      }
      expect(docGrid().anchors, [16, 32]);
    });

    test('一次修正 = 一次段级提交、一步撤销；撤销同时回退倍频与锚点', () {
      seedReadyGrid(anchors: const [4, 8]);
      final before = historyLength();
      editor().submitBeatDensity(2);
      expect(historyLength(), before + 1);
      editor().undo();
      expect(docGrid().density, 1);
      expect(docGrid().anchors, [4, 8]);
      expect(historyLength(), before);
    });

    test('改倍频不动平移量、不动任何线的时刻', () {
      seedReadyGrid(shift: 0.25, anchors: const [4]);
      editor().submit(const AddSegmentLine(at: Duration(seconds: 10)));
      final linesBefore = timeline().segmentLines;
      editor().submitBeatDensity(2);
      expect(docGrid().shift, 0.25);
      expect(timeline().segmentLines, linesBefore);
      // 正交反向：改平移量不动倍频与锚点。
      editor().submitBeatShift(0.5);
      expect(docGrid().density, 2);
      expect(docGrid().anchors, [8]);
    });

    test('同档重复应用为 EditNoop（不入史）', () {
      seedReadyGrid(anchors: const [4]);
      editor().submitBeatDensity(2);
      final before = historyLength();
      expect(editor().submitBeatDensity(2).applied, isFalse);
      expect(historyLength(), before);
    });

    test('锁定分段不挡倍频：照常应用、入史、写定、不弹锁提示', () {
      seedReadyGrid(anchors: const [4]);
      container.read(layoutLockedProvider.notifier).toggle();
      final before = historyLength();
      final outcome = editor().submitBeatDensity(2);
      expect(outcome.applied, isTrue);
      expect(historyLength(), before + 1);
      expect(docGrid().density, 2);
      expect(container.read(noticeTriggerProvider(NoticeId.layoutLock)), 0);
    });
  });

  group('倍频后的自动分段（消费方：首尾线落在派生网格首末拍）', () {
    /// 生产调用路径：自动分段消费 track 的 beat 文档（含已落盘倍频）。
    void submitAutoSegment() {
      final outcome = editor().submitAutoSegment(
        docGrid(),
        fullIntervalsPerSegment: 4,
      );
      expect(outcome.applied, isTrue);
    }

    test('×2 后自动分段：尾线 = 派生网格末拍 4.5s（不是曲中 2.5s）', () {
      seedReadyGrid();
      editor().submitBeatDensity(2);
      // 派生网格 17 拍（0.5..4.5s 步 0.25s）；文档仍 9 拍——末拍序号必须
      // 取派生网格自己的，按文档拍数索引会落在曲中。
      expect(container.read(beatGridProvider).lastBeatIndex, 16);

      submitAutoSegment();

      expect(timeline().rangeStart, const Duration(milliseconds: 500));
      expect(timeline().rangeEnd, const Duration(milliseconds: 4500));
      // 八拍点 0.5/2.5/4.5s → 只 2 个整八拍区间，未满 4 不下刀。
      expect(timeline().segmentLines, isEmpty);
    });

    test('×½ 后自动分段：尾线 = 派生网格末拍 4.5s（不按文档拍数外推）', () {
      seedReadyGrid();
      editor().submitBeatDensity(0.5);
      // 派生网格 5 拍（0.5/1.5/2.5/3.5/4.5s）。
      expect(container.read(beatGridProvider).lastBeatIndex, 4);

      submitAutoSegment();

      expect(timeline().rangeStart, const Duration(milliseconds: 500));
      expect(timeline().rangeEnd, const Duration(milliseconds: 4500));
    });
  });

  group('编辑器 → 保存编排链路（sink diff）', () {
    test('倍频应用入队含 corrections 段（density + anchors）的段级 diff；'
        'undo 回退两者', () {
      final sink = RecordingSink();
      container.read(annotationSaveSinkStateProvider.notifier).set(sink);
      seedReadyGrid(anchors: const [4, 8]);
      sink.diffs.clear();

      editor().submitBeatDensity(0.5);
      final applyDiff = sink.diffs.last;
      expect(applyDiff.corrections?.density, 0.5);
      expect(applyDiff.corrections?.eightBeatAnchors, [4]);
      expect(applyDiff.corrections?.shiftSeconds, 0);

      editor().undo();
      expect(sink.diffs.last.corrections?.density, 1);
      expect(sink.diffs.last.corrections?.eightBeatAnchors, [4, 8]);
    });
  });

  group('锚点烘焙纯函数（rebakeEightBeatAnchors）', () {
    final beats = [
      for (var i = 0; i < 9; i++) BeatPoint(t: 0.5 + i * 0.5, down: i % 4 == 0),
    ];

    test('原样 → 原样：恒等', () {
      expect(
        rebakeEightBeatAnchors(
          beats: beats,
          fromDensity: 1,
          toDensity: 1,
          anchors: const [4, 8],
        ),
        [4, 8],
      );
    });

    test('越界旧锚点直接丢弃，不抛', () {
      expect(
        rebakeEightBeatAnchors(
          beats: beats,
          fromDensity: 1,
          toDensity: 2,
          anchors: const [99, 4],
        ),
        [8],
      );
    });
  });
}
