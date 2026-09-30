import 'package:dance_learning_app/beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
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

/// 半拍线落点解析模块面直测：交互命令提交时模块内解析就近
/// 半拍格点（相邻拍点中点；占位均匀网格照常派生）+ 合法域（时间线开区间）
/// 检查——解析触界或区间外 = EditNoop 静默（不入史不入盘）；拖动会话
/// moveTo 返回写后真实落点；步进原始目标提交经模块解析幂等。
class _RecordingSaveSink implements AnnotationSaveSink {
  final List<AnnotationSectionDiff> saved = [];

  @override
  void save(AnnotationSectionDiff diff) => saved.add(diff);

  @override
  Future<void> flush() async {}
}

void main() {
  const total = Duration(minutes: 1);
  // 就绪网格与占位同值：0.5s 一拍 → 半拍格点 = 0.25s + 0.5k。
  const ten30 = Duration(seconds: 10, milliseconds: 300);
  const ten25 = Duration(seconds: 10, milliseconds: 250);

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

  group('AddHalfBeatLine：提交时模块内半拍格点吸附', () {
    test('就绪网格：任意请求位置写入就近半拍格点（等距取靠后）', () {
      injectReadyGrid();
      final outcome = editor().submit(AddHalfBeatLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        ten25,
        reason: '10s+300ms → 就近半拍格点 10.25s（距 10.25s 50ms、'
            '距 10.75s 450ms）',
      );
    });

    test('占位均匀网格：半拍格点照常派生（与就绪同语义）', () {
      // 占位态（未注入就绪网格）：占位 120bpm 均匀网格，半拍位 =
      // 250ms 倍数，插入照常吸附（「对齐落点」占位语义不变）。
      final outcome = editor().submit(AddHalfBeatLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        ten25,
      );
    });

    test('就绪但网格空：派生格回落占位均匀格，半拍格点照常派生', () {
      // 与分段线 resolver（就绪但空 = 无吸附依据直通）刻意不同：半拍
      // 落点消费派生格（[beatGridProvider] 就绪但空拍点时回落占位格），
      // 「占位照常派生」语义随行。直测钉死该态。
      container.read(beatTrackStateProvider.notifier).replace(
            BeatTrackState.ready(
              marker_doc.BeatGrid(
                model: 'fake.onnx',
                fps: 100,
                generatedAt: DateTime.utc(2024),
                beats: const [],
              ),
            ),
          );

      final outcome = editor().submit(AddHalfBeatLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        ten25,
      );
    });

    test('解析结果区间外静默：EditNoop、不入史、不入盘、状态未动', () {
      // 有界网格吸附候选止于末拍前一拍、不会落开区间外；区间外静默以占位
      // 无界网格钉死（61s 就近半拍格点 61.25s、60s 等距取靠后 60.25s，
      // 均在开区间 (0, 60s) 外）。
      final timelineBefore = container.read(annotationTimelineProvider);

      final outside = editor().submit(
        AddHalfBeatLine(at: const Duration(seconds: 61)),
      );
      final beyond = editor().submit(AddHalfBeatLine(at: total));

      expect(outside, isA<EditNoop>());
      expect(beyond, isA<EditNoop>());
      expect(container.read(annotationTimelineProvider), timelineBefore);
      expect(container.read(annotationEditHistoryProvider).length, 0);
      expect(sink.saved, isEmpty);
    });
  });

  group('MoveHalfBeatLine：提交时模块内落点解析（步进原始目标幂等）', () {
    test('原始目标恰为半拍格点：解析幂等、原样落位', () {
      injectReadyGrid();
      editor().submit(AddHalfBeatLine(at: ten25));

      final outcome = editor().submit(
        MoveHalfBeatLine(
          index: 0,
          to: const Duration(seconds: 10, milliseconds: 750),
        ),
      );

      expect(outcome.applied, isTrue);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        const Duration(seconds: 10, milliseconds: 750),
      );
    });

    test('非格点原始目标吸附落位；解析结果落自身位置 = 同位 no-op', () {
      injectReadyGrid();
      editor().submit(AddHalfBeatLine(at: ten25));
      editor().submit(
        AddHalfBeatLine(at: const Duration(seconds: 10, milliseconds: 750)),
      );
      // 解析 10.3s → 10.25s = 线自身当前位置 → 写入同值、快照相等 = EditNoop。
      final outcome = editor().submit(MoveHalfBeatLine(index: 0, to: ten30));

      expect(outcome, isA<EditNoop>());
      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        ten25,
      );
    });
  });

  group('拖动会话：moveTo 返回写后真实落点', () {
    test('逐帧请求原始指针位置，返回吸附后半拍格点驱动预览', () {
      injectReadyGrid();
      editor().submit(
        AddHalfBeatLine(at: const Duration(seconds: 10, milliseconds: 750)),
      );
      final session = editor().beginHalfBeatDrag(0);

      // 10.3s → 就近半拍格点 10.25s，写后真实落点返回驱动预览。
      expect(session.moveTo(ten30), ten25);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        ten25,
      );

      // 同位帧：解析落自身位置、无净变化返回 null 且不写。
      expect(session.moveTo(ten30), isNull);
      session.end();
    });

    test('吸附后越邻钳制丢弃：返回 null、线不动', () {
      injectReadyGrid();
      editor().submit(AddHalfBeatLine(at: ten25));
      editor().submit(
        AddHalfBeatLine(at: const Duration(seconds: 10, milliseconds: 750)),
      );
      final session = editor().beginHalfBeatDrag(0);

      // 10.6s 吸附 10.75s = 右邻位置 → moveHalfBeatLine 钳制丢弃。
      expect(
        session.moveTo(const Duration(seconds: 10, milliseconds: 600)),
        isNull,
      );
      expect(
        container.read(annotationTimelineProvider).halfBeatLines[0].position,
        ten25,
      );
      session.end();
    });
  });

  group('异常态：无网格语义自由落点（经合法域检查后直通）', () {
    test('异常态请求位置不吸附、原样写入', () {
      container
          .read(beatTrackStateProvider.notifier)
          .replace(const BeatTrackState.error());

      final outcome = editor().submit(AddHalfBeatLine(at: ten30));

      expect(outcome.applied, isTrue);
      expect(
        container
            .read(annotationTimelineProvider)
            .halfBeatLines
            .single
            .position,
        ten30,
        reason: '异常态吸附停用（既有语义），请求位置经开区间检查后直通',
      );
    });
  });
}
