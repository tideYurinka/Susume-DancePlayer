/// 轨道带（带域骨架 + 预览条与时间缩放 + 空白手势语义）。
///
/// 展开态控制层内、视频下部（底部工具条上方）的半透明浮层轨道带
/// （横屏行）：
///
///   - 带内自下而上 = 轨道手柄带行（最底，无内容的背景行）→ 节拍轨（占位节拍刻度，
///     识别算法 P1）→ 学习段轨（空轨占位，片段在轨上点亮）→ 局部镜像轨
///     （常驻显示，片段经底部「局部镜像」槽创建/选中/拖动/删除）→ 备注轨
///     （36dp 常驻显示，备注片段块体只做呈现，交互归备注编辑模块）。
///   - 轨道带背景深色半透明（≈ 黑 60%）；标注片段/线不透明；
///   - 每轨高度按行表（track_row_table.dart），带高
///     ≈ 屏高 33%；
///   - 时间轴零点之左是**轨道片头**：行集之外的一列短文字标签
///     （行集声明的短标签），随窗口缩放/平移跟内容一起走、滑出可视带即不
///     画；它落在内容区之左（不侵占内容区），按在片头上等于按在带上空白
///     （例外只一条：片头在可视带内时，轨道手柄带行那一段归首线控制柄）。
///     内容映射因此起于 `kTrackPrefixWidth`（见 track_geometry.dart）。
///
/// 其上点亮：**贯穿轨道的预览条**（[Key('preview_line')]，
/// 显示当前播放位置并随播放更新）+ **时间密度缩放**——双指捏合（锚点时间
/// 缩放，焦点下方内容不动）与带外设置簇的缩放滑条（以播放头为锚，缩放后
/// 预览条屏上 x 不变；迁至轨道带外，见 settings_cluster.dart）；缩放
/// 状态 = 可视窗口（[TimelineWindow]，见 track_time.dart），
/// 节拍轨刻度只绘制窗口内格点（随新密度重排）。交互：
///
///   - 拖动预览条 → 帧级 seek：水平拖动（轴锁定：累计位移水平占优才定轴，
///     斜向起手的早期纵向抖动不误判为垂直忽略）把手指位置当预览条，每帧按
///     可视窗口换算目标时间入串行 latest-wins seek 队列（与 player_page
///     共用）；**未拖动的单击不算拖动、不 seek**（空白/收起
///     判定归本带）；
///   - 拖动时预览条贴近屏幕边缘 → 自动平移可视窗口（手指固定、内容随拖
///     移动）再换算目标 → 可持续越过当前可视范围 seek（预览条贴近
///     屏幕边缘时自动调整轨道显示范围）；判定带 = 左右各轨道带宽 ÷ 4
///     （该次量测所用视口下：竖屏 361.1 → 90.3、横屏 781.7 → 195.4），平移速度随侵入深度
///     线性递增且出缘恒 700px/s（与带宽无关），由拖动会话内 ticker 按时间
///     平滑累积（见 [edgePanZonePx] / [EdgePanSession]）；
///   - 播放中播放头越出可视窗口 → 自动跟随平移（[kPlayheadFollowFraction]）
///     保持可见；捏合、预览线拖动与拖线实时预览期间不自动跟随（这三条路径
///     自己写窗口；跟随的唯一求值在会话域，见 [TrackBandSession.followPosition]）。
///
/// **会话域**：可视窗口读写、预览线显示值、拖动进行中标记、编辑态微调
/// scrub 与跨面捏合五件住在 [TrackBandSession]
/// （组合根建唯一实例，经演出层输入—控制层下传）——本带只读它的读数、经它
/// 的入口落点与写窗口。窗口跟随因此只有会话域一处（[TrackBandSession.followPosition]
/// 在位置 tick 上做陈旧窗口归一与跟随），捏合锚点的「手指下时间」取预览线
/// 显示值，按下中点的求值也归会话域。
///
/// **入口**：本带收一个显式的输入值对象
/// [TrackBandInput]——会话域句柄、宿主动作回调与行集一次给全；生产侧的构造
/// 点是控制层（`control_layer.dart`）。
///
/// 半透明分层：本控件是控制层透明主体下的独立浮层，
/// 背景黑 60% 直接叠于 contain 视频上，不被整屏叠层加深（控制层不再整屏
/// 压暗，见 control_layer.dart）。设置簇（预览吸附开关/吸附网格/缩放滑条/
/// 延迟循环）迁至轨道带外右上角（settings_cluster.dart），带内不再
/// 渲染 dock；轨道底行为轨道手柄带（承载线的调整手柄）。
///
/// **依赖方向（单向）**：带级 → 七个带内层域
/// （练习片段轨 / 备注轨 / 局部镜像轨 / 学习段轨 / 节拍刻度 / 片段浮条 /
/// 轨道手柄带）、命中解析适配层、块体骨架共享件、拖动域与会话域、行表与
/// 几何/时间纯件、标注编辑模块——带级只组装，不转发；**反向不存在**：这七个
/// 行域、命中解析适配层、块体骨架、拖动域与会话域都不 import 本文件（方向
/// 不可逆），带内逐族簿记随族搬走。消费本文件的是
/// 上层组装点（控制层，`control_layer.dart` 构造 [TrackBandInput]）与带级
/// widget 套件——层域 → 带级不是域内反向读面。
library;

// 练习片段块的视觉常量随练习片段轨域走；带级仍对外暴露同一组名字（既有
// 引用面逐位不变）。
export 'track_practice_row.dart'
    show
        kPracticeClipActiveBlockColor,
        kPracticeClipActiveBorderWidth,
        kPracticeClipBlockColor,
        kPracticeClipBlockRadius,
        kPracticeClipSelectedBorderColor;

import 'dart:async' show scheduleMicrotask, unawaited;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/compare_materials.dart' show PracticeClip;
import '../annotation/annotation_timeline.dart';
import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart';
import '../annotation/transition_segment.dart';
import '../core/eight_beat_phase.dart'
    show adjacentBeatPoint, adjacentEightBeatPoint;
import '../core/playback/playback_engine.dart';
import '../help/content_registry.dart'
    show
        HandsOnCriterion,
        badgeHalfBeatUnitId,
        badgeLocalMirrorUnitId,
        badgeSegmentFlagUnitId,
        badgeSegmentUnitId,
        badgeThreeFingerJumpUnitId,
        editorIntroUnitId,
        firstLearningSegmentOrder,
        guideUnitStepsDone,
        halfBeatLineAnchorKeyBase,
        liveArtifactAnchorKeyOfBase,
        mirrorFragmentAnchorKeyBase,
        practiceRangeHeadAnchorKey,
        practiceRangeTailAnchorKey,
        practiceRangeUnitId,
        segmentLineAnchorKeyBase;
import '../help/guide_anchor.dart' show GuideAnchor, GuideBadgeTrigger;
import '../help/guide_state.dart' show GuideSessionState, guideSessionProvider;
import 'annotation_editor.dart'
    show
        AnnotationGestureTarget,
        annotationSelectionDomainProvider,
        annotationEditorProvider,
        annotationTimelineProvider,
        effectiveAnnotationTimelineProvider,
        learningEmphasisProvider,
        learningMasteryProvider,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider,
        practiceClipActivationProvider,
        practiceClipsProvider,
        selectedLocalMirrorFragmentIndexProvider,
        selectedNoteFragmentIndexProvider,
        selectedPracticeClipIdProvider,
        selectedSegmentLineIndexProvider,
        selectedVideoRangeBoundaryProvider,
        transitionSegmentProvider;
import 'annotation_selection.dart'
    show
        AnnotationSelectionDomain,
        LocalMirrorFragmentSelection,
        SegmentLineSelection,
        VideoRangeBoundary,
        VideoRangeBoundarySelection,
        selectedLearningSegmentsProvider;
import 'handle_strip.dart';
import 'track_handle_strip.dart';
import 'note_editor.dart' show noteFragmentHighlightProvider;
import 'note_sticker_overlay.dart' show noteMentionRosterColors;
import 'dancer_roster_controller.dart' show dancerRosterProvider;
import 'preview_snap.dart';
import '../stats/selection_haptic.dart' show selectionHapticProvider;
import '../player_session/player_session.dart' show playerSessionProvider;
import 'load_gate.dart' show loadGateActiveProvider;
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatPhaseProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'visual_tokens.dart';
import 'track_time.dart';
import 'track_row_table.dart';
import 'track_geometry.dart';
import 'track_mirror_row.dart';
import 'track_note_row.dart'
    show
        TrackNoteRow,
        TrackNoteRowInput,
        noteRowClearSelectionIfPlayheadLeftOwnWindow;
import 'track_band_session.dart';
import 'track_band_drag.dart';
import 'track_edge_pan.dart';
import 'track_practice_row.dart'
    show TrackPracticeRow, TrackPracticeRowInput, TrackPracticeRowTrim;
import 'track_hit_resolution.dart';
import 'advanced_gestures.dart';
import 'track_beat_ticks.dart';
import 'gesture_surface_session.dart';
import 'track_learning_row.dart';

// 学习段轨域的公开量测面（说明文字三档判定、其枚举与字号常量）：
// 本文件的读者（既有轨道带套件与帮助内容）经本 re-export 原样可达，符号的
// 唯一真源在 track_learning_row.dart。
export 'track_learning_row.dart'
    show
        LearningCaptionFit,
        kLearningCaptionFontSize,
        kLearningCaptionTextStyle,
        learningCaptionFit;

/// 节拍刻度域两个公开符号经本库转出：既有轨道带套件与测试夹具经本库读
/// 它们的旧入口——`beatAnalyzingFlowProvider`
/// （占位态流动开关覆盖缝）与 `kEightCountLabelSlotHeight`（刻度让位量测）。
export 'track_beat_ticks.dart'
    show beatAnalyzingFlowProvider, kEightCountLabelSlotHeight;

/// 贴边平移纯函数群经本库转出：既有轨道带套件经本库读它们的旧入口（速度曲线
/// 与判定带的量测），符号的唯一真源在 track_edge_pan.dart。
export 'track_edge_pan.dart'
    show
        edgePanDepthPx,
        edgePanShiftFor,
        edgePanVelocityPxPerSec,
        edgePanZonePx,
        kPlayheadEdgePanMaxVelocityPxPerSec,
        seekTargetForFingerX;

/// 预览线命中列宽：手柄带内起手判定用——起手落在预览线当前
/// 位置 ± 该宽/2 的列内时，本次拖动转预览线（不移动分段线）。取与控制柄
/// 槽目标宽 [kHandleSlotMaxWidth] 一致，保证预览线与线重合时整列让位。
const double kPreviewLineHitColumnWidth = kHandleSlotMaxWidth;

/// 分段线视觉宽：默认细线（1dp 浅色，真机直接绘制可见）；选中加粗反馈；
/// flag 是更强的进度标记。
const double kSegmentLineWidth = 1;
const double kSegmentLineSelectedWidth = 3;
const double kSegmentLineFlaggedWidth = 6;

/// 首/尾线视觉宽（区别于预览条的 2px 与分段线的细线样式）。
const double kVideoRangeLineWidth = 3;

/// 选中首/尾线后的加粗宽（可见的“选中”反馈）。
const double kVideoRangeSelectedLineWidth = 5;

/// 学习轨行内临时段触发窗单侧半宽上限（「临时段触发窗」分侧公式的 20dp
/// 顶帽项；实际分侧半宽见 `transition_segment.dart`
/// [transitionTriggerSideHalfWidths]，每侧按该侧邻学习段显示宽 10% 收窄）。
const double kTransitionTriggerMaxSideHalfWidthPx = kSegmentLineHitWidth / 2;

/// 轨道带输入：本带挂载所需的全部外部事实——会话域句柄、行集与宿主动作回调
/// （形状与「生产侧的构造点」见库头）。
class TrackBandInput {
  const TrackBandInput({
    required this.session,
    required this.rowTable,
    this.onCollapse,
    this.onDoubleTap,
    this.onTwoFingerDoubleTap,
    this.onScrubCommitted,
    this.onPreviewSnapHaptic,
  });

  /// 轨道带会话域：可视窗口读写、预览线显示
  /// 值、拖动进行中标记、编辑态微调 scrub 与跨面捏合五件的唯一持有者。由
  /// 控制层经演出层输入下传（组合根创建唯一实例）——「这五样要一起传」由
  /// 类型表达。
  final TrackBandSession session;

  /// 行集：本带渲染哪些行、什么次序、
  /// 各行多高与行间间隙的单一来源；「某态下有哪些行」由构造点传哪份行集
  /// 表达，本控件对「模式」保持无知。
  final TrackRowTable rowTable;

  /// 单击轨道空白收起控制层（单击经约 300ms
  /// 双击判定窗口后回调——空白区双击共存语义与全屏唤出一致；由控制层接线
  /// 宿主 onCollapse）。拖动/捏合是手势不是单击，不触发；设置簇等交互区
  /// 在带外兄弟浮层自行消费指针，不进入本判定。
  final VoidCallback? onCollapse;

  /// 空白区单指双击：只切换播放/暂停、**不收起**（保留编辑态）。仅非交互
  /// 空白区识别；段体/线/预览条等编辑内容不识别双击。
  final VoidCallback? onDoubleTap;

  /// 空白区双指双击：收起并启动延迟播放（八拍倒计时）。与捏合按位移
  /// 仲裁：位移过阈识别器让位 → 走缩放。
  final VoidCallback? onTwoFingerDoubleTap;

  /// 预览条（播放头）拖动收口落点回调：本会话发生过 scrub seek
  /// 时，会话结束以最终落点回调一次——宿主据此打「显式用户拖进度」放行
  /// 标记。拖线/捏合缩放不改播放位置，不回调。
  final ValueChanged<Duration>? onScrubCommitted;

  /// 预览线吸附震动回调：吸附目标进入/切换时触发一次；null =
  /// 系统轻触反馈（[HapticFeedback.selectionClick]）。测试注入记录器断言。
  final VoidCallback? onPreviewSnapHaptic;
}

