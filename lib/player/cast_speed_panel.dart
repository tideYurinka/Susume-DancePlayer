/// 投屏**倍速切换**面板：投屏态顶栏首枚那枚工具点开的轻面板——列这次备的
/// 三档各自的状态（正在播 / 可切 / 准备中 xx% / 等着渲 / 没渲出来），点一枚
/// **已渲好**的档即让接收端换一个文件播。
///
/// ## 它回答什么
///
/// - **现在播的是哪一档**：正在播那一档标「正在播」；
/// - **还有哪些档能切**：已渲好的标「可切」、可点；**未渲好的显示各自的准备
///   进度且不可点**（后台还在渲，见 `cast_run.dart` 的先投后渲）；
/// - **换档要等**：过程态写在面板里（`cast_speed_switching`），并有一句话
///   说明「起播等待与跳转精度不由我们决定」——这是这条路的固有代价，界面
///   不把「切准了」写成承诺。
///
/// ## 边界
///
/// 本件只构控件：换档动作（换文件、按比例换算位置、失败回退旧文件）全在投屏
/// 运行域（[CastRunModel.switchTier]）；本件读它的状态、点它的动作，不碰
/// 会话、不碰递出通道、不算位置。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_render_request.dart' show CastSpeedTier;
import '../cast/cast_speed_tier.dart';
import 'cast_run.dart'
    show CastRunState, CastTierRender, CastTierRenderStatus, castRunProvider;
import 'visual_tokens.dart' show kPlayerSkinColor;

/// 面板标题。
const String kCastSpeedTitle = '投屏倍速';

/// 换档过程态那一句（换文件 + 换算位置 + 等接收端起播）。
const String kCastSpeedSwitchingText = '正在换档，等电视起播…';

/// 那条固有代价的实话：起播等待与跳转精度不由我们决定。
const String kCastSpeedWaitText =
    '换档就是让电视换一个文件播：起播要等一会儿（通常 1–3 秒），'
    '跳到哪里也由电视决定，切得不准是正常的';

/// 各档状态的文案。
const String kCastSpeedActiveText = '正在播';
const String kCastSpeedReadyText = '可切';
const String kCastSpeedQueuedText = '等着渲';
const String kCastSpeedFailedText = '这一档没渲出来';

/// 一档在面板里的定位 key。
Key castSpeedOptionKey(CastSpeedTier tier) =>
    Key('cast_speed_option_${tier.name}');

/// 一档状态文字的定位 key。
Key castSpeedOptionStateKey(CastSpeedTier tier) =>
    Key('cast_speed_state_${tier.name}');

/// 打开投屏倍速切换面板（宿主是投屏态顶栏那枚工具）。
Future<void> showCastSpeedPanel(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const CastSpeedPanel());

/// 投屏倍速切换面板。
class CastSpeedPanel extends ConsumerWidget {
  const CastSpeedPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cast = ref.watch(castRunProvider);
    final busy = cast.switching;
    return Dialog(
      key: const Key('cast_speed_panel'),
      backgroundColor: kPlayerSkinColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                kCastSpeedTitle,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (cast.tiers.isEmpty)
                _line(castSpeedTierLabel(cast.activeTier), kCastSpeedActiveText)
              else
                for (final render in cast.tiers)
                  _tierRow(context, ref, cast, render, busy: busy),
              if (busy) ...[
                const SizedBox(height: 6),
                const LinearProgressIndicator(key: Key('cast_speed_switching')),
                const SizedBox(height: 4),
                const Text(
                  kCastSpeedSwitchingText,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                kCastSpeedWaitText,
                key: Key('cast_speed_wait_note'),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('cast_speed_close'),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('收起'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 一档：标签 + 状态（+ 进度条）+ 可点性。
  ///
  /// 可点性只认「已渲好、不是当前档、也不在换档过程中」——未渲好的档在这里
  /// **结构性不可点**（不是靠文案劝阻）。
  Widget _tierRow(
    BuildContext context,
    WidgetRef ref,
    CastRunState cast,
    CastTierRender render, {
    required bool busy,
  }) {
    final tier = render.tier;
    final active = tier == cast.activeTier;
    final tappable = cast.canSwitchTo(tier);
    return InkWell(
      key: castSpeedOptionKey(tier),
      onTap: tappable ? () => unawaited(_switch(context, ref, tier)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              child: Text(
                castSpeedTierLabel(tier),
                style: TextStyle(
                  color: tappable || active ? Colors.white : Colors.white54,
                  fontSize: 15,
                ),
              ),
            ),
            Expanded(
              child: render.status == CastTierRenderStatus.rendering
                  ? LinearProgressIndicator(value: render.fraction)
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 8),
            Text(
              _stateTextOf(render, active: active),
              key: castSpeedOptionStateKey(tier),
              style: TextStyle(
                color: tappable ? Colors.white : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 一档的状态文字（进度那些换成百分比，未渲好一律不可点）。
  String _stateTextOf(CastTierRender render, {required bool active}) {
    if (active) return kCastSpeedActiveText;
    switch (render.status) {
      case CastTierRenderStatus.ready:
        return kCastSpeedReadyText;
      case CastTierRenderStatus.rendering:
        final fraction = render.fraction;
        if (fraction == null) return '准备中…';
        return '准备中 ${(fraction * 100).round()}%';
      case CastTierRenderStatus.queued:
        return kCastSpeedQueuedText;
      case CastTierRenderStatus.failed:
        return kCastSpeedFailedText;
    }
  }

  /// 点一枚可切的档：换档动作本体在投屏运行域；面板收起，过程态与结果由
  /// 投屏态那边呈现（失败经短暂提示，画面不被面板挡住）。
  Future<void> _switch(
    BuildContext context,
    WidgetRef ref,
    CastSpeedTier tier,
  ) async {
    final navigator = Navigator.of(context);
    final switching = ref.read(castRunProvider.notifier).switchTier(tier);
    // 过程态先留在面板里看得见（换文件 + 换算位置 + 等起播），完成后收起。
    await switching;
    if (navigator.mounted) navigator.pop();
  }

  Widget _line(String label, String state) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 15)),
        const SizedBox(width: 8),
        Text(
          state,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    ),
  );
}
