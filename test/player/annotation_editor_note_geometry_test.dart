import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（备注臂入队断言用）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「贴纸几何（单指移 + 双指等比缩放）」模块写缝直测：
/// 贴纸几何命令经 submit 单一收口 seam 落地——请求几何在模块内单点钳制
///（中心钳进内容矩形归一化域、系数钳进具名界）；一次手势恰一个撤销步、
/// 拖回原位无撤销步；受锁定分段门禁（几何类）；geometryChanged 恒假。
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

  void restore({List<NoteSticker> notes = const []}) {
    editor().restoreDocument(
      AnnotationRestoreDocument(
        timeline: AnnotationTimeline.wholeVideo(total),
        notes: notes,
      ),
    );
  }

  group('贴纸几何命令（SetNoteGeometry）', () {
    test('写定请求几何（单指平移 / 双指缩放共用一条命令）', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);

      final outcome = editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
        ),
      );
      expect(outcome.applied, isTrue);
      // 备注 lane 变化不改学习段几何：geometryChanged 恒假。
      expect(outcome.geometryChanged, isFalse);
      expect(
        notes().single.geometry,
        const NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
      );
      expect(historyLength(), 1);
    });

    test('中心钳进归一化域 [0,1]、系数钳进具名界', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);

      editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: -0.5, centerY: 1.7, scale: 99),
        ),
      );
      expect(
        notes().single.geometry,
        const NoteGeometry(centerX: 0, centerY: 1, scale: noteMaxScale),
      );

      editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.2, centerY: 0.2, scale: 0.01),
        ),
      );
      expect(notes().single.geometry.scale, noteMinScale);
    });

    test('保留备注其它字段（时间窗 / 文本 / 样式）', () {
      const seeded = NoteSticker(startMs: 1000, endMs: 5000, text: '注意手');
      restore(notes: const [seeded]);
      editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.7, centerY: 0.6, scale: 2),
        ),
      );
      expect(
        notes().single,
        seeded.copyWith(
          geometry: const NoteGeometry(centerX: 0.7, centerY: 0.6, scale: 2),
        ),
      );
    });

    test('同几何重提交 = EditNoop 静默（不入史）', () {
      const seeded = NoteSticker(
        startMs: 1000,
        endMs: 5000,
        geometry: NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
      );
      restore(notes: const [seeded]);
      final outcome = editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.3, centerY: 0.4, scale: 1.5),
        ),
      );
      expect(outcome.applied, isFalse);
      expect(historyLength(), 0);
      expect(sink.saved, isEmpty);
    });

    test('索引越界抛 RangeError', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);
      expect(
        () => editor().submit(
          const SetNoteGeometry(
            index: 1,
            geometry: NoteGeometry(centerX: 0.5, centerY: 0.5),
          ),
        ),
        throwsRangeError,
      );
    });
  });

  group('贴纸几何拖动会话（第 8 个拖动会话族：逐帧并入事务、一次净变化收口）', () {
    test('逐帧生效（平移与缩放混排）、收口恰一个撤销步、undo/redo 逐位回放', () {
      restore(
        notes: const [
          NoteSticker(startMs: 1000, endMs: 5000),
          NoteSticker(startMs: 40000, endMs: 44000),
        ],
      );

      final session = editor().beginNoteGeometryDrag(0);
      // 单指平移帧：中心移动。
      expect(
        session.moveTo(const NoteGeometry(centerX: 0.4, centerY: 0.3)),
        isNotNull,
      );
      // 双指缩放帧：系数放大（字号由整体缩放承担）。
      expect(
        session.moveTo(
          const NoteGeometry(centerX: 0.4, centerY: 0.3, scale: 1.8),
        ),
        isNotNull,
      );
      // 会话中逐帧不入史、不入队。
      expect(historyLength(), 0);
      expect(sink.saved, isEmpty);

      session.end();
      expect(historyLength(), 1);
      expect(
        notes().first.geometry,
        const NoteGeometry(centerX: 0.4, centerY: 0.3, scale: 1.8),
      );

      editor().undo();
      expect(notes().first.geometry, const NoteGeometry());
      editor().redo();
      expect(
        notes().first.geometry,
        const NoteGeometry(centerX: 0.4, centerY: 0.3, scale: 1.8),
      );
    });

    test('写后真实落点回读 = 模块钳制后的几何', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);
      final session = editor().beginNoteGeometryDrag(0);
      final landing = session.moveTo(
        const NoteGeometry(centerX: 5, centerY: -1, scale: 50),
      );
      expect(
        landing,
        const NoteGeometry(centerX: 1, centerY: 0, scale: noteMaxScale),
      );
      expect(notes().single.geometry, landing);
      session.end();
    });

    test('拖回原位收口：无净变化 = 不入史', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);
      final session = editor().beginNoteGeometryDrag(0);
      session.moveTo(const NoteGeometry(centerX: 0.8, centerY: 0.4));
      session.moveTo(const NoteGeometry(centerX: 0.5, centerY: 0.12));
      session.end();
      expect(
        notes().single.geometry,
        const NoteGeometry(centerX: 0.5, centerY: 0.12),
      );
      expect(historyLength(), 0);
    });

    test('会话唯一性：新会话顶替后旧会话逐帧与收口皆失效', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);

      final stale = editor().beginNoteGeometryDrag(0);
      final current = editor().beginNoteGeometryDrag(0);
      expect(
        stale.moveTo(const NoteGeometry(centerX: 0.9, centerY: 0.9)),
        isNull,
      );
      expect(
        current.moveTo(const NoteGeometry(centerX: 0.9, centerY: 0.9)),
        isNotNull,
      );
      stale.end();
      expect(historyLength(), 0);
      current.end();
      expect(historyLength(), 1);
    });

    test('会话索引越界抛 RangeError', () {
      restore();
      expect(() => editor().beginNoteGeometryDrag(0), throwsRangeError);
    });
  });

  group('不受锁定分段门禁（锁只护分段结构）', () {
    test('锁定分段开启 → 贴纸几何照常写定并单步入史；会话逐帧照常', () {
      restore(notes: const [NoteSticker(startMs: 1000, endMs: 5000)]);
      container.read(layoutLockedProvider.notifier).toggle();

      final outcome = editor().submit(
        const SetNoteGeometry(
          index: 0,
          geometry: NoteGeometry(centerX: 0.3, centerY: 0.4),
        ),
      );
      expect(outcome.applied, isTrue);
      expect(
        notes().single.geometry,
        const NoteGeometry(centerX: 0.3, centerY: 0.4),
      );
      expect(historyLength(), 1);

      final session = editor().beginNoteGeometryDrag(0);
      expect(
        session.moveTo(const NoteGeometry(centerX: 0.2, centerY: 0.2)),
        isNotNull,
      );
      session.end();
      expect(historyLength(), 2);
    });
  });
}
