import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/compare_framing_bar.dart';
import 'package:dance_learning_app/player/compare_framing_view.dart'
    show compareFramingPictureRect;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/settings_persistence.dart'
    show videoDocumentStorageProvider;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/compare_framing_harness.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/device_viewport.dart';

/// 取景条：落位（底部居中、距底 8dp、不遮源侧
/// 画面）、形制（不透明深底＋浅描边＋阴影＋圆角＋显式白色前景）、内容
/// （标题＋手势提示＋复位＋完成，**无任何倍数读数**）、命中（按钮 ≥48dp
/// 且真机等效视口下点得到）、恒定（整次手势里条宽与按钮位置一动不动）与
/// 提示降级（按**是否真放得下**换行居中、条高下限 60dp；不按屏幕宽度省掉）。
///
/// 验收纪律：这些面板类断言一律在**设备等效视口**（2736×1264 @3.5 ⇒
/// 781.7×361.1dp，与开发真机横屏一致）下做几何与命中——「只断言存在不算
/// 过」；布景同时注入可读的 local 文档（跑过恢复路径）。
///
/// 「不遮画面」的判据 = 条的矩形与**源侧画面矩形不相交**：条是**屏幕**底部
/// 居中的（源侧半区只有 389.9dp 宽，放不下本条），横向会越过分缝压住练习侧
/// 预览的一角——那侧「任何落位都会压住一点预览，不作承诺」，故不做
/// 「矩形完全落在源侧下黑边内」的横向包含断言（「取景条」的落位算术：
/// 由 16:9 源画面上下各 70.9dp 黑边推出条高上限）。
void main() {
  late FakePlaybackEngine engine;
  late FakeCameraCaptureService camera;

  /// 横屏宽度不足约 500dp 的小屏（1600/3.5 ≈ 457.1dp）——刻意收窄的
  /// **合成档**（非设备基准，实际逻辑尺寸 457.1 × 361.1dp）；竖向高取
  /// compact 档物理高，像素比随档 3.5。
  final narrowLandscape = Size(1600, ViewportTier.compact.physicalSize.height);

  /// compact 档（竖/横）经唯一入口落位；合成档单独走窄档路径。
  void setCompactPortraitView(WidgetTester tester) =>
      useNamedViewport(tester, ViewportTier.compact);
  void setCompactLandscapeView(WidgetTester tester) =>
      useNamedViewport(tester, ViewportTier.compact, landscape: true);
  void setNarrowLandscapeView(WidgetTester tester) {
    tester.view.physicalSize = narrowLandscape;
    tester.view.devicePixelRatio = ViewportTier.compact.devicePixelRatio;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPlayer(WidgetTester tester) async {
    final source = Uri.file('/videos/a.mp4');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          cameraCaptureProvider.overrideWithValue(camera),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(
                    filePath: source.toFilePath(),
                    mirrored: false,
                    videoId: 'vid-test',
                  ),
                ],
              ),
            ),
          ),
          // 可读 local 文档（验收纪律：轻量 UI 验收默认布景）。
          videoDocumentStorageProvider('vid-test').overrideWithValue(
            InMemoryVideoDocumentStorage(local: const {'version': 3}),
          ),
        ],
        child: MaterialApp(home: PlayerPage(source: source)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 设备等效视口下统一用定长等待（播放循环持续动画，pumpAndSettle 不收敛）。
  Future<void> settle(WidgetTester tester) =>
      awaitFraming(tester, FramingWait.fixedPump);

  Future<void> enterFraming(
    WidgetTester tester, {
    bool viaControlLayer = true,
  }) => enterFramingMode(
    tester,
    viaControlLayer: viaControlLayer,
    wait: FramingWait.fixedPump,
  );

  /// 单指从 [from] 拖到 [to]：建一个取景选区（真手势序列）。
  Future<void> buildBox(
    WidgetTester tester, {
    required Offset from,
    required Offset to,
  }) async {
    final touch = await tester.startGesture(from);
    await tester.pump();
    // 首帧位移只用于越过识别 slop：识别器的 start 落在这一帧的位置上，
    // 之后才跟手到 [to]。
    await touch.moveTo(Offset.lerp(from, to, 0.15)!);
    await tester.pump();
    await touch.moveTo(to);
    await tester.pump();
    await touch.up();
    await settle(tester);
  }

  Rect barRect(WidgetTester tester) =>
      tester.getRect(find.byKey(const Key('framing_bar')));

  /// 同排判据：标题与提示的纵向中心重合（同一 Row 内垂直居中）。
  void expectSameLine(WidgetTester tester) {
    final title = tester.getRect(find.byKey(const Key('framing_bar_title')));
    final hint = tester.getRect(find.byKey(const Key('framing_bar_hint')));
    expect(
      hint.center.dy,
      closeTo(title.center.dy, 0.5),
      reason: '放得下时提示应与标题同一行',
    );
  }

  /// 换行判据：提示完全落在标题下方（标题行与提示行不重叠），且两行在文字
  /// 列内**居中**——中心 x 重合（列宽取两行较宽者，居中即两中心同 x）。
  void expectWrappedCentered(WidgetTester tester) {
    final title = tester.getRect(find.byKey(const Key('framing_bar_title')));
    final hint = tester.getRect(find.byKey(const Key('framing_bar_hint')));
    expect(
      hint.top,
      greaterThanOrEqualTo(title.bottom - 0.01),
      reason: '放不下时提示应换到标题下一行',
    );
    expect(
      hint.center.dx,
      closeTo(title.center.dx, 0.5),
      reason: '换行后的提示应在文字列内居中',
    );
  }

  Size screenSize(WidgetTester tester) =>
      tester.view.physicalSize / tester.view.devicePixelRatio;

  /// 源的「画面矩形」与「画面下方的黑边矩形」（全局坐标，几何声明与手势
  /// 接线同源 [compareFramingPictureRect]）。横屏 16:9 contain 下源侧半区
  /// 389.9 × 361.1dp、画面高 219.3dp ⇒ 上下各 70.9dp 黑边。
  ({Rect picture, Rect bottomBand}) sourceRects(WidgetTester tester) {
    final size = screenSize(tester);
    final landscape =
        MediaQuery.orientationOf(tester.element(find.byType(PlayerPage))) ==
        Orientation.landscape;
    final picture = compareFramingPictureRect(
      screen: size,
      landscape: landscape,
      aspectRatio: engine.videoAspectRatio,
    );
    return (
      picture: picture,
      bottomBand: landscape
          ? Rect.fromLTRB(0, picture.bottom, picture.right, size.height)
          : Rect.fromLTRB(
              picture.right,
              size.height / 2,
              size.width,
              size.height,
            ),
    );
  }

  setUp(() {
    engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    camera = FakeCameraCaptureService();
  });

  testWidgets('落位：底部居中、距底 8dp、整条落在源侧画面外的下黑边内（不遮画面）', (tester) async {
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    final screen = screenSize(tester);
    final bar = barRect(tester);
    final bands = sourceRects(tester);

    // 距底 8dp、单行高 = 下限 60dp（16:9 源画面 ⇒ 源侧黑边 70.9dp ⇒ 上限 62.9dp）。
    expect(bar.bottom, closeTo(screen.height - 8, 0.01));
    expect(bar.height, closeTo(kCompareFramingBarMinHeight, 0.01));
    // 黑边内：整条在源侧画面的下方，且不越过屏幕下缘。
    expect(bar.top, greaterThanOrEqualTo(bands.bottomBand.top - 0.01));
    expect(bar.bottom, lessThanOrEqualTo(bands.bottomBand.bottom + 0.01));
    // 一点不遮住源侧画面。
    expect(bands.picture.overlaps(bar), isFalse, reason: '取景条压住了源侧画面');
    // 底部**居中**（屏幕居中：源侧半区放不下本条，见文件头）。
    expect(bar.center.dx, closeTo(screen.width / 2, 0.01));
  });

  testWidgets('内容：标题＋手势提示＋「复位」＋「完成」；取景态内不存在任何倍数数字', (tester) async {
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    expect(find.text(kCompareFramingBarTitle), findsOneWidget);
    expect(find.text(kCompareFramingBarHint), findsOneWidget);
    expect(find.text(kCompareFramingBarResetLabel), findsOneWidget);
    expect(find.text(kCompareFramingBarDoneLabel), findsOneWidget);

    // 读数取消：取景态内任何位置都没有倍数数字。先调出
    // 一个非 1.0× 的取值，确保不是「恰好 1.0×」让读数隐身；断言扫全树的
    // 文本而不认某个 key——旧的 `framing_scale_readout` 存在性断言正是
    // 「只断言存在不算过」的反例，已随之撤掉。
    await buildBox(tester, from: const Offset(120, 150), to: const Offset(360, 320));
    expect(
      framingBoxOnScreen(tester),
      isNotNull,
      reason: '先圈出非默认取值（屏上框出现），读数隐身才不是「恰好 1.0×」',
    );
    final scaleTexts = find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data != null &&
          RegExp(r'\d+(\.\d+)?\s*×').hasMatch(widget.data!),
    );
    expect(scaleTexts, findsNothing, reason: '取景态内不得出现任何倍数读数');
  });

  testWidgets('形制：黑 78% 不透明深底＋1px 浅描边＋阴影＋圆角 28＋内边距 16＋前景显式白色', (tester) async {
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    // 验收清单逐条点名了这些形制取值，故按条身外观逐条断言：这一组
    // 就是「形制落地」的验收面，不是实现细节的复述。
    final bar = tester.widget<Container>(find.byKey(const Key('framing_bar')));
    final decoration = bar.decoration! as BoxDecoration;
    expect(decoration.color!.a, closeTo(0.78, 0.01));
    expect(decoration.color!.r, 0.0);
    expect(decoration.color!.g, 0.0);
    expect(decoration.color!.b, 0.0);
    final border = decoration.border! as Border;
    expect(border.top.width, kCompareFramingBarBorderWidth);
    expect(border.top.color.a, greaterThan(0.0));
    expect(border.top.color.r, 1.0);
    expect(decoration.boxShadow, isNotEmpty);
    expect(decoration.borderRadius, BorderRadius.circular(28));
    expect((bar.padding! as EdgeInsets).left, 16);
    expect((bar.padding! as EdgeInsets).right, 16);

    // 前景显式白色：标题与手势提示（浅色主题的默认前景压在深底上看不清）。
    expect(
      tester.widget<Text>(find.text(kCompareFramingBarTitle)).style!.color,
      Colors.white,
    );
    final hint = tester.widget<Text>(find.text(kCompareFramingBarHint));
    expect(hint.style!.color!.r, 1.0);
    expect(hint.style!.color!.a, greaterThan(0.5));

    // 「复位」为描边按钮且前景显式白色（不吃 M3 默认主色 = 深紫）；
    // 「完成」为主色填充按钮（FilledButton = 主题主色填充）。
    final reset = tester.widget<OutlinedButton>(
      find.byKey(const Key('framing_reset')),
    );
    expect(
      reset.style!.foregroundColor!.resolve(<WidgetState>{}),
      Colors.white,
    );
    expect(
      tester.widget(find.byKey(const Key('framing_done'))),
      isA<FilledButton>(),
    );
  });

  testWidgets('真机可达性：两枚按钮命中区 ≥48dp 且命中自身；完成回对比-控制层、复位清取值回基线', (tester) async {
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    for (final key in const ['framing_reset', 'framing_done']) {
      final box = tester.renderObject<RenderBox>(find.byKey(Key(key)));
      expect(box.size.height, greaterThanOrEqualTo(48.0));
      expect(box.size.width, greaterThanOrEqualTo(48.0));
      // 命中落在按钮**自身**（不是只 find.byKey 存在）。
      final hit = tester.hitTestOnBinding(
        box.localToGlobal(box.size.center(Offset.zero)),
      );
      expect(
        hit.path.any((entry) => entry.target == box),
        isTrue,
        reason: '$key 必须命中自身',
      );
    }

    // 调出非默认取值 → 复位清取值、屏上框随之消失（回到本路径未调过的
    // 基线，只改显示值）。
    await buildBox(tester, from: const Offset(120, 150), to: const Offset(360, 320));
    expect(framingBoxOnScreen(tester), isNotNull);
    await tester.tap(find.byKey(const Key('framing_reset')));
    await settle(tester);
    expect(framingBoxOnScreen(tester), isNull, reason: '复位 = 屏上框消失');

    await tester.tap(find.byKey(const Key('framing_done')));
    await settle(tester);
    expect(find.byKey(const Key('control_layer')), findsOneWidget);
    expect(find.byKey(const Key('framing_bar')), findsNothing);
  });

  testWidgets('条宽与按钮位置在整次手势里一动不动（含取值变化引起的重建）', (tester) async {
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    final before = barRect(tester);
    final resetBefore = tester.getRect(find.byKey(const Key('framing_reset')));
    final doneBefore = tester.getRect(find.byKey(const Key('framing_done')));

    await buildBox(tester, from: const Offset(120, 150), to: const Offset(360, 320));
    expect(
      framingBoxOnScreen(tester),
      isNotNull,
      reason: '屏上框出现 = 取值确实变了、确有重建',
    );

    expect(barRect(tester), before);
    expect(tester.getRect(find.byKey(const Key('framing_reset'))), resetBefore);
    expect(tester.getRect(find.byKey(const Key('framing_done'))), doneBefore);
  });

  testWidgets('放得下：横屏窄条（约 457dp）标题与提示同行、条高 60dp、落位不变', (tester) async {
    setNarrowLandscapeView(tester);
    await pumpPlayer(tester);
    // 直进取景态：457dp 宽的横屏下对比-控制层自己的顶栏/工具条会溢出
    //（控制层面按 781.7dp 真机宽度设计），与取景条无关。
    await enterFraming(tester, viaControlLayer: false);

    // 457.1dp ≥ 条内所需（1.0× 约 294dp）⇒ 提示在场且与标题同行——不再按
    // 屏幕宽度阈值省掉。
    expect(find.text(kCompareFramingBarHint), findsOneWidget);
    expect(find.text(kCompareFramingBarTitle), findsOneWidget);
    expectSameLine(tester);
    expect(find.byKey(const Key('framing_reset')), findsOneWidget);
    expect(find.byKey(const Key('framing_done')), findsOneWidget);

    // 小屏同样整条落在源侧下黑边内、距底 8dp、条高为下限。
    final screen = screenSize(tester);
    final bar = barRect(tester);
    final bands = sourceRects(tester);
    expect(bar.height, closeTo(kCompareFramingBarMinHeight, 0.01));
    expect(bar.bottom, closeTo(screen.height - 8, 0.01));
    expect(bar.top, greaterThanOrEqualTo(bands.bottomBand.top - 0.01));
    expect(bar.bottom, lessThanOrEqualTo(bands.bottomBand.bottom + 0.01));
    expect(bands.picture.overlaps(bar), isFalse);
  });

  testWidgets('竖屏（约 360dp）：提示不再被整段省掉、与标题同行、条高 60dp', (tester) async {
    setCompactPortraitView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester, viaControlLayer: false);

    final screen = screenSize(tester);
    final bar = barRect(tester);
    expect(bar.center.dx, closeTo(screen.width / 2, 0.01));
    expect(bar.height, closeTo(kCompareFramingBarMinHeight, 0.01));
    expect(bar.bottom, closeTo(screen.height - 8, 0.01));
    // 竖屏屏幕宽 361.1dp：按「是否真放得下」判定（1.0× 需约 294dp）⇒ 提示
    // 在场，且与标题同行。
    expect(find.text(kCompareFramingBarHint), findsOneWidget);
    expectSameLine(tester);
    expect(find.byKey(const Key('framing_done')), findsOneWidget);
    expect(find.byKey(const Key('framing_reset')), findsOneWidget);
  });

  testWidgets('放不下（竖屏 2.0× 字号）：提示换到标题下一行并居中，条高按内容增高', (tester) async {
    // 竖屏 361.1dp 宽、2.0× 字号 ⇒ 条内所需约 454dp 放不下 ⇒ 换行。
    useNamedViewport(tester, ViewportTier.compact, textScale: 2.0);
    await pumpPlayer(tester);
    await enterFraming(tester, viaControlLayer: false);

    expect(find.text(kCompareFramingBarHint), findsOneWidget, reason: '换行，绝不省掉');
    expectWrappedCentered(tester);
    final bar = barRect(tester);
    expect(
      bar.height,
      greaterThan(kCompareFramingBarMinHeight),
      reason: '换行后条高按内容增高（下限 60dp）',
    );
    // 两行内容都留在条内（零溢出由 takeException 之外的真机视口覆盖）。
    expect(find.text(kCompareFramingBarTitle), findsOneWidget);
    expect(find.byKey(const Key('framing_done')), findsOneWidget);
    expect(find.byKey(const Key('framing_reset')), findsOneWidget);
  });

  testWidgets('已知限制（登记备查）：竖向源画面没有上下黑边，条必然压住画面下缘', (tester) async {
    // 落位算术（源侧上下各 70.9dp 黑边 ⇒ 条高上限 62.9dp）只对横向
    // 片源成立：竖向片源在横屏半区里 contain = 满高、黑边在左右，下黑边高度
    // 为 0，任何「距底 8dp + 高 56–62dp」的条都压住画面下缘。修这条要先定
    // 非 16:9 的落位口径（条高与距底都是定死的数）；本用例把限制钉成可执行
    // 事实，免得被当成「承诺到处成立」。
    engine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 9 / 16,
    );
    setCompactLandscapeView(tester);
    await pumpPlayer(tester);
    await enterFraming(tester);

    final bar = barRect(tester);
    final bands = sourceRects(tester);
    expect(bands.bottomBand.height, 0);
    expect(bands.picture.overlaps(bar), isTrue);
    // 条本身仍按口径落位（距底 8dp、高 60dp）——不因片源方向而漂移。
    expect(bar.bottom, closeTo(screenSize(tester).height - 8, 0.01));
    expect(bar.height, closeTo(kCompareFramingBarMinHeight, 0.01));
  });

  testWidgets('字号 1.3×/1.6×/2.0×：提示不省掉；放不下换行居中、条高随内容增高；按钮固有宽与命中区不被挤掉', (
    tester,
  ) async {
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    setCompactLandscapeView(tester);

    // 直测取景条本身。判定吃**条自身的约束宽度**，故同一条在两种宽度下量：
    // - 不受限档 2000dp：必然放得下、单行 —— 记下两枚按钮的固有宽与两行
    //   文字在此的单行几何。
    // - 窄档 360dp：1.3× 仍放得下（约 342dp）；1.6×／2.0× 放不下 ⇒ 提示
    //   换到标题下一行、居中，条高按内容增高。三档都必须零溢出；两枚按钮
    //   固有宽逐位不变；列内两行仍各占一行（高度同不受限档）并在放不下整句
    //   时收窄到窄于不受限档（逐行省略，而不是换行或溢出）。
    const narrowBarWidth = 360.0;
    const unboundedBarWidth = 2000.0;

    Future<void> pumpBar(double width) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                child: FramingBar(
                  onDone: () {},
                  onReset: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Size sizeOf(String key) => tester.getSize(find.byKey(Key(key)));

    /// 两枚按钮：命中区 ≥ 下限，整枚落在条内（没被挤出条外），且固有宽
    /// 与不受限档量得的逐位相同。
    void expectButtonsIntact({required Map<String, Size> intrinsic}) {
      final bar = barRect(tester);
      for (final entry in intrinsic.entries) {
        final key = entry.key;
        final box = tester.renderObject<RenderBox>(find.byKey(Key(key)));
        expect(
          box.size.width,
          greaterThanOrEqualTo(kCompareFramingBarButtonMinSize),
          reason: '$key 命中区宽不足',
        );
        expect(
          box.size.height,
          greaterThanOrEqualTo(kCompareFramingBarButtonMinSize),
          reason: '$key 命中区高不足',
        );
        expect(box.size, entry.value, reason: '$key 固有宽被挤掉');
        final button = tester.getRect(find.byKey(Key(key)));
        expect(
          button.left,
          greaterThanOrEqualTo(bar.left - 0.01),
          reason: '$key 必须整枚留在条内',
        );
        expect(
          button.right,
          lessThanOrEqualTo(bar.right + 0.01),
          reason: '$key 必须整枚留在条内',
        );
      }
    }

    for (final scale in const [1.3, 1.6, 2.0]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;

      // 不受限：量固有宽与单行几何（此刻必然单行，提示在场）。
      await pumpBar(unboundedBarWidth);
      expect(tester.takeException(), isNull, reason: '$scale× 不受限条溢出');
      expect(find.text(kCompareFramingBarHint), findsOneWidget);
      expectSameLine(tester);
      final intrinsicReset = sizeOf('framing_reset');
      final intrinsicDone = sizeOf('framing_done');
      final fullTitle = sizeOf('framing_bar_title');
      final fullHint = sizeOf('framing_bar_hint');

      await pumpBar(narrowBarWidth);
      expect(tester.takeException(), isNull, reason: '$scale× 窄条溢出');
      expect(
        find.text(kCompareFramingBarHint),
        findsOneWidget,
        reason: '$scale× 窄条必须保留提示（不省掉）',
      );
      expect(find.text(kCompareFramingBarTitle), findsOneWidget);
      expectButtonsIntact(
        intrinsic: {
          'framing_reset': intrinsicReset,
          'framing_done': intrinsicDone,
        },
      );

      // 逐行省略的几何判据：窄档两行仍各占一行（高度与不受限档相同，
      // 即没有软换行到第二行），宽度只收窄不拉伸；2.0× 真的收窄（省略）。
      for (final entry in [
        ('framing_bar_title', fullTitle),
        ('framing_bar_hint', fullHint),
      ]) {
        final narrow = sizeOf(entry.$1);
        expect(
          narrow.height,
          closeTo(entry.$2.height, 0.5),
          reason: '${entry.$1} 必须单行（窄档不得软换行）',
        );
        expect(
          narrow.width,
          lessThanOrEqualTo(entry.$2.width + 0.5),
          reason: '${entry.$1} 只收窄、不拉伸',
        );
      }
      if (scale >= 2.0) {
        expect(
          sizeOf('framing_bar_hint').width,
          lessThan(fullHint.width),
          reason: '$scale× 提示必须被省略收窄',
        );
      }

      final bar = barRect(tester);
      expect(
        bar.height,
        greaterThanOrEqualTo(kCompareFramingBarMinHeight),
        reason: '$scale× 条高不得低于下限',
      );
      if (scale >= 1.6) {
        expectWrappedCentered(tester);
        expect(
          bar.height,
          greaterThan(kCompareFramingBarMinHeight),
          reason: '$scale× 换行后条高须按内容增高',
        );
      } else {
        expectSameLine(tester);
        expect(
          bar.height,
          closeTo(kCompareFramingBarMinHeight, 0.01),
          reason: '$scale× 单行时条高 = 下限',
        );
      }
    }
  });
}
