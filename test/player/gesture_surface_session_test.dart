// 输入会话簿记壳模块面测试：raw+scale 序列直驱
// [GestureSurfaceSession]，钉死 phase 迁移、strictHorizontal 轴锁边界、
// 铁律闩锁、burst/tap 仲裁输出、cancel 非 tap、内容命中
// 抑制、证据存档时序与混区 suppressed。
//
// tap 判定窗口（约 300ms）与微任务复核经 fakeAsync 驱动；跨面混区用真实
// [CrossSurfacePinchSession]（闭包全空、只借其 burstEverMixed 闩锁语义）。
import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dance_learning_app/player/gesture_surface_session.dart';
import 'package:dance_learning_app/player/track_time.dart';
import 'package:dance_learning_app/player/two_finger_session.dart';

/// 记录型宿主：收集模块输出事件，供各用例断言。
class _Recorder {
  final singles = <Offset>[];
  final doubles = <int>[];
  final twoFingerDoubles = <Offset>[];
  final multiFinger = <int>[];
  final scrubFrames = <Offset>[];
  final pinchFrames = <Offset>[];
  final starts = <int>[];
  final ends = <int>[];
  final idleTapConsumed = <Offset>[];
  bool alive = true;

  GestureSurfaceSession blankSession({bool Function(Offset)? isEditContent}) {
    return GestureSurfaceSession(
      axis: AxisPolicy.strictHorizontal,
      isEditContent: isEditContent,
      isHostAlive: () => alive,
      onSingleTap: () => singles.add(Offset.zero),
      onDoubleTap: () => doubles.add(1),
      onTwoFingerDoubleTap: () => twoFingerDoubles.add(Offset.zero),
      onMultiFingerWhileScrub: () => multiFinger.add(multiFinger.length),
      onSurfaceScaleStart: (d) => starts.add(d.pointerCount),
      onScrubFrame: (d) => scrubFrames.add(d.focalPointDelta),
      onPinchFrame: (d) => pinchFrames.add(d.focalPointDelta),
      onSurfaceScaleEnd: (d) => ends.add(d.pointerCount),
    );
  }

  GestureSurfaceSession bandSession({bool Function(Offset)? isEditContent}) {
    return GestureSurfaceSession(
      axis: AxisPolicy.strictHorizontal,
      isEditContent: isEditContent,
      isHostAlive: () => alive,
      onSingleTap: () => singles.add(Offset.zero),
      onDoubleTap: () => doubles.add(1),
      onTwoFingerDoubleTap: () => twoFingerDoubles.add(Offset.zero),
      onSurfaceScaleStart: (d) => starts.add(d.pointerCount),
      onScrubFrame: (d) => scrubFrames.add(d.focalPointDelta),
      onPinchFrame: (d) => pinchFrames.add(d.focalPointDelta),
      onSurfaceScaleEnd: (d) => ends.add(d.pointerCount),
      onIdleTapContent: () {
        idleTapConsumed.add(Offset.zero);
        return true;
      },
    );
  }
}

PointerDownEvent _down(int pointer, Offset position) =>
    PointerDownEvent(pointer: pointer, position: position);

PointerMoveEvent _move(int pointer, Offset position) =>
    PointerMoveEvent(pointer: pointer, position: position);

PointerUpEvent _up(int pointer, [Offset position = Offset.zero]) =>
    PointerUpEvent(pointer: pointer, position: position);

PointerCancelEvent _cancel(int pointer) => PointerCancelEvent(pointer: pointer);

ScaleStartDetails _scaleStart(int count, Offset focal) => ScaleStartDetails(
  focalPoint: focal,
  localFocalPoint: focal,
  pointerCount: count,
);

ScaleUpdateDetails _scaleUpdate(
  int count,
  Offset focal,
  Offset delta, {
  double scale = 1.0,
}) => ScaleUpdateDetails(
  focalPoint: focal,
  localFocalPoint: focal,
  scale: scale,
  pointerCount: count,
  focalPointDelta: delta,
);

