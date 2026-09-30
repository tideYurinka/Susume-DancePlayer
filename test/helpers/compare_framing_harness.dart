/// 取景态测试共用夹具（与 `compare_framing_state_test.dart`、
/// `compare_framing_bar_test.dart` 共用）：屏上选区框几何读取、定长等待口径，
/// 以及「点按真实入口进对比取景」这条**真用户路径**与双指捏合手势序列。
///
/// 各测试文件的 `pumpPlayer` 布景不同（局部文档、引擎宽高比），故不在此处
/// 统一泵页；这里只放与布景无关的那几件事。先例：`note_editor_harness.dart`。
library;

import 'package:dance_learning_app/annotation/framing_selection.dart'
    show framingSelectionRectOnPicture;
import 'package:dance_learning_app/player/framing_overlay.dart'
    show FramingSelectionOverlay;
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kToolSlotDisabledIconColor;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 播放页所在的 ProviderContainer。
ProviderContainer compareFramingContainer(WidgetTester tester) =>
    ProviderScope.containerOf(
      tester.element(find.byType(PlayerPage)),
      listen: false,
    );

/// 当前播放会话模式取值：只服务**布景驱动**（决定走哪条真入口），不作断言源
/// ——模式断言走屏上判据（取景条 / 控制层谁在场）。
PlayerSessionMode compareFramingMode(WidgetTester tester) =>
    compareFramingContainer(tester).read(playerSessionProvider).mode;

/// 当前取景会话态：只服务**布景读取**，不作断言源——选区断言走
/// [framingBoxOnScreen] 的屏上几何。
FramingState framingValue(WidgetTester tester) =>
    compareFramingContainer(tester).read(framingStateProvider);

/// **屏上选区框**（取景态内那条白框）的屏幕矩形；未调过（屏上不画框）为
/// `null`。
///
/// 读的是覆盖层件自己声明的取值与画面矩形（[FramingSelectionOverlay] 的两个
/// 公开字段）加它自己的屏上原点，与画框的绘制同一份映射——不读 provider 内部
/// 会话态。先例：`single_picture_framing_test.dart` 的 `pictureOnScreen` /
/// `selectionOnScreen`。
Rect? framingBoxOnScreen(WidgetTester tester) {
  final overlayFinder = find.byKey(const Key('framing_selection_overlay'));
  if (overlayFinder.evaluate().isEmpty) return null;
  final overlay = tester.widget<FramingSelectionOverlay>(
    find.ancestor(
      of: overlayFinder,
      matching: find.byType(FramingSelectionOverlay),
    ),
  );
  final selection = overlay.selection;
  final picture = overlay.pictureRect;
  if (selection == null || picture.isEmpty) return null;
  final origin = tester.getRect(overlayFinder).topLeft;
  final rect = framingSelectionRectOnPicture(
    selection: selection,
    pictureLeft: picture.left + origin.dx,
    pictureTop: picture.top + origin.dy,
    pictureWidth: picture.width,
    pictureHeight: picture.height,
  );
  return Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);
}

/// 顶栏工具槽的**屏上可用态**：不可用 = 图标取置灰 token（与
/// `control_layer_test.dart` 的撤销/重做可用性断言同一口径）。
bool toolSlotDisabled(WidgetTester tester, String toolKey) {
  final icon = tester.widget<Icon>(
    find
        .descendant(of: find.byKey(Key(toolKey)), matching: find.byType(Icon))
        .first,
  );
  return icon.color == kToolSlotDisabledIconColor;
}

/// 落定等待口径。设备等效视口（2736×1264 @3.5）下播放循环持续动画，
/// `pumpAndSettle` 不收敛——那些用例走 [FramingWait.fixedPump]。
enum FramingWait {
  /// `pumpAndSettle`（宽视口下的普通布景）。
  settle,

  /// 定长 pump（设备等效视口等不收敛的布景）。
  fixedPump,
}

/// 按 [wait] 等待落定。
Future<void> awaitFraming(WidgetTester tester, FramingWait wait) async {
  switch (wait) {
    case FramingWait.settle:
      await tester.pumpAndSettle();
    case FramingWait.fixedPump:
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
  }
}

/// 点画面唤出闭合态控制层（真手势；单击与双击仲裁隔一个判定窗口）。
Future<void> tapPlayerSurface(
  WidgetTester tester, {
  FramingWait wait = FramingWait.settle,
}) async {
  await tester.tap(
    find.byKey(const Key('player_surface')),
    warnIfMissed: false,
  );
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
  await tester.pump();
  if (wait == FramingWait.settle) await tester.pumpAndSettle();
}

/// 经真入口进对比-控制层：观看态单击唤出控制层 → 点「对比练习」→
/// 对比-播放态单击画面。已在对比-控制层则幂等。
Future<void> enterCompareEditing(
  WidgetTester tester, {
  FramingWait wait = FramingWait.settle,
}) async {
  if (compareFramingMode(tester) == PlayerSessionMode.compareEditing) return;
  await tapPlayerSurface(tester, wait: wait);
  await tester.tap(find.byKey(const Key('tool_compare')));
  await awaitFraming(tester, wait);
  await tapPlayerSurface(tester, wait: wait);
}

/// 进对比取景态（真入口）：[viaControlLayer] = true 时经对比-控制层的
/// 「取景调整」点按进入。
///
/// [viaControlLayer] = false 是**布景捷径**：窄横屏／竖屏下对比-控制层自己
/// 的顶栏排布会溢出（控制层面按真机宽度设计），真入口的中间态在这些布景里
/// 不可达；受审真路径由本文件默认分支与 `compare_framing_bar_test.dart` 的
/// 横向真路径用例覆盖。
Future<void> enterFramingMode(
  WidgetTester tester, {
  bool viaControlLayer = true,
  FramingWait wait = FramingWait.settle,
}) async {
  if (!viaControlLayer) {
    compareFramingContainer(tester)
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareFraming);
    await awaitFraming(tester, wait);
    return;
  }
  if (compareFramingMode(tester) == PlayerSessionMode.compareFraming) return;
  await enterCompareEditing(tester, wait: wait);
  await tester.tap(find.byKey(const Key('tool_framing_adjust')));
  await awaitFraming(tester, wait);
}

/// 双指张开捏合（落点居中）：两指各向外移 50px → 实测累计 scale ≈ 1.5×。
///
/// **真手势序列（回归配方）**：抬指与末指抬起之间必须有一帧余指
/// 移动——识别器正是在那一帧重发手势开始（`_reconfigure` 重设跨度基准 →
/// 余指的下一个 move 帧重开手势，当帧 scale 恰为 1.0）。缺了这一帧，
/// 绝对值型取景的「松手回弹」缺陷不会显形。
Future<void> pinchOpenFraming(
  WidgetTester tester, {
  required Offset around,
  FramingWait wait = FramingWait.settle,
}) async {
  final touch1 = await tester.startGesture(around + const Offset(-50, 0));
  final touch2 = await tester.startGesture(around + const Offset(50, 0));
  await tester.pump();
  await touch1.moveBy(const Offset(-100, 0));
  await touch2.moveBy(const Offset(100, 0));
  await tester.pump();
  await touch1.up();
  await touch2.moveBy(const Offset(12, 0));
  await tester.pump();
  await touch2.up();
  await awaitFraming(tester, wait);
}
