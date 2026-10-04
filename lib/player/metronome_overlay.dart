/// 数拍跟练浮层：可拖浮层底座 + 数拍数字。
///
/// - **数拍数字锚点派生**（纯函数 seam）：
///   [deriveBeatCount] 以激活学习段段首为锚点，把播放位置解析为
///   练习区两数（八拍号 + 拍号）或前导区第 0 个八拍顺数两数
///   （八拍号固定 0 + 拍号）。起练习区八拍号**按八拍点顺数**
///   （相位源入参 [BeatPhase]：网格 + 八拍锚点）——半八拍表现为下一个
///   八拍号提前到来，不再整段漂移；前导区与显示格式不变。
/// - **可拖浮层**（[MetronomeOverlay]）：常态 `IgnorePointer` 穿透播放
///   手势；宿主（播放页）仲裁点选——命中浮层进「浮层选中态」（播放态
///   子状态），命中浮层外退出且不唤出控制层（`resolvePlaybackOverlayTap`）。
///   选中态显示矩形框（虚线青）+ 4 角工具（关闭 / 重置位置 / 跳转节拍
///   提示面板 / 右下锁定钮）；双指捏合按形态缩放（矩形只改宽度、摆锤
///   整体等比，钳制见模块内尺寸换算 `overlay.dart`；灵敏度减半、
///   范围 0.5–2.5×、混区闩锁在缩放会话期间不抑制，屏幕任意位置起手的
///   宿主仲裁见 `player_page.dart`）。选中态下**单指落浮层主体即拖动平移**——
///   宿主经 [OverlayMixedBurstTracker] 判定单指命中选中态浮层后驱动
///   [MetronomeOverlayController.moveBy]；右下工具为**锁定钮**：锁定后
///   单指平移禁用并穿透回视频宿主默认语义、双指
///   缩放禁用，但点选/角工具仍可操作；锁定不持久化（每次进入选中态
///   默认解锁）。混区（一指浮层一指浮层外）起手经
///   [MetronomeOverlayController.setBurstSuppressed] 闩锁抑制整场单指
///   语义（宿主经 [OverlayMixedBurstTracker] 判定，复用
///   `burstEverMixed` 混区锁语义）。
/// - **几何参考系 = 播放页视口**（全局逻辑坐标，与 PointerEvent.position
///   同一空间）；**存取归属 = 本地私密**（per-video 本地文档，不随公开标记
///   文件分享）。存取实现由宿主经 [MetronomeOverlayController.setStore]
///   接入，本控制器不假设存取面从哪里来。
/// - 位置 + 分形态系数 per-video 本地私密 JSON 持久化
///   （[overlayPlacementProvider]
///   为落盘恢复的 provider 面，读写由 `VideoSettingsPersistence` 收口；
///   位置按姿态 × 对比分四格记忆，矩形宽系数与摆锤等比系数分形态记忆）。
///   当前格由宿主按姿态（视口宽高）× 对比（会话模式）解析后经
///   [MetronomeOverlayController.setCell] 注入；缺席格 = 贴左、纵向视口高
///   12%（[defaultOverlayOffset] 按当前钳制框现算）。越界只钳生效面
///   （[MetronomeOverlayController.effectiveOffset]），**钳制结果不回写**
///   ——转屏/折展/分屏改尺寸不改写存值，转回原姿态原样恢复。
/// - 常态播放也按保存系数渲染：渲染尺寸统一经
///   [resolveOverlaySize]（`overlay.dart`），选中态预览与常态一致，
///   命中区/拖拽区随实际尺寸。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'beat_animation.dart' show BeatAnimationStyle;
import 'dashed_selection_box.dart' show DashedSelectionBoxPainter;
import 'overlay.dart';
import '../core/current_beat.dart';
import 'visual_tokens.dart';

/// 选中态双指缩放灵敏度：每指行程 0.5 响应——生效倍率 =
/// 1 + (原始倍率 − 1) × 本系数（按手势起始快照累计换算，逐帧等价于
/// 「每次增量 ×0.5」，且不随帧率漂移）。
const double kOverlayPinchSensitivity = 0.5;

/// 四角工具命中盒边长（dp）：透明外扩到命中盒
/// 下限。矩形形态最小生效位 160×120 时四角 48 盒互不重叠；摆锤最小档
/// （110×60）下纵向两角重叠，由 Stack 序仲裁——命中值不降（见 `_cornerTool`）。
const double kMetronomeCornerToolHitSize = kHitTargetMinSize;

