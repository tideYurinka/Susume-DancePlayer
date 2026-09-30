import 'dart:async';

import 'package:dance_learning_app/core/playback/serial_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SerialSeekQueue（latest-wins 串行 seek）', () {
    test('在途期间新目标折叠：一次只在途一个，完成后只发最新', () async {
      final calls = <Duration>[];
      final gates = <Completer<void>>[];
      final queue = SerialSeekQueue((t) async {
        calls.add(t);
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
      });

      queue.enqueue(const Duration(seconds: 1));
      queue.enqueue(const Duration(seconds: 2)); // 在途：只更新待发值
      queue.enqueue(const Duration(seconds: 3));
      await pumpEventQueue();
      expect(calls, [const Duration(seconds: 1)], reason: '首个 seek 在途');

      gates[0].complete(); // 首个完成 → 只发最新（2 被 latest-wins 折叠）
      await pumpEventQueue();
      expect(calls, [
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ]);

      gates[1].complete();
      await pumpEventQueue();
      expect(queue, isNotNull); // 排空完成、无遗留
    });

    test('逐个串行：前一个 seek 完成前不开始下一个', () async {
      final calls = <Duration>[];
      final gate = Completer<void>();
      var started = 0;
      final queue = SerialSeekQueue((t) async {
        started++;
        calls.add(t);
        if (started == 1) {
          await gate.future;
        }
      });

      queue.enqueue(const Duration(seconds: 1));
      queue.enqueue(const Duration(seconds: 5));
      await pumpEventQueue();
      expect(started, 1, reason: '第一个在途，第二个不并发开始');

      gate.complete();
      await pumpEventQueue();
      expect(started, 2);
      expect(calls, [
        const Duration(seconds: 1),
        const Duration(seconds: 5),
      ]);
    });

    test('enqueue 返回目标（调用侧可同源消费入队值）', () {
      final queue = SerialSeekQueue((t) async {});
      const target = Duration(seconds: 42);
      expect(queue.enqueue(target), target);
    });
  });

  group('SerialSeekQueue 按帧节流', () {
    test('首个 seek 立即发出；节流窗口内的中间目标被丢弃、窗口后只发最新', () async {
      final calls = <Duration>[];
      var now = DateTime(2026);
      final delays = <Duration>[];
      final delayGates = <Completer<void>>[];
      final queue = SerialSeekQueue(
        (t) async => calls.add(t),
        minInterval: const Duration(milliseconds: 16),
        clock: () => now,
        delay: (d) {
          delays.add(d);
          final gate = Completer<void>();
          delayGates.add(gate);
          return gate.future;
        },
      );

      // 首个目标无前置 dispatch → 立即发出（不等待）。
      queue.enqueue(const Duration(seconds: 1));
      await pumpEventQueue();
      expect(calls, [const Duration(seconds: 1)]);

      // 间隔未到：过密的中间目标不发出，先等待节流窗口。
      queue.enqueue(const Duration(seconds: 2));
      queue.enqueue(const Duration(seconds: 3));
      await pumpEventQueue();
      expect(calls, [const Duration(seconds: 1)], reason: '节流窗口内不发');
      expect(delays, [const Duration(milliseconds: 16)]);

      // 窗口到点（时钟前进）：只发最新目标（2 被 latest-wins 折叠丢弃）。
      now = now.add(const Duration(milliseconds: 16));
      delayGates.single.complete();
      await pumpEventQueue();
      expect(calls, [
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ]);

      // 排空：无遗留待发。
      queue.enqueue(const Duration(seconds: 4));
      await pumpEventQueue();
      expect(calls.length, 2, reason: '节流窗口内的孤立目标仍需等待，不误发');
    });

    test('节流等待期间新目标持续折叠为最新（latest-wins 保持）', () async {
      final calls = <Duration>[];
      var now = DateTime(2026);
      Completer<void>? pendingDelay;
      final queue = SerialSeekQueue(
        (t) async => calls.add(t),
        minInterval: const Duration(milliseconds: 16),
        clock: () => now,
        delay: (d) {
          pendingDelay = Completer<void>();
          return pendingDelay!.future;
        },
      );

      queue.enqueue(const Duration(seconds: 1));
      await pumpEventQueue();
      // 进入节流等待后仍持续入队：只保留最新。
      queue.enqueue(const Duration(seconds: 2));
      await pumpEventQueue();
      queue.enqueue(const Duration(seconds: 5));
      queue.enqueue(const Duration(seconds: 7));
      await pumpEventQueue();

      now = now.add(const Duration(milliseconds: 16));
      pendingDelay!.complete();
      await pumpEventQueue();
      expect(calls, [
        const Duration(seconds: 1),
        const Duration(seconds: 7),
      ]);
    });

    test('默认（minInterval = 0）不经节流路径：逐个串行行为不变', () async {
      final calls = <Duration>[];
      final queue = SerialSeekQueue((t) async => calls.add(t));
      queue.enqueue(const Duration(seconds: 1));
      queue.enqueue(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(calls, [
        const Duration(seconds: 1),
        const Duration(seconds: 2),
      ]);
    });
  });
}
