/// CompareRecordingClips：对比录制与练习片段域。
///
/// 本域是以下编排的宿主：
///
/// - **录制相位**：内部持一只 [CompareRecordingController]，相位同步把四个
///   keepAlive 注入点（录制相位、可视数拍、起录点、冻结基线项）写到位，并把
///   播放面纪律交给「录制期播放接管」域（[RecordingPlaybackTakeover]）；
/// - **录制按钮的起停**：待录态按下 = 装载门 → 收掉在途 scrub 与瞬态倍速 →
///   起录（拒录给一句短暂提示）；准备/录制中按下 = 停录（准备期即取消并丢弃
///   已武装的那段）；
/// - **素材入轨**：录制产出先登记 1:1 在轨片段、再落素材清单（写失败不抛到
///   UI）。练习片段轨的写面归属不变：截取/删除仍经标注编辑，录制入轨仍是
///   非历史写；
/// - **练习片段的回放**：在屏播放源切到片段回放即停相机预览并让第二播放源就位
///   （点选激活即起播、恢复就位不自动播）；退出即回放退场、仍在对比态时恢复
///   实时预览；素材解析不到即退出回看。片段循环期间循环前导归零。
///
/// 依赖方向（单向）：本域 → 录制控制器、[PracticeClipPlaybackController]、
/// [RecordingPlaybackTakeover]、[CameraStage]、引擎接缝；反向无——构造收显式
/// 依赖（读取闭包 + 回调 + 两个环境接口），不读构建上下文、不注容器，可在无
/// ProviderScope 下直测。
library;

import 'dart:async';
import 'dart:io';

import '../annotation/compare_materials.dart';
import '../camera_capture/camera_capture.dart';
import '../core/playback/playback_engine.dart';
import '../persistence/material_manifest.dart' show MaterialManifestDocument;
import '../surface_direction/surface_direction.dart';

import 'package:path/path.dart' as p;

import 'camera_stage.dart';
import 'compare_recording.dart';
import 'practice_clip_playback.dart';
import 'recording_playback_takeover.dart';

/// 录制值道写面（宿主注入）：相位同步把四个 keepAlive 注入点写到位；[reset]
/// 是「离开播放页 / 页面就位」两个触发点的收口。
abstract interface class CompareRecordingChannels {
  void setPhase(CompareRecordingPhase phase);

  void setPrepBeat(RecordingPrepBeatVisual? visual);

  void setRecordingStart(Duration? start);

  void setArmedBaselines(SurfaceBaselines? baselines);

  void reset();
}

/// 值道写缝的域内实现：四个跨帧值道模型的句柄
/// 由宿主经构造交入，读写的写面与复位都收在域内——它们是录制域的会话值，
/// 复位沿「本页面就位」与「离开播放页」两个触发点，推迟到树收尾后的微任务
/// （容器已随应用/测试销毁时静默跳过：复位本就无事可做）。
class NotifierCompareRecordingChannels implements CompareRecordingChannels {
  NotifierCompareRecordingChannels({
    required this.phase,
    required this.prepBeat,
    required this.recordingStart,
    required this.armedBaselines,
  });

  final CompareRecordingPhaseModel phase;
  final RecordingPrepBeatModel prepBeat;
  final CompareRecordingStartModel recordingStart;
  final ArmedSurfaceBaselinesModel armedBaselines;

  @override
  void setPhase(CompareRecordingPhase value) => phase.set(value);

  @override
  void setPrepBeat(RecordingPrepBeatVisual? visual) => prepBeat.set(visual);

  @override
  void setRecordingStart(Duration? start) => recordingStart.set(start);

  @override
  void setArmedBaselines(SurfaceBaselines? baselines) =>
      armedBaselines.set(baselines);

  @override
  void reset() {
    scheduleMicrotask(() {
      try {
        phase.reset();
        prepBeat.reset();
        recordingStart.reset();
        armedBaselines.reset();
      } on Exception {
        // 模型已随容器销毁（riverpod 抛 UnmountedRefException）：无需复位。
        // 只吞 Exception——真正的程序错误（Error 系）照常暴露。
      }
    });
  }
}

/// 练习片段回看的宿主事实（按下时现读的读取面）。
abstract interface class CompareClipsEnv {
  /// 在屏播放源为片段回放、且激活片段能在轨道上解析到时的那条片段；否则
  /// null（含引用悬空 = 该面答实时预览）。
  PracticeClip? reviewClip();

  /// 当前激活片段的 id（回放就位失败的收尾判据）。
  String? get activeClipId;

