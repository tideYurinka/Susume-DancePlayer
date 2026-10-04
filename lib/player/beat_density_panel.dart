/// 「节拍倍频」独立锚定气泡：节拍矫正菜单
/// 列第三条目的控件本体——五档 2 的幂（×¼/×½/原样/×2/×4），形状复用节拍
/// 对齐独立气泡那套。
///
/// - **读数**：当前档（预览档优先，未调整时为已落盘档，如「×2」）。
/// - **预览节奏**：「快一倍/慢一半/重置」只写 `beatDensityPreviewProvider`
///   （派生网格实时跟随，节拍轨刻度先动、不写盘）；**确认** 才经应用命令
///   （AnnotationEditor.submitBeatDensity）落盘 = 一次可撤销的标注编辑，
///   落盘后关闭本气泡（无净变化时同样关闭）；**取消** 丢弃预览并关气泡。
///   关气泡/切走即弃未应用预览（不自动应用，气泡会话侧统一处理，与节拍
///   对齐同一组语义）。
/// - **端点置灰**：×4 时「快一倍」置灰、×¼ 时「慢一半」置灰；「重置」
///   回到原样（预览 = ×1）。
/// - **置灰门**：真实拍点可用（占位/异常置灰，与八拍矫正
///   同族；不学节拍对齐的「恒可点」）。
/// - **固定内容宽**：与节拍对齐气泡同值（344，形状复用），气泡宽恒定、
///   不随读数变化。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'beat_alignment_panel.dart' show beatAlignBubbleContentWidth;
import 'beat_bubble_theme.dart';
import '../core/beat_grid.dart' show BeatGridReads;
import 'annotation_editor.dart' show annotationEditorProvider;
import '../beat_track_state/beat_track_state.dart'
    show beatDensityPreviewProvider, beatGridProvider, beatTrackStateProvider;
import '../player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'speed_bubble.dart' show speedBubbleSessionProvider;

/// 节拍侧「网格未就绪」两态的使用提示句（唯一取辞处；节拍提示面板的
/// 「节拍倍频」条目与本气泡入口同一组句子，改辞只改这里）。
const String kBeatGridPlaceholderHint = '节拍分析完成后可用';
const String kBeatGridErrorHint = '节拍识别失败，暂不可用';

/// 五档档位表（「加一档只改一处」）：升序 2 的幂。
const List<double> beatDensityLevels = [0.25, 0.5, 1, 2, 4];

/// 档位读数（纯函数）：×1 读「原样」，其余读「×n」。
String beatDensityLabel(double density) => switch (density) {
  0.25 => '×¼',
  0.5 => '×½',
  1 => '原样',
  2 => '×2',
  4 => '×4',
  _ => '×$density',
};

/// 节拍倍频可用谓词：**真实拍点可用**（占位/
/// 异常置灰）——派生网格就绪即可调倍频，无强拍也合法（识别退化按首拍
/// 定相回落）；比八拍矫正的「还须有强拍」门更宽。
final beatDensityAvailableProvider = Provider<bool>((ref) {
  return ref.watch(beatGridProvider).hasRealBeats;
});

