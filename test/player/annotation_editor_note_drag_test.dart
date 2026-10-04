import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show beatTrackStateProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart';
import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（备注臂入队断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「轨片段拖动（整体移 + 端点拖）」模块写缝直测：拖动
/// 命令经 submit 单一收口 seam 落地——整体移宽度不变、端点拖改起止且不
/// 得倒置；与相邻备注 + 视频首尾互斥钳制，钳空 = EditNoop 静默停住；
/// 就绪网格落点吸**每个拍点**（与局部镜像片段端点同一支）、非就绪自由；一次手势恰一个撤销步、拖回原点
/// 无撤销步；受锁定分段门禁（移 / 端点属几何类）。
void main() {
  const total = Duration(minutes: 1);

  late ProviderContainer container;
  late FakePlaybackEngine engine;
  late RecordingSaveSink sink;

  setUp(() {
    engine = FakePlaybackEngine(duration: total);
    sink = RecordingSaveSink();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        annotationSaveSinkProvider.overrideWithValue(sink),
      ],
    );
  });

  tearDown(() => container.dispose());

  AnnotationEditor editor() => container.read(annotationEditorProvider);

  List<NoteSticker> notes() => container.read(noteStickersProvider);

  int historyLength() => container.read(annotationEditHistoryProvider).length;

  /// 就绪网格：真实拍点每 0.5s 一拍 → 拍点 = 0/0.5/1…s（八拍点 0/4/8…s
  /// 只是其中每第 8 个）。
  void injectReadyGrid({double seconds = 60}) {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: seconds));
  }

  void restore({List<NoteSticker> notes = const []}) {
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: notes,
      ),
    );
  }

  group('整体移命令（MoveNote）', () {
    test('宽度不变、时间窗平移；就绪网格起点吸附拍点；单步入史', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);

      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 21000)),
      );
      expect(outcome.applied, isTrue);
      // 备注 lane 变化不改学习段几何：geometryChanged 恒假。
      expect(outcome.geometryChanged, isFalse);
      // 21s 是拍点（不是八拍点）也照落：按拍点吸附、不按八拍分级。
      expect(notes(), const [NoteSticker(startMs: 21000, endMs: 29000)]);
      expect(historyLength(), 1);
    });

    test('非就绪网格：不吸附、落点 = 请求位置（自由）', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 15300)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [NoteSticker(startMs: 15300, endMs: 23300)]);
    });

    test('与左邻备注互斥钳制：顶到左邻终点不再前进', () {
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 4000, endMs: 12000),
          NoteSticker(startMs: 20000, endMs: 28000),
        ],
      );
      editor().submit(
        const MoveNote(index: 1, to: Duration(milliseconds: 8000)),
      );
      expect(notes(), const [
        NoteSticker(startMs: 4000, endMs: 12000),
        // 钳到左邻终点 12s（半开共享端点视为不重叠）。
        NoteSticker(startMs: 12000, endMs: 20000),
      ]);
    });

    test('与视频首尾互斥钳制：钳进首尾区间内', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: -40000)),
      );
      expect(notes(), const [NoteSticker(startMs: 0, endMs: 8000)]);

      restore(notes: const [NoteSticker(startMs: 50000, endMs: 58000)]);
      editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 80000)),
      );
      expect(notes(), const [NoteSticker(startMs: 52000, endMs: 60000)]);
    });

    test('钳空（无可放置区间）= EditNoop 静默停住，历史与保存不动', () {
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 0, endMs: 20000),
          NoteSticker(startMs: 20000, endMs: 36000),
        ],
      );
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 4000)),
      );
      expect(outcome.applied, isFalse);
      expect(notes(), const [
        NoteSticker(startMs: 0, endMs: 20000),
        NoteSticker(startMs: 20000, endMs: 36000),
      ]);
      expect(historyLength(), 0);
      expect(sink.saved, isEmpty);
    });

    test('拖回原点：无净变化 = EditNoop、不入史', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 4000, endMs: 12000)]);
      final outcome = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 4100)),
      );
      expect(outcome.applied, isFalse);
      expect(notes(), const [NoteSticker(startMs: 4000, endMs: 12000)]);
      expect(historyLength(), 0);
    });

    test('保留备注其它字段（文本 / 样式 / 几何）', () {
      injectReadyGrid();
      const seeded = NoteSticker(
        startMs: 10000,
        endMs: 18000,
        text: '注意手',
        geometry: NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
      );
      restore(notes: const [seeded]);
      editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 20000)),
      );
      expect(notes(), const [
        NoteSticker(
          startMs: 20000,
          endMs: 28000,
          text: '注意手',
          geometry: NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
        ),
      ]);
    });

    test('索引越界抛 RangeError', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      expect(
        () => editor().submit(
          const MoveNote(index: 1, to: Duration(milliseconds: 20000)),
        ),
        throwsRangeError,
      );
    });
  });

  group('端点拖命令（DragNoteEdge）', () {
    test('拖起点：只改起点、就绪网格吸附拍点', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      final outcome = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.start,
          to: Duration(milliseconds: 13500),
        ),
      );
      expect(outcome.applied, isTrue);
      expect(outcome.geometryChanged, isFalse);
      // 13.5s 是拍点、不是八拍点（八拍点 = 0/4/8…s）：按拍点落，不被拉回 12s。
      expect(notes(), const [NoteSticker(startMs: 13500, endMs: 18000)]);
    });

    test('拖终点：只改终点；向右邻备注起点钳制', () {
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 10000, endMs: 18000),
          NoteSticker(startMs: 20000, endMs: 24000),
        ],
      );
      editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(milliseconds: 30000),
        ),
      );
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 20000),
        NoteSticker(startMs: 20000, endMs: 24000),
      ]);
    });

    test('端点不得倒置：起点拖过终点 = EditNoop；终点拖过起点同', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      final startOver = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.start,
          to: Duration(milliseconds: 20000),
        ),
      );
      expect(startOver.applied, isFalse);
      final endUnder = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(milliseconds: 8000),
        ),
      );
      expect(endUnder.applied, isFalse);
      expect(notes(), const [NoteSticker(startMs: 10000, endMs: 18000)]);
      expect(historyLength(), 0);
    });

    test('非就绪网格：端点自由落点（不吸附）', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      final outcome = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.end,
          to: Duration(milliseconds: 21500),
        ),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [NoteSticker(startMs: 10000, endMs: 21500)]);
    });

    test('拖回原位：无净变化 = EditNoop、不入史', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 12000, endMs: 18000)]);
      final outcome = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.start,
          to: Duration(milliseconds: 12200),
        ),
      );
      expect(outcome.applied, isFalse);
      expect(notes(), const [NoteSticker(startMs: 12000, endMs: 18000)]);
      expect(historyLength(), 0);
    });

    test('索引越界抛 RangeError', () {
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      expect(
        () => editor().submit(
          const DragNoteEdge(
            index: -1,
            edge: IntervalEdge.start,
            to: Duration(milliseconds: 12000),
          ),
        ),
        throwsRangeError,
      );
    });
  });

  group('拖动会话（唯一令牌 / 逐帧并入事务 / 一次净变化收口）', () {
    test('整体移会话：逐帧生效、收口恰一个撤销步、undo/redo 逐位回放', () {
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 10000, endMs: 18000),
          NoteSticker(startMs: 40000, endMs: 44000),
        ],
      );

      final session = editor().beginNoteMoveDrag(0);
      expect(session.moveTo(const Duration(milliseconds: 25000)), isNotNull);
      expect(notes()[0], const NoteSticker(startMs: 25000, endMs: 33000));
      expect(session.moveTo(const Duration(milliseconds: 30250)), isNotNull);
      // 请求 30.25s 与 30s/30.5s 两个拍点等距：并列取时间靠后者（与
      // snap.dart 同口径）。
      expect(notes()[0], const NoteSticker(startMs: 30500, endMs: 38500));
      // 会话中逐帧不入史。
      expect(historyLength(), 0);

      session.end();
      expect(historyLength(), 1);
      expect(notes(), const [
        NoteSticker(startMs: 30500, endMs: 38500),
        NoteSticker(startMs: 40000, endMs: 44000),
      ]);

      editor().undo();
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 18000),
        NoteSticker(startMs: 40000, endMs: 44000),
      ]);
      editor().redo();
      expect(notes(), const [
        NoteSticker(startMs: 30500, endMs: 38500),
        NoteSticker(startMs: 40000, endMs: 44000),
      ]);
    });

    test('端点拖会话：逐帧生效、收口一个撤销步', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);

      final session = editor().beginNoteEdgeDrag(0, IntervalEdge.end);
      expect(session.moveTo(const Duration(milliseconds: 25000)), isNotNull);
      expect(notes().single, const NoteSticker(startMs: 10000, endMs: 25000));
      expect(historyLength(), 0);

      session.end();
      expect(historyLength(), 1);
      expect(notes().single, const NoteSticker(startMs: 10000, endMs: 25000));
    });

    test('拖回原点收口：无净变化 = 不入史', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 4000, endMs: 12000)]);

      final session = editor().beginNoteMoveDrag(0);
      session.moveTo(const Duration(milliseconds: 8000));
      session.moveTo(const Duration(milliseconds: 4000));
      session.end();
      expect(notes().single, const NoteSticker(startMs: 4000, endMs: 12000));
      expect(historyLength(), 0);
    });

    test('会话唯一性：新会话顶替后旧会话逐帧与收口皆失效', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);

      final stale = editor().beginNoteMoveDrag(0);
      final current = editor().beginNoteMoveDrag(0);
      expect(stale.moveTo(const Duration(milliseconds: 20000)), isNull);
      expect(current.moveTo(const Duration(milliseconds: 20000)), isNotNull);
      stale.end();
      // 陈旧会话收口为空操作：收口归当前会话。
      expect(historyLength(), 0);
      current.end();
      expect(historyLength(), 1);
    });

    test('会话索引越界抛 RangeError', () {
      restore();
      expect(() => editor().beginNoteMoveDrag(0), throwsRangeError);
      expect(
        () => editor().beginNoteEdgeDrag(0, IntervalEdge.end),
        throwsRangeError,
      );
    });
  });

  group('不受锁定分段门禁（锁只护分段结构）', () {
    test('锁定分段开启 → 移/端点照常生效并入史', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 10000, endMs: 18000)]);
      container.read(layoutLockedProvider.notifier).toggle();

      final move = editor().submit(
        const MoveNote(index: 0, to: Duration(milliseconds: 20000)),
      );
      expect(move.applied, isTrue);
      final edge = editor().submit(
        const DragNoteEdge(
          index: 0,
          edge: IntervalEdge.start,
          to: Duration(milliseconds: 8000),
        ),
      );
      expect(edge.applied, isTrue);
      expect(notes(), isNotEmpty);
      expect(historyLength(), greaterThan(0));
    });
  });
}
