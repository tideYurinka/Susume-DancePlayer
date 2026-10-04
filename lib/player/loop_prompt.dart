import 'dart:async';

import 'package:flutter/material.dart';

import '../annotation/annotation_timeline.dart';
import '../core/beat_grid.dart';
import '../core/playback/playback_engine.dart';
import '../core/notice_badge.dart';
import 'visual_tokens.dart';

/// 越尾线加固诊断日志 tag（单 tag debugPrint）：真机 logcat
/// 按此过滤——武装/拦截/自动循环、续播恢复越界、续播记录越界、边界改写
/// 与播放头关系。
const String kTailGuardLogTag = '[tailGuard]';

/// 统一诊断输出：单一出口便于测试注入 debugPrint 捕获。
void tailGuardLog(String message) {
  debugPrint('$kTailGuardLogTag $message');
}

/// 循环提示阶段。
enum LoopPromptPhase {
  /// 无提示、无倒计时。
  idle,

  /// 已播放到尾：左下角提示可见，等待一个八拍后自动循环。
  countdown,

  /// 已点击「不循环」：本次播放会话不再自动循环。
  dismissed,
}

/// 循环提示状态机。
///
/// - 监听 [PlaybackEngine.completedStream]：播放到尾进入 countdown 阶段，
///   延迟一个八拍后自动从头重新播放（未设置视频首/尾时从头，设置后从
///   视频首，随学习段接线）；
/// - 调用 [updateVideoRange] 后改为区间语义：播放中从尾线左侧自动跨过
///   自定义视频尾即停在尾边界再弹提示（自动跨线一律拦截）；显式
///   手动拖进度越线（[markManualSeek]）带放行标记的播放放行到片尾；自动
///   循环从自定义视频首开始；
/// - [dismiss]（「不循环」）：停留于结尾、本次播放会话不再自动循环
///   （后续 completed 事件不再触发提示/循环；重新打开播放器恢复）；
/// - 由任意 [PlaybackEngine]（含 FakeEngine）驱动：循环逻辑 widget 测试
///   经 FakeEngine 完成事件验证。
///
/// 本控制器不持有引擎所有权；[dispose] 只取消倒计时与完成事件订阅。
/// 越尾线拦截：自动跨线一律拦截——播放中且上一位置在尾线左侧、当前位置
/// ≥ 尾线即到尾停 + 循环提示；「手动拖到右侧后播放放行到片尾」——显式
/// 用户拖进度/scrub 越线经 [markManualSeek] 打放行标记，带标记才放行；
/// 自动 seek/续播/边界改写不产生放行标记，起播即在尾线右侧且无标记按
/// 到尾语义处理（停在新尾线并提示）。
class LoopPromptController extends ChangeNotifier {
  LoopPromptController(this._engine, {required this._gridOf}) {
    _completedSubscription = _engine.completedStream.listen(
      (_) => _onCompleted(),
    );
    _positionSubscription = _engine.positionStream.listen(_onPosition);
    _playingSubscription = _engine.isPlayingStream.listen(_onPlayingEdge);
  }

  final PlaybackEngine _engine;

  /// 八拍等待时长换算用节拍网格来源（seam 注入点，**必填**——测试替身
  /// 必须表态自己是哪一种节奏来源，不留占位默认参）：
  /// 触发倒计时时现读，跟随节拍轨三态切换（占位/真实/秒制兜底）。
  final BeatGrid Function() _gridOf;

  StreamSubscription<void>? _completedSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  Timer? _countdown;
  bool _disposed = false;
  bool _stoppingAtVideoEnd = false;

  /// 最近一次观察到的播放位置（逐位置跨线判定用）。
  Duration? _lastObservedPosition;

  /// 显式用户拖进度/scrub 越尾线的放行标记：只有带标记的播放才
  /// 放行到片尾；位置回到尾线左侧或边界改写即清除。自动 seek/续播/边界
  /// 改写不产生标记。
  bool _manualSeekPastEnd = false;

  /// 自动循环起点；默认 0:00（未接线/未设边界时的兜底语义）。
  Duration _loopStart = Duration.zero;