/// 「节拍倍频」气泡内容：读数 + 快一倍/慢一半/重置 + 应用/取消。
class BeatDensityPanelGroup extends ConsumerWidget {
  const BeatDensityPanelGroup({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(beatTrackStateProvider);
    final preview = ref.watch(beatDensityPreviewProvider);
    // 当前生效档：预览优先；未调整时为已落盘档（读数即所见派生网格）。
    // 可用门读单一来源谓词（与入口同门，勿另手写就绪判定）。
    final ready = ref.watch(beatDensityAvailableProvider);
    final effective = preview ?? (ready ? track.grid?.density ?? 1.0 : 1.0);
    final levelIndex = beatDensityLevels.indexOf(effective);

    void step(int sign) {
      if (!ready || levelIndex < 0) return;
      ref
          .read(beatDensityPreviewProvider.notifier)
          .set(beatDensityLevels[levelIndex + sign]);
    }

    return Column(
      key: const Key('beat_density_group'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, bottom: 4),
          child: Text(
            '节拍倍频',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        // 行1：读数居左 + 「重置」右侧。
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 8),
          child: Row(
            children: [
              SizedBox(
                key: const Key('beat_density_readout'),
                child: Text(
                  ready ? beatDensityLabel(effective) : '—',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                key: const Key('beat_density_reset'),
                onPressed: ready
                    ? () =>
                          ref.read(beatDensityPreviewProvider.notifier).set(1.0)
                    : null,
                style: _bubbleButtonStyle,
                child: const Text('重置'),
              ),
            ],
          ),
        ),
        // 行2：「快一倍」「慢一半」+ 取消/确认（确认正对重置下方）。
        // 五个控件同挂放大档（行高与边距放宽）：
        // 左右两组各成一个 Wrap 子项、组间 spaceBetween——零缩放时即单排
        // （Spacer 让位）布局；大字号（1.6×）放不下时右组换行兜底，
        // 不横向溢出。
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    key: const Key('beat_density_faster'),
                    onPressed:
                        ready &&
                            levelIndex >= 0 &&
                            levelIndex < beatDensityLevels.length - 1
                        ? () => step(1)
                        : null,
                    style: _bubbleButtonStyle,
                    child: const Text('快一倍'),
                  ),
                  OutlinedButton(
                    key: const Key('beat_density_slower'),
                    onPressed: ready && levelIndex > 0 ? () => step(-1) : null,
                    style: _bubbleButtonStyle,
                    child: const Text('慢一半'),
                  ),
                ],
              ),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    key: const Key('beat_density_cancel'),
                    onPressed: ready ? () => _cancel(ref) : null,
                    style: _bubbleButtonStyle,
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    key: const Key('beat_density_apply'),
                    onPressed: ready ? () => _apply(ref, effective) : null,
                    style: _bubbleButtonStyle,
                    child: const Text('确认'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // 行3：「对特定段落设置倍频」入口：
        // 按下即关气泡 + **落一个进入段内倍频待命态的待办**（经播放会话
        // 模式唯一进入路径，不在发起方另写模式值；宿主听待办槽完成编排后
        // 经唯一提交入口提交）。置灰门 = 真实拍点可用（占位/异常置灰），
        // 与本气泡整体同门；置灰时按既有使用提示句式说明原因。
        Padding(
          padding: const EdgeInsets.only(
            left: 12,
            right: 8,
            top: 12,
            bottom: 8,
          ),
          child: Row(
            children: [
              OutlinedButton(
                key: const Key('beat_density_segment_entry'),
                onPressed: ready
                    ? () {
                        ref.read(speedBubbleSessionProvider.notifier).close();
                        ref
                            .read(playerSessionProvider.notifier)
                            .requestEntry(
                              PlayerSessionMode.segmentDensityStandby,
                            );
                      }
                    : null,
                style: _bubbleButtonStyle,
                child: const Text('对特定段落设置倍频'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _entryHint(ref, ready),
                  key: const Key('beat_density_segment_entry_hint'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 入口的使用提示句式：不可用两态各说明
  /// 原因，取辞与节拍提示面板「节拍倍频」条目同一组句子。
  String _entryHint(WidgetRef ref, bool ready) {
    if (ready) return '在轨道上点选要调整的段';
    return ref.watch(beatGridProvider).isSecondsFallback
        ? kBeatGridErrorHint
        : kBeatGridPlaceholderHint;
  }

  /// 取消：丢弃未应用预览并关气泡（不自动应用）。
  void _cancel(WidgetRef ref) {
    ref.read(beatDensityPreviewProvider.notifier).set(null);
    ref.read(speedBubbleSessionProvider.notifier).close();
  }

  /// 确认：经应用命令提交（倍频写定 + 锚点就地烘焙 = 一次标注编辑），
  /// 落盘后关闭气泡——**无净变化（no-op）时同样关闭**：用户按下确认即表示
  /// 结束本次操作。未应用预览随关闭作废。
  void _apply(WidgetRef ref, double effective) {
    unawaited(
      Future<void>.sync(() {
        final outcome = ref
            .read(annotationEditorProvider)
            .submitBeatDensity(effective);
        if (outcome.applied) {
          ref.read(beatDensityPreviewProvider.notifier).set(null);
        }
        ref.read(speedBubbleSessionProvider.notifier).close();
      }),
    );
  }
}

/// 「节拍倍频」气泡行控件档：放大触控目标（行高 [_bubbleButtonHeight]、
/// 横向边距放宽、字号 14）——五个控件同挂本档，含 textScale 1.3 的最宽行。
const double _bubbleButtonHeight = 42;

const ButtonStyle _bubbleButtonStyle = ButtonStyle(
  // 气泡内容主题默认 VisualDensity.compact（-2），会再压掉 8dp——显式回到
  // standard，行高才真的等于 [_bubbleButtonHeight]。
  visualDensity: VisualDensity.standard,
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  minimumSize: WidgetStatePropertyAll(Size(0, _bubbleButtonHeight)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 14)),
);

/// 「节拍倍频」气泡内容宽（形状复用节拍对齐气泡）：单源引用
/// 对齐气泡的内容宽（[beatAlignBubbleContentWidth] 344），改对齐即同步。
const double beatDensityBubbleContentWidth = beatAlignBubbleContentWidth;

/// 「节拍倍频」独立锚定气泡内容：容器与节拍对齐气泡同一套壳
/// （`SpeedBubbleMode.beatDensity`，共享 `speedBubbleSessionProvider` 单值
/// 互斥会话），锚同一入口链接。
class BeatDensityBubbleContent extends StatelessWidget {
  const BeatDensityBubbleContent({super.key});

  /// 气泡内容宽（宿主按此放宽气泡 `maxWidth` 兜底）。
  static const double contentWidth = beatDensityBubbleContentWidth;

  @override
  Widget build(BuildContext context) {
    // 气泡底为深色浮层：沿用节拍气泡内容级暗色主题。
    return Theme(
      data: beatBubbleContentTheme,
      child: const SizedBox(
        key: Key('beat_density_bubble'),
        width: beatDensityBubbleContentWidth,
        child: BeatDensityPanelGroup(),
      ),
    );
  }
}