/// 四角工具图标边长（dp，观感值）：命中盒外扩不改变它。
const double kMetronomeCornerToolIconSize = 20;

/// 四角工具图标距浮层对应角的内距（dp，观感值）：图标中心因此落在距角
/// [kMetronomeCornerToolIconInset] + 图标半宽处，与命中盒大小无关。
const double kMetronomeCornerToolIconInset = 10;

/// 浮层存在性 = 内容可见性：浮层底座（绘制 + 点选命中区）只在
/// 数拍内容**真正显示**时存在——节拍动画总开关开 且 有可显示的内容 且
/// 播放位置就绪 且 非异常态。激活学习段/临时衔接段不在条件之列。
///
/// [hasContent] 由宿主判定：常态 = 锚点链给得出可锚点；**录制准备期**
/// = 准备期自己的可视数拍状态（节拍前导期有数字，秒制兜底整段无内容）。
/// 四种内容为空的情况一律不挂载浮层、不参与命中、不可进选中态。
bool isBeatOverlayContentVisible({
  required bool displayEnabled,
  required bool hasContent,
  required bool positionReady,
  required bool beatTrackError,
}) {
  return displayEnabled && hasContent && positionReady && !beatTrackError;
}

/// 浮层位 + 分形态缩放系数的会话态模型（落盘恢复 / 页面接线的唯一事实源；
/// null = 文件无任何浮层位字段，四格全未自定义）。
class OverlayPlacementModel extends Notifier<OverlayPlacements?> {
  @override
  OverlayPlacements? build() => null;

  /// 写入（容器已销毁时跳过，沿 AnnotationSaveSinkModel.set 先例）。
  void set(OverlayPlacements? value) {
    if (!ref.mounted) return;
    state = value;
  }
}

/// 浮层位 + 分形态缩放系数的会话态 provider。
final overlayPlacementProvider =
    NotifierProvider<OverlayPlacementModel, OverlayPlacements?>(
      OverlayPlacementModel.new,
    );

/// 可拖浮层控制器：选中态 + 位置/缩放的单一事实源（ChangeNotifier，
/// 沿 GestureFeedbackController 等 plain-class 先例，不进 Riverpod）。
class MetronomeOverlayController extends ChangeNotifier {
  MetronomeOverlayController({OverlayPlacements? initialPlacement})
    : _placements = initialPlacement ?? const OverlayPlacements();

  /// 用户意图载荷（四格容器）：写回一律是用户意图，钳制只进生效面。
  OverlayPlacements _placements;

  /// 当前格（宿主按姿态 × 对比解析后经 [setCell] 注入）。
  OverlayPlacementCell _cell = OverlayPlacementCell.portraitNormal;

  /// 当前格（生效位置从它所属的格取值）。
  OverlayPlacementCell get cell => _cell;

  /// 生效几何（偏移 + 内容尺寸）的唯一解析口：尺寸按形态系数解析（铺满
  /// 钳制框为止）；偏移取当前格自定义值（缺席则按钳制框现算的默认位：
  /// 贴左、纵向视口高 12%），再钳回钳制框内。
  ///
  /// **钳制只在此生效**：容器里存的值一字不改（钳制不回写）。宿主未接线
  /// （钳制框 null）时不钳，默认位回落屏左上原点。
  ({Offset offset, Size size}) _effectiveGeometry() {
    final box = _clampBox;
    final size = resolveOverlaySize(
      style: _style,
      rectWidthFactor: _placements.rectWidthFactor,
      pendulumScale: _placements.pendulumScale,
      viewport: box,
    );
    final raw =
        _placements.offsetFor(_cell) ??
        (box == null ? Offset.zero : defaultOverlayOffset(box));
    if (box == null) return (offset: raw, size: size);
    return (
      offset: clampOverlayOffset(offset: raw, contentSize: size, viewport: box),
      size: size,
    );
  }

  /// 当前格**生效**的左上角偏移（显示位与命中区同源）。
  Offset get effectiveOffset => _effectiveGeometry().offset;

  /// 钳制框（播放页逻辑尺寸，宿主经 [setViewport] 注入）；null = 宿主未
  /// 接线，不钳（既有语义）。
  Size? _clampBox;

  /// 当前钳制框（宿主注入视口；null = 未接线，不钳）。
  Size? get clampBox => _clampBox;

  /// 几何存取实现：宿主经 [setStore] 接入持久化背后的存取面；缺省为只在
  /// 本会话内存中的易失实现（无宿主接线时几何不留存）。
  OverlayGeometryStore _store = _VolatileGeometryStore();

