/// 续播位置与「从头播放？」（续播行为）：
/// 退出播放器/切后台/暂停时把当前位置记录进 index 条目的私密
/// `lastPositionMs`（不随 markers 分享）；再次打开时位置有效则跳到该位置
/// 自动续播，位置超出头部阈值再弹左下角非模态小卡「已从上次位置继续 ·
/// 从头播放？」——点它跳回 0 并继续播放，不点约数秒自动消失、不打断
/// 播放；位置在头部阈值内或上次到尾时不弹卡（尾部视为从头，从头播放）。
///
/// 契约：记录/恢复共用同一条越尾钳制（[resolveResumeTarget]），打开决策由
/// 纯函数 [resumeDecision] 给出；小卡状态 [resumePromptProvider] 为会话级
/// 内存态。
///
/// 依赖方向（单向）：只依赖播放内核接缝、视频索引存储与续播日志缝，零
/// import 中枢；反向不可。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../persistence/video_index.dart' show VideoIndexStorage;
import 'loop_prompt.dart' show tailGuardLog;

/// 「位置在头部数秒内」不弹卡阈值。
const Duration resumeHeadThreshold = Duration(seconds: 5);

/// 「从头播放？」小卡不点自动消失的时长。
const Duration resumePromptAutoDismiss = Duration(seconds: 5);

/// 打开续播决策（纯函数 seam）：按 index 记录的续播位置与视频时长判定
/// 打开行为——不续播（[ResumeDecision.none]，含无位置/上次到尾/时长
/// 未知）、静默续播（[ResumeDecision.continueSilently]，位置在头部阈值
/// 内）、续播并弹「从头播放？」（[ResumeDecision.continueWithPrompt]）。
enum ResumeDecision { none, continueSilently, continueWithPrompt }

ResumeDecision resumeDecision({
  required Duration lastPosition,
  required Duration videoDuration,
}) {
  // 时长未知时位置无从校验（越界/到尾判定失效），不续播。
  if (videoDuration <= Duration.zero) return ResumeDecision.none;
  // 无位置（0 = 上次到尾记录值或从未离开过中部）→ 从头播放，不弹卡。
  if (lastPosition <= Duration.zero) return ResumeDecision.none;
  // 上次到尾（位置 ≥ 时长）→ 从头播放，不弹卡。
  if (lastPosition >= videoDuration) return ResumeDecision.none;
  if (lastPosition < resumeHeadThreshold) {
    return ResumeDecision.continueSilently;
  }
  return ResumeDecision.continueWithPrompt;
}

/// 越尾钳制目标位（纯函数 seam）：续播位置不打到视频尾部或自定义尾线
/// 右侧——① 到尾（[videoDuration] 已知且 >0 且 [position] ≥ 时长）返回 0
/// （到尾=从头，0 是既有存储编码）；② 越自定义尾线（[rangeEnd] >0 且
/// [position] 严格 > [rangeEnd]，且时长未知或 [rangeEnd] < [videoDuration]，
/// 尾线等于时长即整片、不视为尾线）钳回尾线内侧返回 [rangeEnd]；③ 否则
/// [position] 原样（恰在尾线 ==rangeEnd 不算越线）。
Duration resolveResumeTarget({
  required Duration position,
  required Duration? videoDuration,
  required Duration? rangeEnd,
}) {
  if (videoDuration != null &&
      videoDuration > Duration.zero &&
      position >= videoDuration) {
    return Duration.zero;
  }
  if (rangeEnd != null &&
      rangeEnd > Duration.zero &&
      position > rangeEnd &&
      (videoDuration == null || rangeEnd < videoDuration)) {
    return rangeEnd;
  }
  return position;
}

