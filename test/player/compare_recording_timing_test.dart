/// 起录时机与录制准备：位置驱动 + 提前武装、
/// 无相位时起点原样 / 越界拒录 / 尾点取先到者、第 0 个八拍顺数。
///
/// 落在第二层：**会话 + 两个 Fake**——注入既有
/// Fake 引擎（位置流按假时钟推进、到尾即发完成事件，`seekCalls`/`callLog`
/// 可断言）与既有 Fake 相机（可脚本化起录耗时），直测时序，不新开生产接缝
/// （沿用本文件的同一套布景，不另立脚手架）。
///
/// 替身纪律（「先红后绿配方」）：起录耗时**必须显式设成非零**——替补
/// 把起录演成微任务时，本轮的每一条时序判据都会假绿。
library;

import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/core/current_beat.dart'
    show deriveBeatCount, LeadingBeatCount;
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart' show BeatPhase;
import 'package:dance_learning_app/persistence/marker_document.dart' as marker_doc;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/player/compare_recording.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/document_grid_of.dart';
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';

/// 位置流不推进的引擎（异常源/内核不推进）：position 恒为 [frozen]、
/// positionStream 不发任何事件——宽限期兜底那一条的布景。
class _StalledEngine extends FakePlaybackEngine {
  _StalledEngine(this.frozen);

  final Duration frozen;

  @override
  Duration get position => frozen;

  @override
  Stream<Duration> get positionStream => const Stream<Duration>.empty();
}

/// 一次会话的布景：真生产装配（`CallbackCompareRecordingEnv`）＋两个 Fake。
class _Session {
  _Session({
    Duration duration = const Duration(seconds: 30),
    this.rangeStartMs = 0,
    this.rangeEndMs = 30000,
    this.active,
    String? videoId = 'v1',
    bool stalled = false,
    this.grid = const UniformBeatGrid(),
    this.phase,
  }) : engine = stalled
           ? _StalledEngine(Duration.zero)
           : FakePlaybackEngine(duration: duration) {
    final dir = Directory.systemTemp.createTempSync('cmp_timing');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on Object {
        // 临时目录清理失败不影响断言。
      }
    });
    outputPath = File('${dir.path}/take.mp4');
    controller = CompareRecordingController(
      engine,
      camera,
      CallbackCompareRecordingEnv(
        resolvePrepBeatsOf: () async => 8,
        beatGridOf: () => grid,
        phaseOf: () => phase,
        rangeStartOf: () => Duration(milliseconds: rangeStartMs),
        rangeEndOf: () => Duration(milliseconds: rangeEndMs),
        activeLoopRangeOf: () => active,
        videoIdOf: () => videoId,
        orientationOf: () => RecordingOrientation.landscape,
        surfaceBaselinesOf: () => liveBaselines,
      ),
      () async => outputPath,
      (record, preambleMs) async =>
          ingests.add((record: record, preambleMs: preambleMs)),
    );
  }

  final FakePlaybackEngine engine;
  final FakeCameraCaptureService camera = FakeCameraCaptureService();
  final int rangeStartMs;
  final int rangeEndMs;

  /// 本次会话的派生节拍网格（缺省 = 占位式无界均匀网格 120bpm，名下单拍
  /// 500ms；异常态传 [UnavailableBeatGrid]，拒录阈值随网格名下单拍走）。
  final BeatGrid grid;
  final ({Duration start, Duration end})? active;

  /// 本次会话的八拍相位（null = 占位/异常网格不产生八拍
  /// 点，起录点保持按下位置原样）。
  final BeatPhase? phase;

  /// 设备事实的当前取值（画面方向库的基线项）：武装那一刻由会话取一次；
  /// 用例在武装前/后改它，即可断言冻结语义。
  SurfaceBaselines liveBaselines = const SurfaceBaselines(
    platformPreviewBasis: FaceDirection.original,
    platformSaveBasis: FaceDirection.original,
  );

  late final File outputPath;
  late final CompareRecordingController controller;

  /// 入库记录（含前言长度）。
  final List<({MaterialRecord record, int preambleMs})> ingests = [];

  /// 按下录制（按下编排为异步，落定由 fake 时钟的
  /// flushMicrotasks 驱动），[startOutcomes] 收每次按下的落定。
  void press() {
    unawaited(controller.startRequested().then(startOutcomes.add));
  }

  /// 每次 [press] 的落定（宿主据此决定要不要给拒录提示）。
  final List<RecordingStartOutcome> startOutcomes = [];
}

