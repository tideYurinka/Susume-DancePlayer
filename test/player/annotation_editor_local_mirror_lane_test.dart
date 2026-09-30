import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/annotation_save_orchestrator.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationSaveSinkProvider,
        localMirrorFragmentsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 记录型保存 sink（段级折叠断言用：几何提交不得改写片段值）。
class RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

/// 「局部镜像片段并入标注编辑模块数据道 + 打开恢复水合」模块 seam 直测：
/// 片段列表作为**独立值道**接入模块（自身 store/Notifier + 快照独立 lane +
/// 独立 diff 组 + 恢复水合）——不挂 AnnotationTimeline、不被无关几何操作改动、
/// 打开恢复装载经 [AnnotationEditor.restoreDocument] 就位。片段编辑 verb 族
/// （建/删/整体移/端点拖/启停切换）归 03，本文件不涉及。
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

  List<LocalMirrorFragment> fragments() =>
      container.read(localMirrorFragmentsProvider);

  const List<LocalMirrorFragment> seed = [
    LocalMirrorFragment(startMs: 1000, endMs: 3000),
    LocalMirrorFragment(startMs: 5000, endMs: 9000),
  ];

  group('独立值道接入：store/Notifier + 快照 lane', () {
    test('会话 store 缺省为空列表（提供者就位）', () {
      expect(fragments(), isEmpty);
    });

    test('装载载荷水合进会话 store；缺省空（无 payload）不触碰、不报错', () {
      editor().restoreDocument(
        const AnnotationRestoreDocument(localMirrorFragments: seed),
      );
      expect(fragments(), seed);

      // 空载荷整体 no-op，不触碰既有片段 lane。
      editor().restoreDocument(const AnnotationRestoreDocument());
      expect(fragments(), seed);

      // 空列表载荷 = 装载为空。
      editor().restoreDocument(
        const AnnotationRestoreDocument(localMirrorFragments: []),
      );
      expect(fragments(), isEmpty);
    });
  });

  group('与几何操作互不干扰（回归直测：几何 op 后片段逐位保真）', () {
    test('装载片段后增/移分段线不改动片段列表、保存 diff 不带片段组', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: seed,
        ),
      );
      sink.saved.clear();

      editor().submit(AddSegmentLine(at: twenty));
      expect(fragments(), seed);

      editor().submit(
        const MoveSegmentLine(index: 0, to: Duration(seconds: 30)),
      );
      expect(fragments(), seed);

      // 几何提交的保存 diff 不改片段值（片段未被无关几何改写/丢）。
      expect(sink.saved.length, 2);
      for (final diff in sink.saved) {
        expect(diff.annotations?.localMirrorFragments, seed);
      }
    });

    test('半拍线增删/首尾调整不改动片段列表', () {
      editor().restoreDocument(
        AnnotationRestoreDocument(
          timeline: AnnotationTimeline.wholeVideo(total),
          localMirrorFragments: seed,
        ),
      );
      sink.saved.clear();

      editor().submit(AddHalfBeatLine(at: twenty));
      editor().submit(const SetVideoRange(start: ten, end: twenty));
      expect(fragments(), seed);
    });
  });

  group('段级折叠（foldSectionDiff 空 ⇔ 快照相等护栏已含片段面）', () {
    test('几何提交前后片段值相等 → 保存 diff 携带原片段终值', () {
      editor().restoreDocument(
        const AnnotationRestoreDocument(localMirrorFragments: seed),
      );
      sink.saved.clear();
      editor().submit(AddSegmentLine(at: twenty));
      // 保存 diff 的 annotations 段携带片段原值 = 片段随段整写不丢不删。
      expect(sink.saved.single.annotations?.localMirrorFragments, seed);
    });
  });

  group('换视频全复位清空片段 lane', () {
    test('resetForVideo 复位片段列表为空', () {
      editor().restoreDocument(
        const AnnotationRestoreDocument(localMirrorFragments: seed),
      );
      expect(fragments(), seed);

      editor().resetForVideo(total);
      expect(fragments(), isEmpty);
    });
  });
}
