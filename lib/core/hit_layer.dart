/// 透明命中层内容件。
///
/// 外扩一律用透明命中盒：调用方用 [Positioned] 把本件铺成
/// [kHitTargetMinSize]×[kHitTargetMinSize]，视觉件留在原处、命中域由本件
/// 承担。可点层自带无障碍按钮语义（名字/取值 + 无障碍点按），指针点按交给
/// [onTapUpLocal]，调用方据局部坐标按最近目标换算——重叠的命中层因此不会
/// 「谁压在最上面谁赢」。
library;

import 'package:flutter/widgets.dart';

import 'hit_target.dart';

/// [kHitTargetMinSize] 见方的透明可点层。
///
/// [onActivate] 是这次激活的动作：无障碍点按走它；指针点按在没有
/// [onTapUpLocal] 时也走它（否则指针走 [onTapUpLocal] 的最近换算）。
///
/// [semantics] 为 false 时不产生无障碍节点（语义由外层视觉件承担，如带
/// 「跳过」文字的按钮）。
class HitTargetLayer extends StatelessWidget {
  const HitTargetLayer({
    super.key,
    this.label,
    this.value,
    this.onActivate,
    this.onTapUpLocal,
    this.semantics = true,
    this.button = true,
  });

  /// 无障碍按钮名字。
  final String? label;

  /// 无障碍取值（如练习量、当前进度）。
  final String? value;

  /// 激活动作（无障碍点按；无 [onTapUpLocal] 时也是指针点按）。
  final VoidCallback? onActivate;

  /// 需要按局部坐标换算最近目标时的指针点按。
  final ValueChanged<Offset>? onTapUpLocal;

  /// 是否在无障碍树里报语义。
  final bool semantics;

  /// 是否报按钮角色（无动作的格子只报名字与取值）。
  final bool button;

  @override
  Widget build(BuildContext context) {
    // 无任何动作时不留可点层：opaque 的无手势层仍会吞掉命中，挡住下层
    // 网格的空白单击。
    final Widget content = const SizedBox.expand();
    final layer = onActivate == null && onTapUpLocal == null
        ? content
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: onTapUpLocal == null ? onActivate : null,
            onTapUp: onTapUpLocal == null
                ? null
                : (details) => onTapUpLocal!(details.localPosition),
            child: content,
          );
    if (!semantics) return layer;
    return Semantics(
      container: true,
      button: button,
      label: label,
      value: value,
      onTap: onActivate,
      child: layer,
    );
  }
}