  /// 视频尾停止点；null 表示未启用区间停止（物理完成事件接管）。
  Duration? _stopAt;

  LoopPromptPhase _phase = LoopPromptPhase.idle;

  /// 当前阶段（widget 据此显隐左下角提示弹窗）。
  LoopPromptPhase get phase => _phase;

  /// 本次播放会话是否已点击「不循环」（重新打开播放器后恢复）。
  bool get dismissed => _phase == LoopPromptPhase.dismissed;

  /// 自动循环开始时回调（seek 回起点并 play 之后调用；播放器据此同步 UI）。
  void Function()? onAutoLoopStarted;

  /// 学习段区间循环是否接管尾点语义（激活段优先于视频尾提示）。
  bool _segmentLoopActive = false;

  /// 录制期（含准备期）整片循环抑制开关。
  bool _recordingActive = false;

  /// 尾点语义此刻是否被接管或抑制：录制期优先于学习段循环接管，
  /// 两者都不为真时才轮到「视频尾 = 整片循环」这条默认语义。
  ///
  /// 优先级只写在**这一个地方**：各处 guard 只问本谓词，不靠 `||` 的书写
  /// 顺序隐式裁决（可组合的取值不该由再叠一个
  /// bool + 书写顺序来定仲裁）。
  bool get _tailSemanticsSuspended => _recordingActive || _segmentLoopActive;

  /// 录制期整片循环抑制：录制
  /// 期间（含准备期）**不发生整片循环**——尾点循环提示的倒计时与「一个八拍
  /// 后回片头起播」一并停用。理由：录制有自己的停止判据（一次性墙钟 + 物理
  /// 尾），尾点循环提示抢在它前面暂停/回拨会让素材照录满而声明的源区间比
  /// 实际内容多；「录到一半进度自己跳回片头」也是同一件事的另一面。
  ///
  /// 与 [setSegmentLoopActive] 刻意分开：那条是「学习段循环**接管**尾点语义」
  /// 的既有事实，这条是「谁都不接管、**暂时不循环**」——两个事实各存一处、
  /// 由 [_tailSemanticsSuspended] 一处裁决优先级。
  ///
  /// 形状沿用 [setSegmentLoopActive] 的推送式门（而非 `gridOf` 那样的读缝
  /// 谓词）：本门带**跃迁副作用**——置位要取消在途倒计时（用户在尾点倒计时
  /// 里按下录制时，那个倒计时会把引擎拉回片头、正好砸在录制前导中间）。
  /// 纯读缝谓词表达不了「置位那一刻」。
  void setRecordingActive(bool value) {
    if (_recordingActive == value) return;
    _recordingActive = value;
    _lastObservedPosition = _engine.position;
    if (value && _phase == LoopPromptPhase.countdown) {
      _cancelCountdown();
      _phase = LoopPromptPhase.idle;
      notifyListeners();
    }
  }

  void _onCompleted() {
    // 倒计时中或已「不循环」：不再重复触发。
    if (_tailSemanticsSuspended || _phase != LoopPromptPhase.idle) return;
    _beginCountdown();
  }

  /// 显式用户拖进度/scrub 落点回报：落点在尾线右侧打放行标记
  /// （该次播放放行到片尾），在尾线左侧/恰在尾线则清除标记。宿主在 scrub
  /// 会话收口时调用；自动 seek 不经此。
  void markManualSeek(Duration position) {
    final stopAt = _stopAt;
    final past = stopAt != null && position > stopAt;
    if (_manualSeekPastEnd == past) return;
    _manualSeekPastEnd = past;
    if (past) {
      tailGuardLog('手动拖放行标记：落点 $position 在尾线 $stopAt 右侧，放行到片尾');
    } else {
      tailGuardLog('手动拖落点 $position 未越尾线，放行标记清除');
    }
  }

