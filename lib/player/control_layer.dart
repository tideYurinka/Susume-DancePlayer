/// 控制层库（标注编辑界面外壳）：顶栏、中部空白手势面、设置条、轨道带
/// 挂载与底部工具条。装配按簇分片在 part 文件里，本文件留外壳 State 与
/// 各落点的行装配：
///
/// - `play_tool_row.dart`：顶栏播放设置工具行与竖屏视频工具栏（行集遍历、
///   活值束、量宽与单槽渲染）；
/// - `annotation_tool_row.dart`：底部标注工具行（槽条目装配、事实、判定表
///   门控管道与熟练度件）；
/// - `tool_menus.dart`：工具菜单壳、互斥单开登记与菜单路由；
/// - `frame_step.dart`：帧步进与格点跳步；
/// - `rotate_buttons.dart`：横竖屏转屏钮、命中矩形与视觉件。
library;

import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/half_beat_snap.dart'
    show nextHalfBeatPoint, previousHalfBeatPoint;
import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart';
import '../core/beat_grid.dart';
import '../annotation/snap.dart' show nextBeatPoint, previousBeatPoint;
import '../help/content_registry.dart'
    show
        HandsOnCriterion,
        autoSegmentMenuAnchorKey,
        badgeAutoSegmentUnitId,
        badgeSegmentUnitId;

import '../help/guide_anchor.dart' show GuideAnchor, guideAnchorRectsProvider;
import '../help/guide_state.dart' show guideSessionProvider;
import '../help/guide_units_page.dart' show GuideUnitsPage;
import 'auto_scroll_title.dart';
import 'annotation_edit.dart'
    show
        AddEightBeatAnchor,
        AddSegmentLine,
        ClearEightBeatAnchors,
        MoveHalfBeatLine,
        RemoveEightBeatAnchor,
        RemoveHalfBeatLine,
        RemoveLocalMirrorFragment,
        RemovePracticeClip,
        RemoveSegmentLine,
        SetSelectedSegmentsMastery,
        SetSelectedSegmentsDensity,
        SetVideoRange,
        ToggleSelectedSegmentsEmphasis;
import 'cast_entry_gate.dart'
    show
        castEntryBlocksStart,
        castEntryFactsProvider,
        castEntryToolFacts,
        castEntryVerdict;
import 'load_gate.dart';
import 'gesture_surface_session.dart';
import 'notice.dart' show NoticeId, noticeTriggerProvider;
import 'no_subject_hint.dart' show showNoSubjectHint;
import 'play_tool_table.dart';
import '../core/frame_time.dart';
import '../core/text_extent.dart';
// 选中域库：不入史选中态的值类型与
// 状态 provider 本体在此；调用点直连域对象。装配 provider
// `annotationSelectionDomainProvider` 仍从编辑库取（唯一同时握有域端口与
// 片段／备注现值的地方）。
import 'annotation_selection.dart'
    show VideoRangeBoundary, selectedLearningSegmentsProvider;
import 'annotation_editor.dart';
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'editor_skeleton.dart';
import 'mirror.dart';
import '../player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatTrackStateProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import 'beat_correction.dart'
    show
        beatCorrectionAvailableProvider,
        hasEightBeatAnchorsProvider,
        previewAnchorOccupiedProvider,
        previewDownbeatProvider;
import '../cast/cast_session.dart' show CastRemoteItem;
import 'cast_preview.dart' show castPreviewProvider;
import 'cast_run.dart' show castRemoteControlsProvider;
import 'cast_speed_panel.dart' show showCastSpeedPanel;
import 'practice_mirror.dart';
import 'rate_label_slot.dart';
import 'settings_cluster.dart' show SettingsCluster, settingsStripVisibleFor;
import 'session_mode_surfaces.dart' show sessionModeSurfacesOf;
import 'speed_control.dart';
import 'system_mirror_entry.dart' show openSystemMirrorEntry;
import 'system_ui.dart' show ScreenOrientation;
import 'tool_slots.dart';
import 'tool_menu_actions.dart';
import 'visual_tokens.dart';
import 'speed_bubble.dart';
import 'track_band.dart';
import 'track_band_session.dart';
import 'track_row_table.dart';

part 'frame_step.dart';
part 'play_tool_row.dart';
part 'annotation_tool_row.dart';
part 'tool_menus.dart';
part 'rotate_buttons.dart';

/// 控制层（标注编辑界面外壳）。
///
/// 布局（自上而下的纵向骨架，横竖屏同一套）：
///
/// - 顶部栏：左侧返回箭头 + 标题（视频文件名）；右侧播放设置工具区
///   （倍速设置 / 镜像 可点，对比练习 /
///   查看引导置灰）——播放设置工具区是倍速入口的**收口落点**；
/// - 中部：视频可见区（单击收起控制层）；
/// - 轨道带（[TrackBand]，骨架）：轨道手柄带行最底、其上节拍轨（占位刻度）、
///   学习段轨空轨，浮于视频下部、工具条上方；
/// - 底部工具条：左侧进度控件（播放/暂停、当前时间/总时长），右侧标注工具
///   （分段 / 自动分段等——不可用态；
///   局部镜像 / 渲染导出隐藏）。
///
/// 主体不整屏压暗：视频全屏 contain 作背景，中部视频可见区保持干净可辨认；
/// 顶栏/轨道带/工具条各自携带深色半透明浮层（横屏浮层行：
/// chrome 浮于 contain 背景上，轨道带 ≈黑60% 不被整屏叠层加深）。本控件自身
/// 覆盖全屏，以不透明命中测试阻断下层播放手势层（手势作用域切换，
/// 控制层展开时播放手势不生效；收起后由宿主移除本控件即恢复）。
///
/// 播放设置工具区的一次只开一个展开项：倍速设置 / 节拍提示 / 音画同步为互斥
/// 气泡（状态存于 [speedBubbleSessionProvider] 单值），展开新项自动
/// 收起旧项；镜像点击立即生效（非面板）。
///
/// [ControlLayer] 不持有播放引擎等所有权；引擎 / 倍速模型 / 位置流经
/// provider 读取（见 `playback_engine_providers.dart` /
/// `speed_control.dart`），镜像由宿主传入 [mirror]（宿主保有并驱动画面
/// 翻转）。
class ControlLayer extends ConsumerStatefulWidget {
  const ControlLayer({
    super.key,
    required this.title,
    required this.mirror,
    required this.playing,
    required this.onTogglePlay,
    required this.onDelayedPlay,
    required this.onBack,
    required this.onCollapse,
    required this.onEditSignature,
    required this.skeleton,
    required this.rowTable,
    required this.session,
    required this.recording,
    required this.onRequestOrientation,
    required this.onDisconnectCast,
    required this.videoFilePath,
    required this.onToggleCastPicture,
    this.onScrubCommitted,
  });

  /// 顶部栏标题（歌曲署名显示串，未署名回退文件名；宿主拼接传入）。
  final String title;

