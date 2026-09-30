import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
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

/// 「备注插入命令与落点解析」模块写缝直测：插入经 submit
/// 单一收口 seam 落地，落点解析四步（钳入首尾 → 占用不建 → 自由区间内
/// 最近八拍点吸附 → 向视频尾与右邻起点截断）全部经命令结果 + 回读备注
/// 列表观察；非就绪网格不吸附、照常创建（不静默 no-op）；零宽不成立；
/// 列表按起点升序且两两不重叠；受锁定分段门禁（建属几何类）。
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

  /// 就绪网格：真实拍点每 0.5s 一拍、强拍每 4 拍 → 八拍点 = 0/4/8…s、
  /// 派生格一个八拍宽 = 4s。吸附落点据此断言。
  void injectReadyGrid({double seconds = 60}) {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(uniformReadyBeatState(seconds: seconds));
  }

  void injectErrorGrid() {
    container
        .read(beatTrackStateProvider.notifier)
        .replace(const BeatTrackState.error());
  }

  void restore({List<NoteSticker> notes = const []}) {
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: notes,
      ),
    );
  }

  group('默认窗与吸附（起点吸自由区间内最近拍点、宽一个八拍）', () {
    test('就绪网格：落点吸附到拍点、窗宽一个八拍，单步入史', () {
      injectReadyGrid();
      restore();

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 5100)),
      );
      expect(outcome.applied, isTrue);
      // 几何（备注 lane 变化）不改学习段几何：geometryChanged 恒假。
      expect(outcome.geometryChanged, isFalse);
      // 5.1s 吸最近拍点 5s（不是被拉回 4s 的八拍点），窗宽仍是一个八拍。
      expect(notes(), const [
        NoteSticker(startMs: 5000, endMs: 9000),
      ]);
      expect(container.read(annotationEditHistoryProvider).length, 1);
    });

    test('段级折叠：插入入队保存 diff 只带 notes 段', () {
      injectReadyGrid();
      restore();
      editor().submit(
        const InsertNote(at: Duration(milliseconds: 5100)),
      );
      final diff = sink.saved.single;
      expect(diff.notes, const [NoteSticker(startMs: 5000, endMs: 9000)]);
      expect(diff.annotations, isNull);
      expect(diff.corrections, isNull);
      expect(diff.session, isNull);
    });
  });

  group('网格未就绪：不吸附、照常创建（落点 = 请求位置，不静默 no-op）', () {
    test('占位网格：起点 = 请求位置、窗宽 = 派生格一个八拍', () {
      restore();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 10300)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [
        NoteSticker(startMs: 10300, endMs: 14300),
      ]);
    });

    test('异常网格：吸附停用直通、窗宽秒制兜底一个八拍', () {
      injectErrorGrid();
      restore();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 10300)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [
        NoteSticker(startMs: 10300, endMs: 14300),
      ]);
    });
  });

  group('落点在既有备注窗内：不建且不产生备注（模块兜底 no-op）', () {
    const seed = [NoteSticker(startMs: 10000, endMs: 18000)];

    test('请求位置落在既有窗内 → EditNoop，备注列表与历史不动', () {
      injectReadyGrid();
      restore(notes: seed);
      sink.saved.clear();

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 12000)),
      );
      expect(outcome.applied, isFalse);
      expect(notes(), seed);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);
    });

    test('占用谓词按半开窗判定，供入口路由消费', () {
      restore(notes: seed);
      expect(editor().isNoteLandingOccupied(const Duration(milliseconds: 12000)), isTrue);
      expect(editor().isNoteLandingOccupied(const Duration(milliseconds: 10000)), isTrue);
      expect(editor().isNoteLandingOccupied(const Duration(milliseconds: 18000)), isFalse);
      expect(editor().isNoteLandingOccupied(const Duration(milliseconds: 9999)), isFalse);
    });
  });

  group('越界钳制与截断', () {
    test('请求位置越首界：钳入视频首、吸附首拍点', () {
      injectReadyGrid();
      restore();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: -2000)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [NoteSticker(startMs: 0, endMs: 4000)]);
    });

    test('向右邻备注起点截断（不重叠不变量）', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 7000, endMs: 15000)]);
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 5100)),
      );
      expect(outcome.applied, isTrue);
      // 吸附 5s 起、默认宽到 9s，被右邻起点 7s 截断。
      expect(notes(), const [
        NoteSticker(startMs: 5000, endMs: 7000),
        NoteSticker(startMs: 7000, endMs: 15000),
      ]);
    });

    test('向视频尾截断', () {
      injectReadyGrid();
      restore();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 57500)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [NoteSticker(startMs: 57500, endMs: 60000)]);
    });

    test('紧贴右邻备注起点：半开区间共享端点视为不重叠、照常成立', () {
      injectReadyGrid();
      restore(
        notes: const [NoteSticker(startMs: 56000, endMs: 60000)],
      );
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 55000)),
      );
      expect(outcome.applied, isTrue);
      // 55s 请求即拍点、照落 55s，默认宽到 59s 被右邻起点 56s 截断为紧贴。
      expect(notes(), const [
        NoteSticker(startMs: 55000, endMs: 56000),
        NoteSticker(startMs: 56000, endMs: 60000),
      ]);
    });

    test('钳在视频尾起点：终点向尾截断到零宽不成立（EditNoop、不产生备注）', () {
      injectReadyGrid();
      restore();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 60000)),
      );
      expect(outcome.applied, isFalse);
      expect(notes(), isEmpty);
    });
  });

  group('起点吸附只在自由区间内取拍点（不吸被占窗内的拍点）', () {
    test('被占拍点被跳过：吸附取下一自由拍点', () {
      injectReadyGrid();
      restore(notes: const [NoteSticker(startMs: 4000, endMs: 14700)]);
      sink.saved.clear();
      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 14720)),
      );
      expect(outcome.applied, isTrue);
      // 请求 14.72s 已在既有窗尾之外（窗 = [4s,14.7s)）；最近拍点 14.5s 落在
      // 窗内被跳过，取下一自由拍点 15s——而不是把新备注叠进既有窗。
      expect(notes(), const [
        NoteSticker(startMs: 4000, endMs: 14700),
        NoteSticker(startMs: 15000, endMs: 19000),
      ]);
    });
  });

  group('结果列表按起点升序且两两不重叠；撤销/重做逐位回放', () {
    test('两次插入按起点升序；undo 逐步回退', () {
      injectReadyGrid();
      restore();
      editor().submit(const InsertNote(at: Duration(milliseconds: 40500)));
      editor().submit(const InsertNote(at: Duration(milliseconds: 10200)));
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 14000),
        NoteSticker(startMs: 40500, endMs: 44500),
      ]);

      editor().undo();
      expect(notes(), const [NoteSticker(startMs: 40500, endMs: 44500)]);
      editor().undo();
      expect(notes(), isEmpty);

      editor().redo();
      expect(notes(), const [NoteSticker(startMs: 40500, endMs: 44500)]);
      editor().redo();
      expect(notes(), const [
        NoteSticker(startMs: 10000, endMs: 14000),
        NoteSticker(startMs: 40500, endMs: 44500),
      ]);
    });
  });

  group('不受锁定分段门禁（锁只护分段结构）', () {
    test('锁定分段开启 → 备注照常建出并入史', () {
      injectReadyGrid();
      restore();
      container.read(layoutLockedProvider.notifier).toggle();

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 5100)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), hasLength(1));
      expect(container.read(annotationEditHistoryProvider).length, 1);
    });
  });

  group('新建几何初值：沿用落点左侧紧邻的前一条（无前一条回落默认落点）', () {
    const left = NoteGeometry(centerX: 0.2, centerY: 0.8, scale: 2.0);

    test('前一条带非默认几何 → 新备注沿用其三字段', () {
      injectReadyGrid();
      restore(
        notes: const [NoteSticker(startMs: 0, endMs: 4000, geometry: left)],
      );

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 10200)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [
        NoteSticker(startMs: 0, endMs: 4000, geometry: left),
        NoteSticker(startMs: 10000, endMs: 14000, geometry: left),
      ]);
      expect(container.read(annotationEditHistoryProvider).length, 1,
          reason: '沿用几何不额外入史');
    });

    test('值拷贝：随后改动左邻的几何，已建出的新备注不跟着变', () {
      injectReadyGrid();
      restore(
        notes: const [NoteSticker(startMs: 0, endMs: 4000, geometry: left)],
      );
      editor().submit(const InsertNote(at: Duration(milliseconds: 10200)));

      const moved = NoteGeometry(centerX: 0.9, centerY: 0.1, scale: 0.5);
      editor().submit(const SetNoteGeometry(index: 0, geometry: moved));

      expect(notes(), const [
        NoteSticker(startMs: 0, endMs: 4000, geometry: moved),
        NoteSticker(startMs: 10000, endMs: 14000, geometry: left),
      ]);
    });

    test('落点在两段之间的空档：取左邻（不是右邻、也不是列表最后一条）', () {
      const right = NoteGeometry(centerX: 0.9, centerY: 0.3, scale: 0.5);
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 0, endMs: 4000, geometry: left),
          NoteSticker(startMs: 20000, endMs: 24000, geometry: right),
        ],
      );

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 10200)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [
        NoteSticker(startMs: 0, endMs: 4000, geometry: left),
        NoteSticker(startMs: 10000, endMs: 14000, geometry: left),
        NoteSticker(startMs: 20000, endMs: 24000, geometry: right),
      ]);
    });

    test('落在所有既有备注之前：无左邻，回落默认落点（不抄它右边那条）', () {
      injectReadyGrid();
      restore(
        notes: const [NoteSticker(startMs: 10000, endMs: 14000, geometry: left)],
      );

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 2000)),
      );
      expect(outcome.applied, isTrue);
      // 2s 本身是拍点、照落 2s（落点在既有备注之前）；几何回落默认落点。
      expect(notes(), const [
        NoteSticker(startMs: 2000, endMs: 6000),
        NoteSticker(startMs: 10000, endMs: 14000, geometry: left),
      ]);
    });

    test('左邻已上内容锁：照旧沿用（取初值不改既有备注、不受锁）', () {
      injectReadyGrid();
      restore(
        notes: const [
          NoteSticker(startMs: 0, endMs: 4000, geometry: left, locked: true),
        ],
      );

      final outcome = editor().submit(
        const InsertNote(at: Duration(milliseconds: 10200)),
      );
      expect(outcome.applied, isTrue);
      expect(notes(), const [
        NoteSticker(startMs: 0, endMs: 4000, geometry: left, locked: true),
        NoteSticker(startMs: 10000, endMs: 14000, geometry: left),
      ]);
    });
  });
}