  /// 内容类声明的几何存取实现（宿主接线入口）。
  OverlayGeometryStore get store => _store;

  /// 接入存取实现（宿主持久化接线入口）。
  void setStore(OverlayGeometryStore store) => _store = store;

  bool _selected = false;

  /// 锁定态：true = 单指主体拖动禁用（穿透回视频宿主默认
  /// 语义）且双指缩放禁用，但点选/角工具仍可操作。**不持久化**——
  /// [select] 每次进入选中态都重置为解锁。
  bool _locked = false;

  /// 当前节拍动画形态（命中区与两指缩放语义随形态）。宿主经
  /// [MetronomeOverlay] 的 `style` 参数同步。
  BeatAnimationStyle _style = BeatAnimationStyle.bar;

  /// 本 burst 混区闩锁（宿主经 [OverlayMixedBurstTracker] 判定后置位；
  /// true 期间浮层单指/双指语义整场抑制）。选中态缩放会话（[pinchActive]）
  /// 期间不生效：选中态缩放是明确模态，不进混区锁。
  bool _burstSuppressed = false;

  /// 选中态缩放会话（[beginPinch] 起快照，[endPinch] 清空）：非 null 即
  /// 进行中——全局双指仲裁，宿主与浮层两条路径经同一会话 API 驱动，混区
  /// 闩锁在会话期间被忽略。快照 = 分形态系数基准。
  ({double rectWidthFactor, double pendulumScale})? _pinch;

  /// 浮层位载荷（四格容器；当前格之外的三格原样携带）。
  OverlayPlacements get placements => _placements;

  BeatAnimationStyle get style => _style;

  /// 宿主注入当前视口（播放页逻辑尺寸 = 钳制框）。
  /// 方向/尺寸变化只换钳制框：生效位置与生效尺寸按新框现算（钳制只进
  /// 生效面），容器里存的值一字不改，故转屏/折展**不产生任何写入**。
  /// 静默生效不 notify——本方法只在宿主 didChangeDependencies（build 前的
  /// 依赖阶段）调用，紧随的 build 会以新值重渲染。
  void setViewport(Size viewport) {
    if (_clampBox == viewport) return;
    _clampBox = viewport;
  }

  /// 宿主注入当前格（姿态 × 对比解析结果）：切格只换取值来源，
  /// 选中态与锁定态原样保持；生效位置随即由新格派生（不写容器）。拖动
  /// burst 进行中切格 → 本手势就此结束（闩锁到 burst 收尾）。
  void setCell(OverlayPlacementCell value) {
    if (_cell == value) return;
    _cell = value;
    if (_dragStartCell != null) _dragEndedByCellSwitch = true;
    notifyListeners();
  }

  /// 本拖动 burst 起手时的格与「已被切格终结」闩锁（[beginMove] 复位）。
  /// 手势进行中一旦切格，已累积的位移留在切格前那一格，本手势随即结束
  /// 且**不再因切回原格而复燃**（A→B→A 也不恢复写入）。
  OverlayPlacementCell? _dragStartCell;
  bool _dragEndedByCellSwitch = false;

  /// 开始拖动 burst（宿主在 scale 手势起手时调用，与是否命中浮层无关：
  /// 未拖动浮层时本会话记账无副作用）。
  void beginMove() {
    _dragStartCell = _cell;
    _dragEndedByCellSwitch = false;
  }

  /// 结束拖动 burst（burst 收尾；幂等）。
  void endMove() {
    _dragStartCell = null;
    _dragEndedByCellSwitch = false;
  }

  set style(BeatAnimationStyle value) {
    if (_style == value) return;
    _style = value;
    // 形态切换只改生效内容尺寸（如摆锤整体变高）：生效位置由新尺寸现算
    // 重钳，容器里的存值不动。
    notifyListeners();
  }

  bool get selected => _selected;

  bool get locked => _locked;

  bool get burstSuppressed => _burstSuppressed;

  /// 当前浮层命中矩形（播放页坐标系；尺寸按形态系数解析，随实际尺寸）。
  ///
  /// 坐标系契约：placement 与命中判定同用全局逻辑坐标，宿主（播放页）
  /// 的浮层 Stack 须全屏且位于全局原点——与 PointerEvent.position 同一
  /// 空间；外层若引入偏移需同步换算。
  Rect hitRect() {
    final geometry = _effectiveGeometry();
    return Rect.fromLTWH(
      geometry.offset.dx,
      geometry.offset.dy,
      geometry.size.width,
      geometry.size.height,
    );
  }