void main() {
  group('起录位置驱动 + 提前武装', () {
    test('位置越过起录点即起录；起播那次定位之后不再出现任何 seek', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        // 起录重配延迟：编码器到 +9.6s 才在写（起录点 10s 之前）。
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);
        s.camera.scriptedRecordingDuration = const Duration(seconds: 8);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        // 前导起播：一次定位 seek 到 8 拍前（6s），连续播放。
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.seekCalls, [const Duration(seconds: 6)]);
        expect(s.engine.isPlaying, isTrue);

        // 位置自然越过武装点（9.4s）→ 武装编码器；此刻还没到起录点。
        async.elapse(const Duration(milliseconds: 3400));
        expect(s.controller.phase, CompareRecordingPhase.preparing);

        // 重配延迟走完：编码器已在写，位置仍在起录点之前（提前武装成立）。
        async.elapse(const Duration(milliseconds: 200));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.position.inMilliseconds, lessThan(10000));

        // 位置越过起录点（10s）→ 起录，**不再补 seek**。
        async.elapse(const Duration(milliseconds: 400));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(
          s.engine.seekCalls,
          [const Duration(seconds: 6)],
          reason: '起播那次定位之后不得再出现 seek（那一次 seek 就是源侧可见的顿挫）',
        );
        // 段尾（18s）自动停并入库。
        async.elapse(const Duration(seconds: 9));
        expect(s.camera.stopRecordingCount, 1);
        expect(s.controller.phase, CompareRecordingPhase.idle);
      });
    });

    test('宽限兜底：位置流始终不推进也起录（不会卡在准备态）', () {
      fakeAsync((async) {
        final s = _Session(
          stalled: true,
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        // 起录耗时不设成非零就把起录演成了微任务（先红后绿配方）。
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.preparing);

        // 前导 4s + 宽限期：位置流一次都没越过起录点，按定时器补触发。
        async.elapse(const Duration(seconds: 4));
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        async.elapse(kRecordingCrossGrace);
        // 豁免期到点即武装（重配耗时还没走完，尚未在写），武装落定才起录。
        expect(s.camera.startRecordingCalls, isEmpty);
        async.elapse(const Duration(milliseconds: 300));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.controller.phase, CompareRecordingPhase.recording);
      });
    });

    test('无前导路径：先武装、再把引擎摆到起录点起播，全程仅一次定位 seek', () {
      fakeAsync((async) {
        // 按下位置在区间头之前、起点即区间头：起点前没有余量可退。
        final s = _Session(rangeStartMs: 10000, rangeEndMs: 30000);
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        // 武装（含重配耗时）在途时还没有任何定位——先武装、再摆位。
        expect(s.engine.seekCalls, isEmpty);
        async.elapse(const Duration(milliseconds: 200));

        expect(s.engine.seekCalls, [const Duration(seconds: 10)]);
        expect(
          s.engine.callLog.where((entry) => entry == 'seek'),
          hasLength(1),
          reason: '无前导路径全程仅一次定位 seek',
        );
        // 武装在起播之前：武装先于定位 seek。
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(
          s.camera.startRecordingCalls.single.outputPath,
          s.outputPath.path,
        );
        // 摆到起录点起播后即越过起录点 → 起录。
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(s.engine.isPlaying, isTrue);

        // 素材头没有可作前言的死时间（武装一落定就 seek 到起录点）：入点为 0。
        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();
        expect(s.ingests.single.preambleMs, 0);
        expect(s.ingests.single.record.sourceStartMs, 10000);
      });
    });

    test('武装窗口内取消：停录并丢弃已武装的那段，不落素材', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);
        s.engine.setRate(1.5);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        // 武装点 9.4s 已过、重配延迟已走完（编码器在写），但还没到起录点。
        async.elapse(const Duration(milliseconds: 3600));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.controller.phase, CompareRecordingPhase.preparing);

        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();

        // 停录：已武装的那段丢弃——不落素材、不留半截（文件也不留）。
        expect(s.camera.stopRecordingCount, 1);
        expect(s.camera.isRecording, isFalse);
        expect(s.ingests, isEmpty);
        expect(
          s.outputPath.existsSync(),
          isFalse,
          reason: '取消丢弃的产出不得留在私有素材目录里（无清单条目的孤儿文件）',
        );
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.engine.isPlaying, isFalse);
        expect(s.engine.rate, 1.5, reason: '取消后恢复原倍速');
        // 取消后在途位置流不再起录。
        async.elapse(const Duration(seconds: 2));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.ingests, isEmpty);
      });
    });

    test('素材记录：源原点取起录点；时长取真实编码时长（不含起录前等待）', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        // 起录重配延迟 300ms：旧实现把它算进素材时长（系统性多报）。
        s.camera.startRecordingLatency = const Duration(milliseconds: 300);
        s.camera.scriptedRecordingDuration = const Duration(seconds: 2);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5)); // 越过起录点 → 起录。
        expect(s.controller.phase, CompareRecordingPhase.recording);

        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();

        expect(s.ingests, hasLength(1));
        final record = s.ingests.single.record;
        expect(record.sourceStartMs, 10000, reason: '唯一对齐锚点 = 起录点');
        expect(record.durationMs, 2000, reason: '真实编码时长，不含起录前等待与停录收尾');
        // 前言 = **实测**编码时长：武装点 9.4s 起武装、重配 300ms 后编码器
        // 才在写（源位置 9.7s），故真正录进素材头部的前言是 300ms——不是计划
        // 余量 600ms。片段入点按它换算，片段首帧才正好落在起录点。
        expect(
          s.ingests.single.preambleMs,
          300,
          reason: '前言取实测值（武装余量 − 重配耗时），不是计划常量',
        );
      });
    });

    test('起点前余量不足：武装点钳到有效区间头、前言随之缩短', () {
      fakeAsync((async) {
        // 真实网格在窄余量里也有拍点（9.8s / 9.9s）——准备前导自区间头起播
        // （前导起点 = 起录点前第 N 个真实拍点，无拍点即无前导，
        // 不再有「秒制兜底撑起一段无声前导」那条路）。
        final s = _Session(
          rangeStartMs: 9800,
          rangeEndMs: 30000,
          grid: documentGridOf(
            marker_doc.BeatGrid(
              model: 'fake.onnx',
              fps: 100,
              generatedAt: DateTime.utc(2026, 9, 14),
              beats: [
                for (var i = 0; i < 12; i++)
                  marker_doc.BeatPoint(t: 9.8 + i * 0.1, down: i % 4 == 0),
              ],
            ),
          ),
        );
        // 布景：按下位置在 10s（起点前只剩 200ms 余量）。
        s.engine.seek(const Duration(seconds: 10));
        s.engine.seekCalls.clear();
        s.camera.scriptedRecordingDuration = const Duration(milliseconds: 900);
        // 非零起录耗时：本布景的计划余量正好 200ms，不设耗时时实测 == 计划，
        // 断言就分不出「实测前言」与「计划余量」。重配 150ms ⇒ 编码器在源位置
        // 9.9s 才在写 ⇒ 实测前言 100ms（计划 200ms 里的一半）。
        s.camera.startRecordingLatency = const Duration(milliseconds: 150);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        // 余量 200ms（区间头到起录点）：前导与武装都从区间头开始。
        expect(s.engine.seekCalls, [const Duration(milliseconds: 9800)]);
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        // 重配耗时走完：编码器在写，此刻源位置 9.9s（即素材文件偏移 0）。
        async.elapse(const Duration(milliseconds: 150));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        async.elapse(const Duration(milliseconds: 150));
        expect(s.controller.phase, CompareRecordingPhase.recording);

        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();
        expect(
          s.ingests.single.preambleMs,
          100,
          reason: '实测前言（计划余量 200ms − 重配耗时 100ms），不是计划余量本身',
        );
        expect(s.ingests.single.record.sourceStartMs, 10000);
      });
    });

    test('武装失败收尾后再按一次：真的重新武装（不留已完成的武装记录）', () {
      fakeAsync((async) {
        final s = _Session();
        s.camera.startRecordingFails = true;

        // 第一回：没前导可退（起点即区间头），按下即武装 → 起录失败收尾。
        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.startRecordingCalls, isEmpty);

        // 第二回：必须真的重新武装——留着上一回那个已完成的武装记录会让本次
        // 会话「跳过武装直接进录制态」（进录制态却没在录、停录也没人停）。
        s.camera.startRecordingFails = false;
        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.controller.phase, CompareRecordingPhase.recording);

        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests, hasLength(1));
      });
    });

    test('素材未归属舞（videoId 未解析）：不起录、不留半截', () {
      fakeAsync((async) {
        final s = _Session(videoId: null);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        expect(s.camera.startRecordingCalls, isEmpty);
        expect(s.controller.phase, CompareRecordingPhase.idle);
      });
    });
  });

  group('无激活段录制边界：无相位起点原样、越界拒录、尾点取先到者', () {
    test('按下位置距有效区间尾不足一拍：拒录——不落素材、不落片段、回待录态', () {
      fakeAsync((async) {
        final s = _Session();
        // 按下位置 29.7s，区间尾 30s：到尾线只剩 300ms < 一拍（500ms）。
        s.engine.seek(const Duration(milliseconds: 29700));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();

        // 拒录：根本没进准备态（准备期那几拍因此不会被武装），落定交回
        // 「距尾线不足一拍」这一支——宿主据此给短暂提示。
        expect(s.startOutcomes, [RecordingStartOutcome.rejectedTooCloseToEnd]);
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.startRecordingCalls, isEmpty);
        expect(s.engine.seekCalls, isEmpty, reason: '拒录不起前导，不动引擎位置');

        // 事件过去之后也不得补落一条近 0 长的素材与片段。
        async.elapse(const Duration(seconds: 5));
        expect(s.camera.stopRecordingCount, 0);
        expect(s.ingests, isEmpty);
        expect(s.controller.phase, CompareRecordingPhase.idle);
      });
    });

    test('按下位置已在尾线之后：拒录（同样不落素材、不落片段）', () {
      fakeAsync((async) {
        final s = _Session();
        s.engine.seek(const Duration(milliseconds: 30500));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();

        expect(s.startOutcomes, [RecordingStartOutcome.rejectedTooCloseToEnd]);
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.startRecordingCalls, isEmpty);

        async.elapse(const Duration(seconds: 6));
        expect(s.camera.stopRecordingCount, 0);
        expect(s.ingests, isEmpty);
      });
    });

    test('距尾线恰好一拍：仍可录（判据是「不足一拍」，不是「不足或等于」）', () {
      fakeAsync((async) {
        final s = _Session();
        s.engine.seek(const Duration(seconds: 29, milliseconds: 500));
        s.engine.seekCalls.clear();
        s.camera.startRecordingLatency = const Duration(milliseconds: 100);

        s.press();
        async.flushMicrotasks();
        expect(s.startOutcomes, [RecordingStartOutcome.started]);
        expect(s.controller.phase, CompareRecordingPhase.preparing);

        async.elapse(const Duration(seconds: 4)); // 前导 8 拍 = 4s。
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(s.camera.startRecordingCalls, hasLength(1));

        // 到有效区间尾（30s）自动停并入库。
        async.elapse(const Duration(seconds: 1));
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests.single.record.sourceStartMs, 29500);
      });
    });

    test('拒录阈值随拍长走：两拍时距尾 1s 也拒录', () {
      fakeAsync((async) {
        // 拍长 2s 的占位网格（bpm 30）：拒录阈值 = 网格名下单拍。
        final s = _Session(grid: const UniformBeatGrid(bpm: 30));
        s.engine.seek(const Duration(seconds: 29));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        expect(s.startOutcomes, [RecordingStartOutcome.rejectedTooCloseToEnd]);
        expect(s.controller.phase, CompareRecordingPhase.idle);

        async.elapse(const Duration(seconds: 5));
        expect(s.ingests, isEmpty);
      });
    });

    test('按下位置早于有效区间头：起点钳到区间头（起点前没有可播余量）', () {
      fakeAsync((async) {
        final s = _Session(rangeStartMs: 10000, rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 9)); // 按下位置早于区间头。
        s.engine.seekCalls.clear();
        s.camera.startRecordingLatency = const Duration(milliseconds: 100);

        s.press();
        async.flushMicrotasks();
        // 起点即区间头：起点前没有余量 → 无前导路径（先武装、再摆到起点）。
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.seekCalls, isEmpty, reason: '先武装、再摆位');
        async.elapse(const Duration(milliseconds: 100));
        expect(s.startOutcomes, [RecordingStartOutcome.started]);
        expect(s.engine.seekCalls, [const Duration(seconds: 10)]);
        expect(s.controller.phase, CompareRecordingPhase.recording);

        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();
        expect(s.ingests.single.record.sourceStartMs, 10000);
      });
    });

    test('引擎先到视频物理尾：以那一刻立即停（不干等墙钟到有效区间尾）', () {
      fakeAsync((async) {
        // 尾线（30s）晚于物理时长（25s）——只有物理尾先到。
        final s = _Session(
          duration: const Duration(seconds: 25),
          rangeEndMs: 30000,
        );
        s.camera.scriptedRecordingDuration = const Duration(seconds: 17);
        s.engine.seek(const Duration(seconds: 8));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4)); // 前导回 4s、播回 8s 起录。
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(s.camera.startRecordingCalls, hasLength(1));

        // 从 8s 顺播到物理尾 25s：17s 之后的这一刻就停（墙钟判据要到 30s）。
        async.elapse(const Duration(seconds: 17));
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests, hasLength(1));
        expect(s.ingests.single.record.sourceStartMs, 8000);
      });
    });

    test('有效区间尾读不到（0 = 未知）：不起零延迟自停，顺播到物理尾', () {
      fakeAsync((async) {
        // 尾线读不到（0）：终点交物理尾兜底——旧实现这里 waitMs 为负被钳 0，
        // 「起录即停」却照样落一条近 0 长的素材与片段。
        final s = _Session(rangeEndMs: 0);
        s.camera.scriptedRecordingDuration = const Duration(seconds: 18);
        s.engine.seek(const Duration(seconds: 12));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4)); // 前导回 8s、播回 12s 起录。
        expect(s.controller.phase, CompareRecordingPhase.recording);

        // 起录之后一小步仍在录（不是起录即停）。
        async.elapse(const Duration(seconds: 1));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(s.camera.stopRecordingCount, 0);

        // 顺播到物理尾 30s 才停（12s + 18s）。
        async.elapse(const Duration(seconds: 17));
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests.single.record.sourceStartMs, 12000);
      });
    });

    test('准备期引擎先到物理尾（尾线晚于物理时长）：立即收尾、不落素材', () {
      fakeAsync((async) {
        // 物理尾 12s、尾线 30s，且按下位置已被引擎钳在物理尾：起点 = 12s，
        // 前导从 8s 起播——播到物理尾那一刻就收尾，不会再走到「起录点」。
        final s = _Session(duration: const Duration(seconds: 12));
        s.engine.seek(const Duration(seconds: 12));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.seekCalls, [const Duration(seconds: 8)]);

        async.elapse(const Duration(seconds: 4)); // 8s → 物理尾 12s。
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.ingests, isEmpty);
        // 前导期间武装点（11.4s）已过、编码器早在写：按取消收尾——停录并丢弃
        // 已武装的那段（不落素材、不留孤儿文件）。
        expect(s.camera.stopRecordingCount, 1);
        expect(s.outputPath.existsSync(), isFalse);

        // 收尾之后位置流/宽限期都不再起录。
        async.elapse(const Duration(seconds: 20));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(s.ingests, isEmpty);
      });
    });

    test('有激活段且段尾晚于物理尾：物理尾先到也立即停（尾点口径两支一致）', () {
      fakeAsync((async) {
        // 把「引擎先到视频物理尾则以那一刻为准」写成了通用的停止
        // 口径（不是只管无激活段那一支）：段 [10s,18s]、物理尾 14s ⇒ 14s 就停。
        final s = _Session(
          duration: const Duration(seconds: 14),
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        s.engine.seek(const Duration(seconds: 12));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 4)); // 前导 6s→10s，段首起录。
        expect(s.controller.phase, CompareRecordingPhase.recording);

        async.elapse(const Duration(seconds: 4)); // 10s → 物理尾 14s。
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests.single.record.sourceStartMs, 10000);

        // 往后不再有第二次停录（段尾 18s 的墙钟判据已被取消）。
        async.elapse(const Duration(seconds: 10));
        expect(s.camera.stopRecordingCount, 1);
      });
    });

    test('有激活段的那一支不受影响：起点 = 段首、段尾自动停', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        // 按下位置已越过段尾——有激活段时起点仍是段首，且不拒录。
        s.engine.seek(const Duration(seconds: 20));
        s.engine.seekCalls.clear();

        s.press();
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.seekCalls, [const Duration(seconds: 6)]);

        async.elapse(const Duration(seconds: 4)); // 前导 8 拍。
        expect(s.controller.phase, CompareRecordingPhase.recording);

        async.elapse(const Duration(seconds: 8)); // 段尾 18s。
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.ingests.single.record.sourceStartMs, 10000);
      });
    });
  group('录制准备的可视数拍（第 0 个八拍顺数同源）', () {
    /// 当前可视数拍的拍号（按**引擎媒介位置**换算；非前导期返回 null）。
    /// 生产侧该数字与浮层数拍同读发布值（录制
    /// 锚经锚点链派生 `0｜x`）——本助手只充当**观察通道**：经纯求值
    /// 缝（[deriveBeatCount]）读出，断言的期望值全部是字面号序列（1…8）。
    int? leadingOf(_Session s) {
      final anchor = s.controller.recordingStartPoint;
      if (anchor == null) return null;
      final count = deriveBeatCount(
        grid: s.grid,
        anchor: anchor,
        position: s.engine.position,
        phase: s.phase ?? BeatPhase(grid: s.grid),
      );
      return switch (count) {
        LeadingBeatCount(:final beatCount) => beatCount,
        _ => null,
      };
    }

    test('节拍前导期逐拍推进第 0 个八拍顺数（数字跟媒介位置，不跟墙钟）', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        // 前导起播 = 起录点前第 8 个真实拍点（均匀 500ms 网格 → 6.0s）：
        // 起播即显示第 0 个八拍第 1 拍（与当拍一声同刻）。
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.engine.seekCalls, [const Duration(seconds: 6)]);
        expect(leadingOf(s), 1, reason: '前导第一拍 = 0|1');

        for (var beat = 2; beat <= 8; beat++) {
          async.elapse(const Duration(milliseconds: 500));
          expect(
            leadingOf(s),
            beat,
            reason: '每拍顺数一格（与同一拍序列的节拍声同刻）',
          );
          expect(s.controller.phase, CompareRecordingPhase.preparing);
        }

        // 越过起录点（10s）：数拍让位给正式数拍（1｜1 由锚点链那套渲染给出）。
        async.elapse(const Duration(milliseconds: 500));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(
          s.controller.prepBeatVisual,
          isNull,
          reason: '起录后不再覆盖数拍显示，正式数拍按锚点链走',
        );
        expect(
          s.controller.recordingStartPoint,
          const Duration(seconds: 10),
          reason: '录制期锚 = 起录点（无激活段录制也一样）',
        );
      });
    });

    test('数字不再由自由计时器驱动：媒介位置冻结时墙钟流逝不推进数字', () {
      fakeAsync((async) {
        final s = _Session(rangeStartMs: 0, rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 12));

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(leadingOf(s), 1);

        // 冻结媒介位置（暂停 = 位置流不再推进）：旧实现那只自由计时器照样
        // 每拍推进数字，数字只跟媒介位置走。
        s.engine.pause();
        async.elapse(const Duration(seconds: 2));
        expect(
          leadingOf(s),
          1,
          reason: '墙钟走了 2s 而媒介位置没动 → 数字不许动',
        );
        expect(s.engine.position, const Duration(seconds: 8));
      });
    });

    test('seek 后数字随媒介位置跳（与拍声同一条位置流，不是自由计时器）', () {
      fakeAsync((async) {
        final s = _Session(rangeStartMs: 0, rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 12));

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        // 前导起点 = 起录点前第 8 个真实拍点 = 8.0s。
        expect(leadingOf(s), 1);

        // 播放推进两拍后回跳/前跳：数字跟随媒介位置，不跟随已流逝的墙钟。
        async.elapse(const Duration(seconds: 1));
        expect(leadingOf(s), 3);
        s.engine.seek(const Duration(seconds: 10));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        expect(leadingOf(s), 5, reason: '10.0s = 第 5 个准备拍（与位置一一对应）');
        s.engine.seek(const Duration(milliseconds: 8500));
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        expect(leadingOf(s), 2, reason: '回跳同样即刻跟随，不残留旧拍号');
        expect(s.controller.phase, CompareRecordingPhase.preparing);
      });
    });

    test('起录点前可用真实拍点不足：按可用拍点缩短、数字照实（不整块静默）', () {
      fakeAsync((async) {
        // 区间头 10s、按下位置 12s：可用的真实拍点只有 10.0/10.5/11.0/11.5
        // 四个（设定 8 拍）→ 缩短成四拍。
        final s = _Session(rangeStartMs: 10000, rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 12));
        s.engine.seekCalls.clear();

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        expect(s.controller.phase, CompareRecordingPhase.preparing);
        // 预备起点 = 区间头内第一个真实拍点 10.0s（可用的只有 10.0–11.5
        // 四拍）——截断由这条字面 seek 落点钉住（可视数拍已无载荷，
        // beatTimes 不再外露）。
        expect(s.engine.seekCalls, [const Duration(seconds: 10)]);
        expect(s.controller.prepBeatVisual, isA<RecordingPrepLeadingBeat>(),
            reason: '「有网格但不足」不得退化成整块静默');
        for (var beat = 5; beat <= 8; beat++) {
          expect(
            leadingOf(s),
            beat,
            reason: '距起录点还有 ${9 - beat} 拍 → 0|$beat',
          );
          async.elapse(const Duration(milliseconds: 500));
        }
      });
    });

    test('异常网格：无数字（秒制兜底）', () {
      fakeAsync((async) {
        final s = _Session(grid: const UnavailableBeatGrid(), rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 12));

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(s.controller.prepBeatVisual, isA<RecordingPrepSilentBeat>());
        for (var i = 0; i < 3; i++) {
          // 兜底 4s：1.5s 仍在准备期内。
          async.elapse(const Duration(milliseconds: 500));
          expect(s.controller.prepBeatVisual, isA<RecordingPrepSilentBeat>());
        }
      });
    });

    test('无激活段但起点前余量足够：同样按节拍前导顺数（基准 = 按下位置）', () {
      fakeAsync((async) {
        final s = _Session(rangeStartMs: 0, rangeEndMs: 30000);
        s.engine.seek(const Duration(seconds: 12));
        s.engine.seekCalls.clear();

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();

        // 无激活段：起点 = 按下位置 12s，其前 8 个真实拍点自 8.0s 起。
        expect(s.engine.seekCalls, [const Duration(seconds: 8)]);
        expect(leadingOf(s), 1);
        async.elapse(const Duration(seconds: 4));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(s.controller.prepBeatVisual, isNull);
      });
    });

    test('待录态不干预数拍显示（null = 锚点链照旧）', () {
      fakeAsync((async) {
        final s = _Session(
          active: (
            start: const Duration(seconds: 10),
            end: const Duration(seconds: 18),
          ),
        );
        expect(s.controller.prepBeatVisual, isNull);
        expect(s.controller.recordingStartPoint, isNull);
      });
    });
  });
  });

  group('录制期方向冻结：基线项在武装那一刻取一次', () {
    // 三份设备事实按取值命名：素材方向 = 平台保存基准，故 basisSaveMirrored 与
    // basisBothOriginal 的素材方向不同，足以分辨「武装那一刻取的是哪一份」。
    const basisBothOriginal = SurfaceBaselines(
      platformPreviewBasis: FaceDirection.original,
      platformSaveBasis: FaceDirection.original,
    );
    const basisSaveMirrored = SurfaceBaselines(
      platformPreviewBasis: FaceDirection.original,
      platformSaveBasis: FaceDirection.mirrored,
    );
    const basisPreviewMirrored = SurfaceBaselines(
      platformPreviewBasis: FaceDirection.mirrored,
      platformSaveBasis: FaceDirection.original,
    );

    /// 有激活段（起录点 10s、前导 8 拍 = 4s、武装点 9.4s）的一次会话：
    /// 武装落在准备期之内，故「武装前 / 武装后」两个改动窗口都可布置。
    _Session sessionWithPreamble() {
      final s = _Session(
        active: (
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 18),
        ),
      );
      // 起录耗时不设成非零就把武装演成微任务（先红后绿配方）。
      s.camera.startRecordingLatency = const Duration(milliseconds: 200);
      s.camera.scriptedRecordingDuration = const Duration(seconds: 8);
      return s;
    }

    test('武装前改取新值、武装后改不动已冻结的取值；前言段与正片段读到同一份', () {
      fakeAsync((async) {
        final s = sessionWithPreamble();
        s.liveBaselines = basisBothOriginal;

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.preparing);
        expect(
          s.controller.armedBaselines,
          isNull,
          reason: '还没武装：本次录制尚未取冻结值',
        );

        // 武装前改设备事实：本次录制取新值（武装那一刻现读）。
        s.liveBaselines = basisSaveMirrored;
        async.elapse(const Duration(milliseconds: 3400));
        async.elapse(const Duration(milliseconds: 200));
        expect(s.camera.startRecordingCalls, hasLength(1));
        expect(
          s.controller.armedBaselines,
          basisSaveMirrored,
          reason: '武装那一刻取一次：武装前改则取新值',
        );
        final frozen = s.controller.armedBaselines!;

        // 武装后改设备事实（仍在准备期 = 前言段）：已冻结的取值一字不变。
        s.liveBaselines = basisPreviewMirrored;
        expect(
          s.controller.armedBaselines,
          frozen,
          reason: '武装后改基线项不影响本次录制已冻结的取值',
        );
        expect(
          frozen.materialDirection,
          FaceDirection.mirrored,
          reason: '素材方向取自冻结的那一份（basisSaveMirrored）',
        );

        // 位置越过起录点（正片开始）：读到的仍是同一份冻结值（前言与正片同向）。
        async.elapse(const Duration(milliseconds: 500));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(
          s.controller.armedBaselines!.materialDirection,
          frozen.materialDirection,
          reason: '前言段与正片段的方向由同一份冻结值给出',
        );
      });
    });

    test('冻结随会话释放：收尾即清空，下一次录制重新取当时的设备事实', () {
      fakeAsync((async) {
        final s = sessionWithPreamble();
        s.liveBaselines = basisBothOriginal;

        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 3600));
        expect(s.controller.armedBaselines, basisBothOriginal);

        // 收尾（准备期取消 = 停录并丢弃已武装的那段）：冻结值一并释放。
        unawaited(s.controller.stopRequested());
        async.flushMicrotasks();
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(
          s.controller.armedBaselines,
          isNull,
          reason: '会话收尾释放冻结值（不留给下一次录制）',
        );

        // 下一次录制：重新取一次当时的设备事实。
        s.liveBaselines = basisPreviewMirrored;
        unawaited(s.controller.startRequested());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 3600));
        expect(
          s.controller.armedBaselines,
          basisPreviewMirrored,
          reason: '冻结只活一次会话：下一次武装取新的设备事实',
        );
      });
    });
  });

  group('起录点吸附八拍点（越点起录、拒录零副作用随新起录点）', () {
    /// 真实网格替身：拍点每 500ms 一个、每 4 拍一个强拍（4/4）——八拍点
    /// 每 4000ms 一个（0、4、8…s）；与相位同源构造。
    (_Session, BeatPhase) snappedSession({
      int rangeEndMs = 30000,
      int? pressMs,
    }) {
      final grid = documentGridOf(
        marker_doc.BeatGrid(
          model: 'madmom_downbeat_rnn_full.onnx',
          fps: 100,
          generatedAt: DateTime.utc(2026, 9, 16),
          beats: [
            for (var i = 0; i < 100; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: i % 4 == 0),
          ],
        ),
      );
      final phase = BeatPhase(grid: grid);
      final s = _Session(grid: grid, phase: phase, rangeEndMs: rangeEndMs);
      if (pressMs != null) {
        s.engine.seek(Duration(milliseconds: pressMs));
        s.engine.seekCalls.clear();
      }
      return (s, phase);
    }

    test('越点起录随新起录点：前导与素材来源起点都吸附后的八拍点为锚', () {
      fakeAsync((async) {
        final (s, _) = snappedSession(pressMs: 15333);
        s.camera.startRecordingLatency = const Duration(milliseconds: 200);
        s.camera.scriptedRecordingDuration = const Duration(seconds: 8);

        s.press();
        async.flushMicrotasks();

        // 起录点 15.333s 吸附到 16s；前导 8 拍 → 12s 起播（一次定位 seek）。
        expect(s.startOutcomes, [RecordingStartOutcome.started]);
        expect(s.engine.seekCalls, [const Duration(seconds: 12)]);

        // 位置越过新起录点（16s）→ 起录；到有效区间尾（30s）自动停并入库，
        // 素材来源起点 = 新起录点（对齐锚只有起录点一个）。
        async.elapse(const Duration(seconds: 6));
        expect(s.controller.phase, CompareRecordingPhase.recording);
        expect(
          s.engine.seekCalls,
          [const Duration(seconds: 12)],
          reason: '起播那次定位之后不得再出现 seek',
        );
        // 引擎自 12s 起播：越过 16s 起录后继续推进到有效区间尾（30s）。
        async.elapse(const Duration(seconds: 13));
        expect(s.camera.stopRecordingCount, 1);
        expect(s.ingests.single.record.sourceStartMs, 16000);
      });
    });

    test('拒录判定随新起录点：吸附推后落到尾线一拍内 → 拒录且零副作用', () {
      fakeAsync((async) {
        // 按下 27.6s 原样距尾 700ms ≥ 一拍；吸附到 28s 后距尾 300ms < 一拍
        //（区间尾 28.3s）→ 拒录。
        final (s, _) = snappedSession(rangeEndMs: 28300, pressMs: 27600);

        s.press();
        async.flushMicrotasks();

        expect(s.startOutcomes, [RecordingStartOutcome.rejectedTooCloseToEnd]);
        expect(s.controller.phase, CompareRecordingPhase.idle);
        expect(s.camera.startRecordingCalls, isEmpty);
        expect(s.engine.seekCalls, isEmpty, reason: '拒录不动引擎位置');
        async.elapse(const Duration(seconds: 5));
        expect(s.ingests, isEmpty);
      });
    });

    test('占位网格（无相位）：既有口径不变——起点 = 按下位置原样', () {
      fakeAsync((async) {
        final s = _Session();
        s.engine.seek(const Duration(milliseconds: 15333));
        s.engine.seekCalls.clear();
        s.camera.startRecordingLatency = const Duration(milliseconds: 100);

        s.press();
        async.flushMicrotasks();

        // 不吸附：前导 8 拍按占位网格真实拍点回退（15.333s 前第 8 拍 = 11.5s）。
        expect(s.startOutcomes, [RecordingStartOutcome.started]);
        expect(s.engine.seekCalls, [const Duration(milliseconds: 11500)]);
      });
    });
  });
}