/// 轨道带（契约终稿）。
///
/// **行集驱动**：本带渲染哪些行、什么次序、各行多高与行间间隙，全部由
/// 输入值对象的 [TrackBandInput.rowTable]（行集）给出；整带高由行集派生
/// （[TrackRowTable.totalHeight]），读取面 [TrackBand.height] 是缺省行集
/// `normal` 下的同一派生（非缺省行集的带高在 build 内直接读行集）。本控件
/// 对「当前处于哪种模式」保持无知——「某态下有哪些行」由构造点传哪份行集
/// 表达，换行集不改本控件。
///
/// **按行标识分派渲染**：行与行间隙由行集生成（列内子序 = 行集顺序），
/// 每行经 [_buildRow] 按行标识分派到各自渲染件，行高与行键取自行的
/// 声明；行不在本行集内时对应渲染件与覆盖层一并不渲染（见
/// [_rectIfPresent]）。行内装饰（刻度内缩、控制柄底偏移、镜像片段块
/// 内边距、学习段体填充）留在各自渲染件里。
///
/// **只读分工的留白**（本期未实施）：widget 侧将来按行
/// 能力决定置灰与手势是否参与；模块侧由唯一写入口执行门禁，形状为
/// 「一个门禁 N 个原因」，不建第二张平行动词表。本期本控件不引入
/// **行级可编辑性与带级只读**概念；既有「锁定分段」用户锁门禁照旧，
/// 是上述唯一写入口门禁在今天的一个原因。
///
/// 轨道带底行（轨道手柄带行）为**轨道手柄带**——分段线与首/尾线在此各有
/// 把手控制柄（32×18dp 胶囊把手），**拖动仅由控制柄起手触发**；控制柄槽按
/// 等分互斥分区分配（见 handle_strip.dart：相邻线中点分界、目标宽 ≤48、
/// 向外侧空余扩展优先）。线身保留单击（选中 toggle；flag 与普通线一致）
/// 但不整列按下即拖；学习/节拍/手柄带行空白仍可整带直接跟手滑预览条
/// （拖动可跨过线列不被抢）。分段线控制柄起手落在预览线命中列内时本次拖动
/// 转预览线（不移动线）。
class TrackBand extends ConsumerStatefulWidget {
  const TrackBand({super.key, required this.input});

  /// 本带挂载所需的全部外部事实（见 [TrackBandInput]）。
  final TrackBandInput input;

  /// 带高读取面：缺省行集 `normal` 派生的整带高
  /// （Σ行高 + 间隙 × (行数 − 1)），数值逐位沿用今天（四行 + 3 × 轨间隔）。
  /// 非缺省行集的带高由 [TrackBandInput.rowTable] 派生（build 内直接读
  /// totalHeight）。
  static double get height => TrackRowTable.normal.totalHeight;

  @override
  ConsumerState<TrackBand> createState() => _TrackBandState();
}

/// 轨道带手势会话的会话类别分发由 [GestureSurfaceSession] 相位/帧事件承担
/// 一指锁定 = scrub 帧事件、捏合会话 = pinch 帧事件，本控件只
/// 保留内容层（预览条 seek/贴边平移/捏合窗口换算/学习段点选）。

/// 视频首/尾边界（端标端别）：点选、线身渲染与键盘微调共用；拖动起手也据此
/// 构造目标身份 [TrackBandDragTarget.range]。
enum _VideoRangeDrag { start, end }

/// 非空锚点 key 时给 [child] 包一层锚点包装器（null 原样返回）——菜单类四
/// 条角标只在实物就是刚落成的那一个时才包，其余时刻被包内容逐位不变。
Widget _guideAnchored(String? anchorKey, Widget child) =>
    anchorKey == null ? child : GuideAnchor(anchorKey: anchorKey, child: child);

/// 拖动态 → 选中端标映射：start/end 拖动态各自对应同端标选中；
/// none 不参与（选中态不含「无」）。
extension _VideoRangeDragX on _VideoRangeDrag {
  VideoRangeBoundary get asSelectionBoundary => this == _VideoRangeDrag.start
      ? VideoRangeBoundary.start
      : VideoRangeBoundary.end;
}

/// 轨道片头：轨道最左、位于时间轴**零点之前**的一列短文字
/// 标签，是时间轴的第二根正交轴（行 × 片头）。
///
/// **行集之外**：它不是行集里的第七行——不带行高、不参与行矩形与行命中，
/// 纵向只是按该态行集的逐行行高与行间隙与所属行对齐（行集一行不加、一行
/// 不减）。标签文案与条数取自行自己声明的短标签（[TrackRowTable.prefixLabels]），
/// 没有第二份清单。
///
/// **随窗口走**：画在轨道内容坐标系里——调用点传入 [left]（= 时间轴零点
/// 屏上 x 减一个片头宽），窗口缩放/平移时跟内容一起移动；滑出可视带时由
/// 调用点整列不画。
///
/// **不参与命中**：整列是纯显示（[IgnorePointer]）——时间轴零点之左的那一
/// 条横向空白守卫已经在**位置**上把内容命中层挡在外面，片头只负责画；按在
/// 片头上等于按在带上空白（不选中、不拖动、不吸附任何内容），只有守卫让给
/// 首线控制柄的轨道手柄带行那一段例外。
class _TrackPrefix extends StatelessWidget {
  const _TrackPrefix({
    required this.left,
    required this.width,
    required this.rowTable,
  });

  /// 片头带左缘屏上 x（可为负：随内容滑出可视带）。
  final double left;

  /// 片头带宽（定宽一列）。
  final double width;

