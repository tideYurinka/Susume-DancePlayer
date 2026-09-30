/// 对比录制与练习片段域的模块级直测：不 pump
/// widget、不注容器——真 [CompareRecordingController] + 两个 Fake（引擎、相机）
/// 驱动录制相位与起停，脚本化的宿主事实驱动练习片段回放。
///
/// 覆盖验收面：录制相位与四个值道、录制按钮的起停与拒录提示、素材入轨的
/// 次序、片段回放的就位/退场/解析失败收尾、循环前导归零、收尾。
library;

import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/eight_beat_phase.dart' show BeatPhase;
import 'package:dance_learning_app/player/camera_stage.dart';
import 'package:dance_learning_app/player/compare_recording.dart';
import 'package:dance_learning_app/player/compare_recording_clips.dart';
import 'package:dance_learning_app/player/practice_clip_playback.dart';
import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';

/// 脚本化录制环境（读取面）：按下时现读，不构造时快照。
class _ScriptedRecordingEnv implements CompareRecordingEnv {
  int prepBeats = 8;
  BeatGrid grid = const UniformBeatGrid();
  BeatPhase? phaseOf;
  Duration rangeStartMs = Duration.zero;
  Duration rangeEndMs = const Duration(seconds: 30);
  ({Duration start, Duration end})? active;
  String? videoIdOf = 'v1';
  RecordingOrientation orientation = RecordingOrientation.landscape;
  SurfaceBaselines baselines = const SurfaceBaselines(
    platformPreviewBasis: FaceDirection.original,
    platformSaveBasis: FaceDirection.original,
  );

  @override
  Future<int> resolvePrepBeats() async => prepBeats;

  @override
  BeatGrid get beatGrid => grid;

  @override
  BeatPhase? get beatPhase => phaseOf;

  @override
  Duration get rangeStart => rangeStartMs;

  @override
  Duration get rangeEnd => rangeEndMs;

  @override
  ({Duration start, Duration end})? get activeLoopRange => active;

  @override
  String? get videoId => videoIdOf;

  @override
  RecordingOrientation get currentOrientation => orientation;

  @override
  SurfaceBaselines get surfaceBaselines => baselines;
}

/// 值道写面记录器。
class _RecordingChannels implements CompareRecordingChannels {
  final List<CompareRecordingPhase> phases = [];
  final List<RecordingPrepBeatVisual?> prepBeats = [];
  final List<Duration?> starts = [];
  final List<SurfaceBaselines?> baselines = [];
  int resets = 0;

  @override
  void setPhase(CompareRecordingPhase phase) => phases.add(phase);

  @override
  void setPrepBeat(RecordingPrepBeatVisual? visual) => prepBeats.add(visual);

  @override
  void setRecordingStart(Duration? start) => starts.add(start);

  @override
  void setArmedBaselines(SurfaceBaselines? value) => baselines.add(value);

  @override
  void reset() => resets++;
}

/// 脚本化片段回看事实。
class _ScriptedClipsEnv implements CompareClipsEnv {
  PracticeClip? clip;
  String? activeId;
  bool onscreenClipPlayback = false;
  bool quietRestore = false;
  bool compareActive = true;
  bool mounted = true;

  @override
  PracticeClip? reviewClip() => clip;

  @override
  String? get activeClipId => activeId;

  @override
  bool get clipPlaybackOnscreen => onscreenClipPlayback;

  @override
  bool get restoreQuietWrite => quietRestore;

  @override
  bool get isCompare => compareActive;

  @override
  bool get isMounted => mounted;
}

