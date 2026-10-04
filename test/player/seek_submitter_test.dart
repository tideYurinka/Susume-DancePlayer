import 'dart:async';

import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/core/playback/seek_submitter.dart';
import 'package:dance_learning_app/core/playback/serial_seek.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// SeekSubmitter 模块面测试（提交口只
/// 写显示值）：假时钟 + 记录型 clearLoops + 记录型 engineSeek，直接驱动
/// `submit` / `submitAndSettle`，断言内部固定次序（钳制 → clearLoops →
/// 入队 → displayHead）、返回钳制后实际入队值、节流折叠、total 未知分支与
/// 落定语义。
void main() {
  late List<String> events; // 事件序：'clearLoops' / 'seek:<t>'
  late List<Duration> seeks;
  late ValueNotifier<Duration> displayHead;
  var now = DateTime(2026);
  final delays = <Duration>[];

  SeekSubmitter build({
    Duration minInterval = Duration.zero,
    Duration? Function()? total,
    DateTime Function()? clock,
    Future<void> Function(Duration delay)? delay,
    ValueNotifier<Duration>? head,
    AnnotationTimeline Function()? timelineDuration,
  }) {
    events = <String>[];
    seeks = <Duration>[];
    delays.clear();
    displayHead = head ?? ValueNotifier(Duration.zero);
    final AnnotationTimeline Function() tlFn =
        timelineDuration ??
        () => AnnotationTimeline.wholeVideo(const Duration(seconds: 10));
    return SeekSubmitter(
      engineSeek: (t) async {
        events.add('seek:$t');
        seeks.add(t);
      },
      minInterval: minInterval,
      clock: clock ?? () => now,
      delay:
          delay ??
          (d) {
            delays.add(d);
            now = now.add(d);
            return Future<void>.value();
          },
      total: total ?? () => const Duration(seconds: 10),
      timeline: tlFn,
      clearLoops: (tl, t) {
        events.add('clearLoops');
      },
      displayHead: displayHead,
    );
  }

  group('SeekSubmitter.submit（唯一提交口）', () {
    test('钳制到 [0, total] 并返回钳制后实际入队值', () async {
      final s = build();
      expect(
        s.submit(const Duration(seconds: 12)),
        const Duration(seconds: 10),
      );
      expect(s.submit(const Duration(seconds: -3)), Duration.zero);
      await pumpEventQueue();
      expect(seeks, [const Duration(seconds: 10), Duration.zero]);
    });

    test('内部次序：clearLoops 先于入队', () {
      final s = build();
      s.submit(const Duration(seconds: 1));
      expect(events, ['clearLoops', 'seek:0:00:01.000000']);
    });

    test('displayHead 每次落点被写（与 seek 同源）；提交口不写窗口', () {
      final s = build();
      final seen = <Duration>[];
      s.submit(const Duration(seconds: 1));
      seen.add(displayHead.value);
      s.submit(const Duration(seconds: 2));
      seen.add(displayHead.value);
      expect(seen, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('clearLoops 收到 timeline() 派生与钳制后目标（宿主完整 helper 恒含临时段）', () {
      AnnotationTimeline? received;
      final tl = AnnotationTimeline.wholeVideo(const Duration(seconds: 10));
      events = <String>[];
      seeks = <Duration>[];
      final s = SeekSubmitter(
        engineSeek: (t) async => seeks.add(t),
        total: () => const Duration(seconds: 10),
        timeline: () => tl,
        clearLoops: (timeline, t) => received = timeline,
        displayHead: null,
      );
      s.submit(const Duration(seconds: 99));
      expect(identical(received, tl), isTrue);
      expect(seeks, [const Duration(seconds: 10)]);
    });

    test('total 未知（null）：只钳 ≥0、照常入队', () async {
      final s = build(total: () => null);
      expect(s.submit(const Duration(seconds: -1)), Duration.zero);
      expect(
        s.submit(const Duration(seconds: 999)),
        const Duration(seconds: 999),
        reason: '无上界不钳',
      );
      await pumpEventQueue();
      expect(seeks, [Duration.zero, const Duration(seconds: 999)]);
    });

    test('total ≤0：与未知同分支', () async {
      final s = build(total: () => Duration.zero);
      expect(s.submit(const Duration(seconds: -1)), Duration.zero);
      expect(displayHead.value, Duration.zero);
    });
  });

  group('SeekSubmitter 节流（内部 SerialSeekQueue）', () {
    test('minInterval 16ms：窗口内中间目标折叠，只发最新', () async {
      final s = build(minInterval: kScrubSeekMinInterval);
      s.submit(const Duration(seconds: 1)); // 首个立即发出
      s.submit(const Duration(seconds: 2)); // 节流窗口内：折叠为待发
      s.submit(const Duration(seconds: 3));
      await pumpEventQueue();
      // 节流等待经注入 delay 前进假时钟后放行 → 最新目标必达。
      await pumpEventQueue();
      expect(delays, contains(kScrubSeekMinInterval));
      expect(seeks, [
        const Duration(seconds: 1),
        const Duration(seconds: 3),
      ], reason: '首个立即发出，窗口内中间目标 2s 被折叠，只发最新 3s');
    });

    test('minInterval zero（player）：不节流，逐个串行发出', () async {
      final s = build();
      s.submit(const Duration(seconds: 1));
      s.submit(const Duration(seconds: 2));
      await pumpEventQueue();
      expect(delays, isEmpty);
      expect(seeks, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });
  });

  group('SeekSubmitter.submitAndSettle（单发并等队列排空）', () {
    test('等待在途与节流 seek 全部落定后完成', () async {
      final gate = Completer<void>();
      var now0 = DateTime(2026);
      events = <String>[];
      seeks = <Duration>[];
      delays.clear();
      final s = SeekSubmitter(
        engineSeek: (t) async {
          events.add('seek:$t');
          seeks.add(t);
          if (t == const Duration(seconds: 1)) await gate.future;
        },
        minInterval: kScrubSeekMinInterval,
        clock: () => now0,
        delay: (d) async {
          delays.add(d);
          now0 = now0.add(d);
        },
        total: () => const Duration(seconds: 10),
        timeline: () =>
            AnnotationTimeline.wholeVideo(const Duration(seconds: 10)),
        clearLoops: (_, _) => events.add('clearLoops'),
      );
      s.submit(const Duration(seconds: 1)); // 在途（被 gate 挡住）
      final settled = s.submitAndSettle(const Duration(seconds: 4));
      var done = false;
      unawaited(settled.then((_) => done = true));
      await pumpEventQueue();
      expect(done, isFalse, reason: '在途 seek 未完成前不落定');
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();
      expect(done, isTrue);
      expect(seeks, [const Duration(seconds: 1), const Duration(seconds: 4)]);
    });

    test('submitAndSettle 同样钳制并在落定后写 displayHead', () async {
      final s = build();
      await s.submitAndSettle(const Duration(seconds: 99));
      expect(seeks, [const Duration(seconds: 10)]);
      expect(displayHead.value, const Duration(seconds: 10));
    });
  });
}
