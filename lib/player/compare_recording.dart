import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../annotation/compare_materials.dart';
import '../camera_capture/camera_capture.dart';
import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart' show BeatPhase;
import '../core/playback/playback_engine.dart';
import '../core/private_json.dart' show PrivateJsonStorage;
import '../surface_direction/surface_direction.dart' show SurfaceBaselines;
import 'notice.dart' show NoticeId, NoticeSpec;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 对比-录制阶段注入点：倍速写穿门（speed_control）与页面 UI 共同消费。
class CompareRecordingPhaseModel extends Notifier<CompareRecordingPhase> {
  @override
  CompareRecordingPhase build() => CompareRecordingPhase.idle;

  void set(CompareRecordingPhase phase) => state = phase;

  /// 复位（keepAlive 会话值 = 一个复位方法 + 两个触发点
  /// ——离开播放页、换视频）：回到待录态。
  void reset() => set(CompareRecordingPhase.idle);
}

final compareRecordingPhaseProvider =
    NotifierProvider<CompareRecordingPhaseModel, CompareRecordingPhase>(
      CompareRecordingPhaseModel.new,
    );

/// 录制准备期的可视数拍：与
/// 循环前导**同一套视觉**的「第 0 个八拍顺数」（八拍号固定 0 + 拍号顺数）。
///
/// 准备期的**数字**与浮层数拍同读发布值（录制锚经锚点链派生 `0｜x`）——
/// 本类型只剩准备期的显隐口径：有节拍前导 = 浮层照常（数字由发布值给出），
/// 秒制兜底 = 整段不显示。
///
/// 两个子类都无载荷：数字与浮层同读发布值，
/// 本类型只承载「准备期要不要显示」这一个口径。const 单例判等即可，宿主
/// 每次阶段同步重写同一实例不触发浮层重建。
sealed class RecordingPrepBeatVisual {
  const RecordingPrepBeatVisual();

  /// 准备期是否有数拍内容（false = 秒制兜底：整段不显示）。
  bool get showsContent;
}

/// 节拍前导期：有节拍前导（浮层照常，数字由发布值按录制锚给出）。
final class RecordingPrepLeadingBeat extends RecordingPrepBeatVisual {
  const RecordingPrepLeadingBeat();

  @override
  bool get showsContent => true;

  @override
  String toString() => 'RecordingPrepLeadingBeat()';
}

/// 秒制兜底（异常网格 / 起录点前无可用拍点）：**无数字**（无声由会话的拍
/// 计时出口保证）。浮层在准备期整段不出现——「无节拍器/数字/声」是同一句话。
final class RecordingPrepSilentBeat extends RecordingPrepBeatVisual {
  const RecordingPrepSilentBeat();

  @override
  bool get showsContent => false;

  @override
  String toString() => 'RecordingPrepSilentBeat()';
}

/// 两支的 const 单例（宿主每次阶段同步重写同一实例，不触发浮层重建）。
const RecordingPrepLeadingBeat kRecordingPrepLeadingBeat =
    RecordingPrepLeadingBeat();
const RecordingPrepSilentBeat kRecordingPrepSilentBeat =
    RecordingPrepSilentBeat();

/// 录制准备期可视数拍的注入点（宿主在录制阶段同步处写入，与
/// [compareRecordingPhaseProvider] 同一条路径）：null = 无准备期，数拍显示
/// 不干预（锚点链照旧）。
class RecordingPrepBeatModel extends Notifier<RecordingPrepBeatVisual?> {
  @override
  RecordingPrepBeatVisual? build() => null;

  void set(RecordingPrepBeatVisual? visual) {
    if (state == visual) return;
    state = visual;
  }

  /// 复位（keepAlive 会话值 = 一个复位方法 + 两个触发点
  /// ——离开播放页、换视频）：回到「不干预数拍显示」。
  void reset() => set(null);
}

final recordingPrepBeatProvider =
    NotifierProvider<RecordingPrepBeatModel, RecordingPrepBeatVisual?>(
      RecordingPrepBeatModel.new,
    );

/// 录制会话起录点的注入点（宿主在录制阶段同步处写入，与
/// [compareRecordingPhaseProvider] 同一条路径）：录制阶段（含准备期）非
/// null、其余态 null（不干预锚点链）。
///
/// 消费点 = 数拍锚点解析：**录制期锚 = 起录点**（再由锚点对齐纯函数归到
/// 网格八拍大线上）——无激活段录制不再退化成「最近分段线 → 首线」。
///
/// 为什么不并进 [recordingPrepBeatProvider]：两者生命周期不同——准备期可视
/// 数拍在越过起录点那一刻就该清空（交回锚点链），而起录点要一直活到录制收尾
/// 才失效。并成一个值道会让「准备期结束」与「录制期锚失效」两个边沿绑死。
class CompareRecordingStartModel extends Notifier<Duration?> {
  @override
  Duration? build() => null;

