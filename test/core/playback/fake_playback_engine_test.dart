import 'package:fake_async/fake_async.dart';
import '../../helpers/video_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_playback_engine.dart';

void main() {
  group('FakePlaybackEngine（首条基于 FakeEngine 的测试）', () {
    test('open 记录 source 并发出 position 0（不自动播放）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final positions = <Duration>[];
        engine.positionStream.listen(positions.add);

        engine.open(Uri.file('/videos/a.mp4'));
        async.flushMicrotasks();

        expect(engine.source, Uri.file('/videos/a.mp4'));
        expect(engine.isPlaying, isFalse);
        expect(positions, [Duration.zero]);
      });
    });

    test('play 后 position 随墙钟推进（默认 1.0 倍速）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final positions = <Duration>[];
        engine.positionStream.listen(positions.add);

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));

        expect(engine.isPlaying, isTrue);
        expect(positions.last, const Duration(seconds: 1));
      });
    });

    test('pause 冻结 position，play 从冻结处继续', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(milliseconds: 500));
        engine.pause();
        async.elapse(const Duration(seconds: 2));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(milliseconds: 500));

        engine.play();
        async.elapse(const Duration(milliseconds: 500));
        expect(engine.position, const Duration(seconds: 1));
      });
    });

    test('setRate 任意倍速：position 按 rate 折算推进', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        engine.setRate(0.5);
        async.elapse(const Duration(seconds: 2));

        expect(engine.rate, 0.5);
        expect(engine.position, const Duration(seconds: 1));
      });
    });

    test('seek 帧级定位（含越界收敛到 [0, duration]）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
        final positions = <Duration>[];
        engine.positionStream.listen(positions.add);

        engine.seek(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(engine.position, const Duration(seconds: 30));

        engine.seek(const Duration(seconds: -5));
        expect(engine.position, Duration.zero);

        engine.seek(const Duration(minutes: 2));
        expect(engine.position, const Duration(minutes: 1));
      });
    });

    test('seek 补发的位置事件携带 seek 目标（真实内核同口径）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(minutes: 1));
        final echoed = <Duration>[];
        engine.positionStream.listen(echoed.add);

        engine.seek(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(echoed.last, const Duration(seconds: 30),
            reason: '补发事件携带 seek 目标，不携带 seek 之前的旧位置');
      });
    });

    test('播放到尾：发出一次 completed，isPlaying 变 false，position 停在尾', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final completed = <void>[];
        engine.completedStream.listen((_) => completed.add(null));

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 2));

        expect(completed, hasLength(1));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 1));
      });
    });

    test('到尾后再次 play 从头开始并再次触发 completed', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final completed = <void>[];
        engine.completedStream.listen((_) => completed.add(null));

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 2));
        expect(completed, hasLength(1));

        engine.play();
        async.elapse(const Duration(seconds: 2));
        expect(completed, hasLength(2));
        expect(engine.position, const Duration(seconds: 1));
      });
    });

    test('播放中 open 新源：旧节拍取消，position 归零后重新推进', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));
        expect(engine.position, const Duration(seconds: 1));

        engine.open(Uri.file('/videos/b.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));
        expect(engine.source, Uri.file('/videos/b.mp4'));
        // 旧节拍已取消：只推进了新源打开后的 1s。
        expect(engine.position, const Duration(seconds: 1));
      });
    });

    test('dispose 幂等：重复调用不抛错', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        engine.dispose();
        expect(() => engine.dispose(), returnsNormally);
      });
    });

    test('dispose 后停止推进并关闭流', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final done = <Object?>[];
        engine.positionStream.listen((_) {}, onDone: () => done.add(null));

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        engine.dispose();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        expect(engine.isDisposed, isTrue);
        expect(engine.isPlaying, isFalse);
        expect(engine.position, Duration.zero);
        // 流已关闭：onDone 已发出。
        expect(done, hasLength(1));
      });
    });
  });

  group('FakePlaybackEngine.buildVideoSurface（渲染接缝）', () {
    testWidgets('返回带 videoSurfacePlaceholderKey 的 contain 占位控件', (
      tester,
    ) async {
      final engine = FakePlaybackEngine(videoAspectRatio: 9 / 16);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: engine.buildVideoSurface())),
      );
      expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);
    });

    testWidgets('宽高比未知时占位填满可用区域', (tester) async {
      tester.view.physicalSize = const Size(1600, 800); // 合成档 800×400dp（dpr 2.0），非设备档。
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      final engine = FakePlaybackEngine(); // videoAspectRatio = null
      await tester.pumpWidget(
        // 与播放页一致的全幅容器（Scaffold body 为松约束，ColoredBox
        // 在松约束下收缩为 0，不反映实际使用）。
        MaterialApp(
          home: Scaffold(
            body: SizedBox.expand(child: engine.buildVideoSurface()),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(videoSurfacePlaceholderKey)),
        const Size(800, 400),
      );
    });
  });
}