  /// 镜像状态机（宿主保有；渲染层翻转由宿主按 [MirrorController.mirrored]）。
  final MirrorController mirror;

  /// 当前是否播放中（宿主直读引擎播放态传入，驱动工具条播放/
  /// 暂停图标）。
  final bool playing;

  /// 播放/暂停切换（宿主接线到引擎 + 状态同步）。
  final VoidCallback onTogglePlay;

  /// 延迟播放触发（宿主接线到 [DelayedPlayController.trigger]，
  /// 进度控件含「延迟播放」）。
  final VoidCallback onDelayedPlay;

  /// 返回（投屏态内先断开回编辑态；对比-控制层先退对比态；否则宿主 pop
  /// 回来源页）。不承担转屏。
  final VoidCallback onBack;

  /// 收起控制层（宿主 setState 复位展开态 + 解锁自动旋转方向）。
  final VoidCallback onCollapse;

  /// 「署名编辑」入口（页级入口表同名的
  /// [PageWriteEntryId.signatureEdit]）：点顶栏标题（整条标题 + 尾部铅笔
  /// 图标）时宿主打开 `SongNamingDialog` 的 `rename` 场景并提交署名。门
  /// （装载未完成）由本层按页级入口表挡下，挡下时本回调不被调用。
  final VoidCallback onEditSignature;

  /// 编辑面骨架分配（[editorSkeletonFor] 的唯一求值点在其宿主）：
  /// 竖屏行按它落视频带几何；横屏行（`portrait` 为假）走既有布局。
  final EditorSkeleton skeleton;

  /// 本态轨道行集（模式 → 行集的映射在宿主一处发生，本层对模式无知）。
  final TrackRowTable rowTable;

  /// 是否录制中（含准备期）：录制画面方向在起录瞬间锁定，转屏钮不出现。
  /// 由演出层读取一次、经此传入，本层不自开第二条读路。
  final bool recording;

  /// 方向动作回调（唯一一枚，/04）：语义 = 「请求屏幕朝向转为 X」。
  /// 横屏那枚文字钮传 [ScreenOrientation.portrait]。
  final ValueChanged<ScreenOrientation> onRequestOrientation;

  /// 断开投屏（投屏态顶栏那枚工具的动作）：宿主侧同一处实现，左上角退出
  /// 箭头在投屏态内走的是**同一个**回调语义——两处入口、一个动作。
  final VoidCallback onDisconnectCast;

  /// 这支舞的**视频副本**路径（宿主唯一知道的那份）：投屏入口五条门里
  /// 「副本丢失」一条的输入（其余四条由 `cast_entry_gate.dart` 自己接）。
  final String videoFilePath;

  /// 画面开关（投屏态顶栏那枚工具的动作）：宿主把画面区从黑底切成静音本地
  /// 预览、或切回黑底。起播定位（问接收端要位置）与静音都归投屏预览域，
  /// 这里只交出「用户点了这一下」——源文件在宿主手上。
  final VoidCallback onToggleCastPicture;

  /// 显式用户拖进度收口落点回报：预览条拖动与非轨道区微调 scrub
  /// 会话结束时回调，宿主据此打循环提示放行标记。
  final ValueChanged<Duration>? onScrubCommitted;

  /// 轨道带会话域：组合根创建的唯一实例，经
  /// 演出层输入下传。可视窗口读写、预览线显示值、拖动进行中标记、编辑态
  /// 微调 scrub 与跨面捏合都住在它里面——本层经它读窗口、落点与拖动标记。
  final TrackBandSession session;

  @override
  ConsumerState<ControlLayer> createState() => ControlLayerState();
}

/// 气泡模式：倍速设置 / 节拍提示共用 [SpeedBubble] 组件与
/// [speedBubbleSessionProvider] 状态来源；展开单值保证一次只开一个。

class ControlLayerState extends ConsumerState<ControlLayer> {
  /// 倍速气泡锚点：顶栏工具图标为 CompositedTransformTarget，
  /// 气泡锚定图标下方；开关状态存于 [speedBubbleSessionProvider]（与观看态
  /// 胶囊同一状态来源）。步进并入本气泡右栏（步进栏）。
  final LayerLink _speedSettingsLink = LayerLink();

  /// 节拍提示气泡锚点：顶栏「节拍提示」工具为
  /// CompositedTransformTarget，气泡锚定工具下方；与倍速/步进气泡共享
  /// [speedBubbleSessionProvider] 单值互斥会话。
  final LayerLink _beatPromptLink = LayerLink();

  /// 音画同步气泡锚点：顶栏「音画同步」工具（节拍提示紧左）
  /// 为 CompositedTransformTarget；同一互斥气泡会话。
  final LayerLink _avSyncLink = LayerLink();

  /// 「更多」钮锚点：紧凑档横屏下音画同步与节拍提示（含节拍侧另两个气泡）
  /// 的气泡锚点就挂这枚钮（这两枚在紧凑档横屏不常驻顶栏）——见
  /// [_buildBubbleOverlay]。
  final LayerLink _moreLink = LayerLink();

  /// 此刻横屏顶栏是否走紧凑档行集：「这一帧是不是紧凑档」
  /// （[EditorSkeleton.compact]——宿主按本次布局屏尺寸求值一次）与
  /// 「是不是横屏」两件事实的合成。消费点三处（横屏顶栏行集选择、
  /// 气泡锚点选择、轨道带剪裁），三处读同一份取值。
  bool get _compactLandscape =>
      !widget.skeleton.portrait && widget.skeleton.compact;

  /// 会话域句柄（本层只经它触碰窗口、落点与拖动标记）。
  TrackBandSession get _session => widget.session;

  /// 空白面输入会话簿记壳（[GestureSurfaceSession]）：raw 指针簿记、
  /// burst/tap 仲裁、轴锁与事件转发收口于模块——本 State 只剩装配（下方
  /// 注入闭包）+ 内容层（捏合窗口换算与微调 scrub 会话）。
  ///
  /// 空白区双击判定：单指双击 = 只切换播放/暂停（不
  /// 收起）、双指双击 = 收起 + 延迟播放（仅空白区识别）；
  /// 孤立单指单击 = 约 300ms 判定窗口后收起（与全屏唤出
  /// 层同一判定语义；收起仅由静止单击触发）。onMultiFingerWhileScrub 注入
  /// = blank 形态：锁定微调中加指/被混区抑制/指针取消 → 冻结并按松手语义
  /// 恢复手势前播放态（轴锁复位、回落 arming 待重锁）。
  late final GestureSurfaceSession _blankSurface = GestureSurfaceSession(
    axis: AxisPolicy.strictHorizontal,
    pinchSession: _session,
    pinchSurface: PinchForwardSurface.blank,
    isHostAlive: () => mounted,
    onSingleTap: _onBlankSingleTap,
    onDoubleTap: _onBlankDoubleTap,
    onTwoFingerDoubleTap: _onBlankTwoFingerDoubleTap,
    onMultiFingerWhileScrub: () => unawaited(_session.endFineScrub()),
    onSurfaceScaleStart: _onBlankSurfaceScaleStart,
    onScrubFrame: (d) =>
        unawaited(_session.fineScrubFrame(d.focalPointDelta.dx)),
    onPinchFrame: (d) =>
        _session.pinchFrame(factor: d.scale, focalX: d.localFocalPoint.dx),
    onSurfaceScaleEnd: _onBlankSurfaceScaleEnd,
  );