  void set(Duration? start) {
    if (state == start) return;
    state = start;
  }

  /// 复位（keepAlive 会话值 = 一个复位方法 + 两个触发点
  /// ——离开播放页、换视频）：回到「不干预锚点链」。
  void reset() => set(null);
}

final compareRecordingStartProvider =
    NotifierProvider<CompareRecordingStartModel, Duration?>(
      CompareRecordingStartModel.new,
    );

/// 本次录制**冻结的基线项**（画面方向库的 [SurfaceBaselines]；冻结时刻 =
/// 会话武装落定那一刻）的注入点：宿主在录制阶段同步处写入（与
/// [compareRecordingPhaseProvider] 同一条路径），非武装态 null。
///
/// 消费点 = 练习侧画面方向装配点：录制期读冻结的那份、其余时间读设备事实的
/// 当前取值——于是「录制所见 == 回看所见」在设备事实中途变化时仍成立，而
/// 练习镜像是活输入（不在本值内、照旧现读）。
class ArmedSurfaceBaselinesModel extends Notifier<SurfaceBaselines?> {
  @override
  SurfaceBaselines? build() => null;

  void set(SurfaceBaselines? baselines) {
    if (state == baselines) return;
    state = baselines;
  }

  /// 复位（keepAlive 会话值 = 一个复位方法 + 两个触发点
  /// ——离开播放页、换视频）：回到「不冻结」。
  void reset() => set(null);
}

final armedSurfaceBaselinesProvider =
    NotifierProvider<ArmedSurfaceBaselinesModel, SurfaceBaselines?>(
      ArmedSurfaceBaselinesModel.new,
    );

/// 录制分辨率档：设备级设置——`global_private.json` 的
/// `recordingResolution` 键并列扩键（不新建文件）；默认 1080p，可切
/// 720p。切档 UI 归将来设备级设置。
class RecordingResolutionModel extends Notifier<RecordingResolution> {
  @override
  RecordingResolution build() => RecordingResolution.fhd1080p;

  /// 启动恢复（宿主传入设备级私密存储；读失败维持默认 1080p）。
  Future<void> restore(PrivateJsonStorage storage) async {
    try {
      final raw = (await storage.read())['recordingResolution'];
      if (raw == '720p') state = RecordingResolution.hd720p;
      if (raw == '1080p') state = RecordingResolution.fhd1080p;
    } on Object {
      // 存储不可读：维持默认档位。
    }
  }

  /// 切换分辨率档（写点：随切随落设备级私密文件，下次启动经
  /// [restore] 回来；写失败时会话值仍生效）。
  Future<void> select(
    RecordingResolution resolution,
    PrivateJsonStorage storage,
  ) async {
    state = resolution;
    try {
      await storage.mutate((json, {required bool present}) {
        json['recordingResolution'] = switch (resolution) {
          RecordingResolution.hd720p => '720p',
          RecordingResolution.fhd1080p => '1080p',
        };
      });
    } on Object {
      // 存储不可写：会话内档位仍生效。
    }
  }
}

final recordingResolutionProvider =
    NotifierProvider<RecordingResolutionModel, RecordingResolution>(
      RecordingResolutionModel.new,
    );

/// 录制准备拍数缺省值（默认 8；local `prefs` 段缺键
/// 与解析失败兜底共用此常量）。
const int kDefaultRecordingPrepBeats = 8;

/// 越过起录点的宽限期：位置流在宽限期内始终没有越过起录点时按
/// 定时器补触发，保证不会卡在准备态（异常源/内核不推进位置）。
const Duration kRecordingCrossGrace = Duration(milliseconds: 1000);

/// 对比-录制会话：对比-播放
/// 态常驻相机式录制钮的会话控制器——按下 = 暂停 → 循环前导式回退（录制准备
/// 拍数，独立设置项、默认 8；异常网格或起点前不足按秒制兜底 ≈4s）→
/// **位置越过起录点**即起录。
///
/// 起录时机：
/// - **位置驱动**：前导在引擎里连续播放，本会话订阅位置流，位置自然越过
///   起录点的那一刻就是起录时刻——不再「到点 seek 回起点再起录」（那次补
///   seek 就是源侧可见的顿挫）。位置流不推进时的兜底见 [kRecordingCrossGrace]。
/// - **提前武装**：起录点前约 `kRecordingArmMarginMs` 先武装编码器（引擎
///   照常连续播放、不 seek）。武装点与起录点之间录下的**前言**留在素材文件
///   里作对齐余量，但不进片段定义（片段入点 = 前言长度）。
/// - **无前导路径**：起点前没有余量、引擎处于暂停时先武装、再把引擎摆到
///   起录点起播，全程只有一次定位 seek。
///
/// 激活学习段段尾自动停、无激活段手动停或有效区间尾自动停；录制中强制
/// 1.0×；停止后暂停在停止点、恢复原倍速，素材经 [onIngest] 入库（连带前言
/// 长度，供片段入点换算）；武装窗口内取消 = 停录并丢弃已武装的那段。
///
/// 本控制器不持有 provider/IO：环境取值经 [CompareRecordingEnv] 注入，
/// 素材输出路径经 [resolveOutputFile] 注入，入库经 [onIngest] 回调；
/// 准备期拍声由节拍呈现按「位置是唯一真相」驱动（录制锚进上下文）。
class CompareRecordingController extends ChangeNotifier {
  CompareRecordingController(
    this._engine,
    this._camera,
    this._env,
    this._resolveOutputFile,
    this._onIngest,
  );

