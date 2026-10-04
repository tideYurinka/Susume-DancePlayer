import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_loop_layer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_playback_engine.dart';

void main() {
  group('PlaybackLoopLayer（AB 区间循环薄层，预留接缝）', () {
    test('播放到 B 点帧级 seek 回 A，循环继续推进', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        // 5s 处 seek 回 2s，此后继续推进 1s → 3s。
        async.elapse(const Duration(seconds: 6));

        expect(engine.position, const Duration(seconds: 3));
        expect(loop.enabled, isTrue);

        loop.disableLoop();
        expect(loop.enabled, isFalse);
      });
    });

    test('禁用后播放越过 B 点不再 seek 回 A', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 4));
        loop.disableLoop();
        async.elapse(const Duration(seconds: 2));

        // 4s + 2s = 6s，不再回跳。
        expect(engine.position, const Duration(seconds: 6));
      });
    });

    test('a >= b 视为未启用', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);

        loop.enableLoop(
          a: const Duration(seconds: 5),
          b: const Duration(seconds: 5),
        );
        expect(loop.enabled, isFalse);

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 7));
        expect(engine.position, const Duration(seconds: 7));
      });
    });

    test('dispose 后取消 position 订阅，不再 seek', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        loop.dispose();
        async.elapse(const Duration(seconds: 7));

        expect(engine.position, const Duration(seconds: 7));
      });
    });

    test('每次回到 A 点发布递增循环遍数事件', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);
        final events = <int>[];
        final subscription = loop.loopCountStream.listen(events.add);

        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 6));
        async.elapse(const Duration(seconds: 3));

        expect(loop.loopCount, 2);
        expect(events, const [1, 2]);

        subscription.cancel();
      });
    });

    test('重新启用循环开始新的遍数计数会话', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);

        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 6));
        expect(loop.loopCount, 1);

        loop.disableLoop();
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        expect(loop.loopCount, 0);

        async.elapse(const Duration(seconds: 2));
        expect(loop.loopCount, 1);
      });
    });

    test('帧级 seek 在途时忽略后续 B 点 tick，一圈只计数一次', () {
      fakeAsync((async) {
        final release = Completer<void>();
        final engine = _DelayedSeekEngine(
          release: release,
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(milliseconds: 5100));

        expect(engine.seekStarts, 1);
        expect(loop.loopCount, 1);

        release.complete();
        async.flushMicrotasks();
      });
    });

    test('启用循环时进度已在 B 点后不提前计数，等回到区间后再计', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 10),
        );
        final loop = PlaybackLoopLayer(engine);

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 7));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.play();
        async.elapse(const Duration(milliseconds: 100));

        expect(engine.position, const Duration(milliseconds: 7100));
        expect(loop.loopCount, 0);
      });
    });
  });

  group('循环前导（到段尾 seek 段首−前导拍数连续播放，替代静帧）', () {
    test('到段尾 seek 到段首−前导时长连续播放；期间发布前导态，播过段首结束', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        final leadStates = <bool>[];
        loop.delayedLoopActiveStream.listen(leadStates.add);

        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 5));

        // 到达 B（5s）：seek 到段首−前导（2s−2s=0）连续播放，全程在播。
        expect(engine.seekCalls, contains(Duration.zero));
        expect(engine.isPlaying, isTrue);
        expect(loop.delayedLoopActive, isTrue);
        expect(loop.loopCount, 1);

        // 播过段首（2s）：前导态结束，进入正式练习区。
        async.elapse(const Duration(seconds: 2));
        expect(loop.delayedLoopActive, isFalse);
        expect(engine.isPlaying, isTrue);

        // 再到段尾：下一圈前导照常（循环成立）。
        async.elapse(const Duration(seconds: 3));
        expect(loop.loopCount, 2);
        expect(engine.seekCalls.where((c) => c == Duration.zero), hasLength(2));
        expect(leadStates, const [true, false, true]);
      });
    });

    test('段首前余量不足前导时长：前导起点钳到视频 0 处', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.updateDelayedLoopWait(const Duration(seconds: 4));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 5));

        expect(engine.seekCalls, contains(Duration.zero));
        expect(engine.position, Duration.zero);
        expect(loop.delayedLoopActive, isTrue);
      });
    });

    test('不延迟（前导时长为零）= 立即回段首，从不发布前导态', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        final leadStates = <bool>[];
        loop.delayedLoopActiveStream.listen(leadStates.add);
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 5));

        expect(engine.seekCalls, contains(const Duration(seconds: 2)));
        expect(engine.isPlaying, isTrue);
        expect(loop.delayedLoopActive, isFalse);
        expect(leadStates, isEmpty);
      });
    });

    test('前导期间手动 seek 段内：前导态结束、从落点续播，下圈前导照常', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 6),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 6));
        expect(loop.delayedLoopActive, isTrue);
        expect(engine.position, Duration.zero);

        // 前导期间手动 seek 到段内：前导态结束，从落点续播。
        engine.seek(const Duration(seconds: 3));
        async.elapse(const Duration(milliseconds: 100));
        expect(loop.delayedLoopActive, isFalse);
        expect(engine.isPlaying, isTrue);

        // 续播到段尾（3s）+ 前导回到段首−前导（0）：第 2 圈前导正常建立。
        async.elapse(const Duration(seconds: 3));
        expect(loop.loopCount, 2);
        expect(loop.delayedLoopActive, isTrue);
        expect(engine.position, lessThan(const Duration(milliseconds: 500)));
      });
    });

    test('前导期间手动 seek 出段（越过 B）：取消前导、不自动回段首', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        final leadStates = <bool>[];
        loop.delayedLoopActiveStream.listen(leadStates.add);
        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 5));
        expect(loop.delayedLoopActive, isTrue);

        // 手动 seek 越过段尾：取消前导，不被拽回前导起点。
        engine.seek(const Duration(seconds: 12));
        async.elapse(const Duration(milliseconds: 100));
        expect(loop.delayedLoopActive, isFalse);

        async.elapse(const Duration(seconds: 3));
        expect(engine.seekCalls, isNot(contains(const Duration(seconds: 2))));
        expect(
          engine.position,
          greaterThanOrEqualTo(const Duration(seconds: 15)),
        );
        expect(loop.loopCount, 1);
        expect(leadStates, const [true, false]);
      });
    });

    test('前导期间手动 seek 出段（早于前导起点）：取消前导、不拉回', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 4),
          b: const Duration(seconds: 6),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 6));
        expect(loop.delayedLoopActive, isTrue);
        expect(engine.position, const Duration(seconds: 2));

        engine.seek(const Duration(milliseconds: 300));
        async.elapse(const Duration(milliseconds: 100));
        expect(loop.delayedLoopActive, isFalse);
        expect(engine.position, const Duration(milliseconds: 400));
      });
    });

    test('disableLoop 打断前导：前导态取消，引擎保持播放、不再 seek', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        final leadStates = <bool>[];
        loop.delayedLoopActiveStream.listen(leadStates.add);
        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 5));
        expect(loop.delayedLoopActive, isTrue);

        loop.disableLoop();
        expect(loop.delayedLoopActive, isFalse);
        expect(engine.isPlaying, isTrue, reason: '前导是播放态，打断不停住画面');

        async.elapse(const Duration(seconds: 5));
        expect(engine.seekCalls, isNot(contains(const Duration(seconds: 2))));
        expect(loop.loopCount, 1);
        expect(leadStates, const [true, false]);
      });
    });

    test('前导 seek 在途：不重复触发（一圈只计一次），落定后发布前导态', () {
      fakeAsync((async) {
        final release = Completer<void>();
        final engine = _DelayedSeekEngine(
          release: release,
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        final leadStates = <bool>[];
        loop.delayedLoopActiveStream.listen(leadStates.add);
        loop.updateDelayedLoopWait(const Duration(seconds: 2));
        loop.enableLoop(
          a: const Duration(seconds: 2),
          b: const Duration(seconds: 5),
        );

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(milliseconds: 5100));

        // 前导 seek 在途：引擎继续播过 B，也不重复计圈/触发。
        expect(engine.seekStarts, 1);
        expect(loop.loopCount, 1);
        expect(loop.delayedLoopActive, isFalse, reason: 'seek 落定前不发布前导态');

        release.complete();
        async.flushMicrotasks();
        expect(loop.delayedLoopActive, isTrue);
        expect(leadStates, const [true]);
      });
    });

    test('dispose 打断前导：前导态取消、不再 seek', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        loop.updateDelayedLoopWait(const Duration(seconds: 4));
        loop.enableLoop(
          a: const Duration(seconds: 4),
          b: const Duration(seconds: 6),
        );
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 6));
        expect(loop.delayedLoopActive, isTrue);

        loop.dispose();
        async.elapse(const Duration(seconds: 6));
        expect(loop.delayedLoopActive, isFalse);
        expect(engine.seekCalls, isNot(contains(const Duration(seconds: 4))));
      });
    });
  });

  group('短段 tick 防御', () {
    test('短学习段 tick 跨越：越过 B 的 tick 视为已进入，循环照常触发', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 20),
        );
        final loop = PlaybackLoopLayer(engine);
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        // 段长 50ms < tick 间隔 100ms：无任何 tick 落在 [a,b) 内，
        // 进度从段外（< a）一条 tick 直接越过 B。
        loop.enableLoop(
          a: const Duration(milliseconds: 2000),
          b: const Duration(milliseconds: 2050),
        );
        engine.seek(const Duration(milliseconds: 1950));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        expect(
          loop.loopCount,
          greaterThanOrEqualTo(1),
          reason: '越过 B 的 tick 视为已进入区间，循环不再永不触发',
        );
        expect(engine.seekCalls, contains(const Duration(milliseconds: 2000)));
        expect(engine.isPlaying, isTrue);
      });
    });
  });
}

class _DelayedSeekEngine extends FakePlaybackEngine {
  _DelayedSeekEngine({required this.release, required super.duration});

  final Completer<void> release;
  int seekStarts = 0;

  @override
  Future<void> seek(Duration position) {
    seekStarts++;
    return release.future.then((_) => super.seek(position));
  }
}
