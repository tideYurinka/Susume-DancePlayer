import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        AnnotationEditor,
        annotationEditHistoryProvider,
        annotationEditorProvider,
        annotationTimelineProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 拖动会话唯一性（会话令牌）：同一时刻只有一个进行中会话，被新会话顶替
/// 的陈旧会话对象在结构上失效——逐帧返回空、收口为空操作。缝 = 模块公开
/// 写入口（五个具名工厂 + moveTo + end）与只读面（时间线现值、历史长度）。
void main() {
  group('拖动会话唯一性（会话令牌）', () {
    late ProviderContainer container;
    late FakePlaybackEngine engine;
    late AnnotationEditor editor;

    setUp(() {
      engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
      container = ProviderContainer(
        overrides: [playbackEngineProvider.overrideWithValue(engine)],
      );
      editor = container.read(annotationEditorProvider);
    });

    tearDown(() => container.dispose());

    AnnotationTimeline timeline() => container.read(annotationTimelineProvider);

    int historyLength() => container.read(annotationEditHistoryProvider).length;

    test('新会话顶替后，陈旧会话逐帧返回空、收口为空操作', () {
      final stale = editor.beginRangeDrag(VideoRangeBoundary.start);
      final current = editor.beginRangeDrag(VideoRangeBoundary.end);

      // 陈旧会话写不进新会话：逐帧返回空、不改变任何状态。
      expect(stale.moveTo(const Duration(seconds: 10)), isNull);
      expect(timeline().rangeStart, Duration.zero);

      // 陈旧会话收口为空操作：不影响进行中的新会话。
      stale.end();

      // 新会话照常工作并一次收口。
      expect(current.moveTo(const Duration(seconds: 30)), isNotNull);
      current.end();
      expect(timeline().rangeEnd, const Duration(seconds: 30));
      expect(historyLength(), 1);
    });

    test('会话被撤销防御性收口后，其后续逐帧返回空', () {
      final session = editor.beginRangeDrag(VideoRangeBoundary.start);
      session.moveTo(const Duration(seconds: 10));
      editor.undo(); // 防御性收口 + 撤销该次拖动
      expect(session.moveTo(const Duration(seconds: 20)), isNull);
      session.end(); // 幂等：不产生第二条历史。
      expect(historyLength(), 0);
    });
  });
}