  final PlaybackEngine _engine;
  final CameraCaptureService _camera;
  final CompareRecordingEnv _env;
  final Future<File> Function() _resolveOutputFile;

  /// 入库回调：素材记录 ＋ 本次录制的**前言长度**（片段入点 = 前言长度）。
  final Future<void> Function(MaterialRecord record, int preambleMs) _onIngest;

  CompareRecordingPhase _phase = CompareRecordingPhase.idle;

  /// 当前会话阶段。
  CompareRecordingPhase get phase => _phase;

  Timer? _autoStopTimer;
  Timer? _crossDeadline;
  StreamSubscription<Duration>? _positions;

  /// 本次会话的「播放到尾」订阅（判据③）：引擎先到视频物理尾即以那
  /// 一刻立即停——准备期同样接住（播到尾就直接收尾），录制期则立即停录入库。
  StreamSubscription<void>? _completions;
  bool _disposed = false;
  bool _advancing = false;

  /// 编码器**已在写**（武装成功；起录边沿不是「我们调用起录」）。
  bool _armed = false;

  /// 在途武装（取消路径要等它落定再停录，否则停录请求赶在编码器开始写之前，
  /// 那段就再没人停了）；落定即清位，失败不留在位（下一次会话重新武装）。
  Future<void>? _armInFlight;
  double _savedRate = 1.0;
  RecordingPrepPlan _prep = const RecordingPrepPlan(
    startPointMs: 0,
    leadStartMs: 0,
    leadDurationMs: 0,
    beatLed: false,
  );

  /// 本次会话解析出的录制准备拍数（前导可视数拍的拍号基准；与循环前导的
  /// 拍档无关）。
  int _prepBeats = 0;

  /// 本次会话的武装点（= 起录点 − 余量，钳到有效区间头）。
  int _armPointMs = 0;

  /// 武装落定那一刻的引擎位置（**实测前言**基准）：编码器从这一刻
  /// 起在写，素材文件偏移 0 就落在这个源位置上。null = 引擎在武装之后被
  /// 重新摆位（无前导路径），源位置差不再是前言。
  int? _armedAtPositionMs;

  /// 实测前言长度（毫秒；起录点那一刻定值）：武装落定到位置越过起录点之间
  /// 录进素材头部的那一段——**不是**计划的武装余量（两者差一个「武装落定
  /// 耗时」：`startRecording()` 直到系统报告录像已开始才返回）。
  int _preambleMs = 0;

  /// 本次会话在**武装**落定那一刻冻结的**基线项**（[SurfaceBaselines]）：
  /// **素材方向**（[SurfaceBaselines.materialDirection]）取自它，此后本会话不再
  /// 重读设备事实；练习镜像是活输入、不在本值内。未武装为 null（冻结只活一次
  /// 会话）；宿主经 [armedSurfaceBaselinesProvider] 把它交给练习侧装配点。
  SurfaceBaselines? _armedBaselines;

  /// 本次会话冻结的基线项；未武装为 null。
  SurfaceBaselines? get armedBaselines => _armedBaselines;

  /// 录制准备拍数解析（随舞私密 prefs 段读取点；默认 8）。
  Future<int> resolvePrepBeats() => _env.resolvePrepBeats();

  /// 本会话准备期的可视数拍（null = 无准备期，数拍显示不干预）：
  /// 节拍前导期 = 第 0 个八拍顺数（拍号按**准备拍序列**与当前媒介位置派生）；
  /// 秒制兜底 = 无数字。宿主在阶段同步处把它写进
  /// [recordingPrepBeatProvider]，数拍浮层按它渲染。
  RecordingPrepBeatVisual? get prepBeatVisual {
    if (_phase != CompareRecordingPhase.preparing) return null;
    if (!_prep.beatLed || _prep.beatTimesMs.isEmpty) {
      return kRecordingPrepSilentBeat;
    }
    return kRecordingPrepLeadingBeat;
  }

