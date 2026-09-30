/// 倍速气泡（合并观看态全宽弹层与编辑态全宽面板两套重复 UI；步进并入同一
/// 气泡右栏）。
///
/// - **同一气泡组件 + 同一状态来源**：[SpeedBubble] 由
///   观看态（player_page 右下胶囊上方）与编辑态（control_layer 顶栏工具
///   图标下）共同消费；展开状态唯一来源为 [speedBubbleSessionProvider]
///   ——`open` 单值保证各锚定气泡互斥（一次只开一个）。
/// - 倍速模式内容左右两栏：
///   左「倍速栏」＝顶部倍率下拉（当前值 + 常用/历史置顶 + 0.1–2.0 步 0.05
///   全档可滚）+ 常规档位 | 历史档位（空态占位）+ 竖向滑条（0.1–1.5、0.05
///   步、拖动实时生效不收起）；右「步进栏」＝栏头（「倍速步进」+ 生效时
///   「已启用」）+ 预设列表/编辑器，内容超高在栏内滚动。
/// - 会话内记忆：气泡关闭再打开样子一致；不落盘（持久化归
///    的预设 JSON seam）。
/// - 步进启用时倍速栏（速选/历史/标题/滑条）不置灰——面板始终可操作，
///   改倍速经既有 [SpeedControlModel.setRate]（模型级互斥保留：手动 setRate
///   停步进）。
/// - 锚定由宿主负责（CompositedTransformTarget/Follower + 点气泡外收起
///   的遮罩）；宿主对居中结果统一做水平钳制
///   （[speedBubbleClampShift]）。
library;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// _RenderBubbleClampShift 需要 RenderProxyBox / BoxHitTestResult。
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text_extent.dart';
import '../help/content_registry.dart'
    show
        badgeAvSyncUnitId,
        badgeBeatPromptUnitId,
        badgeSpeedUnitId,
        speedStepColumnAnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor;
import '../help/guide_state.dart'
    show
        currentGuideStepProvider,
        guideSessionProvider,
        onboardingStorageProvider;
import 'av_sync_bubble.dart';
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'beat_alignment_panel.dart';
import 'beat_bubble_theme.dart';
import 'beat_density_panel.dart';
import 'beat_prompt_panel.dart';
import 'bubble_reflow.dart';
import '../beat_track_state/beat_track_state.dart'
    show beatAlignPreviewOffsetProvider, beatDensityPreviewProvider;
import 'window_keyboard_metrics.dart';
import '../player_session/player_session.dart';
import 'speed_control.dart';
import 'speed_step.dart';
import 'speed_step_preset.dart';
import 'speed_step_preset_store.dart';
import 'speed_step_entry.dart';
import 'visual_tokens.dart';

/// 气泡模式（倍速设置 / 节拍提示），节拍提示并入同一锚定气泡互斥会话；
/// 音画同步、节拍对齐与节拍倍频气泡同会话互斥单开。节拍对齐气泡与节拍提示
/// 气泡锚**同一入口链接**；再点「节拍提示」工具即切回节拍提示气泡；节拍
/// 倍频气泡同款——与节拍提示气泡互斥单开、锚**同一入口链接**。
enum SpeedBubbleMode { speed, beat, beatAlign, beatDensity, avSync }

/// 节拍侧气泡判定（**唯一来源**）：节拍提示、节拍对齐与节拍
/// 倍频气泡共享
/// 同一入口链接、同一「关闭/切走即弃未应用预览」语义、同一钳位兜底缩放
/// ——凡「哪些模式算节拍侧」的判断都走本 getter，新增节拍侧气泡只
/// 改这里。
extension SpeedBubbleModeBeatSide on SpeedBubbleMode {
  bool get isBeatSide =>
      this == SpeedBubbleMode.beat ||
      this == SpeedBubbleMode.beatAlign ||
      this == SpeedBubbleMode.beatDensity;
}

/// 整泡等比缩小兜底的参与模式（**唯一来源**）：节拍侧气泡与
/// 倍速气泡在可用宽不足时整泡等比缩小（下限 [bubbleMinScale]）；其余非
/// 节拍侧模式只做水平钳制。
extension SpeedBubbleModeScaleFallback on SpeedBubbleMode {
  bool get usesScaleFallback =>
      isBeatSide || this == SpeedBubbleMode.speed;
}

/// 气泡会话内状态（不落盘，78）。
class SpeedBubbleSessionState {
  const SpeedBubbleSessionState({
    this.open,
    this.rateSnapshot,
  });

  /// 当前展开的气泡（null = 全部收起）；单值保证倍速/步进互斥。
  final SpeedBubbleMode? open;

  /// 倍速气泡打开时的倍速快照：关闭时若最终
  /// 倍速相对快照变化才记一次历史；不随气泡内容展示。
  final double? rateSnapshot;
}

/// 气泡会话状态模型（会话内记忆，provider 存活期 = 应用会话，跨气泡
/// 开合与控制层收起保持）。
class SpeedBubbleSession extends Notifier<SpeedBubbleSessionState> {
  @override
  SpeedBubbleSessionState build() {
    // 邻居自收尾：气泡**听模式值**自我收尾——
    // 控制层展开位边沿（进 / 退编辑面）即收起已展开的气泡，与原进入 /
    // 退出两个调用点上的手写关包逐位等效（同走 [close]：历史提交、对齐
    // 预览丢弃、校准会话退出语义不变）。依赖方向单向：气泡侧 → 模式库。
    ref.listen(playerSessionProvider, (previous, next) {
      if (previous == null) return;
      if (previous.controlOpen != next.controlOpen && state.open != null) {
        close();
      }
    });
    return const SpeedBubbleSessionState();
  }

  /// 打开某模式气泡（打开新模式自动替换旧模式——互斥）。展开区状态
  /// （编辑值）不重置——关闭再开样子一致。
  ///
  /// 打开倍速气泡时记录倍速快照；离开倍速气泡（收起或切到其它
  /// 步进）时按「快照 → 比对」提交历史。离开节拍侧气泡（节拍提示／节拍
  /// 对齐）时丢弃对齐预览（不自动应用）。离开音画同步气泡即显式取消校准会话（空白关闭/收起/
  /// 切其它工具同口径，不依赖气泡内容卸载时序）。
  void open(SpeedBubbleMode mode) {
    // 防御（审查）：同模式重复 open 视为无操作——beat→beat 不误清
    // 预览；现入口均为 toggle，不触发。
    if (mode == state.open) return;
    _commitHistoryIfLeavingSpeed();
    _discardBeatPreviewIfLeaving();
    _cancelAvSyncIfLeaving();
    if (mode == SpeedBubbleMode.speed) {
      state = SpeedBubbleSessionState(
        open: mode,
        rateSnapshot: ref.read(speedControlProvider).manualRate,
      );
    } else {
      state = SpeedBubbleSessionState(open: mode);
    }
    _triggerGuideUnit(mode);
  }

  /// 逐栏走查单元的触发：气泡打开 = 对应功能被真正使用——全部
  /// 打开路径（编辑态工具、观看态入口、数拍浮层工具）都经本会话单点记入，
  /// 不在各入口散写。节拍对齐 / 节拍倍频两个独立气泡不在走查范围，不触达。
  void _triggerGuideUnit(SpeedBubbleMode mode) {
    final unitId = _guideUnitIdOf(mode);
    if (unitId == null) return;
    ref.read(guideSessionProvider.notifier).trigger(unitId);
  }

  /// 用户把气泡关掉 = 逐栏走查收场并置位：与引导宿主的
  /// `skipGuideUnit`（跳过 = 整单元一次置位）同一收场序列，只是入口在
  /// Notifier 侧（`Ref`），无法与 WidgetRef 版共用函数体；单元已置位
  /// （走完 / 跳过过 / 收场过）时是幂等 no-op，不重写状态位。
  void _settleGuideWalkthroughOnClose(SpeedBubbleMode? mode) {
    final unitId = _guideUnitIdOf(mode);
    if (unitId == null) return;
    if (ref.read(guideSessionProvider).seen.contains(unitId)) return;
    ref.read(guideSessionProvider.notifier).markSeen(unitId);
    // 写失败静默：本会话内已收场，下次启动最多再看一次。
    unawaited(ref.read(onboardingStorageProvider).markUnitSeen(unitId));
    ref.invalidate(currentGuideStepProvider);
  }

  /// 气泡模式 → 逐栏走查单元 id；不在走查范围的模式（节拍对齐 / 节拍
  /// 倍频）返回 null。
  static String? _guideUnitIdOf(SpeedBubbleMode? mode) => switch (mode) {
        SpeedBubbleMode.speed => badgeSpeedUnitId,
        SpeedBubbleMode.beat => badgeBeatPromptUnitId,
        SpeedBubbleMode.avSync => badgeAvSyncUnitId,
        _ => null,
      };

  /// 收起气泡（展开区状态保留——关闭再开一致）。
  void close() {
    _commitHistoryIfLeavingSpeed();
    _discardBeatPreviewIfLeaving();
    _cancelAvSyncIfLeaving();
    _settleGuideWalkthroughOnClose(state.open);
    state = const SpeedBubbleSessionState();
  }

  /// 历史提交时机：倍速气泡关闭回全屏播放时，
  /// 若最终倍速相对打开快照变化才记一次（含 1.0）；气泡内滑条/输入/档位
  /// 调整不逐档记（[SpeedControlModel.setRate] 已不写历史）。
  /// 同步完成（[SpeedControlModel.recordHistory] 无内核调用），close/open
  /// 后续语句读到的一定是已提交后的历史。
  void _commitHistoryIfLeavingSpeed() {
    if (state.open != SpeedBubbleMode.speed) return;
    final snapshot = state.rateSnapshot;
    if (snapshot == null) return;
    final control = ref.read(speedControlProvider);
    if (control.manualRate != snapshot) {
      ref.read(speedControlProvider.notifier).recordHistory(control.manualRate);
    }
  }

  /// 节拍侧气泡关闭语义（扩展到节拍对齐独立气泡）：离开任一节拍侧气泡
  /// （收起、切其它气泡、两气泡之间互切）即丢弃节拍对齐预览偏移
  /// （不自动应用）。
  void _discardBeatPreviewIfLeaving() {
    if (state.open?.isBeatSide != true) return;
    ref.read(beatAlignPreviewOffsetProvider.notifier).set(null);
    // 节拍倍频预览同一组语义：离开任一节拍侧气泡即弃。
    ref.read(beatDensityPreviewProvider.notifier).set(null);
  }

  /// 校准会话显式退出：离开音画
  /// 同步气泡（空白关闭遮罩 / 收起 / 互斥切其它工具）即取消校准会话——
  /// 丢弃试听值 + 还原播放，同一条模块退出路径；气泡内容 `dispose` 仅
  /// 兜底（cancel 对非活跃会话无害 no-op）。
  void _cancelAvSyncIfLeaving() {
    if (state.open != SpeedBubbleMode.avSync) return;
    unawaited(ref.read(avSyncCalibrationSessionProvider.notifier).cancel());
  }
}

/// 气泡会话状态注入点。
final speedBubbleSessionProvider =
    NotifierProvider<SpeedBubbleSession, SpeedBubbleSessionState>(
      SpeedBubbleSession.new,
    );