  bool hitTest(Offset globalPosition) => hitRect().contains(globalPosition);

  void select() {
    if (_selected) return;
    _selected = true;
    // 锁定不持久化：每次进入选中态默认解锁。
    _locked = false;
    notifyListeners();
  }

  void deselect() {
    if (!_selected) return;
    _selected = false;
    notifyListeners();
  }

  /// 写入锁定态：锁定后浮层不响应单指平移/双指缩放手势
  /// （宿主据此把单指穿透回视频），仍保持选中与角工具可操作；解锁恢复。
  void setLocked(bool locked) {
    if (_locked == locked) return;
    _locked = locked;
    notifyListeners();
  }

  /// 「重置位置」角工具：只清**当前这一
  /// 格**的自定义位（该格回未自定义 = 贴左、视口高 12%），其余三格的位置
  /// 一字不动；同时把两形态共用的尺寸系数回 1.0——尺寸四格共用，故另三格
  /// 的尺寸观感也随之回默认。写入的是用户意图（未自定义 + 默认系数），不
  /// 是任何钳制结果。
  void resetPlacement() {
    _commit(
      _placements
          .withOffset(_cell, null)
          .withFactors(rectWidthFactor: 1.0, pendulumScale: 1.0),
    );
  }

  /// 整体替换浮层位载荷（持久化恢复接线用）：位置原样落容器（越界值只
  /// 在生效面钳，转回原姿态原样恢复），系数钳回上下限。
  void applyPlacements(OverlayPlacements placements) =>
      _commit(_withClampedFactors(placements));

  /// 载荷提交收口：写库一律经此——值未变不通知（相等性防环，也免去一次
  /// 无谓的会话态写入/落盘）。
  void _commit(OverlayPlacements next) {
    if (next == _placements) return;
    _placements = next;
    notifyListeners();
  }

  /// 生效面尺寸系数的上下限钳制（位置钳制只进 [effectiveOffset]，不在此）。
  OverlayPlacements _withClampedFactors(OverlayPlacements placements) =>
      placements.withFactors(
        rectWidthFactor: clampRectWidthFactor(placements.rectWidthFactor),
        pendulumScale: clampPendulumScale(placements.pendulumScale),
      );

  /// 单指平移（屏幕坐标增量）：从**用户看得见的生效位**起算，写入其加
  /// 位移后的用户意图（不是钳制结果）。burst 进行中切格即本手势结束，
  /// 之后的帧（含切回原格的帧）一律不再写。
  void moveBy(Offset delta) {
    if (delta == Offset.zero) return;
    if (_dragEndedByCellSwitch) return;
    _placements = _placements.withOffset(_cell, effectiveOffset + delta);
    notifyListeners();
  }

  /// 矩形形态两指捏合（增量乘语义，兼容视图/回归 seam）：取水平分量只改
  /// 宽度。钳制与写回统一收口在 [_applyPinchPlacement]（含生效面视口钳）。
  void applyRectPinch(double horizontalScale) {
    _applyPinchPlacement(
      _placements.withFactors(
        rectWidthFactor: _placements.rectWidthFactor * horizontalScale,
      ),
    );
  }

  /// 摆锤形态两指捏合（增量乘语义）：整体等比缩放。钳制收口同
  /// [applyRectPinch]。
  void applyPendulumPinch(double scale) {
    _applyPinchPlacement(
      _placements.withFactors(pendulumScale: _placements.pendulumScale * scale),
    );
  }

  /// 混区闩锁写入（burst 起手清零由宿主负责）。缩放会话进行中
  /// 的置位忽略：选中态缩放是明确模态，两指出框不闩锁抑制。
  void setBurstSuppressed(bool suppressed) {
    if (_pinch != null && suppressed) return;
    if (_burstSuppressed == suppressed) return;
    _burstSuppressed = suppressed;
    notifyListeners();
  }

  /// 选中态缩放会话开始（全局双指仲裁的单一 seam：浮层自身与宿主
  /// 两条驱动路径共用）。快照分形态系数基准；起手解除已落混区闩锁。
  void beginPinch() {
    _pinch = (
      rectWidthFactor: _placements.rectWidthFactor,
      pendulumScale: _placements.pendulumScale,
    );
    if (_burstSuppressed) {
      _burstSuppressed = false;
      notifyListeners();
    }
  }

