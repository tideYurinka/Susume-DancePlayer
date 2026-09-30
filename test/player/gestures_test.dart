import 'package:dance_learning_app/player/gestures.dart';
import 'package:flutter/widgets.dart' show EdgeInsets, Offset, Size;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('轴向锁定阈值（kAxisLockSlop = 18px）', () {
    test('未越过阈值前 update 返回 null', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600);

      expect(g.update(dx: 10, dy: 0), isNull);
      expect(g.update(dx: 0, dy: 5), isNull);
      // 累计位移仍 < 18。
      expect(g.update(dx: 0, dy: 2), isNull);
    });

    test('越过阈值即锁定轴向并返回动作', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600);

      expect(g.update(dx: 10, dy: 0), isNull);
      // 累计 10 + 10 = 20 ≥ 18 → 锁定水平 → seek（增量为本帧 dx）。
      final action = g.update(dx: 10, dy: 0);
      expect(action, isNotNull);
      expect(action!.type, PlayerGestureActionType.seek);
      expect(action.deltaPx, 10);
    });

    test('轴向锁定后不随后续位移切换', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600);

      g.update(dx: 10, dy: 0);
      g.update(dx: 10, dy: 0); // 锁定水平
      // 之后以垂直位移为主，仍走 seek（deltaPx 取 dx）。
      final action = g.update(dx: 2, dy: 40);
      expect(action!.type, PlayerGestureActionType.seek);
      expect(action.deltaPx, 2);
    });
  });

  group('进度滑动（水平）', () {
    test('单指右滑 → seek 正增量；左滑 → 负增量', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600);
      g.update(dx: 20, dy: 0); // 锁定水平

      expect(g.update(dx: 5, dy: 0)!.deltaPx, 5);
      expect(g.update(dx: -8, dy: 0)!.deltaPx, -8);
    });

    test('双指水平滑 → seek 动作（灵敏度倍率在换算层处理）', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 2, startX: 300, screenWidth: 600);
      g.update(dx: 20, dy: 0);

      final action = g.update(dx: 10, dy: 0);
      expect(action!.type, PlayerGestureActionType.seek);
      expect(action.deltaPx, 10);
    });
  });

  group('音量/亮度（单指垂直滑，按起始侧分支）', () {
    test('右半屏起始 → 垂直滑映射为音量，向上为增', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 450, screenWidth: 600); // 右侧
      g.update(dx: 0, dy: 10);
      g.update(dx: 0, dy: 10); // 累计 20 ≥ 18 → 锁定垂直

      final up = g.update(dx: 0, dy: -6);
      expect(up!.type, PlayerGestureActionType.volume);
      expect(up.deltaPx, 6); // -dy：向上为正

      final down = g.update(dx: 0, dy: 4);
      expect(down!.type, PlayerGestureActionType.volume);
      expect(down.deltaPx, -4);
    });

    test('左半屏起始 → 垂直滑映射为亮度', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 100, screenWidth: 600); // 左侧
      g.update(dx: 0, dy: 10);
      g.update(dx: 0, dy: 10);

      final action = g.update(dx: 0, dy: -6);
      expect(action!.type, PlayerGestureActionType.brightness);
      expect(action.deltaPx, 6);
    });

    test('起点恰在中线视为右侧（音量）', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600); // x == width/2
      g.update(dx: 0, dy: 10);
      g.update(dx: 0, dy: 10);

      expect(g.update(dx: 0, dy: -5)!.type, PlayerGestureActionType.volume);
    });

    test('双指垂直滑不绑定动作', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 2, startX: 300, screenWidth: 600);
      g.update(dx: 0, dy: 10);
      g.update(dx: 0, dy: 10); // 累计 20 ≥ 18 → 锁定垂直

      expect(g.update(dx: 0, dy: -6), isNull);
    });
  });

  group('会话生命周期', () {
    test('未 start 时 update 返回 null；end 后会话清空', () {
      final g = PlayerGestureInterpreter();
      expect(g.update(dx: 10, dy: 0), isNull);

      g.start(pointerCount: 1, startX: 300, screenWidth: 600);
      g.update(dx: 20, dy: 0);
      g.end();

      expect(g.update(dx: 10, dy: 0), isNull);
    });

    test('重复 start 重置累计位移与轴向', () {
      final g = PlayerGestureInterpreter();
      g.start(pointerCount: 1, startX: 300, screenWidth: 600);
      g.update(dx: 20, dy: 0); // 锁定水平
      g.update(dx: 10, dy: 0);

      // 新会话从 0 开始，需重新越过阈值。
      g.start(pointerCount: 1, startX: 100, screenWidth: 600);
      expect(g.update(dx: 10, dy: 0), isNull);
      final action = g.update(dx: 0, dy: 20);
      expect(action!.type, PlayerGestureActionType.brightness); // 左侧
    });
  });

  group('灵敏度换算（seekDeltaFor）', () {
    test('单指低灵敏度：100px = 5s；双指高灵敏度 ×3 = 15s', () {
      expect(
        seekDeltaFor(100, 1),
        Duration(milliseconds: (100 * kSeekSensitivityMsPerPx).round()),
      );
      expect(
        seekDeltaFor(100, 2),
        Duration(milliseconds: (100 * kSeekSensitivityMsPerPx * 3).round()),
      );
      expect(seekDeltaFor(-50, 1), const Duration(milliseconds: -2500));
    });
  });

  group('让路区几何（systemGestureYieldInsets）', () {
    test('上报值小于下限：每边取固定下限（顶 48 / 底 44 / 左右 16）', () {
      final insets = systemGestureYieldInsets(
        system: const EdgeInsets.fromLTRB(0, 10, 0, 12),
      );
      expect(insets.top, 48.0);
      expect(insets.bottom, 44.0);
      expect(insets.left, 16.0);
      expect(insets.right, 16.0);
    });

    test('上报值大于下限：取上报值（每边独立）', () {
      final insets = systemGestureYieldInsets(
        system: const EdgeInsets.fromLTRB(30, 90, 20, 60),
      );
      expect(insets.top, 90.0);
      expect(insets.bottom, 60.0);
      expect(insets.left, 30.0);
      expect(insets.right, 20.0);
    });
  });

  group('起手判定（yieldedAxes）', () {
    const screen = Size(800, 600);
    final insets = systemGestureYieldInsets(system: EdgeInsets.zero);

    test('顶区起手 → 垂直被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(400, 10),
          screen: screen,
          insets: insets,
        ),
        {PlayerGestureAxis.vertical},
      );
    });

    test('底区起手 → 垂直被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(400, 595),
          screen: screen,
          insets: insets,
        ),
        {PlayerGestureAxis.vertical},
      );
    });

    test('左区起手 → 水平被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(8, 300),
          screen: screen,
          insets: insets,
        ),
        {PlayerGestureAxis.horizontal},
      );
    });

    test('右区起手 → 水平被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(795, 300),
          screen: screen,
          insets: insets,
        ),
        {PlayerGestureAxis.horizontal},
      );
    });

    test('顶区与侧区重叠（屏幕极窄）→ 两轴同时被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(8, 20),
          screen: screen,
          insets: insets,
        ),
        {PlayerGestureAxis.vertical, PlayerGestureAxis.horizontal},
      );
    });

    test('让路区外起手 → 两轴都不被禁', () {
      expect(
        yieldedAxes(
          downPosition: const Offset(400, 300),
          screen: screen,
          insets: insets,
        ),
        isEmpty,
      );
    });

    test('起手点缺失 → 不让路', () {
      expect(
        yieldedAxes(downPosition: null, screen: screen, insets: insets),
        isEmpty,
      );
    });

    test('解释器锁到被禁轴的会话整场无动作；未禁轴照常', () {
      final g = PlayerGestureInterpreter()
        ..start(
          pointerCount: 1,
          startX: 400,
          screenWidth: 800,
          yieldedAxes: const {PlayerGestureAxis.vertical},
        );
      expect(g.update(dx: 0, dy: -100), isNull);
      expect(g.update(dx: 0, dy: -100), isNull, reason: '锁到被禁轴后整场无动作');
      expect(g.update(dx: 60, dy: 0), isNull, reason: '不退化为另一轴');

      final gFree = PlayerGestureInterpreter()
        ..start(
          pointerCount: 1,
          startX: 400,
          screenWidth: 800,
          yieldedAxes: const {PlayerGestureAxis.vertical},
        );
      expect(gFree.update(dx: 30, dy: 0)!.type, PlayerGestureActionType.seek);
    });
  });
}
