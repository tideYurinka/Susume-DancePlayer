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
import 'package:dance_learning_app/player/control_layer.dart'
    show kLandscapeToPortraitButtonKey, kPortraitRotateButtonKey;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentCoordinatorProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kKeyboardFocusHighlight;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/gestures.dart' show HitTestResult;
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// 控制层关键入口的键盘焦点与激活：返回（`control_layer_back`）、
/// 转屏（竖屏 `portrait_rotate_button` / 横屏 `landscape_to_portrait_button`）、
/// 播放开关（`toolbar_play`）可用外接键盘（Enter / Space）激活，且焦点有可见
/// 样式（24% 白内填，画在入口自身材质内，不被粘性头部/浮层遮挡）。
///
/// 本文件钉**用户可见面**：入口可聚焦、焦点反馈颜色已声明、键盘激活后动作
/// 确实发生（返回 = 路由 pop、播放开关 = 引擎播放态翻转、转屏 = 方向锁定）、
/// 无浮层展开时焦点入口命中不被覆盖层截走。触摸路径不改动：指针激活仍走
/// 原手势/按钮回调，本用例只加焦点样式与键盘可达。
void main() {
  /// 测试视口：刻意放宽的**合成档**（非设备基准），实际逻辑尺寸 668 × 1368dp。
  const portraitScreen = Size(668.0, 1368.0);

  /// compact 档横屏（2736 × 1264 @3.5 = 781.7 × 361.1dp）。
  const landscapeScreen = Size(781.7, 361.1);

  void setPortraitView(WidgetTester tester) {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = portraitScreen * 2.0;
    addTearDown(tester.view.reset);
  }

  void setLandscapeView(WidgetTester tester) {
    tester.view.devicePixelRatio = 3.5;
    tester.view.physicalSize = landscapeScreen * 3.5;
    addTearDown(tester.view.reset);
  }

  Future<FakeSystemUi> pumpPlayer(
    WidgetTester tester, {
    required FakePlaybackEngine engine,
    FakeSystemUi? systemUi,
    NavigatorObserver? observer,
  }) async {
    final fake = systemUi ?? FakeSystemUi();
    final source = Uri.file('/videos/a.mp4');
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
        child: MaterialApp(
          navigatorObservers: [?observer],
          // PlayerPage 落在第二路由上：返回动作走 `Navigator.maybePop`，
          // 单路由下 maybePop 不弹、观察器收不到 pop（生产里由系统接管）。
          routes: {
            '/': (_) => const Scaffold(),
            '/player': (_) => PlayerPage(source: source),
          },
          initialRoute: '/player',
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  /// 单击画面唤出控制层（等双击判定窗口过）。
  Future<void> openEditor(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await pumpPastMarquee(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
  }

  /// [key] 所在入口的 Focus 节点（焦点节点长在按钮内部、比 key 所挂按钮
  /// 低一层，故从入口图标/文字处向上取最近祖先 Focus 节点）。
  FocusNode? nodeOfEntry(WidgetTester tester, Key key) {
    final inner = find.descendant(
      of: find.byKey(key),
      matching: find.byWidgetPredicate(
        (widget) => widget is Icon || widget is Text,
      ),
    );
    return Focus.maybeOf(tester.element(inner.first));
  }

  /// 把键盘焦点落到 [key] 所在入口上。
  Future<void> focusEntry(WidgetTester tester, Key key) async {
    final node = nodeOfEntry(tester, key);
    expect(node, isNotNull, reason: '$key 必须挂在可聚焦入口上');
    node!.requestFocus();
    await tester.pump();
    expect(node.hasFocus, isTrue, reason: '$key 聚焦后必须持有焦点');
  }

  /// 焦点可见样式：入口声明了 24% 白的焦点反馈色。key 可挂
  /// IconButton（返回/播放）、InkWell（横屏钮）或其外层 Material（竖屏钮）。
  void expectFocusStyleDeclared(WidgetTester tester, Key key) {
    final self = tester.widget(find.byKey(key));
    final Widget target;
    if (self is IconButton || self is InkWell) {
      target = self;
    } else {
      // key 挂在外层 Material（竖屏钮）：取内层 InkWell。不直接「第一个
      // 后代 InkWell」——IconButton 内部也包私有 InkWell，会取错。
      target = tester.widget<InkWell>(
        find
            .descendant(of: find.byKey(key), matching: find.byType(InkWell))
            .first,
      );
    }
    if (target is IconButton) {
      expect(target.focusColor, kKeyboardFocusHighlight);
    } else {
      expect((target as InkWell).focusColor, kKeyboardFocusHighlight);
    }
  }

  /// 无浮层展开时焦点入口不被覆盖层截走：入口中心的命中测试至少命中入口
  /// 自身子树内的对象（转屏钮被气泡压住时的「点泡外收起」语义不受影响，
  /// 本断言只钉无浮层基线）。
  void expectNotOccluded(WidgetTester tester, Key key) {
    final rect = tester.getRect(find.byKey(key));
    final result = HitTestResult();
    RendererBinding.instance.hitTestInView(
      result,
      rect.center,
      tester.view.viewId,
    );
    final subtree = find.byKey(key);
    final hitInside = result.path.any((entry) {
      final target = entry.target;
      return target is RenderObject &&
          subtree.evaluate().any((element) => element.renderObject == target);
    });
    expect(hitInside, isTrue, reason: '$key 中心的命中必须落在入口自身子树内');
  }

  testWidgets('返回键：可聚焦、焦点色已声明、Enter 激活触发路由 pop', (tester) async {
    setPortraitView(tester);
    final observer = _PopObserver();
    await pumpPlayer(
      tester,
      engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      observer: observer,
    );
    await openEditor(tester);

    const key = Key('control_layer_back');
    expectNotOccluded(tester, key);
    expectFocusStyleDeclared(tester, key);
    await focusEntry(tester, key);

    expect(observer.pops, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(observer.pops, 1, reason: 'Enter 激活返回键 → 宿主 pop 回来源页');
  });

  testWidgets('返回键：Space 同样激活', (tester) async {
    setPortraitView(tester);
    final observer = _PopObserver();
    await pumpPlayer(
      tester,
      engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      observer: observer,
    );
    await openEditor(tester);

    await focusEntry(tester, const Key('control_layer_back'));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(observer.pops, 1, reason: 'Space 激活返回键 → 宿主 pop 回来源页');
  });

  testWidgets('播放开关：可聚焦、焦点色已声明、Enter 激活切换引擎播放态', (tester) async {
    setPortraitView(tester);
    final engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    await pumpPlayer(tester, engine: engine);
    await openEditor(tester);
    await engine.pause();
    await tester.pump();
    expect(engine.isPlaying, isFalse);

    const key = Key('toolbar_play');
    expectNotOccluded(tester, key);
    expectFocusStyleDeclared(tester, key);
    await focusEntry(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(engine.isPlaying, isTrue, reason: 'Enter 激活播放开关 → 引擎开始播放');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.isPlaying, isFalse, reason: 'Space 激活播放开关 → 引擎暂停');
  });

  testWidgets('竖屏转屏钮：可聚焦、焦点色已声明、Enter 激活锁横屏', (tester) async {
    setPortraitView(tester);
    final systemUi = await pumpPlayer(
      tester,
      engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
    );
    await openEditor(tester);
    expect(systemUi.lockLandscapeCount, 0);

    const key = kPortraitRotateButtonKey;
    expectNotOccluded(tester, key);
    expectFocusStyleDeclared(tester, key);
    await focusEntry(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(systemUi.lockLandscapeCount, 1, reason: 'Enter 激活转屏钮 → 锁横屏');

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(systemUi.lockLandscapeCount, 2, reason: 'Space 同样激活转屏钮');
  });

  testWidgets('横屏「转为竖屏」钮：可聚焦、焦点色已声明、Enter 激活锁竖屏', (tester) async {
    setLandscapeView(tester);
    final systemUi = await pumpPlayer(
      tester,
      engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
    );
    await openEditor(tester);
    expect(systemUi.lockPortraitCount, 0);

    const key = kLandscapeToPortraitButtonKey;
    expectNotOccluded(tester, key);
    expectFocusStyleDeclared(tester, key);
    await focusEntry(tester, key);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(systemUi.lockPortraitCount, 1, reason: 'Enter 激活转为竖屏钮 → 锁竖屏');
  });

  testWidgets('Tab 遍历可达三个关键入口；走到返回键后 Enter 激活 pop', (tester) async {
    setPortraitView(tester);
    final observer = _PopObserver();
    final systemUi = await pumpPlayer(
      tester,
      engine: FakePlaybackEngine(videoAspectRatio: 16 / 9),
      observer: observer,
    );
    await openEditor(tester);

    const backKey = Key('control_layer_back');
    const playKey = Key('toolbar_play');
    const rotateKey = kPortraitRotateButtonKey;
    final backNode = nodeOfEntry(tester, backKey);
    final reached = <Key>{};
    // 焦点遍历从根作用域起：连按 Tab 走**完整一圈**（回到返回键再停，上限
    // 120 步足够覆盖控制层全部可聚焦件），三个关键入口都必须被走到；中途
    // 遇到返回键不早停——否则排在返回键之后的入口走不到。
    for (var i = 0; i < 120; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final current = FocusManager.instance.primaryFocus;
      if (current == backNode) {
        if (reached.contains(backKey)) break;
        reached.add(backKey);
        continue;
      }
      if (current == nodeOfEntry(tester, playKey)) reached.add(playKey);
      if (current == nodeOfEntry(tester, rotateKey)) reached.add(rotateKey);
    }
    expect(reached, containsAll(<Key>[backKey, playKey, rotateKey]),
        reason: 'Tab 遍历必须可达返回、播放开关、转屏钮');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(observer.pops, 1, reason: '遍历落在返回键后 Enter 激活 → pop');
    expect(systemUi.lockLandscapeCount, 0, reason: '遍历过程未误触任何入口');
  });
}

/// 记录路由 pop 次数的导航观察器（返回键键盘激活的可观察结果）。
class _PopObserver extends NavigatorObserver {
  int pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pops++;
  }
}