  /// 更新有效练习区间（视频首/尾）。end 传 null 表示回落到物理视频尾。
  void updateVideoRange({required Duration start, required Duration? end}) {
    _loopStart = start;
    _stopAt = end;
    // 边界改写不保留/不产生放行标记：旧尾线的放行承诺对新尾线
    // 不成立，跨新尾线由逐位置判定重新裁决。
    _manualSeekPastEnd = false;
    final position = _engine.position;
    tailGuardLog(
      '边界改写：start=$start end=$end 播放头=$position 在播=${_engine.isPlaying}',
    );
    // 播放中尾线被移到播放头左侧/越过播放头（自动首尾/分段、节拍对齐、
    // 撤销重做、SetVideoRange、拖线等）：立即停在新尾线并提示；暂停中不
    // 打断，下次起播按新区间武装（起播仍在尾线右侧且无标记 → 到尾语义）。
    if (_engine.isPlaying && end != null && position >= end) {
      tailGuardLog('边界改写后尾线 $end 在播放头 $position 左侧：播放中立即停');
      unawaited(_pauseAtAndPrompt(end));
    }
    // 边界在倒计时中被调整时，旧尾边界上的循环承诺不再成立；重置后由新
    // 边界或 completed 事件重新触发。「不循环」是本次播放会话的用户选择，
    // 不因查看/微调边界而自动反转。
    if (_phase == LoopPromptPhase.countdown) {
      _cancelCountdown();
      _phase = LoopPromptPhase.idle;
      notifyListeners();
    }
  }

  /// 视频首/尾变化同步：无激活区间时按全片回落为物理 completed 语义；
  /// 有激活区间时只置区间语义（范围由激活源接线另行给出）。
  void syncToTimeline(
    AnnotationTimeline timeline, {
    required bool segmentLoopActive,
  }) {
    if (segmentLoopActive) {
      setSegmentLoopActive(true);
      return;
    }
    setSegmentLoopActive(false);
    final hasDuration = timeline.videoDuration > Duration.zero;
    updateVideoRange(
      start: hasDuration ? timeline.rangeStart : Duration.zero,
      end: hasDuration ? timeline.rangeEnd : null,
    );
  }

  /// 标记学习段循环接管（true）或交还（false）尾点语义。
  ///
  /// 接管时取消尚未完成的旧视频尾倒计时；交还后按最新视频首/尾重新判定。
  void setSegmentLoopActive(bool value) {
    if (_segmentLoopActive == value) return;
    _segmentLoopActive = value;
    if (value && _phase == LoopPromptPhase.countdown) {
      _cancelCountdown();
      _phase = LoopPromptPhase.idle;
      notifyListeners();
    }
  }

  /// 播放态边沿：起播即在尾线右侧且无放行标记（续播/边界改写/
  /// 自动 seek 留下的越尾线位置）按到尾语义处理——停在新尾线并提示；带
  /// 标记（显式手动拖右）放行到片尾。恰在尾线不算界外（放行起点）。
  void _onPlayingEdge(bool playing) {
    if (!playing) return;
    if (_tailSemanticsSuspended || _phase != LoopPromptPhase.idle) return;
    final stopAt = _stopAt;
    if (stopAt == null) return;
    final position = _engine.position;
    if (position > stopAt && !_manualSeekPastEnd) {
      tailGuardLog('起播 $position 已在尾线 $stopAt 右侧且无放行标记：按到尾语义钳回');
      unawaited(_pauseAtAndPrompt(stopAt));
    }
  }

  void _onPosition(Duration position) {
    final stopAt = _stopAt;
    final previous = _lastObservedPosition;
    _lastObservedPosition = position;
    if (_disposed ||
        _tailSemanticsSuspended ||
        _stoppingAtVideoEnd ||
        _phase != LoopPromptPhase.idle ||
        stopAt == null) {
      return;
    }
    if (position < stopAt) {
      // 回到尾线左侧（自动循环回段首/手动拖回/从头播放）：放行标记失效。
      if (_manualSeekPastEnd) {
        _manualSeekPastEnd = false;
        tailGuardLog('位置 $position 回到尾线 $stopAt 左侧：放行标记清除');
      }
      return;
    }
    // 逐位置跨线判定：播放中上一位置在尾线左侧、当前位置 ≥ 尾线
    // 即自动跨过——到尾停 + 循环提示。无标记且已身在尾线右侧的起播由
    // [_onPlayingEdge] 按到尾语义收口。
    if (!_engine.isPlaying || _manualSeekPastEnd) return;
    if (previous == null || previous >= stopAt) return;
    tailGuardLog('自动跨线拦截：$previous → $position ≥ 尾线 $stopAt');
    unawaited(_pauseAtAndPrompt(stopAt));
  }