  // ---- 非轨道区微调（全程不显示进度浮层）----
  // 视频可见区单指横滑 = 全屏式微调：轴锁定时若在播即暂停定格；目标 =
  // 暂停点 + 位移增量 × 全屏单指灵敏度（不按手指绝对位置换算 → 不贴手指）；
  // 松手恢复手势前播放态。无取消角；编辑态（含轨道带空白横滑）全程不显示
  // 进度浮层，观看态的全屏 scrub 浮层不受此改。

  @override
  void dispose() {
    _blankSurface.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 竖屏骨架：骨架的求值点在宿主（唯一读点），本层只消费结果。
    // 对比-控制层**不重分配画面层**——其竖屏分屏几何与取景描边保持既有行为
    // 但 middle 区（空白手势面）与两行
    // 工具栏按设备方向走同一套竖屏骨架（普通/待命/对比三态一致）。
    final portraitDevice = widget.skeleton.portrait;
    // 横屏文字钮：锚由**系统栏内缩**推出，**屏幕坐标**
    // ——见 [landscapeToPortraitButtonRect]。左 = 左内缩 + 间隙，与返回键、
    // 顶栏同一条内缩线；压在画面上是可接受代价，只避开数拍数字与轨道带。
    // 渲染在 SafeArea 之外，否则会被内缩再挪一次、与顶栏那条线错开。
    final media = MediaQuery.of(context);
    // 横屏文字钮：**命中矩形**由视觉矩形外扩到
    // 命中下限（唯一式子 [landscapeToPortraitButtonHitRect]，屏幕坐标——见
    // [landscapeToPortraitButtonRect]），视觉件在命中盒内保持原位。
    final landscapeTrackBandTop =
        media.size.height -
        media.padding.bottom -
        kEditorToolbarHeight -
        widget.rowTable.totalHeight;
    final landscapeVisualRect = !portraitDevice && !widget.recording
        ? landscapeToPortraitButtonRect(
            systemTopInset: media.padding.top,
            systemLeftInset: media.padding.left,
            trackBandTop: landscapeTrackBandTop,
          )
        : null;
    final buttonRect = landscapeVisualRect == null
        ? null
        : landscapeToPortraitButtonHitRectOf(
            visual: landscapeVisualRect,
            trackBandTop: landscapeTrackBandTop,
          );
    // 命中盒相对视觉矩形的上探量：视觉件在命中盒内下移同量、原位不动。
    final buttonVisualTopOffset = landscapeVisualRect == null
        ? 0.0
        : landscapeVisualRect.top - buttonRect!.top;
    // 竖屏转屏钮：锚只看画面区、不看画面显示朝向；**屏幕坐标**，渲染在
    // SafeArea 之外。命中盒 = 视觉圆底外扩到命中下限，视觉圆底在外扩盒内
    // 居中、位置逐位不变。
    final portraitRotateRect = portraitDevice && !widget.recording
        ? portraitRotateButtonRect(
            pictureArea: portraitPictureAreaRect(
              screen: media.size,
              systemTopInset: media.padding.top,
              skeleton: widget.skeleton,
            ),
          ).inflate((kHitTargetMinSize - kRotateButtonVisualSize) / 2)
        : null;
    return Material(
      key: const Key('control_layer'),
      // 透明主体（不整屏压暗）：视频全屏 contain 背景保持干净，各 chrome 浮层
      // （顶栏/轨道带/工具条）自带深色半透明底；TrackBand ≈黑60% 直接叠于
      // 视频上、不被整屏 0.55 叠加加深。
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 第一层：各 chrome 与中部空白手势面。本层覆盖序 = 本层 → 竖屏转屏钮
          // → 气泡覆盖层，末尾再叠横屏「转为竖屏」钮。
          SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(),
                    // 中部：画面区占位（单击收起控制层）。竖屏行（09）：
                    // 画面按骨架落位两分支绘制在内容区之内，本层不画
                    // 画面。横屏行（06）：「转为竖屏」矩形钮不在本段
                    // 内——它按屏幕坐标画在 SafeArea 之外（见上），锚只由画面
                    // 矩形与系统栏内缩推出，与中带容器内固定值无关。
                    Expanded(child: _buildBlankArea()),
                    // 竖屏视频播放工具栏两行：横屏住在顶栏的九枚看片
                    // 工具搬进画面正下方（设置条之上）。
                    if (portraitDevice) _buildVideoToolRows(),
                    // 轨道带（骨架）：浮于视频下部、底部工具条上方——轨道手柄带行最底、
                    // 其上节拍轨（占位刻度）、学习段轨空轨。
                    // 轨道空白单击 → 收起（onCollapse 接线）。空白区
                    // 单击经约 300ms 判定窗口、单指双击 = 只切播放（不收起）、
                    // 双指双击 = 收起 + 延迟播放。捏合窗口、预览线显示值与拖动
                    // 标记、微调会话、跨面双指会话统一住在会话域里——本层与本带各持同
                    // 一个引用。轨道带的输入
                    // 值对象在这里唯一构造：会话域句柄、宿主动作回调
                    // 与行集一处给全。
                    // 设置簇：轨道带外右上角右对齐一行
                    // [预览吸附开关｜锁定分段｜缩放滑条]；缩放仍以播放头为锚、
                    // 与轨道带/空白捏合共享同一会话域；无时间线时整簇隐藏
                    // （簇内自判）。
                    // 设置条行盒即命中盒（下限档）。
                    // 行内控件之外落点与空白区同语义（同一空白手势面：缩放
                    // 识别器、单击收起、指针簿记都接 [_blankSurface]）。
                    _buildSettingsStrip(),
                    TrackBand(
                      input: TrackBandInput(
                        session: _session,
                        // 行集由宿主按模式值一处映射后注入——轨道带
                        // 对模式保持无知。
                        rowTable: widget.rowTable,
                        onCollapse: widget.onCollapse,
                        onDoubleTap: _onBlankDoubleTap,
                        onTwoFingerDoubleTap: _onBlankTwoFingerDoubleTap,
                        onScrubCommitted: widget.onScrubCommitted,
                      ),
                    ),
                    // 底栏两行拆分只看设备方向（对比态竖屏同样拆两行；
                    // 对比态仅画面层不进骨架分支）。
                    _buildToolbar(portrait: portraitDevice),
                  ],
                ),
              ],
            ),
          ),
          // 竖屏转屏钮：被气泡覆盖层压住时不可点，正是「点泡外收起」要的语义。
          if (portraitRotateRect != null)
            Positioned.fromRect(
              rect: portraitRotateRect,
              child: _PortraitRotateButton(
                onPressed: () =>
                    widget.onRequestOrientation(ScreenOrientation.landscape),
              ),
            ),
          // 气泡覆盖层：压住其下所有常驻件（含转屏钮），与观看态同铺法全屏铺开。
          _buildBubbleOverlay(),
          // 横屏「转为竖屏」钮（06）：SafeArea 之外、屏幕坐标，与
          // 顶栏/返回键同一条内缩线——见 [landscapeToPortraitButtonRect]。
          if (buttonRect != null)
            Positioned.fromRect(
              rect: buttonRect,
              child: _LandscapeToPortraitButton(
                visualTopOffset: buttonVisualTopOffset,
                onPressed: () =>
                    widget.onRequestOrientation(ScreenOrientation.portrait),
              ),
            ),
        ],
      ),
    );
  }

  // ---- 顶部栏 ----

  Widget _buildTopBar() {
    // 竖屏顶栏只剩返回键与标题（标题拿回整行宽、跑马字幕照旧）；
    // 横屏顶栏十三条工具内联一行。一行渲染的槽位集就是该行的全部槽位。
    // 顶栏**行集**由「模式 → 顶栏行集」唯一映射给出（
    // `play_tool_table.dart` 的 [playToolTopBarRowFor]）：投屏态两值取自己
    // 那份三枚行集（与朝向、紧凑档无关），其余取值沿用朝向与紧凑档；活值
    // 由装配点按槽身份装配。
    final portrait = widget.skeleton.portrait;
    final session = ref.watch(playerSessionProvider);
    final mode = session.mode;
    final casting = session.isCast;
    // 返回键 tooltip 与实际动作一致：对比-控制层内第一次返回只
    // 退对比态回单画面（见宿主 `_onControlLayerBack`）；投屏态内是
    // 「断开投屏」（同一动作的第二处入口）；其余状态下 pop 回来源页。
    final compareEditing = session.isCompare;
    // 装载未完成：改名入口按与其它写盘入口同一道门取不可用
    // 视觉（置灰），热区仍可点、点一下弹「正在装载」（见 [_onTitleRenameTap]）。
    final titleRenameIconColor = ref.watch(loadGateActiveProvider)
        ? kToolSlotDisabledIconColor
        : kTopBarRenameIconColor;
    return Container(
      key: const Key('control_layer_top_bar'),
      color: Colors.black.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 工具行的可用宽 = 顶栏内容宽 − 返回键 − 工具间隙（两落点共用
            // 一条算式）。
            final toolsMaxWidth =
                constraints.maxWidth - kTopBarBackWidth - kTopBarToolsGapWidth;
            return Row(
              children: [
                IconButton(
                  key: const Key('control_layer_back'),
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 24,
                  ),
                  tooltip: casting
                      ? '断开投屏'
                      : (compareEditing ? '退出对比' : '返回来源页'),
                  focusColor: kKeyboardFocusHighlight,
                  onPressed: widget.onBack,
                ),
                Expanded(
                  // 顶栏署名编辑入口：热区 = 整条
                  // 标题 + 尾部铅笔图标，横向随标题收缩、上限 = 标题可用宽；**长
                  // 标题时**整体右缩 [kTopBarRenameRightInset]，使图标不进入工具
                  // 间隙死区（该空隙两侧都不接点击）。
                  // 文本包在 `Flexible` 里——否则长标题按 intrinsic 宽撑破热区、
                  // 压到工具行上。
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 「长标题」= 文本单份宽超出「不右缩时的可用文本宽」（热区
                      // 上限 − 间隙 − 图标），与 [AutoScrollTitle] 的溢出判定同源；
                      // 能单份完整显示的标题不右缩（上限 = 今天标题的可用宽）。
                      final fits =
                          _topBarTitleTextWidth(context) <=
                          constraints.maxWidth -
                              kTopBarRenameIconGap -
                              kTopBarRenameIconSize;
                      // 尾部铅笔图标仅在标题位放得下「间隙 + 图标」时显示
                      //（看片工具到 13 位后，大字号下
                      // 标题位可能被挤到 18dp 以下——热区行不再容纳图标，
                      // 改名入口的语义按钮与热区本体仍在，不溢出）。
                      final showRenameIcon =
                          constraints.maxWidth >=
                          kTopBarRenameIconGap +
                              kTopBarRenameIconSize +
                              kTopBarRenameIconMinTitleFloor;
                      return Align(
                        key: const Key('control_layer_title_slot'),
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: fits ? 0 : kTopBarRenameRightInset,
                          ),
                          child: Semantics(
                            button: true,
                            label: '重命名',
                            child: GestureDetector(
                              key: const Key('control_layer_rename'),
                              behavior: HitTestBehavior.opaque,
                              onTap: _onSignatureEditTap,
                              child: SizedBox(
                                height: kTopBarRenameHotZoneHeight,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 顶栏标题自动滚动：溢出时匀速向左
                                    // 循环 + 边缘淡出，未溢出静止单份显示（滚动
                                    // 与裁剪在 [AutoScrollTitle] 内部，不改
                                    // 其行为）。
                                    Flexible(
                                      child: AutoScrollTitle(
                                        key: const Key('control_layer_title'),
                                        text: widget.title,
                                        style: _kTopBarTitleStyle,
                                      ),
                                    ),
                                    if (showRenameIcon) ...[
                                      const SizedBox(
                                        width: kTopBarRenameIconGap,
                                      ),
                                      Icon(
                                        Icons.drive_file_rename_outline,
                                        key: const Key(
                                          'control_layer_rename_icon',
                                        ),
                                        size: kTopBarRenameIconSize,
                                        color: titleRenameIconColor,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (!portrait) ...[
                  const SizedBox(width: kTopBarToolsGapWidth),
                  // 顶栏行集按「模式 → 顶栏行集」唯一映射取：投屏态两值
                  // 取投屏态那份行集；其余取值沿用朝向与紧凑档（紧凑档 →
                  // 紧凑行集，音画同步/取景调整/节拍提示收在「更多」的向上
                  // 弹出菜单里；常规档 → 常规行集）。选择只有
                  // [playToolTopBarRowFor] 一处。
                  _playToolRow(
                    playToolTopBarRowFor(
                      mode: mode,
                      portrait: false,
                      compact: _compactLandscape,
                    ),
                    maxWidth: toolsMaxWidth,
                  ),
                ] else ...[
                  // 撤销/重做/投屏/查看引导落竖屏标题栏右侧（返回键与标题
                  // 之后，与标题之间留既有工具间隙）；行集同样取
                  // [playToolTopBarRowFor]（竖屏标题栏，投屏态换成投屏那份）。
                  const SizedBox(width: kTopBarToolsGapWidth),
                  _playToolRow(
                    playToolTopBarRowFor(
                      mode: mode,
                      portrait: true,
                      compact: _compactLandscape,
                    ),
                    maxWidth: toolsMaxWidth,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// 镜像点击立即生效（简化镜像开关并入控制层工具区）。
  /// 装载未完成：写盘入口被同一道门挡下——弹「正在装载」、
  /// 镜像值一位不动。
  void _toggleMirror() {
    if (loadGateBlocksWrite(ref, PageWriteEntryId.mirrorSwitch)) return;
    final mirror = widget.mirror;
    mirror.chooseMirrored(!mirror.mirrored);
  }

  /// 标题单份文本宽（与 [AutoScrollTitle] 内部同一量法与样式）：只服务
  /// 「长标题」判定（是否右缩）。
  double _topBarTitleTextWidth(BuildContext context) {
    return measureTextExtent(
      widget.title,
      _kTopBarTitleStyle,
      scaler: MediaQuery.textScalerOf(context),
      direction: Directionality.of(context),
      maxLines: 1,
    ).width;
  }

  /// 标题热区点击：装载未完成时按页级入口门挡下（弹「正在
  /// 装载」、不开命名框、无写入）；否则交宿主打开 `rename` 场景。
  void _onSignatureEditTap() {
    if (loadGateBlocksWrite(ref, PageWriteEntryId.signatureEdit)) return;
    widget.onEditSignature();
  }

  /// 「对比练习」开关：对比-控制层点按 = 退出对比态回单画面
  /// （编辑面——本出口需保持控制层承接面以继续编辑，故不经 [
  /// PlayerSessionModel.exitCompare]；返回箭头/系统返回的对比态出口才回
  /// watching）；编辑面点按 = 进入对比-播放态（落待办，
  /// 宿主编排后经唯一提交入口提交——控制层随进入收起、分屏呈现）。进入
  /// 前置逐值声明见 [playerSessionEntryDeclarationTable]；`compareWatching`
  /// 的进入前置 = 相机授权，由宿主编排的相机门承接。校准会话
  /// 进行中拒绝进入（互斥）：静默 no-op、模式值与会话值一位不动。
  void _toggleCompare() {
    final session = ref.read(playerSessionProvider);
    if (session.mode == PlayerSessionMode.compareEditing) {
      ref.read(playerSessionProvider.notifier).enter(PlayerSessionMode.editing);
      return;
    }
    if (ref.read(avSyncCalibrationSessionProvider).active) return;
    ref
        .read(playerSessionProvider.notifier)
        .requestEntry(PlayerSessionMode.compareWatching);
  }

  /// 「投屏」工具：编辑面点按 = 落待办进入投屏-控制层（进入前置 =
  /// 投屏准备，见 [playerSessionEntryDeclarationTable]）：宿主依次开准备面板、
  /// 起递出通道与投屏会话，成功才经唯一提交入口提交；取消或起投失败零副作用
  /// （模式值一位不动、待办清空）。已在投屏态内时本枚不在顶栏（换装成
  /// 「断开投屏」），此支不承担断开——断开是 [ControlLayer.onDisconnectCast]。
  ///
  /// **五条门先在这里拦下**（票 #35）：门命中时本枚已置灰（可点性经共用判定
  /// 表派生，见 `play_tool_row.dart`），按下去只弹一句原因——**不落待办、
  /// 不开面板**。判定用与置灰同一份事实（[castEntryFactsProvider]），
  /// 不重算一套。
  void _toggleCast() {
    if (ref.read(playerSessionProvider).isCast) return;
    if (castEntryBlocksStart(
      ref,
      facts: ref.read(castEntryFactsProvider(widget.videoFilePath)),
    )) {
      return;
    }
    ref
        .read(playerSessionProvider.notifier)
        .requestEntry(PlayerSessionMode.castControl);
  }

  /// 取景调整：装载未完成门挡下并弹既有提示；
  /// 点按目标按当前态分派（对比-控制层 → 分屏取景，其余编辑面 → 单画面
  /// 取景），两路都落待办、经唯一提交入口提交。
  void _toggleFramingAdjust() {
    if (loadGateBlocksWrite(ref, PageWriteEntryId.framingAdjust)) return;
    final session = ref.read(playerSessionProvider);
    ref
        .read(playerSessionProvider.notifier)
        .requestEntry(
          session.mode == PlayerSessionMode.compareEditing
              ? PlayerSessionMode.compareFraming
              : PlayerSessionMode.framing,
        );
  }

  /// 「查看引导」进新手引导页：与帮助中心首项是同一页。
  void _openGuideUnits() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const GuideUnitsPage()));
  }

  /// 局部镜像总开关点击：有片段 → 取反并立即生效 + 写盘；无片段
  /// → 置灰槽位的软门，弹居中轻提示「请添加局部镜像片段」，不改任何状态、
  /// 不入撤销史。
  void _toggleLocalMirror() {
    // 装载未完成：同 `_toggleMirror`——弹「正在装载」、值不动。
    if (loadGateBlocksWrite(ref, PageWriteEntryId.mirrorSwitch)) return;
    if (ref.read(localMirrorFragmentsProvider).isEmpty) {
      ref
          .read(noticeTriggerProvider(NoticeId.localMirrorEmpty).notifier)
          .show();
      return;
    }
    final mirror = widget.mirror;
    mirror.setLocalMirrorEnabled(!mirror.localMirrorEnabled);
  }

  /// 倍速/步进气泡开关：同模式再点收起、异模式直接替换（互斥）。
  /// 角标触发（改会话单点）：气泡打开 = 对应功能被真正
  /// 使用（收起不触发），触发与「关气泡收场置位」统一在
  /// [SpeedBubbleSession.open] / [SpeedBubbleSession.close]。
  void _toggleBubble(SpeedBubbleMode mode) {
    final session = ref.read(speedBubbleSessionProvider);
    final bubble = ref.read(speedBubbleSessionProvider.notifier);
    if (session.open == mode) {
      bubble.close();
      return;
    }
    bubble.open(mode);
  }

  /// 音画同步动作本体（槽位与「更多」菜单条目共调，只有这一份）。
  ///
  /// 互斥：从对比态进校准会话先走对比态退出（回编辑面，
  /// 单画面），再开气泡——校准会话自身的统一退出路径（含丢弃试听
  /// 值）照旧。两条互相冲突的播放态主张（进入即暂停 vs 进入即续播）
  /// 从此只有一个成立。
  void _activateAvSync() {
    if (ref.read(playerSessionProvider).isCompare) {
      ref.read(playerSessionProvider.notifier).enter(PlayerSessionMode.editing);
    }
    _toggleBubble(SpeedBubbleMode.avSync);
  }

  /// 节拍提示动作本体（槽位与「更多」菜单条目共调，只有这一份）。
  void _activateBeatPrompt() => _toggleBubble(SpeedBubbleMode.beat);

  /// 气泡覆盖层：锚定对应工具图标下方、点气泡外收起（接线为共享
  /// [SpeedBubbleHost]，与观看态同一组件与状态来源）。「节拍提示」
  /// 工具气泡并入同一宿主，锚定其工具下方。
  ///
  /// 气泡**水平中心**与触发按钮中心对齐
  /// （bottomCenter/topCenter）；
  /// 居中放不下时由宿主水平钳制进屏（近右缘图标下右缘不溢出）。
  ///
  /// 紧凑档横屏下音画同步与节拍提示（含节拍侧另两个气泡）的锚点在「更多」
  /// 钮上：这两枚不在紧凑档横屏顶栏，各自工具的锚点不在场
  /// （`showWhenUnlinked: false` 会让气泡不显示），故本层按同一档位取
  /// [_moreLink]。常规档下两枚常驻顶栏，各读自己的锚点。
  Widget _buildBubbleOverlay() {
    final compactLandscape = _compactLandscape;
    return SpeedBubbleHost(
      linkFor: (mode) => switch (mode) {
        SpeedBubbleMode.speed => _speedSettingsLink,
        SpeedBubbleMode.avSync => compactLandscape ? _moreLink : _avSyncLink,
        // 节拍侧三气泡（节拍提示／节拍对齐／节拍倍频，/03）锚
        // **同一入口链接**（「节拍提示」工具）——后两个从「节拍提示」气泡
        // 内部打开，锚点必须与入口同一个。
        SpeedBubbleMode.beat ||
        SpeedBubbleMode.beatAlign ||
        SpeedBubbleMode.beatDensity =>
          compactLandscape ? _moreLink : _beatPromptLink,
      },
      targetAnchor: Alignment.bottomCenter,
      followerAnchor: Alignment.topCenter,
      offset: const Offset(0, 4),
    );
  }

  // ---- 中部轨道区占位 ----

  // 中部视频可见区 = 非交互空白区。本区只挂一个 scale 识别器（独占
  // arena，按下即胜出）：双指捏合缩放轨道时间轴；scale 会话空闲结束上报
  // [_blankTapArbiter] 判定单击（约 300ms 窗口后收起）/单指双击/双指双击。
  // 结构上不含任何交互子控件，交互控件（顶栏/工具条/面板）都在本区之外 →
  // 点击即时不受双击判定窗口延迟。
  //
  // 本区结构上不含编辑内容（段体/线/预览条都在轨道
  // 带内，内容命中检查见 track_band）——双指双击「仅空白区识别」在本区由
  // 区域互斥天然满足；单指水平占优 = 全屏式微调（见 _onBlankScaleUpdate）
  // 会话结束不进入空白单击判定（铁律闩锁 _blankMaxDisplacement）。

  /// 孤立单指单击（约 300ms 判定窗口后）：收起控制层（铁律：收起仅由静止
  /// 单击触发）。空白收起不针对选中线 → 先清除。
  void _onBlankSingleTap() {
    ref.read(annotationSelectionDomainProvider).clear();
    widget.onCollapse();
  }

  /// 单指双击（第二次 tap 完成时触发）：只切换播放/暂停、**保留编辑态不
  /// 收起**。
  /// 播放控制不针对选中线 → 清除。
  void _onBlankDoubleTap() {
    ref.read(annotationSelectionDomainProvider).clear();
    widget.onTogglePlay();
  }

  /// 双指双击（第二次 tap 完成时触发）：收起并启动延迟播放（八拍倒计时 +
  /// 提示音、任意操作中断）。收起先于触发——
  /// 不残留展开态。仅非交互空白区识别
  /// （段体/分段线/首尾线/预览条上的指针不进入判定）。
  /// 清除归入共享的收起+触发路径（见 [_collapseAndStartDelayedPlay]）。
  void _onBlankTwoFingerDoubleTap() {
    _collapseAndStartDelayedPlay();
  }

  /// 收起控制层并触发延迟播放：工具条延迟钮与空白区
  /// 双指双击走同一条路径、同一次交互内完成，收起先于触发——不在展开态里
  /// 留下延迟。预备期屏幕正中没有占位徽章，可见反馈 =
  /// 数拍浮层与视频区正中大数字。两条入口在此之前的簿记也同款：清除选中
  /// （「其它操作即清除」）。
  void _collapseAndStartDelayedPlay() {
    ref.read(annotationSelectionDomainProvider).clear();
    widget.onCollapse();
    widget.onDelayedPlay();
  }

  // ---- 空白面手势内容层（簿记与仲裁在 [_blankSurface]） ----

  /// 空白 scale 会话开始（内容钩子；簿记复位已由模块完成）：清除选中
  /// 防御性微调收尾、双指捏合基准与锚点快照（锚点 = 预览线显示
  /// 值在窗内则取它，否则按下瞬间双指中点经全宽时间轴映射——视频可见区与
  /// 轨道带同宽，映射与轨道带一致；scale 识别器位移过阈才回调、焦点已偏离
  /// 真实中点，取按下点）。
  void _onBlankSurfaceScaleStart(ScaleStartDetails d) {
    // 「其它操作即清除」：空白缩放/微调 scrub 会话不针对选中线。
    ref.read(annotationSelectionDomainProvider).clear();
    // 防御性复位：若上一会话被系统取消而未走收尾（scale 无 cancel 钩子），
    // 微调会话可能滞留暂停态——先收尾（恢复手势前播放态）再开新会话。
    unawaited(_session.endFineScrub());
    if (d.pointerCount < 2) return;
    // 起手帧只把带宽与**按下瞬间**各指针的面内局部 x 推给会话域：按下中点
    // 的求值、基准窗口、锚时间与整场累计换算都住在那里（锚点的「手指下
    // 时间」= 预览线显示值，判定规则见 pinchAnchorTime）。控制层宽即空白面
    // 捏合的换算带宽（见会话域库头两套口径）。按下点 → 局部 x 的映射与
    // 带内共用 localDownXs。
    final box = context.findRenderObject();
    final w = box is RenderBox ? box.size.width : 0.0;
    _session.beginPinch(
      surface: TrackPinchSurface.blank,
      width: w,
      downXs: box is RenderBox
          ? localDownXs(_blankSurface.pointerDownPositions, box.globalToLocal)
          : const [],
      fallbackFocalX: d.localFocalPoint.dx,
    );
  }

  /// 空白 scale 会话结束（内容钩子；微任务 tap 仲裁已由模块收口）：清捏合
  /// 基准并收尾微调会话（微调收尾含拖动标记复位；!isActive 时 no-op）。
  void _onBlankSurfaceScaleEnd(ScaleEndDetails d) {
    _session.endPinch();
    unawaited(_session.endFineScrub());
  }

  /// 设置簇实例（会话句柄注入的唯一构造点）：竖屏独立行与横屏空白区底缘
  /// 两个落点按骨架二选一挂载。
  Widget _settingsCluster() => SettingsCluster(session: _session);

  /// 设置条行：行盒撑到命中下限后，行内控件
  /// 之外的落点保持空白区语义——本行挂同一空白手势面（缩放识别器 + 指针
  /// 簿记都接 [_blankSurface]），横滑 seek、单击收起与空白区逐字相同。
  Widget _buildSettingsStrip() {
    // 无时间线时簇自收 0 高，本行随之整体让位（可见性判定与簇内自判读
    // 同一出处 [settingsStripVisibleFor]）。
    if (!settingsStripVisibleFor(ref.watch(playbackEngineProvider).duration)) {
      return const SizedBox.shrink();
    }
    // 行盒即命中盒（48）。竖屏行距容得下，独立
    // 行给足 48；横屏短高下固定行（顶栏/轨道带/工具条，大字号还会长高）
    // 合计后行距容不下 48——整行不占槽，改画进上方空白区的底缘（见
    // [_buildBlankArea]，该处紧贴轨道带上缘、落位不变），空白手势面在
    // 控件之外照常生效，横屏竖向排版容量与大字号行为与基线逐字相同。
    if (widget.skeleton.portrait) {
      return SizedBox(
        height: kHitTargetMinSize,
        child: _blankGestureSurface(child: _settingsCluster()),
      );
    }
    return const SizedBox.shrink();
  }

  /// 空白手势面：不透明缩放识别层 + 指针簿记（同一 [_blankSurface]
  /// 会话）。空白区与设置条行两处共用同一拼装、同一会话。
  Widget _blankGestureSurface({
    Key? detectorKey,
    Widget? child,
    Widget? bottomOverlay,
  }) {
    return Listener(
      onPointerDown: _blankSurface.pointerDown,
      onPointerMove: _blankSurface.pointerMove,
      onPointerUp: _blankSurface.pointerUp,
      onPointerCancel: _blankSurface.pointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            key: detectorKey,
            behavior: HitTestBehavior.opaque,
            onScaleStart: _blankSurface.scaleStart,
            onScaleUpdate: _blankSurface.scaleUpdate,
            onScaleEnd: _blankSurface.scaleEnd,
            child: const ColoredBox(color: Colors.transparent),
          ),
          ?child,
          if (bottomOverlay != null)
            Positioned(left: 0, right: 0, bottom: 0, child: bottomOverlay),
        ],
      ),
    );
  }

  // ---- 竖屏编辑面骨架----

  Widget _buildBlankArea() {
    // 视频可见区空白（双击共存语义 + 捏合全域）：见上方注释；手势面拼装
    // 与设置条行共用 [_blankGestureSurface]。
    return _blankGestureSurface(
      detectorKey: const Key('control_layer_blank'),
      // 设置簇：横屏不占独立行，贴空白
      // 区底缘、右对齐一行，行盒即命中盒（48）；竖屏走独立行（见
      // [_buildSettingsStrip]）。
      bottomOverlay: widget.skeleton.portrait ? null : _settingsCluster(),
    );
  }

  // ---- 底部工具条 ----

  Widget _buildToolbar({required bool portrait}) {
    // 竖屏底栏拆两行——标注工具行在上（该态槽集全部内联），播放
    // 控制工具行在下（播放控制组 + 帧号读数，读数字号 12 以容下「当前 /
    // 总长」两段）；横屏行走既有单行装配。两行的槽位集都是各行的全部槽位。
    //
    // **槽集为空 = 标注工具行整排不出现**（投屏态：分段只读是结构性的，
    // 无槽可选）：空集下不画那一条行盒，不留空占位。播放控制组照常在场
    // ——投屏态里它是遥控电视的那一条路。
    final hasSlots = _slotTable.slots.isNotEmpty;
    return Container(
      key: const Key('control_layer_toolbar'),
      color: kControlToolbarScrimColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: portrait
            ? Column(
                children: [
                  if (hasSlots) _buildAnnotationToolRow(),
                  Row(
                    children: [
                      ..._buildPlaybackControls(),
                      _timeReadoutCell(12),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  ..._buildPlaybackControls(),
                  _timeReadoutCell(14),
                  ?_segmentDensityReadout(),
                  // 工具组整体右对齐：标注工具组紧
                  // 贴右缘；一行渲染的槽位集就是该行的全部槽位。
                  // 大字号下槽件自然高超出名义行高 48 时整组等比缩小（与
                  // 标注工具行同一口径：缩小仍可辨，撑破底栏则整列溢出）；
                  // 名义档内零缩放、取值不变。
                  if (hasSlots)
                    SizedBox(
                      height: 48,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: _ToolSlotRow(
                          table: _slotTable,
                          mirror: widget.mirror,
                          session: _session,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// 播放控制按钮组（提行复用）：播放/暂停、延迟播放、左移一步、
  /// 右移一步——横屏底栏左段与竖屏播放控制工具行同一份装配。
  ///
  /// **投屏态内两枚遥控项由接收端能力判据决定在不在**（票 #38）：「播放暂停」
  /// 与「进度（帧步进）」判据说这一项不显示（探测不到 / 探测失败 / 设备确实
  /// 不支持）就不进装配——按下去没反应的控件不留（`CastRemoteControls` 是
  /// 唯一判据；非投屏态两枚恒在，行为逐位不变）。
  List<Widget> _buildPlaybackControls() {
    final isCast = ref.watch(playerSessionProvider).isCast;
    final remoteControls = ref.watch(castRemoteControlsProvider);
    final showsPlayPause =
        !isCast || remoteControls.shows(CastRemoteItem.playPause);
    final showsProgress =
        !isCast || remoteControls.shows(CastRemoteItem.progress);
    return [
      // 播放/暂停、延迟播放（与空白区双指双击同一条路径
      // ——收起 + 触发）。
      if (showsPlayPause)
        IconButton(
          key: const Key('toolbar_play'),
          icon: Icon(
            widget.playing ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
            size: 28,
          ),
          tooltip: widget.playing ? '暂停' : '播放',
          focusColor: kKeyboardFocusHighlight,
          onPressed: widget.onTogglePlay,
        ),
      IconButton(
        key: const Key('toolbar_delayed_play'),
        icon: const _DelayedPlayIcon(),
        tooltip: '延迟播放（一个八拍后开始）',
        onPressed: _collapseAndStartDelayedPlay,
      ),
      // 帧步进：目标优先级与门禁语义见 [_stepFrame]；
      // 长按连续步进：文案固定「左移/右移一步」，选中线/端标
      // 时不做长按连续（见 [_stepTargetSelected]）。
      if (showsProgress)
        _FrameStepButton(
          buttonKey: const Key('toolbar_frame_step_back'),
          icon: Icons.chevron_left,
          tooltip: '左移一步',
          holdToRepeat: !_stepTargetSelected,
          onStep: () => _stepFrame(-1),
        ),
      if (showsProgress)
        _FrameStepButton(
          buttonKey: const Key('toolbar_frame_step_forward'),
          icon: Icons.chevron_right,
          tooltip: '右移一步',
          holdToRepeat: !_stepTargetSelected,
          onStep: () => _stepFrame(1),
        ),
      const SizedBox(width: 8),
    ];
  }

  /// 竖屏标注工具行：该态槽集**全部**槽位单行内联——一行即
  /// 全部槽位（横竖屏一致）。整行贴右缘与横屏标注工具组同一口径；门禁与
  /// 次序逐位沿用槽集声明。
  Widget _buildAnnotationToolRow() {
    // 槽件内容自然高 48；上下各 2 内边距使单行与播放行的钮档同为名义高 52
    //（渲染对比断言钉住）。
    final densityReadout = _segmentDensityReadout();
    return Padding(
      key: kAnnotationToolRowKey,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          ?densityReadout,
          // 大字号不溢出：六/七槽在窄竖屏放不下
          // 时整行等比缩小，与 [_buildVideoToolRows] 同一「居中件 + 无界量测
          // + 按可用宽缩」口径——[Expanded] + [Align] 给 [FittedBox] 可用宽
          // 约束，放得下零缩放、放不下才 [BoxFit.scaleDown]；标签不裁字、
          // 行不越出控制层。
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _ToolSlotRow(
                  table: _slotTable,
                  mirror: widget.mirror,
                  session: _session,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 段内倍频读数：只在段内倍频待命态且有
  /// 选中时非 null（横屏行与竖屏标注行同一枚单元）；显示选中段的段内档，
  /// 多段档位不一时显示最小档（与熟练度槽显示最低档同一先例）。
  Widget? _segmentDensityReadout() {
    if (ref.watch(playerSessionProvider).mode !=
        PlayerSessionMode.segmentDensityStandby) {
      return null;
    }
    final selected = ref.watch(selectedLearningSegmentsProvider);
    if (selected.isEmpty) return null;
    final densities = ref.watch(segmentDensitiesProvider);
    final lowest = selected
        .map((order) => densities[order] ?? 1)
        .reduce((a, b) => a < b ? a : b);
    return Padding(
      key: const Key('segment_density_readout'),
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Text(segmentDensityLabel(lowest)),
    );
  }

  /// 本态底排槽集：取「模式 → 界面」声明表（横屏行与竖屏标注行共用同一份
  /// 答案，映射不在此另写）。
  ToolSlotTable get _slotTable =>
      sessionModeSurfacesOf(ref.watch(playerSessionProvider).mode).slotTable;

  /// 帧号读数单元（共用）：Expanded 左对齐独占剩余
  /// 宽——横屏底栏中段与竖屏播放控制工具行同一装配，字号由行决定。
  Widget _timeReadoutCell(double fontSize) {
    return Expanded(
      child: Align(
        alignment: Alignment.centerLeft,
        child: _TimeReadout(fontSize: fontSize),
      ),
    );
  }
}

/// 顶栏工具区与标题的间隙宽（Row 内同步使用）。它与标题改名热区的
/// [kTopBarRenameRightInset] 右缩合起来构成**死区**：标题热区到死区左缘
/// （= 工具行左缘 − 本值 − 右缩）为止，工具行从它右缘开始，中间不接点击。
const double kTopBarToolsGapWidth = 8.0;

/// 顶栏返回键的最小宽（IconButton 默认最小边 [kMinInteractiveDimension]）；
/// [_playToolRow] 的可用宽判据按它预留返回键的位。
const double kTopBarBackWidth = kMinInteractiveDimension;

// ── 顶栏标题改名热区 token──
// 入口 = 控制层顶栏的标题本身（整条标题 + 尾部铅笔图标），不另设按钮。

/// 标题改名热区高度（热区随标题横向收缩，纵向恒为本值）。取命中盒下限。
const double kTopBarRenameHotZoneHeight = kHitTargetMinSize;

/// 标题位容纳「间隙 + 图标」之外的最小文本宽：
/// 低于它铅笔图标退场、只留语义按钮与热区本体——40dp ≈ 4 字标题在基准
/// 字号下的单份宽，保住「图标可见即标题可读」的工效下限。
const double kTopBarRenameIconMinTitleFloor = 40.0;

/// 标题与尾部铅笔图标之间的间隙。
const double kTopBarRenameIconGap = 4.0;

/// 铅笔图标边长（非文本几何：字号两档只判文本，本值与系统字号无关）。
const double kTopBarRenameIconSize = 14.0;

/// 长标题时热区右缘相对标题可用宽的右缩量：图标与工具间隙死区之间留出
/// 可见空隙（热区右缘 = 死区左缘 − 本值）。
const double kTopBarRenameRightInset = 8.0;

/// 标题改名图标正常态颜色（装载未完成时改取 [kToolSlotDisabledIconColor]）。
const Color kTopBarRenameIconColor = Colors.white54;

/// 顶栏标题文本样式：热区的「长标题」判定与 [AutoScrollTitle] 渲染共用同
/// 一份，两处测量不会漂移。
const TextStyle _kTopBarTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 15,
);

/// 工具条左侧当前/总时长读数（总长未知只显示当前）。
/// 语义档（随系统字号）：时间读数承载语义、随系统字号缩放，无覆写即吃环境
/// 缩放（[fontSize] 只是各版式的基准字号）。
class _TimeReadout extends ConsumerWidget {
  const _TimeReadout({this.fontSize = 14});

  /// 读数字号：竖屏播放控制行 12——两段「当前 / 总长」在真机
  /// 竖屏基准的剩余宽内放得下；横屏底栏 14。
  final double fontSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playbackEngineProvider);
    final total = engine.duration;
    final current =
        ref.watch(playbackPositionProvider).value ?? engine.position;
    // 帧号时间文本（mm:ss:ff，帧号自 0）与观看态 scrub 浮层共用
    // [formatFrameTime]；帧率源 = 引擎可暴露的 demux-fps，取不到回落
    // 默认 30fps 常量。
    final fps = engine.videoFps ?? kDefaultVideoFps;
    final text = total == null
        ? formatFrameTime(current, fps: fps)
        : '${formatFrameTime(current, fps: fps)} / '
              '${formatFrameTime(total, fps: fps)}';
    return Text(
      text,
      key: const Key('toolbar_time'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: Colors.white70, fontSize: fontSize),
    );
  }
}

/// 延迟播放图标：播放三角居中 + 右下角小时钟——与底部工具条
/// 那排播放控制同一图标语系，小时钟标出「延迟」语义。纯图标、无点击。
class _DelayedPlayIcon extends StatelessWidget {
  const _DelayedPlayIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Icon(Icons.play_arrow, color: Colors.white)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.schedule, color: Colors.white, size: 10),
          ),
        ],
      ),
    );
  }
}