/// 气泡宿主接线（两宿主共享，消除接线重复）：点气泡外收起的
/// 遮罩 + [CompositedTransformFollower] 锚定的 [SpeedBubble]。
///
/// 作为宿主 Stack 的**直接子级**使用（内部 Positioned.fill 要求最近的
/// RenderObject 祖先是宿主 Stack）。开关状态唯一来源为
/// [speedBubbleSessionProvider]：open 为 null 时整层不渲染。
class SpeedBubbleHost extends ConsumerStatefulWidget {
  const SpeedBubbleHost({
    super.key,
    required this.linkFor,
    required this.targetAnchor,
    required this.followerAnchor,
    this.offset = Offset.zero,
  });

  /// 各模式气泡锚定到的 LayerLink（宿主持有，配 CompositedTransformTarget）。
  final LayerLink Function(SpeedBubbleMode mode) linkFor;

  /// 宿主两处现用中心对齐：编辑态（图标下方）
  /// target bottomCenter / follower topCenter；观看态（胶囊上方）
  /// target topCenter / follower bottomCenter。居中放不下时由
  /// 水平钳制平移进屏。
  final Alignment targetAnchor;
  final Alignment followerAnchor;
  final Offset offset;

  @override
  ConsumerState<SpeedBubbleHost> createState() => _SpeedBubbleHostState();
}

class _SpeedBubbleHostState extends ConsumerState<SpeedBubbleHost> {
  /// Esc 收起焦点：气泡开着时宿主层自动
  /// 持焦，键盘用户按 Esc 即收起；关层后整层卸载、焦点随节点释放。
  final FocusNode _escFocus = FocusNode();

  @override
  void dispose() {
    _escFocus.dispose();
    super.dispose();
  }