/// 记录续播位置到 index 条目（私密存储，不随 markers 分享）：落盘值经
/// [resolveResumeTarget] 得出——到尾（≥ 时长）记 0（尾部视为从头）、越
/// 自定义尾线记尾线值（续播记录钳制：续播位置不再落到尾线右侧，
/// 越线不再自愈式复现）、其余原样；位置为 0 视为「本次未开播」而非有效
/// 离开点——不改写条目（避免覆掉上次的有效续播位置）；条目不存在（新
/// 视频语义）不新增；位置与现值一致不产生写盘；失败静默（记录属非关键
/// 路径）。
Future<void> recordResumePosition({
  required VideoIndexStorage indexStore,
  required String filePath,
  required Duration position,
  required Duration? videoDuration,
  Duration? rangeEnd,
}) async {
  if (position <= Duration.zero) return;
  final effective = resolveResumeTarget(
    position: position,
    videoDuration: videoDuration,
    rangeEnd: rangeEnd,
  );
  // 越线判定以 resolveResumeTarget 为准（严格 > 尾线），此处仅为其
  // 日志副作用推导，勿在此另立钳制语义。
  if (rangeEnd != null && effective == rangeEnd && position > rangeEnd) {
    tailGuardLog('续播记录越界：$position > 尾线 $rangeEnd → 记尾线内侧');
  }
  final positionMs = effective.inMilliseconds;
  try {
    await indexStore.update((index) {
      final entry = index.findByFilePath(filePath);
      if (entry == null) return index;
      if (entry.lastPositionMs == positionMs) return index;
      return index.replaceEntry(entry.copyWith(lastPositionMs: positionMs));
    });
  } on Object {
    // 记录失败不阻塞播放收尾（下次离开再记录）。
  }
}

/// 续播落盘会话：宿主在组合根建一次，「何时记录」
/// （暂停 / 切后台 / 离开页面 / 播放完成）之外的取数收进本域——索引存取、打开
/// 路径、当前播放位置/时长与生效尾线的读取都经显式闭包注入；库不读容器、不读
/// 构建上下文，可脱离 widget 直测。
class ResumeRecorder {
  ResumeRecorder({
    required this.indexStore,
    required this.filePath,
    required this.positionOf,
    required this.videoDurationOf,
    required this.rangeEndOf,
  });

  final VideoIndexStorage indexStore;
  final String filePath;
  final Duration Function() positionOf;
  final Duration? Function() videoDurationOf;
  final Duration? Function() rangeEndOf;

  /// 记录一次续播位置；写失败静默（见 [recordResumePosition]）。
  Future<void> save() => recordResumePosition(
    indexStore: indexStore,
    filePath: filePath,
    position: positionOf(),
    videoDuration: videoDurationOf(),
    rangeEnd: rangeEndOf(),
  );
}

/// 「从头播放？」小卡状态：打开续播命中时 [show]，点「从头
/// 播放？」跳 0 并继续播放（[restartFromHead]），不点 [resumePromptAutoDismiss]
/// 后自动消失（[dismiss]），不打断播放、不拦截其它交互。
class ResumePromptController extends Notifier<bool> {
  Timer? _autoDismiss;

  @override
  bool build() {
    ref.onDispose(_cancelTimer);
    return false;
  }

  /// 显示小卡并重置自动消失计时。
  void show() {
    if (!ref.mounted) return;
    state = true;
    _cancelTimer();
    _autoDismiss = Timer(resumePromptAutoDismiss, () {
      if (ref.mounted) state = false;
    });
  }

  /// 立即消失（点按/离开播放页）。
  void dismiss() {
    _cancelTimer();
    if (ref.mounted) state = false;
  }

  /// 点「从头播放？」：跳回 0 并保持播放（引擎在播时 seek 后自然续播）。
  Future<void> restartFromHead() async {
    dismiss();
    try {
      await ref.read(playbackEngineProvider).seek(Duration.zero);
    } on Object {
      // seek 失败保持当前位置，卡已按用户意图消失。
    }
  }

  void _cancelTimer() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
  }
}

final resumePromptProvider = NotifierProvider<ResumePromptController, bool>(
  ResumePromptController.new,
);