  /// 缩放帧（≥2 指帧）：[scale]/[horizontalScale] 为自会话起始的**累计**
  /// 原始倍率（ScaleUpdateDetails 语义），按灵敏度 [kOverlayPinchSensitivity]
  /// 减半后以起始快照为基准**绝对写回**——生效系数 = 基准 × (1 + (原始 − 1)
  /// × 0.5)（对累计倍率做算术减半，而非对每帧增量做 0.5 连乘；与
  /// 半灵敏度的「原始倍率减半」口径一致，且与帧数/帧率无关）。非会话期间
  /// 忽略。两指语义随形态：矩形只取水平分量只改宽度，摆锤整体等比。钳制
  /// 收口在 [_applyPinchPlacement]（内容相对钳 + 生效面视口钳）。
  void updatePinch({required double scale, required double horizontalScale}) {
    final pinch = _pinch;
    if (pinch == null) return;
    switch (_style) {
      case BeatAnimationStyle.bar:
        _applyPinchPlacement(
          _placements.withFactors(
            rectWidthFactor:
                pinch.rectWidthFactor * _halvedPinch(horizontalScale),
          ),
        );
      case BeatAnimationStyle.pendulum:
        _applyPinchPlacement(
          _placements.withFactors(
            pendulumScale: pinch.pendulumScale * _halvedPinch(scale),
          ),
        );
    }
  }

  /// 缩放帧的绝对写回（与 [applyRectPinch]/[applyPendulumPinch] 同一
  /// 收口）：写的是用户意图系数（钳回上下限），位置不落钳制结果；生效面
  /// 位置钳制归 [effectiveOffset]（放大后位置随钳制收口保持可达）。
  void _applyPinchPlacement(OverlayPlacements next) =>
      _commit(_withClampedFactors(next));

  /// 缩放会话结束（清基准；幂等）。
  void endPinch() {
    _pinch = null;
  }

  /// 原始倍率减半：生效 = 1 + (原始 − 1) × 灵敏度。
  double _halvedPinch(double rawScale) =>
      1 + (rawScale - 1) * kOverlayPinchSensitivity;
}

/// 播放页混区 burst 跟踪（闩锁语义）：按原始指针记录「落浮层上 / 浮层外」，
/// burst（首指按下 → 全部抬起）内两类指针并存即闩锁整场抑制。
class OverlayMixedBurstTracker {
  final Set<int> _onOverlay = {};
  final Set<int> _offOverlay = {};
  bool _everMixed = false;

  /// 本 burst 是否曾进入混区（闩锁到 burst 结束才复位）。
  bool get burstEverMixed => _everMixed;

  /// 浮层选中态下本 burst 是否有指针落浮层上（宿主抑制播放语义的依据；
  /// 未选中时恒 false——常态浮层穿透，指针语义归播放层）。
  bool get burstTouchesSelectedOverlay => _onOverlay.isNotEmpty;

  /// [onOverlay] = 按下点是否命中**选中态**浮层（宿主先做命中判定）。
  void pointerDown(int pointer, {required bool onOverlay}) {
    if (_onOverlay.isEmpty && _offOverlay.isEmpty) {
      _everMixed = false; // 新 burst 起复位闩锁。
    }
    onOverlay ? _onOverlay.add(pointer) : _offOverlay.add(pointer);
    if (_onOverlay.isNotEmpty && _offOverlay.isNotEmpty) {
      _everMixed = true;
    }
  }

  void pointerUp(int pointer) {
    _onOverlay.remove(pointer);
    _offOverlay.remove(pointer);
  }

  /// burst 结束（全部指针抬起）：清空簿记（闩锁随之复位）。
  void endBurst() {
    _onOverlay.clear();
    _offOverlay.clear();
    _everMixed = false;
  }
}

/// 数拍数字内容（给定 [BeatCountDisplay] 渲染两数）。
class BeatCountNumbers extends StatelessWidget {
  const BeatCountNumbers({super.key, required this.display});

  final BeatCountDisplay display;

  @override
  Widget build(BuildContext context) {
    switch (display) {
      case PracticeBeatCount(:final eightCount, :final beatCount):
        final cycle = eightCountCycleDisplay(eightCount);
        return _BeatPairRow(
          eightText: '${cycle.number}',
          groupText: cycle.group == null ? null : '${cycle.group}',
          beatText: '$beatCount',
          rowKey: const Key('beat_count_practice'),
        );
      case LeadingBeatCount(:final eightCount, :final beatCount):
        return _BeatPairRow(
          eightText: '$eightCount',
          beatText: '$beatCount',
          rowKey: const Key('beat_count_leading'),
        );
    }
  }
}

