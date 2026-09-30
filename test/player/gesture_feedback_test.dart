import 'package:dance_learning_app/player/gesture_feedback.dart';
import 'package:dance_learning_app/player/level_feedback.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/semantics_assertions.dart';

void main() {
  group('GestureFeedbackController（共享骨架）', () {
    test('初始为 idle：isScrubbing false、isActive false', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);

      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.isScrubbing, isFalse);
      expect(c.isActive, isFalse);
    });

    test('起始手指数：缺省 1，noteStartPointerCount 记录本次手势值', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);

      expect(c.startPointerCount, 1);
      c.noteStartPointerCount(3);
      expect(c.startPointerCount, 3);
    });

    test('beginScrubbing：idle → scrubbing，通知监听者一次', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.beginScrubbing();

      expect(c.phase, GestureFeedbackPhase.scrubbing);
      expect(c.isScrubbing, isTrue);
      expect(c.isActive, isTrue);
      expect(notified, 1);
    });

    test('重复 beginScrubbing 幂等：不重复通知', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.beginScrubbing();
      c.beginScrubbing();
      c.beginScrubbing();

      expect(notified, 1);
    });

    test('endScrubbing：scrubbing → idle，通知监听者一次', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      c.beginScrubbing();
      var notified = 0;
      c.addListener(() => notified++);

      c.endScrubbing();

      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.isScrubbing, isFalse);
      expect(c.isActive, isFalse);
      expect(notified, 1);
    });

    test('idle 时 endScrubbing 幂等：不通知、相位不变', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.endScrubbing();

      expect(c.phase, GestureFeedbackPhase.idle);
      expect(notified, 0);
    });

    test('dispose 后阶段保持且不再通知', () {
      final c = GestureFeedbackController();
      var notified = 0;
      c.addListener(() => notified++);
      c.beginScrubbing();
      c.dispose();

      expect(notified, 1);
      // dispose 后阶段保持（不再通知；不再有监听者存活）。
      expect(c.phase, GestureFeedbackPhase.scrubbing);
    });
  });

  group('GestureFeedbackController 音量/亮度调节', () {
    test('初始：isLevelAdjusting false、isActive false', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);

      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.isLevelAdjusting, isFalse);
      expect(c.isActive, isFalse);
    });

    test('showLevelAdjust：idle → levelAdjust，记录 kind/value，通知一次', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.showLevelAdjust(kind: LevelAdjustKind.brightness, value: 0.4);

      expect(c.phase, GestureFeedbackPhase.levelAdjust);
      expect(c.isLevelAdjusting, isTrue);
      expect(c.isScrubbing, isFalse);
      expect(c.isActive, isTrue);
      expect(c.levelKind, LevelAdjustKind.brightness);
      expect(c.levelValue, 0.4);
      expect(notified, 1);
    });

    test('showLevelAdjust 进入后逐帧更新：值变化通知、未变化不通知、越界钳制', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.5);
      expect(notified, 1);

      notified = 0;
      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.8);
      expect(c.levelValue, 0.8);
      expect(notified, 1, reason: '值变化通知');

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.8);
      expect(notified, 1, reason: '值未变化不重复通知（幂等）');

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: -0.3);
      expect(c.levelValue, 0.0, reason: '越界钳制到 0..1');
      expect(notified, 2);

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 1.3);
      expect(c.levelValue, 1.0);
    });

    test('showLevelAdjust：调节对象（kind）变化也通知并更新', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.5);
      notified = 0;
      c.showLevelAdjust(kind: LevelAdjustKind.brightness, value: 0.5);
      expect(c.levelKind, LevelAdjustKind.brightness);
      expect(notified, 1, reason: 'kind 变化通知');
    });

    test('endLevelAdjust：levelAdjust → idle 通知一次；idle 时幂等不通知', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.endLevelAdjust();
      expect(notified, 0, reason: 'idle 时 end 幂等');

      c.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.8);
      notified = 0;
      c.endLevelAdjust();
      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.isLevelAdjusting, isFalse);
      expect(c.isActive, isFalse);
      expect(notified, 1);

      c.endLevelAdjust();
      expect(notified, 1, reason: '再次 end 幂等');
    });

    test('与 scrubbing 互斥：showLevelAdjust 覆盖 scrubbing（一次手势一个相位）', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      c.beginScrubbing();
      expect(c.isScrubbing, isTrue);

      c.showLevelAdjust(kind: LevelAdjustKind.brightness, value: 0.5);
      expect(c.phase, GestureFeedbackPhase.levelAdjust);
      expect(c.isScrubbing, isFalse);
      expect(c.isLevelAdjusting, isTrue);
      expect(c.levelKind, LevelAdjustKind.brightness);

      c.endLevelAdjust();
      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.isActive, isFalse);
    });
  });

  group('GestureFeedbackController 进度拖动取消区', () {
    test('初始 cancelArmed false；非 scrubbing 相位 setCancelArmed 无副作用', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      expect(c.cancelArmed, isFalse);
      c.setCancelArmed(true);
      expect(c.cancelArmed, isFalse, reason: '非 scrubbing 相位不进入待取消');
      expect(notified, 0);
    });

    test('beginScrubbing 复位待取消（复用控制器时前会话不残留）', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      c.beginScrubbing();
      c.setCancelArmed(true);
      expect(c.cancelArmed, isTrue);

      // 结束并重启新会话：待取消复位。
      c.endScrubbing();
      c.beginScrubbing();
      expect(c.cancelArmed, isFalse, reason: '新 scrub 会话从非待取消开始');
    });

    test('scrubbing 中 setCancelArmed：true 通知一次、重复 true 幂等、false 再通知', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      c.beginScrubbing();
      var notified = 0;
      c.addListener(() => notified++);

      c.setCancelArmed(true);
      expect(c.cancelArmed, isTrue);
      expect(notified, 1, reason: '进入待取消通知一次');

      c.setCancelArmed(true);
      expect(notified, 1, reason: '重复 true 幂等不通知');

      c.setCancelArmed(false);
      expect(c.cancelArmed, isFalse);
      expect(notified, 2, reason: '移出取消区恢复通知');
    });

    test('endScrubbing 复位待取消并回 idle', () {
      final c = GestureFeedbackController();
      addTearDown(c.dispose);
      c.beginScrubbing();
      c.setCancelArmed(true);

      c.endScrubbing();
      expect(c.phase, GestureFeedbackPhase.idle);
      expect(c.cancelArmed, isFalse, reason: '结束 scrub 复位待取消');
    });
  });

  group('GestureFeedbackOverlay（IgnorePointer 浮层宿主）', () {
    testWidgets('idle 不占空间；scrubbing 激活时叠加内容且不拦截触摸', (tester) async {
      final controller = GestureFeedbackController();
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                // 底层可点击层：记录点击，验证浮层不拦截触摸。
                GestureDetector(
                  key: const Key('underlay'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                GestureFeedbackOverlay(
                  controller: controller,
                  contentBuilder: (context) => const ColoredBox(
                    key: Key('feedback_content'),
                    color: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // idle：浮层不渲染内容。
      expect(find.byKey(const Key('feedback_content')), findsNothing);
      // idle：点击直达底层。
      await tester.tapAt(const Offset(400, 300));
      expect(taps, 1);

      // scrubbing：内容叠加，但 IgnorePointer 不拦截触摸。
      controller.beginScrubbing();
      await tester.pump();
      expect(find.byKey(const Key('feedback_content')), findsOneWidget);
      await tester.tapAt(const Offset(400, 300));
      expect(taps, 2, reason: 'IgnorePointer 浮层不拦截触摸');

      // 结束 scrubbing：内容消失。
      controller.endScrubbing();
      await tester.pump();
      expect(find.byKey(const Key('feedback_content')), findsNothing);
    });
  });

  group('GestureFeedbackOverlay + 音量/亮度滑条内容', () {
    testWidgets('levelAdjust 相位激活时叠加横向滑条，IgnorePointer 不拦截触摸', (tester) async {
      final controller = GestureFeedbackController();
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                // 底层可点击层：记录点击，验证滑条浮层不拦截触摸。
                GestureDetector(
                  key: const Key('underlay'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                GestureFeedbackOverlay(
                  controller: controller,
                  contentBuilder: (context) => const LevelAdjustSlider(
                    kind: LevelAdjustKind.brightness,
                    value: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // idle：不渲染滑条。
      expect(find.byKey(const Key('level_adjust_slider')), findsNothing);

      // levelAdjust：滑条出现（内容由播放器页按控制器 kind/value 挂载，
      // 本测试 contentBuilder 固定为亮度滑条 → 太阳图标），点击直达底层。
      controller.showLevelAdjust(kind: LevelAdjustKind.volume, value: 0.5);
      await tester.pump();
      expect(find.byKey(const Key('level_adjust_slider')), findsOneWidget);
      expect(
        find.byIcon(Icons.wb_sunny),
        findsOneWidget,
        reason: 'contentBuilder 产出的亮度滑条 → 太阳图标',
      );
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('level_adjust_slider'))),
      );
      expect(taps, 1, reason: 'IgnorePointer 浮层不拦截触摸');

      // 结束：滑条消失。
      controller.endLevelAdjust();
      await tester.pump();
      expect(find.byKey(const Key('level_adjust_slider')), findsNothing);
    });

    testWidgets('滑条报出可播报读数：对象 + 整数百分比（期望值写死，不重算实现）', (tester) async {
      Future<void> pumpSlider(LevelAdjustKind kind, double value) => tester
          .pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: LevelAdjustSlider(kind: kind, value: value),
              ),
            ),
          );

      await pumpSlider(LevelAdjustKind.volume, 0.6);
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '音量 60%',
        liveRegion: true,
      );

      // 值变化 → 可播报文本跟着变。
      await pumpSlider(LevelAdjustKind.volume, 0.37);
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '音量 37%',
        liveRegion: true,
      );

      await pumpSlider(LevelAdjustKind.brightness, 0.42);
      expectSemanticsLabel(
        tester,
        const Key('level_adjust_announce'),
        label: '亮度 42%',
        liveRegion: true,
      );
    });
  });
}
