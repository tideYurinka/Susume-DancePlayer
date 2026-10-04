import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'editor_skeleton.dart' show cancelZoneRadius;
import '../core/frame_time.dart';
import 'gestures.dart';
import 'visual_tokens.dart';

/// 进度拖动取消区提示文案：scrubbing 期间迷你进度条下方常显的
/// 说明文字（手指进入左上角取消区 → 换为 [kScrubCancelArmedText] 警示）。
const String kScrubCancelHintText = '拖到画面左上角松开可取消';

/// 进度拖动取消区「待取消」提示：手指进入画面左上角取消区时，浮层
/// 换为警示色并显示本文案（在此松开即取消本次进度调整）。
const String kScrubCancelArmedText = '松开取消';

/// 取消区标记弧内小字。
const String kScrubCancelMarkText = '取消';

/// 取消区标记：以画面矩形左上角为圆心、
/// [cancelZoneRadius] 为半径的四分之一圆弧（2dp 细线）与弧内居中
/// [kScrubCancelMarkText]；常态 white70，待取消转琥珀并给弧内铺低透琥珀。
/// 纯视觉：与气泡同属 IgnorePointer 浮层宿主，不拦截触摸。
class ScrubCancelMark extends StatelessWidget {
  const ScrubCancelMark({
    super.key,
    required this.pictureRect,
    required this.armed,
  });

  /// 画面矩形（屏幕坐标）：圆心取其左上角，半径经 [cancelZoneRadius] 与
  /// 判定域取同一个值。
  final Rect pictureRect;

  /// 是否处于待取消（弧与文字转琥珀、弧内铺低透琥珀）。
  final bool armed;