  /// 本次会话的起录点（非录制态 null = 不干预锚点链）：录制阶段
  /// 的**数拍锚 = 起录点**——起录点吸附在八拍点上
  /// （就绪网格；占位/异常网格保持按下位置，锚链按既有对齐口径回落），
  /// 越起录点即 1｜1 起；有激活段时起录点即段首，与既有激活锚同值。
  Duration? get recordingStartPoint => _phase == CompareRecordingPhase.idle
      ? null
      : Duration(milliseconds: _prep.startPointMs);

  /// 按下录制（待录态 → 准备/武装 → 录制）。非待录态为 no-op。
  ///
  /// 返回值 = 本次按下的落定。[RecordingStartOutcome.rejectedTooCloseToEnd]
  /// = 无激活段且按下位置距有效区间尾不足一拍/已在尾线之后——**拒录**，不落
  /// 素材、不落片段、不起前导（准备期那几拍因此不会被武装），宿主据此给一句
  /// 短暂提示。拒录判定在动引擎之前落定，故拒录路径上引擎位置、倍速、播放态
  /// 一律不变；其余失败落定（准备期收尾）另计，不冒充拒录原因。
  Future<RecordingStartOutcome> startRequested() async {
    if (_disposed || _phase != CompareRecordingPhase.idle) {
      return RecordingStartOutcome.aborted;
    }
    final active = _env.activeLoopRange;
    final rangeStartMs = _env.rangeStart.inMilliseconds;
    final pressPositionMs = _engine.position.inMilliseconds;
    final int startPointMs;
    if (active != null) {
      // 有激活段的一支：起点 = 段首，不受区间尾判据约束。
      startPointMs = active.start.inMilliseconds;
    } else {
      final decision = computeRecordingStart(
        pressPositionMs: pressPositionMs,
        rangeStartMs: rangeStartMs,
        rangeEndMs: _env.rangeEnd.inMilliseconds,
        // 拒录阈值 = 名下单拍（入参交给纯件；会话不写死阈值）——异常态
        // 即哨兵 500ms，取值条款由读面 [BeatGridReads.nominalBeat] 承载。
        minTailMs: _env.beatGrid.nominalBeat.inMilliseconds,
        // 当前相位：起录点吸附到相位下最近的八拍点；
        // 占位/异常网格不产生八拍点 → null = 按下位置原样（既有口径）。
        phase: _env.beatPhase,
      );
      if (!decision.recordable) {
        return RecordingStartOutcome.rejectedTooCloseToEnd;
      }
      startPointMs = decision.startPointMs;
    }
    _prepBeats = await _env.resolvePrepBeats();
    _prep = computeRecordingPrep(
      startPointMs: startPointMs,
      rangeStartMs: rangeStartMs,
      prepBeats: _prepBeats,
      grid: _env.beatGrid,
    );
    // 武装点 = 起录点 − 余量，钳到有效区间头（判据①）。
    _armPointMs = computeRecordingArmPoint(
      startPointMs: startPointMs,
      rangeStartMs: rangeStartMs,
    );
    _armedAtPositionMs = null;
    _preambleMs = 0;
    _armedBaselines = null;
    // 录制准备即强制 1.0×（停后恢复原倍速）。先落 preparing 阶段再动
    // 引擎：统计排除随阶段同步，前导回退的播放边沿已在排除内。
    _savedRate = _engine.rate;
    _phase = CompareRecordingPhase.preparing;
    notifyListeners();
    // 尾点取先到者（判据③）：**引擎先到视频物理尾**（尾线晚于物理
    // 时长或读不到）时以那一刻立即停——准备期就播到尾时同一条路收尾
    // （取消准备、不落素材），录制期则立即停录入库，都不干等墙钟。
    _watchCompletion();
    await _engine.setRate(1.0);
    await _engine.pause();
    if (_disposed || _phase != CompareRecordingPhase.preparing) {
      return RecordingStartOutcome.aborted;
    }
    if (_prep.leadDurationMs > 0) {
      // 前导连续播放：起播这一次定位 seek 之后不再有任何 seek。
      _watchPositions();
      await _engine.seek(Duration(milliseconds: _prep.leadStartMs));
    } else {
      // 无前导路径（判据③）：先武装、再把引擎摆到起录点起播——全程仅一次
      // 定位 seek。
      await _armEncoder();
      if (_disposed || !_isPreparing) return RecordingStartOutcome.aborted;
      // 武装之后才把引擎摆到起录点：这段路里录下的静止画面在帧级以下（武装
      // 一落定就 seek），故本轮没有可作前言对齐的源位置差。
      _armedAtPositionMs = null;
      _watchPositions();
      await _engine.seek(Duration(milliseconds: _prep.startPointMs));
    }
    await _engine.play();
    // 宽限兜底：到起录点的剩余时长就是前导时长（无前导路径为 0）。
    _startCrossDeadline(remainingMs: _prep.leadDurationMs);
    return RecordingStartOutcome.started;
  }

