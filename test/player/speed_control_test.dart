import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/playback/playback_loop_providers.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationSelectionDomainProvider, annotationEditorProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/gestures.dart';
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryCap;
import 'package:dance_learning_app/player/speed_step.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

void main() {
  late FakePlaybackEngine engine;
  late ProviderContainer container;

  setUp(() {
    engine = FakePlaybackEngine();
    container = ProviderContainer(
      overrides: [playbackEngineProvider.overrideWithValue(engine)],
    );
    addTearDown(container.dispose);
  });

  SpeedControlModel model() => container.read(speedControlProvider.notifier);
  SpeedControlState state() => container.read(speedControlProvider);

  group('倍速设置', () {
    test('setRate 驱动内核 setRate', () async {
      await model().setRate(1.25);
      expect(engine.rate, 1.25);
      expect(state().manualRate, 1.25);
      expect(state().effectiveRate, 1.25);
    });

    test('超上限钳制到 speedRateMax，低于下限钳制到 speedRateMin', () async {
      await model().setRate(5.0);
      expect(state().manualRate, speedRateMax);
      expect(engine.rate, speedRateMax);

      await model().setRate(0.01);
      expect(state().manualRate, speedRateMin);
      expect(engine.rate, speedRateMin);

      // 0.055 四舍五入为 0.06，仍低于下限 → 钳制到 0.1。
      await model().setRate(0.055);
      expect(state().manualRate, speedRateMin);
      expect(engine.rate, speedRateMin);
    });

    test('保留两位小数（范围内）', () async {
      await model().setRate(0.555);
      expect(state().manualRate, 0.56);
      expect(engine.rate, 0.56);

      await model().setRate(1.234);
      expect(state().manualRate, 1.23);
      expect(engine.rate, 1.23);
    });

    test('setRate 不再逐次记历史（历史改气泡关闭点提交）', () async {
      await model().setRate(0.5);
      await model().setRate(0.75);
      expect(state().history, isEmpty, reason: '滑条/档位调整不逐档入史');
    });

    test('recordHistory 去重、最近使用在前（含 1.0）', () async {
      expect(state().history, isEmpty);

      model().recordHistory(0.5);
      model().recordHistory(0.75);
      expect(state().history, [0.75, 0.5]);

      // 重复使用 0.5：不新增条目，仅移到最前。
      model().recordHistory(0.5);
      expect(state().history, [0.5, 0.75]);

      // 1.0 也入史。
      model().recordHistory(1.0);
      expect(state().history, [1.0, 0.5, 0.75]);
    });

    test('历史上限截断（保留最近 speedHistoryCap 条）', () async {
      for (var i = 0; i < 10; i++) {
        model().recordHistory(0.1 * (i + 1)); // 0.1 … 1.0
      }
      expect(state().history.length, speedHistoryCap);
      expect(state().history.first, 1.0); // 最近使用在前
      expect(state().history.last, 0.3); // 最旧的 0.1、0.2 被挤出
    });
  });

  group('倍速步进', () {
    test('启用步进：内核切到首档 a', () async {
      await model().setRate(0.75);
      await model().setStepEnabled(true);

      expect(state().stepEnabled, isTrue);
      expect(state().effectiveRate, 0.5); // 默认 a=0.5
      expect(engine.rate, 0.5);
    });

    test('停用步进：回到手动倍率', () async {
      await model().setRate(0.75);
      await model().setStepEnabled(true);
      await model().setStepEnabled(false);

      expect(state().stepEnabled, isFalse);
      expect(state().effectiveRate, 0.75);
      expect(engine.rate, 0.75);
    });

    test('重复启用/停用为幂等', () async {
      await model().setStepEnabled(true);
      await model().setStepEnabled(true);
      expect(state().stepEnabled, isTrue);
      expect(engine.rate, 0.5);

      await model().setStepEnabled(false);
      await model().setStepEnabled(false);
      expect(state().stepEnabled, isFalse);
      expect(engine.rate, 1.0);
    });
  });

  group('倍速设置与步进互斥（模型级）', () {
    test('步进启用后 setRate 会停用步进', () async {
      await model().setStepEnabled(true);
      expect(state().stepEnabled, isTrue);

      await model().setRate(1.5);
      expect(state().stepEnabled, isFalse);
      expect(state().effectiveRate, 1.5);
      expect(engine.rate, 1.5);
    });

    test('步进启用期间手动倍率保留、不生效', () async {
      await model().setRate(0.75);
      await model().setStepEnabled(true);

      expect(state().manualRate, 0.75); // 手动值保留
      expect(state().effectiveRate, 0.5); // 生效的是步进首档
    });
  });

  group('倍速侧激活谓词', () {
    test('默认（倍速 1.0、步进未启用）：倍速侧未生效', () {
      expect(state().speedSideInEffect, isFalse);
    });

    test('步进生效即激活——手动倍速仍为 1.0', () async {
      await model().setStepEnabled(true);
      expect(state().speedSideInEffect, isTrue);
    });

    test('步进停用且手动倍速 ≠1.0 仍激活；回 1.0 即熄灭', () async {
      await model().setRate(0.75);
      expect(state().speedSideInEffect, isTrue);

      await model().setRate(1.0);
      expect(state().speedSideInEffect, isFalse);
    });
  });

  group('步进参数编辑', () {
    test('合法参数应用；步进启用时内核切到新首档', () async {
      await model().setStepEnabled(true);
      await model().updateStepParams(
        const SpeedStepParams(
          startRate: 0.25,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
      );

      expect(state().stepParams.startRate, 0.25);
      expect(state().effectiveRate, 0.25);
      expect(engine.rate, 0.25);
    });

    test('非法参数忽略并保持原值', () async {
      await model().setRate(0.75);
      await model().updateStepParams(const SpeedStepParams(startRate: 0));

      expect(state().stepParams, const SpeedStepParams());
      expect(state().manualRate, 0.75);
      expect(engine.rate, 0.75);
    });

    test('参数变化后从起步档重新起步（遍数清零）', () async {
      await model().setStepEnabled(true);
      // 推进 3 遍 → 升到第二档 0.6。
      await model().onSegmentLoopLap();
      await model().onSegmentLoopLap();
      await model().onSegmentLoopLap();
      expect(state().effectiveRate, 0.6);

      await model().updateStepParams(
        const SpeedStepParams(
          startRate: 0.25,
          maxRate: 1.0,
          lapsPerRate: 2,
          rateIncrement: 0.25,
        ),
      );
      expect(state().stepCycle, 0);
      expect(state().effectiveRate, 0.25);
      expect(engine.rate, 0.25);
    });
  });

  group('步进作用范围与倍率推进', () {
    test('默认作用范围为激活段；启用后遍数清零、内核在起步档', () async {
      await model().setStepEnabled(true);
      expect(state().stepScope, SpeedStepScope.activeSegment);
      expect(state().stepCycle, 0);
      expect(engine.rate, 0.5);
    });

    test('激活段每循环一圈 +1 遍：每档遍数用满后升档、至封顶回起步', () async {
      await model().setStepEnabled(true);
      // 默认起步 0.5、封顶 1.0、每档 3 遍、递增量 0.1。
      for (var lap = 1; lap <= 18; lap++) {
        await model().onSegmentLoopLap();
        final expected = rateForStepCycle(const SpeedStepParams(), lap);
        expect(state().stepCycle, lap, reason: 'lap $lap');
        expect(state().effectiveRate, expected, reason: 'lap $lap');
        expect(engine.rate, expected, reason: 'lap $lap');
      }
      // 第 18 遍后回 a（0.5 → … → 1.0 用 15 遍，第 16–18 遍为 1.0，随后回 a）。
      await model().onSegmentLoopLap();
      expect(state().effectiveRate, 0.5);
    });

    test('停用后循环事件不推进', () async {
      await model().setStepEnabled(true);
      await model().setStepEnabled(false);
      await model().onSegmentLoopLap();
      expect(state().stepCycle, 0);
      expect(engine.rate, 1.0);
    });

    test('事件来源与作用范围不匹配时不推进（互不串档）', () async {
      await model().setStepEnabled(true); // activeSegment
      await model().onWholeVideoLoop();
      expect(state().stepCycle, 0);
      expect(engine.rate, 0.5);

      await model().setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      await model().onSegmentLoopLap();
      expect(state().stepCycle, 0);
      expect(engine.rate, 0.5);

      await model().onWholeVideoLoop();
      expect(state().stepCycle, 1);
      expect(engine.rate, 0.5); // 第 1 遍仍为首档（c=3）
    });

    test('「对全片」范围显式传入并生效', () async {
      await model().setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      expect(state().stepScope, SpeedStepScope.wholeVideo);
      expect(state().stepEnabled, isTrue);
      expect(engine.rate, 0.5);
    });

    test('循环遍数事件源驱动推进（learningSegmentLoopCountStreamProvider 接线）', () async {
      final laps = StreamController<int>.broadcast();
      addTearDown(laps.close);
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          learningSegmentLoopCountStreamProvider.overrideWithValue(laps.stream),
        ],
      );
      addTearDown(container.dispose);
      container.read(speedControlProvider); // 初始化模型（订阅事件源）
      await model().setStepEnabled(true);

      laps.add(1);
      laps.add(2);
      await Future<void>.delayed(Duration.zero);
      expect(state().stepCycle, 2);
      expect(engine.rate, 0.5); // c=3：第 2 遍仍为首档
      laps.add(3);
      await Future<void>.delayed(Duration.zero);
      expect(engine.rate, 0.6); // 满 c 遍升一档
    });

    test('步进作用于激活段时，激活被取消 → 自动停用步进', () async {
      // 播种/激活/清除均走模块与 seek 清除缝，不再直写。
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      editor.submit(AddSegmentLine(at: const Duration(seconds: 20)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await model().setStepEnabled(true);
      expect(state().stepEnabled, isTrue);

      // 模拟 seek 越出激活范围（段 0 范围 [0, 10s]）→ 取消激活。
      container
          .read(annotationSelectionDomainProvider)
          .clearLearningSegmentsIfOutside(const Duration(seconds: 11));
      expect(state().stepEnabled, isFalse);
      expect(engine.rate, 1.0); // 回到手动倍率
    });

    test('步进作用于全片时，激活被取消 → 步进保持启用', () async {
      final editor = container.read(annotationEditorProvider);
      editor.submit(AddSegmentLine(at: const Duration(seconds: 10)));
      container.read(annotationSelectionDomainProvider).selectOnly(0);
      await model().setStepEnabled(true, scope: SpeedStepScope.wholeVideo);

      // 模拟 seek 越出激活范围（段 0 范围 [0, 10s]）→ 取消激活。
      container
          .read(annotationSelectionDomainProvider)
          .clearLearningSegmentsIfOutside(const Duration(seconds: 11));
      expect(state().stepEnabled, isTrue);
      expect(state().stepScope, SpeedStepScope.wholeVideo);
    });
  });
  // 开舞装载：随舞记忆的装载入口——读回记忆（null = 无记忆）、
  // 立即写穿引擎、步进归未启用且遍数清零。记忆单元只有手动倍率。
  group('开舞装载（倍速记忆随舞 + 步进归零）', () {
    test('装载记忆值：引擎倍速立即是记忆值，手动倍率同值', () async {
      await model().loadForOpen(0.75);

      expect(engine.rate, 0.75, reason: '第一遍就是这个速度');
      expect(state().manualRate, 0.75);
      expect(state().memoryRate, 0.75);
      expect(state().effectiveRate, 0.75);
    });

    test('无记忆装载：引擎是出厂原速 1.0×，不继承上一支舞速率', () async {
      await model().setRate(1.25); // 上一支舞残留 1.25×
      await model().loadForOpen(null);

      expect(engine.rate, 1.0);
      expect(state().manualRate, 1.0);
      expect(state().memoryRate, isNull, reason: '无记忆 = 没有意见');
    });

    test('装载一律归零步进：未启用、遍数清零、引擎回到本舞倍率', () async {
      await model().setStepEnabled(true);
      await model().onSegmentLoopLap();
      await model().onSegmentLoopLap();
      expect(state().stepEnabled, isTrue);
      expect(state().stepCycle, 2);

      await model().loadForOpen(0.75);

      expect(state().stepEnabled, isFalse);
      expect(state().stepCycle, 0);
      expect(engine.rate, 0.75, reason: '步进不带入下一支舞');
    });

    test('用户改档：写这支舞的记忆与引擎倍速', () async {
      await model().loadForOpen(0.5);
      await model().setRate(1.25);

      expect(state().memoryRate, 1.25);
      expect(state().manualRate, 1.25);
      expect(engine.rate, 1.25);
    });

    test('步进运行期档位推进不改记忆；停用步进回落记忆值', () async {
      await model().loadForOpen(0.75);
      await model().setStepEnabled(true);
      await model().onSegmentLoopLap();
      await model().onSegmentLoopLap();
      await model().onSegmentLoopLap();
      expect(state().effectiveRate, isNot(0.75), reason: '档位推进已生效');
      expect(state().memoryRate, 0.75, reason: '档位是循环位置的投影，不是这支舞的倍率');

      await model().setStepEnabled(false);
      expect(state().effectiveRate, 0.75);
      expect(engine.rate, 0.75);
    });

    test('录制中装载：记忆照读但不写穿引擎（维持录制强制 1.0×）', () async {
      container
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.recording);

      await model().loadForOpen(0.5);

      expect(engine.rate, 1.0, reason: '录制强制 1.0×：装载不穿透');
      expect(state().manualRate, 0.5, reason: '这支舞的倍率照读到会话');
      expect(state().memoryRate, 0.5);
      expect(state().stepEnabled, isFalse);
    });

    test('瞬态 2× 期间装载：debug assert（换舞须先按既有语义结束瞬态）', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(0.5);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().loadForOpen(0.75),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  // 瞬态倍速（长按 2×，候选 6）：rate 唯一写穿收进本模型。
  group('瞬态倍速（长按 2×）', () {
    test('在播 begin：快照引擎倍速、内核切 2.0、transientActive 置位', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(1.5);

      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      expect(engine.rate, kLongPressDoubleSpeedRate);
      expect(state().transientActive, isTrue);
      // 手动值不变（纯引擎层临时覆盖）。
      expect(state().manualRate, 1.5);
    });

    test('暂停 begin：无副作用（不生效、倍速不变）', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await engine.pause();

      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      expect(state().transientActive, isFalse);
      expect(engine.rate, 1.0);
    });

    test('end：恢复手势前引擎倍速、退出 active', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(0.5);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await model().endTransientRate();

      expect(engine.rate, 0.5);
      expect(state().transientActive, isFalse);
      expect(state().manualRate, 0.5);
    });

    test('触发后中途转暂停仍保持 2× 至 end，end 恢复原值', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(1.25);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await engine.pause();
      expect(state().transientActive, isTrue);
      expect(engine.rate, kLongPressDoubleSpeedRate);

      await model().endTransientRate();
      expect(engine.rate, 1.25);
    });

    test('未 begin 时 end 无副作用', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);

      await model().endTransientRate();

      expect(state().transientActive, isFalse);
      expect(engine.rate, 1.0);
    });

    test('begin 未 end 再 begin：debug assert、首快照不覆盖', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(0.5);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().beginTransientRate(kLongPressDoubleSpeedRate),
        throwsA(isA<AssertionError>()),
      );
      await model().endTransientRate();
      expect(engine.rate, 0.5);
    });

    test('瞬态期间手动写穿（setRate）：debug assert、模型状态不变', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(0.5);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().setRate(1.5),
        throwsA(isA<AssertionError>()),
      );
      expect(engine.rate, kLongPressDoubleSpeedRate);
      expect(state().manualRate, 0.5);
      expect(state().transientActive, isTrue);

      await model().endTransientRate();
      expect(engine.rate, 0.5);
    });

    test('瞬态期间步进写穿（setStepEnabled）：debug assert', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().setStepEnabled(true),
        throwsA(isA<AssertionError>()),
      );
      expect(engine.rate, kLongPressDoubleSpeedRate);
      expect(state().stepEnabled, isFalse);
    });

    test('瞬态期间步进推进（onSegmentLoopLap）：debug assert', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(0.5);
      await model().setStepEnabled(true);
      expect(state().stepEnabled, isTrue);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().onSegmentLoopLap(),
        throwsA(isA<AssertionError>()),
      );
      expect(engine.rate, kLongPressDoubleSpeedRate);
    });

    test('瞬态期间更新步进参数（updateStepParams）：debug assert', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setStepEnabled(true);
      await model().beginTransientRate(kLongPressDoubleSpeedRate);

      await expectLater(
        model().updateStepParams(
          const SpeedStepParams(startRate: 0.25, maxRate: 1.0, lapsPerRate: 2),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(engine.rate, kLongPressDoubleSpeedRate);
    });

    test('录制期松手（end）：不把速率写回瞬态前基准（录制强制 1.0× 不被穿透）', () async {
      await engine.open(Uri.file('/v/a.mp4'), play: true);
      await model().setRate(1.5); // 录制前的原倍速 1.5。
      await model().beginTransientRate(kLongPressDoubleSpeedRate); // 瞬态 2.0。
      expect(engine.rate, kLongPressDoubleSpeedRate);

      // 录制起录：强制 1.0×（相位值道是倍速写穿的唯一门）。
      container
          .read(compareRecordingPhaseProvider.notifier)
          .set(CompareRecordingPhase.recording);
      await engine.setRate(1.0);

      await model().endTransientRate();

      expect(
        engine.rate,
        1.0,
        reason: '录制期收尾上锁：松手不得写回 1.5（录制强制的 1.0× 不能被穿透）',
      );
      expect(state().transientActive, isFalse, reason: '瞬态态照常收尾');
      await model().endTransientRate(); // 幂等：无第二次写入。
      expect(engine.rate, 1.0);
    });
  });

  // 倍速气泡快捷档清单与滑条上界常量映射（纯函数 seam）。
  group('气泡快捷档清单与滑条上界', () {
    test('快捷档清单：0.25/0.5/0.75/1/1.25/1.5（0.25 慢速入列，2.0 移出快捷）', () {
      expect(commonSpeeds, [0.25, 0.5, 0.75, 1.0, 1.25, 1.5]);
      expect(commonSpeeds.contains(2.0), isFalse);
    });

    test('气泡滑条上界为 1.5、下界沿用输入下界 0.1（输入仍可到 2.0）', () {
      expect(speedSliderMax, 1.5);
      expect(speedSliderMax, lessThan(speedRateMax));
      expect(speedRateMin, 0.1);
    });
  });
}
