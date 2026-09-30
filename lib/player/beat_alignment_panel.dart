/// 面板「节拍对齐」组。
///
/// - **步长三档**：1 拍（按当前就绪网格拍距换算）/½拍/10ms + −/+ 按钮。
/// - **读数**：当前生效偏移（预览偏移优先，未调整时为已应用平移量），
///   拍 + 毫秒双显示；**重置** 归零（预览 = 0）。读数、标签与状态小字承载
///   语义，属语义档（随系统字号）：无覆写即吃环境缩放。
/// - **预览节奏**：±/重置 只写 [beatAlignPreviewOffsetProvider]（派生网格
///   实时跟随，轨道/动画/八拍点先动、已落盘线不动、不写盘）；**应用** 才
///   经应用命令（AnnotationEditor.submitBeatShift）提交；关闭气泡预览即
///   弃（会话侧 SpeedBubbleSession 关闭/切换时清空预览）。
/// - **门禁**：仅真实网格就绪可用；占位/异常置灰。
/// - **A 排版**：行1 步长分段 + 右侧「重置」；
///   行2 左侧「− 读数 ＋」（读数拍 + 毫秒两行、不居中）+ 右侧「应用」（正对
///   重置下方）；末行小字状态（未应用/已应用/已改·未应用）右对齐。读数双行
///   与步长换算语义沿用，仅重排呈现。
/// - **独立气泡**：本组由 [BeatAlignmentBubbleContent] 承载于**独立锚定
///   气泡**，锚同一入口链接、与节拍提示气泡互斥单开（会话单值）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../beat_track_state/beat_track_state.dart'
    show
        BeatTrackPhase,
        beatAlignPreviewOffsetProvider,
        beatGridProvider,
        beatTrackStateProvider;
import '../core/beat_grid.dart' show BeatGrid;
import 'annotation_editor.dart' show annotationEditorProvider;
import 'beat_bubble_theme.dart';

/// 步长档（会话级，默认 1 拍）。
enum BeatShiftStepUnit { oneBeat, halfBeat, tenMs }

/// 步长换算（纯函数）：1 拍按当前网格拍距、½拍为其半（毫秒取整）、
/// 10ms 恒定。
Duration beatShiftStep(BeatShiftStepUnit unit, BeatGrid grid) => switch (unit) {
      BeatShiftStepUnit.oneBeat => grid.beatsDuration(1),
      BeatShiftStepUnit.halfBeat => Duration(
          milliseconds: grid.beatsDuration(1).inMilliseconds ~/ 2,
        ),
      BeatShiftStepUnit.tenMs => const Duration(milliseconds: 10),
    };

/// 读数换算（纯函数）：偏移秒 → 拍数（按拍距）+ 毫秒。
class BeatShiftReadout {
  const BeatShiftReadout({required this.beats, required this.ms});

  /// 偏移折合拍数（按拍距换算，可为分数/负数）。
  final double beats;

  /// 偏移毫秒（四舍五入取整，可为负）。
  final int ms;
}

BeatShiftReadout beatShiftReadout(double offsetSeconds, Duration beatInterval) {
  final intervalMs = beatInterval.inMilliseconds;
  return BeatShiftReadout(
    beats: intervalMs <= 0 ? 0 : offsetSeconds * 1000 / intervalMs,
    ms: (offsetSeconds * 1000).round(),
  );
}

/// 步长档设置槽：会话级，默认 1 拍（不落盘）。
class BeatShiftStepUnitModel extends Notifier<BeatShiftStepUnit> {
  @override
  BeatShiftStepUnit build() => BeatShiftStepUnit.oneBeat;

  void set(BeatShiftStepUnit unit) {
    if (!ref.mounted || unit == state) return;
    state = unit;
  }
}

final beatShiftStepUnitProvider =
    NotifierProvider<BeatShiftStepUnitModel, BeatShiftStepUnit>(
      BeatShiftStepUnitModel.new,
    );

/// 读数格式化：符号 + 去尾零（拍）/ 整数（毫秒）。
String _formatBeats(double beats) =>
    '${beats < 0 ? '−' : '+'}'
    '${beats.abs().toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')} 拍';

String _formatMs(int ms) => '${ms < 0 ? '−' : '+'}${ms.abs()} ms';

/// 对齐应用状态小字（纯函数）：未应用 / 已应用 / 已改·未应用。
///
/// - **committed**：已应用平移量（grid.shift，落盘的派生网格平移量）。
/// - **preview**：未提交的预览偏移；与 committed 不同即视为「已改·未应用」，
///   相同或无预览时按 committed 是否非零判 已应用/未应用。
String beatAlignStatusLabel({
  required double committed,
  double? preview,
}) {
  final changed = preview != null && preview != committed;
  if (changed) return '已改·未应用';
  if (committed != 0.0) return '已应用';
  return '未应用';
}

/// 面板「节拍对齐」组（由 [BeatAlignmentBubbleContent] 承载于
/// 独立锚定气泡）。
class BeatAlignmentPanelGroup extends ConsumerWidget {
  const BeatAlignmentPanelGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(beatTrackStateProvider);
    final grid = track.grid;
    // 就绪判定用裸判（相位就绪 + 网格与拍点非空），不走共享谓词。
    final ready = track.phase == BeatTrackPhase.ready &&
        grid != null &&
        grid.beats.isNotEmpty;
    final preview = ref.watch(beatAlignPreviewOffsetProvider);
    final stepUnit = ref.watch(beatShiftStepUnitProvider);