  /// 在屏播放源是否为片段回放（片段循环期间循环前导归零的判据）。
  bool get clipPlaybackOnscreen;

  /// 本次循环激活写回是否来自打开恢复（恢复就位不自动播）。
  bool get restoreQuietWrite;

  /// 页面处于对比态（退出回看时恢复预览的前提）。
  bool get isCompare;

  /// 页面仍在树上（回放就位失败后的收尾不在已卸载页面上发生）。
  bool get isMounted;
}

/// [CompareClipsEnv] 的闭包装配实现（宿主接线一处组装）。
class CallbackCompareClipsEnv implements CompareClipsEnv {
  CallbackCompareClipsEnv({
    required this.reviewClipOf,
    required this.activeClipIdOf,
    required this.clipPlaybackOnscreenOf,
    required this.restoreQuietWriteOf,
    required this.isCompareOf,
    required this.isMountedOf,
  });

  final PracticeClip? Function() reviewClipOf;
  final String? Function() activeClipIdOf;
  final bool Function() clipPlaybackOnscreenOf;
  final bool Function() restoreQuietWriteOf;
  final bool Function() isCompareOf;
  final bool Function() isMountedOf;

  @override
  PracticeClip? reviewClip() => reviewClipOf();

  @override
  String? get activeClipId => activeClipIdOf();

  @override
  bool get clipPlaybackOnscreen => clipPlaybackOnscreenOf();

  @override
  bool get restoreQuietWrite => restoreQuietWriteOf();

  @override
  bool get isCompare => isCompareOf();

  @override
  bool get isMounted => isMountedOf();
}

/// 对比录制与练习片段域的宿主动作（写缝与命令面）：值道之外的三个写点、
/// 装载门、瞬态倍速收尾、拒录提示、退出回看与第二播放源装配。
abstract interface class CompareRecordingClipsHost {
  /// 录制产出登记为 1:1 在轨片段（练习片段轨的非历史写）。
  void addClipFromMaterial(MaterialRecord record, int preambleMs);

  /// 录制产出追加进素材清单。
  Future<void> appendMaterial(MaterialRecord record);

  /// 装配练习片段回放控制器（第二播放源懒建）。
  PracticeClipPlaybackController createClipPlayback();

  /// 录制入轨是会写盘入口：装载未完成时挡下起录。
  bool blocksRecordingWrite();

  /// 起录前收掉瞬态倍速（长按 2×）。
  Future<void> endTransientRate();

  /// 拒录短暂提示。
  void showRejectedPrompt();

  /// 退出练习片段回看的唯一收口。
  void exitClipReview();
}

/// [CompareRecordingClipsHost] 的闭包装配实现（宿主接线一处组装）。
class CallbackCompareRecordingClipsHost implements CompareRecordingClipsHost {
  CallbackCompareRecordingClipsHost({
    required this.addClipFromMaterialOf,
    required this.appendMaterialOf,
    required this.createClipPlaybackOf,
    required this.blocksRecordingWriteOf,
    required this.endTransientRateOf,
    required this.showRejectedPromptOf,
    required this.exitClipReviewOf,
  });

  final void Function(MaterialRecord record, int preambleMs)
  addClipFromMaterialOf;
  final Future<void> Function(MaterialRecord record) appendMaterialOf;
  final PracticeClipPlaybackController Function() createClipPlaybackOf;
  final bool Function() blocksRecordingWriteOf;
  final Future<void> Function() endTransientRateOf;
  final void Function() showRejectedPromptOf;
  final void Function() exitClipReviewOf;

  @override
  void addClipFromMaterial(MaterialRecord record, int preambleMs) =>
      addClipFromMaterialOf(record, preambleMs);

  @override
  Future<void> appendMaterial(MaterialRecord record) =>
      appendMaterialOf(record);

  @override
  PracticeClipPlaybackController createClipPlayback() => createClipPlaybackOf();

  @override
  bool blocksRecordingWrite() => blocksRecordingWriteOf();

  @override
  Future<void> endTransientRate() => endTransientRateOf();

  @override
  void showRejectedPrompt() => showRejectedPromptOf();

  @override
  void exitClipReview() => exitClipReviewOf();
}

/// 对比录制与练习片段域（会话域：无 widget）。
class CompareRecordingClips {
  CompareRecordingClips({
    required this.engine,
    required this._camera,
    required this.cameraStage,
    required this.takeover,
    required this._recordingEnv,
    required this.channels,
    required this.clipsEnv,
    required this._resolveOutputFile,
    required this.host,
    this.readManifestOf,
    this.baseDirectoryOf,
  }) {
    controller = CompareRecordingController(
      engine,
      _camera,
      _recordingEnv,
      _resolveOutputFile,
      _ingest,
    );
    controller.addListener(_sync);
    _playingSub = engine.isPlayingStream.listen((playing) {
      unawaited(_syncClipPlaying(playing));
    });
  }

