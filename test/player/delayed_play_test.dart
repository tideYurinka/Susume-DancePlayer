import 'dart:async' show unawaited;

import 'package:dance_learning_app/core/eight_beat_phase.dart' show BeatPhase;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/player/delayed_play.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/uniform_test_grid.dart';

/// 测试夹具：就绪真实网格（500ms 一拍、64 拍 = 32s；八拍点在 0、4s、8s…）。
UniformTestGrid realGrid() => UniformTestGrid();

/// 相位（无八拍锚点）。
BeatPhase plainPhase([UniformTestGrid? grid]) =>
    BeatPhase(grid: grid ?? realGrid());

/// 有效区间 = 全网格。
({Duration start, Duration end}) fullRange([UniformTestGrid? grid]) => (
  start: Duration.zero,
  end: (grid ?? realGrid()).beatTime((grid ?? realGrid()).beatCount - 1),
);

void main() {
  group('DelayedPlayController（起点 = 最近八拍点、预备连续播 N 拍）', () {
    test('触发即倒回起点前 N 拍连续播：seek(预备起点) → play', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        // 位置 18s（index 36）：起点 = 最近八拍点 16s（index 32），预备 =
        // 14s…15.5s（index 28…31），预备起点 14s。
        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();

        expect(controller.phase, DelayedPlayPhase.preparing);
        expect(controller.delayAnchor, const Duration(seconds: 16));
        expect(engine.callLog, ['seek', 'play']);
        expect(engine.seekCalls.single, const Duration(seconds: 14));
        expect(engine.isPlaying, isTrue, reason: '触发即连续播，暂停中触发也照样起播');

        controller.dispose();
      });
    });

    test('越过起点即转 active 并交出延迟锚', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        // 预备中（14s → 16s 之间）：仍是 preparing。
        async.elapse(const Duration(seconds: 1));
        expect(controller.phase, DelayedPlayPhase.preparing);

        // 越过 16s：转 active、锚就位、收前导。
        async.elapse(const Duration(seconds: 2));
        expect(controller.phase, DelayedPlayPhase.active);
        expect(controller.delayAnchor, const Duration(seconds: 16));
        expect(engine.callLog, ['seek', 'play'], reason: '越点不补发引擎调用');

        controller.dispose();
      });
    });

    test('等距并列取靠后者：位置在两个八拍点正中 → 起点取靠后的那个', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 2,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        // 22s = 20s 与 24s 两个八拍点的正中 → 靠后者 24s。
        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 22)),
        );
        async.flushMicrotasks();
        expect(controller.delayAnchor, const Duration(seconds: 24));

        controller.dispose();
      });
    });

    test('八拍锚点重定相：起点按当前相位（含锚点）解析', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          // 锚点 index 12（6s）：其后的八拍点 = 12、20、28…（不再是 0、8、16…）。
          phaseOf: () => BeatPhase(grid: realGrid(), anchors: [12]),
          prepBeatsOf: () => 2,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        // 位置 10.5s（index 21）：无锚相位的最近点 = 24（12s），重定相后
        // = 20（10s）。
        unawaited(
          controller.trigger(
            mediaPosition: const Duration(milliseconds: 10500),
          ),
        );
        async.flushMicrotasks();
        expect(controller.delayAnchor, const Duration(seconds: 10));

        controller.dispose();
      });
    });

    test('预备序列在有效区间头截断：只剩几拍就数几拍', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 4,
          // 区间头 15s：起点 16s 前只剩 15s、15.5s 两拍。
          validRangeOf: () => (
            start: const Duration(seconds: 15),
            end: const Duration(seconds: 32),
          ),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();

        expect(
          engine.seekCalls.single,
          const Duration(seconds: 15),
          reason: '预备起点 = 区间头内第一拍，而不是凑满 N 拍',
        );

        controller.dispose();
      });
    });

    test('打断（interrupt）：收前导 + 清锚 + 回 idle；不 seek、不改播放态', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 500));
        expect(engine.callLog, ['seek', 'play']);

        controller.interrupt();
        expect(controller.phase, DelayedPlayPhase.idle);
        expect(controller.delayAnchor, isNull);
        expect(engine.callLog, ['seek', 'play'], reason: '打断不 seek、不改播放态');

        // 打断后越过原起点也不再转 active、不交锚。
        async.elapse(const Duration(seconds: 5));
        expect(controller.phase, DelayedPlayPhase.idle);
        expect(controller.delayAnchor, isNull);

        // idle 时 interrupt 为 no-op。
        controller.interrupt();

        controller.dispose();
      });
    });

    test('active 期被打断同样撤锚（数拍回到普通锚点链）', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 2,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));
        expect(controller.phase, DelayedPlayPhase.active);

        controller.interrupt();
        expect(controller.phase, DelayedPlayPhase.idle);
        expect(controller.delayAnchor, isNull);

        controller.dispose();
      });
    });

    test('重复触发 = 重设：清旧锚、按新位置重算', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 2,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        expect(controller.delayAnchor, const Duration(seconds: 16));

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 25)),
        );
        async.flushMicrotasks();
        expect(controller.delayAnchor, const Duration(seconds: 24));
        expect(controller.phase, DelayedPlayPhase.preparing);
        expect(engine.seekCalls, hasLength(2));
        expect(engine.seekCalls.last, const Duration(seconds: 23));

        controller.dispose();
      });
    });

    test('占位网格走兜底：墙钟一个八拍标称后从当前位置起播、无锚', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: () => null,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        expect(controller.phase, DelayedPlayPhase.preparing);
        expect(controller.delayAnchor, isNull, reason: '兜底路径无延迟锚');
        expect(engine.seekCalls, isEmpty, reason: '兜底不 seek——从当前位置起播');

        // 未到点不播。
        async.elapse(const Duration(seconds: 3, milliseconds: 999));
        expect(engine.isPlaying, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(controller.phase, DelayedPlayPhase.idle);
        expect(engine.isPlaying, isTrue);
        expect(engine.seekCalls, isEmpty);
        expect(controller.delayAnchor, isNull);

        controller.dispose();
      });
    });

    test('起点越出有效区间走兜底', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: plainPhase,
          prepBeatsOf: () => 4,
          // 区间头 20s：位置 18s 的最近八拍点 16s 越出区间头 → 兜底。
          validRangeOf: () => (
            start: const Duration(seconds: 20),
            end: const Duration(seconds: 32),
          ),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 17)),
        );
        async.flushMicrotasks();
        expect(controller.phase, DelayedPlayPhase.preparing);
        expect(controller.delayAnchor, isNull);
        expect(engine.seekCalls, isEmpty);
        async.elapse(placeholderBeatGrid.eightBeatNominal);
        expect(engine.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('异常网格（秒制兜底）走兜底：无编号、固定 4s 后从当前位置起播', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: () => null,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => const UnavailableBeatGrid(),
        );

        unawaited(controller.trigger());
        async.flushMicrotasks();
        expect(controller.phase, DelayedPlayPhase.preparing);
        async.elapse(const Duration(seconds: 4));
        expect(controller.phase, DelayedPlayPhase.idle);
        expect(engine.isPlaying, isTrue);

        controller.dispose();
      });
    });

    test('dispose：取消订阅与倒计时，不再起播', () {
      fakeAsync((async) {
        final engine = FakePlaybackEngine();
        final controller = DelayedPlayController(
          engine,
          phaseOf: () => null,
          prepBeatsOf: () => 4,
          validRangeOf: () => fullRange(),
          gridOf: () => placeholderBeatGrid,
        );

        unawaited(
          controller.trigger(mediaPosition: const Duration(seconds: 2)),
        );
        async.flushMicrotasks();
        controller.dispose();
        async.elapse(const Duration(seconds: 10));
        expect(engine.isPlaying, isFalse);
      });
    });
  });
}