    // 当前生效偏移：预览优先；未调整时为已应用平移量（读数即所见派生网格）。
    final effective = preview ?? (ready ? grid.shift : 0.0);
    final derivedGrid = ref.watch(beatGridProvider);
    final stepMs =
        ready ? beatShiftStep(stepUnit, derivedGrid).inMilliseconds : 0;
    final intervalMs = ready
        ? derivedGrid.beatsDuration(1).inMilliseconds
        : 0;
    final readout = beatShiftReadout(
      effective,
      Duration(milliseconds: intervalMs),
    );
    // 末行状态小字：已应用平移量（grid.shift）+ 预览偏移判定三态。
    final committed = ready ? grid.shift : 0.0;
    final status = beatAlignStatusLabel(
      committed: committed,
      preview: preview,
    );

    void adjust(int sign) {
      if (!ready) return;
      // 以毫秒整数量化累加，避免连续 ± 的浮点误差累积。
      ref
          .read(beatAlignPreviewOffsetProvider.notifier)
          .set(((effective * 1000).round() + sign * stepMs) / 1000);
    }

    return Column(
      key: const Key('beat_align_group'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 4),
          child: Text(
            '节拍对齐',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        // 行1：步长三档（宽自适应）+ 右侧「重置」。
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<BeatShiftStepUnit>(
                  key: const Key('beat_align_step'),
                  segments: const [
                    ButtonSegment(
                      value: BeatShiftStepUnit.oneBeat,
                      label: Text('1 拍'),
                    ),
                    ButtonSegment(
                      value: BeatShiftStepUnit.halfBeat,
                      label: Text('½拍'),
                    ),
                    ButtonSegment(
                      value: BeatShiftStepUnit.tenMs,
                      label: Text('10ms'),
                    ),
                  ],
                  selected: {stepUnit},
                  onSelectionChanged: ready
                      ? (selection) => ref
                          .read(beatShiftStepUnitProvider.notifier)
                          .set(selection.first)
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8),
                child: TextButton(
                  key: const Key('beat_align_reset'),
                  onPressed: ready
                      ? () => ref
                          .read(beatAlignPreviewOffsetProvider.notifier)
                          .set(0.0)
                      : null,
                  child: const Text('重置'),
                ),
              ),
            ],
          ),
        ),
        // 行2：左侧「− 读数（拍+毫秒两行）＋」，读数不居中、与分段控件
        // 起始对齐（行左内边距与行1 一致）；右侧「应用」正对重置下方。读数
        // 行窄宽自适应（FittedBox scaleDown），长值缩入可用宽、永不横向溢出。
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                key: const Key('beat_align_minus'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 20),
                tooltip: '减一步',
                onPressed: ready ? () => adjust(-1) : null,
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    key: const Key('beat_align_readout'),
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ready ? _formatBeats(readout.beats) : '— 拍',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        ready ? _formatMs(readout.ms) : '— ms',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const Key('beat_align_plus'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 20),
                tooltip: '加一步',
                onPressed: ready ? () => adjust(1) : null,
              ),
              const Spacer(),
              FilledButton(
                key: const Key('beat_align_apply'),
                onPressed: ready ? () => _apply(ref, effective) : null,
                child: const Text('应用'),
              ),
            ],
          ),
        ),
        // 末行：状态小字右对齐。
        Padding(
          padding: const EdgeInsets.only(right: 16, top: 2),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              status,
              key: const Key('beat_align_status'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }

  /// 应用：经应用命令提交（预览值写定、线整体平移、预览清空）。
  void _apply(WidgetRef ref, double effective) {
    unawaited(
      Future<void>.sync(
        () => ref.read(annotationEditorProvider).submitBeatShift(effective),
      ),
    );
  }
}

/// 节拍对齐气泡内容宽（**单一来源**）：固定列宽预算 **344**——A 排版几何
/// （步长行/读数行/重置/应用/状态小字的相对位置与右对齐）按该宽度定稿。
/// 节拍提示气泡的节拍矫正菜单列宽沿用本预算（见
/// `BeatPromptBubbleContent.correctionColWidth`）——两处列宽、气泡总宽与
/// 分隔线位置一律不动，改本值即两处同步。
const double beatAlignBubbleContentWidth = 344;

/// 「节拍对齐」独立锚定气泡内容：整组控件（步长三档 / ± 读数 / 重置 /
/// 应用 / 末行状态小字）。
///
/// - **容器**：与节拍提示气泡同一套壳（`SpeedBubbleMode.beatAlign`，共享
///   `speedBubbleSessionProvider` 单值互斥会话），锚同一入口链接。
/// - **关闭弃预览**：关闭本气泡或切走（含切回节拍提示气泡）即清空节拍对齐
///   预览偏移、不自动应用——会话侧统一处理。
/// - **固定内容宽**：[BeatAlignmentPanelGroup] 内部行用 `Expanded` 铺排，
///   须有确定宽（与既有列宽同值），气泡宽随之恒定、不随读数长短变化。
class BeatAlignmentBubbleContent extends StatelessWidget {
  const BeatAlignmentBubbleContent({super.key});

  /// 气泡内容宽（宿主按此放宽气泡 `maxWidth` 兜底）。
  static const double contentWidth = beatAlignBubbleContentWidth;

  @override
  Widget build(BuildContext context) {
    // 气泡底为深色浮层：沿用节拍气泡内容级暗色主题（否则亮色默认主题下
    // 文本/控件在深底上不可读）。
    return Theme(
      data: beatBubbleContentTheme,
      child: const SizedBox(
        key: Key('beat_align_bubble'),
        width: beatAlignBubbleContentWidth,
        child: BeatAlignmentPanelGroup(),
      ),
    );
  }
}
