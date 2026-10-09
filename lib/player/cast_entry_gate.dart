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
/// **事实类型就是共用判定表吃的那一份**（票 #44）：装配点直出 [ToolFacts]，
/// 不再有「投屏专用事实 → 判定表事实」的搬运层；置灰观感与可点性由顶栏
/// 读同**一次**判定求值给出（`play_tool_table.dart` 的 `playToolAvailability`），
/// 本文件不再为置灰另算一遍。
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

/// 五条门的**唯一装配点**：入参是这支舞的视频副本路径（副本丢失门的输入），
/// 其余四条各读既有读面；出参就是共用判定表吃的那一份事实（[ToolFacts]），
/// 只有投屏那五位被点亮——其余入口一位不受影响（命中集 = 声明 ∩ 事实）。
///
/// 加一条门 = 本表补一行 + `kPlayToolCast.gates` 补一声明 + [ToolGateKind]、
/// [ToolFacts] 与判定表的「按门取事实」各补一位（漏一处测试红或编译报错）。
final castEntryFactsProvider = Provider.family<ToolFacts, String>((
  ref,
  videoFilePath,
) {
  final session = ref.watch(playerSessionProvider);
  return ToolFacts(
    castCopyMissing: !ref
        .watch(videoCopyPresenceProvider)
        .exists(videoFilePath),
    castAvSyncCalibrating: ref.watch(avSyncCalibrationSessionProvider).active,
    // 录制相位与录制期播放接管域在同一次相位同步里一起写（见
    // `compare_recording_clips.dart` 的 `_sync`），两者同义。
    castRecording:
        ref.watch(compareRecordingPhaseProvider) != CompareRecordingPhase.idle,
    castCompareOrFraming:
        session.isCompare || sessionModeSurfacesOf(session.mode).framingActive,
    castRendering: ref.watch(castRenderInProgressProvider),
  );
});

/// 投屏入口此刻的判定：available 为假 = 置灰（tappable 为真 = 按下去只解释
/// 原因）。与顶栏槽声明同源，不另判一套。
ToolSlotVerdict castEntryVerdict(ToolFacts facts) =>
    evaluateDeclaredGates(kPlayToolCast.gates.toSet(), facts);

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
bool castEntryBlocksStart(WidgetRef ref, {required ToolFacts facts}) {
  final verdict = castEntryVerdict(facts);
  if (verdict.available) return false;
  ref.read(castEntryBlockedGateProvider.notifier).write(verdict.kind!);
  ref.read(noticeTriggerProvider(NoticeId.castEntryBlocked).notifier).show();
  return true;
}