  Future<void> _pauseAtAndPrompt(Duration stopAt) async {
    _stoppingAtVideoEnd = true;
    try {
      await _engine.pause();
      if (_disposed) return;
      await _engine.seek(stopAt);
      _beginCountdown();
    } finally {
      _stoppingAtVideoEnd = false;
    }
  }

  void _beginCountdown() {
    if (_phase != LoopPromptPhase.idle) return;
    _phase = LoopPromptPhase.countdown;
    // 倒计时 = 八拍标称：异常态由哨兵算术自然得
    // 4s，实算值原样入 Timer（退化守卫不折进通用换算）。
    _countdown = Timer(_gridOf().eightBeatNominal, _startAutoLoop);
    notifyListeners();
  }

  /// 「不循环」：停留于结尾，本次播放会话不再自动循环。
  void dismiss() {
    if (_phase != LoopPromptPhase.countdown) return;
    _cancelCountdown();
    _phase = LoopPromptPhase.dismissed;
    notifyListeners();
  }

  Future<void> _startAutoLoop() async {
    _countdown = null;
    _phase = LoopPromptPhase.idle;
    notifyListeners();
    // 未设置视频首/尾时 _loopStart 默认 0:00；区间语义下回到视频首。
    tailGuardLog('自动循环：回到 $_loopStart 重新播放');
    await _engine.seek(_loopStart);
    if (_disposed) return; // 倒计时期间已离开播放器：不再自动播放。
    await _engine.play();
    if (_disposed) {
      await _engine.pause(); // dispose 之后不恢复播放。
      return;
    }
    onAutoLoopStarted?.call();
  }

  void _cancelCountdown() {
    _countdown?.cancel();
    _countdown = null;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _cancelCountdown();
    _completedSubscription?.cancel();
    _completedSubscription = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    await _playingSubscription?.cancel();
    _playingSubscription = null;
    super.dispose();
  }
}

/// 左下角循环提示弹窗。
///
/// countdown 阶段可见：提示「即将自动循环播放」并提供「不循环」按钮；
/// 其余阶段不占空间。必须作为 [Stack] 的子级使用（自身是 [Positioned]）。
/// 落位由入参 [anchor] 给出（演出层每帧算一次、两张卡共用一份，已换算成
/// `Positioned` 语义）；卡自身不读系统手势内缩、不写固定内缩。[anchor] 为空
/// = 本次放不下、不渲染。卡自身矩形由 [NoticeBadge] 的底衬接管点按（点卡
/// 不穿透到下层控制层空白手势面）。
class LoopPromptOverlay extends StatelessWidget {
  const LoopPromptOverlay({
    super.key,
    required this.controller,
    required this.anchor,
  });

  final LoopPromptController controller;

  /// 卡左下角（`Positioned` 语义：`left` 距屏幕左缘、`bottom` 距屏幕底）；
  /// null = 本次不画。
  final ({double left, double bottom})? anchor;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final anchor = this.anchor;
        if (controller.phase != LoopPromptPhase.countdown || anchor == null) {
          return const SizedBox.shrink();
        }
        return Positioned(
          key: const Key('loop_prompt'),
          left: anchor.left,
          bottom: anchor.bottom,
          child: NoticeBadge(
            // 紧凑档取值（内边距/字号/间距/按钮样式）只在 visual_tokens 一处
            // 定义、两卡共用。
            padding: kCornerPromptCardPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('即将自动循环播放', style: kCornerPromptCardTextStyle),
                const SizedBox(width: kCornerPromptCardGap),
                TextButton(
                  key: const Key('loop_dismiss_button'),
                  onPressed: controller.dismiss,
                  style: kCornerPromptCardButtonStyle,
                  child: const Text('不循环'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
