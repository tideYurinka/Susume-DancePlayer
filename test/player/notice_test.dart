import 'package:dance_learning_app/player/notice.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测试用时长（与 notice.dart 导出的生产常量独立取值，
/// 避免常量自证）。
const _hold = Duration(milliseconds: 1500);
const _fade = Duration(milliseconds: 300);

void main() {
  group('时长表（缺省 + 只列例外）', () {
    test('时长表例外：三指跳转 600/200，临时衔接段缺省停留 + 300 淡出', () {
      expect(noticeTimingOf(NoticeId.threeFingerToast).hold,
          const Duration(milliseconds: 600));
      expect(noticeTimingOf(NoticeId.threeFingerToast).fade,
          const Duration(milliseconds: 200));
      expect(noticeTimingOf(NoticeId.transition).hold, kDefaultNoticeHold);
      expect(noticeTimingOf(NoticeId.transition).fade,
          const Duration(milliseconds: 300));
    });
  });

  group('NoticeController（fakeAsync 驱动）', () {
    test('初始 hidden：visible false', () {
      final c = NoticeController(hold: _hold, fade: _fade);
      addTearDown(c.dispose);

      expect(c.phase, NoticePhase.hidden);
      expect(c.visible, isFalse);
    });

    test('show：进入 showing，通知监听者一次', () {
      final c = NoticeController(hold: _hold, fade: _fade);
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.show();

      expect(c.phase, NoticePhase.showing);
      expect(c.visible, isTrue);
      expect(notified, 1);
    });

    test('hold 到点 fading（仍可见），fade 到点回 hidden', () {
      fakeAsync((async) {
        final c = NoticeController(hold: _hold, fade: _fade);
        c.show();

        async.elapse(_hold - const Duration(milliseconds: 1));
        expect(c.phase, NoticePhase.showing);

        async.elapse(const Duration(milliseconds: 1));
        expect(c.phase, NoticePhase.fading);
        expect(c.visible, isTrue);

        async.elapse(_fade);
        expect(c.phase, NoticePhase.hidden);
        expect(c.visible, isFalse);

        c.dispose();
      });
    });

    test('fade == 0：hold 到点直接 hidden，不经 fading（原 centered 语义）', () {
      fakeAsync((async) {
        final c = NoticeController(hold: _hold);
        c.show();

        async.elapse(_hold - const Duration(milliseconds: 1));
        expect(c.phase, NoticePhase.showing);

        async.elapse(const Duration(milliseconds: 1));
        expect(c.phase, NoticePhase.hidden);
        expect(c.visible, isFalse);

        c.dispose();
      });
    });

    test('展示中重新 show：淡出定时重排（旧消失时刻不生效）', () {
      fakeAsync((async) {
        final c = NoticeController(hold: _hold, fade: _fade);
        c.show(); // 原定时：t=1500 淡出
        async.elapse(_hold ~/ 2); // t=750

        c.show(); // 重排：t=2250 淡出
        expect(c.phase, NoticePhase.showing);

        async.elapse(_hold ~/ 2); // t=1500（原定时到点）
        expect(c.phase, NoticePhase.showing, reason: '重新 show 重排，旧消失时刻不生效');

        async.elapse(_hold ~/ 2 - const Duration(milliseconds: 1)); // t=2249
        expect(c.phase, NoticePhase.showing);
        async.elapse(const Duration(milliseconds: 1)); // t=2250
        expect(c.phase, NoticePhase.fading);

        c.dispose();
      });
    });

    test('hideNow：立即回 hidden 并通知', () {
      final c = NoticeController(hold: _hold, fade: _fade);
      addTearDown(c.dispose);
      var notified = 0;
      c.addListener(() => notified++);

      c.show();
      expect(notified, 1);

      c.hideNow();

      expect(c.phase, NoticePhase.hidden);
      expect(c.visible, isFalse);
      expect(notified, 2);
    });

    test('hideNow 后旧 hold 定时不复活', () {
      fakeAsync((async) {
        final c = NoticeController(hold: _hold, fade: _fade);
        c.show();
        c.hideNow();

        async.elapse(_hold + _fade);
        expect(c.phase, NoticePhase.hidden);

        c.dispose();
      });
    });

    test('dispose 取消定时器：不再推进相位、不抛错', () {
      fakeAsync((async) {
        final c = NoticeController(hold: _hold, fade: _fade);
        c.show();
        c.dispose();

        async.elapse(_hold + _fade + const Duration(seconds: 1));
        expect(c.phase, NoticePhase.showing);
      });
    });

    test('dispose 后 show 是 no-op', () {
      final c = NoticeController(hold: _hold, fade: _fade);
      c.dispose();

      c.show();

      expect(c.phase, NoticePhase.hidden);
    });
  });

  group('NoticeOverlay（IgnorePointer 居中浮层）', () {
    Widget host(Widget overlay) => MaterialApp(
      home: Scaffold(
        body: Stack(fit: StackFit.expand, children: [overlay]),
      ),
    );

    /// 收尾：推进走完「停留 + 淡出」并断言消失。
    Future<void> fadeOutAndGone(WidgetTester tester, Finder finder) async {
      await tester.pump(_hold);
      await tester.pump(_fade + const Duration(milliseconds: 10));
      expect(finder, findsNothing);
    }

    testWidgets('hidden 不占空间；show 后居中显示内容', (tester) async {
      final controller = NoticeController(hold: _hold, fade: _fade);
      addTearDown(controller.dispose);
      const noticeKey = Key('notice_under_test');

      await tester.pumpWidget(
        host(
          NoticeOverlay(
            controller: controller,
            noticeKey: noticeKey,
            contentBuilder: (_) =>
                const Text('提示', style: TextStyle(color: Colors.white)),
          ),
        ),
      );
      expect(find.byKey(noticeKey), findsNothing);

      controller.show();
      await tester.pump();

      final notice = find.byKey(noticeKey);
      expect(notice, findsOneWidget);
      final center = tester.getCenter(notice);
      expect(center.dx, closeTo(400, 1));
      expect(center.dy, closeTo(300, 1));
      expect(find.text('提示'), findsOneWidget);

      await fadeOutAndGone(tester, notice);
    });

    testWidgets('fade==0：hold 到点立即消失（无淡出挂载期）', (tester) async {
      final controller = NoticeController(hold: _hold);
      addTearDown(controller.dispose);
      const noticeKey = Key('notice_under_test');

      await tester.pumpWidget(
        host(
          NoticeOverlay(
            controller: controller,
            noticeKey: noticeKey,
            contentBuilder: (_) => const Text('即时'),
          ),
        ),
      );

      controller.show();
      await tester.pump();
      expect(find.byKey(noticeKey), findsOneWidget);

      await tester.pump(_hold);
      expect(find.byKey(noticeKey), findsNothing);
    });

    testWidgets('hideNow：浮层立即卸载', (tester) async {
      final controller = NoticeController(hold: _hold, fade: _fade);
      addTearDown(controller.dispose);
      const noticeKey = Key('notice_under_test');

      await tester.pumpWidget(
        host(
          NoticeOverlay(
            controller: controller,
            noticeKey: noticeKey,
            contentBuilder: (_) => const Text('提示'),
          ),
        ),
      );

      controller.show();
      await tester.pump();
      expect(find.byKey(noticeKey), findsOneWidget);

      controller.hideNow();
      await tester.pump();
      expect(find.byKey(noticeKey), findsNothing);
    });

    testWidgets('IgnorePointer：提示可见期间点击直达底层', (tester) async {
      final controller = NoticeController(hold: _hold, fade: _fade);
      addTearDown(controller.dispose);
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  key: const Key('underlay'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                  child: const SizedBox.expand(),
                ),
                NoticeOverlay(
                  controller: controller,
                  noticeKey: const Key('notice_under_test'),
                  contentBuilder: (_) => const Text('提示'),
                ),
              ],
            ),
          ),
        ),
      );

      controller.show();
      await tester.pump();
      expect(find.byKey(const Key('notice_under_test')), findsOneWidget);

      await tester.tapAt(const Offset(400, 300));
      expect(taps, 1, reason: 'IgnorePointer 浮层不拦截触摸');

      await fadeOutAndGone(tester, find.byKey(const Key('notice_under_test')));
    });
  });
}