  void _onKey(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      ref.read(speedBubbleSessionProvider.notifier).close();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(speedBubbleSessionProvider).open;
    if (open == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: KeyboardListener(
        focusNode: _escFocus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          children: [
            Positioned.fill(
              child: BubbleOutsideTapScrim(
                key: const Key('speed_bubble_scrim'),
                onTap: ref.read(speedBubbleSessionProvider.notifier).close,
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: widget.linkFor(open),
              targetAnchor: widget.targetAnchor,
              followerAnchor: widget.followerAnchor,
              offset: widget.offset,
              showWhenUnlinked: false,
              // 水平钳制：居中矩形超屏时水平
              // 平移进屏——观看态胶囊与编辑态近右缘工具图标统一走此路径。
              // 非 const：宿主重建（模式/锚点变化）时经 didUpdateWidget
              // 重算钳制。+ ：节拍侧气泡与倍速气泡
              // （[SpeedBubbleModeScaleFallback]）叠加兜底等比缩小（下限
              // 0.8×）；avSync 仍只平移。
              child: _BubbleClamp(
                scaleFallback: open.usesScaleFallback,
                child: const SpeedBubble(),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}

/// 气泡水平钳制留边（屏幕左右缘最少留 8dp）。
const double speedBubbleScreenMargin = 8;

/// 气泡可用屏宽（逻辑像素）唯一来源：两栏排布决策与水平钳制/兜底缩放同取
/// 此处（[MediaQuery] 依赖使横竖屏切换自动重排）。
double speedBubbleScreenWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width;

/// 气泡可用屏高（逻辑像素）：两轴钳位的竖直方向同源取值。
double speedBubbleScreenHeight(BuildContext context) =>
    MediaQuery.sizeOf(context).height;

/// 气泡竖直钳位平移量（纯函数 seam，与
/// [speedBubbleClampShift] 对称）：按锚点排出气泡矩形（上缘
/// [bubbleTop]、高 [bubbleHeight]）后，若底缘超出屏内（底缘 ≤ 屏高 −
/// [margin]）则返回竖直平移量（负 = 向上），否则 0。气泡比屏还高时贴上
/// 留边（底缘尽力而为）。
double speedBubbleVerticalClampShift({
  required double bubbleTop,
  required double bubbleHeight,
  required double screenHeight,
  double margin = speedBubbleScreenMargin,
}) {
  var dy = 0.0;
  final bottom = bubbleTop + bubbleHeight;
  if (bottom > screenHeight - margin) dy = screenHeight - margin - bottom;
  final shiftedTop = bubbleTop + dy;
  if (shiftedTop < margin) dy = margin - bubbleTop;
  return dy;
}

/// 气泡水平钳制平移量（纯函数 seam）：
/// 按锚点居中排出气泡矩形（左缘 [bubbleLeft]、宽 [bubbleWidth]）后，
/// 若超出屏内（左右缘各留 [speedBubbleScreenMargin]）则返回水平平移量
/// （负 = 向左、正 = 向右），否则 0（居中观感保持，仅放不下才平移）。
/// 气泡比屏还宽时贴左留边（右缘尽力而为）。
double speedBubbleClampShift({
  required double bubbleLeft,
  required double bubbleWidth,
  required double screenWidth,
  double margin = speedBubbleScreenMargin,
}) {
  var dx = 0.0;
  final right = bubbleLeft + bubbleWidth;
  if (right > screenWidth - margin) dx = screenWidth - margin - right;
  final shiftedLeft = bubbleLeft + dx;
  if (shiftedLeft < margin) dx = margin - bubbleLeft;
  return dx;
}

/// 气泡兜底缩放下限（0.8×；0.8× 后仍放不下才允许
/// 水平裁切。节拍侧与倍速气泡共用）。
const double bubbleMinScale = 0.8;

/// 气泡钳位适配（水平 + 竖直两轴；纯函数 seam，节拍侧与倍速气泡接线）：
/// 中心锚点排出气泡（左缘
/// [bubbleLeft]、上缘 [bubbleTop]、自然宽 [bubbleWidth]、自然高
/// [bubbleHeight]）后，返回 (dx, dy, scale)——dx 为水平平移量（可用宽
/// （[screenWidth] − 2×[margin]）不足且 [scaleFallback] 时整泡 `scale`
/// 等比缩小至恰好进屏（下限 [bubbleMinScale]），钳位按缩后有效宽计算，
/// 0.8× 后仍放不下时贴左留边、右缘允许裁切），dy 为竖直平移量（底缘
/// ≤ 屏高 − [margin]，比屏还高时贴上留边、底缘尽力而为），scale 为整泡
/// 等比缩放系数。竖直**不**参与缩放兜底——缩放兜底仍只服务「可用宽不足」
/// （[usesScaleFallback] 的参与模式集合不变），竖直一律平移解决。传
/// [bubbleTop]/[bubbleHeight]/[screenHeight] 时竖直钳位生效，否则 dy = 0
/// （既有水平用例口径不变）。
({double dx, double dy, double scale}) bubbleClampFit({
  required double bubbleLeft,
  required double bubbleWidth,
  required double screenWidth,
  double bubbleTop = 0,
  double bubbleHeight = 0,
  double? screenHeight,
  bool scaleFallback = true,
  double margin = speedBubbleScreenMargin,
  double minScale = bubbleMinScale,
}) {
  final avail = screenWidth - 2 * margin;
  var scale = 1.0;
  if (scaleFallback && bubbleWidth > avail) {
    scale = math.max(minScale, avail / bubbleWidth);
  }
  final effectiveWidth = bubbleWidth * scale;
  final center = bubbleLeft + bubbleWidth / 2;
  final dx = speedBubbleClampShift(
    bubbleLeft: center - effectiveWidth / 2,
    bubbleWidth: effectiveWidth,
    screenWidth: screenWidth,
    margin: margin,
  );
  final dy = (screenHeight != null && bubbleHeight > 0)
      ? speedBubbleVerticalClampShift(
          bubbleTop: bubbleTop,
          bubbleHeight: bubbleHeight,
          screenHeight: screenHeight,
          margin: margin,
        )
      : 0.0;
  return (dx: dx, dy: dy, scale: scale);
}

/// 气泡两轴钳位包装（水平钳制，扩成
/// 水平 + 竖直）：帧末量取气泡全局矩形，超出屏内（四边留边
/// [speedBubbleScreenMargin]）时平移进屏；竖直规则 = 底缘 ≤ 屏高 − 留边，
/// 比屏还高时贴上留边、底缘尽力而为。
/// + [scaleFallback]（节拍侧与倍速气泡）下可用宽不足时叠加
/// 整泡等比缩小（[bubbleClampFit]，下限 [bubbleMinScale]）。
///
/// - **量测时机**：postFrameCallback（Follower 变换在首帧 paint 中尚未
///   建立，paint 期量取恒得 0）；量取的是本包装盒（= 锚定排布后的未平移
///   位置，平移只作用于子级）→ setState 不改变量测、无反馈振荡。
/// - **首帧不可见**：量测完成前 [Opacity] 0 占位——气泡出现的第一帧即
///   钳制到位，无「先溢出再回拉」的一帧闪烁。
/// - **重算触发**（各有职责，非冗余）：initState（首次）/ didUpdateWidget
///   （宿主重建：模式切换、锚点 link 变化）/ 子级尺寸变化
///   （[SizeChangedLayoutNotifier]：步进展开区等宽度变化）/ 窗口 metrics
///   变化（旋转、键盘）。命中随 Transform 生效 → 滑条等最右内容可达可拖。
class _BubbleClamp extends StatefulWidget {
  const _BubbleClamp({required this.child, this.scaleFallback = false});

  final Widget child;

  ///  + ：可用宽不足时整泡等比缩小兜底（下限
  /// [bubbleMinScale]）；节拍侧与倍速气泡开启
  /// （[SpeedBubbleModeScaleFallback]），avSync 不受影响。
  final bool scaleFallback;

  @override
  State<_BubbleClamp> createState() => _BubbleClampState();
}

class _BubbleClampState extends State<_BubbleClamp>
    with WidgetsBindingObserver {
  double _dx = 0;
  double _dy = 0;
  double _scale = 1;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleRecompute();
  }

  @override
  void didUpdateWidget(_BubbleClamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleRecompute();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    _scheduleRecompute();
  }

  void _scheduleRecompute() {
    // 帧末量取（本帧布局/绘制完成后；Follower 变换已就位）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return;
      final screenWidth = speedBubbleScreenWidth(context);
      if (screenWidth <= 0) return;
      final screenHeight = speedBubbleScreenHeight(context);
      final global = box.localToGlobal(Offset.zero);
      final left = global.dx;
      final top = global.dy;
      final width = box.size.width;
      final height = box.size.height;
      final ({double dx, double dy, double scale}) fit = bubbleClampFit(
        bubbleLeft: left,
        bubbleTop: top,
        bubbleWidth: width,
        bubbleHeight: height,
        screenWidth: screenWidth,
        screenHeight: screenHeight,
        scaleFallback: widget.scaleFallback,
      );
      final nextDx = fit.dx;
      final nextDy = fit.dy;
      final nextScale = fit.scale;
      if (nextDx != _dx || nextDy != _dy || nextScale != _scale || !_measured) {
        setState(() {
          _dx = nextDx;
          _dy = nextDy;
          _scale = nextScale;
          _measured = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _BubbleClampShift(
      // 水平钳制平移「绘制与命中一致」——此前用 Transform.translate
      // 只平移绘制，命中仍按钳制前矩形判定（外层代理框自身 size.contains
      // 门在平移前拦截），气泡锚点落在屏缘时出现「看得见点不中」。改为
      // 最外层自定义绘制/命中同步平移（放在 Opacity 之外，绕过其未平移的
      // size 门）。
      dx: _dx,
      dy: _dy,
      child: Opacity(
        // 首帧量测完成前不可见：出现即钳制到位（无溢出闪烁）。
        opacity: _measured ? 1 : 0,
        child: Transform.scale(
          scale: _scale,
          alignment: Alignment.center,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleRecompute();
              return false;
            },
            child: SizeChangedLayoutNotifier(child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 水平钳制平移的绘制/命中一致代理——把子树平移 [dx] 绘制，命中
/// 测试按同一平移反解（不受本框 size 门限制，语义与
/// [RenderFollowerLayer] 一致）。布局尺寸仍取子树原尺寸（钳制不改布局，
/// follower 锚点几何不受影响）。
class _BubbleClampShift extends SingleChildRenderObjectWidget {
  const _BubbleClampShift({
    required this.dx,
    required this.dy,
    super.child,
  });

  final double dx;
  final double dy;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBubbleClampShift(dx, dy);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderBubbleClampShift renderObject,
  ) {
    renderObject
      ..dx = dx
      ..dy = dy;
  }
}

class _RenderBubbleClampShift extends RenderProxyBox {
  _RenderBubbleClampShift(this._dx, this._dy);

  /// 钳位平移量：绘制、命中（[hitTestChildren]）与几何查询
  /// （[applyPaintTransform]）三处共用同一对取值；改变即 [markNeedsPaint]
  /// ——否则绘制会停在旧平移上，而命中已按新平移判定，出现「看得见的
  /// 地方点不动」（钳位值在首帧量测后变化时必然经过这里）。
  double _dx;
  double _dy;

  double get dx => _dx;
  set dx(double value) {
    if (_dx == value) return;
    _dx = value;
    markNeedsPaint();
  }

  double get dy => _dy;
  set dy(double value) {
    if (_dy == value) return;
    _dy = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset + Offset(dx, dy));
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    // 供 localToGlobal/getRect 等几何查询取到与绘制/命中一致的平移。
    transform.translateByDouble(dx, dy, 0, 1);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // 与绘制对齐：不做本框 size 门（钳位平移后命中点可落在框外），
    // 直接按平移后的坐标命中子树。
    return hitTestChildren(result, position: position);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return result.addWithPaintOffset(
      offset: Offset(dx, dy),
      position: position,
      hitTest: (result, transformed) =>
          super.hitTestChildren(result, position: transformed),
    );
  }
}


/// 倍速气泡组件（内容组件；锚定与开关由 [SpeedBubbleHost] 接线）。
class SpeedBubble extends ConsumerWidget {
  const SpeedBubble({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(speedBubbleSessionProvider);
    switch (session.open) {
      case SpeedBubbleMode.speed:
        // 倍速气泡（双栏 + 竖排）：
        // 左「倍速栏」＝倍速面板，右「步进栏」＝步进预设列表/编辑器；
        // 两栏并排或上下堆叠、中间一条满高分隔线（方向随排布）。内容宽由
        // [_MergedSpeedContent] 的两栏几何自身决定，故 maxWidth 不设兜底上限
        //（不再另处量测，几何单源）。
        return _scaffold(const _MergedSpeedContent(), maxWidth: double.infinity);
      case SpeedBubbleMode.beat:
        // 节拍提示气泡：三段并排横屏重排——内容宽超过共享
        // maxWidth（300）上限，需放宽气泡内容 maxWidth 兜底
        // （内容自适应列宽；速/步/avSync 仍用共享上限）。第三列为
        // 「节拍矫正」菜单列。并排/堆叠判定复用气泡族
        // 共用纯件（[beatPromptBubbleLayout]）——竖屏放不下并排即三段堆叠，
        // 内容宽收为最宽段，气泡总宽随之收窄。
        final beatLayout = beatPromptBubbleLayout(
          availableWidth:
              speedBubbleScreenWidth(context) - 2 * speedBubbleScreenMargin,
          sideBySideBubbleWidth:
              BeatPromptBubbleContent.contentWidth +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
        );
        return _beatScaffold(
          BeatPromptBubbleContent(stacked: beatLayout.stacked),
          maxWidth:
              beatLayout.contentWidth +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
        );
      case SpeedBubbleMode.beatAlign:
        // 节拍对齐独立气泡：原「节拍提示」第三列整组原样迁入
        // ——内容定宽（与原列宽同值），气泡宽随之恒定。
        return _beatScaffold(
          const BeatAlignmentBubbleContent(),
          maxWidth:
              BeatAlignmentBubbleContent.contentWidth +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
        );
      case SpeedBubbleMode.beatDensity:
        // 节拍倍频独立气泡：形状复用节拍对齐那套，内容定宽
        //（与对齐气泡同值），气泡宽随之恒定。
        return _beatScaffold(
          const BeatDensityBubbleContent(),
          maxWidth:
              BeatDensityBubbleContent.contentWidth +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
        );
      case SpeedBubbleMode.avSync:
        // 音画同步 V2 气泡内容：设备名 + 延迟滑条 + 读数/重置
        // + v2 看+听参考区。
        return _scaffold(const AvSyncBubbleContent());
      case null:
        return const SizedBox.shrink();
    }
  }

  /// 气泡外观：圆角深色浮层，宽随内容收缩（maxWidth
  /// 仅兜底，常规尺寸由内容决定——左区不再 Expanded 撑满）；键盘弹出时随
  /// viewInsets 压缩高度。整
  /// 面板单气泡完整显示、**内容量上限内永不滚动**——以紧凑间距 + 历史展示
  /// 上限兜底保证内容恒小于可用高度，滚动容器仅作键盘压缩等极端可用高度
  /// 下的兜底（上限内 maxScrollExtent = 0）。
  Widget _scaffold(Widget child, {double? maxWidth}) {
    // 内容宽上限（速/步/avSync 共享 300 上限；节拍提示三段
    // 并排放宽到 [BeatPromptBubbleContent.contentWidth]）。
    final contentMaxWidth = maxWidth ?? speedBubbleMaxWidth;
    // 键盘压缩取数走共用件（坑注释见其文档）。
    return WindowMetricsWatcher(
      builder: (context, viewData) {
        final maxHeight = math.max(
          120.0,
          viewData.size.height * 0.7 - viewData.viewInsets.bottom,
        );
        return Material(
          key: const Key('speed_bubble'),
          color: kSpeedBubbleScrimColor,
          borderRadius: BorderRadius.circular(12),
          elevation: 6,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              // maxWidth 约束放在滚动视口**内侧**——SingleChildScrollView
              // 会撑满交叉轴可用宽，maxWidth 在外侧时气泡恒撑满 300；移到内侧
              // 后内容随内容收缩（≈171），maxWidth 仅兜底。
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: contentMaxWidth),
                child: Padding(
                  // 盒边距：左 8 / 右 12——不对称（右区
                  // 轨道为实心重视觉元素、贴边观感稳）；上 8 / 下 12（整高
                  // = 内容 240 + 20 ≈ 260）。
                  padding: const EdgeInsets.fromLTRB(
                    speedBubblePaddingLeft,
                    speedBubblePaddingTop,
                    speedBubblePaddingRight,
                    speedBubblePaddingBottom,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 节拍侧气泡壳：把气泡暗色主题的正文色交给内容 `DefaultTextStyle`。
  ///
  /// 壳 [Material] 的 `DefaultTextStyle` 取**环境主题**（App 亮色）的
  /// `bodyMedium`，而各节拍气泡内容的暗色 `Theme` 包在它下层——内容里不显式
  /// 设色的 `Text` 会取到亮色主题的近黑正文色，画在近黑气泡底上即成「置灰」
  /// 不可读（按钮/Switch 读 `Theme` 故不受影响）。这里把与底色相配的正文色
  /// 显式压在内容之上，气泡内未设色的文字一律可读。
  ///
  /// 走独立 `DefaultTextStyle` 而非 [Material.textStyle]：后者经
  /// `AnimatedDefaultTextStyle` 在气泡模式切换（速 ↔ 节拍）时插值，
  /// 两个主题的 `bodyMedium` `inherit` 取值不同会触发插值断言。
  Widget _beatScaffold(Widget child, {double? maxWidth}) => _scaffold(
    DefaultTextStyle(
      style: beatBubbleContentTheme.textTheme.bodyMedium!,
      child: child,
    ),
    maxWidth: maxWidth,
  );
}

/// 气泡最大宽（maxWidth ≈ 300）。
/// 仅作兜底上限——常规尺寸由内容决定（≈171）。
const double speedBubbleMaxWidth = 300;

/// 气泡盒边距：左 8 / 右 12（不对称——右区轨道为
/// 实心重视觉元素、贴边观感稳）；上 8 / 下 12（整高 = 内容 240 + 20）。
/// 常量测试锚定。
const double speedBubblePaddingLeft = 8;
const double speedBubblePaddingRight = 12;
const double speedBubblePaddingTop = 8;
const double speedBubblePaddingBottom = 12;

/// 倍速气泡右栏「步进栏」定宽 280。
const double mergedStepColumnWidth = 280;

/// 倍速气泡栏内容高（212 = 240；派生，不独立定值）。
const double mergedBubbleColumnHeight =
    speedTitleHeight + speedTitleColumnGap + speedColumnsBlockHeight;

/// 倍速气泡总高 = 上边距 + 栏内容高 + 下边距 = 260（与今日倍速气泡同高；
/// 预设条数变化与「列表 ↔ 编辑器」切换都不改变）。
const double mergedBubbleHeight =
    speedBubblePaddingTop + mergedBubbleColumnHeight + speedBubblePaddingBottom;

/// 步进栏栏头高（标题「倍速步进」+ 生效标记「已启用」一行）。
const double mergedStepHeaderHeight = 28;

/// 倍速气泡列间距（与节拍提示气泡同口径）：1px 分隔线、线两侧各留 8 →
/// 列距 8 + 1 + 8 = 17。
const double mergedBubbleColumnSeparatorWidth = 1;
const double mergedBubbleColumnGapSide = 8;
const double mergedBubbleColumnGap =
    mergedBubbleColumnGapSide * 2 + mergedBubbleColumnSeparatorWidth;

/// 倍速气泡两栏几何（[mergedSpeedBubbleColumns] 的返回值）：`stacked` 为
/// true 时上下堆叠（竖排），否则左右并排；`stepWidth`/`speedWidth` 为步进栏
/// 与倍速栏的宽（堆叠时相等），`separatorOffset` 为分隔线中心在列距轴上的
/// 位置（并排 = 竖线中心 x、堆叠 = 横线中心 y，轴向由 `stacked` 判定），
/// `width` 为内容总宽（不含盒边距）。
typedef MergedSpeedBubbleColumns = ({
  bool stacked,
  double stepWidth,
  double speedWidth,
  double separatorOffset,
  double width,
});

/// 倍速气泡两栏几何（纯函数 seam）：并排时步进栏在
/// 左、定宽 [mergedStepColumnWidth]，倍速栏在右、取自然宽
/// [speedColumnNaturalWidth]；分隔线位置与内容总宽只此一处累计。
///
/// [availableWidth] = 屏宽 − 左右留边（气泡屏幕锚定，锚点不额外裁剪可用
/// 宽）不足以放下整个气泡（两栏内容 + 盒边距）时改为**上下堆叠**：倍速栏在
/// 上、步进栏在下，气泡内容宽回到既有 [speedBubbleMaxWidth] 上限，分隔线
/// 随之改横线。
///
/// 并排/堆叠判定的唯一来源是气泡族共用纯件 [bubbleReflowFor]：
/// 本函数只把「并排所需外宽」喂给它，不在此手写宽比较。
MergedSpeedBubbleColumns mergedSpeedBubbleColumns({
  required double speedColumnNaturalWidth,
  double availableWidth = double.infinity,
}) {
  final horizontalWidth =
      mergedStepColumnWidth + mergedBubbleColumnGap + speedColumnNaturalWidth;
  final horizontalBubbleWidth =
      horizontalWidth + speedBubblePaddingLeft + speedBubblePaddingRight;
  if (bubbleReflowFor(
        availableWidth: availableWidth,
        sideBySideWidth: horizontalBubbleWidth,
      ) ==
      BubbleReflow.sideBySide) {
    return (
      stacked: false,
      stepWidth: mergedStepColumnWidth,
      speedWidth: speedColumnNaturalWidth,
      separatorOffset: mergedStepColumnWidth + mergedBubbleColumnGapSide,
      width: horizontalWidth,
    );
  }
  return (
    stacked: true,
    stepWidth: speedBubbleMaxWidth,
    speedWidth: speedBubbleMaxWidth,
    separatorOffset: mergedBubbleColumnHeight + mergedBubbleColumnGapSide,
    width: speedBubbleMaxWidth,
  );
}

/// 标题栏高（高 24、单行不折行；容器中点 = 双列块中点
/// ——值位数变化时容器随内容伸缩、中点恒定）。
const double speedTitleHeight = 24;

/// 标题底 → 双列顶间距（纵向锚定约束④：列顶 = 标题底 + 4）。
const double speedTitleColumnGap = 4;

/// 档位单钮高（上下 padding 7 → 单钮高 32，便于触控）。
const double speedRateButtonHeight = 32;

/// 档位按钮纵向内边距（7 → 单钮高 32，便于触控；横向见
/// [rateOptionHorizontalPadding]）。仅档位按钮使用。
const double speedRateOptionVerticalPadding = 7;

/// 档位列内行距 g（**唯一纵向自由参数**，4——
/// 调松紧只动此值，列高等派生高度随之变化、对齐约束永不破坏）。
const double speedRateRowGap = 4;

/// 双列块高（派生：6×单钮 32 + 5×行距 4 = **212**；常驻列内
/// space-between 铺满）。
const double speedColumnsBlockHeight =
    6 * speedRateButtonHeight + 5 * speedRateRowGap;

/// 滑条顶相对标题顶偏移（纵向锚定约束①：滑条顶 = 标题顶 + 6）。
const double speedSliderTopOffset = 6;

/// 滑条整高超出双列块的高度的派生差（锚定约束①②联立：顶 = 标题顶
/// + 6、底 = 列底 → 滑条整高 − 列高 = 22，不独立定值；调 g 自动跟随）。
const double speedSliderColumnInset = 22;

/// 竖向滑条列（刻度尺 + 竖轨）显式固定高度：**派生值** = 双列块高 +
/// [speedSliderColumnInset] = 212 + 22 = **234**。锚定约束——顶 = 标题顶
/// + 6、底 = 双列块底：调 g 时自动跟随，对齐关系永不破坏。
const double speedSliderColumnHeight =
    speedColumnsBlockHeight + speedSliderColumnInset;

/// 竖向滑条竖轨厚度（≈28dp）。
const double speedSliderTrackThickness = 28;

/// 刻度尺列宽（竖滑条左侧常驻刻度尺——数字标签 +
/// 细分小刻度）。
const double speedRulerWidth = 26;

/// 刻度尺列与竖轨之间的间隙。
const double speedRulerGap = 4;

/// 滑条列宽（刻度尺 + 间隙 + 竖轨；倍速气泡几何左栏宽度的最后一段）。
const double speedSliderColumnWidth =
    speedSliderTrackThickness + speedRulerWidth + speedRulerGap;

/// 刻度尺刻度线宽（刻度线 6×2、贴尺右缘）。
const double speedRulerTickWidth = 6;

/// 刻度尺刻度线高（线 6×2）。
const double speedRulerTickHeight = 2;

/// 刻度大刻度数字标签样式（定位用）：字号即标签高——Text style
/// `height: 1`，行高 = 字号，标签定位按此推导，不另设魔法数。
const double _rulerLabelFontSize = 10;

/// 刻度大刻度数字标签高度（= [_rulerLabelFontSize]，style height 1）。
const double _rulerLabelHeight = _rulerLabelFontSize;

/// 档位按钮水平内边距（文字左右各 3dp、居中）。仅档位按钮使用。
const double rateOptionHorizontalPadding = 3;

/// 档位按钮字号（字号 13）。仅档位按钮使用（常量
/// 测试锚定）。
const double rateOptionFontSize = 13;

/// 步进编辑器参数行间距（3dp 紧凑值）：倍速面板组间距/列间距由
/// [speedGroupGap]（6）承担，本常量只服务步进编辑器参数行。常量测试锚定。
const double speedCompactGap = 3;

/// 倍速面板组间距 = 列间距（均为 **6**；组间不大于组内的格式塔修正由
/// 行距 g=4 < 组距 6 保证）。
const double speedGroupGap = 6;

/// 历史档位展示条数上限（整面板单气泡不滚动的
/// **兜底**——仅限制展示条数，不改历史记录语义（模型历史照常累积））。
const int speedHistoryDisplayLimit = 5;

/// 自适应列宽的布局余量：量测宽与实际排版存在浮点/取整边缘差，
/// 预留 1dp 防「×」意外换行。
const double rateOptionWidthSlack = 1;

/// 档位列宽纯函数 seam：列宽 = 最宽文本 + [rateOptionHorizontalPadding]×2 +
/// [rateOptionWidthSlack] 布局余量——文字宽度 → 按钮宽度 → 列宽度。仅用于
/// 推导**常驻列**所需列宽（常驻列内容固定，作为两列均分时的内容下限）；
/// 历史列宽度不由历史内容推导。纯函数测试锚定。[baseStyle] 传入
/// 调用处的 [DefaultTextStyle]（实际渲染会与主题样式合并，字距等影响
/// 量测——不传则按裸字号量测）。
double rateOptionColumnWidth(
  Iterable<String> labels, {
  TextStyle? baseStyle,
}) {
  var widest = 0.0;
  for (final label in labels) {
    final width = measureTextExtent(
      label,
      (baseStyle ?? const TextStyle()).merge(
        TextStyle(fontSize: rateOptionFontSize),
      ),
    ).width;
    widest = math.max(widest, width);
  }
  return widest + rateOptionHorizontalPadding * 2 + rateOptionWidthSlack;
}

/// 标题条「当前倍速」文字（量测 [measureRateTitleWidth] 与渲染
/// [_RateTitleSelect] 同源，防两处漂移）。
const String _rateTitleLabelText = '当前倍速';

/// 标题条「当前倍速」标签字号。
const double _rateTitleLabelFontSize = 12;

/// 标题条当前值文本字号 / 字重（量测与下拉控件 style 同源）。
const double _rateTitleValueFontSize = 16;
const FontWeight _rateTitleValueWeight = FontWeight.w600;

/// 标题条「当前倍速」文字与当前值控件间距（与 [_RateTitleSelect]
/// 内 Row 的间距同源）。
const double _rateTitleLabelGap = 8;

/// 标题条当前值控件（[DropdownButton] isDense）超出最宽值文本的杂项宽估算
/// 下拉箭头 + 选中项横向留白等。当前值控件会为最宽候选项预留
/// 等宽（值切换不引起控件宽变化），故左区宽以「最宽全档值文本 + 此杂项」为
/// 恒定的标题自然宽——作为左区宽下限，保证标题任何取值都不越出气泡左缘。
const double _rateTitleDropdownChrome = 26;

/// 标题行自然宽（纯函数 seam）：
/// = 「当前倍速」标签（12px）+ 间距 + 最宽候选项值文本（16px/w600，当前值
/// 控件为最宽候选项预留等宽）+ 下拉杂项宽。该宽度与当前取值无关（取值切换
/// 只改变选中值文字、不改变控件宽），作为左区宽下限恒容纳标题、永不越出
/// 气泡左缘。[baseStyle] 传入调用处的 [DefaultTextStyle]（与 _RateTitleSelect
/// 实际渲染同样式）；[textScaler] 传入调用处 MediaQuery 的缩放，使量测跟随
/// 实际渲染（防系统字体缩放下标题重新越界）。下拉杂项（箭头/留白）为图标尺
/// 寸、不随文本缩放，故不乘缩放。
///
/// 标题、档位与历史列表文本承载语义，属语义档（随系统字号）：渲染吃环境
/// 缩放，量测侧传调用处同一 `MediaQuery.textScalerOf`。
double measureRateTitleWidth({
  TextStyle? baseStyle,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  double textWidth(String text, TextStyle explicit) {
    return measureTextExtent(
      text,
      (baseStyle ?? const TextStyle()).merge(explicit),
      scaler: textScaler,
    ).width;
  }

  final labelWidth = textWidth(
    _rateTitleLabelText,
    const TextStyle(fontSize: _rateTitleLabelFontSize),
  );
  // 最宽候选项值文本（全档 0.1–2.0 步 0.05 的格式化文本；如 0.05x/1.05x）。
  var widestValue = 0.0;
  for (final rate in rateCandidates()) {
    final w = textWidth(
      '${formatRate(rate)}x',
      const TextStyle(
        fontSize: _rateTitleValueFontSize,
        fontWeight: _rateTitleValueWeight,
      ),
    );
    if (w > widestValue) widestValue = w;
  }
  return labelWidth + _rateTitleLabelGap + widestValue + _rateTitleDropdownChrome;
}

/// 刻度尺单个刻度（纯函数 seam）。
class SpeedRulerTick {
  const SpeedRulerTick({
    required this.value,
    required this.major,
    required this.label,
  });

  /// 刻度对应的滑条取值。
  final double value;

  /// 是否大刻度（带数字标签）。
  final bool major;

  /// 大刻度数字标签（如 `0.5`）；小刻度为 null。
  final String? label;
}

/// 刻度尺刻度/标签布局（+ 纯函数 seam）：
/// 在 [min, max] 值域内按 [minorEvery]（默认 0.1）生成细分小刻度（无字）；
/// 带文字标签的大刻度 = **落在细分网格上的取值范围端点（最低 [min]/最高
/// [max]）** 叠加 [majorEvery]（默认 0.5）主刻度（如 0.5/1.0）——即竖滑条
/// 刻度标签集 **0.1×（最低）/0.5×/1.0×/1.5×（最高）**，与滑条取值范围
/// 同步；升序、去重、全部落在值域内——标签纵位由调用方按滑条同一线性映射
/// 摆放，实现「刻度与滑条取值同步」。
List<SpeedRulerTick> speedRulerTicks({
  required double min,
  required double max,
  double majorEvery = 0.5,
  double minorEvery = 0.1,
}) {
  final ticks = <SpeedRulerTick>[];
  final first = (min / minorEvery).ceil();
  final last = (max / minorEvery).floor();
  const eps = 1e-6;
  for (var k = first; k <= last; k++) {
    final value = double.parse((k * minorEvery).toStringAsFixed(2));
    // 端点（最低/最高值）与 majorEvery 主刻度都带文字标签；其余细分小刻度
    // 无字。端点用近似比较（0.1 网格值相对 min/max 的误差 < 1e-6）。
    final atMin = (value - min).abs() < eps;
    final atMax = (max - value).abs() < eps;
    final frac = value / majorEvery;
    final onMajor = (frac - frac.roundToDouble()).abs() < eps;
    final isMajor = atMin || atMax || onMajor;
    ticks.add(
      SpeedRulerTick(
        value: value,
        major: isMajor,
        label: isMajor ? value.toStringAsFixed(1) : null,
      ),
    );
  }
  return ticks;
}

/// 刻度尺纵位线性映射的唯一实现：[value] 在 [min]/[max] 值域内
/// 映射为「自顶部起算的高度比例」（min 在下 → 比例 1，max 在上 → 比例 0）。
/// 标签 Positioned 纵位与 [_RulerTicksPainter] 刻度线绘制都经此函数换算，
/// 防两处公式漂移（刻度列定高修复：位置与取值映射不变）。
double speedRulerTopFraction({
  required double value,
  required double min,
  required double max,
}) {
  return 1 - ((value - min) / (max - min)).clamp(0.0, 1.0);
}

/// 刻度尺刻度线几何纯函数：
/// 线 **6×2**、贴尺右缘（右缘 = 刻度尺宽，贴近滑条一侧）；[top] 为分度值
/// 纵位（线中心）——矩形顶 = top − 1（**1px 线高补偿**：2px 线高的中心
/// 精确落在分度值位置）。纯函数测试锚定。大/小刻度同几何（6×2 统一，
/// 仅由文字标签区分）。
Rect speedRulerTickRect({required double rulerWidth, required double top}) {
  return Rect.fromLTWH(
    rulerWidth - speedRulerTickWidth,
    top - speedRulerTickHeight / 2,
    speedRulerTickWidth,
    speedRulerTickHeight,
  );
}

/// 倍速栏（左栏）宽度度量（纯度量 seam，倍速气泡几何与 [_SpeedContent] 实际
/// 排版共用同一处，防两处漂移）：左区宽 = max(标题行自然宽, 两列最小宽和 +
/// 列距)；两列等分左区宽。
({double bodyWidth, double columnWidth}) speedPanelWidths(
  BuildContext context,
) {
  final measuringStyle = DefaultTextStyle.of(context).style;
  final residentNeeded = rateOptionColumnWidth(
    [for (final rate in commonSpeeds) '${formatRate(rate)}x'],
    baseStyle: measuringStyle,
  );
  final titleWidth = measureRateTitleWidth(
    baseStyle: measuringStyle,
    textScaler: MediaQuery.textScalerOf(context),
  );
  final bodyWidth = math.max(titleWidth, 2 * residentNeeded + speedGroupGap);
  return (
    bodyWidth: bodyWidth,
    columnWidth: (bodyWidth - speedGroupGap) / 2,
  );
}

/// 倍速栏（左栏）自然宽 = 左区宽 + 列距 + 滑条列宽（倍速气泡几何左栏取此值）。
double speedPanelNaturalWidth(BuildContext context) {
  final widths = speedPanelWidths(context);
  return widths.bodyWidth + speedGroupGap + speedSliderColumnWidth;
}

/// 倍速气泡内容（双栏 + 竖排）：步进
/// 栏＝原步进预设列表/编辑器（[_StepColumn]），倍速栏＝原倍速面板
/// （[_SpeedContent]）。
///
/// - **并排**（横屏可用宽足够）：步进栏在左（定宽 280、定高 240）、倍速栏在
///   右（自然宽），两栏顶对齐、中间一条满高竖分隔线，气泡总高恒 260；
/// - **堆叠**（竖屏可用宽不足以并排）：倍速栏在上、步进栏在下，分隔线改横线，
///   气泡宽回到既有 300 上限、高随内容（超高由 [_scaffold] 的整体滚动兜底）。
///
/// 两态沿用同一子级结构与类型（仅方向/尺寸/滚动参数变化），横竖屏切换时
/// 步进栏的选中预设、步进启用态与展开中的预设编辑器不丢。
class _MergedSpeedContent extends ConsumerWidget {
  const _MergedSpeedContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layout = mergedSpeedBubbleColumns(
      speedColumnNaturalWidth: speedPanelNaturalWidth(context),
      availableWidth:
          speedBubbleScreenWidth(context) - 2 * speedBubbleScreenMargin,
    );
    // 倍速栏：堆叠时栏宽（300）大于面板自然宽，面板在栏内居中；并排时栏宽
    // 即自然宽，本层无效果。倍速栏不承载引导锚点（锚点只在步进栏上）：
    // 并排与堆叠共用同一栏 widget，无需按方位分支。
    final speedColumn = SizedBox(
      key: const Key('speed_rate_column'),
      width: layout.speedWidth,
      child: const Align(child: _SpeedContent()),
    );
    final stepColumn = _StepColumn(
      // 稳定 key：并排与堆叠的**次序不同**（见下），横竖屏切换会重排 Flex
      // 子级——无 key 时元素按位次匹配失败被重建，展开中的预设编辑器等栏内
      // 状态会被丢弃。
      key: const Key('speed_step_column_slot'),
      width: layout.stepWidth,
      stacked: layout.stacked,
    );
    // 并排：步进栏在左、倍速栏在右；堆叠：倍速栏在上、步进栏在下。
    final (first, second) = layout.stacked
        ? (speedColumn, stepColumn)
        : (stepColumn, speedColumn);
    return SizedBox(
      // 内容总宽由纯函数单源给出（两栏宽 + 列距即此值）。
      width: layout.width,
      child: Flex(
        key: const Key('speed_merged_columns'),
        direction: layout.stacked ? Axis.vertical : Axis.horizontal,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [first, _MergedBubbleSeparator(layout: layout), second],
      ),
    );
  }
}

/// 倍速气泡两栏间的分隔线（并排 = 竖线，堆叠 = 横线）：占据列距
/// [mergedBubbleColumnGap]，线画在 [MergedSpeedBubbleColumns.separatorOffset]
/// 处（换算为盒内偏移）；列不必等高，并排时线高取栏内容高
/// [mergedBubbleColumnHeight]。
class _MergedBubbleSeparator extends StatelessWidget {
  const _MergedBubbleSeparator({required this.layout});

  final MergedSpeedBubbleColumns layout;

  @override
  Widget build(BuildContext context) {
    final boxStart = layout.stacked
        ? mergedBubbleColumnHeight
        : layout.stepWidth;
    return SizedBox(
      key: const Key('speed_merged_separator'),
      width: layout.stacked ? layout.width : mergedBubbleColumnGap,
      height: layout.stacked ? mergedBubbleColumnGap : mergedBubbleColumnHeight,
      child: CustomPaint(
        painter: _MergedBubbleSepPainter(
          stacked: layout.stacked,
          lineOffset: layout.separatorOffset - boxStart,
        ),
      ),
    );
  }
}

/// 步进栏（并排时的左栏、堆叠时的下栏）：
/// 栏头「倍速步进」+ 步进生效时右端「已启用」标记；其下为预设列表 / 预设
/// 编辑器。
///
/// [stacked] 为 false（并排）时栏定高、内容超出在**栏内**滚动（倍速栏不随之
/// 滚动），气泡几何恒定；为 true（堆叠）时栏随内容自然高，超高由气泡整体
/// 滚动兜底。
class _StepColumn extends ConsumerWidget {
  const _StepColumn({
    super.key,
    required this.width,
    required this.stacked,
  });

  /// 栏宽（并排 = 左栏定宽；堆叠 = 两栏共同内容宽）。
  final double width;

  /// 是否上下堆叠（唯一来源 = [mergedSpeedBubbleColumns] 的判定）。
  final bool stacked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stepEnabled = ref.watch(speedControlProvider).stepEnabled;
    return GuideAnchor(
      // 锚点包装：倍速步进角标锚在步进栏上；气泡打开时挂载。
      anchorKey: speedStepColumnAnchorKey,
      child: SizedBox(
        key: const Key('speed_step_column'),
        width: width,
        height: stacked ? null : mergedBubbleColumnHeight,
      child: Column(
        mainAxisSize: stacked ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: mergedStepHeaderHeight,
            child: Row(
              key: const Key('speed_step_column_header'),
              children: [
                const Text(
                  '倍速步进',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (stepEnabled)
                  Container(
                    key: const Key('speed_step_enabled_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: kHighlightAmber.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '已启用',
                      style: TextStyle(color: kHighlightAmber, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          Flexible(
            // 并排：吃满栏内剩余高（栏内滚动）；堆叠：随内容自然高（整泡
            // 滚动归 [_scaffold]）。
            fit: stacked ? FlexFit.loose : FlexFit.tight,
            child: SingleChildScrollView(
              key: const Key('speed_step_column_scroll'),
              // 堆叠时栏高不受限 → 滚动视口随内容收缩、无滚动余量；并排时
              // 栏内滚动（左栏不随之滚动）。
              physics: stacked ? const NeverScrollableScrollPhysics() : null,
              child: const _StepContent(),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// 倍速气泡两栏间的分隔线绘制（[MergedSpeedBubbleSeparator] 的画笔）：线在
/// 列距轴上距本盒起点 [lineOffset] 处，并排为竖线、堆叠为横线。
class _MergedBubbleSepPainter extends CustomPainter {
  const _MergedBubbleSepPainter({
    required this.stacked,
    required this.lineOffset,
  });

  final bool stacked;
  final double lineOffset;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = mergedBubbleColumnSeparatorWidth;
    final half = mergedBubbleColumnSeparatorWidth / 2;
    if (stacked) {
      final y = lineOffset + half;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    } else {
      final x = lineOffset + half;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_MergedBubbleSepPainter oldDelegate) =>
      oldDelegate.stacked != stacked || oldDelegate.lineOffset != lineOffset;
}

/// 倍速气泡内容：顶部倍
/// 率下拉标题条（高 24、单行、随当前值居中于左区内）+ 左区档位双列 | 右侧
/// 定高竖向滑条（整高 = 列高 + 22 = 234，顶 = 标题顶 + 6、底 = 列底）。
///
/// - 顶部标题条：显示当前实际倍速、点按弹出候选下拉（当前值 + 常用/历史
///   置顶 + 0.1–2.0 步 0.05 全档可滚），与档位/滑条双向同步
///   （外部生效→标题跟随）；
/// - 左区：宽下限 = 标题行自然宽（标题不再居中越界绘制出气泡左缘）；
///   其下常驻/历史两列以相等列宽均分左区内容宽（列宽只由左区宽决定，与
///   内容/历史有无无关）。常规档位 | 历史档位（去重、与快捷档重复的值不
///   重复展示、展示条数设上限；无历史时槽内「暂无历史」占位，列不隐藏不
///   收缩、两态切换零移动）；
/// - 右列：整高自定义竖向滑条（0.1–1.5、0.05 步），滑条列顶与
///   内容顶对齐（顶 = 标题顶 + 6）；滑条拖动实时生效、气泡不收起；
/// - 点常规/历史档位即生效并收起。两列顶部无列标题；常驻列严格升序
///   渲染（0.25 慢速在顶、向下更大）、历史列按倍速值升序（去重、忽略最近
///   先后）。
class _SpeedContent extends ConsumerWidget {
  const _SpeedContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(speedControlProvider);
    final notifier = ref.read(speedControlProvider.notifier);
    final sessionNotifier = ref.read(speedBubbleSessionProvider.notifier);
    // 历史档与快捷档去重展示（同值只出现在快捷档）；展示条数设上限
    // 兜底：单气泡不滚动；模型历史照常累积、语义不变。展示子集沿用最近
    // 在前 + 条数上限。渲染序按倍速值降序（忽略最近先后，与常驻列、竖向
    // 滑条同向）。
    final history = control.history
        .where((r) => !commonSpeeds.contains(r))
        .take(speedHistoryDisplayLimit)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    // 步进启用时两处倍速面板
    // （观看态与编辑态同一组件）不再置灰/禁用——面板始终可操作。面板「当前
    // 生效倍速」以 [SpeedControlState.effectiveRate] 为准：步进停用时即
    // [manualRate]、步进启用时即当前步进档位（随档位循环实时更新，如实
    // 显示）。用户在其中改倍速（档位/滑条/下拉）走既有 [SpeedControlModel.
    // setRate]（模型侧自动停步进）并应用新倍速。
    final currentRate = control.effectiveRate;

    // 左区宽下限 = 标题行自然宽
    // （标题不再被夹在窄于自身的 Stack/OverflowBox 内居中越界绘制出气泡
    // 左缘）；常驻/历史两列均分左区内容宽——两列列宽相等、只由左区宽决定，
    // 与内容/历史有无无关。量测带调用处 DefaultTextStyle（与实际渲染同一样
    // 式，防字距差异导致换行）。宽度度量经 [speedPanelWidths] 单源（倍速气泡
    // 几何纯函数取同一处）。
    final widths = speedPanelWidths(context);
    final leftWidth = widths.bodyWidth;
    final columnWidth = widths.columnWidth;

    // 点档即生效并收起（视觉按钮与透明命中层共用这一条写入口）。
    Future<void> selectRate(double rate) async {
      await notifier.setRate(rate);
      sessionNotifier.close();
    }

    Widget rateOption(double rate, {required Key key}) => SizedBox(
          width: columnWidth,
          height: speedRateButtonHeight,
          child: _RateOption(
            key: key,
            label: '${formatRate(rate)}x',
            selected: roundRate(currentRate) == rate,
            onTap: () => selectRate(rate),
          ),
        );

    // 命中层：每个档位一枚透明 [kHitTargetMinSize]
    // 高命中层，位置与视觉列同源（常驻列 pitch 由列高与档位数派生，历史列
    // pitch = 单钮高）。先画（视觉按钮压在命中层之上 → 钮自身 32dp 命中优
    // 先），相邻命中层重叠时靠下那层先测——每个钮的中心都落在自己那层内，
    // 「点哪个是哪个」不变；视觉件 32、列高 212、气泡几何逐位不变。
    //
    // 几何下界（代价清单）：列高固定 212、单钮 32 时档位 pitch 恒
    // 36 < 48，故命中层必然互相重叠——每钮**独占可达区**受 pitch 上限约束
    // （视觉 32 + 相邻缝 4）。命中层末位钳进列内，不越出可测界。
    List<Widget> rateHitLayers(
      List<double> rates,
      String keyPrefix,
      double pitch,
    ) {
      final maxTop = (speedColumnsBlockHeight - kHitTargetMinSize)
          .clamp(0.0, double.infinity);
      return [
        for (var i = 0; i < rates.length; i++)
          Positioned(
            left: 0,
            right: 0,
            top: math.min(i * pitch, maxTop),
            height: kHitTargetMinSize,
            child: GestureDetector(
              key: Key('${keyPrefix}_hit_${rates[i]}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => selectRate(rates[i]),
              child: const SizedBox.expand(),
            ),
          ),
      ];
    }

    // 常驻列：两列等分后的列宽 [columnWidth]、定高 212、space-between 铺满
    //（行距 g=4 派生）。按倍速值降序渲染——大值在顶、向下更小，与
    // 竖向滑条「min 在下、max 在上」同向（commonSpeeds 数据本身升序语义
    // 不变，仍供下拉候选与历史去重判定）。
    final residentRates = commonSpeeds.reversed.toList();
    // space-between 的行距：末钮底 = 列底，故 pitch = 列高差 / (n − 1)。
    final residentPitch = residentRates.length > 1
        ? (speedColumnsBlockHeight - speedRateButtonHeight) /
              (residentRates.length - 1)
        : 0.0;
    final residentColumn = SizedBox(
      key: const Key('speed_quick_column'),
      width: columnWidth,
      height: speedColumnsBlockHeight,
      child: Stack(
        children: [
          ...rateHitLayers(residentRates, 'speed_quick', residentPitch),
          Positioned.fill(
            child: Column(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final rate in residentRates)
                  rateOption(rate, key: Key('speed_quick_$rate')),
              ],
            ),
          ),
        ],
      ),
    );

    // 历史列：与常驻列同宽（不因内容收缩）；无历史时槽内「暂无历史」占位
    //（白 24%、12px、槽内居中），列不隐藏、宽度不收缩——两态切换零移动。
    final historyColumn = SizedBox(
      key: const Key('speed_history_column'),
      width: columnWidth,
      height: speedColumnsBlockHeight,
      child: history.isEmpty
          ? const Center(
              child: Text(
                '暂无历史',
                key: Key('speed_history_empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: kSpeedHistoryEmptyTextColor,
                  fontSize: 12,
                ),
              ),
            )
          : Stack(
              children: [
                ...rateHitLayers(history, 'speed_history', speedRateButtonHeight),
                Positioned.fill(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      for (final rate in history)
                        rateOption(rate, key: Key('speed_history_$rate')),
                    ],
                  ),
                ),
              ],
            ),
    );

    return IntrinsicHeight(
      child: Row(
        // 整行顶对齐——左区标题顶与滑条列顶同基线（滑条顶 = 标题顶
        // + 6，经 [speedSliderTopOffset] 内边距实现）。宽随内容收缩：min。
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左区：标题条 + 双列块，宽度 = [leftWidth]（标题行自然宽作下限，
          // 标题随当前值居中于左区内、永不越出气泡左缘）。
          SizedBox(
            width: leftWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 标题条：高 24、单行不折行、随内容伸缩并居中。
                SizedBox(
                  height: speedTitleHeight,
                  child: _RateTitleSelect(),
                ),
                const SizedBox(height: speedTitleColumnGap),
                // 双列块：定高 212（= 6×32 + 5×g，g=4），两列均分左区宽。
                SizedBox(
                  height: speedColumnsBlockHeight,
                  child: Row(
                    key: const Key('speed_columns_row'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      residentColumn,
                      const SizedBox(width: speedGroupGap),
                      historyColumn,
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: speedGroupGap),
          // 右列：定高自定义竖向滑条（0.1–1.5、0.05 步、拖动实时生效不收
          // 起）。整高 = 列高 + 22 = 234，顶 = 标题顶 + 6、底 = 列底（派生
          // 关系锁定）。显式固定高度，刻度尺/
          // 竖轨不依赖推断。
          Padding(
            padding: const EdgeInsets.only(top: speedSliderTopOffset),
            child: SizedBox(
              width: speedSliderColumnWidth,
              height: speedSliderColumnHeight,
              child: _VerticalRateSlider(
                key: const Key('speed_rate_slider'),
                value: currentRate.clamp(speedRateMin, speedSliderMax),
                min: speedRateMin,
                max: speedSliderMax,
                step: speedSliderStep,
                // 实时生效：拖动中每一档都应用到内核（步进启用中改档即经
                // setRate 自动退步进），气泡保持展开。
                onChanged: notifier.setRate,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 自定义竖向滑条（min 在下、max 在上；向上拖 = 加速）：**拇指旁不显示
/// 动态数值**——实时当前值只由标题栏显示并随拖动同步；竖轨左侧设常驻刻度尺
/// （0.5/1.0/1.5 大刻度带数字 + 0.1 细分小刻度，刻度与滑条取值同步）。
///
/// 值直接跳到触点位置（与 Slider 拖动语义一致：按住轨道任意处即跳到该
/// 值，再拖动跟随）；[step] 步进吸附。
class _VerticalRateSlider extends StatelessWidget {
  const _VerticalRateSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;

  double _snap(double v) {
    final snapped = min + ((v - min) / step).roundToDouble() * step;
    return roundRate(math.min(max, math.max(min, snapped)));
  }

  void _emit(double raw) {
    final next = _snap(raw);
    if (next != value) onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final trackColor = Colors.white24;
    final activeColor = kHighlightAmber;
    final thumbColor = Colors.white;
    final labelColor = Colors.white;
    final t = ((value - min) / (max - min)).clamp(0.0, 1.0);
    // 刻度只依赖值域（静态），build 内算一次、painter 与标签循环共用。
    final ticks = speedRulerTicks(min: min, max: max);
    // 替代路径：触摸拖动之外，滑条以「滑条
    // 角色 + 当前值 + 可增减」暴露给读屏/辅助技术——增减走与拖动同一个
    // 写入口（onChanged），一步 = 一个 step，到端不越界。
    final slider = GestureDetector(
      behavior: HitTestBehavior.opaque,
      // 手势原生语义不进无障碍树：拖动产生的是无名 scroll/tap 动作，滑条的
      // 可操作面由外层 [Semantics] 的滑条角色与增减动作表达。
      excludeFromSemantics: true,
      // 值直接跳到触点（与 Slider 拖动语义一致）；高度经已布局的
      // RenderBox 读取（回调时必已完成布局；不用 LayoutBuilder——
      // IntrinsicHeight 不支持其 intrinsic 计算）。
      // 面板不再因步进而禁用，滑条恒可操作。
      onVerticalDragStart: (d) => _emitForY(context, d.localPosition.dy),
      onVerticalDragUpdate: (d) => _emitForY(context, d.localPosition.dy),
      onTapUp: (d) => _emitForY(context, d.localPosition.dy),
      child: Row(
        children: [
          // 常驻刻度尺（取代拇指旁的横向值
          // 文字——实时当前值只由标题栏显示并随拖动同步）：大刻度数字标签
          // 纵位与滑条同一线性映射（刻度与取值同步），细分小刻度由
          // CustomPaint 绘制；标签静态（仅主刻度，不随值重排）。
          // 列高显式固定（[speedSliderColumnHeight]），标签改为
          // Positioned 纵向定位——不再依赖 Stack「取最大约束」的高度推断
          // （真机推断可为 0 → 标签整体锚出可视区）。Clip.none：顶/底主
          // 刻度（1.5/贴近 min 的标签）中心恰在刻度尺边缘，标签上半/下半
          // 允许越出刻度尺绘制（仍在气泡内）。
          SizedBox(
            width: speedRulerWidth,
            height: speedSliderColumnHeight,
            child: Stack(
              key: const Key('speed_rate_ruler'),
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const Key('speed_rate_ruler_minors'),
                    painter: _RulerTicksPainter(
                      ticks: ticks,
                      min: min,
                      max: max,
                      tickColor: trackColor,
                    ),
                  ),
                ),
                for (final tick in ticks)
                  if (tick.major)
                    Positioned(
                      left: 0,
                      // 标签中心精确落在该取值的线性映射纵位（与拇指中心
                      // 一致）：top = 顶部起算比例 × 定高 − 半个标签高；
                      // 比例经 [speedRulerTopFraction]（与刻度线绘制同源）。
                      top: speedRulerTopFraction(
                            value: tick.value,
                            min: min,
                            max: max,
                          ) *
                          speedSliderColumnHeight -
                          _rulerLabelHeight / 2,
                      child: SizedBox(
                        height: _rulerLabelHeight,
                        // 刻度数字是装饰档（固定排版，不承载语义）：数值可增减的
                        // 滑条节点由外层
                        // 提供，这些刻度文字不进无障碍树（否则会拼成滑条
                        // 的名字）。
                        child: ExcludeSemantics(
                          child: Text(
                            tick.label!,
                            key: Key('speed_rate_ruler_label_${tick.label}'),
                            style: TextStyle(
                              color: labelColor,
                              fontSize: _rulerLabelFontSize,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: speedRulerGap),
          // 竖轨：厚度 ≈28dp，min 在下、max 在上。轨道/填充/
          // 拇指整轨由 CustomPaint 按值比例绘制（intrinsic 友好）。
          // 与刻度尺同高（显式定高）。
          SizedBox(
            width: speedSliderTrackThickness,
            height: speedSliderColumnHeight,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    key: const Key('speed_rate_slider_track'),
                    painter: _VerticalTrackPainter(
                      fraction: t,
                      trackColor: trackColor,
                      activeColor: activeColor.withValues(alpha: 0.45),
                      thumbColor: thumbColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: const Key('speed_rate_slider_semantics'),
      container: true,
      slider: true,
      label: '倍速',
      value: '${formatRate(value)}x',
      increasedValue: '${formatRate(_snap(value + step))}x',
      decreasedValue: '${formatRate(_snap(value - step))}x',
      onIncrease: () => _emit(value + step),
      onDecrease: () => _emit(value - step),
      child: slider,
    );
  }

  void _emitForY(BuildContext context, double y) {
    final size = context.size;
    if (size == null || size.height <= 0) return;
    _emit(
      min + (max - min) * ((size.height - y) / size.height).clamp(0.0, 1.0),
    );
  }
}

/// 刻度尺刻度线绘制：大刻度长线（数字标签的刻度标记）+ 小刻度
/// 短线（细分）。纵位共用与标签/拇指一致的线性映射（[min]/[max] 传入，
/// 不从刻度列表端点反推）。
class _RulerTicksPainter extends CustomPainter {
  const _RulerTicksPainter({
    required this.ticks,
    required this.min,
    required this.max,
    required this.tickColor,
  });

  final List<SpeedRulerTick> ticks;
  final double min;
  final double max;
  final Color tickColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = tickColor;
    for (final tick in ticks) {
      // 纵位经 [speedRulerTopFraction]——与标签 Positioned 同一映射实现
      //（防两处公式漂移）。
      final y = speedRulerTopFraction(
        value: tick.value,
        min: min,
        max: max,
      ) *
          size.height;
      // 线 6×2、贴尺右缘、线中心 = 分度值位置（几何经
      // [speedRulerTickRect] 纯函数，含 1px 线高补偿）。
      canvas.drawRect(
        speedRulerTickRect(rulerWidth: size.width, top: y),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RulerTicksPainter old) =>
      old.tickColor != tickColor || old.min != min || old.max != max;
}

/// 竖轨绘制：整轨圆角背景 + 自下而上的已填充段（按值比例）+ 拇指横条。
class _VerticalTrackPainter extends CustomPainter {
  const _VerticalTrackPainter({
    required this.fraction,
    required this.trackColor,
    required this.activeColor,
    required this.thumbColor,
  });

  /// 当前值占比（0=min 底部，1=max 顶部）。
  final double fraction;
  final Color trackColor;
  final Color activeColor;
  final Color thumbColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(6);
    final trackRRect = RRect.fromRectAndRadius(Offset.zero & size, radius);
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);
    final thumbY = (1 - fraction) * size.height;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, thumbY, size.width, size.height - thumbY),
        radius,
      ),
      Paint()..color = activeColor,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          3,
          (thumbY - 3).clamp(0.0, size.height - 6),
          size.width - 6,
          6,
        ),
        Radius.circular(3),
      ),
      Paint()..color = thumbColor,
    );
  }

  @override
  bool shouldRepaint(_VerticalTrackPainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.activeColor != activeColor ||
      old.thumbColor != thumbColor;
}

/// 候选下拉通用：展示值吸附到最近候选——历史 JSON 带入非网格
/// 值时仍可显示，但可选值恒在候选集内（无手输越界）。
T snapToCandidates<T extends num>(T value, List<T> candidates) {
  return candidates.reduce(
    (a, b) => (b - value).abs() < (a - value).abs() ? b : a,
  );
}

/// 顶部标题条倍率下拉（取消数字输入）。
///
/// - 候选集 = 当前值 + 常用/历史置顶（去重）+ 0.1–2.0 步 0.05 全档
///   （[pinnedRateCandidates]），菜单超高可滚；可选值恒在候选集内——
///   无手输越界；
/// - 选中即生效、气泡不收起（与原输入提交行为一致）；
/// - 双向同步：当前实际倍速变化（档位/滑条/外部生效/步进推进）→ 标题跟随；
/// - ：步进启用中亦不置灰——改档即经 setRate 自动退步进。
class _RateTitleSelect extends ConsumerWidget {
  const _RateTitleSelect();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(speedControlProvider);
    final options = pinnedRateCandidates(
      current: control.effectiveRate,
      common: commonSpeeds,
      history: control.history,
    );
    final displayed = snapToCandidates(control.effectiveRate, options);
    return Row(
      key: const Key('speed_rate_title'),
      // 标题容器宽随内容（mainAxisSize.min）——内容
      // 「当前倍速 + 下拉值 + ▾」单行不折行，容器中点 = 双列块中点（倍速
      // 值位数变化时容器同步伸缩、中点恒定）。
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          _rateTitleLabelText,
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: TextStyle(
            color: Colors.white54,
            fontSize: _rateTitleLabelFontSize,
          ),
        ),
        const SizedBox(width: _rateTitleLabelGap),
        DropdownButton<double>(
          key: const Key('speed_rate_select'),
          value: displayed,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: _rateTitleValueFontSize,
            fontWeight: _rateTitleValueWeight,
          ),
          dropdownColor: Colors.black87,
          items: [
            for (final rate in options)
              DropdownMenuItem(
                key: Key('speed_rate_option_$rate'),
                value: rate,
                child: Text('${formatRate(rate)}x'),
              ),
          ],
          // 下拉选中即生效、不收起（与输入提交一致）。步进启用中
          // 面板不再禁用——改档经 setRate 自动退步进。
          onChanged: (rate) async {
            if (rate == null) return;
            await ref.read(speedControlProvider.notifier).setRate(rate);
          },
        ),
      ],
    );
  }
}

/// 步进栏内容（并入倍速气泡右栏）。
///
/// - 预设行主区（名称 + 参数摘要）：单击走三态（见 [_onPresetTap]）——未启用
///   → 启用该预设（预览在激活范围内直接启用；范围外先弹三选一作用域）；
///   已启用点「已启用」那行 → 停用；已启用点别的行 → 切换。三态收起
///   气泡（三选一取消除外）；
/// - 行右侧独立「编辑」与「删除」（内置与自定义同一枚）；
/// - 启用/停用走预设行与左栏改倍速；列表尾为**虚线占位整行「＋ 新增预设」**；
/// - 「编辑」/新建进入该预设的编辑子视图（名称唯一输入 + 四参数下拉选择，
///   保存即存）；内置编辑含「恢复默认」；删除需二次确认弹窗。
class _StepContent extends ConsumerStatefulWidget {
  const _StepContent();

  @override
  ConsumerState<_StepContent> createState() => _StepContentState();
}

/// 编辑目标哨兵：null = 预设列表；'' = 新建中；否则为正在编辑的预设 id。
const String _newPresetSentinel = '__new__';

class _StepContentState extends ConsumerState<_StepContent> {
  /// null = 预设列表；[_newPresetSentinel] = 新建中；否则 = 正在编辑的预设 id。
  String? _editingId;

  bool get _creating => _editingId == _newPresetSentinel;

  /// 点预设行三态：
  /// **未启用** → 选中该预设并开启步进（预览位置在激活范围外时仍先走既有
  /// 三选一）；**已启用且点「已启用」那行** → 停用；**已启用且点别的行** →
  /// 切换（旧的跑停、按新预设起跑），不再重走范围判定、沿用本次已定范围。
  /// 三态都收起气泡；范围三选一取消则不收起（未完成任何动作）。
  Future<void> _onPresetTap(String id) async {
    final presetNotifier = ref.read(speedStepPresetProvider.notifier);
    final bubble = ref.read(speedBubbleSessionProvider.notifier);
    if (ref.read(speedControlProvider).stepEnabled) {
      if (id == ref.read(speedStepPresetProvider).selectedId) {
        await ref.read(speedControlProvider.notifier).setStepEnabled(false);
      } else {
        await presetNotifier.select(id);
        if (!mounted) return;
        // 切换：沿用本次已定范围，从新预设首档重新起跑（旧的跑停）。
        await ref
            .read(speedControlProvider.notifier)
            .setStepEnabled(
              true,
              scope: ref.read(speedControlProvider).stepScope,
            );
      }
      if (!mounted) return;
      bubble.close();
      return;
    }
    await presetNotifier.select(id);
    if (!mounted) return;
    await enableSpeedStepForPreview(context, ref);
    if (!mounted) return;
    if (ref.read(speedControlProvider).stepEnabled) {
      bubble.close();
    }
  }

  /// 删除预设的二次确认弹窗（内置与自定义同一枚删除钮、同一个弹窗）；
  /// 确认即删——内置删除不可恢复，被删内置的「恢复默认」入口随行消失。
  Future<void> _confirmDelete(BuildContext context, SpeedStepPreset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('speed_step_delete_dialog'),
        title: const Text('删除预设'),
        content: Text('删除「${preset.name}」？此操作不可撤销。'),
        actions: [
          TextButton(
            key: const Key('speed_step_delete_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('speed_step_delete_confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      // 删除同步提交内存 state 后即从列表消失；落盘为后台写（store seam）。
      unawaited(ref.read(speedStepPresetProvider.notifier).delete(preset.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(speedStepPresetProvider);
    if (_creating) {
      return _StepPresetEditor(
        key: const ValueKey('step_editor_new'),
        creating: true,
        initialName: defaultCustomPresetName([for (final p in doc.presets) p.name]),
        initialParams: presetById(doc, doc.selectedId)?.params ??
            const SpeedStepParams(),
        onClose: () => setState(() => _editingId = null),
      );
    }
    final editingPreset = _editingId == null
        ? null
        : presetById(doc, _editingId!);
    if (editingPreset != null) {
      return _StepPresetEditor(
        key: ValueKey('step_editor_${editingPreset.id}'),
        creating: false,
        preset: editingPreset,
        onClose: () => setState(() => _editingId = null),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final preset in doc.presets) _buildPresetRow(context, preset, doc),
        const SizedBox(height: 6),
        _AddPresetPlaceholder(
          onTap: () => setState(() => _editingId = _newPresetSentinel),
        ),
      ],
    );
  }

  Widget _buildPresetRow(
    BuildContext context,
    SpeedStepPreset preset,
    SpeedStepPresetDoc doc,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: _PresetRowMain(
              preset: preset,
              selected: preset.id == doc.selectedId,
              onTap: () => _onPresetTap(preset.id),
            ),
          ),
          _RowActionButton(
            key: Key('speed_step_edit_${preset.id}'),
            icon: Icons.edit_outlined,
            tooltip: '编辑',
            onTap: () => setState(() => _editingId = preset.id),
          ),
          _RowActionButton(
            key: Key('speed_step_delete_${preset.id}'),
            icon: Icons.delete_outline,
            tooltip: '删除',
            onTap: () => _confirmDelete(context, preset),
          ),
        ],
      ),
    );
  }
}

/// 预设行的主区（名称 + 摘要），整区可点 = 应用并启用步进。
class _PresetRowMain extends StatelessWidget {
  const _PresetRowMain({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final SpeedStepPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final summary = speedStepPresetSummary(preset.params);
    final foreground = selected ? kHighlightAmber : Colors.white70;
    final background = selected
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.transparent;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        key: Key('speed_step_preset_${preset.id}'),
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preset.name,
                style: TextStyle(
                  color: foreground,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                summary,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 预设行右侧的小按钮（编辑/删除；与整行应用命中分离防误触）。
class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 命中盒下限：透明外扩到 48×48，图标 18
    // 与内边距 8 的观感不变。
    return Tooltip(
      message: tooltip,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kHitTargetMinSize,
          minHeight: kHitTargetMinSize,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Icon(icon, size: 18, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表尾「＋ 新增预设」虚线占位整行：点击进入新建。
class _AddPresetPlaceholder extends StatelessWidget {
  const _AddPresetPlaceholder({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: Colors.white38),
      child: InkWell(
        key: const Key('speed_step_add_preset'),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: Colors.white70),
              SizedBox(width: 4),
              Text(
                '新增预设',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 虚线占位行外框绘制（虚线占位整行视觉）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0;
    const gap = 3.0;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(8),
        ),
      );
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

/// 预设编辑器（编辑/新建子视图）。[creating] = true 为新建（无 id，
/// 保存即建）；false 编辑 [preset]（保存即存）。
class _StepPresetEditor extends ConsumerStatefulWidget {
  const _StepPresetEditor({
    super.key,
    required this.creating,
    required this.onClose,
    this.preset,
    this.initialName,
    this.initialParams,
  }) : assert(creating ? preset == null : preset != null,
            '新建不传 preset，编辑必传 preset');

  final bool creating;
  final SpeedStepPreset? preset;
  final String? initialName;
  final SpeedStepParams? initialParams;
  final VoidCallback onClose;

  @override
  ConsumerState<_StepPresetEditor> createState() => _StepPresetEditorState();
}

class _StepPresetEditorState extends ConsumerState<_StepPresetEditor> {
  late final TextEditingController _nameController;
  late SpeedStepParams _params;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.creating ? (widget.initialName ?? '') : widget.preset!.name,
    );
    _params = widget.creating
        ? (widget.initialParams ?? const SpeedStepParams())
        : widget.preset!.params;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 保存即存/即建：编辑 → updatePreset（名称 + 参数）；新建 → createCustom。
  ///
  /// 模型方法在提交后**同步落内存 state、异步落盘**（store seam），「保存即存」
  /// 只要求同步提交即可收起编辑器回列表；落盘为后台写，UI 不阻塞其完成。
  void _save() {
    final pn = ref.read(speedStepPresetProvider.notifier);
    if (!_params.isValid) {
      setState(() => _error = '参数非法：需起步倍速>0、递增量>0、每档遍数≥1、封顶≥起步');
      return;
    }
    setState(() => _error = null);
    if (widget.creating) {
      pn.createCustom(_nameController.text.trim(), params: _params);
    } else {
      pn.updatePreset(
        id: widget.preset!.id,
        name: _nameController.text.trim(),
        params: _params,
      );
    }
    widget.onClose();
  }

  /// 内置编辑的「恢复默认」：回到出厂参数。
  void _restoreBuiltinDefault() {
    final pn = ref.read(speedStepPresetProvider.notifier);
    pn.restoreBuiltinDefault(widget.preset!.id);
    final doc = ref.read(speedStepPresetProvider);
    final restored = doc.presets.firstWhere(
      (p) => p.id == widget.preset!.id,
      orElse: () => widget.preset!,
    );
    setState(() {
      _params = restored.params;
      _nameController.text = restored.name;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final params = _params;
    final isBuiltin = widget.creating ? false : widget.preset!.builtin;
    return Column(
      key: const Key('speed_step_editor'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 返回列表 + 标题。
        Row(
          children: [
            // 命中盒下限：透明外扩到 48×48，
            // 图标 18 与贴左内边距 4 的观感不变。
            ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: kHitTargetMinSize,
                minHeight: kHitTargetMinSize,
              ),
              child: InkWell(
                key: const Key('speed_step_editor_back'),
                borderRadius: BorderRadius.circular(6),
                onTap: widget.onClose,
                child: Semantics(
                  button: true,
                  label: '返回预设列表',
                  child: const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.arrow_back,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Expanded(
              child: Text(
                '预设编辑',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            if (isBuiltin)
              TextButton(
                key: const Key('speed_step_restore_default'),
                onPressed: _restoreBuiltinDefault,
                child: const Text(
                  '恢复默认',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        // 名称（唯一保留输入）。
        TextField(
          key: const Key('speed_step_editor_name'),
          controller: _nameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: const InputDecoration(
            hintText: '预设名称',
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            border: OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 6),
        // 参数选择（四参数下拉，候选集同）。按钮行横向均匀
        // 分布——每项 Expanded 等分、间距 3dp。
        Row(
          key: const Key('speed_step_editor_params_row'),
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _ParamDropdown(
                fieldKey: const Key('speed_step_editor_start_rate'),
                label: '起步',
                value: params.startRate,
                candidates: rateCandidates(),
                format: formatRate,
                onChanged: (v) => setState(() => _params = params.copyWith(startRate: v)),
              ),
            ),
            const SizedBox(width: speedCompactGap),
            Expanded(
              child: _ParamDropdown(
                fieldKey: const Key('speed_step_editor_max_rate'),
                label: '封顶',
                value: params.maxRate,
                candidates: rateCandidates(),
                format: formatRate,
                onChanged: (v) => setState(() => _params = params.copyWith(maxRate: v)),
              ),
            ),
            const SizedBox(width: speedCompactGap),
            Expanded(
              child: _ParamDropdown<int>(
                fieldKey: const Key('speed_step_editor_laps_per_rate'),
                label: '遍数',
                value: params.lapsPerRate,
                candidates: lapsPerRateCandidates,
                format: (v) => '$v',
                onChanged: (v) => setState(() => _params = params.copyWith(lapsPerRate: v)),
              ),
            ),
            const SizedBox(width: speedCompactGap),
            Expanded(
              child: _ParamDropdown(
                fieldKey: const Key('speed_step_editor_rate_increment'),
                label: '递增',
                value: params.rateIncrement,
                candidates: rateIncrementCandidates,
                format: formatRate,
                onChanged: (v) => setState(() => _params = params.copyWith(rateIncrement: v)),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(
            _error!,
            key: const Key('speed_step_editor_error'),
            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
          ),
        ],
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('speed_step_editor_save'),
            onPressed: _save,
            child: Text(
              widget.creating ? '新增' : '保存',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
class _ParamDropdown<T extends num> extends StatelessWidget {
  const _ParamDropdown({
    super.key,
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.candidates,
    required this.format,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final T value;
  final List<T> candidates;
  final String Function(T) format;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final displayed = snapToCandidates(value, candidates);
    return Column(
      mainAxisSize: MainAxisSize.min,
      // stretch：填满 Expanded 等分宽（均匀分布——列内控件不因内容
      // 宽度不同而参差）。
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 10),
        ),
        DropdownButton<T>(
          key: fieldKey,
          value: displayed,
          isDense: true,
          iconSize: 14,
          underline: const SizedBox.shrink(),
          style: const TextStyle(color: Colors.white, fontSize: 13),
          dropdownColor: Colors.black87,
          items: [
            for (final candidate in candidates)
              DropdownMenuItem(
                value: candidate,
                child: Text(format(candidate)),
              ),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

/// 气泡外点按遮罩（「点气泡外收起」，两宿主共用）。
///
/// 用指针级 [Listener] 而非 GestureDetector.onTap：编辑态空白区的 scale
/// 识别器会独占 gesture arena（判定语义），tap 识别器在其上必落败、
/// 永不触发。此处不进 arena：按下点记录、抬起位移在触摸 slop 内视为一次
/// 点外收起（拖动/捏合不误收）。
class BubbleOutsideTapScrim extends StatefulWidget {
  const BubbleOutsideTapScrim({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<BubbleOutsideTapScrim> createState() => _BubbleOutsideTapScrimState();
}

class _BubbleOutsideTapScrimState extends State<BubbleOutsideTapScrim> {
  final _downPoints = <int, Offset>{};

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _downPoints[e.pointer] = e.position,
      onPointerUp: (e) {
        final down = _downPoints.remove(e.pointer);
        if (down != null && (e.position - down).distance < kTouchSlop) {
          widget.onTap();
        }
      },
      onPointerCancel: (e) => _downPoints.remove(e.pointer),
      child: Semantics(
        // 退出语义：读屏用户无需精确点外，
        // dismiss 动作即收起气泡；指针点外路径不变。
        label: '收起气泡',
        onDismiss: widget.onTap,
        child: const ColoredBox(color: Colors.black54),
      ),
    );
  }
}

/// 可点档位钮：文字居中、单行不换行（「×」结构性单行）；列宽由
/// [rateOptionColumnWidth] 按最宽文本自适应（字号 [rateOptionFontSize]、
/// 横向内边距 [rateOptionHorizontalPadding]、纵向内边距
/// [speedRateOptionVerticalPadding]）。选中琥珀高亮（集中 token）。面板不因
/// 步进而置灰禁用。
class _RateOption extends StatelessWidget {
  const _RateOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? kHighlightAmber : Colors.white70;
    final background = selected
        ? Colors.white.withValues(alpha: 0.16)
        : Colors.transparent;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: rateOptionHorizontalPadding,
            vertical: speedRateOptionVerticalPadding,
          ),
          child: SizedBox(
            width: double.infinity,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(color: foreground, fontSize: rateOptionFontSize),
            ),
          ),
        ),
      ),
    );
  }
}
