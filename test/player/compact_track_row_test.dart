import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart'
    show contentHasherProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        annotationEditorProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/load_gate.dart'
    show loadGateActiveProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowId, TrackRowTable;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;
import '../helpers/device_viewport.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/pump_past_marquee.dart';

/// 紧凑档空轨不占行（整页组合点）：档位 × 两轨当前空否 → 轨道带实际行集。
/// 只断言外部行为——行背景（行键）、片头标签、整带高、以及「落一条即出现 /
/// 删最后一条即离场」与装载门；行级命中的剪裁口径见 track_row_table_test /
/// track_hit_resolution_test（纯件直测）。
void main() {
  final source = Uri.file('/videos/a.mp4');

  const band = Key('track_band');
  const noteRow = Key('track_notes');
  const mirrorRow = Key('track_mirror');
  const practiceRow = Key('track_practice');
  const learningRow = Key('track_learning');
  const beatRow = Key('track_beat');
  const handleRow = Key('track_handle_strip_row');
  const noteLabel = ValueKey('track_prefix_label_note');
  const mirrorLabel = ValueKey('track_prefix_label_localMirror');
  const learningLabel = ValueKey('track_prefix_label_learning');

  final normalHeight = TrackRowTable.normal.totalHeight;

  /// 紧凑档某行不在场时的整带高：normal 全行集剪掉这些行。
  double bandHeightWithout(Set<TrackRowId> rows) =>
      TrackRowTable.normal.withoutRows(rows).totalHeight;

  /// 两轨皆空（剪掉空备注轨与空局部镜像轨）。
  final trimmedHeight = bandHeightWithout(const {
    TrackRowId.note,
    TrackRowId.localMirror,
  });

  /// 备注轨在场、镜像轨空（剪掉空局部镜像轨）。
  final noteOnlyHeight = bandHeightWithout(const {TrackRowId.localMirror});

  /// 镜像轨在场、备注轨空（剪掉空备注轨）。
  final mirrorOnlyHeight = bandHeightWithout(const {TrackRowId.note});

  Future<ProviderContainer> pumpPlayer(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          contentHasherProvider.overrideWithValue(const FixedHasher('vid-a')),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          videoDocumentCoordinatorProvider.overrideWith(
            (ref, videoId) =>
                VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );
  }

  /// 进入编辑态（控制层展开即编辑面，轨道带与控制层同一装配）。
  Future<ProviderContainer> pumpEditSurface(WidgetTester tester) async {
    final container = await pumpPlayer(tester);
    container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.editing);
    await tester.pump();
    await pumpPastMarquee(tester);
    expect(find.byKey(band), findsOneWidget);
    return container;
  }

  double bandHeight(WidgetTester tester) =>
      tester.getSize(find.byKey(band)).height;

  /// 紧凑档四档（现有四档全文落紧凑档）：每个档位两向都按同一条规则剪裁。
  for (final (tier, landscape) in const [
    (ViewportTier.small, true),
    (ViewportTier.compact, false),
    (ViewportTier.regular, true),
    (ViewportTier.large, false),
  ]) {
    final label = '${tier.name}${landscape ? ' 横屏' : ' 竖屏'}';
    testWidgets('紧凑档 $label：两轨皆空时行背景、片头标签一并离场，其余行照旧', (tester) async {
      useNamedViewport(tester, tier, landscape: landscape);
      await pumpEditSurface(tester);

      expect(find.byKey(noteRow), findsNothing);
      expect(find.byKey(mirrorRow), findsNothing);
      expect(find.byKey(noteLabel), findsNothing);
      expect(find.byKey(mirrorLabel), findsNothing);
      expect(find.byKey(learningRow), findsOneWidget);
      expect(find.byKey(beatRow), findsOneWidget);
      expect(find.byKey(handleRow), findsOneWidget);
      // 片头标签列与行集同序收缩：最顶那行的标签是「分段」。
      expect(find.byKey(learningLabel), findsOneWidget);
      // 整带高 = 剪裁后逐行行高之和 + 行间间隙。
      expect(bandHeight(tester), trimmedHeight);
      // 省下的两行让下一行顶到带顶：学习段轨行顶 == 带顶。
      expect(
        tester.getTopLeft(find.byKey(learningRow)).dy,
        tester.getTopLeft(find.byKey(band)).dy,
      );
    });
  }

  testWidgets('紧凑档落下第一条备注该轨立刻在场、删掉最后一条立刻离场', (tester) async {
    useNamedViewport(tester, ViewportTier.small, landscape: true);
    final container = await pumpEditSurface(tester);
    expect(find.byKey(noteRow), findsNothing);

    final editor = container.read(annotationEditorProvider);
    expect(
      editor.submit(const InsertNote(at: Duration(seconds: 2))).applied,
      isTrue,
    );
    await tester.pump();
    expect(container.read(noteStickersProvider), hasLength(1));
    expect(find.byKey(noteRow), findsOneWidget);
    expect(find.byKey(noteLabel), findsOneWidget);
    // 备注轨（36）+ 学习段（48）+ 节拍（24）+ 手柄带（30）+ 10 × 3。
    expect(
      bandHeight(tester),
      noteOnlyHeight,
      reason: '备注轨在场、空局部镜像轨不占行',
    );

    expect(editor.submit(const RemoveNote(index: 0)).applied, isTrue);
    await tester.pump();
    expect(container.read(noteStickersProvider), isEmpty);
    expect(find.byKey(noteRow), findsNothing);
    expect(bandHeight(tester), trimmedHeight);
  });

  testWidgets('紧凑档落下第一个局部镜像片段该轨立刻在场；「局部镜像」开关不影响力', (tester) async {
    useNamedViewport(tester, ViewportTier.small, landscape: true);
    final container = await pumpEditSurface(tester);
    expect(find.byKey(mirrorRow), findsNothing);

    final editor = container.read(annotationEditorProvider);
    expect(
      editor
          .submit(const AddLocalMirrorFragment(at: Duration(seconds: 2)))
          .applied,
      isTrue,
    );
    await tester.pump();
    expect(container.read(localMirrorFragmentsProvider), hasLength(1));
    expect(find.byKey(mirrorRow), findsOneWidget);
    expect(find.byKey(mirrorLabel), findsOneWidget);
    // 镜像轨（30）+ 学习段（48）+ 节拍（24）+ 手柄带（30）+ 10 × 3。
    expect(
      bandHeight(tester),
      mirrorOnlyHeight,
      reason: '镜像轨在场、空备注轨不占行',
    );

    // 扳开关不改轨道的有无（只跟着片段数走）。
    container.read(localMirrorEnabledProvider.notifier).replace(false);
    await tester.pump();
    expect(find.byKey(mirrorRow), findsOneWidget);

    expect(
      editor.submit(const RemoveLocalMirrorFragment(index: 0)).applied,
      isTrue,
    );
    await tester.pump();
    expect(container.read(localMirrorFragmentsProvider), isEmpty);
    expect(find.byKey(mirrorRow), findsNothing);
    expect(bandHeight(tester), trimmedHeight);

    // 开着开关也不凭空出现。
    container.read(localMirrorEnabledProvider.notifier).replace(true);
    await tester.pump();
    expect(find.byKey(mirrorRow), findsNothing);
  });

  testWidgets('紧凑档装载未完成按该态全行集渲染，装载落定后按两轨空否剪裁', (tester) async {
    useNamedViewport(tester, ViewportTier.small, landscape: true);
    final container = await pumpEditSurface(tester);
    expect(find.byKey(noteRow), findsNothing);

    container.read(loadGateActiveProvider.notifier).begin();
    await tester.pump();
    expect(find.byKey(noteRow), findsOneWidget);
    expect(find.byKey(mirrorRow), findsOneWidget);
    expect(bandHeight(tester), normalHeight);

    container.read(loadGateActiveProvider.notifier).settle();
    await tester.pump();
    expect(find.byKey(noteRow), findsNothing);
    expect(find.byKey(mirrorRow), findsNothing);
    expect(bandHeight(tester), trimmedHeight);
  });

  testWidgets('紧凑档对比态：空备注轨同样不占行，练习视频轨照旧常驻', (tester) async {
    useNamedViewport(tester, ViewportTier.small, landscape: true);
    final container = await pumpPlayer(tester);
    container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareEditing);
    await tester.pump();
    await pumpPastMarquee(tester);

    expect(find.byKey(noteRow), findsNothing);
    expect(find.byKey(noteLabel), findsNothing);
    expect(find.byKey(practiceRow), findsOneWidget);
    expect(find.byKey(learningRow), findsOneWidget);
    expect(find.byKey(beatRow), findsOneWidget);
    // 对比行集本就没有局部镜像轨与手柄带行。
    expect(find.byKey(mirrorRow), findsNothing);
    expect(find.byKey(handleRow), findsNothing);
    // 练习视频轨（48）+ 学习段（48）+ 节拍（24）+ 10 × 2。
    expect(
      bandHeight(tester),
      TrackRowTable.compare.withoutRows(const {TrackRowId.note}).totalHeight,
    );
  });

  testWidgets('紧凑档对比态：有备注时备注轨在场（裁剪只跟片段数走）', (tester) async {
    useNamedViewport(tester, ViewportTier.small, landscape: true);
    final container = await pumpPlayer(tester);
    // 对比态只读，备注先在可编辑态落下。
    expect(
      container
          .read(annotationEditorProvider)
          .submit(const InsertNote(at: Duration(seconds: 2)))
          .applied,
      isTrue,
    );
    container
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareEditing);
    await tester.pump();
    await pumpPastMarquee(tester);

    expect(find.byKey(noteRow), findsOneWidget);
    expect(find.byKey(practiceRow), findsOneWidget);
    // 对比行集全行集（186）里备注轨在场。
    expect(bandHeight(tester), TrackRowTable.compare.totalHeight);
  });

  for (final landscape in const [false, true]) {
    testWidgets(
      '平板视口${landscape ? '横屏' : '竖屏'}（常规档）：空轨仍常驻，整带高与今天逐位相同',
      (tester) async {
        useNamedViewport(
          tester,
          ViewportTier.tablet,
          landscape: landscape,
        );
        await pumpEditSurface(tester);

        expect(find.byKey(noteRow), findsOneWidget);
        expect(find.byKey(mirrorRow), findsOneWidget);
        expect(find.byKey(noteLabel), findsOneWidget);
        expect(find.byKey(mirrorLabel), findsOneWidget);
        expect(find.byKey(learningRow), findsOneWidget);
        expect(find.byKey(beatRow), findsOneWidget);
        expect(find.byKey(handleRow), findsOneWidget);
        expect(bandHeight(tester), normalHeight);
        // 常规档整带（208）仍收在视口内，不溢出。
        expect(tester.takeException(), isNull);
        final dpr = tester.view.devicePixelRatio;
        final viewport = Offset.zero &
            Size(
              tester.view.physicalSize.width / dpr,
              tester.view.physicalSize.height / dpr,
            );
        final bandRect = tester.getRect(find.byKey(band));
        expect(bandRect.left, greaterThanOrEqualTo(viewport.left));
        expect(bandRect.right, lessThanOrEqualTo(viewport.right));
        expect(bandRect.top, greaterThanOrEqualTo(viewport.top));
        expect(bandRect.bottom, lessThanOrEqualTo(viewport.bottom));
      },
    );
  }
}
