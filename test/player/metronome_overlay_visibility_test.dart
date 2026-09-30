import 'package:dance_learning_app/player/metronome_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('浮层存在性 = 内容可见性 isBeatOverlayContentVisible', () {
    test('四条件全满足（总开关开 ∧ 有内容 ∧ 位置就绪 ∧ 非异常）→ 可见', () {
      expect(
        isBeatOverlayContentVisible(
          displayEnabled: true,
          hasContent: true,
          positionReady: true,
          beatTrackError: false,
        ),
        isTrue,
      );
    });

    test('节拍动画总开关关 → 不可见', () {
      expect(
        isBeatOverlayContentVisible(
          displayEnabled: false,
          hasContent: true,
          positionReady: true,
          beatTrackError: false,
        ),
        isFalse,
      );
    });

    test('无内容（无激活锚且位置早于首线/超出网格末拍）→ 不可见', () {
      expect(
        isBeatOverlayContentVisible(
          displayEnabled: true,
          hasContent: false,
          positionReady: true,
          beatTrackError: false,
        ),
        isFalse,
      );
    });

    test('异常态（无网格）→ 不可见', () {
      expect(
        isBeatOverlayContentVisible(
          displayEnabled: true,
          hasContent: true,
          positionReady: true,
          beatTrackError: true,
        ),
        isFalse,
      );
    });

    test('位置未就绪 → 不可见', () {
      expect(
        isBeatOverlayContentVisible(
          displayEnabled: true,
          hasContent: true,
          positionReady: false,
          beatTrackError: false,
        ),
        isFalse,
      );
    });
  });

  group('控制层展开态只读浮层 MetronomeOverlay.readOnly（widget seam）', () {
    Future<void> pumpOverlay(
      WidgetTester tester, {
      required bool readOnly,
      bool selected = false,
    }) async {
      final controller = MetronomeOverlayController();
      if (selected) controller.select();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // 底层播放面：readOnly 下点击应穿透落到底层。
                GestureDetector(
                  key: const Key('surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: const SizedBox.expand(),
                ),
                MetronomeOverlay(
                  controller: controller,
                  readOnly: readOnly,
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('readOnly + 选中态：无选中框与角工具，内容照常绘制', (tester) async {
      await pumpOverlay(tester, readOnly: true, selected: true);

      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('metronome_overlay_close')),
        findsNothing,
      );
      expect(find.byKey(const Key('metronome_overlay_lock')), findsNothing);
    });

    testWidgets('readOnly：IgnorePointer 穿透，点击落到底层播放面', (tester) async {
      var surfaceTaps = 0;
      final controller = MetronomeOverlayController()..select();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                GestureDetector(
                  key: const Key('surface'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => surfaceTaps++,
                  child: const SizedBox.expand(),
                ),
                MetronomeOverlay(
                  controller: controller,
                  readOnly: true,
                  child: const SizedBox.expand(),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      // 浮层内容区（选中态本应整面接管）中心点击：穿透落到底层播放面。
      await tester.tap(find.byKey(const Key('surface')));
      await tester.pump();

      expect(surfaceTaps, 1);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsNothing,
      );
    });

    testWidgets('展开（进入只读）即失焦：退出选中态，收起后选中框不未点选回归',
        (tester) async {
      final controller = MetronomeOverlayController()..select();
      Widget buildOverlay({required bool readOnly}) => MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  const SizedBox.expand(),
                  MetronomeOverlay(
                    controller: controller,
                    readOnly: readOnly,
                    child: const SizedBox.expand(),
                  ),
                ],
              ),
            ),
          );

      await tester.pumpWidget(buildOverlay(readOnly: false));
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );

      // 进入只读（= 控制层展开）：真正退出选中态，非渲染伪装。
      await tester.pumpWidget(buildOverlay(readOnly: true));
      await tester.pump();
      expect(controller.selected, isFalse);
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsNothing,
      );

      // 收起控制层（只读解除）：选中框不得未点选而回归。
      await tester.pumpWidget(buildOverlay(readOnly: false));
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsNothing,
      );

      // 点选后选中态照常恢复（收起后恢复完整交互）。
      controller.select();
      await tester.pump();
      expect(
        find.byKey(const Key('metronome_overlay_selected')),
        findsOneWidget,
      );
    });
  });
}
