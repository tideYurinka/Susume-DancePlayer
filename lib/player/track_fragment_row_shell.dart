/// 区间片段行块体骨架（「区间片段行共用块壳，不重叠语义各按
/// 自己的理由定」）：备注轨与
/// 局部镜像轨共用的一块块体骨架——`Positioned` 摆位、`Stack` 层序（块体层
/// → 载荷层 → 端点带层）、块体四个水平拖动回调的挂法、端点带层。
///
/// **契约（只认三件）**：
///
///   - **怎么算**——块矩形由调用点经共用纯件 `intervalBlockRect` 求值后传入
///     （[block]）；本件不读时间、不读窗口、不自己算像素；`null` 降级由调
///     用点处理。
///   - **怎么摆**——[block] 给横向（[IntervalBlockRect.left] / `width`）、
///     [rowRect] 给纵向（`top` / `height`）；[edgeBandsOutward] 决定端点带
///     贴块外侧（命中域让位到块外空隙：外层铺到块 ± 两侧带宽、块体内容按
///     伸出量内移，块外带体才接得到命中）还是贴块内侧（带体叠在块体之上）。
///   - **怎么接线**——四支水平拖动回调逐位照挂：块体层挂 [onMoveDragStart]
///     起手，端点带层挂 [onEdgeDragStart] 起手（带出该侧 [IntervalEdge]），
///     两层共用 [onDragUpdate] / [onDragEnd] / [onDragCancel]。
///
/// **不认**：颜色、圆角、内边距、文字、图标、锁定角标、选中与高亮描边、
/// 端点柄条——装饰与载荷由调用点经 [body] / [payload] / [edgeBandChild] 自带；
/// 锁定与选中的判据归调用点。
///
/// **端点带宽由调用点按各自规则算好传入**（镜像轨 = 共用区域划分的窄块抑
/// 制、贴块内侧；备注轨 = 命中域分配、贴块外侧空隙），`0` = 该侧让出、不
/// 渲染（见 [startEdgeBandWidth] / [endEdgeBandWidth]）。**键全部由调用点
/// 提供**（[blockKey] / [edgeKey]，引导锚点键 [guideAnchorKey]）——本件不
/// 拼任何键字符串。
///
/// **依赖方向（单向）**：本件 → `annotation/interval_fragment_row.dart`（块
/// 矩形与端点选边的纯值）、`track_row_table.dart`（行矩形纯值）、
/// `help/guide_anchor.dart`（只构造锚点包装件 `GuideAnchor`——本件自己不读
/// provider、不碰容器句柄）。三条都是本件向下的消费方向，本件不被其中任何
/// 一个 import，也不 import 轨道带 State 或任何行域。
library;

import 'package:flutter/material.dart';

import '../annotation/interval_fragment_row.dart'
    show IntervalBlockRect, IntervalEdge;
import '../help/guide_anchor.dart' show GuideAnchor;
import 'track_row_table.dart' show TrackRowRect;

/// 区间片段行块体骨架：装饰与载荷留在调用点，本件只认怎么算、怎么摆、怎么
/// 接线（详见库头）。
class TrackFragmentRowShell extends StatelessWidget {
  const TrackFragmentRowShell({
    super.key,
    required this.blockKey,
    required this.block,
    required this.rowRect,
    required this.startEdgeBandWidth,
    required this.endEdgeBandWidth,
    required this.edgeBandsOutward,
    required this.body,
    this.payload = const [],
    this.edgeBandChild,
    required this.edgeKey,
    this.guideAnchorKey,
    required this.onMoveDragStart,
    required this.onEdgeDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onDragCancel,
  });

  /// 块体 `Positioned` 的键（调用点原键，逐位不变）。
  final Key blockKey;

  /// 共用件 [intervalBlockRect] 求值出的块矩形（null 降级由调用点处理）。
  final IntervalBlockRect block;

  /// 所在行的行矩形（纵向摆位）。
  final TrackRowRect rowRect;

  /// 两端端点带宽度（调用点算好；`0` = 该侧让出、不渲染）。
  final double startEdgeBandWidth;
  final double endEdgeBandWidth;