  /// 仍在录制准备期（位置驱动状态机每个 await 之后都要复查）。
  bool get _isPreparing =>
      !_disposed && _phase == CompareRecordingPhase.preparing;

  /// 订阅引擎位置流：位置越过武装点即武装、越过起录点即起录（位置驱动）。
  void _watchPositions() {
    _positions = _engine.positionStream.listen((_) => unawaited(_advance()));
  }

  /// 退订位置流（起录、收尾、停录、dispose 四条路共用；退订后位置流不再
  /// 触发任何编排）。
  void _stopWatching() {
    unawaited(_positions?.cancel());
    _positions = null;
  }

  /// 宽限兜底计时（到起录点的剩余时长 + [kRecordingCrossGrace]）：位置流
  /// 始终不推进时由它补触发，保证不会卡在准备态。
  void _startCrossDeadline({required int remainingMs}) {
    _crossDeadline?.cancel();
    final waitMs = remainingMs < 0 ? 0 : remainingMs;
    _crossDeadline = Timer(
      Duration(milliseconds: waitMs) + kRecordingCrossGrace,
      () => unawaited(_onCrossDeadline()),
    );
  }

  /// 位置流推进一步（位置驱动状态机）。串行执行：武装在途时重入直接让位，
  /// 而武装落定后本方法会再读一次位置，故不会漏掉紧跟其后的起录点。
  Future<void> _advance() async {
    if (_advancing || !_isPreparing) return;
    _advancing = true;
    try {
      if (!_armed) {
        if (_engine.position.inMilliseconds < _armPointMs) return;
        await _armEncoder();
        if (!_isPreparing) return;
      }
      if (_engine.position.inMilliseconds >= _prep.startPointMs) {
        await _crossStartPoint();
      }
    } finally {
      _advancing = false;
    }
  }

  /// 宽限期到：位置流没越过起录点也补起录（先武装、再起录，皆幂等）。
  Future<void> _onCrossDeadline() async {
    if (!_isPreparing) return;
    _crossDeadline = null;
    // 武装幂等：已在途就等它落定——起录不得赶在编码器开始写之前（那段
    // 就白录了）。
    await _armEncoder();
    if (!_isPreparing) return;
    await _crossStartPoint();
  }

  /// 武装编码器（幂等）：**真的开始录**——Android 没有编码器预热 API，故
  /// 「武装」即起录，武装点到起录点之间录下的那段就是前言。素材未归属舞
  /// （videoId 未解析）或武装失败按准备收尾（不留下半截、不留黑屏）。
  Future<void> _armEncoder() {
    if (_armed) return Future<void>.value();
    return _armInFlight ??= _armOnce();
  }

  Future<void> _armOnce() async {
    try {
      if (_env.videoId == null) {
        await _abortPrep();
        return;
      }
      try {
        final file = await _resolveOutputFile();
        // 起录不带档位：档位在进入对比态开流时已定在预览实例上，
        // 起录只在该实例上挂录像用例、预览流全程不断。会话中途改档不改本
        // 实例的档，故起录后的素材档 = 开流档。
        await _camera.startRecording(
          outputPath: file.path,
          orientation: _env.currentOrientation,
        );
        // 「编码器在写」才是武装成立：`startRecording` 直到系统报告录像已
        // 开始才返回，此前它还没在写。此处的引擎位置就是素材文件偏移 0 对应
        // 的源位置，起录点与它的差即**实测前言长度**（前导路径上引擎连续
        // 1.0× 播放，源时间与墙钟等比）。
        _armed = true;
        // 武装落定（编码器在写）那一刻取一次**基线项**：本次录制的素材方向由
        // 它给出，此后本会话不再重读设备事实——武装之后设备事实变了也不改已
        // 冻结的取值（武装之前改的取新值）。前言从这一刻开始写，故前言与正片
        // 同向。取完即通知：消费点据此从「设备事实当前取值」切到这份冻结值。
        // 会话已在武装在途期间收尾（取消）则不取：那次产出会被丢弃，不落素材。
        if (_isPreparing) {
          _armedBaselines = _env.surfaceBaselines;
        }
        _armedAtPositionMs = _engine.position.inMilliseconds;
        notifyListeners();
      } on Object {
        await _abortPrep();
      }
    } finally {
      // 在途标记随本次尝试的落定清位（成功与否都清）：失败时 `_armed` 仍为
      // 假，下一次会话必须真的重新武装——留着已完成的 Future 会让下一次
      // 会话「跳过武装直接起录」（黑账：进录制态而没有素材）。
      _armInFlight = null;
    }
  }