/// 一次会话的布景：域 + 两个 Fake + 记录面。
class _Harness {
  _Harness() {
    // 相机授权前置：开实时预览以已授权为前提（与真机进入对比态的授权门一致）。
    unawaited(camera.requestPermission());
    takeover = RecordingPlaybackTakeover(
      disableRecordingLoop: () => hostEvents.add('disableLoop'),
      restoreLearningSegmentLoop: () => hostEvents.add('restoreLoop'),
      setRecordingMarker: (active) => hostEvents.add('marker:$active'),
      endScrubSession: () async => hostEvents.add('endScrub'),
      interruptPendingDelayedPlay: () => hostEvents.add('interrupt'),
      stopRecordingSession: () async => stopCalls++,
    );
    cameraStage = CameraStage(
      camera: camera,
      isCompare: () => clipsEnv.compareActive,
      isMounted: () => clipsEnv.mounted,
      hasPendingEntry: () => true,
      resolution: () => RecordingResolution.fhd1080p,
      onPreviewChanged: () => previewChanges++,
      promptDenied: (_) async => false,
    );
    domain = CompareRecordingClips(
      engine: engine,
      camera: camera,
      cameraStage: cameraStage,
      takeover: takeover,
      recordingEnv: env,
      channels: channels,
      clipsEnv: clipsEnv,
      resolveOutputFile: () async {
        hostEvents.add('resolveOutputFile');
        return outputFile;
      },
      host: CallbackCompareRecordingClipsHost(
        addClipFromMaterialOf: (record, preambleMs) {
          ingestEvents.add('clip');
          ingests.add((record: record, preambleMs: preambleMs));
        },
        appendMaterialOf: (record) async {
          ingestEvents.add('manifest');
          manifest.add(record);
        },
        createClipPlaybackOf: () => PracticeClipPlaybackController(
          engine: clipEngine,
          resolveSource: (_) async => clipSource,
        ),
        blocksRecordingWriteOf: () => blocksWrite,
        endTransientRateOf: () async => hostEvents.add('endTransientRate'),
        showRejectedPromptOf: () => rejectedPrompts++,
        exitClipReviewOf: () => exitReviews++,
      ),
    );
  }

  final FakePlaybackEngine engine = FakePlaybackEngine(
    duration: const Duration(seconds: 30),
  );
  final FakePlaybackEngine clipEngine = FakePlaybackEngine(
    duration: const Duration(seconds: 20),
  );
  final FakeCameraCaptureService camera = FakeCameraCaptureService();
  final _ScriptedRecordingEnv env = _ScriptedRecordingEnv();
  final _RecordingChannels channels = _RecordingChannels();
  final _ScriptedClipsEnv clipsEnv = _ScriptedClipsEnv();

  late final RecordingPlaybackTakeover takeover;
  late final CameraStage cameraStage;
  late final CompareRecordingClips domain;

  final File outputFile = File(
    '${Directory.systemTemp.createTempSync('cmp_clips').path}/take.mp4',
  );

  /// 宿主动作次序（scrub 收尾、瞬态倍速收尾、接管域的播放面纪律）。
  final List<String> hostEvents = [];

  /// 入库次序（先片段后清单）。
  final List<String> ingestEvents = [];
  final List<({MaterialRecord record, int preambleMs})> ingests = [];
  final List<MaterialRecord> manifest = [];

  Uri? clipSource = Uri.file('/materials/vid-a/rec_m1.mp4');
  bool blocksWrite = false;
  int rejectedPrompts = 0;
  int exitReviews = 0;
  int stopCalls = 0;
  int previewChanges = 0;

  PracticeClip clip({String id = 'clip_m1'}) => PracticeClip(
    id: id,
    materialId: 'm1',
    materialSourceStartMs: 0,
    inMs: 1000,
    outMs: 3000,
  );

  /// 会话收尾（每个用例末尾调用；临时目录清理失败不影响断言）。
  void tearDown() {
    domain.dispose();
    try {
      outputFile.parent.deleteSync(recursive: true);
    } on Object {
      // 临时目录清理失败不影响断言。
    }
  }
}

