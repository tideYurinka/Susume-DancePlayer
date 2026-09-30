import 'package:flutter/material.dart';

import '../core/text_extent.dart';

/// 顶栏标题匀速循环滚动速度（px/s）。
const double kTitleAutoScrollSpeed = 30;

/// 两圈衔接空隙宽度（px）：文字末尾接下一圈开头时留出的间隔。
const double kTitleScrollGap = 32;

/// 左右边缘淡出遮罩宽度（px）。
const double kTitleScrollFadeWidth = 16;

/// 顶栏标题自动滚动：文本宽度超出可用空间时匀速向左循环滚动
/// （文字末尾接下一圈开头），左右边缘淡出；未溢出时静止单份显示。
/// 文本/可用宽度变化即时重算（经 LayoutBuilder + 文本量测）。
class AutoScrollTitle extends StatefulWidget {
  const AutoScrollTitle({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<AutoScrollTitle> createState() => _AutoScrollTitleState();
}

class _AutoScrollTitleState extends State<AutoScrollTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  bool _scrolling = false;
  double _cycle = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 测量结果的动画同步：不在 build 期间启停动画（帧末统一执行）。
  void _sync(bool overflow, double cycle) {
    if (!overflow) {
      if (_scrolling) {
        _controller.stop();
        _scrolling = false;
      }
      return;
    }
    // 容差比较：字形重排的亚像素抖动不重设时长。
    if ((cycle - _cycle).abs() > 0.5) {
      _cycle = cycle;
      _controller.duration = Duration(
        milliseconds: (cycle * 1000 / kTitleAutoScrollSpeed).round(),
      );
    }
    if (!_scrolling) {
      _scrolling = true;
      _controller
        ..value = 0
        ..repeat();
    }
  }

  void _scheduleSync(bool overflow, double cycle) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sync(overflow, cycle);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 语义档（随系统字号）：标题承载语义，量测与渲染同源——量测吃调用处
        // [MediaQuery.textScalerOf]，渲染的 [Text] 随环境缩放取同一值。
        final textSize = measureTextExtent(
          widget.text,
          widget.style,
          direction: Directionality.of(context),
          scaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        );
        final textWidth = textSize.width;
        final overflow =
            constraints.maxWidth.isFinite && textWidth > constraints.maxWidth;
        _scheduleSync(overflow, textWidth + kTitleScrollGap);
        if (!overflow) {
          return Text(widget.text, maxLines: 1, style: widget.style);
        }
        return ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) {
              final fade = kTitleScrollFadeWidth.clamp(0.0, bounds.width / 2);
              return LinearGradient(
                colors: const [
                  Colors.transparent,
                  Colors.white,
                  Colors.white,
                  Colors.transparent,
                ],
                stops: [
                  0,
                  fade / bounds.width,
                  1 - fade / bounds.width,
                  1,
                ],
              ).createShader(Offset.zero & bounds.size);
            },
            child: SizedBox(
              height: textSize.height,
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final offset = -_controller.value * _cycle;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.text, maxLines: 1, style: widget.style),
                          const SizedBox(width: kTitleScrollGap),
                          Text(widget.text, maxLines: 1, style: widget.style),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