  /// 播放内核（片段回看自动播判据与录制会话共用同一只）。
  final PlaybackEngine engine;

  /// 相机与练习面域（进入对比态接管练习侧、退出回看恢复预览）。
  final CameraStage cameraStage;

  /// 录制期播放接管域（播放面纪律的施加与复位）。
  final RecordingPlaybackTakeover takeover;

  /// 录制值道写面。
  final CompareRecordingChannels channels;

  /// 练习片段回看的宿主事实。
  final CompareClipsEnv clipsEnv;

  /// 宿主动作（写缝与命令面）。
  final CompareRecordingClipsHost host;

  final CameraCaptureService _camera;
  final CompareRecordingEnv _recordingEnv;
  final Future<File> Function() _resolveOutputFile;

  /// 素材清单读取（片段回放的素材解析用，宿主注入）。
  final Future<MaterialManifestDocument> Function()? readManifestOf;

  /// 素材基目录读取（同上）。
  final Future<Directory> Function()? baseDirectoryOf;

  /// 录制会话控制器（录制钮按它取相位）。
  late final CompareRecordingController controller;

  PracticeClipPlaybackController? _clipPlayback;

  /// 引擎播放态边沿订阅：片段回放跟随源侧播放态（同起同停）。
  StreamSubscription<bool>? _playingSub;

  /// 当前录制阶段。
  CompareRecordingPhase get phase => controller.phase;

  /// 练习片段回放引擎（懒建：未就位回放时为 null）。
  PlaybackEngine? get clipEngine => _clipPlayback?.engine;

