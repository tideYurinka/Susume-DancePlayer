/// 投屏入口的五条门（票 #35）：**副本丢失 / 音画同步校准中 /
/// 录制中（含准备期）/ 对比态或取景调节态 / 渲染进行中**。
///
/// ## 它回答什么
///
/// 顶栏那枚「投屏」入口此刻能不能投、为什么不能：五条事实各由一个既有读面
/// 回答（[castEntryFactsProvider] 是**唯一装配点**——生产与测试读同一份），
/// 判定与可点性一律交共用判定表（`tool_slots.dart` 的
/// [evaluateDeclaredGates]，槽的门清单声明在 [kPlayToolCast]）。
/// 「灰着的入口按下去绝不执行动作、只解释原因」因此不是本文件另写的一套：
/// [castEntryVerdict] 是那份判定表的投屏取道，[castEntryBlocksStart] 是那条
/// 契约的点击落点（弹 [castEntryBlockedNoticeSpec] 那一句，返回 true，调用
/// 方直接返回——不落待办、不开准备面板）。
///
/// ## 「不可达」不在入口这道门上
///
/// 「搜不到接收端 / 接收端不可达」只能靠一次发现或一次起投那一下才知道，
/// 做不成构建期事实：它拦在**准备面板空态**与**起投失败面**（短暂提示、
/// 零残留、模式值一位不动），见 `cast_prep_panel.dart` 与 `cast_run.dart`。
///
/// ## 依赖方向（单向）
///
/// 本域 → 若干既有读面（视频副本存在性、校准会话、录制相位、播放会话、
/// 渲染活动事实）与工具表；不 import 播放页、不构控件（提示内容是一件
/// ConsumerWidget，与 `no_subject_hint.dart` / `load_gate.dart` 同款）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_render_activity.dart';
import '../dance/video_copy_presence.dart' show videoCopyPresenceProvider;
import '../player_session/player_session.dart';
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'cast_prep_panel.dart' show kCastPrepCopyMissingText;
import 'compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'play_tool_table.dart' show kPlayToolCast;
import 'session_mode_surfaces.dart' show sessionModeSurfacesOf;
import 'tool_slots.dart'
    show ToolFacts, ToolGateKind, ToolSlotVerdict, evaluateDeclaredGates;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 投屏入口五条门的事实快照：一次求值时刻，每一条门成不成立。
///
/// 纯值——取哪几个读面由装配点（[castEntryFactsProvider]）决定，本类不认识
/// provider。
class CastEntryFacts {
  const CastEntryFacts({
    this.copyMissing = false,
    this.avSyncCalibrating = false,
    this.recording = false,
    this.compareOrFraming = false,
    this.rendering = false,
  });

  /// 这支舞的视频副本不在本机。
  final bool copyMissing;

  /// 音画同步校准会话进行中。
  final bool avSyncCalibrating;

  /// 录制中或录制准备中（相位非待录态——与录制期播放接管域同一次相位
  /// 同步写入，两者同义）。
  final bool recording;

  /// 处于对比态或取景调节态。
  final bool compareOrFraming;

  /// 另一次投屏渲染还在跑。
  final bool rendering;

  @override
  bool operator ==(Object other) =>
      other is CastEntryFacts &&
      other.copyMissing == copyMissing &&
      other.avSyncCalibrating == avSyncCalibrating &&
      other.recording == recording &&
      other.compareOrFraming == compareOrFraming &&
      other.rendering == rendering;

  @override
  int get hashCode => Object.hash(
    copyMissing,
    avSyncCalibrating,
    recording,
    compareOrFraming,
    rendering,
  );
}

/// 五条门的**唯一装配点**：入参是这支舞的视频副本路径（副本丢失门的输入），
/// 其余四条各读既有读面。加一条门 = 本表补一行 + `kPlayToolCast.gates` 补
/// 一声明 + 判定表补一行（三处都少不得，漏一处测试红）。
final castEntryFactsProvider = Provider.family<CastEntryFacts, String>((
  ref,
  videoFilePath,
) {
  final session = ref.watch(playerSessionProvider);
  return CastEntryFacts(
    copyMissing: !ref.watch(videoCopyPresenceProvider).exists(videoFilePath),
    avSyncCalibrating: ref.watch(avSyncCalibrationSessionProvider).active,
    // 录制相位与录制期播放接管域在同一次相位同步里一起写（见
    // `compare_recording_clips.dart` 的 `_sync`），两者同义。
    recording:
        ref.watch(compareRecordingPhaseProvider) != CompareRecordingPhase.idle,
    compareOrFraming:
        session.isCompare || sessionModeSurfacesOf(session.mode).framingActive,
    rendering: ref.watch(castRenderInProgressProvider),
  );
});

