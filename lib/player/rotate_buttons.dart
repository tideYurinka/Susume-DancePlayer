part of 'control_layer.dart';

/// 横竖屏转屏钮：两枚钮的稳定 key、命中矩形外扩式子与视觉件。视觉矩形
/// （屏幕坐标）由 editor_skeleton.dart 给出。

/// 横屏编辑面「转为竖屏」矩形钮：纯文字、
/// 动作写清（62 × 32dp）。锚由**系统栏内缩**推出（见
/// [landscapeToPortraitButtonRect]）：左 = 左内缩 + 间隙，与返回键、顶栏同一条
/// 内缩线；压在画面上是可接受代价，只避开数拍数字默认位与轨道带。渲染在控制
/// 层 SafeArea 之外的全屏 Stack 上，否则会被内缩再挪一次、且必须避开中带那个
/// 会把钮裁掉下半截的低矮 Stack。
const Key kLandscapeToPortraitButtonKey = Key('landscape_to_portrait_button');

/// 横屏「转为竖屏」钮的**命中矩形** key：视觉
/// 矩形透明外扩后的可点域，见 [landscapeToPortraitButtonHitRect]。
const Key kLandscapeToPortraitButtonHitKey = Key(
  'landscape_to_portrait_button_hit',
);

/// 竖屏编辑面转屏钮（动作「转为横屏」，无字图标）的稳定 key 与字形尺寸；
/// 视觉圆底与内缩见 [portraitRotateButtonRect]。
const Key kPortraitRotateButtonKey = Key('portrait_rotate_button');

/// 竖屏转屏钮**命中矩形** key：视觉圆底透明外扩
/// 到命中下限后的可点域。
const Key kPortraitRotateButtonHitKey = Key('portrait_rotate_button_hit');
const double kRotateButtonGlyphSize = 24;

/// 横屏「转为竖屏」钮的命中矩形（屏幕坐标）：视觉
/// 矩形 [landscapeToPortraitButtonRect] 按命中下限外扩。该钮上与顶栏、下与
/// 轨道带各只隔 4dp 间隙，纵向容纳不下 48dp——这是邻接密集区，按
/// [kHitTargetDenseMinSize] 兜底（代价：上探与返回键命中域底缘重叠约 2dp；
/// 下探止于轨道带上缘不越界）。外扩规则：向下探到 [trackBandTop] 为止，其余
/// 向上补足；渲染点与测试断言共用本式，不各算一次。
Rect landscapeToPortraitButtonHitRect({
  required double systemTopInset,
  required double systemLeftInset,
  required double trackBandTop,
}) => landscapeToPortraitButtonHitRectOf(
  visual: landscapeToPortraitButtonRect(
    systemTopInset: systemTopInset,
    systemLeftInset: systemLeftInset,
    trackBandTop: trackBandTop,
  ),
  trackBandTop: trackBandTop,
);

/// [landscapeToPortraitButtonHitRect] 的视觉矩形入口：渲染点已持有视觉矩形
/// 时从这里走，避免同参把 [landscapeToPortraitButtonRect] 算两遍。
Rect landscapeToPortraitButtonHitRectOf({
  required Rect visual,
  required double trackBandTop,
}) {
  final totalGrow = kHitTargetDenseMinSize - visual.height;
  final growDown = math
      .min(totalGrow, trackBandTop - visual.bottom)
      .clamp(0.0, totalGrow);
  final growUp = totalGrow - growDown;
  return Rect.fromLTRB(
    visual.left,
    visual.top - growUp,
    visual.right,
    visual.bottom + growDown,
  );
}

/// 竖屏编辑面转屏钮（无字图标）：动作「转为横屏」。字形 24dp、**视觉圆底**
/// 36dp、半透明深色圆底；位置由调用点按画面区右下角内缩 8dp 摆好。布局 =
/// 命中盒 48（外层 SizedBox，透明，调用点把视觉圆底外扩到命中下限），视觉
/// 圆底居中其内、位置逐位不变（透明外扩）。
class _PortraitRotateButton extends StatelessWidget {
  const _PortraitRotateButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: kPortraitRotateButtonHitKey,
      width: kHitTargetMinSize,
      height: kHitTargetMinSize,
      // 透明命中盒的点击面：外扩出的透明边缘也在本钮可点域内；点中视觉
      // 圆底时内层 InkWell 赢得竞技场，只触发一次。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Center(
          // 视觉圆底外的语义层：按钮角色、中文
          // 名字与激活动作同挂这一层——它恰好包住视觉件（36dp），所以几何
          // 断言仍打视觉矩形；读屏聚焦到的就是这枚钮，双击即触发。
          child: Semantics(
            key: kPortraitRotateButtonKey,
            button: true,
            label: '转为横屏',
            onTap: onPressed,
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                customBorder: const CircleBorder(),
                focusColor: kKeyboardFocusHighlight,
                onTap: onPressed,
                child: const ExcludeSemantics(
                  child: SizedBox(
                    width: kRotateButtonVisualSize,
                    height: kRotateButtonVisualSize,
                    child: Icon(
                      Icons.screen_rotation,
                      size: kRotateButtonGlyphSize,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 横屏编辑面「转为竖屏」纯文字矩形钮：动作
/// 由文字写清，半透明深色底衬使它在视频画面上仍读得出来。布局 = 命中盒
/// （外层 SizedBox，透明），视觉底衬 62 × 32 在其中按 [visualTopOffset]
/// 保持原位（透明外扩）；文字包 `FittedBox`
/// 单行缩放——大字号下收缩认读，不换行不被裁。
class _LandscapeToPortraitButton extends StatelessWidget {
  const _LandscapeToPortraitButton({
    required this.visualTopOffset,
    required this.onPressed,
  });

  /// 视觉底衬顶缘在命中盒内的偏移（= 命中盒上探量）。
  final double visualTopOffset;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: kLandscapeToPortraitButtonHitKey,
      // 透明命中盒的点击面：外扩出的透明边缘也在本钮可点域内（不透明铺满
      // 可点层包裹视觉件）；点中视觉件时
      // 内层 InkWell 赢得竞技场，只触发一次。
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        // Align 放松约束：视觉底衬 62 × 32 在命中盒内保持自身尺寸、按
        // [visualTopOffset] 停在原位（不被命中盒的紧约束拉伸）。
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(top: visualTopOffset),
            // 语义层包住视觉底衬（62 × 32）：按钮角色、中文名字与激活动作
            // 同挂这一层，几何断言仍打视觉矩形。
            child: Semantics(
              key: kLandscapeToPortraitButtonKey,
              button: true,
              label: '转为竖屏',
              onTap: onPressed,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: kLandscapeToPortraitButtonWidth,
                  height: kLandscapeToPortraitButtonHeight,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    focusColor: kKeyboardFocusHighlight,
                    onTap: onPressed,
                    // 可见文字不出现在语义树里：读屏听到的只有上面这枚
                    // 干净的名字，不重复播报一遍按钮文字。
                    child: const ExcludeSemantics(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '转为竖屏',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
