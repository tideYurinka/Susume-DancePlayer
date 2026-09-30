import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/player/loop_prompt.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

void main() {
  group('八拍时长（节拍 seam 占位换算）', () {
    test('默认 120 BPM：一个八拍 = 4s', () {
      expect(placeholderBeatGrid.eightBeatNominal, const Duration(seconds: 4));
    });

    test('BPM 可配置换算', () {
      expect(const UniformBeatGrid(bpm: 60).eightBeatNominal, const Duration(seconds: 8));
      expect(const UniformBeatGrid(bpm: 240).eightBeatNominal, const Duration(seconds: 2));
    });
  });

  group('LoopPromptController（FakeEngine 完成事件驱动）', () {
    test('播放到尾进入 countdown，一个八拍后自动从头循环播放', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1)); // 播放到尾 → completed

        expect(controller.phase, LoopPromptPhase.countdown);
        expect(autoLoopStarted, 0);

        // 延迟一个八拍（默认 120 BPM → 4s）后自动循环：从头重新播放。
        async.elapse(placeholderBeatGrid.eightBeatNominal);

        expect(controller.phase, LoopPromptPhase.idle);
        expect(autoLoopStarted, 1);
        expect(engine.isPlaying, isTrue);
        expect(engine.position, Duration.zero);

        controller.dispose();
      });
    });

    test('「不循环」停留于结尾，本次播放会话不再自动循环', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dismiss();
        expect(controller.phase, LoopPromptPhase.dismissed);
        expect(controller.dismissed, isTrue);

        // 倒计时已取消：停留于结尾，不自动循环。
        async.elapse(const Duration(seconds: 10));
        expect(autoLoopStarted, 0);
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 1));

        // 手动重新播放到尾：不再提示、不再自动循环。
        engine.play();
        expect(engine.position, Duration.zero);
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.dismissed);
        expect(engine.isPlaying, isFalse);
        async.elapse(const Duration(seconds: 10));
        expect(autoLoopStarted, 0);
        expect(engine.position, const Duration(seconds: 1));

        controller.dispose();
      });
    });

    test('countdown 中再次到尾不重复触发（防御）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.countdown);

        // 模拟 countdown 期间重复 completed：阶段不变、不重启倒计时。
        engine.seek(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 2));
        expect(controller.phase, LoopPromptPhase.countdown);
        expect(autoLoopStarted, 0);

        controller.dispose();
      });
    });

    test('dispose 取消倒计时与订阅，不再自动循环', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
        async.elapse(const Duration(seconds: 10));

        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 1));
      });
    });
  });

  group('LoopPromptController（视频首/尾区间驱动）', () {
    test('播放到视频尾停止于尾边界，一个八拍后从视频首循环', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 19));
        engine.play();
        async.elapse(const Duration(seconds: 1));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));
        expect(controller.phase, LoopPromptPhase.countdown);

        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(controller.phase, LoopPromptPhase.idle);
        expect(engine.isPlaying, isTrue);
        expect(
          engine.position,
          greaterThanOrEqualTo(const Duration(seconds: 10)),
        );
        expect(engine.position, lessThan(const Duration(seconds: 11)));
        expect(autoLoopStarted, 1);

        controller.dispose();
      });
    });

    test('节拍异常态秒制兜底：注入不可用网格，提示延迟一个八拍 = 固定 4s', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 1),
        );
        final controller = LoopPromptController(
          engine,
          gridOf: () => const UnavailableBeatGrid(),
        );
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1)); // 播放到尾 → completed
        expect(controller.phase, LoopPromptPhase.countdown);

        // 4s 兜底窗口内未到点不循环。
        async.elapse(const Duration(seconds: 3, milliseconds: 999));
        expect(controller.phase, LoopPromptPhase.countdown);
        expect(autoLoopStarted, 0);

        async.elapse(const Duration(milliseconds: 1)); // 共 4s 到点
        expect(controller.phase, LoopPromptPhase.idle);
        expect(autoLoopStarted, 1);
        expect(engine.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('视频尾点「不循环」后本次播放不再自动循环', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 19));
        engine.play();
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dismiss();
        async.elapse(placeholderBeatGrid.eightBeatNominal + const Duration(seconds: 1));
        expect(controller.phase, LoopPromptPhase.dismissed);
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));

        controller.dispose();
      });
    });

    test('未自定义边界时物理完成保持既有行为', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);
        engine.open(Uri.file('/videos/a.mp4'), play: true);
        async.elapse(const Duration(seconds: 1));

        expect(controller.phase, LoopPromptPhase.countdown);
        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(engine.position, Duration.zero);

        controller.dispose();
      });
    });

    test('手动拖放行：显式拖过尾线打放行标记，播放放行到片尾不拦截', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        // 手动拖过尾线（25s）打放行标记后起播：播过尾边界不停、不弹提示。
        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 25));
        async.elapse(Duration.zero); // 排空 open/seek 的挂起位置事件
        controller.markManualSeek(const Duration(seconds: 25));
        engine.play();
        async.elapse(const Duration(seconds: 3));
        expect(engine.isPlaying, isTrue);
        expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 28)));
        expect(controller.phase, LoopPromptPhase.idle);
        expect(autoLoopStarted, 0);

        controller.dispose();
      });
    });

    test('无放行标记的自动 seek 落在尾线右侧：起播按到尾语义钳回尾线并提示', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );

        // 续播/自动 seek 到尾线右侧（25s，无放行标记）：起播停在新尾线。
        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 25));
        engine.play();
        async.elapse(const Duration(milliseconds: 500));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('起点恰在尾线：不视为界外，起播按无标记语义放行到物理尾', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        async.elapse(Duration.zero); // 排空 open 的挂起位置事件
        engine.seek(const Duration(seconds: 20));
        async.elapse(Duration.zero);
        engine.play();
        async.elapse(const Duration(seconds: 10)); // 从尾线播到物理尾
        // 精确停在尾线不是跨线：播放继续到物理尾 → completed 提示。
        expect(engine.position, const Duration(seconds: 30));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('暂停中边界改写把尾线移到播放头左侧：下次起播按新区间到尾语义钳回', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 20),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 15));
        engine.play();
        async.elapse(const Duration(milliseconds: 300));
        engine.pause();
        async.elapse(const Duration(milliseconds: 100));
        // 暂停中尾线移到播放头左侧（12s < 15s）：不打断，起播才钳回。
        controller.updateVideoRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 12),
        );
        expect(engine.position, const Duration(seconds: 15, milliseconds: 300));
        engine.play();
        async.elapse(const Duration(milliseconds: 500));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 12));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('播放中自动边界改写把尾线移到播放头左侧：立即停在新尾线并提示', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 2),
            end: const Duration(seconds: 20),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 15));
        engine.play();
        async.elapse(const Duration(milliseconds: 300));
        // 播放中尾线被自动改写到播放头左侧（14s < 播放头）：立即停。
        controller.updateVideoRange(
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 14),
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 14));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('段循环解除激活：抑制窗口收窄——在播越尾线立即停+提示，不整会话放开', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );
        engine.open(Uri.file('/videos/a.mp4'));

        // 段循环接管期间（播放头 25s 在段外）：视频尾拦截被抑制。
        controller.setSegmentLoopActive(true);
        engine.seek(const Duration(seconds: 25));
        async.elapse(Duration.zero);
        engine.play();
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.isPlaying, isTrue);
        expect(controller.phase, LoopPromptPhase.idle);

        // 解除激活（宿主随后按现时间线 updateVideoRange 重断言）：
        // 不再整会话放开——立即停在新尾线并提示。
        controller.setSegmentLoopActive(false);
        controller.updateVideoRange(
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        );
        async.elapse(const Duration(milliseconds: 200));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('段循环恢复越界：激活期起播在视频尾右侧无标记，交还后钳回拦截', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );
        engine.open(Uri.file('/videos/a.mp4'));

        // 恢复（不 seek）就位段循环激活：起播边沿不钳回（段循环接管）。
        controller.setSegmentLoopActive(true);
        engine.seek(const Duration(seconds: 25));
        async.elapse(Duration.zero);
        engine.play();
        async.elapse(const Duration(milliseconds: 100));

        // 激活清除（恢复越界场景：播放头在激活段外，宿主清激活并重断言）
        // → 下一拍立即按视频尾语义拦截。
        controller.setSegmentLoopActive(false);
        controller.updateVideoRange(
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        );
        async.elapse(const Duration(milliseconds: 300));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });

    test('诊断日志：自动跨线拦截输出单 tag debugPrint', () {
      fakeAsync((async) {
        final logs = <String>[];
        final original = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
        };
        addTearDown(() => debugPrint = original);

        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );
        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 15));
        engine.play();
        async.elapse(const Duration(seconds: 6));

        expect(
          logs.any((line) => line.contains(kTailGuardLogTag)),
          isTrue,
          reason: '拦截等关键事件须经 kTailGuardLogTag 输出诊断日志',
        );

        controller.dispose();
      });
    });

    test('越界播放：从左侧播放跨越尾线仍被拦截（停 + 提示 + 循环）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 15));
        engine.play();
        async.elapse(const Duration(seconds: 6));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 20));
        expect(controller.phase, LoopPromptPhase.countdown);

        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(engine.isPlaying, isTrue);
        expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 10)));
        expect(engine.position, lessThan(const Duration(seconds: 20)));

        controller.dispose();
      });
    });

    test('录制期抑制整片循环：越尾线不停不提示、不倒计时、不自动回片头起播', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: Duration.zero,
            end: const Duration(seconds: 10),
          );
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'));
        engine.play();
        // 录制期：尾点循环提示与它的倒计时一并
        // 抑制——收尾归录制会话自己的墙钟判据。
        controller.setRecordingActive(true);

        async.elapse(const Duration(seconds: 11)); // 越过尾线 10s。

        expect(controller.phase, LoopPromptPhase.idle, reason: '录制期不进入倒计时');
        expect(engine.isPlaying, isTrue, reason: '录制期源侧恒在播：尾线不拦、不停');
        expect(engine.position, const Duration(seconds: 11));
        expect(autoLoopStarted, 0);

        // 越过尾线之后再过两个八拍：不得「回片头起播」。
        async.elapse(placeholderBeatGrid.eightBeatNominal);
        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(controller.phase, LoopPromptPhase.idle);
        expect(autoLoopStarted, 0);
        expect(
          engine.position,
          greaterThanOrEqualTo(const Duration(seconds: 10)),
          reason: '位置始终在尾线之后（从未回到片头）',
        );

        controller.dispose();
      });
    });

    test('解除录制不补做抑制期间错过的跨线：交还那一刻不立刻停、不提示', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: Duration.zero,
            end: const Duration(seconds: 10),
          );

        engine.open(Uri.file('/videos/a.mp4'));
        engine.play();
        controller.setRecordingActive(true);
        async.elapse(const Duration(seconds: 11)); // 抑制期间早已越过尾线。

        // 停录交还：位置基准重新立在当前位置——不把「抑制期间错过的那次跨线」
        // 事后补做（补做 = 交还瞬间凭空停一下 + 弹提示）。
        controller.setRecordingActive(false);
        async.elapse(const Duration(milliseconds: 300));

        expect(controller.phase, LoopPromptPhase.idle);
        expect(engine.isPlaying, isTrue);
        expect(
          engine.position,
          greaterThanOrEqualTo(const Duration(seconds: 11)),
          reason: '交还后照常顺播，不补做错过的跨线',
        );

        controller.dispose();
      });
    });

    test('录制期物理完成事件同样不进入倒计时（收尾由录制会话负责）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid);
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'), play: true);
        controller.setRecordingActive(true);
        async.elapse(const Duration(seconds: 1)); // 播放到物理尾 → completed。

        expect(controller.phase, LoopPromptPhase.idle);
        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(controller.phase, LoopPromptPhase.idle);
        expect(autoLoopStarted, 0);

        controller.dispose();
      });
    });

    test('解除录制后交还整片循环：越尾线照常停 + 提示 + 自动回片头', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: Duration.zero,
            end: const Duration(seconds: 10),
          );
        var autoLoopStarted = 0;
        controller.onAutoLoopStarted = () => autoLoopStarted++;

        engine.open(Uri.file('/videos/a.mp4'));
        engine.play();
        controller.setRecordingActive(true);
        async.elapse(const Duration(seconds: 4));
        expect(engine.isPlaying, isTrue);

        // 停录：交还尾点语义——越尾线照常拦截并提示、一个八拍后回到片头。
        controller.setRecordingActive(false);
        async.elapse(const Duration(seconds: 7)); // 越过尾线 10s。
        expect(engine.isPlaying, isFalse);
        expect(controller.phase, LoopPromptPhase.countdown);

        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(autoLoopStarted, 1);
        expect(engine.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('播放中尾线拖过播放头，跨新尾线照常拦截（放行标记随改写失效）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine(
          duration: const Duration(seconds: 30),
        );
        final controller = LoopPromptController(engine, gridOf: () => placeholderBeatGrid)
          ..updateVideoRange(
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 20),
          );

        // 手动拖到旧尾线右侧（25s）打放行标记后起播。
        engine.open(Uri.file('/videos/a.mp4'));
        engine.seek(const Duration(seconds: 25));
        async.elapse(Duration.zero); // 排空 open/seek 的挂起位置事件
        controller.markManualSeek(const Duration(seconds: 25));
        engine.play();

        // 播放中尾线改写到播放头之后（28s）：放行标记失效，跨新尾线拦截。
        controller.updateVideoRange(
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 28),
        );
        async.elapse(const Duration(seconds: 4));
        expect(engine.isPlaying, isFalse);
        expect(engine.position, const Duration(seconds: 28));
        expect(controller.phase, LoopPromptPhase.countdown);

        controller.dispose();
      });
    });
  });
}
