import 'package:flutter/material.dart';

import 'gesture_feedback.dart';
import 'gestures.dart';

/// 音量/亮度调节横向滑条。
///
/// 单指垂直滑动（右半屏=音量、左半屏=亮度，向上为增，轴向分支）
/// 自轴向锁定起，屏幕正中显示本滑条：图标在条左端区分类型（亮度=太阳、
/// 音量=喇叭），无数字，填充长度按当前值（0..1）从左到右实时更新；
/// 手势结束（松手）即整体消失（不延迟淡出）。
///
/// 纯视觉内容：经 [GestureFeedbackOverlay] 的 IgnorePointer 宿主挂载，
/// 不拦截触摸、不与手势争 arena。
class LevelAdjustSlider extends StatelessWidget {
  const LevelAdjustSlider({super.key, required this.kind, required this.value});

  /// 调节对象（音量/亮度），决定左端图标。
  final LevelAdjustKind kind;

  /// 当前值（0..1），决定填充长度（从左到右）。
  final double value;

  /// 调节对象的图标与播报名：一处声明，左端图标与可播报读数的对象不会走散。
  static ({IconData icon, String name}) _displayOf(LevelAdjustKind kind) =>
      switch (kind) {
        LevelAdjustKind.volume => (icon: Icons.volume_up, name: '音量'),
        LevelAdjustKind.brightness => (icon: Icons.wb_sunny, name: '亮度'),
      };

  @override
  Widget build(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width * kLevelAdjustSliderWidthFraction;
    final display = _displayOf(kind);
    return Center(
      // 手势期间的读数用可播报区域表达：滑条本身无语义，
      // liveRegion 随值变化播报「音量 60%」这类文本。
      child: Semantics(
        key: const Key('level_adjust_announce'),
        container: true,
        liveRegion: true,
        label: '${display.name} ${(value.clamp(0.0, 1.0) * 100).round()}%',
        child: Container(
          key: const Key('level_adjust_slider'),
          width: width,
          padding: const EdgeInsets.symmetric(
            horizontal: kLevelAdjustPillPaddingH,
            vertical: kLevelAdjustPillPaddingV,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(kLevelAdjustPillRadius),
          ),
          child: Row(
            children: [
              Icon(display.icon, size: kLevelAdjustIconSize, color: Colors.white),
              const SizedBox(width: kLevelAdjustIconTrackGap),
              Expanded(
                child: SizedBox(
                  key: const Key('level_track'),
                  height: kLevelAdjustTrackHeight,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final fillWidth =
                          constraints.maxWidth * value.clamp(0.0, 1.0);
                      final trackRadius =
                          BorderRadius.circular(kLevelAdjustTrackHeight / 2);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // 底轨（半透明白）。
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: trackRadius,
                            ),
                          ),
                          // 已填充段（左对齐，随当前值实时伸缩）。
                          Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              key: const Key('level_fill'),
                              width: fillWidth,
                              height: double.infinity,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: trackRadius,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