void main() {
  group('录制相位与值道', () {
    test('无前导起录：相位 idle → preparing → recording 经值道交出，接管域进入', () {
      fakeAsync((async) {
        final h = _Harness();
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();

        expect(h.channels.phases.first, CompareRecordingPhase.preparing);
        expect(h.takeover.active, isTrue);
        expect(h.hostEvents, contains('marker:true'));
        // 武装落定即把设备事实的当前取值写进冻结基线值道。
        expect(h.channels.baselines.last, h.env.baselines);

        // 位置越过起录点（按下位置 0 = 起录点）。
        async.elapse(const Duration(milliseconds: 200));
        expect(h.domain.phase, CompareRecordingPhase.recording);
        expect(h.channels.phases.last, CompareRecordingPhase.recording);
        expect(h.hostEvents, contains('disableLoop'));

        h.domain.stop();
        async.flushMicrotasks();
        expect(h.domain.phase, CompareRecordingPhase.idle);
        expect(h.channels.phases.last, CompareRecordingPhase.idle);
        expect(h.takeover.active, isFalse);
        expect(h.hostEvents, contains('marker:false'));
        expect(h.hostEvents, contains('restoreLoop'));
        h.tearDown();
      });
    });

    test('准备期不暂停循环（suppressLoop 只在录制本体）；停后复位各只一次', () {
      fakeAsync((async) {
        final h = _Harness();
        h.env.active = (
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
        );
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.domain.phase, CompareRecordingPhase.preparing);
        expect(h.hostEvents, isNot(contains('disableLoop')));

        async.elapse(const Duration(seconds: 5));
        expect(h.domain.phase, CompareRecordingPhase.recording);
        expect(h.hostEvents.where((e) => e == 'disableLoop'), hasLength(1));

        h.domain.stop();
        async.flushMicrotasks();
        expect(h.hostEvents.where((e) => e == 'marker:false'), hasLength(1));
        expect(h.hostEvents.where((e) => e == 'restoreLoop'), hasLength(1));
        h.tearDown();
      });
    });

    test('值道复位把四个注入点收回待录态', () {
      final h = _Harness();
      h.domain.resetValueChannels();
      expect(h.channels.resets, 1);
      h.tearDown();
    });
  });

  group('录制按钮的起停', () {
    test('待录态按下起录、起录中再按停录', () {
      fakeAsync((async) {
        final h = _Harness();
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.camera.startRecordingCalls, hasLength(1));
        expect(h.domain.phase, isNot(CompareRecordingPhase.idle));

        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.camera.stopRecordingCount, 1);
        expect(h.domain.phase, CompareRecordingPhase.idle);
        h.tearDown();
      });
    });

    test('装载未完成：门挡下起录，不落素材与片段', () {
      fakeAsync((async) {
        final h = _Harness()..blocksWrite = true;
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.domain.phase, CompareRecordingPhase.idle);
        expect(h.camera.startRecordingCalls, isEmpty);
        expect(h.ingests, isEmpty);
        h.tearDown();
      });
    });

    test('起录前先收掉在途 scrub、再收瞬态倍速，最后才起步会话', () {
      fakeAsync((async) {
        final h = _Harness();
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.hostEvents.indexOf('endScrub'), isNonNegative);
        expect(
          h.hostEvents.indexOf('endScrub'),
          lessThan(h.hostEvents.indexOf('endTransientRate')),
        );
        expect(
          h.hostEvents.indexOf('endTransientRate'),
          lessThan(h.hostEvents.indexOf('resolveOutputFile')),
        );
        h.tearDown();
      });
    });

    test('无激活段按下位置距区间尾不足一拍：拒录并给短暂提示，零副作用', () {
      fakeAsync((async) {
        final h = _Harness();
        h.env.rangeEndMs = const Duration(milliseconds: 300);
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        expect(h.rejectedPrompts, 1);
        expect(h.camera.startRecordingCalls, isEmpty);
        expect(h.ingests, isEmpty);
        expect(h.domain.phase, CompareRecordingPhase.idle);
        expect(h.engine.rate, 1.0);
        h.tearDown();
      });
    });

    test('停录产出：先登记在轨片段、再落素材清单，并转发素材记录与前言长度', () {
      fakeAsync((async) {
        final h = _Harness();
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        expect(h.domain.phase, CompareRecordingPhase.recording);

        h.domain.stop();
        async.flushMicrotasks();
        expect(h.ingestEvents, ['clip', 'manifest']);
        expect(h.ingests, hasLength(1));
        expect(h.ingests.single.record.sourceStartMs, 0);
        expect(h.ingests.single.preambleMs, 0);
        expect(h.manifest.single.id, h.ingests.single.record.id);
        h.tearDown();
      });
    });
  });

  group('对比态出入口', () {
    test('进入对比态：在屏为片段回放即就位回放（不自动播），否则开实时预览', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_m1';
        h.clipsEnv.onscreenClipPlayback = true;
        h.clipsEnv.quietRestore = true;
        h.domain.enterCompare();
        async.flushMicrotasks();
        expect(h.domain.clipEngine, isNotNull);
        expect(h.clipEngine.source, isNotNull);
        expect(h.clipEngine.isPlaying, isFalse, reason: '恢复就位不自动播');

        h.clipsEnv.clip = null;
        h.clipsEnv.onscreenClipPlayback = false;
        h.domain.enterCompare();
        async.flushMicrotasks();
        expect(h.camera.startCount, 1, reason: '无回看即开实时预览');
        h.tearDown();
      });
    });

    test('离开对比态：录制中自动停并入库，再关相机', () {
      fakeAsync((async) {
        final h = _Harness();
        h.domain.onRecordButtonTap();
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 200));
        expect(h.domain.phase, CompareRecordingPhase.recording);

        h.domain.exitCompare();
        async.flushMicrotasks();
        expect(h.camera.stopRecordingCount, 1);
        expect(h.ingestEvents, ['clip', 'manifest']);
        expect(h.camera.stopCount, 1);
        h.tearDown();
      });
    });
  });

  group('练习片段回放', () {
    test('点选激活：停相机预览、第二播放源就位并起播', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_m1';
        h.clipsEnv.onscreenClipPlayback = true;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.camera.stopCount, 1, reason: '回看期间停实时预览');
        expect(h.clipEngine.source, isNotNull);
        expect(h.clipEngine.isPlaying, isTrue, reason: '点选激活即起播');
        h.tearDown();
      });
    });

    test('退出回看：回放退场，仍在对比态时恢复实时预览', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_m1';
        h.clipsEnv.onscreenClipPlayback = true;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.clipEngine.isPlaying, isTrue);

        h.clipsEnv.clip = null;
        h.clipsEnv.onscreenClipPlayback = false;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.clipEngine.isPlaying, isFalse);
        expect(h.camera.startCount, 1, reason: '回落实时预览');
        h.tearDown();
      });
    });

    test('非对比态退出回看：不恢复预览', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipsEnv.compareActive = false;
        h.clipsEnv.onscreenClipPlayback = false;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.camera.startCount, 0);
        h.tearDown();
      });
    });

    test('播放源解析不到：退出回看（唯一收口）', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipSource = null;
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_m1';
        h.clipsEnv.onscreenClipPlayback = true;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.exitReviews, 1);
        h.tearDown();
      });
    });

    test('激活已被别的写取代：解析失败也不补清', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipSource = null;
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_other';
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.exitReviews, 0);
        h.tearDown();
      });
    });

    test('页面已卸载：解析失败不补清', () {
      fakeAsync((async) {
        final h = _Harness();
        h.clipSource = null;
        h.clipsEnv.clip = h.clip();
        h.clipsEnv.activeId = 'clip_m1';
        h.clipsEnv.mounted = false;
        h.domain.syncClipPlayback();
        async.flushMicrotasks();
        expect(h.exitReviews, 0);
        h.tearDown();
      });
    });

    test('循环前导取值：片段回放期间归零、其余时间用现拍档', () {
      final h = _Harness();
      h.clipsEnv.onscreenClipPlayback = true;
      expect(
        h.domain.effectiveLoopWait(const Duration(seconds: 2)),
        Duration.zero,
      );
      h.clipsEnv.onscreenClipPlayback = false;
      expect(
        h.domain.effectiveLoopWait(const Duration(seconds: 2)),
        const Duration(seconds: 2),
      );
      h.tearDown();
    });
  });
}