  @override
  Widget build(BuildContext context) {
    final r = cancelZoneRadius(pictureRect);
    final color = armed ? kHighlightAmber : Colors.white70;
    // 弧与「取消」小字是纯装饰提示（真正的取消说明由 ScrubIndicator 的
    // 提示文案承担）：整块不进无障碍树，读屏不会把它读成一个孤立控件。
    return ExcludeSemantics(
      child: SizedBox(
        width: r,
        height: r,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _CancelArcPainter(
                  radius: r,
                  color: color,
                  armed: armed,
                ),
              ),
            ),
            Center(
              child: Text(
                kScrubCancelMarkText,
                style: TextStyle(color: color, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 四分之一圆弧画笔：弧只覆盖第一象限（自圆心
/// 右侧水平起、顺时针 90° 到正下方），不越出画面；armed 时先铺低透琥珀扇内底。
class _CancelArcPainter extends CustomPainter {
  const _CancelArcPainter({
    required this.radius,
    required this.color,
    required this.armed,
  });

  final double radius;
  final Color color;
  final bool armed;

  @override
  void paint(Canvas canvas, Size size) {
    final arcRect = Rect.fromCircle(
      center: Offset.zero,
      // 半径内缩 1px：保证 2dp 描边整体落在标记盒内、不沿盒边被裁。
      radius: radius - 1,
    );
    if (armed) {
      final fill = Path()
        ..moveTo(0, 0)
        ..arcTo(arcRect, 0, math.pi / 2, true)
        ..close();
      canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.13));
    }
    canvas.drawArc(
      arcRect,
      0,
      math.pi / 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_CancelArcPainter old) =>
      old.radius != radius || old.color != color || old.armed != armed;
}

/// scrub 指示浮层：进度拖动（scrubbing）
/// 期间屏幕正中的迷你进度条 + 时间文本。
///
/// - 屏幕正中水平迷你进度条（约屏宽 60%，见 [kScrubIndicatorWidthFraction]），
///   条上方时间文本「目标/总长」（[formatFrameTime]，mm:ss:ff 帧号自 0，
///   帧率源 = 引擎可暴露的 demux-fps，缺省 30fps 常量）；
/// - 游标（填充段）占条比例 = **[target] / [total]**，即播放器页按
///   `[0, total]` 钳制后的目标位置——不是引擎实际 position（串行 seek 期间
///   会滞后）；比例按 0.1s 粒度网格计算（比例侧保留该粒度；文本按帧号
///   粒度，二者不互为约束）；
/// - [total] 未知（未解析/打开失败，引擎 `PlaybackEngine.duration` 为
///   null）时不崩溃：只显示目标时间，不显示比例条与总长；
/// - 条下方常显说明文字「拖到画面左上角松开可取消」（指向画面）；手指
///   进入画面左上角取消区（[armed]）时换为警示色「松开取消」（条与时间
///   同转），离开恢复原样；
/// - 纯视觉：经 `GestureFeedbackOverlay`（IgnorePointer 浮层宿主）挂载，
///   不拦截触摸、拖动 seek 持续生效。
///
/// 本部件不决定显隐：由浮层宿主按反馈相位（scrubbing）叠加/移除。
class ScrubIndicator extends StatelessWidget {
  const ScrubIndicator({
    super.key,
    required this.target,
    this.total,
    this.armed = false,
    this.showCancelHint = true,
    this.fps = kDefaultVideoFps,
  });

  /// 显示的目标位置（调用方保证已按 `[0, total]` 钳制）。
  final Duration target;

  /// 视频总长；未知（未解析/打开失败）时为 null——只显示目标时间。
  final Duration? total;

  /// 是否处于进度拖动「取消区」待取消：手指焦点已进入画面左上角
  /// 取消区 → 条与时间转警示色、条下方文案换为「松开取消」。
  final bool armed;

  /// 是否显示条下方的取消区提示文案（默认显示，全屏进度拖动语义）。
  /// 编辑态非轨道区微调无取消角 → 传 false，不显示提示。
  final bool showCancelHint;

  /// 帧号换算帧率：调用侧传引擎可暴露的 demux-fps（取不到传
  /// 缺省 [kDefaultVideoFps]）。
  final double fps;

  @override
  Widget build(BuildContext context) {
    final total = this.total;
    // 游标比例 = 目标 / 总长（0.1s 粒度，向下取整钳制）；无总长可比 →
    // 不显示比例（null 分支隐藏进度条与总长时间）。
    final targetTenths = target.inMilliseconds ~/ 100;
    final totalTenths = (total?.inMilliseconds ?? 0) ~/ 100;
    final ratio = totalTenths > 0
        ? (targetTenths / totalTenths).clamp(0.0, 1.0)
        : null;
    final timeText = total == null
        ? formatFrameTime(target, fps: fps)
        : '${formatFrameTime(target, fps: fps)} / '
              '${formatFrameTime(total, fps: fps)}';
    final barWidth =
        MediaQuery.sizeOf(context).width * kScrubIndicatorWidthFraction;
    // 进入取消区 → 警示色（条 + 时间同转）并显示「松开取消」。
    final accent = armed ? kHighlightAmber : Colors.white;

    return Center(
      key: const Key('scrub_indicator'),
      child: Container(
        key: const Key('scrub_indicator_bubble'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeText,
              softWrap: false,
              maxLines: 1,
              style: TextStyle(
                color: accent,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                // 视频画面明暗不定：阴影保证文字可读。
                shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
              ),
            ),
            if (ratio != null) ...[
              const SizedBox(height: kScrubIndicatorTextGap),
              SizedBox(
                key: const Key('scrub_indicator_bar'),
                width: barWidth,
                height: kScrubIndicatorBarHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                    kScrubIndicatorBarHeight / 2,
                  ),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: ColoredBox(color: Color(0x59FFFFFF)), // 轨道
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: barWidth * ratio,
                        child: ColoredBox(
                          key: const Key('scrub_indicator_fill'),
                          color: accent, // 游标填充（取消区待取消转警示色）
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // 迷你进度条下方说明文字（scrubbing 期间全程显示、结束即隐）；
            // 进入取消区换为警示色「松开取消」。无取消角场景（编辑态非轨道
            // 微调）不显示。
            if (showCancelHint) ...[
              const SizedBox(height: kScrubIndicatorTextGap),
              Text(
                armed ? kScrubCancelArmedText : kScrubCancelHintText,
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: armed ? kHighlightAmber : Colors.white70,
                  fontSize: 12,
                  fontWeight: armed ? FontWeight.w700 : FontWeight.w400,
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