/// 两数渲染（八拍号 青·大 + 拍号 白·小），练习区与前导区共用。
class _BeatPairRow extends StatelessWidget {
  static const _groupSuperscriptFontSize = 14.0;

  /// 主数字为组序让位的左内边距（≥ 上标宽；随上标字号联动）。
  static const _groupSuperscriptLeftInset = 15.0;

  const _BeatPairRow({
    required this.eightText,
    required this.beatText,
    required this.rowKey,
    this.groupText,
  });

  final String eightText;

  /// 组上标：仅相对八拍 > 4 时非空。
  final String? groupText;
  final String beatText;
  final Key rowKey;

  @override
  Widget build(BuildContext context) {
    final eight = Text(
      eightText,
      key: const Key('beat_count_eight'),
      style: const TextStyle(
        color: kCyanAccentColor,
        fontSize: 56,
        height: 1.0,
        fontWeight: FontWeight.w700,
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 组序 = 青色大数左上角上标：主数字行左移让位，
        // 组序悬于行左上角（不参与基线排版、不改行高）。
        if (groupText != null)
          Positioned(
            left: 0,
            top: 0,
            child: Text(
              groupText!,
              key: const Key('beat_count_group'),
              style: const TextStyle(
                color: kCyanAccentColor,
                fontSize: _groupSuperscriptFontSize,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        Row(
          key: rowKey,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: groupText == null ? 0 : _groupSuperscriptLeftInset,
              ),
              child: eight,
            ),
            const SizedBox(width: 6),
            Text(
              beatText,
              key: const Key('beat_count_beat'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                height: 1.0,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 可拖浮层（底座）。
///
/// 常态：[IgnorePointer] 穿透——点选/命中判定归宿主（`resolvePlaybackOverlayTap`，
/// 经 [MetronomeOverlayController.hitTest]）。
/// 选中态：矩形框（虚线青）+ 4 角工具（含右下锁定钮）。选中态主体对
/// 指针穿透——单指拖动平移（[controller.locked] 为 false 时）与双指缩放
/// 都归宿主手势层全局仲裁（控制器 [MetronomeOverlayController] 缩放会话 +
/// [locked] seam）；锁定后单指
/// 穿透回视频宿主默认语义、双指缩放禁用，角工具仍可操作。
/// [controller.burstSuppressed] 为 true 期间全部单指/双指语义抑制。
class MetronomeOverlay extends StatefulWidget {
  const MetronomeOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.style = BeatAnimationStyle.bar,
    this.readOnly = false,
    this.onClose,
    this.onReset,
    this.onToggleBeatBubble,
    this.beatBubbleLink,
  });

  final MetronomeOverlayController controller;

  /// 当前节拍动画形态（两指缩放语义随形态、尺寸随形态系数）。
  final BeatAnimationStyle style;

  /// 浮层内容（数拍数字；后续节拍动画/文字备注复用同底座）。
  final Widget child;

  /// 只读态（控制层展开时浮层如同烙在源视频上）——内容照常
  /// 绘制但 IgnorePointer 不可交互、不显示选中框与角工具（即使控制器
  /// 仍处于选中态也按常态渲染）；位置/缩放沿用保存值。
  final bool readOnly;

  final VoidCallback? onClose;
  final VoidCallback? onReset;

  /// 节拍提示气泡开关：短按左下角工具 = 切换气泡展开/收起
  /// （与倍速/步进气泡互斥单开）。
  final VoidCallback? onToggleBeatBubble;

  /// 节拍提示气泡锚点：左下角工具为 CompositedTransformTarget，
  /// 气泡锚定工具上方；非 null 时工具包一层目标变换。
  final LayerLink? beatBubbleLink;

  @override
  State<MetronomeOverlay> createState() => _MetronomeOverlayState();
}

class _MetronomeOverlayState extends State<MetronomeOverlay> {
  MetronomeOverlayController get _controller => widget.controller;

  bool get _suppressed => _controller.burstSuppressed;

  @override
  void initState() {
    super.initState();
    _controller.style = widget.style;
    _exitSelectionIfReadOnly();
  }

  @override
  void didUpdateWidget(MetronomeOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.style = widget.style;
    _exitSelectionIfReadOnly();
  }

  /// 只读态 = 失焦：进入只读
  /// 即真正退出控制器选中态——不只是渲染层隐藏，收起只读后选中框不得
  /// 未点选而回归。
  void _exitSelectionIfReadOnly() {
    if (widget.readOnly) _controller.deselect();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final offset = _controller.effectiveOffset;
        // 常态渲染：内容按保存系数解析出的实际尺寸布局——矩形按
        // 实宽铺内容（矩形栏 LayoutBuilder 等分随宽伸缩）、摆锤整体等比
        // 缩放（含数字）。选中态预览与常态同源。
        final content = _sizedContent(context);
        // 只读态（控制层展开）强制按常态渲染：穿透、无选中框与角工具。
        if (widget.readOnly || !_controller.selected) {
          // 常态穿透：不参与命中，播放手势原样生效。
          return Positioned(
            left: offset.dx,
            top: offset.dy,
            child: IgnorePointer(child: content),
          );
        }
        final rect = _controller.hitRect();
        return Positioned(
          left: offset.dx,
          top: offset.dy,
          width: rect.width,
          height: rect.height,
          child: Stack(
            key: const Key('metronome_overlay_selected'),
            clipBehavior: Clip.none,
            children: [
              // 按实际尺寸布局的内容（左上锚定）。
              // 语义档（随系统字号）：数拍两数与格内拍号承载语义，
              // 随设备 textScaler 缩放；盒几何（命中矩形 / 摆锤基准盒 +
              // FittedBox）不变，摆锤形态经 FittedBox 单次缩放仍全域无溢出。
              // 选中态 body 对指针穿透：宿主全局双指
              // 缩放需在「任意位置」起手都拿到指针；单指主体拖动与锁定
              // 后穿透给视频都归宿主 scale 识别器仲裁——浮层自身内容
              // 不吞命中，仅 4 角工具各自保留独立命中。
              IgnorePointer(child: content),
              // 虚线青矩形选中框（纯装饰：对指针穿透，仅角工具交互）。
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DashedSelectionBoxPainter(
                      color: kCyanAccentColor,
                      strokeWidth: 1.5,
                    ),
                  ),
                ),
              ),
              // 4 角工具（次序 = [OverlayCorner] 枚举序）。
              ..._cornerTools(),
            ],
          ),
        );
      },
    );
  }

  /// 按形态系数解析实际尺寸并布局内容：矩形 = SizedBox 实宽（矩形栏
  /// 随宽横向伸缩）；摆锤 = 实际尺寸容器内「基准一次布局 + FittedBox
  /// 单次视觉缩放」（内容恒在专属基准 [kPendulumBaseContentSize]
  /// 220×120 布局一次、只缩放一次，s∈[0.5,2.5] 全域无溢出、无二次位移）。
  /// 尺寸统一取命中矩形（视口联动生效钳制的单一来源：常态渲染与
  /// 命中/选中框同源铺满视口生效值）。
  /// 语义档（随系统字号）：数拍数字随系统字号长高，内容盒的**竖向容量**
  /// 按同一缩放值重算（缩放 ≤1 不收缩，沿用槽位定宽的既有口径）；外层
  /// 盒与摆锤基准盒**同倍**加高，fill 的纵横比不变（单次缩放
  /// 几何逐位保持），数字在屏上真的变大而不被 FittedBox 压回。宽向与
  /// 命中矩形保持一致（命中/选中框几何不变；内容为顶部锚定的透明文字
  /// 层，加高部分只增排版容量，不改观感基准）。
  Widget _sizedContent(BuildContext context) {
    final size = _controller.hitRect().size;
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final heightScale = textScale > 1 ? textScale : 1;
    if (_controller.style != BeatAnimationStyle.pendulum) {
      return SizedBox(
        width: size.width,
        height: size.height * heightScale,
        child: widget.child,
      );
    }
    return SizedBox(
      width: size.width,
      height: size.height * heightScale,
      child: FittedBox(
        fit: BoxFit.fill,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: kPendulumBaseContentSize.width,
          height: kPendulumBaseContentSize.height * heightScale,
          child: widget.child,
        ),
      ),
    );
  }

