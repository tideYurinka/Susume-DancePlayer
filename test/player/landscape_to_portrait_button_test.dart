import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart'
    show VideoDocumentCoordinator;
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;

import 'dart:math' as math;

import 'package:dance_learning_app/player/control_layer.dart'
    show
        kLandscapeToPortraitButtonHitKey,
        kLandscapeToPortraitButtonKey,
        kPortraitRotateButtonKey;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetDenseMinSize, kHitTargetMinSize;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/track_band.dart' show TrackBand;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/android_camera_platform.dart';
import '../helpers/beat_test_seam.dart' show hangingBeatPipeline;
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/pump_past_marquee.dart';
import '../helpers/semantics_assertions.dart';
import '../helpers/device_viewport.dart';

/// 横屏编辑面「转为竖屏」矩形钮：
/// 锚由**系统栏内缩**推出——左 = 左内缩 + 间隙，与返回键、顶栏同一条内缩线；
/// 压在画面上是已接受代价（半透明底衬保证可读），只避开数拍数字默认位置与
/// 轨道带。点它锁竖屏并粘住；顶栏返回与系统返回都不承担转屏。
///
/// 本文件钉**用户可见面**：存在性与落位（尺寸、左缘 = 左内缩 + 间隙、右缘 ≤
/// 数拍数字左缘、底边不越轨道带上缘、矩形完整含于渲染 Stack 不被裁剪）、显隐
/// 门禁（控制层展开、非录制、横屏屏、对比态共用）、点击锁竖屏、返回键 tooltip
/// 与退出行为。落位断言一律写关系式，不以单一设备的绝对坐标为期望值。
void main() {
  /// 真机横屏基准视口：2736 × 1264 @3.5 = 781.7 × 361.1dp。
  void setLandscapeView(
    WidgetTester tester, {
    double leftInset = 0,
    double topInset = 0,
  }) {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    if (leftInset != 0 || topInset != 0) {
      tester.view.padding = FakeViewPadding(
        left: leftInset * 3.5,
        top: topInset * 3.5,
      );
    }
    addTearDown(tester.view.reset);
  }

  /// 真机竖屏基准视口（对照组）：1264 × 2736 @3.5 = 361.1 × 781.7dp。
  void setPortraitView(WidgetTester tester) {
    useNamedViewport(tester, ViewportTier.compact);
  }

  Future<FakeSystemUi> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
    Widget Function(Widget player)? wrap,
  }) async {
    final fake = systemUi ?? FakeSystemUi();
    final source = Uri.file('/videos/a.mp4');
    final player = PlayerPage(source: source);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
          cameraCaptureProvider.overrideWithValue(FakeCameraCaptureService()),
          androidCameraPlatform(),
          systemUiControllerProvider.overrideWithValue(fake),
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
        child: MaterialApp(home: wrap == null ? player : wrap(player)),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// 横屏单击画面唤出控制层（等双击判定窗口过）。
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  Finder rotateButton() => find.byKey(kLandscapeToPortraitButtonKey);

  /// 当前视口尺寸（dp）。
  Size screenOf(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  /// 离 [finder] 最近的 `Stack` 祖先的矩形（全局坐标）——用于钉住钮的渲染点
  /// 在全屏 Stack 内、而不是被中带小 Stack 裁剪。
  Rect nearestStackRect(WidgetTester tester, Finder finder) {
    Element? nearest;
    tester.element(finder).visitAncestorElements((ancestor) {
      if (ancestor.widget is Stack) {
        nearest = ancestor;
        return false;
      }
      return true;
    });
    expect(nearest, isNotNull, reason: '钮必须在某个 Stack 内');
    final box = nearest!.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  group('锚与落位', () {
    testWidgets('单画面 16:9：尺寸 62 × 32、返回键正下方、左缘 = 左内缩 + 间隙', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      expect(find.text('转为竖屏'), findsOneWidget);
      final topBar = tester.getRect(
        find.byKey(const Key('control_layer_top_bar')),
      );
      final rect = tester.getRect(rotateButton());
      expect(rect.width, 62);
      expect(rect.height, 32);
      expect(rect.top, topBar.bottom + 4, reason: '返回键正下方');
      expect(rect.left, 4, reason: 'padding = 0：左 = 左内缩 0 + 间隙 4');
    });

    testWidgets('号机左内缩 39.4dp：左缘 = 43.4dp，与返回键同处一列', (tester) async {
      setLandscapeView(tester, leftInset: 39.4);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final back = tester.getRect(find.byKey(const Key('control_layer_back')));
      final rect = tester.getRect(rotateButton());
      expect(rect.left, closeTo(39.4 + 4, 0.01), reason: '左 = 左内缩 + 间隙 4');
      expect(rect.left, closeTo(back.left, 0.01), reason: '与返回键同一条内缩线（同一列）');
      expect(rect.top, closeTo(56, 0.01), reason: '返回键正下方（顶内缩 0）');
    });

    testWidgets('底边不越过轨道带上缘', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final rect = tester.getRect(rotateButton());
      final trackBand = tester.getRect(find.byType(TrackBand));
      expect(rect.bottom, lessThanOrEqualTo(trackBand.top));
    });

    testWidgets('渲染点在全屏 Stack 内：钮完整含于最近 Stack 祖先（旧锚被中带小 Stack 裁掉下半截）', (
      tester,
    ) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      // 旧锚把钮放在横屏中带那个 Stack（高 = 余数，被设置条+轨道带挤到
      // < 36dp）里，32dp 高的钮下半截被 Stack 默认裁剪吃掉——真机表现为
      // 「上半截可见可点、下半截不显示」。渲染点移到全屏 Stack 后，最近
      // Stack 祖先即全屏 Stack，该裁剪不可能再发生。
      final screen = screenOf(tester);
      final ancestor = nearestStackRect(tester, rotateButton());
      expect(ancestor.left, closeTo(0, 0.01));
      expect(ancestor.top, closeTo(0, 0.01));
      expect(ancestor.width, closeTo(screen.width, 0.01));
      expect(
        ancestor.height,
        closeTo(screen.height, 0.01),
        reason: '最近 Stack 祖先 = 全屏 Stack，不是中带小 Stack',
      );

      final rect = tester.getRect(rotateButton());
      expect(rect.left, greaterThanOrEqualTo(ancestor.left));
      expect(rect.top, greaterThanOrEqualTo(ancestor.top));
      expect(rect.right, lessThanOrEqualTo(ancestor.right));
      expect(
        rect.bottom,
        lessThanOrEqualTo(ancestor.bottom),
        reason: '钮矩形完整含于最近 Stack 祖先内，无裁剪',
      );
    });

    testWidgets('与数拍数字默认位置不相交（数字在 x ≈ 130–190）', (tester) async {
      setLandscapeView(tester, leftInset: 39.4);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final rect = tester.getRect(rotateButton());
      expect(rect.right, lessThanOrEqualTo(130), reason: '整条在数字左缘之左');
    });
  });

  group('命中盒', () {
    /// 命中矩形（视觉矩形透明外扩后的可点域）。
    Rect hitRect(WidgetTester tester) =>
        tester.getRect(find.byKey(kLandscapeToPortraitButtonHitKey));

    testWidgets('命中矩形：宽 ≥ 通行下限、高达到密集区兜底下限；视觉矩形 62 × 32 逐位不变', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final hit = hitRect(tester);
      expect(
        hit.width,
        greaterThanOrEqualTo(kHitTargetMinSize),
        reason: '命中宽 ≥ 通行下限 48',
      );
      expect(hit.height, kHitTargetDenseMinSize, reason: '命中高 = 密集区兜底 44');
      final rect = tester.getRect(rotateButton());
      final trackBand = tester.getRect(find.byType(TrackBand));
      expect(rect.size, const Size(62, 32), reason: '视觉矩形逐位不变');
      expect(hit.left, rect.left, reason: '命中盒与视觉矩形同左缘');
      expect(hit.right, rect.right, reason: '命中盒与视觉矩形同右缘');
      // 向下探到 min(兜底余量, 轨道带上缘) 为止，其余向上补足。
      final growDown = math.min(
        kHitTargetDenseMinSize - rect.height,
        trackBand.top - rect.bottom,
      );
      expect(
        hit.bottom,
        closeTo(rect.bottom + growDown, 0.01),
        reason: '命中盒向下探到轨道带上缘为止',
      );
      expect(
        hit.top,
        closeTo(rect.top - (12 - growDown), 0.01),
        reason: '其余外扩量向上补足',
      );
    });

    testWidgets('命中盒底边不越过轨道带上缘；与返回键命中域的重叠 ≤ 2dp（返回键图标中心无碍）', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      final hit = hitRect(tester);
      final trackBand = tester.getRect(find.byType(TrackBand));
      expect(
        hit.bottom,
        lessThanOrEqualTo(trackBand.top),
        reason: '命中盒不越轨道带上缘',
      );
      final back = tester.getRect(find.byKey(const Key('control_layer_back')));
      final overlapTop = math.max(hit.top, back.top);
      final overlapBottom = math.min(hit.bottom, back.bottom);
      expect(
        math.max(0.0, overlapBottom - overlapTop),
        lessThanOrEqualTo(2.5),
        reason: '命中盒上探只与返回键命中域底缘重叠 ≤ 2dp',
      );
    });

    for (final scale in [1.3, 1.6, 2.0]) {
      testWidgets('大字号 $scale：文字单行、完整落在钮内不被裁', (tester) async {
        setLandscapeView(tester);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpPlayer(
          tester,
          engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
        );
        await openEditor(tester);

        // 全播放器在 1.6+ 下别处仍有整行溢出（倍率定宽槽等已知项），
        // 沿用既有契约测试的口径：1.3 断言无溢出，1.6+ 排干已知异常后
        // 只钉这枚钮的文字单行、不换行、完整可见。
        if (scale == 1.3) {
          expect(tester.takeException(), isNull, reason: '1.3× 下无溢出异常');
        } else {
          while (tester.takeException() != null) {}
        }
        final rect = tester.getRect(rotateButton());
        final text = tester.getRect(find.text('转为竖屏'));
        expect(
          text.height,
          lessThanOrEqualTo(rect.height),
          reason: '字号 $scale：文字单行且高不超过钮（换行即被裁）',
        );
        expect(
          text.width,
          lessThanOrEqualTo(rect.width + 0.5),
          reason: '字号 $scale：文字缩放后宽不超过钮',
        );
        expect(
          text.top,
          greaterThanOrEqualTo(rect.top - 0.5),
          reason: '字号 $scale：文字上缘在钮内',
        );
        expect(
          text.bottom,
          lessThanOrEqualTo(rect.bottom + 0.5),
          reason: '字号 $scale：文字下缘在钮内（不被裁）',
        );
      });
    }
  });

  group('显隐门禁', () {
    testWidgets('控制层收起时不出现', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      expect(rotateButton(), findsNothing, reason: '观看态不出现');

      await openEditor(tester);
      expect(rotateButton(), findsOneWidget);

      containerOf(tester).read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      expect(find.byKey(const Key('control_layer')), findsNothing);
      expect(rotateButton(), findsNothing, reason: '收起后不出现');
    });

    testWidgets('竖屏编辑面不出现（那枚无字图标在场）', (tester) async {
      setPortraitView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      expect(rotateButton(), findsNothing);
      expect(find.byKey(kPortraitRotateButtonKey), findsOneWidget);
    });

    testWidgets('录制中（含准备期）不出现', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);
      expect(rotateButton(), findsOneWidget);

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.recording);
      await tester.pump();
      expect(rotateButton(), findsNothing, reason: '录制中不出现');

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.preparing);
      await tester.pump();
      expect(rotateButton(), findsNothing, reason: '准备期同样不出现');

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.idle);
      await tester.pump();
      expect(rotateButton(), findsOneWidget, reason: '回待录态恢复');
    });

    testWidgets('对比练习态共用同一枚', (tester) async {
      setLandscapeView(tester);
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      containerOf(tester)
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.compareEditing);
      await pumpPastMarquee(tester);

      expect(find.byKey(const Key('control_layer')), findsOneWidget);
      expect(rotateButton(), findsOneWidget);
      expect(
        tester.getRect(rotateButton()).right,
        lessThanOrEqualTo(130),
        reason: '对比态与单画面共用同一锚（贴左、不碰数拍数字）',
      );
      // 对比态返回只退对比态回单画面，tooltip 与之相符。
      expect(find.byTooltip('退出对比'), findsOneWidget);
      expect(find.byTooltip('返回来源页'), findsNothing);
    });
  });

  group('转回竖屏与返回', () {
    testWidgets('点它锁竖屏一次并粘住：此后不再请求跟随、收起零方向副作用', (tester) async {
      setLandscapeView(tester);
      final systemUi = await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);
      expect(systemUi.lockPortraitCount, 0, reason: '进编辑面零方向锁');

      await tester.tap(rotateButton());
      await tester.pump();
      expect(systemUi.lockPortraitCount, 1, reason: '点一次锁竖屏');
      expect(systemUi.lockLandscapeCount, 0);

      // 粘性：此后不再请求跟随，收起控制层不解除锁定。
      containerOf(tester).read(playerSessionProvider.notifier).collapse();
      await tester.pump();
      expect(systemUi.lockPortraitCount, 1, reason: '没有第二次请求');
      expect(systemUi.lockLandscapeCount, 0);
    });

    testWidgets('转屏钮：报按钮角色与名字；读屏激活确实锁竖屏', (tester) async {
      final semantics = tester.ensureSemantics();
      setLandscapeView(tester);
      final systemUi = await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      );
      await openEditor(tester);

      expectButtonSemantics(
        tester,
        kLandscapeToPortraitButtonKey,
        label: '转为竖屏',
      );
      activateBySemantics(tester, kLandscapeToPortraitButtonKey);
      await tester.pump();
      expect(systemUi.lockPortraitCount, 1, reason: '读屏双击转屏钮应真的锁竖屏');
      semantics.dispose();
    });

    testWidgets('顶栏返回键 tooltip 与退出行为一致：按返回退出播放器回来源页，不转屏', (tester) async {
      setLandscapeView(tester);
      final systemUi = FakeSystemUi();
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
        systemUi: systemUi,
        wrap: (player) => _SourcePage(child: player),
      );
      await tester.tap(find.byKey(const Key('open_player')));
      await tester.pumpAndSettle();
      await openEditor(tester);

      expect(find.byTooltip('返回来源页'), findsOneWidget);
      expect(find.byTooltip('返回首页'), findsNothing);

      await tester.tap(find.byKey(const Key('control_layer_back')));
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing, reason: '退出播放器回来源页');
      expect(find.byKey(const Key('source_page')), findsOneWidget);
      expect(systemUi.lockPortraitCount, 0, reason: '返回不承担转屏');
      expect(systemUi.lockLandscapeCount, 0);
    });

    testWidgets('系统返回同样退出播放器回来源页、不转屏', (tester) async {
      setLandscapeView(tester);
      final systemUi = FakeSystemUi();
      await pumpPlayer(
        tester,
        engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
        systemUi: systemUi,
        wrap: (player) => _SourcePage(child: player),
      );
      await tester.tap(find.byKey(const Key('open_player')));
      await tester.pumpAndSettle();
      await openEditor(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byKey(const Key('source_page')), findsOneWidget);
      expect(systemUi.lockPortraitCount, 0, reason: '系统返回不承担转屏');
      expect(systemUi.lockLandscapeCount, 0);
    });
  });
}

/// 来源页：按「打开播放」推出播放页；播放页返回后落回本页。
class _SourcePage extends StatelessWidget {
  const _SourcePage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('source_page'),
      body: Center(
        child: TextButton(
          key: const Key('open_player'),
          onPressed: () =>
              Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => child)),
          child: const Text('打开播放'),
        ),
      ),
    );
  }
}