  /// 位置越过起录点：起录（**不再补 seek**）。起录点那一帧由提前武装保证
  /// 已入素材；起录点是素材与源时间轴的唯一对齐锚点。
  Future<void> _crossStartPoint() async {
    if (!_isPreparing) return;
    _phase = CompareRecordingPhase.recording;
    // 越起录点：预备期拍声由节拍呈现按「位置是唯一真相」自收（前导区
    // 0|x → 起点起 1|1），无显式收口。
    _crossDeadline?.cancel();
    _crossDeadline = null;
    _stopWatching();
    notifyListeners();
    // 实测前言：武装落定（编码器在写）到起录点之间录下的那段。位置已越过
    // 起录点时为负 → 0（编码器比余量慢：素材头晚于起录点，该改常量）。
    final armedAtMs = _armedAtPositionMs;
    final measuredMs = armedAtMs == null ? 0 : _prep.startPointMs - armedAtMs;
    _preambleMs = measuredMs < 0 ? 0 : measuredMs;
    // 自动停：激活段 = 段尾；无激活段 = 有效区间尾。起录点起按 1.0× 顺播
    // 计；位置已越过起录点时以实际位置为锚（不把已播掉的那点算回去）。
    final endMs = activeEndMs();
    final positionMs = _engine.position.inMilliseconds;
    final anchorMs = positionMs < _prep.startPointMs
        ? _prep.startPointMs
        : positionMs;
    // 有效区间尾读不到（0 = 未知）：**不起零延迟的自停墙钟**——那会
    // 把一次正常按下变成「起录即停」并落一条近 0 长的素材与片段。这一支的
    // 终点交物理尾（[_watchCompletion]）或手动停。
    if (endMs > 0) {
      final waitMs = endMs - anchorMs;
      _autoStopTimer = Timer(
        Duration(milliseconds: waitMs < 0 ? 0 : waitMs),
        () => unawaited(stopRequested()),
      );
    }
  }

  /// 订阅引擎「播放到尾」：物理尾先到时以那一刻为准立即停（墙钟判据还要
  /// 等到尾线，干等就会把重复/静止画面录进素材尾部；判据③）。
  void _watchCompletion() {
    _completions ??= _engine.completedStream.listen(
      (_) => unawaited(stopRequested()),
    );
  }

  /// 准备收尾（不起录）：暂停、恢复原倍速、回待录态。
  Future<void> _abortPrep() async {
    if (_disposed) return;
    _phase = CompareRecordingPhase.idle;
    _armedBaselines = null;
    _cancelPendingTriggers();
    _stopWatching();
    await _engine.pause();
    await _engine.setRate(_savedRate);
    notifyListeners();
  }

  /// 自动停的终点（毫秒）：激活段段尾优先，否则有效区间尾。
  /// **0 = 读不到**（无激活段且有效区间尾未知）：调用侧据此不起自停墙钟。
  int activeEndMs() {
    final active = _env.activeLoopRange;
    if (active != null) return active.end.inMilliseconds;
    return _env.rangeEnd.inMilliseconds;
  }

  /// 停止（手动 / 段尾与区间尾自动 / 退后台与离开对比态）：未在会话中为
  /// no-op。停后暂停在停止点、恢复原倍速、素材入库。
  ///
  /// **武装窗口内取消**（判据⑥）：编码器已在写——停录并丢弃已武装的
  /// 那段，不落素材、不留半截。
  Future<void> stopRequested() async {
    if (_disposed || _phase == CompareRecordingPhase.idle) return;
    final wasRecording = _phase == CompareRecordingPhase.recording;
    _phase = CompareRecordingPhase.idle;
    // 释放冻结的基线项与阶段一起落：收尾的 await 窗口里不再读冻结值（下一次
    // 录制在武装那一刻重新取一次）。
    _armedBaselines = null;
    _cancelPendingTriggers();
    _stopWatching();
    // 武装在途：等它落定再停录——否则停录请求会赶在编码器开始写之前，那段
    // 就再没人停了。落定后按「编码器是否在写」决定要不要停录。
    final pendingArm = _armInFlight;
    if (pendingArm != null) await pendingArm;
    RecordingOutput? output;
    if (_armed) {
      output = await _camera.stopRecording();
    }
    await _engine.pause();
    await _engine.setRate(_savedRate);
    _armed = false;
    _armInFlight = null;
    notifyListeners();
    // 武装窗口内取消：产出连同文件一并丢弃（那段是前言余量，不构成一次录制
    // ——留在私有素材目录里就是一个没有清单条目的孤儿文件）。
    if (!wasRecording || output == null) {
      if (output != null) _discardOutput(output.filePath);
      return;
    }
    final videoId = _env.videoId;
    if (videoId == null) return;
    var sizeBytes = 0;
    try {
      sizeBytes = File(output.filePath).lengthSync();
    } on Object {
      // 文件状态读取失败按 0 记账，不阻断入库。
    }
    await _onIngest(
      MaterialRecord(
        id: 'mat_${DateTime.now().microsecondsSinceEpoch}',
        videoId: videoId,
        createdAt: DateTime.now(),
        // 素材时长 = 相机 seam 交出的**真实编码时长**（编码器真正在写到停下
        // 两个边沿之间的实测值，不含起录前的等待与停录收尾）。
        durationMs: output.duration.inMilliseconds,
        // 素材源原点 = 起录点（唯一对齐锚点，不取武装点）。
        sourceStartMs: _prep.startPointMs,
        fileName: p.basename(output.filePath),
        sizeBytes: sizeBytes,
      ),
      _preambleMs,
    );
  }