  /// 四角工具（键 / 图标 / 点击回调在此收敛；次序 = [OverlayCorner]
  /// 枚举序）：左上关闭 / 右上重置位置 / 左下节拍提示面板入口 / 右下锁定钮。
  /// `burstSuppressed` 期间全部禁用。
  List<Widget> _cornerTools() {
    final suppressed = _suppressed;
    final byCorner = <OverlayCorner, Widget>{
      OverlayCorner.topLeft: _cornerTool(
        alignment: Alignment.topLeft,
        key: const Key('metronome_overlay_close'),
        icon: Icons.close,
        label: '关闭数拍浮层',
        onTap: suppressed ? null : widget.onClose,
      ),
      OverlayCorner.topRight: _cornerTool(
        alignment: Alignment.topRight,
        key: const Key('metronome_overlay_reset'),
        icon: Icons.center_focus_strong,
        label: '重置数拍浮层位置',
        onTap: suppressed
            ? null
            : () {
                _controller.resetPlacement();
                widget.onReset?.call();
              },
      ),
      OverlayCorner.bottomLeft: _cornerTool(
        alignment: Alignment.bottomLeft,
        key: const Key('metronome_overlay_beat_panel'),
        icon: Icons.graphic_eq,
        label: '切换节拍提示面板',
        onTap: suppressed ? null : widget.onToggleBeatBubble,
        link: widget.beatBubbleLink,
      ),
      // 右下锁定钮：切换锁定态。锁定 =
      // 单指主体拖动禁用（穿透回视频）+ 双指缩放禁用；解锁恢复拖动与
      // 缩放。锁定不持久化（进入选中态默认解锁）。
      OverlayCorner.bottomRight: _cornerTool(
        alignment: Alignment.bottomRight,
        key: const Key('metronome_overlay_lock'),
        icon: _controller.locked ? Icons.lock : Icons.lock_open,
        label: _controller.locked ? '解锁数拍浮层' : '锁定数拍浮层',
        onTap: suppressed
            ? null
            : () => _controller.setLocked(!_controller.locked),
      ),
    };
    return [for (final corner in OverlayCorner.values) byCorner[corner]!];
  }