/// 五条门 → 判定表吃的事实值（只有投屏那五条被点亮；其余入口一位不受
/// 影响——命中集 = 声明 ∩ 事实）。顶栏装配点读它把事实交给共用判定表。
ToolFacts castEntryToolFacts(CastEntryFacts facts) => ToolFacts(
  castCopyMissing: facts.copyMissing,
  castAvSyncCalibrating: facts.avSyncCalibrating,
  castRecording: facts.recording,
  castCompareOrFraming: facts.compareOrFraming,
  castRendering: facts.rendering,
);

/// 投屏入口此刻的判定：available 为假 = 置灰（tappable 为真 = 按下去只解释
/// 原因）。与顶栏槽声明同源，不另判一套。
ToolSlotVerdict castEntryVerdict(CastEntryFacts facts) => evaluateDeclaredGates(
  kPlayToolCast.gates.toSet(),
  castEntryToolFacts(facts),
);

/// 一条门的一句话（文案改了要能在测试里看见：测试逐字重写期望值）。
///
/// 只认投屏入口的五条门；别的门种调到这里是编程错误，显式报错而不是静默
/// 给一句错话（穷尽 switch：加 [ToolGateKind] 取值即编译报错）。
String castEntryGateText(ToolGateKind gate) => switch (gate) {
  // 与准备面板里那条「副本丢失」是同一事实、同一句话（一处取值）。
  ToolGateKind.castCopyMissing => kCastPrepCopyMissingText,
  ToolGateKind.castAvSyncCalibrating => '音画同步校准中，先退出校准再投屏',
  ToolGateKind.castRecording => '录制中（含准备中）不能投屏，先停录',
  ToolGateKind.castCompareOrFraming => '先退出对比或取景调整，再投屏',
  ToolGateKind.castRendering => '正在渲染投屏副本，渲完再投',
  ToolGateKind.loading ||
  ToolGateKind.noSubject ||
  ToolGateKind.locked ||
  ToolGateKind.gridNotReady ||
  ToolGateKind.previewOutOfBounds => throw StateError(
    '不是投屏入口的门：$gate（投屏入口的门清单见 kPlayToolCast.gates）',
  ),
};

/// 刚才那一下按的是哪条门（提示内容按它取那一句；与三指跳转方向注入点
/// 同款：触发前必先写入，缺省值不参与演出）。
class CastEntryBlockedGate extends Notifier<ToolGateKind> {
  @override
  ToolGateKind build() => ToolGateKind.castCopyMissing;

  void write(ToolGateKind gate) => state = gate;
}

/// 投屏入口被挡下的原因注入点。
final castEntryBlockedGateProvider =
    NotifierProvider<CastEntryBlockedGate, ToolGateKind>(
      CastEntryBlockedGate.new,
    );

/// 「投屏入口被挡下」提示内容（按注入的原因取那一句）。
Widget castEntryBlockedNoticeContent(BuildContext _) =>
    const _CastEntryBlockedNotice();

class _CastEntryBlockedNotice extends ConsumerWidget {
  const _CastEntryBlockedNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(castEntryBlockedGateProvider);
    return Text(castEntryGateText(gate), style: kNoticeTextStyle);
  }
}

/// 投屏入口门的提示声明（组合根装配，每次按都弹）。
const castEntryBlockedNoticeSpec = NoticeSpec(
  id: NoticeId.castEntryBlocked,
  content: castEntryBlockedNoticeContent,
  noticeKey: Key('cast_entry_blocked_prompt'),
);

/// 灰着的投屏入口按下去：命中门即写入原因、弹那一句，返回 true——**调用方
/// 必须直接返回**：不落待办、不开准备面板、不碰任何会话（动作绝不发生）。
/// 没有门命中（真能投）时返回 false，且不弹任何提示。
bool castEntryBlocksStart(WidgetRef ref, {required CastEntryFacts facts}) {
  final verdict = castEntryVerdict(facts);
  if (verdict.available) return false;
  ref.read(castEntryBlockedGateProvider.notifier).write(verdict.kind!);
  ref.read(noticeTriggerProvider(NoticeId.castEntryBlocked).notifier).show();
  return true;
}