  /// 静默删除被丢弃的武装产物（删不掉也不阻断会话收尾）。同步删除：与上方
  /// 素材字节日志同一口径（会话收尾不把异步文件 IO 带进编排）。
  void _discardOutput(String filePath) {
    try {
      final file = File(filePath);
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 删除失败不阻断收尾：孤儿文件不影响会话状态。
    }
  }

  /// 取消本次会话的全部在途触发（定时器 ＋ 「播放到尾」订阅）：停录、准备
  /// 收尾、dispose 三条收尾路共用。起录点那一步**不**取消——录制期要靠该
  /// 订阅接住物理尾（判据③）；位置流的退订仍归 [_stopWatching]。
  void _cancelPendingTriggers() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    _crossDeadline?.cancel();
    _crossDeadline = null;
    unawaited(_completions?.cancel());
    _completions = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelPendingTriggers();
    _stopWatching();
    super.dispose();
  }
}

/// 录制会话阶段。
enum CompareRecordingPhase { idle, preparing, recording }

/// 按下录制的落定：**拒绝原因收成封闭枚举**，
/// 不建平行真相源（同一形状）——宿主只在「距区间尾不足一拍/已在
/// 尾线之后」这一支给拒录提示，其余落定（非待录态 no-op、素材未归属舞或
/// 武装失败经准备收尾）不给**假原因**。
enum RecordingStartOutcome {
  /// 已进入会话（准备/武装 → 录制）。
  started,

  /// **拒录**：无激活段，按下位置距有效区间尾不足一拍或已在尾线之后——
  /// 不落素材、不落片段、不起前导。
  rejectedTooCloseToEnd,

  /// 未起步：非待录态的 no-op，或准备期收尾（videoId 未解析、武装失败）。
  aborted,
}

/// 录制会话环境取值（宿主注入：provider 读点收在播放页接线一处）。
///
/// 录制分辨率档**不在此列**：档位是**开流时**的属性——进入对比态
/// 开流时按档建预览控制器，起录只在该实例上挂录像用例，故会话内不需要
/// （也不该）再读一次档。
abstract interface class CompareRecordingEnv {
  /// 录制准备拍数（随舞私密 prefs 段读点；默认 8）。
  Future<int> resolvePrepBeats();

  /// 当前派生节拍网格（收非空）：准备拍
  /// 序列（起录点前可用的真实拍点）与拒录阈值（名下单拍）的唯一来源；
  /// 「异常态」由网格性质自陈（[BeatGridReads.isSecondsFallback]），不再
  /// 用空值编码。
  BeatGrid get beatGrid;

  /// 当前八拍相位：起录点吸附到相位下最近的八拍点
  /// （唯一出处 = [BeatPhase.nearest]）。null = 占位/异常网格
  /// 不产生八拍点 → 起录点 = 按下位置原样（既有口径）。
  BeatPhase? get beatPhase;

  /// 有效练习区间（首/尾）。
  Duration get rangeStart;

  Duration get rangeEnd;

  /// 当前激活循环范围（学习段/临时段；null = 无激活段）。
  ({Duration start, Duration end})? get activeLoopRange;

  /// 当前 videoId（未解析为 null：不起录——素材必须归属舞）。
  String? get videoId;

  /// 起录瞬间的画面方向（方向锁定元数据来源）。
  RecordingOrientation get currentOrientation;

  /// 设备事实的当前取值（画面方向库的**基线项**：平台预览基准 / 平台保存基准）：
  /// **武装落定那一刻现读一次**，此后本会话只读那份冻结值。
  SurfaceBaselines get surfaceBaselines;
}

/// [CompareRecordingEnv] 的闭包装配实现（宿主接线一处组装）：取值都是
/// **按下时现读**的函数，不构造时快照。
class CallbackCompareRecordingEnv implements CompareRecordingEnv {
  CallbackCompareRecordingEnv({
    required this.resolvePrepBeatsOf,
    required this.beatGridOf,
    required this.phaseOf,
    required this.rangeStartOf,
    required this.rangeEndOf,
    required this.activeLoopRangeOf,
    required this.videoIdOf,
    required this.orientationOf,
    required this.surfaceBaselinesOf,
  });

  final Future<int> Function() resolvePrepBeatsOf;

  /// 录制准备拍数（随舞私密 prefs 段读取点；默认 8）。
  @override
  Future<int> resolvePrepBeats() => resolvePrepBeatsOf();