  Widget _cornerTool({
    required AlignmentGeometry alignment,
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    LayerLink? link,
  }) {
    // 命中盒下限：命中盒取
    // [kMetronomeCornerToolHitSize]，图标 [kMetronomeCornerToolIconSize] 按
    // [kMetronomeCornerToolIconInset] 贴浮层对应角——命中盒外扩不移动图标。
    Widget tool = IconButton(
      key: key,
      // 不叠 compact 密度：Material 的 padded 触控下限即命中盒下限。
      alignment: alignment,
      padding: const EdgeInsets.all(kMetronomeCornerToolIconInset),
      constraints: const BoxConstraints(
        minWidth: kMetronomeCornerToolHitSize,
        minHeight: kMetronomeCornerToolHitSize,
      ),
      icon: Icon(
        icon,
        color: Colors.white,
        size: kMetronomeCornerToolIconSize,
        semanticLabel: label,
      ),
      onPressed: onTap,
    );
    if (link != null) {
      tool = CompositedTransformTarget(link: link, child: tool);
    }
    return Align(alignment: alignment, child: tool);
  }
}

/// 数拍浮层的本地私密几何存取实现：读 / 写 / 订阅全部落在
/// [overlayPlacementProvider]（本地私密的会话态面；落盘由
/// `VideoSettingsPersistence` 收口）。
class OverlayPlacementSessionStore implements OverlayGeometryStore {
  OverlayPlacementSessionStore(this._ref);

  final WidgetRef _ref;

  @override
  OverlayPlacements? read() => _ref.read(overlayPlacementProvider);

  /// 「四格全未自定义」与「文件无任何浮层位字段」（null）在本存取面上是
  /// 同一个值：写成全未自定义即清除（回落 null）。值无变化时跳过写入
  /// ——控制器在 build 依赖阶段（`didChangeDependencies`）的切格通知会走到
  /// 这里，而 Riverpod 禁止在 widget 生命周期内改 provider（即便同值）。
  @override
  void write(OverlayPlacements? value) {
    final next = value == const OverlayPlacements() ? null : value;
    if (_ref.read(overlayPlacementProvider) == next) return;
    _ref.read(overlayPlacementProvider.notifier).set(next);
  }

  @override
  void listen(
    void Function(OverlayPlacements? value) onChanged, {
    required bool fireImmediately,
  }) => _ref.listenManual(
    overlayPlacementProvider,
    (_, OverlayPlacements? next) => onChanged(next),
    fireImmediately: fireImmediately,
  );
}

/// 缺省几何存取实现：几何只在本会话内存中，不落盘。
class _VolatileGeometryStore implements OverlayGeometryStore {
  OverlayPlacements? _value;

  @override
  OverlayPlacements? read() => _value;

  @override
  void write(OverlayPlacements? value) => _value = value;

  @override
  void listen(
    void Function(OverlayPlacements? value) onChanged, {
    required bool fireImmediately,
  }) {}
}