ScaleEndDetails _scaleEnd() => ScaleEndDetails();

void main() {
  group('phase 迁移（raw+scale 序列驱动）', () {
    test('idle → tracking → horizontalLocked → idle', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      expect(s.phase, GestureSurfacePhase.idle);
      s.scaleStart(_scaleStart(1, Offset.zero));
      expect(s.phase, GestureSurfacePhase.tracking);
      // 纵向未过阈：保持 tracking。
      s.scaleUpdate(_scaleUpdate(1, const Offset(0, 4), const Offset(0, 4)));
      expect(s.phase, GestureSurfacePhase.tracking);
      // 水平占优：锁定。
      s.scaleUpdate(_scaleUpdate(1, const Offset(10, 4), const Offset(10, 0)));
      expect(s.phase, GestureSurfacePhase.horizontalLocked);
      expect(rec.scrubFrames, hasLength(1));
      s.scaleEnd(_scaleEnd());
      expect(s.phase, GestureSurfacePhase.idle);
      expect(rec.starts, [1]);
      expect(rec.ends, [_scaleEnd().pointerCount]);
    });

    test('会话中 ≥2 指 → multiFinger；scaleUpdate 未 start 内部忽略', () {
      final rec = _Recorder();
      final s = rec.bandSession();
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
      expect(rec.scrubFrames, isEmpty, reason: '未 start 的 update 内部忽略');
      s.scaleStart(_scaleStart(2, Offset.zero));
      s.scaleUpdate(_scaleUpdate(2, const Offset(0, 5), const Offset(0, 5)));
      expect(s.phase, GestureSurfacePhase.multiFinger);
      expect(rec.pinchFrames, hasLength(1), reason: '起手即双指整场按 pinch 转发');
      s.scaleEnd(_scaleEnd());
      expect(s.phase, GestureSurfacePhase.idle);
    });

    test('suppressedByMixedPinch：混区 burst 闩锁到下一 burst 首指', () {
      fakeAsync((async) {
        final pinch = CrossSurfacePinchSession(
          () => null,
          () => 800.0,
          () => null,
          (_) {},
          () => null,
        );
        final s = GestureSurfaceSession(
          axis: AxisPolicy.strictHorizontal,
          pinchSession: pinch,
          pinchSurface: PinchForwardSurface.trackBand,
          isHostAlive: () => true,
        );
        expect(s.suppressedByMixedPinch, isFalse);
        // 一指带内 + 一指他面 → 混区会话激活。
        s.pointerDown(_down(1, const Offset(100, 10)));
        pinch.blankPointerDown(2, const Offset(300, 200));
        expect(s.suppressedByMixedPinch, isTrue);
        expect(s.phase, GestureSurfacePhase.suppressed);
        s.pointerUp(_up(1));
        s.pointerUp(_up(2));
        expect(s.suppressedByMixedPinch, isTrue, reason: '闩锁到下一 burst');
        // 下一 burst 首指按下 → 复位。
        s.pointerDown(_down(3, const Offset(100, 10)));
        expect(s.suppressedByMixedPinch, isFalse);
        s.pointerUp(_up(3));
        async.flushMicrotasks();
      });
    });
  });

  group('strictHorizontal 轴锁边界', () {
    test('纵向占优不锁轴；持平不锁轴；水平占优锁定且首帧立即生效', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      // 纵向主导：不锁。
      s.scaleUpdate(_scaleUpdate(1, const Offset(0, 30), const Offset(0, 30)));
      expect(s.phase, GestureSurfacePhase.tracking);
      // 持平（|dx| == |dy|）：不锁。
      s.scaleUpdate(_scaleUpdate(1, const Offset(30, 30), const Offset(30, 0)));
      expect(s.phase, GestureSurfacePhase.tracking);
      // 水平占优：锁定，且锁定事件本身立即转发（前段位移生效）。
      s.scaleUpdate(_scaleUpdate(1, const Offset(60, 30), const Offset(30, 0)));
      expect(s.phase, GestureSurfacePhase.horizontalLocked);
      expect(rec.scrubFrames.last, const Offset(30, 0));
    });

    test('锁定后纵向增量继续转发 scrub 帧（seek 只随横向，由宿主换算）', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 9), const Offset(0, 9)));
      expect(rec.scrubFrames, hasLength(2));
      expect(rec.scrubFrames.last, const Offset(0, 9));
    });
  });

  group('铁律闩锁', () {
    test('拖出又回到原位：曾超 slop 即拖动会话，结束不判空白单击', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession();
        s.scaleStart(_scaleStart(1, Offset.zero));
        s.pointerDown(_down(1, Offset.zero));
        s.scaleUpdate(_scaleUpdate(1, const Offset(50, 0), const Offset(50, 0)));
        s.scaleUpdate(_scaleUpdate(1, Offset.zero, const Offset(-50, 0)));
        s.scaleEnd(_scaleEnd());
        s.pointerUp(_up(1));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty, reason: '闩锁：净零位移也是拖动会话');
        expect(rec.doubles, isEmpty);
      });
    });
  });

  group('burst/tap 仲裁输出', () {
    test('两次静止双指 burst → 双指双击（一次）', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        // 第一击。
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.pointerDown(_down(2, const Offset(140, 100)));
        s.pointerUp(_up(1));
        s.pointerUp(_up(2));
        async.elapse(const Duration(milliseconds: 50));
        // 第二击（判定窗口内、位置相近）。
        s.pointerDown(_down(3, const Offset(104, 100)));
        s.pointerDown(_down(4, const Offset(144, 100)));
        s.pointerUp(_up(3));
        s.pointerUp(_up(4));
        expect(rec.twoFingerDoubles, hasLength(1));
        expect(rec.singles, isEmpty);
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.twoFingerDoubles, hasLength(1), reason: '不重复触发');
      });
    });

    test('孤立单指 scale 会话空闲结束 → 约 300ms 窗口后 onSingleTap', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.pointerUp(_up(1));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        expect(rec.singles, isEmpty);
        async.elapse(const Duration(milliseconds: 400));
        expect(rec.singles, hasLength(1));
      });
    });

    test('窗口内第二次单指 tap → 单指双击（不触发单击）', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession();
        for (final p in [1, 2]) {
          s.pointerDown(_down(p, const Offset(100, 100)));
          s.scaleStart(_scaleStart(1, const Offset(100, 100)));
          s.pointerUp(_up(p));
          s.scaleEnd(_scaleEnd());
          async.flushMicrotasks();
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(rec.doubles, hasLength(1));
        expect(rec.singles, isEmpty);
      });
    });

    test('加指空转会话（其余指针仍按下）不算 tap', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.pointerDown(_down(2, const Offset(300, 100)));
        // 识别器重启的空转单指会话：起始焦点零位移、结束仍有指针按下。
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty);
        expect(rec.doubles, isEmpty);
      });
    });

    test('cancel 的 burst 不判 tap，且取消待定序列', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.pointerDown(_down(2, const Offset(140, 100)));
        s.pointerCancel(_cancel(1));
        s.pointerUp(_up(2));
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.twoFingerDoubles, isEmpty, reason: '取消的双指不是静止两击');

        // 已有待定单指序列时 burst 取消 → 序列被取消，不出单击。
        final rec2 = _Recorder();
        final s2 = rec2.bandSession();
        s2.pointerDown(_down(1, const Offset(100, 100)));
        s2.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s2.scaleEnd(_scaleEnd());
        s2.pointerUp(_up(1));
        async.flushMicrotasks();
        s2.pointerDown(_down(3, const Offset(100, 100)));
        s2.pointerCancel(_cancel(3));
        async.elapse(const Duration(milliseconds: 500));
        expect(rec2.singles, isEmpty, reason: '取消不误触发收起');
      });
    });

    test('内容命中抑制：burst 内有指针落在编辑内容上不进入 tap 判定', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession(
          isEditContent: (g) => g.dy < 40, // 上带高视为编辑内容。
        );
        s.pointerDown(_down(1, const Offset(100, 30)));
        s.pointerDown(_down(2, const Offset(140, 100)));
        s.pointerUp(_up(1));
        s.pointerUp(_up(2));
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.twoFingerDoubles, isEmpty);
        expect(rec.singles, isEmpty);
      });
    });

    test('内容命中抑制：单指空闲单击落在编辑内容上不判空白单击', () {
      fakeAsync((async) {
        final rec = _Recorder();
        // blank 形态：无 onIdleTapContent 消费钩子，空闲单击只能落到空白
        // tap 仲裁（band 形态的学习段消费钩子恒返回 true，会把这个断言
        // 变成空转）。
        final s = rec.blankSession(
          isEditContent: (g) => g.dy < 40, // 上带高视为编辑内容。
        );
        // 单指按下 → 抬起，位移仍在 slop 内（「空闲单击」的形状）：唯一区别
        // 是按下点落在编辑内容上。修前这条证据只喂双指路径，故这里会走成
        // 空白单击（块体上的一次误触把控制层收起来）。
        s.pointerDown(_down(1, const Offset(100, 30)));
        s.scaleStart(_scaleStart(1, const Offset(100, 30)));
        s.pointerMove(_move(1, const Offset(110, 30)));
        s.pointerUp(_up(1));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty, reason: '内容上的单击不是空白手势');
        expect(rec.doubles, isEmpty);
      });
    });

    test('空白处单指单击仍判空白单击（内容抑制不放宽空白语义）', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession(
          isEditContent: (g) => g.dy < 40, // 上带高视为编辑内容。
        );
        s.pointerDown(_down(1, const Offset(100, 200)));
        s.scaleStart(_scaleStart(1, const Offset(100, 200)));
        s.pointerUp(_up(1));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, hasLength(1), reason: '带级空白单击语义不变');
      });
    });
  });

  group('证据存档时序', () {
    test('burst 曾含 ≥2 指：迟到的少指 scale 会话不判空闲单击', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        // 双指 burst 结束（证据存档：maxPointers=2）。
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.pointerDown(_down(2, const Offset(140, 100)));
        s.pointerUp(_up(1));
        s.pointerUp(_up(2));
        // 迟到的单指会话（识别器重启）：零位移。
        s.pointerDown(_down(3, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.pointerUp(_up(3));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty, reason: '证据保留至下一 burst 首指');
      });
    });

    test('burst 曾位移：迟到的少指会话同样不判空闲', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.pointerMove(_move(1, const Offset(200, 100)));
        s.pointerUp(_up(1));
        s.pointerDown(_down(3, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.pointerUp(_up(3));
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty);
      });
    });
  });

  group('blank 形态（onMultiFingerWhileScrub 注入）', () {
    test('锁定 scrub 中加指：回调一次、轴锁复位、转 multiFinger', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
      expect(s.phase, GestureSurfacePhase.horizontalLocked);
      s.scaleUpdate(_scaleUpdate(2, const Offset(30, 0), const Offset(10, 0)));
      expect(rec.multiFinger, hasLength(1), reason: '冻结并按松手语义收尾');
      expect(s.phase, GestureSurfacePhase.multiFinger);
      expect(rec.pinchFrames, hasLength(1), reason: 'pinch 帧照常转发（宿主自判基准）');
    });

    test('抬回单指后水平仍占优 → 重新锁轴继续 scrub 帧', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
      s.scaleUpdate(_scaleUpdate(2, const Offset(25, 0), const Offset(5, 0)));
      s.scaleUpdate(_scaleUpdate(1, const Offset(35, 0), const Offset(10, 0)));
      expect(s.phase, GestureSurfacePhase.horizontalLocked);
      expect(rec.scrubFrames, hasLength(2), reason: '重锁后恢复微调帧');
      expect(rec.multiFinger, hasLength(1));
    });

    test('混区抑制帧：锁定中的微调立即收尾、轴锁复位、无 scrub 帧', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final pinch = CrossSurfacePinchSession(
          () => null,
          () => 800.0,
          () => null,
          (_) {},
          () => null,
        );
        final s = GestureSurfaceSession(
          axis: AxisPolicy.strictHorizontal,
          pinchSession: pinch,
          pinchSurface: PinchForwardSurface.blank,
          isHostAlive: () => true,
          onMultiFingerWhileScrub: () => rec.multiFinger.add(0),
          onScrubFrame: (d) => rec.scrubFrames.add(d.focalPointDelta),
          onPinchFrame: (d) => rec.pinchFrames.add(d.focalPointDelta),
        );
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, Offset.zero));
        s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
        // 第二指落在带面（模块面为 blank，其指针已转发 blank 侧）→ 混区
        // 激活；混区聚合由 pinch 会话自身判定，模块侧只读 burstEverMixed。
        pinch.trackBandPointerDown(2, const Offset(300, 200));
        s.scaleUpdate(_scaleUpdate(1, const Offset(30, 0), const Offset(10, 0)));
        expect(rec.multiFinger, hasLength(1), reason: '被混区抑制即收尾微调');
        expect(rec.scrubFrames, hasLength(1), reason: '抑制帧不转发 scrub');
        expect(s.phase, GestureSurfacePhase.suppressed);
        async.flushMicrotasks();
      });
    });

    test('未锁定（微调未起）时加指不触发收尾回调', () {
      final rec = _Recorder();
      final s = rec.blankSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      // 纵向累计、从未锁轴（宿主微调会话未起始）。
      s.scaleUpdate(_scaleUpdate(1, const Offset(0, 30), const Offset(0, 30)));
      s.scaleUpdate(_scaleUpdate(2, const Offset(0, 35), const Offset(0, 5)));
      expect(rec.multiFinger, isEmpty, reason: '锁定中加指才收尾（active 蕴含曾锁定）');
      expect(rec.pinchFrames, hasLength(1));
    });

    test('指针取消：微调收尾回调触发（轴锁复位）', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.scaleUpdate(_scaleUpdate(1, const Offset(120, 100), const Offset(20, 0)));
        s.pointerCancel(_cancel(1));
        expect(rec.multiFinger, hasLength(1), reason: '取消 → scrub 随之中止');
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty, reason: '取消的会话不是单击');
      });
    });
  });

  group('band 形态（无 onMultiFingerWhileScrub）', () {
    test('锁定 scrub 中加指：冻结不结束（轴锁保留），抬回单指即恢复', () {
      final rec = _Recorder();
      final s = rec.bandSession();
      s.scaleStart(_scaleStart(1, Offset.zero));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(20, 0)));
      s.scaleUpdate(_scaleUpdate(2, const Offset(25, 0), const Offset(5, 0)));
      expect(rec.multiFinger, isEmpty);
      expect(s.phase, GestureSurfacePhase.multiFinger);
      expect(rec.scrubFrames, hasLength(2), reason: '冻结帧仍转发（宿主按 pointerCount 自冻结）');
      s.scaleUpdate(_scaleUpdate(1, const Offset(35, 0), const Offset(10, 0)));
      expect(rec.scrubFrames, hasLength(3), reason: '抬回单指恢复 seek');
    });

    test('起手即双指的会话抬到剩一指：继续 pinch 帧不锁轴', () {
      final rec = _Recorder();
      final s = rec.bandSession();
      s.scaleStart(_scaleStart(2, Offset.zero));
      s.scaleUpdate(_scaleUpdate(2, const Offset(10, 0), const Offset(10, 0)));
      s.scaleUpdate(_scaleUpdate(1, const Offset(20, 0), const Offset(10, 0)));
      expect(rec.scrubFrames, isEmpty, reason: '抬到剩一指挂起等手势结束');
      expect(rec.pinchFrames, hasLength(2), reason: 'pinch 帧照常转发，宿主自判 pointerCount');
    });

    test('混区 burst 内不累计、不锁定、不转发（整场归跨面会话）', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final pinch = CrossSurfacePinchSession(
          () => null,
          () => 800.0,
          () => null,
          (_) {},
          () => null,
        );
        final s = GestureSurfaceSession(
          axis: AxisPolicy.strictHorizontal,
          pinchSession: pinch,
          pinchSurface: PinchForwardSurface.trackBand,
          isHostAlive: () => true,
        );
        s.pointerDown(_down(1, const Offset(100, 10)));
        pinch.blankPointerDown(2, const Offset(300, 200));
        s.scaleStart(_scaleStart(1, Offset.zero));
        s.scaleUpdate(_scaleUpdate(1, const Offset(50, 0), const Offset(50, 0)));
        expect(rec.scrubFrames, isEmpty);
        expect(s.phase, GestureSurfacePhase.suppressed);
        s.scaleEnd(_scaleEnd());
        s.pointerUp(_up(1));
        s.pointerUp(_up(2));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty, reason: '混区 burst 不判空白单击');
      });
    });

    test('空闲单指单击的内容消费机会：命中即不进入 tap 仲裁', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.bandSession();
        s.pointerDown(_down(1, const Offset(100, 100)));
        s.scaleStart(_scaleStart(1, const Offset(100, 100)));
        s.scaleEnd(_scaleEnd());
        s.pointerUp(_up(1));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.idleTapConsumed, hasLength(1));
        expect(rec.singles, isEmpty, reason: '学习段命中已消费');
      });
    });
  });

  group('带内双指会话', () {
    CrossSurfacePinchSession pinchWithWindow(List<TimelineWindow> updates) {
      return CrossSurfacePinchSession(
        () => const Duration(minutes: 3),
        () => 800.0,
        () => TimelineWindow.full(const Duration(minutes: 3)),
        updates.add,
        () => null,
      );
    }

    test('双指同落轨道带（控制柄/段体等子级拖区）：会话激活并驱动窗口', () {
      final updates = <TimelineWindow>[];
      // 预置非全宽窗口（全宽窗口无处可平移）。
      const base = Duration(minutes: 3);
      final preset = TimelineWindow(
        total: base,
        start: const Duration(seconds: 30),
        end: const Duration(seconds: 150),
      );
      final pinch = CrossSurfacePinchSession(
        () => base,
        () => 800.0,
        () => preset,
        updates.add,
        () => null,
      );
      expect(pinch.mixedActive, isFalse);
      // 两指都经带面转发（手柄带/学习段体的指针都汇入带 Listener）。
      pinch.trackBandPointerDown(1, const Offset(300, 10));
      expect(pinch.mixedActive, isFalse);
      pinch.trackBandPointerDown(2, const Offset(400, 10));
      expect(pinch.mixedActive, isTrue, reason: '≥2 指同在带内即激活（不要求分落两面）');
      expect(pinch.burstEverMixed, isTrue, reason: '子级拖拽/单指语义抑制依据');
      // 双指同向右移 100px（跨度不变 = 纯平移）→ 窗口随焦点平移。
      pinch.trackBandPointerMove(1, const Offset(350, 10));
      pinch.trackBandPointerMove(2, const Offset(450, 10));
      expect(updates, isNotEmpty, reason: '会话驱动窗口更新');
      expect(
        updates.last.start,
        lessThan(preset.start),
        reason: '焦点右移 → 窗口左移、锚内容跟手右移',
      );
      pinch.trackBandPointerUp(1);
      pinch.trackBandPointerUp(2);
      expect(pinch.mixedActive, isFalse);
    });

    test('双指张合（跨度放大）：窗口以锚缩放', () {
      final updates = <TimelineWindow>[];
      final pinch = pinchWithWindow(updates);
      pinch.trackBandPointerDown(1, const Offset(300, 10));
      pinch.trackBandPointerDown(2, const Offset(400, 10));
      // 张开：跨度 100 → 300，中点不动。
      pinch.trackBandPointerMove(1, const Offset(200, 10));
      pinch.trackBandPointerMove(2, const Offset(500, 10));
      expect(updates, isNotEmpty);
      expect(
        updates.last.end - updates.last.start,
        lessThan(const Duration(minutes: 3)),
        reason: '张合放大 → 可视窗口变短',
      );
      pinch.trackBandPointerUp(1);
      pinch.trackBandPointerUp(2);
    });

    test('双指同落空白面：不激活（空白面捏合归既有 scale 路径）', () {
      final updates = <TimelineWindow>[];
      final pinch = pinchWithWindow(updates);
      pinch.blankPointerDown(1, const Offset(300, 400));
      pinch.blankPointerDown(2, const Offset(400, 400));
      expect(pinch.mixedActive, isFalse, reason: '两指都不在带面');
      pinch.blankPointerMove(1, const Offset(350, 400));
      pinch.blankPointerMove(2, const Offset(450, 400));
      expect(updates, isEmpty);
      pinch.blankPointerUp(1);
      pinch.blankPointerUp(2);
    });

    test('锚点取预览线：预览线在窗口内 → 缩放以预览线为锚', () {
      final updates = <TimelineWindow>[];
      const base = Duration(minutes: 3);
      final preset = TimelineWindow(
        total: base,
        start: const Duration(seconds: 30),
        end: const Duration(seconds: 150),
      );
      final pinch = CrossSurfacePinchSession(
        () => base,
        () => 800.0,
        () => preset,
        updates.add,
        () => const Duration(seconds: 40), // 预览线在窗口内（贴左部）。
      );
      // 双指中点 x=350 → 焦点时间 82.5s；张开跨度 100→200（放大 2×）。
      pinch.trackBandPointerDown(1, const Offset(300, 10));
      pinch.trackBandPointerDown(2, const Offset(400, 10));
      pinch.trackBandPointerMove(1, const Offset(250, 10));
      pinch.trackBandPointerMove(2, const Offset(450, 10));
      expect(updates, isNotEmpty);
      // 锚 = 预览线 40s：p = (40-30)/120，s = 40 - 60/12 = 35s。
      expect(updates.last.start, const Duration(seconds: 35));
      expect(updates.last.end, const Duration(seconds: 95));
      pinch.trackBandPointerUp(1);
      pinch.trackBandPointerUp(2);
    });

    test('锚点取预览线：预览线在窗口外 → 仍以手指焦点为锚', () {
      final updates = <TimelineWindow>[];
      const base = Duration(minutes: 3);
      final preset = TimelineWindow(
        total: base,
        start: const Duration(seconds: 30),
        end: const Duration(seconds: 150),
      );
      final pinch = CrossSurfacePinchSession(
        () => base,
        () => 800.0,
        () => preset,
        updates.add,
        () => const Duration(seconds: 160), // 预览线在窗口外。
      );
      // 双指中点 x=350 → 焦点时间 82.5s；张开跨度 100→200（放大 2×）。
      pinch.trackBandPointerDown(1, const Offset(300, 10));
      pinch.trackBandPointerDown(2, const Offset(400, 10));
      pinch.trackBandPointerMove(1, const Offset(250, 10));
      pinch.trackBandPointerMove(2, const Offset(450, 10));
      expect(updates, isNotEmpty);
      // 锚 = 焦点 82.5s：p = (82.5-30)/120，s = 82.5 - 26.25 = 56.25s。
      expect(
        updates.last.start,
        const Duration(seconds: 56, microseconds: 250000),
      );
      expect(
        updates.last.end,
        const Duration(seconds: 116, microseconds: 250000),
      );
      pinch.trackBandPointerUp(1);
      pinch.trackBandPointerUp(2);
    });
  });

  group('宿主存活守卫', () {
    test('宿主销毁后微任务不再仲裁', () {
      fakeAsync((async) {
        final rec = _Recorder();
        final s = rec.blankSession();
        s.scaleStart(_scaleStart(1, Offset.zero));
        rec.alive = false;
        s.scaleEnd(_scaleEnd());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(rec.singles, isEmpty);
        rec.alive = true;
        s.dispose();
      });
    });
  });
}