  /// 端点带贴块外侧（备注轨：命中域让位到块外空隙）还是贴块内侧（镜像轨
  /// 既有口径）。外侧时块壳放开裁切，让带体伸进块外空隙。
  final bool edgeBandsOutward;

  /// 块体层：调用点提供的装饰与载荷容器（包在块体拖动手势里）。
  final Widget body;

  /// 载荷层：夹在块体与端点带之间的额外部件（锁定角标、高亮描边等）。
  final List<Widget> payload;

  /// 端点带内的装饰件（可选，两端各一次调用）：画在本侧带体**内部**，
  /// 因此「看得见的柄」与「拖得动的带」是同一个矩形——所见即所拖。装饰仍
  /// 由调用点提供，本件不认颜色。
  final Widget Function(IntervalEdge edge)? edgeBandChild;

  /// 端点带键（调用点原键，逐位不变）。
  final Key Function(IntervalEdge edge) edgeKey;

  /// 非空 = 本块是菜单类角标（备注 / 局部镜像）刚落成的实物：块体层包一层
  /// 锚点包装器上报矩形；被包内容逐位不变。
  final String? guideAnchorKey;

  final void Function(DragStartDetails details) onMoveDragStart;
  final void Function(IntervalEdge edge, DragStartDetails details)
  onEdgeDragStart;
  final void Function(DragUpdateDetails details) onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onDragCancel;

  @override
  Widget build(BuildContext context) {
    final bandWidths = {
      IntervalEdge.start: startEdgeBandWidth,
      IntervalEdge.end: endEdgeBandWidth,
    };
    // 贴块外侧（备注轨）时命中带在块矩形之外：外层 `Positioned` 铺到扩展
    // 矩形（块 ± 两侧带宽），块体内容按伸出量内移——命中测试才能到达块外
    // 的带体（块尺寸的 Stack 转发不了界外命中）。贴块内侧（镜像轨既有口
    // 径）时不扩展，带体叠在块体之上、行为逐位不变。
    final extendStart = edgeBandsOutward ? startEdgeBandWidth : 0.0;
    final extendEnd = edgeBandsOutward ? endEdgeBandWidth : 0.0;
    // 块体层（含载荷）：角标锚点包在块体 `Positioned` 之内，上报矩形因此
    // 恰是块矩形（不含贴块外侧的端点带外扩），被包内容逐位不变。
    final blockContent = Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: onMoveDragStart,
            onHorizontalDragUpdate: onDragUpdate,
            onHorizontalDragEnd: (_) => onDragEnd(),
            onHorizontalDragCancel: onDragCancel,
            child: body,
          ),
        ),
        ...payload,
      ],
    );
    final guideAnchorKey = this.guideAnchorKey;
    return Positioned(
      left: block.left - extendStart,
      width: block.width + extendStart + extendEnd,
      top: rowRect.top,
      height: rowRect.height,
      child: Stack(
        children: [
          // 块体层 + 载荷层：装饰与载荷由调用点提供，块内坐标不变。
          Positioned(
            key: blockKey,
            left: extendStart,
            width: block.width,
            top: 0,
            height: rowRect.height,
            child: guideAnchorKey == null
                ? blockContent
                : GuideAnchor(anchorKey: guideAnchorKey, child: blockContent),
          ),
          // 端点命中带层：起手进入端点拖。宽度 0 的侧让出、不渲染（备注轨
          // 的冲突让位与镜像轨的窄块抑制同款收口）。
          for (final entry in bandWidths.entries)
            if (entry.value > 0)
              Positioned(
                key: edgeKey(entry.key),
                left: entry.key == IntervalEdge.start ? 0 : null,
                right: entry.key == IntervalEdge.end ? 0 : null,
                top: 0,
                width: entry.value,
                height: rowRect.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) =>
                      onEdgeDragStart(entry.key, details),
                  onHorizontalDragUpdate: onDragUpdate,
                  onHorizontalDragEnd: (_) => onDragEnd(),
                  onHorizontalDragCancel: onDragCancel,
                  child: edgeBandChild?.call(entry.key),
                ),
              ),
        ],
      ),
    );
  }
}
