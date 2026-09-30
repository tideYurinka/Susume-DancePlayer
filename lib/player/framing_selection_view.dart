/// 取景应用件：按**取景选区** + 本态容器几何
/// 派生 contain 显示变换，并在取景调节态内叠压暗与选框。单画面与对比源侧两条
/// 路径共用这一处渲染数学——可用区是否贴底、画面宽高比随调用点传入。
///
/// - 取景态（[framingActive]）：画面按**未调过的整帧**显示（选区为 null 即
///   基线），只叠覆盖层，便于对着整帧重圈；
/// - 其余态：选区内容按 contain 装进可用区（未调过 = 整帧 contain）；
/// - 画面宽高比未知：纯件安静降级为无变换（画面即容器）。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/framing_selection.dart'
    show
        FramingSelectionGeometry,
        framingSelectionRectOnPicture,
        framingSelectionTransform;
import 'framing_overlay.dart' show FramingSelectionOverlay;
import 'framing_session_state.dart' show framingStateProvider;
import 'note_sticker_layout.dart' show videoContentRectInBox;

/// 取景应用件：读取源画面选区，按可用区几何施加显示变换并叠覆盖层。
///
/// 施加选区时把画面**裁到选区内容那一块**（等价于「选区里那一块重新导入」）：
/// 选区内容按 contain 装进可用区，选区之外不露出相邻源画面（含贴底盒高封顶
/// 后的左右黑边）。
class FramingSelectionView extends ConsumerWidget {
  const FramingSelectionView({
    super.key,
    required this.aspectRatio,
    required this.child,
    this.sticksToBottom = false,
    this.framingActive = false,
  });

  /// 画面宽高比（null = 未知，画面即容器）。
  final double? aspectRatio;

  final Widget child;

  /// 可用区贴底分支（竖屏编辑态）：纵向把选区下缘对到可用区下缘。
  final bool sticksToBottom;

  /// 取景调节态：画面按未调过的整帧显示并叠覆盖层。
  final bool framingActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(
      framingStateProvider.select((s) => s.source),
    );
    // 取景调节态内画面按整帧显示，故变换与裁切都按未调过。
    final applied = framingActive ? null : selection;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stage = constraints.biggest;
        final picture = videoContentRectInBox(
          box: stage,
          aspectRatio: aspectRatio,
        );
        final t = framingSelectionTransform(
          selection: applied,
          geometry: FramingSelectionGeometry(
            availableWidth: stage.width,
            availableHeight: stage.height,
            aspectRatio: aspectRatio,
            sticksToBottom: sticksToBottom,
          ),
        );
        final translate = Offset(t.translateX, t.translateY);
        final content = applied == null
            ? null
            : framingSelectionRectOnPicture(
                selection: applied,
                pictureLeft: picture.left,
                pictureTop: picture.top,
                pictureWidth: picture.width,
                pictureHeight: picture.height,
              );
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                child: Transform.translate(
                  offset: translate,
                  child: Transform.scale(
                    scale: t.scale,
                    child: content == null
                        ? child
                        : ClipRect(
                            clipper: _FramingContentClipper(
                              Rect.fromLTRB(
                                content.left,
                                content.top,
                                content.right,
                                content.bottom,
                              ),
                            ),
                            child: child,
                          ),
                  ),
                ),
              ),
              if (framingActive)
                FramingSelectionOverlay(
                  selection: selection,
                  // 取景态的变换是纯平移（scale 1）：覆盖层的画面矩形随它
                  // 落到画面实际显示的位置。
                  pictureRect: picture.shift(translate),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 把画面裁到选区内容矩形（可用区局部坐标）——选区之外不画相邻源画面。
class _FramingContentClipper extends CustomClipper<Rect> {
  const _FramingContentClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(_FramingContentClipper oldClipper) =>
      oldClipper.rect != rect;
}