  /// 素材文件解析：清单按 materialId 找回素材记录（videoId +
  /// 文件名），落在私有素材目录 `<基目录>/<videoId>/<fileName>`；清单不可读 /
  /// 素材缺失返回 null（静默不回放）。
  Future<Uri?> resolveClipSource(PracticeClip clip) async {
    final readManifest = readManifestOf;
    final readBaseDirectory = baseDirectoryOf;
    if (readManifest == null || readBaseDirectory == null) return null;
    try {
      final manifest = await readManifest();
      for (final record in manifest.materials) {
        if (record.id != clip.materialId) continue;
        final base = await readBaseDirectory();
        return Uri.file(p.join(base.path, record.videoId, record.fileName));
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// 录制钮点击：待录态起录（装载门挡下的写入口）、其余态停录。
  void onRecordButtonTap() {
    if (controller.phase == CompareRecordingPhase.idle) {
      // 录制入轨是会写盘入口：装载未完成时被同一道门挡下并说明原因——不起
      // 录、不落素材与片段（停录/取消不受门影响）。
      if (host.blocksRecordingWrite()) return;
      unawaited(start());
    } else {
      // 录制中 = 停；准备中（含武装窗口） = 取消（停录并丢弃已武装的那段）。
      unawaited(stop());
    }
  }

  /// 按下录制：收掉在途的定格预览与瞬态倍速，再起步录制会话；只有**拒录**
  /// 这一支给短暂提示（准备期收尾不是「太靠近结尾」，不该弹同一句假原因）。
  Future<void> start() async {
    // 起录即收掉在途的定格预览（收口在接管域，录制会话起步之前）：多点触控
    // 下「拖着进度条按录制」可达，那一刻 scrub 相位若留着，它的收尾就会在
    // 起录之后回写播放态与位置。
    await takeover.endScrubBeforeStart();
    // 瞬态倍速（长按 2×）不属于录制：起录前先收尾，免得它把非 1.0× 的
    // 「原倍速」快照带进录制会话。
    await host.endTransientRate();
    final outcome = await controller.startRequested();
    // 准备期收尾（素材未归属舞、武装失败）不是「太靠近结尾」，不给同一句
    // 假原因；页面已卸载时交回宿主也无需提示。
    if (outcome != RecordingStartOutcome.rejectedTooCloseToEnd ||
        !clipsEnv.isMounted) {
      return;
    }
    host.showRejectedPrompt();
  }

  /// 停止 / 取消录制（手动停、退后台、离开对比态、离开页面）。
  Future<void> stop() => controller.stopRequested();

  /// 进入对比态时接管练习侧：在屏为片段回放即就位回放（不自动播），否则开
  /// 实时预览（授权前提由相机与练习面域自持）。
  Future<void> enterCompare() async {
    final clip = clipsEnv.reviewClip();
    if (clip != null) {
      await _placeClipPlayback(clip, autoplay: false);
      return;
    }
    await cameraStage.openPreview();
  }

  /// 离开对比态：录制中自动停并入库，同时关相机（两者并发——关相机不等待
  /// 停录与清单落盘完成）。
  Future<void> exitCompare() async {
    unawaited(stop());
    await cameraStage.closePreview();
  }

  /// 在屏播放源变化时同步练习侧回放：激活片段 = 停预览并就位回放（点选激活
  /// 即起播、恢复就位不自动播）；退出 = 回放退场、仍在对比态时恢复实时预览。
  void syncClipPlayback() {
    final clip = clipsEnv.reviewClip();
    if (clip != null) {
      unawaited(cameraStage.closePreview());
      final quietPlacement = clipsEnv.restoreQuietWrite;
      final autoplay = !quietPlacement || engine.isPlaying;
      unawaited(_placeClipPlayback(clip, autoplay: autoplay));
      return;
    }
    _clipPlayback?.hide();
    if (clipsEnv.isCompare) unawaited(cameraStage.openPreview());
  }

  /// 片段回放跟随源侧播放态（练习侧回放与源侧同起同停；未在回放时零行为）。
  Future<void> _syncClipPlaying(bool playing) async {
    await _clipPlayback?.syncPlaying(playing);
  }

  /// 片段循环期间循环前导一律归零（片段不套循环前导）；否则用现拍档。
  Duration effectiveLoopWait(Duration setting) =>
      clipsEnv.clipPlaybackOnscreen ? Duration.zero : setting;

  /// 值道复位（页面就位与离开播放页两个触发点）。
  void resetValueChannels() => channels.reset();

  /// 收尾：摘相位监听 → 复位值道 → 停录制 → 释放回放控制器。相位监听先摘
  /// ——收尾期的相位通知不再回写值道。
  void dispose() {
    controller.removeListener(_sync);
    _playingSub?.cancel();
    _playingSub = null;
    channels.reset();
    unawaited(stop());
    _clipPlayback?.dispose();
  }

  /// 就位回放并兜住播放源失效：解析不到素材文件即走「退出练习片段回看」唯一
  /// 收口；激活已被别的写更新的（不再指向本片段）不补清。
  Future<void> _placeClipPlayback(
    PracticeClip clip, {
    required bool autoplay,
  }) async {
    final placed = await _ensureClipPlayback().show(clip, autoplay: autoplay);
    if (!clipsEnv.isMounted || placed) return;
    final active = clipsEnv.activeClipId;
    if (active != null && active == clip.id) host.exitClipReview();
  }

  PracticeClipPlaybackController _ensureClipPlayback() =>
      _clipPlayback ??= host.createClipPlayback();

  /// 录制产出入库：先登记在轨片段、再落素材清单（清单写失败不抛到 UI——半截
  /// 素材不阻断会话收尾）。
  Future<void> _ingest(MaterialRecord record, int preambleMs) async {
    try {
      host.addClipFromMaterial(record, preambleMs);
      await host.appendMaterial(record);
    } on Object {
      // 清单写失败不抛到 UI（半截素材不阻断会话收尾）。
    }
  }

  /// 相位同步：四个值道一次写到位，播放面纪律交接管域施加/复位。
  void _sync() {
    final current = controller.phase;
    channels.setPhase(current);
    // 可视数拍：准备期的拍号由准备拍序列 + 媒介位置派生（浮层按位置实时
    // 换算），起录/收尾即清空——非准备期不干预数拍显示（锚点链照旧）。
    channels.setPrepBeat(controller.prepBeatVisual);
    // 录制期锚 = 起录点：无激活段录制时数拍不退化到「最近分段线 → 首线」，
    // 锚经对齐纯函数归到网格八拍大线；非录制态清空。
    channels.setRecordingStart(controller.recordingStartPoint);
    // 冻结的基线项：武装落定那一刻写入、收尾清空——练习侧画面方向的装配点
    // 据此在录制期只读冻结值。
    channels.setArmedBaselines(controller.armedBaselines);
    // 播放面纪律：整片循环抑制、在途延迟播放收挂账、录制期循环停用、退出时
    // 学段循环作用域复位，四条同属「录制期播放行为被接管」这一条纪律。
    if (current == CompareRecordingPhase.idle) {
      takeover.disengage();
    } else {
      takeover.engage(suppressLoop: current == CompareRecordingPhase.recording);
    }
  }
}