  final BeatGrid Function() beatGridOf;

  @override
  BeatGrid get beatGrid => beatGridOf();

  final BeatPhase? Function() phaseOf;

  @override
  BeatPhase? get beatPhase => phaseOf();

  final Duration Function() rangeStartOf;

  @override
  Duration get rangeStart => rangeStartOf();

  final Duration Function() rangeEndOf;

  @override
  Duration get rangeEnd => rangeEndOf();

  final ({Duration start, Duration end})? Function() activeLoopRangeOf;

  @override
  ({Duration start, Duration end})? get activeLoopRange => activeLoopRangeOf();

  final String? Function() videoIdOf;

  @override
  String? get videoId => videoIdOf();

  final RecordingOrientation Function() orientationOf;

  @override
  RecordingOrientation get currentOrientation => orientationOf();

  final SurfaceBaselines Function() surfaceBaselinesOf;

  @override
  SurfaceBaselines get surfaceBaselines => surfaceBaselinesOf();
}

/// 拒录提示声明：一行声明 = 身份 + 内容 + 定位 key。
/// 触发面由提示模块持有（无激活段按下录制经 `noticeTriggerProvider(
/// NoticeId.compareRecordRejected)` 只报身份）；挂载由演出层的唯一宿主
/// 承担。提示纯视觉：不产生任何状态变化、不入撤销史、不落素材与片段。
Widget compareRecordRejectedNoticeContent(BuildContext _) =>
    const Text('太靠近结尾，无法起录', style: kNoticeTextStyle);

/// 拒录提示声明清单项（组合根装配）。
const compareRecordRejectedNoticeSpec = NoticeSpec(
  id: NoticeId.compareRecordRejected,
  content: compareRecordRejectedNoticeContent,
  noticeKey: Key('compare_record_rejected_prompt'),
);

/// 相机式录制钮的形制取值：外环白环外径
/// [kCompareRecordButtonOuterDiameter] 与环厚 [kCompareRecordButtonRingThickness]、
/// 待录内芯白实心圆直径 [kCompareRecordButtonIdleCoreDiameter]、录制中内芯红圆角
/// 方块边长 [kCompareRecordButtonRecordingCoreSize] 与圆角
/// [kCompareRecordButtonRecordingCoreRadius]。
const double kCompareRecordButtonOuterDiameter = 72;
const double kCompareRecordButtonRingThickness = 4;
const double kCompareRecordButtonIdleCoreDiameter = 56;
const double kCompareRecordButtonRecordingCoreSize = 32;
const double kCompareRecordButtonRecordingCoreRadius = 8;
const Color kCompareRecordButtonRecordingColor = Color(0xFFE53935);

/// 录制钮距画面底边（系统手势内缩另加）。
const double kCompareRecordButtonBottomInset = 24;

/// 相机式录制钮：对比-播放态常驻——待录态
/// 白环 + 白实心圆；准备态与录制中内芯变红圆角方块（可点停）；**不显示已录
/// 时长**（控制器秒表与素材时长时间不同源，会显示一个比实际录到的更
/// 长的值——会撒谎的数字不如不给）。取景调节态内整枚钮不画（底部
/// 居中让给取景条），故本件没有置灰相位。
class CompareRecordButton extends StatelessWidget {
  const CompareRecordButton({super.key, required this.controller, this.onTap});

  final CompareRecordingController controller;

  /// 点击语义由宿主按阶段分发（待录 → 起录；录制中/准备中 → 停）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final red = controller.phase != CompareRecordingPhase.idle;
        return SizedBox(
          key: const Key('compare_record_hit'),
          // 命中盒 = 外环外径（「不小于 72」下限）：环本身已经大过
          // 通行下限，故不靠透明外扩补命中面；纯图形区无死区由
          // `opaque` 铺满整个盒保证。命中盒与环同值也是刻意的——调大环只会
          // 让命中面跟着变大，不会出现环伸出命中盒之外。
          width: kCompareRecordButtonOuterDiameter,
          height: kCompareRecordButtonOuterDiameter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              key: const Key('compare_record_button'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: kCompareRecordButtonRingThickness,
                ),
              ),
              child: Center(
                child: Semantics(
                  button: true,
                  enabled: true,
                  label: red ? '停止录制' : '开始录制',
                  child: red
                      ? Container(
                          key: const Key('compare_recording_indicator'),
                          width: kCompareRecordButtonRecordingCoreSize,
                          height: kCompareRecordButtonRecordingCoreSize,
                          decoration: BoxDecoration(
                            color: kCompareRecordButtonRecordingColor,
                            borderRadius: BorderRadius.circular(
                              kCompareRecordButtonRecordingCoreRadius,
                            ),
                          ),
                        )
                      : Container(
                          width: kCompareRecordButtonIdleCoreDiameter,
                          height: kCompareRecordButtonIdleCoreDiameter,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