  /// 行集：标签文案、条数、逐行行高与行间隙的唯一来源。
  final TrackRowTable rowTable;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      key: const Key('track_prefix'),
      left: left,
      top: 0,
      width: width,
      height: rowTable.totalHeight,
      // 纯显示：整列不吃指针——片头落在时间轴零点之左那一条空白守卫之内
      // （守卫与片头同占那一段），命中归属只留守卫一处，片头不当第二个
      // 吸收者（否则它自己的底色会把守卫让给首线控制柄的那一段又挡住）。
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: kTrackPrefixBackgroundColor),
            ),
            // 标签列与行集逐行同高同隙：片头与所属行纵向对齐由同一份行表
            // 保证，不手算纵向坐标。
            Positioned.fill(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rowTable.rows.length; i++) ...[
                    if (i > 0) SizedBox(height: rowTable.gap),
                    SizedBox(
                      height: rowTable.rows[i].height,
                      child: Center(
                        // 装饰档（固定排版，不承载语义）：片头文字只是行分区
                        // 标签，读不到它不丢失信息；固定排版的理由是量测与
                        // 渲染同源——样式 [kTrackPrefixLabelTextStyle] 只此
                        // 一份，本处显式吃 [TextScaler.noScaling]，盒宽不随
                        // 系统字号变化。
                        child: Text(
                          rowTable.rows[i].prefixLabel,
                          key: ValueKey(
                            'track_prefix_label_${rowTable.rows[i].id.name}',
                          ),
                          style: kTrackPrefixLabelTextStyle,
                          textScaler: TextScaler.noScaling,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // 右缘浅分界（落在时间轴零点上）：标签列与轨道内容各归一侧。
            Positioned(
              key: const Key('track_prefix_divider'),
              top: 0,
              bottom: 0,
              right: 0,
              width: kTrackPrefixDividerWidth,
              child: const ColoredBox(color: kTrackPrefixDividerColor),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackBandState extends ConsumerState<TrackBand>
    with TickerProviderStateMixin {
  /// 本次编辑会话的窗口与手指下时间：窗口
  /// 读写、预览线显示值、拖动进行中标记、编辑态微调 scrub 与跨面捏合都住在
  /// 会话域里，本带只读它的读数、经它的入口落点。
  TrackBandSession get _session => widget.input.session;

  /// 带内拖动手势域：
  /// 十族的声明条目**逐族经注册入口登记**——本处是拖动域唯一构造点，两族的
  /// 条目在本处登记（本带是这两族的装配方：预览线拖动 + 学习段圈选）；
  /// **半拍线一族随半拍线覆盖层（节拍刻度域）搬走**、首尾端标与分段线两族随
  /// 轨道手柄带域、截取一族随练习片段轨域、备注两族随备注轨域、镜像两族随
  /// 局部镜像轨域，各由那一域在自己的按族登记入口提交（族与它的渲染同处）。
  /// 域持单槽与世代；各族的帧事务都住在域里，本带只持各族起手交回的句柄
  /// （十族全部随域或行域搬走，本带不再持有任何句柄字段）。命中解析仍留在本带。
  /// 拖动域的**按族注册表**：本带与各行域共用
  /// 同一份实例——逐族搬出的行域把自己的族声明登记进这里，域按门禁目标分派
  /// 起手（行域不私持第二份注册表）。
  final TrackBandDragFamilies _dragFamilies = TrackBandDragFamilies();

  late final TrackBandDragSession _dragDomain = TrackBandDragSession(
    families: _dragFamilies
      // 镜像整体移 / 端点拖：两族声明条目已
      // **随族**搬到局部镜像轨域——该域在自己的按族登记处把声明登记进本
      // 拖动域的共享注册表，本处不再拼表。
      // 备注整体移 / 端点拖两族的声明条目随备注轨域走：
      // 由 `track_note_row.dart` 在自己的登记点经本注册入口
      // 登记，带内不再有该族的声明条目与包装。
      // 半拍线移动一族的声明条目随半拍线覆盖层（`track_beat_ticks.dart`）
      // 走：节拍刻度域在自己的按族登记处登记，带内不再有该族的条目。
      // 预览线拖动（第九族）：**没有模块事务**
      // ——seek 不是编辑命令，`beginSession` 因此留空（请求即落点）；准入 =
      // 本次起手的带内局部 x 落在预览线命中列内（接管只从轨道手柄带的控制柄
      // 起手路径发起，起手方在那一域——它只问本域「这一族接不接」）；换算与
      // 落点消费是两条声明钩子。
      ..register(
        AnnotationGestureTarget.previewLineDrag,
        TrackBandDragDeclaration(
          // 装载未完成门只挡写盘入口；本族是 seek，起从不读这道门
          // （如实入表，不顺手统一）。
          respectLoadGate: false,
          toTime: (localX, _) => _previewLineSeekTarget(localX),
          admit: (_, localX) => _previewLineColumnAt(localX),
          onBegin: (_) => _selectionDomain.clear(),
          onFrame: _consumePreviewLineSeek,
          onEnd: _endPreviewLineDragVisuals,
        ),
      )
      // 学习段圈选（第十族）：**自家帧族**——它改的是选中集合而不是
      // 时间落点，逐帧与提交、取消两条收口都由族自己的帧解释。命中解析留在
      // 带侧（目标身份承载解析出的段序），故这里只建帧。
      ..register(
        AnnotationGestureTarget.learningTrackTap,
        TrackBandDragDeclaration(
          // 混区 burst 让位：本族与练习片段截取族同样有此判定，如实入表。
          yieldOnMixedBurst: true,
          // 双指半途加入本族**回滚取消**（不是其余族的「冻结」）：这条既有
          // 差异由族自己的帧回答，域不代它冻结。
          freezeOnPinch: false,
          beginFrame: _beginLearningSpanFrame,
          onBegin: (_) =>
              unawaited(ref.read(selectionHapticProvider).selectionImpact()),
        ),
      ),
    isPinchActive: () => _trackPinchActive,
    isMixedBurstActive: () => _mixedPinchBurst,
    loadGateActive: () => _loadGateActive,
    gestureStartRejected: _gestureStartRejected,
    promptOnReject: _promptIfSegmentLockRejected,
    bandWidth: _dragBandWidth,
  );

  /// 练习片段截取族的句柄：句柄字段与起手/
  /// 逐帧/收口三件包装都住在练习片段轨域，本带只持这一个句柄对象；族声明
  /// 条目经拖动域的按族注册入口在本域唯一登记点登记（条目随族走）。
  late final TrackPracticeRowTrim _practiceRowTrim = TrackPracticeRowTrim(
    dragDomain: _dragDomain,
    toTimeMs: _bandDragTime,
    clips: () => ref.read(practiceClipsProvider),
    beginSession: (target) {
      final trim = target as ClipTrimDragTarget;
      return ref
          .read(annotationEditorProvider)
          .beginPracticeClipTrimDrag(trim.index, trim.edge);
    },
  )..install(_dragDomain.families);

  /// 本帧已排入的首尾线铺开（见 [_syncPracticeRangeExpand]）：provider 不允许
  /// 在 widget 构建期改写，故本帧只排一次、真正的记入与写窗口在帧尾做。
  bool _practiceRangeExpandScheduled = false;

  /// 首尾线单元上场时把可视窗口复位为全片（首尾线单元上场时铺开整
  /// 片）：轮到该步演出、而用户此刻正放大在别处——那时区间的头线与尾线都落
  /// 在窗口之外，两枚锚点一圈也画不出来，这一步讲的东西根本不在屏上。复位挂
  /// 在该步**轮到演出**上，不挂锚点在场与否（锚点全缺席正是需要它的那个场
  /// 景）：「轮到演出」= 排在前面的编辑态上手已收场（三步都走完、或被整单元
  /// 跳过），按**同步可读**的会话面判，不看判定面那趟异步求值——两枚锚点都被
  /// 放大挡在窗外时，判定面对本步取「不可显示」，而那正是需要复位的场景。本
  /// 会话只做一次（做过的单元记在 [GuideSessionState.sideEffects] 里，收起
  /// 再展开控制层也照旧只做一次；该单元重置即清掉）。不做视觉交代，不动气泡
  /// 文案。
  void _syncPracticeRangeExpand() {
    if (_practiceRangeExpandScheduled) return;
    if (ref
        .read(guideSessionProvider)
        .sideEffects
        .contains(practiceRangeUnitId)) {
      return;
    }
    // 本会话已收场（关掉 / 跳过）即不再复位——此刻窗口是用户自己的。
    final seen = ref.read(guideSessionProvider).seen;
    if (seen.contains(practiceRangeUnitId)) return;
    if (!seen.contains(editorIntroUnitId) &&
        !guideUnitStepsDone(
          editorIntroUnitId,
          ref.read(guideSessionProvider).stepsDone,
        )) {
      return;
    }
    if (ref.read(annotationTimelineProvider).segmentLines.isEmpty) return;
    _practiceRangeExpandScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _practiceRangeExpandScheduled = false;
      if (!mounted) return;
      // 本帧到帧尾之间该步可能已经收场（关掉 / 跳过）：此刻窗口归用户。
      if (ref.read(guideSessionProvider).seen.contains(practiceRangeUnitId)) {
        return;
      }
      ref
          .read(guideSessionProvider.notifier)
          .markSideEffect(practiceRangeUnitId);
      _session.updateWindow(null);
    });
  }

  /// 起手前纯读判定：这个手势目标起手会不会被文档级门禁拒
  /// ——由模块手势目标声明表派生（widget 不再手拼门禁子集）。拖动/点选
  /// **起手前**读一次，被拒即静默不参与（不弹提示、不建会话）；拒绝与
  /// 提示的最终裁决归标注编辑模块逐帧提交时的门禁。对比态只读
  ///（单一事实源 = annotationCompareReadonlyProvider，由模块读）。
  bool _gestureStartRejected(AnnotationGestureTarget target) =>
      ref.read(annotationEditorProvider).gestureStartRejected(target);

  /// 拖动被分段锁拒绝时的统一反馈：拖动手势**首次位移成立**
  /// （onDragStart 已越过触摸 slop）那刻弹一次「已锁定分段」并放弃本次手势
  /// ——两个受锁目标（拖分段线 / 拖首尾边界）共用这一处口子；对比态只读与
  /// 组员方案只读仍静默（[AnnotationEditor.gestureStartRejected] 合并三者，
  /// 本处只认分段锁）。
  void _promptIfSegmentLockRejected(AnnotationGestureTarget target) {
    if (!ref
        .read(annotationEditorProvider)
        .gestureStartRejectedBySegmentLock(target)) {
      return;
    }
    ref.read(noticeTriggerProvider(NoticeId.layoutLock).notifier).show();
  }

  /// 「装载未完成」门的**手势参与判定**：写类拖动
  /// 起手前读一次，装载期静默不参与（不建会话、不弹提示）——与对比态只读
  /// 同款「起手前只读判定」。拒绝与提示归各会写盘入口承担；手势按只读
  /// 处理，不占门的原因是「拖动中无法说明」。
  bool get _loadGateActive => ref.read(loadGateActiveProvider);

  /// 选中域写面：本带的单值点选与
  /// 学习段选中两族写点一律经域对象，不再经编辑模块的转发成员。
  AnnotationSelectionDomain get _selectionDomain =>
      ref.read(annotationSelectionDomainProvider);

  /// 拖动中的分段线索引（null = 无分段线拖动会话）：本字段只驱动 build
  /// （setState 可见——线身与把手同一序号取同档选中观感）；**族句柄字段与
  /// 起手/逐帧/收口包装随族搬进轨道手柄带域**，
  /// 本带只收它交回的这个事实。
  int? _draggingLine;

  /// 首尾端标拖动在场（轨道手柄带域交回的事实）：本带两处手势仲裁
  /// （scale 会话起点是否清选中、空白横滑是否让位）读它——与那一族的句柄同源。
  bool _rangeDragActive = false;

  /// 各族起手交回的域句柄：逐帧与收口只经本族自己的句柄。跨族覆盖后旧句柄
  /// 由域的世代守卫变成空操作——不读 [TrackBandDragSession.activeHandle]，
  /// 否则旧族的操作会落到新会话上。
  /// 同族的整体移与端点拖互斥，共用一个槽。分段线与首尾端标两族的句柄随
  /// 轨道手柄带域搬走。备注两族的槽随备注轨域走。半拍线族的句柄与拖动视觉
  /// 随半拍线覆盖层（[TrackHalfBeatOverlay]）走。

  /// 当前手势会话的输入会话簿记壳（[GestureSurfaceSession]）：raw
  /// 指针簿记、burst/tap 仲裁、轴锁与 tap 输出收口于模块；本 State 只剩
  /// 装配（下方注入闭包）+ 内容层（预览条 seek/贴边平移/捏合窗口/学习段
  /// 点选）。tap 仲裁输出沿用原 [BlankTapArbiter] 装配语义：带内空白单击
  /// 收起先清选中，单指双击只切播放。
  late final GestureSurfaceSession _surface = GestureSurfaceSession(
    axis: AxisPolicy.strictHorizontal,
    isEditContent: _isEditContentAt,
    pinchSession: _session,
    pinchSurface: PinchForwardSurface.trackBand,
    isHostAlive: () => mounted,
    onSingleTap: () {
      _selectionDomain.clear();
      widget.input.onCollapse?.call();
    },
    onDoubleTap: () {
      _selectionDomain.clear();
      widget.input.onDoubleTap?.call();
    },
    onTwoFingerDoubleTap: () => widget.input.onTwoFingerDoubleTap?.call(),
    onSurfaceScaleStart: _onSurfaceScaleStart,
    onScrubFrame: _applyScrubUpdate,
    onPinchFrame: _applyPinch,
    onSurfaceScaleEnd: _onSurfaceSessionEnd,
    onIdleTapContent: () => _handleLearningTrackTap(_idleTapDownLocal),
  );

  /// 空闲单指单击的带内按下位置（scale 会话单指起手时快照；学习段轨最近段
  /// 命中判定用——up 后按下点已清空，无法再取。仅空闲单击路径消费，拖动/
  /// 捏合会话会覆盖此值但不消费）。
  Offset _idleTapDownLocal = Offset.zero;

  /// 当前吸附中的分段线时间：null = 未吸附；吸附目标进入/切换
  /// 时触发一次震动，同线内停留不重复。会话结束复位。
  Duration? _snappedLine;

  /// 拖线实时预览会话：拖动分段线/首尾线期间非 null——画面随
  /// 拖动目标逐帧预览（[_previewLineDragFrame]），预览线显示值不随动
  /// （[_onPositionTick] 会话内不写 [_playhead]）。[restoreTo] = 起手定格点
  /// （松手恢复目标，拖线本身不改变播放位置）；[wasPlaying] = 起手时是否在播
  /// （同时决定「按下即暂停」与「松手续播」）。
  ({Duration restoreTo, bool wasPlaying})? _lineDragPreview;

  /// 指针抬起/取消与 burst 结束上报收口于 [_surface]。

  /// 本 burst 曾进入跨面双指会话（混区起手）：是 → 单指 seek/选中
  /// 一律抑制（整场按缩放+平移会话处理）。
  bool get _mixedPinchBurst => _session.burstEverMixed;

  /// 双指会话当前在场：活跃 ≥2 指且至少一指在带内（含控制柄/
  /// 学习段体等子级横向拖区）→ 子级拖拽让位：不启动新拖拽会话、进行中
  /// 的拖拽冻结（抬回单指恢复，与 seek 加指冻结同语义）。
  bool get _trackPinchActive => _session.mixedActive;

  /// 生效的预览线显示值：会话域持有，控制层空白横滑与带内拖动
  /// 共享同一份——空白横滑的拖动目标直接驱动带内预览线（与入队 seek 同源）。
  ValueListenable<Duration> get _playhead => _session.previewLine;

  /// 会话域的拖动进行中标记：播放 tick 让位于拖动目标。
  bool get _externalScrubActive => _session.dragActive.value;

  ///  预览线拖动优先（拖动域第九族）：分段线控制柄起手
  /// 落在预览线命中列内 → 本手势整场转预览线拖动（scrub），不再移动分段线。
  /// 「这一族在跑吗」只有域的单槽一处答案（句柄身份），带内不留第二份布尔
  /// 接管字段。句柄本身住在起手方——轨道手柄带域。
  bool get _previewLineFamilyRunning =>
      _dragDomain.activeHandle?.target is PreviewLineDragTarget;

  /// 本 scale 会话发生过播放头 scrub：会话结束据此回报落点。
  bool _scrubbedThisSession = false;

  /// 贴边平移会话（带内唯一一份 ticker）：三条路径共用——带内空白
  /// 精细调整的命中列路径、预览线拖动族（第九族）与学习段圈选族（第十族）。
  /// 手指位与「平移后重算」的驱动者随会话登记，不因拆族而复制 ticker；
  /// 会话本体住 [EdgePanSession]（tick 循环、冻结判据与幂等复用都在那里）。
  late final EdgePanSession _edgePan = EdgePanSession(
    createTicker: createTicker,
    context: _dragContext,
    updateWindow: (window) => _session.updateWindow(window),
    pinchActive: () => _trackPinchActive,
  );

  /// 长按拖动圈选进行中（拖动域第十族）：整场窗口自管（播放头
  /// 跟随让位——拖动与滚屏期间窗口只由手指/贴边滚屏驱动）。与预览线拖动同一
  /// 条口径：只问域的单槽，带内不留第二份布尔簿记，也不留手指位字段（手指位
  /// 随贴边平移会话与族自己的帧走）。
  bool get _learningSpanFamilyRunning =>
      _dragDomain.activeHandle?.target is LearningSpanDragTarget;

  /// 精细调整上一应用帧的指针数：手指数变化后的首帧
  /// focalPointDelta 跨指针集合重算含跳变，丢弃该帧增量。
  int _fineScrubFramePointerCount = 1;

  /// 本 scale 会话起手是否落在预览线命中列内：列内 = 预览线
  /// 内容拖动（语义），不进空白精细调整。
  bool _scrubStartedInPreviewColumn = false;

  /// 拖动会话中的轨道带宽（手势起点从渲染盒读取，不在 build 期写实例状态）。
  double _bandWidth = 0;

  /// 捏合基准（起始窗口、锚时间与焦点基准 x）住在会话域：本带只在起手帧
  /// 把带宽与按下瞬间中点 x 推给它，逐帧帧事件原样转发。
  ///
  /// 带内按下指针的全局位置收在 [_surface]（pinch 锚点用），锚点换算经
  /// [_surface.pointerDownPositions] 读取。

  /// 会话中是否有指针被系统取消（edge 手势抢占等）：取消不是单击，不收起
  /// （闩锁收进 [_surface]）。

  /// 当前 scale 会话的起始手指数与焦点、会话内最大焦点位移（铁律
  /// 闩锁）与 burst 级证据上报都收进 [_surface]。

  /// 空闲单指单击的带内按下位置（_onSurfaceScaleStart 单指时快照；学习段轨
  /// 最近段命中判定用——up 后按下点已清空，无法再取。仅空闲单击路径消费，
  /// 拖动/捏合会话会覆盖此值但不消费）。

  /// 播放头显示位置的分层刷新源：播放 position tick 与拖动目标都
  /// 只写本 notifier，由 [_PlayheadLayer] 叶子层单独重绘——静态轨道层
  /// （片段/线/刻度）不再随每次 tick 整带全量重建。
  ///
  /// 这不是跨组件共享的应用状态而是控件本地的重绘管道（逐帧播放头
  /// 显示值不跨层共享，不建 provider）。
  /// 控制层空白横滑 seek 经外部共享 notifier 写入同一显示值（见
  /// [_playhead] getter）。

  /// burst 内是否有指针落在编辑内容上（练习片段块/段体/分段线/首尾线/预览
  /// 条，内容命中检查）：内容上的**单指空闲单击与双指双击**都不进入
  /// 空白 tap 判定（两条路径同一判据）。
  /// 该证据闩锁收进 [_surface]（经 isEditContent 注入）。

  PlaybackEngine get _engine => ref.read(playbackEngineProvider);

  @override
  void initState() {
    super.initState();
    _session.setPreviewLine(_engine.position);
    // 播放中逐 tick 推进预览条 + 播放头越出可视窗口时自动跟随平移。
    ref.listenManual(playbackPositionProvider, (_, next) {
      _onPositionTick(next.value);
    });
    // 轮到首尾线那一步的当帧即铺开（见 [_syncPracticeRangeExpand]）：编辑
    // 态上手走完（或整单元收场）正是那一刻；用户此刻还放大在别处时，这一步
    // 的两枚锚点都落在窗外，绕判定面那一趟异步求值等不到它。
    ref.listenManual(
      guideSessionProvider.select((session) => session.stepsDone),
      (_, _) {
        _syncPracticeRangeExpand();
      },
    );
    ref.listenManual(guideSessionProvider.select((session) => session.seen), (
      _,
      _,
    ) {
      _syncPracticeRangeExpand();
    });
    // 窗口（本带写入或控制层空白捏合写入）变化 → 重建渲染。
    _session.windowChanges.addListener(_onWindowChanged);
    // 临时衔接段激活（含异线替换）→ 弹短提示；取消/清除不提示。
    // 触发只报身份，渲染归演出层唯一宿主。
    ref.listenManual(transitionSegmentProvider, (_, next) {
      if (next != null) {
        ref.read(noticeTriggerProvider(NoticeId.transition).notifier).show();
      }
    });
  }

  /// 窗口（本带写入或控制层空白捏合写入）变化 → 重建渲染。备注轨的选择
  /// 簿记（窗口离场即清选）随备注轨域走：本处只报警重建，判定与写点归
  /// `track_note_row.dart`。
  void _onWindowChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _edgePan.dispose();
    _session.windowChanges.removeListener(_onWindowChanged);
    _surface.dispose();
    super.dispose();
  }

  /// 当前可视窗口（null = total 未知 → 无映射）：问轨道带几何模块的单一
  /// 读取（守卫与归一收在模块一处，纯读无副作用）。
  TimelineWindow? _effectiveWindow() => TrackBandGeometry.eval(
    total: _engine.duration,
    window: _session.window,
    width: 0,
    // 只读窗口（不映射像素）。
    prefixWidth: 0,
  ).effectiveWindowOrNull;

  /// 本带几何：**带内一切时间↔像素换算的唯一构造入口**——内容
  /// 区左缘让出轨道片头带（[kTrackPrefixWidth]），渲染、命中、捏合、贴边
  /// 平移因此共用一个口径，片头不参与任何映射。
  TrackBandGeometry _bandGeometry({
    required Duration? total,
    required double width,
    TimelineWindow? window,
  }) => TrackBandGeometry.eval(
    total: total,
    window: window,
    width: width,
    prefixWidth: kTrackPrefixWidth,
  );

  /// 播放位置 tick：窗口跟随归会话域的唯一一处（[TrackBandSession.followPosition]
  /// 统一做陈旧窗口归一与跟随）。跟随的让位口径 = 「谁在写窗口谁管」：捏合
  /// （跨面或带内双指）、预览线拖动（命中列内绝对跟手 + 贴边平移）与拖线
  /// 实时预览（画面预览不驱动窗口）自己管窗口；微调 scrub 不在其列——它的
  /// 落点由本 tick 跟随（旧行为在提交口跟随，见 [_windowSelfManaged]）。
  /// 预览条位置只经 [_playhead] notifier 驱动预览线叶子层重绘（分层
  /// 刷新）；手势会话中不写预览线显示值（拖动目标与 seek 同源，
  /// 跟手语义）。
  void _onPositionTick(Duration? position) {
    if (!mounted || position == null) return;
    if (!_windowSelfManaged) _session.followPosition(position);
    if (_surface.tickYieldsToGesture ||
        _externalScrubActive ||
        // 拖线实时预览与跨面双指会话期间不覆盖预览线显示值。
        _lineDragPreview != null ||
        _trackPinchActive) {
      return;
    }
    final previous = _playhead.value;
    _session.setPreviewLine(position);
    // 播放头越过选中备注自身的时间窗即清选中：判定与写点归备注轨域
    // 本处只提供触发（位置 tick 是它唯一的触发管道）与现势读数
    // ——帧步进 / 微调 scrub / 预览线拖动另有播放头显示值写点，都不是本
    // 判定。手势会话中提前 return 的 tick 不写显示值，域因此也不判。
    noteRowClearSelectionIfPlayheadLeftOwnWindow(
      notes: ref.read(noteStickersProvider),
      selectedIndex: ref.read(selectedNoteFragmentIndexProvider),
      previous: previous,
      next: position,
      clearSelection: _selectionDomain.clear,
    );
  }

  /// 窗口由手势自己管（位置 tick 的跟随让位）：跨面双指会话、带内起手即
  /// ≥2 指的捏合会话把窗口换算握在自己手里；预览线拖动以绝对跟手 + 贴边
  /// 平移写窗口；拖线实时预览的 seek 是画面预览，不驱动窗口。
  bool get _windowSelfManaged =>
      _trackPinchActive ||
      _surface.multiFingerSession ||
      _lineDragPreview != null ||
      // 预览线拖动（第九族）与长按拖动圈选（第十族）：窗口只由手指/
      // 贴边滚屏驱动，播放头跟随让位。两条判据都取域的单槽身份。
      _previewLineFamilyRunning ||
      _previewLineColumnDrag ||
      _learningSpanFamilyRunning;

  /// 预览线命中列内的拖动会话已锁定（该路径以绝对跟手 + 贴边平移
  /// 写窗口）。[_scrubStartedInPreviewColumn] 是会话世系快照（抬指后仍留到
  /// 下一会话），故配轴锁判据——只在真拖动期间让位跟随。
  bool get _previewLineColumnDrag =>
      _scrubStartedInPreviewColumn && _surface.axisLockedSession;

  // ---- 手势内容层（scale 会话边界与逐帧事件，簿记在 [_surface]） ----

  /// scale 会话开始（内容钩子；簿记复位已由 [_surface.scaleStart] 完成）：
  /// 清除选中、拖动宽度快照、捏合基准与锚点快照、空闲单击候选
  /// 位置快照。
  void _onSurfaceScaleStart(ScaleStartDetails d) {
    // 精细调整：仅松手（全部指针抬起）才收尾；scale 会话在加指/抬指时会
    // 重启（结束+新起，指针仍在按下），重启不是松手、会话冻结续存。
    _endFineScrubWhenAllUp();
    _fineScrubFramePointerCount = d.pointerCount;
    // 「其它操作即清除」：带内空白 scrub/缩放会话不针对选中线。
    // 线/首尾线/预览列的手势各自在其命中层消费，不会进入本回调；但
    // scale 可能晚于控制柄拖动起手才赢得 arena（见 [_rangeDragActive] 说明），
    // 拖线/拖端标会话进行中不清（它们正是针对选中线的操作）。
    if (!_rangeDragActive && _draggingLine == null) {
      _selectionDomain.clear();
    }
    final total = _engine.duration;
    // 起手位置快照——落在预览线命中列内（手柄带）的会话是
    // 预览线内容拖动，不进空白精细调整，仍走绝对跟手 seek。
    // 用原始按下位置（识别器位移过阈才回调，焦点已偏离真实起手点）；
    // downs != 1（加指/抬指的重启瞬间，ancestor Listener 尚未清指针）时
    // 沿用本手势世系的判定——加指后再抬回单指不把列内内容拖动误判为
    // 空白横滑。
    final downs = _surface.pointerDownPositions;
    if (d.pointerCount == 1 && downs.length == 1) {
      _scrubStartedInPreviewColumn = _inPreviewLineHitColumn(downs.first);
    }
    if (total == null || total <= Duration.zero) return;
    // 拖动会话宽度：build 期不再写实例字段（build 副作用收敛），手势起点
    // 从渲染盒读取（同时供捏合锚点做 globalToLocal）。
    final box = context.findRenderObject();
    _bandWidth = box is RenderBox ? box.size.width : 0;
    if (d.pointerCount >= 2) {
      // 捏合：起手帧只把带宽与**按下瞬间**各指针的面内局部 x 推给会话域
      // ——按下中点的求值与锚点判定都在那里（识别器在位移过阈才回调，焦点
      // 已偏出真实中点，围绕它缩放会让预览条漂移），基准窗口与整场累计
      // 换算也住在会话域。按下点 → 局部 x 的映射与空白面共用 [localDownXs]。
      _session.beginPinch(
        surface: TrackPinchSurface.band,
        width: _bandWidth,
        downXs: box is RenderBox
            ? localDownXs(_surface.pointerDownPositions, box.globalToLocal)
            : const [],
        fallbackFocalX: d.localFocalPoint.dx,
      );
    } else {
      // 单指空闲单击候选位置快照（学习段轨最近段命中判定用；拖动/捏合
      // 会话会覆盖此值但不消费）。
      _idleTapDownLocal = d.localFocalPoint;
    }
  }

  /// scale 会话结束（内容钩子；微任务 tap 仲裁已由 [_surface] 收口）：
  /// 复位吸附目标、清捏合基准、停贴边平移（拖动会话收口）；本会话
  /// 发生过播放头 scrub 时以最终落点回报宿主（放行标记）。
  void _onSurfaceSessionEnd(ScaleEndDetails d) {
    _snappedLine = null; // 会话结束复位吸附目标（下次进入重新震动）。
    _session.endPinch();
    _endFineScrubWhenAllUp();
    _edgePan.stop();
    if (_scrubbedThisSession) {
      _scrubbedThisSession = false;
      widget.input.onScrubCommitted?.call(_playhead.value);
    }
  }

  /// 精细调整会话收尾：松手（全部指针抬起）才收尾——scale
  /// 会话在加指/抬指时会**重启**（结束+新起会话，指针仍在按下），重启
  /// 不得当作松手（会话冻结续存，抬回单指继续）；微任务里复核指针清空，
  /// 避开 ancestor Listener 尚未处理 up 的时序。!isActive 时 end 为 no-op。
  void _endFineScrubWhenAllUp() {
    scheduleMicrotask(() {
      if (!mounted) return;
      if (_surface.pointerDownPositions.isNotEmpty) return;
      unawaited(_session.endFineScrub());
    });
  }

  /// 吸附目标进入/切换的震动：系统轻触反馈；测试经
  /// [TrackBandInput.onPreviewSnapHaptic] 注入记录器。
  void _notifyPreviewSnapHaptic() {
    final cb = widget.input.onPreviewSnapHaptic;
    if (cb != null) {
      cb();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// 预览条拖动磁吸公共落点（播放头拖动）：落点规则收在纯件
  /// [snapScrubTarget]（待命态恒定吸最近强拍；开关开时距最近目标线 ≤ 半径
  /// ——12dp 按当前窗口宽度折算成时间——即吸附到该线，目标集 = 分段线 +
  /// 首线 + 尾线）。吸附目标进入/切换时震动一次（同线停留不重复）；未吸附/
  /// 开关关闭时复位 [_snappedLine]（下次进入同线重新震动）。首/尾控制柄拖动
  /// 不经本路径（强制对齐、起落点解析在模块提交时进行，预览磁吸开关不作用
  /// 于首尾线）。
  Duration _applyPreviewSnap(
    Duration target, {
    required Duration windowSpan,
    required double width,
  }) {
    final snapped = snapScrubTarget(
      target,
      standby: ref.read(playerSessionProvider).isBeatCorrectionStandby,
      grid: ref.read(beatGridProvider),
      enabled: ref.read(previewSnapEnabledProvider),
      timeline: ref.read(effectiveAnnotationTimelineProvider),
      windowSpan: windowSpan,
      contentWidth: width,
    );
    if (snapped == null) {
      _snappedLine = null; // 未吸附/开关关闭：复位，重开后进入同线也重新震动。
      return target;
    }
    if (_snappedLine != snapped) {
      _snappedLine = snapped;
      _notifyPreviewSnapHaptic();
    }
    return snapped;
  }

  /// 预览条拖动内容帧（由 [_surface] 在轴锁定后逐帧转发）：
  /// 起**带内空白横滑 = 精细调整**——经会话域持有的微调会话（与非轨道区
  /// 微调同一会话）：目标 = 定格基准 + 累计位移 × 单指灵敏度，预览线随目标
  /// 时间移动、不贴手指；起手定格与松手恢复由会话域收口，无取消角。轴锁定的判定与混区/加指冻结门在模块
  /// 内；≥2 指帧仍会转发、由本处的 pointerCount 守卫冻结——第二指落下
  /// （想捏合/误触）：冻结微调，抬到剩一指再恢复（既有仲裁形状不变）。
  /// 贴边平移与吸附解析不再作用于空白横滑（目标按位移走、无手指位置可
  /// 言）；仅手柄带预览线命中列接管路径仍走 [_seekPreviewToX]。
  void _applyScrubUpdate(ScaleUpdateDetails d) {
    if (_rangeDragActive) return;
    _edgePan.pointerCount = d.pointerCount;
    // 第二指落下（想捏合/误触）：冻结——scale 识别器不会为加指重发会话
    // 起点，继续把焦点当单指会误动目标；抬到剩一指再恢复。
    if (d.pointerCount >= 2) {
      _fineScrubFramePointerCount = d.pointerCount;
      return;
    }
    if (!_scrubStartedInPreviewColumn && !_trackPinchActive) {
      // 手指数变化后的首帧防御（focalPointDelta 跨指针集合重算可能含
      // 跳变）：丢弃该帧增量。常态下手指数变化触发 scale 会话重启
      // （start 已把计数基线重置为新手指数），重启后的 update 以重启
      // 焦点为基准、增量本就健康——本分支仅在识别器不重启的帧序下兜底。
      if (_fineScrubFramePointerCount != d.pointerCount) {
        _fineScrubFramePointerCount = d.pointerCount;
        return;
      }
      unawaited(_session.fineScrubFrame(d.focalPointDelta.dx));
      return;
    }
    _seekPreviewToX(d.localFocalPoint.dx);
  }

  /// 预览线拖动公共落点（带内空白精细调整的命中列路径与族声明的贴边重算
  /// 共用）：换算 + 吸附 + 提交一次。
  void _seekPreviewToX(double localX) {
    // 带内空白精细调整的入口自带钳制（族路径的钳制归拖动域，两条路径不同源、
    // 同口径）：整带 scale 手势交下的焦点 x 可以落在带外。
    final width = _bandBox()?.size.width ?? 0;
    final target = _previewLineSeekTarget(localX.clamp(0.0, width));
    if (target == null) return;
    _consumePreviewLineSeek(target);
  }

  /// 预览线拖动的逐帧换算（第九族声明的 `toTime` 钩子，与带内空白
  /// 精细调整共用）：**已钳在带内的**带内局部 x → 贴边平移登记 + 吸附解析后的
  /// 落点；几何不可用返回空（该帧成为空操作）。带宽自取渲染盒全宽——控制柄
  /// 起手的路径不经过整带 scale 手势（[_bandWidth] 未经会话快照，仍为 0），
  /// 故不声明域交下的带宽（本族不读那个入参）。
  ///
  /// 吸附：开关开时目标经吸附解析——距最近目标线 ≤ 半径
  /// （12dp 按当前窗口宽度折算成时间）即吸附到该线；目标集 = 分段线 + 首线 +
  /// 尾线、半径内取最近者；吸附目标进入/切换时震动一次（同线停留不重复）。
  /// 非轨道区微调不经本路径，天然无磁性吸附。
  Duration? _previewLineSeekTarget(double localX) {
    final ctx = _dragContext();
    if (ctx == null) return null;
    _scrubbedThisSession = true;
    final w = ctx.box.size.width;
    final x = localX;
    // 登记手指位置与「平移后重算」的驱动者；进入边沿区才启动会话级
    // ticker——贴边平移为逐帧时间平滑累积（手指静止也持续平移），离开边沿区/
    // 会话结束停止。本路径按平移后的窗口用同一手指位重新换算并 seek，不在
    // 窗口钳到片首/片尾时停 ticker（既有语义逐位保留）。
    final finger = Offset(x, 0);
    _edgePan.hold(finger, (_) {
      _seekPreviewToX(finger.dx);
      return true;
    });
    final result = seekTargetForFingerX(
      total: ctx.total,
      window: ctx.window,
      width: w,
      x: x,
    );
    return _applyPreviewSnap(
      result.target,
      windowSpan: ctx.window.end - ctx.window.start,
      // 吸附半径按内容区宽折算（片头不吃像素↔时间口径）。
      width: _bandGeometry(
        total: ctx.total,
        window: ctx.window,
        width: w,
      ).contentWidth,
    );
  }

  /// 预览线拖动的落点消费（第九族声明的 `onFrame` 钩子，与带内空白
  /// 精细调整共用）：经会话域的唯一 seek 装配（提交口）提交——钳制、清
  /// 循环激活（与 player_page 共用判定，临时衔接段同规则）、串行节流
  /// 入队与预览线显示位（分层刷新）按固定次序收口，显示值与入队目标
  /// 同源；拖出有效区间允许暂停查看但立即停播；窗口按本轮生效窗口归一。
  void _consumePreviewLineSeek(Duration target) {
    _session.submit(target);
    final timeline = ref.read(effectiveAnnotationTimelineProvider);
    if (target < timeline.rangeStart || target > timeline.rangeEnd) {
      // 拖出有效区间允许暂停查看，但立即停止播放，避免继续越界播放。
      unawaited(_engine.pause());
    }
    final win = _effectiveWindow();
    if (win != null) _session.updateWindow(win);
  }

  /// 预览线拖动的收口视觉（第九族声明的 `onEnd` 钩子）：复位吸附
  /// 目标（下次进入重新震动）并停贴边平移——提交路径与取消路径同一条。
  void _endPreviewLineDragVisuals() {
    _snappedLine = null;
    _edgePan.stop();
  }

  /// 预览线命中列的准入（第九族声明的 `admit` 钩子）：本次起手的
  /// 带内局部 x 落在预览线当前位置 ± [kPreviewLineHitColumnWidth]/2 的列内才
  /// 接管；几何不可映射、播放头不在窗内或落在轨道片头带内都不接管。
  bool _previewLineColumnAt(double localX) {
    final ctx = _dragContext();
    if (ctx == null) return false;
    final playheadPos = _playhead.value;
    if (!ctx.window.contains(playheadPos)) return false;
    final geometry = _bandGeometry(
      total: ctx.total,
      window: ctx.window,
      width: ctx.box.size.width,
    );
    final axis = geometry.axis;
    if (axis.isEmpty) return false;
    if (localX < geometry.contentLeft) return false;
    return (axis.timeToX(playheadPos) - localX).abs() <=
        kPreviewLineHitColumnWidth / 2;
  }

  /// 学习段圈选族的自家帧（第十族声明的 `beginFrame` 钩子）：起手
  /// 段序由目标身份承载（命中解析留在带侧），只读拒绝即起手不成立（不建句柄、
  /// 不起手钩子）。逐帧按当前带内局部落点重解析段序并延伸圈选；提交与取消
  /// 各自回到选中域的一口；贴边平移用带级唯一一份 ticker。
  TrackBandDragFrame? _beginLearningSpanFrame(TrackBandDragTarget target) {
    if (!_selectionDomain.beginDragSelect(target.index)) return null;
    return TrackBandDragFrame(
      moveTo: (local) {
        // 双指半途加入（捏合接管）即回滚取消（与其余族的「冻结」不同，如实
        // 入表）；滚屏一并停止。
        if (_mixedPinchBurst || _trackPinchActive) {
          _edgePan.stop();
          _selectionDomain.cancelDragSelect();
          return;
        }
        // 贴边滚屏会话：登记手指位（横向照旧钳在带内，与既有实现的 tick 深度/
        // 左右侧口径逐位同源）与平移后的重算——回到同手指位置重新解析命中段
        // 并延伸圈选（终点跟着滚出的段走）；窗口已钳在片首/片尾（继续滚不可能
        // 再平移）或命中已钳在首/末段（继续滚不可能再圈进新段）即停。
        final width = _bandBox()?.size.width ?? 0;
        final finger = Offset(local.dx.clamp(0.0, width), local.dy);
        _edgePan.hold(finger, (windowMoved) {
          if (!windowMoved) return false;
          final hit = _learningSpanHitAt(finger);
          if (hit.order != null) _selectionDomain.spanTo(hit.order!);
          return !hit.atSpanEdge;
        });
        final hit = _learningSpanHitAt(local);
        if (hit.order == null) return;
        _selectionDomain.spanTo(hit.order!);
      },
      end: () {
        _edgePan.stop();
        _selectionDomain.commitDragSelect();
      },
      cancel: () {
        _edgePan.stop();
        _selectionDomain.cancelDragSelect();
      },
    );
  }

  /// 双指捏合缩放帧：原样转发给会话域（基准窗口、锚时间与累计换算都在那里
  /// 一处收口）——带内口径 = 带内容区宽，与跨面/空白面的控制层宽口径不同
  /// （见会话域库头「两套捏合带宽口径」）。
  void _applyPinch(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) return; // 抬到剩一指：挂起等手势结束
    _session.pinchFrame(factor: d.scale, focalX: d.localFocalPoint.dx);
  }

  // ---- 渲染 ----

  /// 行集内某行的矩形；行不在本行集内时为 null。
  ///
  /// 与 [TrackRowTable.rectOf]「行不在本行集内显式报错」的分工：报错守护
  /// 的是**行表 API 的调用错误**（把行表当全集用、忘了传行——开发期就该
  /// 炸）；本守卫回答的是**行集数据的合法问题**——「这份行集里有没有这
  /// 一行」（如对比行集不含轨道手柄带行），行缺席是合法状态，对应渲染件
  /// 与覆盖层整体不渲染。存在性由行集声明本身回答（不累加行高、不手算），
  /// 几何仍全部出自行表。
  TrackRowRect? _rectIfPresent(TrackRowId id) =>
      widget.input.rowTable.hasRow(id)
      ? widget.input.rowTable.rectOf(id)
      : null;

  /// 内容区之左（时间轴零点之左）的空白守卫：不落任何内容
  /// 命中——按在那里一律等于按在带上空白（不选中、不拖动、不吸附；带级
  /// 手势层是它的祖先，空白单击/横滑照常）。
  ///
  /// [hole] 是让给首线控制柄的纵向范围（片头在可视带内时为轨道
  /// 手柄带行，否则为空）：守卫退成该段之上与之下两段，首线控制柄在该行
  /// 内可直接接住片头里的起手。
  List<Widget> _buildPrefixGuards({
    required double contentLeft,
    required TrackRowRect? hole,
  }) {
    final rowHeight = widget.input.rowTable.totalHeight;
    Widget guard(double top, double height) => Positioned(
      left: 0,
      top: top,
      width: contentLeft,
      height: height,
      child: const Listener(behavior: HitTestBehavior.opaque),
    );
    final holeTop = hole?.top ?? rowHeight;
    final holeBottom = hole?.bottom ?? rowHeight;
    return [
      if (holeTop > 0) guard(0, holeTop),
      if (holeBottom < rowHeight) guard(holeBottom, rowHeight - holeBottom),
    ];
  }

  /// 练习片段一次点按的双写：切换激活（块缘白色 3dp 描边）+
  /// 切换选中（内缩细描边），两槽再点同片段各自取消。均现读现写，不闭包
  /// 捕获 build 时的状态值。
  ///
  /// 块体上任何一点都走本路径（「命中只留一个答案」）：块体、两端端点
  /// 带、以及压在块上的播放头竖线三处共用同一次写入，不各写一份。写入口住
  /// 带级（激活与选中两 provider 的写面），练习片段轨域经回调取用。
  void _togglePracticeClip(PracticeClip clip) {
    ref.read(practiceClipActivationProvider.notifier).toggle(clip);
    final current = ref.read(selectedPracticeClipIdProvider);
    ref
        .read(selectedPracticeClipIdProvider.notifier)
        .select(current == clip.id ? null : clip.id);
  }

  /// 播放头竖线（2dp 全高列）上的点按：用户点的是那根预览线本身，故横向
  /// 落位取**预览线的位置**而非手指的小数点落位（播放头压在块首/块尾时，
  /// 手指点的正是压住块缘的那 2dp）。命中练习片段块即走与块体同一条点选
  /// 路径；未压在块上时保持原样（预览条 = 编辑内容）。
  ///
  /// 命中求值归练习片段轨域的公开入口，由命中解析适配层
  /// 委派；本处只组装：全局位置 → 预览线落位 → 适配层。
  void _handlePlayheadTap(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    if (band == null) return;
    final hits = _hitResolution(width: band.width);
    final clip = hits.practiceClipAt(
      Offset(hits.geometry.axis.timeToX(_playhead.value), band.local.dy),
    );
    if (clip == null) return;
    _togglePracticeClip(clip);
  }

  /// 逐行渲染按行标识分派：行高与行键取自行的声明，各渲染件
  /// 的构造参数不变；行内装饰（刻度内缩、控制柄底偏移、片段块内边距、
  /// 学习段体填充）仍留在各自渲染件里。
  ///
  /// [learningRowInput] 是学习段轨域的显式输入：本行集含学习段
  /// 轨行时才构造（组装点在 build），故学习段轨分支里它必非空。
  Widget _buildRow(
    TrackRow row, {
    required TimelineAxis axis,
    required AnnotationTimeline timeline,
    required TrackLearningRowInput? learningRowInput,
    required Map<int, LearningMastery> mastery,
    required Set<int> emphasizedSegments,
    required Set<int> activatedSegments,
  }) {
    switch (row.id) {
      case TrackRowId.practiceVideo:
        // 对比行集的练习视频轨：整行归**练习片段轨域**
        // ——行背景、块体与回看浮条住该域自带的 widget 子树；本处只留行位与行键
        // （节点类型、行高与键逐位不变，行背景色由该域画）。
        return Container(key: Key(row.key), height: row.height);
      case TrackRowId.note:
        return Container(
          key: Key(row.key),
          height: row.height,
          color: Colors.white.withValues(alpha: 0.08),
          // 备注轨常驻显示（空轨亦占高）；行内容（块体、展开浮条、
          // 点按/长按与两族拖动）归备注轨域
          // 在带内 Stack 上组装，本行只做背景占位。
        );
      case TrackRowId.localMirror:
        // 局部镜像轨域：块体、行级点按与两族拖动全在域内，本行
        // 只出背景（行键与行高仍取自行声明——行表是这两件事的唯一来源）；
        // 域输入在 build 处按行矩形构造。
        return Container(
          key: Key(row.key),
          height: row.height,
          color: Colors.white.withValues(alpha: 0.06),
        );
      case TrackRowId.learning:
        return Container(
          key: Key(row.key),
          height: row.height,
          color: Colors.white.withValues(alpha: 0.04),
          // 学习段轨域：行内画法、命中与标记全在域内，本行只出
          // 背景；[_buildRow] 只对本行集内的行调用，学习段轨行在场即其行
          // 矩形在场，域输入必已构造（组装点在本文件的 build）。
          child: TrackLearningRow(input: learningRowInput!),
        );
      case TrackRowId.beat:
        return BeatTicksRow(axis: axis, height: row.height);
      case TrackRowId.handleStrip:
        return Container(
          key: Key(row.key),
          height: row.height,
          color: Colors.white.withValues(alpha: 0.10),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _engine.duration;
    final timeline = ref.watch(annotationTimelineProvider);
    // 菜单类四条角标「刚落成的实物」序号（会话事实）：播放域按
    // 它把锚点包装器包在该序号对应的实物上——触发与「新产物是谁」在同一处
    // 取得（见 control_layer 的「添加」菜单条目动作）。序号缺席或越界即不
    // 包锚点，角标宿主按锚点缺席放行。
    final guideArtifactIndexes = ref.watch(
      guideSessionProvider.select((session) => session.artifactIndexes),
    );
    final selectedLearningSegments = ref.watch(
      selectedLearningSegmentsProvider,
    );
    // 分段线选中来自 10 的密封点选状态（与学习段选中互斥）。
    final mastery = ref.watch(learningMasteryProvider);
    final emphasizedSegments = ref.watch(learningEmphasisProvider);
    final selectedLine = ref.watch(selectedSegmentLineIndexProvider);
    final transitionSegment = ref.watch(transitionSegmentProvider);
    final mirrorFragments = ref.watch(localMirrorFragmentsProvider);
    // 练习视频轨的在轨片段：经显式输入值对象交给练习片段轨域
    // 渲染；行不在本行集内（编辑态行集）时该域不组装，列表不被
    // 消费。
    final practiceClips = ref.watch(practiceClipsProvider);
    // 局部镜像总开关：片段块视觉全由本开关驱动（片段 = 纯
    // 区间，无自带启停位）。
    final localMirrorOn = ref.watch(localMirrorEnabledProvider);
    final selectedMirrorFragment = ref.watch(
      selectedLocalMirrorFragmentIndexProvider,
    );
    // 备注贴纸列表：备注轨行矩形 + 各备注的时间窗 → 块体几何
    // 全部经共用件（[intervalBlockRect]），渲染不手算。
    final notes = ref.watch(noteStickersProvider);
    // 名册只读面：框内文本按当前名册解析点名（文本唯一真源，
    // 与贴纸同一份解析、同一套配色）。
    final rosterColors = noteMentionRosterColors(
      ref.watch(dancerRosterProvider),
    );
    // 定位高亮：贴纸左下角工具跳转控制层时宿主打上，渲染在
    // 起点匹配的那条备注片段上。
    final noteHighlight = ref.watch(noteFragmentHighlightProvider);
    // 选中的备注片段：驱动片段选中描边与展开内容浮条。
    final selectedNoteFragment = ref.watch(selectedNoteFragmentIndexProvider);
    // 行矩形：行集给出的各行的带内顶/高——行不在本行集内时为
    // null（对应覆盖层/命中层一并不渲染）。节拍/手柄带行的矩形由各自
    // 渲染件就近向行表求取。
    final mirrorRect = _rectIfPresent(TrackRowId.localMirror);
    final learningRect = _rectIfPresent(TrackRowId.learning);
    final notesRect = _rectIfPresent(TrackRowId.note);
    final practiceRect = _rectIfPresent(TrackRowId.practiceVideo);
    // 轨道手柄带行矩形：片头空白守卫按它把手柄带行让给首线
    // 控制柄；行集无该行时为 null（对比态），守卫不挖。
    final handleStripRect = _rectIfPresent(TrackRowId.handleStrip);
    // 节拍轨行矩形：半拍线命中列的纵向几何；行集无该行时为 null（整层不
    // 渲染半拍线）。
    final beatRowRect = _rectIfPresent(TrackRowId.beat);
    // 首尾线铺开的兜底重查（见 [_syncPracticeRangeExpand]）：判定面换步那
    // 一帧在带已挂载之后（编辑态上手收场当帧）由监听器接住，这一处保证别的
    // 重建源（如本带刚挂载时编辑态上手已置位）也轮到一次。
    if (timeline.segmentLines.isNotEmpty) {
      _syncPracticeRangeExpand();
    }
    return Container(
      key: const Key('track_band'),
      height: widget.input.rowTable.totalHeight,
      // 轨道带背景深色半透明（≈ 黑 60%），直接叠于 contain 视频上；
      // 标注片段/线不透明（标注与学习段轨内容于其上绘制）。
      color: Colors.black.withValues(alpha: 0.6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _bandGeometry(
            total: total,
            window: _effectiveWindow(),
            width: constraints.maxWidth,
          );
          // 空态收成一种：几何值恒非空，「没有可映射几何」
          // 只由 [TrackBandGeometry.isMappable] 一种谓词表达。读取层的可空
          // （[_effectiveWindow] 的 null = 总时长未知，真缺失）与本层
          // 空谓词（退化）各管一层、语义不重叠（见几何模块契约头）。
          final axis = geometry.axis;
          final mappable = geometry.isMappable;
          final win = geometry.effectiveWindow;
          // 局部镜像轨域的显式输入：这一行的全部外部事实一次给
          // 全——片段表、行矩形、时间轴与窗口、总开关与选中片序、角标锚点键、
          // 拖动域句柄与共享注册表、带内局部 x 读取与四个回调。域不在本行
          // 集内（无行矩形）或几何不可映射时不组装它的子树。
          TrackMirrorRowInput? mirrorRowInput;

          // 带级「编辑内容」问本行：纵向带按行表限定为局部镜像轨
          // 行，片段命中问该域公开的命中入口（适配层经它消费，与行级点按同一
          // 条路径）——该行的子树不在场时判否。
          bool mirrorRowContentHit(Offset globalPosition) {
            if (mirrorRowInput == null) return false;
            return _mirrorRowContentAt(globalPosition);
          }

          mirrorRowInput = !mappable || mirrorRect == null
              ? null
              : TrackMirrorRowInput(
                  rowRect: mirrorRect,
                  axis: axis,
                  window: win,
                  fragments: mirrorFragments,
                  masterSwitchOn: localMirrorOn,
                  selectedIndex: selectedMirrorFragment,
                  guideAnchorKeys: (index) => liveArtifactAnchorKeyOfBase(
                    badgeLocalMirrorUnitId,
                    mirrorFragmentAnchorKeyBase,
                    guideArtifactIndexes,
                    index,
                  ),
                  dragFamilies: _dragFamilies,
                  dragSession: _dragDomain,
                  // 模块会话工厂是唯一需要 ref 的一片：本带以闭包注入，域不
                  // 读 provider（抓取偏移、准入与换算都归域）；编辑模块句柄
                  // 就地链式调用、不另存别名（选择守卫的同一条纪律）。
                  beginSession: (target) => target is MirrorEdgeDragTarget
                      ? ref
                            .read(annotationEditorProvider)
                            .beginLocalMirrorEdgeDrag(target.index, target.edge)
                      : ref
                            .read(annotationEditorProvider)
                            .beginLocalMirrorMoveDrag(target.index),
                  localXOf: _bandLocalX,
                  // 守卫沿既有（跨面双指 burst / 捏合期间不判定）——点选不改
                  // 几何，锁定期照常选中、不弹锁提示；被守卫时不落穿空白。
                  onTapFragment: (index) {
                    if (!_mirrorRowTapAllowed) return;
                    _selectionDomain.select(
                      LocalMirrorFragmentSelection(index),
                    );
                  },
                  onTapBlank: (position) {
                    if (!_mirrorRowTapAllowed) return;
                    _forwardRowBlankTapToBandArbiter(position);
                  },
                  onEditContentHit: mirrorRowContentHit,
                  // 拖动视觉簿记仍在带级（实时预览会话属画面层），以回调注入。
                  onDragVisualsBegin: _beginLineDragPreview,
                  onDragFrame: _previewLineDragFrame,
                  onDragVisualsEnd: _endDragPreviewVisuals,
                );
          // 学习段轨域的显式输入：本行的全部外部事实一次给全
          // ——行矩形、时间轴与窗口、时间线与熟练度/重点/激活段、临时衔接
          // 段与该行回调。行集不含学习段轨行时没有行矩形（本行的内容、命中
          // 层与覆盖层一并不组装），故按行矩形在场与否构造。
          final learningRowInput = learningRect == null
              ? null
              : TrackLearningRowInput(
                  rowRect: learningRect,
                  axis: axis,
                  window: win,
                  timeline: timeline,
                  mastery: mastery,
                  emphasizedSegments: emphasizedSegments,
                  activatedSegments: selectedLearningSegments,
                  transition: transitionSegment,
                  onSegmentDragStart: _quickSelectSegment,
                  onSegmentTapUp: _handleLearningSegmentTapUp,
                  onSegmentTapDown: _handleLearningSegmentPressDown,
                  onSegmentTapCancel: _handleLearningSegmentTapCancel,
                  onSegmentLineTap: (index, globalPosition) =>
                      _handleSegmentLineTap(index, globalPosition, timeline),
                  // 长按圈选族（拖动域第十族）：本域只驱动那一族的
                  // 句柄——落点解析的答案与「全局 → 带内局部落点」的换算都问
                  // 本带（族声明与自家帧住带级装配）。
                  dragDomain: _dragDomain,
                  resolveSpanOrder: _spanOrderAt,
                  bandLocalAt: _bandLocalPoint,
                );
          return Stack(
            children: [
              // 手势层：整带水平拖动预览条 / 双指捏合缩放（设置簇在带外，
              // 其区域的指针不进入本层、不与拖动争 arena）。
              Positioned.fill(
                child: Listener(
                  // raw 指针簿记（按下点/burst/内容命中/跨面双指转发）
                  // 收进 [_surface]，Listener 四回调各一行转发。
                  onPointerDown: _surface.pointerDown,
                  onPointerMove: _surface.pointerMove,
                  onPointerUp: _surface.pointerUp,
                  // 指针被系统取消时 scale 会话可能不走 end——
                  // 精细调整会话在此一并收尾（恢复手势前播放态；不在会话
                  // 中时 no-op）。
                  onPointerCancel: (event) {
                    _surface.pointerCancel(event);
                    unawaited(_session.endFineScrub());
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _surface.scaleStart,
                    onScaleUpdate: _surface.scaleUpdate,
                    onScaleEnd: _surface.scaleEnd,
                    child: Stack(
                      // 首/尾线命中带以线心居中、整片视图贴带缘时一半在
                      // 带外：Clip.none 让越界子树的带内命中测试
                      // 不被栈裁切，贴边线内侧半宽仍可抓取；线体在带内绘制。
                      clipBehavior: Clip.none,
                      children: [
                        // 首尾线单元的触达面：线上已有学习段即
                        // 触达。挂在线上不行——视野放大在别处时两条线都落在
                        // 窗口外、连线都不渲染，而那一刻正是该铺开整片的场
                        // 景；故这一枚不承载视觉，只记触达。
                        if (timeline.segmentLines.isNotEmpty)
                          Positioned(
                            left: 0,
                            top: 0,
                            child: GuideBadgeTrigger(
                              unitId: practiceRangeUnitId,
                              child: const SizedBox.shrink(),
                            ),
                          ),
                        // 行容器：行与行间隙由行集
                        // [TrackBandInput.rowTable] 生成；缺省行集 normal 的行序
                        // = 备注（最顶）→ 局部镜像 → 学习段 → 节拍 →
                        // 轨道手柄带行（最底），逐位沿用今天。
                        // 静态轨道层（repaint 边界）：播放 tick / 拖动
                        // 目标只重绘预览线层，本层不随逐帧刷新重绘。
                        RepaintBoundary(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 行与行间隙由行集生成：行序、逐行高
                              // 与间隙均取自 [TrackBandInput.rowTable]，代码中不再
                              // 手写「行高之和 + 间隙 × 3」合计。逐行渲染按
                              // 行标识分派，各渲染件构造参数不变。
                              for (
                                var i = 0;
                                i < widget.input.rowTable.rows.length;
                                i++
                              ) ...[
                                if (i > 0)
                                  SizedBox(height: widget.input.rowTable.gap),
                                _buildRow(
                                  widget.input.rowTable.rows[i],
                                  axis: axis,
                                  timeline: timeline,
                                  learningRowInput: learningRowInput,
                                  mastery: mastery,
                                  emphasizedSegments: emphasizedSegments,
                                  activatedSegments: selectedLearningSegments,
                                ),
                              ],
                            ],
                          ),
                        ),
                        // 练习片段轨域：练习视频轨整行住该域自带的
                        // widget 子树——行背景、块体视觉与端点截取命中带、回看浮
                        // 条（含它自己的根浮层装配点）。带级只按行矩形与时间轴组
                        // 装它、不转发任何行内命中或拖动；块体与浮条不再是带级叠
                        // 的第二份。装配点仍住带内这处 Stack（与局部镜像片段同
                        // 层：视觉在轨内容层、命中住覆盖层才能压过带级手势层）。
                        if (practiceRect != null)
                          Positioned.fill(
                            child: TrackPracticeRow(
                              input: TrackPracticeRowInput(
                                clips: practiceClips,
                                rowRect: practiceRect,
                                bandHeight: widget.input.rowTable.totalHeight,
                                axis: axis,
                                playhead: () => _playhead.value,
                                onToggleClip: _togglePracticeClip,
                                trim: _practiceRowTrim,
                              ),
                            ),
                          ),
                        // 局部镜像轨域：片段块体层与行级点按层
                        // 一起住本行的整行子树（视觉在轨内容层、交互收口到
                        // 模块 verb 与拖动域句柄）。空轨只显示行背景。
                        if (mirrorRowInput != null)
                          TrackMirrorRow(input: mirrorRowInput),
                        // 备注轨域：整行交给
                        // 模块——块体、展开浮条、行级点按/长按与两族拖动都住
                        // 域内；带只组装（行背景、空白落穿、手势守卫与共用拖线
                        // 实时预览经输入值对象注入）。
                        if (notesRect != null)
                          Positioned(
                            left: 0,
                            top: notesRect.top,
                            width: axis.width,
                            height: notesRect.height,
                            child: TrackNoteRow(
                              input: TrackNoteRowInput(
                                notes: notes,
                                // 域内行矩形：域的渲染盒即该行矩形（行顶
                                // 已由本处 `Positioned` 让出）。
                                rowRect: TrackRowRect(
                                  top: 0,
                                  height: notesRect.height,
                                ),
                                axis: axis,
                                window: win,
                                selectedIndex: selectedNoteFragment,
                                highlightedStartMs: noteHighlight,
                                rosterColors: rosterColors,
                                drag: _dragDomain,
                                onBlankTapFallthrough:
                                    _forwardRowBlankTapToBandArbiter,
                                mixedPinchBurst: () => _mixedPinchBurst,
                                trackPinchActive: () => _trackPinchActive,
                                onDragPreviewBegin: _beginLineDragPreview,
                                onDragPreviewFrame: _previewLineDragFrame,
                                onDragPreviewEnd: () =>
                                    unawaited(_endLineDragPreview()),
                              ),
                            ),
                          ),
                        if (mappable && learningRowInput != null) ...[
                          for (var i = 0; i < timeline.segmentLines.length; i++)
                            _buildSegmentLineMarker(
                              index: i,
                              axis: axis,
                              window: win,
                              position: timeline.segmentLines[i].position,
                              selected: selectedLine == i || _draggingLine == i,
                              flagged: timeline.segmentLines[i].flagged,
                              // 线身可承载多条角标的锚点（分段锚改到
                              // 刚落的线上，与「标记分段线」共用同一条线身
                              // ——各自只在本会话记着该序号时才包）。
                              // 各单元按本会话记下的同一序号各自包
                              //（「标记分段线」与「三指跳转」两步同锚
                              // 刚标记的这条线身）。
                              guideAnchorKeys: [
                                for (final unitId in const [
                                  badgeSegmentFlagUnitId,
                                  badgeThreeFingerJumpUnitId,
                                ])
                                  liveArtifactAnchorKeyOfBase(
                                    unitId,
                                    segmentLineAnchorKeyBase,
                                    guideArtifactIndexes,
                                    i,
                                  ),
                              ].whereType<String>().toList(),
                            ),
                          // 线身单击层（仅 tap、不再整列按下即拖
                          // ——拖动移至轨道手柄带手柄起手）：命中带
                          // 贯穿全带高但仅学习轨行内触发临时段，节拍轨行/
                          // 轨间隙不触发线操作。命中层为学习段轨域件，
                          // 座位逐位沿用今天（在预览线/首尾线/控制柄之下）。
                          TrackLearningLineHitLayer(input: learningRowInput),
                        ],
                        if (mappable &&
                            timeline.videoDuration > Duration.zero &&
                            // 行集驱动：首/尾线视觉与其控制柄
                            // 属轨道手柄带行承载的编辑面——行集无该行时
                            // 一并不渲染（对比态行集不含此行）；有效练习
                            // 区间约束（录制/循环边界）读时间线真值，
                            // 不随线渲染消失。
                            handleStripRect != null) ...[
                          _buildVideoRangeLine(
                            axis: axis,
                            window: win,
                            timeline: timeline,
                            isStart: true,
                          ),
                          _buildVideoRangeLine(
                            axis: axis,
                            window: win,
                            timeline: timeline,
                            isStart: false,
                          ),
                          // 轨道手柄带域：槽位求值与摆位、三类手柄的装配
                          // 与手势接线、两族拖动与其族声明、端点键盘微调件
                          // 与线段取色全在该域；带只按行集与几何事实组装它。
                          // 本域不吸收空白命中（`Stack` 自身不吃指针），
                          // 只有控制柄命中区参与手势。
                          Positioned.fill(
                            // 本域 State 持有在飞的两族拖动句柄：前序子项
                            // （片段块、分段线标记/命中层）是可变长子项，
                            // 固定 key 让本域元素在兄弟列表增删时按 key 对上、
                            // 不换位重建。
                            key: const Key('track_handle_strip'),
                            child: TrackHandleStrip(
                              input: TrackHandleStripInput(
                                rowRect: handleStripRect,
                                axis: axis,
                                window: win,
                                bandWidth: constraints.maxWidth,
                                segmentLines: timeline.segmentLines,
                                rangeStart: timeline.rangeStart,
                                rangeEnd: timeline.rangeEnd,
                                selectedSegmentLineIndex: selectedLine,
                                draggingSegmentLineIndex: _draggingLine,
                                // 分段第 ① 步：高亮框框住**刚落那条
                                // 线**的控制柄——序号取本会话记下的新落线序号
                                // （连着落两条时改指第二条）；序号取不到即不
                                // 包锚点（锚点缺席，等它出现再上场）。
                                segmentSelectIndex:
                                    guideArtifactIndexes[badgeSegmentUnitId],
                                dragDomain: _dragDomain,
                                segmentToTime: _bandDragTime,
                                // 首尾端标与分段线共用同一条可空换算
                                // （总时长与生效窗口在带侧现势求值）。
                                rangeToTime: _bandDragTime,
                                beginSegmentLineSession: (index) => ref
                                    .read(annotationEditorProvider)
                                    .beginLineDrag(index),
                                beginRangeSession: (boundary) => ref
                                    .read(annotationEditorProvider)
                                    .beginRangeDrag(boundary),
                                onSegmentLineDragVisual:
                                    _setDraggingSegmentLine,
                                onRangeDragActive: _setRangeDragActive,
                                onBeginLineDragPreview: _beginLineDragPreview,
                                onLineDragPreviewFrame: _previewLineDragFrame,
                                onEndLineDragPreview: _endDragPreviewVisuals,
                                bandLocalX: _bandLocalX,
                                // 按下瞬间的最近线解析归命中解析适配层
                                // （track_hit_resolution.dart），域只收这一问
                                // 的答案。
                                resolveSegmentLineIndex:
                                    _nearestSegmentLineIndexAt,
                                onSegmentHandleTap: _handleControlKnobTap,
                                onRangeHandleTap: _toggleRangeBoundary,
                                onSegmentHandleNudge: _nudgeSegmentLine,
                                onRangeHandleNudge: _nudgeRangeBoundary,
                              ),
                            ),
                          ),
                        ],
                        // 插入半拍线覆盖层（节拍刻度域）：视觉短线 + 命中列
                        // 拖动精调——命中列
                        // 提到分段线/首尾线命中列**之上**（同位时节拍轨行横
                        // 拖归半拍线）；播放头 2dp 竖条仍最顶。本层是整条带大小
                        // 的盒（内部坐标 = 带内坐标），族随渲染住节拍刻度域。
                        if (mappable)
                          Positioned.fill(
                            key: const Key('track_half_beat_overlay'),
                            child: TrackHalfBeatOverlay(
                              input: TrackHalfBeatOverlayInput(
                                axis: axis,
                                window: win,
                                halfBeatLines: [
                                  for (final line in timeline.halfBeatLines)
                                    line.position,
                                ],
                                beatRowRect: beatRowRect,
                                anchorKeyOf: (index) =>
                                    liveArtifactAnchorKeyOfBase(
                                      badgeHalfBeatUnitId,
                                      halfBeatLineAnchorKeyBase,
                                      guideArtifactIndexes,
                                      index,
                                    ),
                                dragFamilies: _dragFamilies,
                                dragDomain: _dragDomain,
                                onDragVisualsBegin: _beginLineDragPreview,
                                onDragPreviewFrame: _previewLineDragFrame,
                                onDragVisualsEnd: _endDragPreviewVisuals,
                              ),
                            ),
                          ),
                        // 贯穿轨道的预览条：当前播放位置（拖动中 = 拖动目标，
                        // 与入队 seek 同源）；播放头在可视窗口外时隐藏。
                        //  z 序置顶：预览线绘制块移到分段线视觉/命中
                        // 层、首尾线、控制柄之后，成为轨道内容最上层；
                        // 预览线 2px 命中柱随之上移——与线重合时柱挡住线
                        // 正中心 2px，线命中带其余部分（±20dp）仍可点选/
                        // 操作，重合处拖动归属按「预览线优先」。
                        // 父级分支自身完整（判 [mappable]，不再
                        // 只判可空、靠 [_PlayheadLayer] 内部早退代偿）。
                        if (mappable)
                          _PlayheadLayer(
                            axis: axis,
                            playhead: _playhead,
                            // 预览线 2dp 命中柱压在练习片段块上时把
                            // 点按路由给片段块（否则这 2dp 就是块体上的第二
                            // 条死区——刚录完停在片段尾、激活后又停在片段
                            // 首，正好是两个最常被点的位置）。
                            onTapUp: (globalPosition) =>
                                _handlePlayheadTap(globalPosition),
                          ),
                        // 学习段轨域的覆盖层：临时衔接段青边框
                        // （跨段框住临时范围，z 序置顶后保持在
                        // 预览线之上，纯视觉不参与命中）与长按圈选判定区
                        // （判定区＝学习轨整行，段窄到分段线命中列
                        // 互相重叠时长按仍可达；translucent：进 arena 但不挡
                        // 下方任何命中；座位在预览线/首尾线/半拍线命中层之上、
                        // 轨道片头空白守卫之下，片头由那道不透明守卫吸收，
                        // 区间外空白落点按域内的准入不加入 arena——空白横滑的
                        // 精细调整与空白单击收起因此保持按下即胜出的既有
                        // 仲裁）。父级分支自身完整（判 [mappable]），
                        // 域件内部早退保留为防御。
                        if (mappable && learningRowInput != null)
                          TrackLearningRowOverlay(input: learningRowInput),
                        // 内容区之左的空白守卫：时间轴零点之左不落
                        // 任何内容——整条吸收命中，按在那里一律等于按在带上
                        // 空白（不选中、不拖动、不吸附；带级手势层是它的祖先，
                        // 空白单击/横滑照常）。它是**位置**上的守卫：片头滑出
                        // 可视带后这一条仍归空白，不因片头不画就露出底下的内容
                        // 命中层。片头在可视带内时把手柄带行让给首线
                        // 控制柄（片头那一段的起手因此落到控制柄），滑出可视带
                        // 后让位收手，零点之左仍整条空白。
                        if (geometry.contentLeft > 0)
                          ..._buildPrefixGuards(
                            contentLeft: geometry.contentLeft,
                            hole: geometry.prefixVisible
                                ? handleStripRect
                                : null,
                          ),
                        // 轨道片头：行集之外、时间轴零点之左的
                        // 一列短文字标签——画在轨道内容坐标系里（与刻度、
                        // 片段、线同一层），随窗口缩放/平移一起移动，滑出
                        // 可视带即整列不画（[prefixVisible]）。它落在内容区
                        // 之左、不侵占内容区，纵向与逐行行矩形对齐；纯显示，
                        // 命中归上面那条空白守卫。
                        if (geometry.prefixVisible)
                          _TrackPrefix(
                            left: geometry.prefixLeft,
                            width: geometry.prefixWidth,
                            rowTable: widget.input.rowTable,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 分段线可见标记：与预览条同法直接 Positioned 绘制（不嵌套命中层——
  /// 真机实测命中层内 Center→SizedBox 的细线不可见，而预览条直接绘制可见）。
  /// 视觉与 24dp 命中层分离；命中层负责长按拖动/flag/单击跳转，本标记只画线。
  Widget _buildSegmentLineMarker({
    required int index,
    required TimelineAxis axis,
    required TimelineWindow window,
    required Duration position,
    required bool selected,
    required bool flagged,
    List<String> guideAnchorKeys = const [],
  }) {
    if (!window.contains(position)) return const SizedBox.shrink();
    final x = axis.timeToX(position);
    // 宽度语义不变：默认细线 1 / 选中 3 / flag 粗 6。
    final width = flagged
        ? kSegmentLineFlaggedWidth
        : selected
        ? kSegmentLineSelectedWidth
        : kSegmentLineWidth;
    // 颜色分色：默认细线半透明白；选中=激活青；flag=琥珀。
    // flag 且选中 = 琥珀粗线 + 青色外发光（组合态肉眼可区分）。
    final color = flagged
        ? kSegmentLineFlaggedColor
        : selected
        ? kSegmentLineSelectedColor
        : kSegmentLineColor;
    final showGlow = flagged && selected;
    // 线身（角标锚点包在这一层：上报矩形恰是那条线，不含命中列与发光层）。
    // 同一条线可同时承载两条角标的锚点（分段与「标记分段线」共用线身
    // ——各自只在本会话记着该序号时才包，逐层嵌套、被包内容逐位不变）。
    Widget line = ColoredBox(
      key: ValueKey('segment_line_$index'),
      color: color,
    );
    for (final key in guideAnchorKeys) {
      line = _guideAnchored(key, line);
    }
    return Positioned(
      left: x - width / 2,
      top: 0,
      bottom: 0,
      width: width,
      child: IgnorePointer(
        child: showGlow
            ? Container(
                key: ValueKey('segment_line_${index}_glow'),
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: kSegmentLineSelectedGlowColor,
                      blurRadius: kSegmentLineSelectedGlowBlurRadius,
                      spreadRadius: kSegmentLineSelectedGlowSpreadRadius,
                    ),
                  ],
                ),
                child: line,
              )
            : line,
      ),
    );
  }

  /// 局部镜像轨行级点按的既有守卫：跨面双指 burst 与捏合期间不判定
  /// ——点选不改几何，锁定期照常选中、不弹锁提示；被守卫时连空白也不落穿。
  bool get _mirrorRowTapAllowed => !_mixedPinchBurst && !_trackPinchActive;

  /// 行级点按层空白命中的落穿：把本次单击（带内局部坐标）交给
  /// [_surface] 的带级空白 tap 仲裁——同一实例、同一份判定窗口。备注轨域
  /// 的行级层经输入回调交到本处（落穿留在带
  /// 级，判定不复刻第二份）。
  void _forwardRowBlankTapToBandArbiter(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    _surface.forwardRowBlankTap(box.globalToLocal(globalPosition));
  }

  /// 收实时预览的收口视觉（幂等，无会话可收时为空操作）：镜像两族与首尾端标
  /// 共用。
  void _endDragPreviewVisuals() => unawaited(_endLineDragPreview());

  /// 分段线单击（命中带内取最近线；选中 toggle——同线再点取消、
  /// 异线替换，不影响学习段激活/循环）。flag 与普通线交互完全一致
  /// （仍可被「删除」取消、「标记分段线」条目切换、视觉保留）；
  /// 定位由三指跳转与预览吸附承担。
  ///
  ///  触发区收窄：临时衔接段仅由
  /// **学习轨行内**点击线身触发（再点取消，激活同时选中该线）；
  /// 节拍轨行与轨间隙点击不触发线操作（本层命中带贯穿全带高，非学习轨
  /// 行的命中按无操作处理——不选中也无临时段，留待节拍调整）。
  ///
  ///  触发窗分侧限制：学习轨行
  /// 内点按只在与线中心横向距离 ≤ **点按所在侧**触发窗半宽
  /// （[transitionTriggerSideHalfWidths]：该侧 = min(20dp, 10% × 该侧邻学习
  /// 段显示宽)，左右可不对称）时开关临时段；窗外点按按「真实段优先」回落
  /// 为学习段命中（线命中半宽同用点按侧窗宽），落在段体上激活真实学习段；
  /// 任意学习段被两端相邻线窗合计占用 ≤20%、恒保留 ≥80% 触发面积。
  ///
  /// 命中解析（最近线、行归属、触发窗的每像素微秒）归适配层
  /// `track_hit_resolution.dart`，本处只组装：全局位置 → 适配层。
  void _handleSegmentLineTap(
    int fallbackIndex,
    Offset globalPosition,
    AnnotationTimeline timeline,
  ) {
    final box = _bandBox();
    if (box == null || box.size.width <= 0) return;
    final local = box.globalToLocal(globalPosition);
    final hits = _hitResolution(width: box.size.width, timeline: timeline);
    final index = hits.nearestSegmentLineOrFallback(fallbackIndex, local.dx);
    if (!hits.isLearningRow(local.dy)) return;
    final perPx = hits.geometry.microsecondsPerPixel;
    final sides = transitionTriggerSideHalfWidths(
      segments: deriveLearningSegments(timeline),
      lineIndex: index,
      microsecondsPerPixel: perPx,
      maxSideWidthPx: kTransitionTriggerMaxSideHalfWidthPx,
    );
    final lineX = hits.geometry.axis.timeToX(
      timeline.segmentLines[index].position,
    );
    final dx = local.dx - lineX;
    // 点按在线中心哪一侧，就用哪一侧的窗宽（左右可不对称）。
    final halfWidth = dx <= 0 ? sides.left : sides.right;
    if (dx.abs() <= halfWidth.inMicroseconds / perPx) {
      _selectSegmentLineAndRecord(
        index,
        (i) => ref.read(annotationEditorProvider).toggleTransitionSegment(i),
      );
    } else {
      // 窗外：真实学习段优先（线命中带同用点按侧窗宽）。
      _handleLearningTrackTap(local, lineHalfWidth: halfWidth);
    }
  }

  /// 点选一条分段线并记下（「动手步的判据」事实）：点控制柄、或在线身
  /// 那一行点它，**这一条**被选中就记它的序号——同线再点取消选中不算（写完
  /// 没选中就不记）；落线本身不选中这条线，故这一步必须由用户自己做到。判据
  /// 是否成立（这一条 = 刚落那条）由引导宿主比对序号，播放域只陈述事实。
  /// 只记事实，手势与标注行为逐位不变（选中的写点仍经选中域）。
  void _selectSegmentLineAndRecord(int index, void Function(int) select) {
    select(index);
    if (ref.read(selectedSegmentLineIndexProvider) == index) {
      ref
          .read(guideSessionProvider.notifier)
          .recordCriterion(HandsOnCriterion.badgeSegmentLineSelected, index);
    }
  }

  /// 命中解析适配层的组装点（本带唯一一处）：引擎接缝、会话域窗口与带宽、行表
  /// 与四份数据快照（时间线、练习片段、备注片段、镜像片段）一次给全。[timeline]
  /// 可交下调用点已持有的那一份（分段线点按一路），缺省现读 provider。
  TrackHitResolution _hitResolution({
    required double width,
    AnnotationTimeline? timeline,
  }) => TrackHitResolution(
    engine: _engine,
    window: _session.window,
    width: width,
    rowTable: widget.input.rowTable,
    timeline: timeline ?? ref.read(effectiveAnnotationTimelineProvider),
    clips: ref.read(practiceClipsProvider),
    notes: ref.read(noteStickersProvider),
    mirrorFragments: ref.read(localMirrorFragmentsProvider),
    playhead: _playhead.value,
  );

  /// 控制柄（轨道手柄带内）点击：仅选中分段线/再点取消
  /// （供标记/删除等工具使用），不激活临时衔接段。最近线解析由轨道手柄带域
  /// 经 [TrackHandleStripInput.resolveSegmentLineIndex] 问本带，本处只收解析
  /// 后的线下标。
  void _handleControlKnobTap(int index) {
    // 点选/清除写点统一经选中域封闭会话组。
    _selectSegmentLineAndRecord(
      index,
      (i) => _selectionDomain.toggle(SegmentLineSelection(i)),
    );
  }

  /// 分段线拖动的视觉簿记（轨道手柄带域交回）：拖动中下标只驱动本带 build
  /// （线身与把手的选中观感同源）；起手写序号、收口清 null。
  void _setDraggingSegmentLine(int? index) =>
      setState(() => _draggingLine = index);

  /// 首尾端标拖动在场事实（轨道手柄带域交回）：与族句柄同源，供本带两处
  /// 手势仲裁读取（scale 会话起点是否清选中、空白横滑是否让位）。
  void _setRangeDragActive(bool active) => _rangeDragActive = active;

  /// 带内局部 x 读取（无渲染盒 = 空）。`globalToLocal` 留在本带（它需要渲染
  /// 对象），域只收局部 x。分段线起手不读边界，本值只为域接口齐备而取。
  double? _bandLocalX(Offset globalPosition) =>
      _bandBox()?.globalToLocal(globalPosition).dx;

  /// 带宽读取（无渲染盒 = 空 → 域判几何不可用、逐帧返回空且不驱动画面）。
  double? _dragBandWidth() => _bandBox()?.size.width;

  /// 本带渲染盒（局部坐标与带宽读取的唯一一处）。
  RenderBox? _bandBox() {
    final box = context.findRenderObject();
    return box is RenderBox ? box : null;
  }

  /// 各族拖动逐帧换算：带内局部 x → 时间（本带几何唯一构造入口
  /// [_bandGeometry]；域只收局部 x，带宽由域交下、与本帧钳制同源）。总时长与
  /// 生效窗口在此**现势求值**，任一未知即空（该帧成为空操作）——分段线、
  /// 首尾端标、截取、镜像/备注各族共用这一条可空纪律。
  Duration? _bandDragTime(double localX, double bandWidth) {
    final total = _engine.duration;
    final win = _effectiveWindow();
    if (total == null || total <= Duration.zero || win == null) return null;
    return dragTimeAt(
      _bandGeometry(total: total, window: win, width: bandWidth).axis,
      localX,
    );
  }

  /// 分段线控制柄的键盘微调：方向键把该线挪到相邻八拍点（目标求值收在
  /// 纯件 [adjacentEightBeatPoint]）。与拖动**同一条写入口**——标注编辑
  /// 模块的拖动会话（beginLineDrag→moveTo→end）与同一落点解析/门禁；被拒
  /// （分段锁、对比/组员方案只读、装载未完成）即无损空操作，不弹提示、
  /// 不动既有拖动手感。
  void _nudgeSegmentLine(int index, int direction) {
    if (_trackPinchActive || _loadGateActive) return;
    if (_gestureStartRejected(AnnotationGestureTarget.segmentLineMove)) {
      return;
    }
    final lines = ref.read(effectiveAnnotationTimelineProvider).segmentLines;
    if (index < 0 || index >= lines.length) return;
    final target = adjacentEightBeatPoint(
      ref.read(beatPhaseProvider),
      ref.read(beatGridProvider),
      lines[index].position,
      direction,
    );
    if (target == null) return;
    final session = ref.read(annotationEditorProvider).beginLineDrag(index);
    session.moveTo(target);
    session.end();
  }

  /// 首/尾线控制柄的键盘微调：与拖动同一条模块会话写入口，
  /// 门禁与归一化钳制仍在模块内裁决。端点键盘微调**件**随族搬进轨道手柄带域
  /// 微调动作住本带（它读 provider），由那一域按方向键回调；目标求值收在
  /// 纯件 [adjacentBeatPoint]。
  void _nudgeRangeBoundary(VideoRangeBoundary boundary, int direction) {
    if (_trackPinchActive || _loadGateActive) return;
    if (_gestureStartRejected(AnnotationGestureTarget.rangeBoundaryDrag)) {
      return;
    }
    final timeline = ref.read(effectiveAnnotationTimelineProvider);
    final current = boundary == VideoRangeBoundary.start
        ? timeline.rangeStart
        : timeline.rangeEnd;
    final target = adjacentBeatPoint(
      ref.read(beatGridProvider),
      current,
      direction,
    );
    if (target == null) return;
    final session = ref.read(annotationEditorProvider).beginRangeDrag(boundary);
    session.moveTo(target);
    session.end();
  }

  ///  预览线命中列：起手位置落在预览线当前位置 ± [kPreviewLineHitColumnWidth]
  /// /2 的列内（预览线在可视窗口内时）。
  ///
  /// **轨道片头带（内容区之左那一段）不在命中列内**——按在片头上
  /// 等于按在带上空白（零点贴内容区左缘时半列都压在片头里，不排除就会把
  /// 片头起手变成预览线内容拖动）。
  bool _inPreviewLineHitColumn(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    return band != null && _previewLineColumnAt(band.local.dx);
  }

  /// 拖动几何快照：总时长 + 生效窗口 + 渲染盒三者齐备才有拖动
  /// 语义（预览线拖动/命中列共用；不满足返回 null）。带宽非正
  /// 与「总时长未知」同级——守卫收在唯一构造点，四个消费点一次性受益
  /// （零宽不再可能走到对无穷取整）。
  DragContext? _dragContext() {
    final total = _engine.duration;
    final win = _effectiveWindow();
    final box = context.findRenderObject();
    if (total == null ||
        total <= Duration.zero ||
        win == null ||
        box is! RenderBox ||
        box.size.width <= 0) {
      return null;
    }
    return (total: total, window: win, box: box);
  }

  /// 拖线实时预览起手：在播先暂停定格（同步回调宿主更新播放态 UI），定格点
  /// 快照为松手恢复目标。引擎时长未知时不建会话（拖线语义照旧）。pause 在
  /// 首个预览 seek 之前发出（FakeEngine callLog 顺序与
  ///  微调同款断言）。
  void _beginLineDragPreview() {
    if (_lineDragPreview != null) return;
    final engine = _engine;
    final wasPlaying = engine.isPlaying;
    final position = engine.position;
    if (position < Duration.zero) return;
    if (wasPlaying) {
      unawaited(engine.pause());
    }
    _lineDragPreview = (restoreTo: position, wasPlaying: wasPlaying);
  }

  /// 拖线实时预览单帧：经会话域的唯一 seek 装配提交——串行帧级
  /// seek 队列发往引擎（节流 latest-wins）、目标越出生效循环范围时取消激活
  /// （与其他 seek 入口同一判定，防循环层拽回段首——拖线本身改变几何时激活
  /// 已随时间线重建清空，此处兜底未变更的钳制态）；预览线显示值不写（保持
  /// 原位不随动，故走提交器的静默分支）。时长未知防御：拖动中途切换视频
  /// （duration 变 null/0）时丢弃本帧。
  void _previewLineDragFrame(Duration target) {
    if (_lineDragPreview == null) return;
    final total = _engine.duration;
    if (total == null || total <= Duration.zero) return;
    _session.submitPicturePreview(target);
  }

  /// 拖线实时预览收尾（松手/取消共用）：seek 回起手定格点（拖线
  /// 不改变播放位置），恢复 seek 落定后原在播从该点续播、原暂停停在该点。
  Future<void> _endLineDragPreview() async {
    final session = _lineDragPreview;
    if (session == null) return;
    _lineDragPreview = null;
    await _session.settlePicturePreview(session.restoreTo);
    if (!mounted) return;
    if (session.wasPlaying) {
      await _engine.play();
    }
  }

  /// 段体抬手：跨面双指 burst 内不选中学习段；落点交回本带的学习段
  /// 命中解析（[TrackBand._handleLearningTrackTap]，域内只按段自身身份报事件）。
  void _handleLearningSegmentTapUp(TapUpDetails details) {
    if (_mixedPinchBurst) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    _handleLearningTrackTap(box.globalToLocal(details.globalPosition));
  }

  /// 按下即选：按下落在段体上即写——未选中的段即刻静默只选中
  /// 这一段（循环范围就位，播放不动）；已选中的段按兵不动，抬手才清空。
  /// 教程「编辑态上手」的判据事实同在按下那一刻记入（落点段为第一段时；
  /// 长按圈选从第一段起手同样先经此处）。
  void _handleLearningSegmentPressDown(int index) {
    //  混区起手与装载门内：不做按下选中副作用。
    if (_mixedPinchBurst || _loadGateActive) return;
    // 教程判据只认落地的按下（组员方案只读被拒/越界不记入）。
    if (!_selectionDomain.press(index)) {
      return;
    }
    if (index == firstLearningSegmentOrder) {
      ref
          .read(guideSessionProvider.notifier)
          .latch(HandsOnCriterion.editorIntroActivate);
    }
  }

  /// 段体按下会话被其它识别器接管（缩放起手/横向快滑/长按/系统打断）：
  /// 长按圈选已开session（回滚基线已继承按下前快照）只了结不回滚；其余
  /// 静默回滚到按下前的选中与循环。
  void _handleLearningSegmentTapCancel(int index) {
    if (_learningSpanFamilyRunning) {
      _selectionDomain.consumePress();
      return;
    }
    _selectionDomain.cancelPress();
  }

  /// 段体横向快滑＝清空后只选中这一段（写选中集合，手势识别
  /// 器本身仍挡掉轨道预览线 seek）；组员方案只读时 selectOnly 静默拒绝。
  /// 快滑起手接管按下会话时无回滚了结——横滑自己的「只选中这一
  /// 段」照常落地，不整片回滚、不落两次写。
  void _quickSelectSegment(int index) {
    //  混区起手：跨面双指 burst 内不做片段选中/拖动副作用（整场是
    // 缩放+平移）。
    if (_mixedPinchBurst) return;
    _selectionDomain.consumePress();
    _selectionDomain.selectOnly(index);
  }

  /// 学习段轨最近段命中：点按位置（带内局部坐标）的学习段命中次序
  /// 解析归适配层 `track_hit_resolution.dart`。命中学习段 → 抬手了结按下会话
  /// （按下写过则选中维持并恢复激活语义——跳选中首段段首并起播；按下
  /// 落在已选中的段则整片清空）；否则不消费（回落为轨道空白单击收起）。返回
  /// 是否消费。
  bool _handleLearningTrackTap(Offset local, {Duration? lineHalfWidth}) {
    final order = _hitResolution(width: _bandBox()?.size.width ?? 0)
        .learningHitOrderAt(local, lineHalfWidth: lineHalfWidth)
        .order;
    if (order == null) return false;
    // 分段线/首尾线的线抓取接线归；其命中层在带内更上层浮层自消费。
    // 抬手写点统一经选中域按下会话收口（先清临时段；组员方案只读
    // 静默拒绝）。
    _selectionDomain.liftPress(order);
    return true;
  }

  /// 全局位置 → 带内局部坐标（不钳制）与带宽；无渲染盒或带宽非正 = 空。
  /// 「全局 → 局部」的换算住本处（它需要带级渲染盒），命中判定全部归适配层
  /// `track_hit_resolution.dart`。
  ({Offset local, double width})? _bandLocalAt(Offset globalPosition) {
    final box = _bandBox();
    if (box == null || box.size.width <= 0) return null;
    return (local: box.globalToLocal(globalPosition), width: box.size.width);
  }

  /// 学习段圈选的落点解析组装（带内局部落点 → 适配层）：落点段序与「是否已
  /// 钳在首/末段」——逐帧与贴边滚屏都要问它（起手准入问 [spanOrderAt]）。
  ({int? order, bool atSpanEdge}) _learningSpanHitAt(Offset local) =>
      _hitResolution(width: _bandBox()?.size.width ?? 0)
          .learningHitResolve(local);

  /// 长按圈选识别器的落点准入（学习段轨域问本带）：
  /// 落点解析出可圈的学习段才准入——判定区因此与学习轨整行一致（分段线与
  /// 首尾线的命中窗不遮蔽长按），区间外空白落点不加入 arena。轨道片头带由更
  /// 上层的空白守卫吸收，不经本准入。
  int? _spanOrderAt(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    if (band == null) return null;
    return _learningSpanHitAt(band.local).order;
  }

  /// 全局位置 → 带内局部落点（不钳制）；无渲染盒或带宽非正 = 空。拖动域收
  /// 带内局部坐标，「全局 → 局部」的换算住本处（它需要带级渲染盒）。
  Offset? _bandLocalPoint(Offset globalPosition) =>
      _bandLocalAt(globalPosition)?.local;

  /// 局部镜像轨的编辑内容组装（全局位置 → 适配层）：纵向落在局部镜像轨行
  /// 内、且经该轨公开的命中入口命中片段为真。
  bool _mirrorRowContentAt(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    if (band == null) return false;
    return _hitResolution(width: band.width).mirrorContentAt(band.local);
  }

  /// 按下瞬间的最近线解析组装（轨道手柄带域问本带）：全局位置 → 最近分段线
  /// 下标；无渲染盒 = 空。
  int? _nearestSegmentLineIndexAt(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    if (band == null) return null;
    return _hitResolution(width: band.width)
        .nearestSegmentLineIndex(band.local.dx);
  }

  /// 点按下位置是否落在编辑内容上（内容命中检查）：目标族与判定次序
  /// （预览条 / 练习片段块 / 学习段轨命中 / 备注片段）归适配层
  /// `track_hit_resolution.dart`；本处只组装——全局位置 → 带内局部坐标 →
  /// 适配层。
  bool _isEditContentAt(Offset globalPosition) {
    final band = _bandLocalAt(globalPosition);
    if (band == null) return false;
    return _hitResolution(width: band.width).editTargetAt(band.local) != null;
  }

  /// 首/尾线视觉 + 线身单击层：线身只保留单击选中（toggle 加粗）
  /// 与视觉，不再整列按下即拖——调界拖动移至轨道手柄带控制柄（见
  /// [TrackHandleStrip]）。
  Widget _buildVideoRangeLine({
    required TimelineAxis axis,
    required TimelineWindow window,
    required AnnotationTimeline timeline,
    required bool isStart,
  }) {
    final position = isStart ? timeline.rangeStart : timeline.rangeEnd;
    if (!window.contains(position)) return const SizedBox.shrink();
    final kind = isStart ? _VideoRangeDrag.start : _VideoRangeDrag.end;
    //  选中上提：端标选中读自密封点选状态（带外可读，与帧步进/
    // 清除规则共用），不再用带内局部 setState。
    final selected =
        ref.watch(selectedVideoRangeBoundaryProvider) ==
        kind.asSelectionBoundary;
    final x = axis.timeToX(position);
    final hit = kVideoRangeHitWidth;
    final lineWidth = selected
        ? kVideoRangeSelectedLineWidth
        : kVideoRangeLineWidth;
    final lineColor = isStart
        ? kVideoRangeStartLineColor
        : kVideoRangeEndLineColor;
    // 线身视觉（线身单击层共用）。
    final lineBody = GestureDetector(
      // 只注册 tap：单击 = 切换选中加粗（不收起、不调界）；线身拖动已
      // 移除，带内空白拖动（含越过线列）归预览条 scrub。
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleRangeBoundary(kind.asSelectionBoundary),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: hit / 2 - lineWidth / 2,
            top: 0,
            bottom: 0,
            width: lineWidth,
            child: ColoredBox(
              key: Key(
                isStart ? 'video_range_start_line' : 'video_range_end_line',
              ),
              color: lineColor,
            ),
          ),
        ],
      ),
    );
    return Positioned(
      left: x - hit / 2,
      top: 0,
      bottom: 0,
      width: hit,
      // 首尾线：两条边界各承载自己那枚锚点——线不在窗口内就不
      // 渲染，那一枚锚点随即从矩形板撤下。
      child: GuideAnchor(
        anchorKey: isStart
            ? practiceRangeHeadAnchorKey
            : practiceRangeTailAnchorKey,
        key: Key(
          isStart ? 'practice_range_head_line' : 'practice_range_tail_line',
        ),
        child: lineBody,
      ),
    );
  }

  /// 首/尾端标点选 toggle（线身单击与轨道手柄带控制柄点按同一出口）：
  /// 写入密封点选状态（与分段线/学习段选中互斥、带外可读）。
  void _toggleRangeBoundary(VideoRangeBoundary boundary) {
    // 写入密封点选状态（与分段线/学习段选中互斥、带外可读）。
    // 点选写点统一经选中域。
    _selectionDomain.toggle(VideoRangeBoundarySelection(boundary));
  }
}

/// 预览线叶子层（分层刷新）：播放 tick 与拖动目标都经 [playhead]
/// notifier 驱动，本层在自身 RepaintBoundary 内单独重绘——静态轨道层
/// （片段/分段线/首尾线/刻度）不随逐帧位置刷新整带重建；仅当可视窗口
/// （缩放/贴边平移/跟随）变化时随整带重建换新 [axis] 映射。
///
/// 预览条是轨道编辑内容：命中在此吸收（只注册 tap 保护）——其上
/// 不识别空白区双击、单击不视为轨道空白收起。**一处例外**：压在练习片段块上
/// 的那 2dp 不再吞掉点按——[onTapUp] 把落点交回带级路由（命中片段块即
/// 激活，与块体同一条路径），未压在块上时行为与既有吸收语义一致。
class _PlayheadLayer extends StatelessWidget {
  const _PlayheadLayer({
    required this.axis,
    required this.playhead,
    required this.onTapUp,
  });

  /// 当前映射（total × 宽 × 可视窗口；随窗口变化由宿主重建传入）。
  final TimelineAxis axis;

  /// 播放头显示位置（拖动中 = 拖动目标，与入队 seek 同源）。
  final ValueListenable<Duration> playhead;

  /// 预览线命中柱上的点按（全局位置；内容路由由宿主决定）。
  final ValueChanged<Offset> onTapUp;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: playhead,
          builder: (context, _) {
            // 父级分支已判可映射；本早退保留为防御。
            if (axis.isEmpty) return const SizedBox.shrink();
            final window = axis.window ?? TimelineWindow.full(axis.total);
            final pos = playhead.value;
            if (!window.contains(pos)) return const SizedBox.shrink();
            final x = axis.timeToX(pos);
            return Stack(
              children: [
                Positioned(
                  left: x - kPreviewLineWidth / 2,
                  top: 0,
                  bottom: 0,
                  width: kPreviewLineWidth,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) => onTapUp(details.globalPosition),
                    child: const ColoredBox(
                      key: Key('preview_line'),
                      color: kPreviewLineColor,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 临时衔接段激活声明：触发只报身份，渲染归演出层
/// 唯一宿主——轨道带不再持有提示状态机与浮层。
const transitionNoticeSpec = NoticeSpec(
  id: NoticeId.transition,
  noticeKey: Key('transition_prompt'),
  content: _transitionNoticeContent,
);

/// 临时衔接段提示内容（语义档（随系统字号）：提示文案随系统字号缩放，读不到
/// 它会丢失信息）。
Widget _transitionNoticeContent(BuildContext _) =>
    const Text('衔接练习：前 1 八拍 ↔ 后 1 八拍循环', style: kNoticeTextStyle);
