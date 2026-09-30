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

/// 记录型保存 sink（段级折叠断言用：几何提交不得改写备注值）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「备注值道与会话 store」模块 seam 直测：备注列表作为**独立值道**
/// 接入标注编辑模块（自身 store/Notifier + 快照独立 lane + 段级折叠备注臂
/// + 恢复装载就位）。模块是唯一写入者（替换/复位/恢复三个私有入口，
/// library 私有——模块外无写缝）；备注 verb 族（插入/删除/…）归 08 起，
/// 本文件不涉及。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const twenty = Duration(seconds: 20);

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

  const List<NoteSticker> seed = [
    NoteSticker(startMs: 1000, endMs: 9000, text: '这里注意手'),
    NoteSticker(startMs: 12000, endMs: 20000, locked: true),
  ];

  group('备注值道（只读 provider 面）', () {
    test('会话 store 缺省为空列表', () {
      expect(notes(), isEmpty);
    });

    test('装载载荷就位（恢复随打开装载）；空载荷不触碰、空列表装载为空', () {
      editor().restoreDocument(const AnnotationRestoreDocument(notes: seed));
      expect(notes(), seed);

      // 空载荷整体 no-op，不触碰既有备注 lane。
      editor().restoreDocument(const AnnotationRestoreDocument());
      expect(notes(), seed);

      // 空列表载荷 = 装载为空（旧文件缺省段读空）。
      editor().restoreDocument(const AnnotationRestoreDocument(notes: []));
      expect(notes(), isEmpty);
    });
  });

  group('复位与恢复路径（换视频清空、装载还原）', () {
    test('resetForVideo 复位备注列表为空', () {
      editor().restoreDocument(const AnnotationRestoreDocument(notes: seed));
      expect(notes(), seed);

      editor().resetForVideo(total);
      expect(notes(), isEmpty);
    });

    test('复位后重新装载还原', () {
      editor().restoreDocument(const AnnotationRestoreDocument(notes: seed));
      editor().resetForVideo(total);
      editor().restoreDocument(const AnnotationRestoreDocument(notes: seed));
      expect(notes(), seed);
    });
  });

  group('与几何操作互不干扰（备注值道独立性回归）', () {
    test('装载备注后增/移分段线不改备注列表、保存 diff 不带备注段', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          notes: seed,
        ),
      );
      sink.saved.clear();

      editor().submit(AddSegmentLine(at: twenty));
      expect(notes(), seed);

      editor().submit(
        const MoveSegmentLine(index: 0, to: Duration(seconds: 30)),
      );
      expect(notes(), seed);

      // 备注未被无关几何提交改写：几何提交的保存 diff 备注臂为 null
      //（备注前后相等，折叠不携段值）。
      expect(sink.saved.length, 2);
      for (final diff in sink.saved) {
        expect(diff.notes, isNull);
      }
    });
  });

  group('备注值类型相等与哈希（覆盖全部字段）', () {
    const base = NoteSticker(
      startMs: 1000,
      endMs: 9000,
      text: '下一拍转身',
      locked: true,
      geometry: NoteGeometry(centerX: 0.4, centerY: 0.3, scale: 1.5),
    );

    test('全字段相同 → 相等且哈希相同', () {
      final twin = NoteSticker(
        startMs: base.startMs,
        endMs: base.endMs,
        text: base.text,
        locked: base.locked,
        geometry: base.geometry,
      );
      expect(base, twin);
      expect(base.hashCode, twin.hashCode);
    });

    test('任一字段不同 → 不等（逐字段抽样）', () {
      final variants = <NoteSticker>[
        base.copyWith(startMs: base.startMs + 1),
        base.copyWith(endMs: base.endMs + 1),
        base.copyWith(text: '改'),
        base.copyWith(locked: false),
        base.copyWith(geometry: const NoteGeometry(scale: 2.0)),
      ];
      for (final variant in variants) {
        expect(variant, isNot(base), reason: '字段变体应不等：$variant');
      }
    });
  });

  group('段值装配与净变化判定（快照备注 lane）', () {
    test('十秒处增线提交后 diff 备注臂为空（装载值前后相等）', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          notes: seed,
        ),
      );
      sink.saved.clear();
      editor().submit(AddSegmentLine(at: ten));
      expect(sink.saved.single.notes, isNull);
    });
  });
}
