/// 画面层模块：播放页里那段画面构建代码的归宿。
///
/// 这一层**自带**它的 widget 子树：手势层件（`Listener` + `GestureDetector` +
/// `RawGestureDetector` 三层骨架）、视频画面件（含镜像翻转闸门）、练习面
/// （对比半区内容与方向）与反馈层（scrub / 音量亮度指示）。它不读 Riverpod
/// 容器、不 import 中枢库、不碰任何页面级 UI 状态
/// （控制层开合、沉浸模式、气泡会话）、也不读构建上下文（布局事实随输入
/// 传入）——判据见 `picture_layer` 的结构护栏套件。可被直接 pump：造一份
/// [PictureLayerInput] 即挂载，不需要十二个 provider 替换。
///
/// ## 库头契约：画面层输入值对象
///
/// 入口是**一个**显式的值对象 [PictureLayerInput]，不是十个具名构造参数。
/// 它的形状就是「这一层需要什么」的可读清单，作为后续层域的样板；加一项输入
/// 只改这一处（值对象字段 + 装配点）。七组事实按概念分行，另加两个层内摆位槽：
///
/// - `face`：画面方向快照——源视频面方向（画面件翻转闸门读它）。
/// - `video`：视频画面件——宽高比与画面内核自供的构建器。
/// - `frame`：**有效区间取景与画面落位**——对比态分屏取景（`compareActive`）
///   与取景调节态描边（`framingActive`）表达「有效区间取景」；竖屏编辑骨架
///   非空 = 按骨架落位。
/// - `practice`：练习面——练习半区内容件（null = 无练习面）。显示层方向归
///   内容件自身（相机与练习面域的 PracticeSurface）。
/// - `feedback`：反馈会话——相位控制器、scrub 目标位置、总长/帧率/画面矩形
///   （现读闭包，见 [PictureFeedbackInput]）。
/// - `playback`：播放指示——引擎播放态、打开态与打开失败态。
/// - `gesture`：手势层件入参——识别器与回调；**手势仲裁逻辑仍归宿主**，
///   本层只拥有那三件 widget 骨架。
/// - `prepCenterNumber` / `doubleSpeedBadge`：层内**摆位槽**——录制准备/延迟
///   预备的居中大数字与长按 2× 提示住在这一层的 Stack 里（层序与既有整页
///   渲染逐位一致），但两者自订阅宿主侧 provider，故由宿主传入 widget、层只
///   负责摆位。它们不属于「这一层要什么」的领域事实，故单列。
///
/// 值对象按内容判等（[PictureLayerInput.==]）：输入相等时这一层不重建子树
/// （画面件构建器不再被调用），输入真变才重建。
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart'
    show
        GestureRecognizer,
        GestureScaleEndCallback,
        GestureScaleStartCallback,
        GestureScaleUpdateCallback,
        LongPressGestureRecognizer,
        PointerCancelEvent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, LogicalKeyboardKey;

import '../surface_direction/surface_direction.dart' show FaceDirection;
import 'advanced_gestures.dart' show PlayerDoubleTapGestureRecognizer;
import 'compare_split.dart' show CompareVideoSplit;
import 'editor_skeleton.dart' show EditorSkeleton, kEditorTopBarHeight;
import 'framing_selection_view.dart' show FramingSelectionView;
import 'gesture_feedback.dart';
import 'level_feedback.dart';
import 'scrub_indicator.dart';
import 'visual_tokens.dart' show kKeyboardFocusHighlight;

/// 画面层输入：本层挂载所需的全部外部事实（见库头契约）。
class PictureLayerInput {
  const PictureLayerInput({
    required this.face,
    required this.video,
    required this.frame,
    required this.practice,
    required this.feedback,
    required this.playback,
    required this.gesture,
    required this.prepCenterNumber,
    required this.doubleSpeedBadge,
  });

  /// 画面方向快照。
  final PictureFaceInput face;

  /// 视频画面件。
  final PictureVideoInput video;

  /// 画面落位（骨架 / 对比取景）。
  final PictureFrameInput frame;

  /// 练习面。
  final PicturePracticeInput practice;

  /// 反馈会话。
  final PictureFeedbackInput feedback;

  /// 播放指示。
  final PicturePlaybackInput playback;

  /// 手势层件入参。
  final PictureGestureInput gesture;

  /// 层内叠加件：录制准备/延迟预备的居中大数字（页面级自订阅，层只负责
  /// 摆位——层序在反馈层之下，与既有整页渲染逐位一致）。
  final Widget prepCenterNumber;

  /// 层内叠加件：长按 2× 提示（层序在反馈层之上，与既有整页渲染逐位一致）。
  final Widget doubleSpeedBadge;

  @override
  bool operator ==(Object other) =>
      other is PictureLayerInput &&
      other.face == face &&
      other.video == video &&
      other.frame == frame &&
      other.practice == practice &&
      other.feedback == feedback &&
      other.playback == playback &&
      other.gesture == gesture &&
      other.prepCenterNumber == prepCenterNumber &&
      other.doubleSpeedBadge == doubleSpeedBadge;

  @override
  int get hashCode => Object.hash(
    face,
    video,
    frame,
    practice,
    feedback,
    playback,
    gesture,
    prepCenterNumber,
    doubleSpeedBadge,
  );
}

/// 画面方向快照：源视频面方向。
class PictureFaceInput {
  const PictureFaceInput({required this.source});

  /// 源视频面方向（渲染层翻转闸门读它，不触源文件字节）。
  final FaceDirection source;

  @override
  bool operator ==(Object other) =>
      other is PictureFaceInput && other.source == source;

  @override
  int get hashCode => source.hashCode;
}

/// 视频画面件：宽高比与画面内核自供的构建器。
class PictureVideoInput {
  const PictureVideoInput({
    required this.aspectRatio,
    required this.surfaceBuilder,
  });

  /// 视频宽高比（宽 / 高）；null 或非正 = 未知（内核自行 contain）。
  final double? aspectRatio;

  /// 构建画面控件（`PlaybackEngine.buildVideoSurface`；资源跨 rebuild 复用）。
  final Widget Function() surfaceBuilder;

  @override
  bool operator ==(Object other) =>
      other is PictureVideoInput &&
      other.aspectRatio == aspectRatio &&
      other.surfaceBuilder == surfaceBuilder;

  @override
  int get hashCode => Object.hash(aspectRatio, surfaceBuilder);
}

/// 画面落位：竖屏编辑骨架、系统栏顶内缩与对比态取景。
class PictureFrameInput {
  const PictureFrameInput({
    required this.skeleton,
    required this.systemTopInset,
    required this.compareActive,
    required this.framingActive,
  });

  /// 竖屏编辑骨架；非空 = 按骨架落位（贴底 / 背景位）。null =
  /// 观看态或横屏面（画面走整屏 contain）。
  final EditorSkeleton? skeleton;

  /// 系统栏顶内缩（屏幕坐标，装配点现读后传入）——画面带顶换算的一项。
  /// 作为输入而非层内读布局上下文：这一层因此不碰构建上下文。
  final double systemTopInset;

  /// 对比态：画面按设备方向等分两块（源侧 / 练习侧）。
  final bool compareActive;

  /// 取景调节态：对比半区挂「当前作用侧」描边。
  final bool framingActive;

  @override
  bool operator ==(Object other) =>
      other is PictureFrameInput &&
      other.skeleton == skeleton &&
      other.systemTopInset == systemTopInset &&
      other.compareActive == compareActive &&
      other.framingActive == framingActive;

  @override
  int get hashCode =>
      Object.hash(skeleton, systemTopInset, compareActive, framingActive);
}

/// 练习面：练习半区内容件（自带显示层方向）。
class PicturePracticeInput {
  const PicturePracticeInput({required this.surface});

  /// 练习半区内容件（实时预览 / 片段回放）；null = 无练习面（空件）。
  final Widget? surface;

  @override
  bool operator ==(Object other) =>
      other is PicturePracticeInput && other.surface == surface;

  @override
  int get hashCode => surface.hashCode;
}

/// 反馈会话：相位控制器与 scrub 指示的取值来源。
class PictureFeedbackInput {
  const PictureFeedbackInput({
    required this.controller,
    required this.scrubTarget,
    required this.durationOf,
    required this.frameRateOf,
    required this.pictureRectOf,
  });

  /// 手势反馈相位控制器（scrubbing / levelAdjust / idle）。
  final GestureFeedbackController controller;

  /// scrub 目标位置（每帧经 ValueNotifier 更新，与 seek 动作同源）。
  final ValueListenable<Duration> scrubTarget;

  /// 视频总长**现读**；未知（未解析 / 打开失败）时为 null——指示只显示目标
  /// 时间。现读而非构建期取值：时长在打开后才解析落定，指示内容构建时读到
  /// 的必须是当时的总长。
  final Duration? Function() durationOf;

  /// 帧号换算帧率**现读**（引擎可暴露的 demux-fps；取不到由装配点给缺省）。
  final double Function() frameRateOf;

  /// 画面矩形**现读**：取消区标记的圆心与半径
  /// 源——与手势仲裁域消费同一份组合根解出的矩形。现读：拖动中途旋转屏幕、
  /// 切换控制层开合时标记按同一条规则重算落点。
  final Rect Function() pictureRectOf;

  @override
  bool operator ==(Object other) =>
      other is PictureFeedbackInput &&
      other.controller == controller &&
      other.scrubTarget == scrubTarget &&
      other.durationOf == durationOf &&
      other.frameRateOf == frameRateOf &&
      other.pictureRectOf == pictureRectOf;

  @override
  int get hashCode =>
      Object.hash(controller, scrubTarget, durationOf, frameRateOf, pictureRectOf);
}

/// 播放指示：引擎播放态与打开态。
///
/// 可见条件读**引擎真实播放态**（单一真源）：`!isPlaying && opened &&
/// !openFailed && !反馈会话激活` 时显示中央播放图标。
class PicturePlaybackInput {
  const PicturePlaybackInput({
    required this.isPlaying,
    required this.opened,
    required this.openFailed,
    required this.onTogglePlay,
  });

  /// 引擎当前播放态。
  final bool isPlaying;

  /// 视频是否已打开。
  final bool opened;

  /// 打开是否失败。
  final bool openFailed;

  /// 播放/暂停开关的写入口：画面层的语义激活与键盘空格/回车
  /// 都转调这一条——与双击同源（均由宿主装配点交入），不另开第二条路径。
  final VoidCallback onTogglePlay;

  @override
  bool operator ==(Object other) =>
      other is PicturePlaybackInput &&
      other.isPlaying == isPlaying &&
      other.opened == opened &&
      other.openFailed == openFailed &&
      other.onTogglePlay == onTogglePlay;

  @override
  int get hashCode =>
      Object.hash(isPlaying, opened, openFailed, onTogglePlay);
}

/// 手势层件入参：识别器与回调。
///
/// 手势**仲裁逻辑**（缩放增量、双击、长按、burst 锁定）仍归宿主，本层只
/// 拥有 `Listener` + `GestureDetector` + `RawGestureDetector` 三层骨架并把
/// 指针事件原样转交。
class PictureGestureInput {
  const PictureGestureInput({
    required this.doubleTapRecognizer,
    required this.longPressRecognizer,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
    required this.onPointerDown,
    required this.onPointerUp,
    required this.onPointerCancel,
  });

  final PlayerDoubleTapGestureRecognizer doubleTapRecognizer;
  final LongPressGestureRecognizer longPressRecognizer;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;
  final void Function(PointerDownEvent event) onPointerDown;
  final void Function(PointerUpEvent event) onPointerUp;
  final void Function(PointerCancelEvent event) onPointerCancel;

  @override
  bool operator ==(Object other) =>
      other is PictureGestureInput &&
      other.doubleTapRecognizer == doubleTapRecognizer &&
      other.longPressRecognizer == longPressRecognizer &&
      other.onScaleStart == onScaleStart &&
      other.onScaleUpdate == onScaleUpdate &&
      other.onScaleEnd == onScaleEnd &&
      other.onPointerDown == onPointerDown &&
      other.onPointerUp == onPointerUp &&
      other.onPointerCancel == onPointerCancel;

  @override
  int get hashCode => Object.hash(
    doubleTapRecognizer,
    longPressRecognizer,
    onScaleStart,
    onScaleUpdate,
    onScaleEnd,
    onPointerDown,
    onPointerUp,
    onPointerCancel,
  );
}

/// 画面层：自带手势层件、视频画面件、练习面与反馈层的 widget 子树。
///
/// 输入不变时不重建子树（值对象按内容判等）；输入真变才重建。布局事实
/// （系统栏顶内缩、竖屏编辑骨架）随输入传入，故本层不读构建上下文。
class PictureLayer extends StatefulWidget {
  const PictureLayer({super.key, required this.input});

  final PictureLayerInput input;

  @override
  State<PictureLayer> createState() => _PictureLayerState();
}

class _PictureLayerState extends State<PictureLayer> {
  Widget? _subtree;

  @override
  Widget build(BuildContext context) => _subtree ??= _build(widget.input);

  @override
  void didUpdateWidget(PictureLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.input != widget.input) {
      _subtree = null;
    }
  }

  Widget _build(PictureLayerInput input) {
    final gesture = input.gesture;
    return _PicturePlaySwitch(
      playback: input.playback,
      child: Listener(
        onPointerDown: gesture.onPointerDown,
        onPointerUp: gesture.onPointerUp,
        onPointerCancel: gesture.onPointerCancel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: gesture.onScaleStart,
          onScaleUpdate: gesture.onScaleUpdate,
          onScaleEnd: gesture.onScaleEnd,
          child: RawGestureDetector(
            key: const Key('player_surface'),
            behavior: HitTestBehavior.opaque,
            gestures: <Type, GestureRecognizerFactory<GestureRecognizer>>{
              PlayerDoubleTapGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    PlayerDoubleTapGestureRecognizer
                  >(() => gesture.doubleTapRecognizer, (_) {}),
              LongPressGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    LongPressGestureRecognizer
                  >(() => gesture.longPressRecognizer, (_) {}),
            },
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoArea(input),
                  _buildPlayIndicator(input),
                  input.prepCenterNumber,
                  GestureFeedbackOverlay(
                    controller: input.feedback.controller,
                    contentBuilder: (context) =>
                        _buildFeedbackContent(input.feedback),
                  ),
                  input.doubleSpeedBadge,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 中央播放提示：暂停时显示、播放中隐藏。任何手势反馈相位激活期间
  /// （scrubbing 定格预览、levelAdjust 音量/亮度调节）不显示暂停态大图标
  /// ——避免遮挡反馈内容；结束按真实状态如实显示（相位由控制器通知驱动
  /// 重建）。
  Widget _buildPlayIndicator(PictureLayerInput input) {
    final playback = input.playback;
    return ListenableBuilder(
      listenable: input.feedback.controller,
      builder: (context, _) {
        if (playback.isPlaying ||
            !playback.opened ||
            playback.openFailed ||
            input.feedback.controller.isActive) {
          return const SizedBox.shrink();
        }
        return const Center(
          child: Icon(
            Icons.play_circle_fill,
            key: Key('play_indicator'),
            size: 96,
            color: Colors.white70,
          ),
        );
      },
    );
  }

  /// 手势反馈浮层内容：按反馈相位挂载指示内容（IgnorePointer 由宿主
  /// [GestureFeedbackOverlay] 包裹，不拦截触摸、不与手势争 arena）。
  Widget _buildFeedbackContent(PictureFeedbackInput feedback) {
    final controller = feedback.controller;
    switch (controller.phase) {
      case GestureFeedbackPhase.scrubbing:
        return ListenableBuilder(
          listenable: Listenable.merge([feedback.scrubTarget, controller]),
          builder: (context, _) {
            // 取消区标记与气泡同属纯提示层：每帧现读画面矩形（拖动中途旋转
            // 屏幕时落点跟随），标记不拦截触摸。
            final pictureRect = feedback.pictureRectOf();
            return Stack(
              children: [
                Positioned(
                  left: pictureRect.left,
                  top: pictureRect.top,
                  child: ScrubCancelMark(
                    key: const Key('scrub_cancel_mark'),
                    pictureRect: pictureRect,
                    armed: controller.cancelArmed,
                  ),
                ),
                Center(
                  child: ScrubIndicator(
                    target: feedback.scrubTarget.value,
                    total: feedback.durationOf(),
                    armed: controller.cancelArmed,
                    fps: feedback.frameRateOf(),
                  ),
                ),
              ],
            );
          },
        );
      case GestureFeedbackPhase.levelAdjust:
        return LevelAdjustSlider(
          kind: controller.levelKind,
          value: controller.levelValue,
        );
      case GestureFeedbackPhase.idle:
        return const SizedBox.shrink();
    }
  }

  /// 视频画面区：contain 语义由引擎画面内核自供——media_kit 内部
  /// contain/旋转；测试内核按宽高比 AspectRatio 留黑。
  ///
  /// 镜像为渲染层翻转（[PictureFaceInput.source] 为镜像时对画面控件做水平
  /// Transform），不修改源文件字节。对比态在骨架之前返回；编辑面非空时按
  /// 骨架落位两分支（贴底 / 背景位），否则整屏 contain 居中。
  Widget _buildVideoArea(PictureLayerInput input) {
    final surface = _SourceVideoSurface(
      direction: input.face.source,
      surfaceBuilder: input.video.surfaceBuilder,
    );
    final frame = input.frame;
    if (frame.compareActive) {
      return CompareVideoSplit(
        // 源侧半区挂取景应用件（取景只有源画面一份）；练习半区不挂任何
        // 取景取值——恒按 contain 显示相机画面。
        source: FramingSelectionView(
          aspectRatio: input.video.aspectRatio,
          framingActive: frame.framingActive,
          child: surface,
        ),
        practice: _buildPracticePreview(input.practice),
      );
    }
    final skeleton = frame.skeleton;
    if (skeleton != null && skeleton.sticksToBottom) {
      // 贴底分支：画面件落在骨架给出的**画面带**内（带高已按选区内容比封顶
      // 在未取景画面矩形高），按取景选区 + 贴底几何派生显示变换——
      // 未调过 = 贴底画面带（贴画面区下缘）；圈小之后内容按 contain 装进
      // 带内，选区比源画面更「高」时左右留黑、顶边不上移。
      return Padding(
        padding: EdgeInsets.only(
          top:
              frame.systemTopInset +
              kEditorTopBarHeight +
              skeleton.pictureBandTop,
        ),
        // Align 把 tight 约束放宽给带盒（StackFit.expand 下 SizedBox 摆不进
        // tight 约束）；带盒 = 骨架给的全宽画面带。
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: double.infinity,
            height: skeleton.pictureBandHeight,
            child: FramingSelectionView(
              aspectRatio: input.video.aspectRatio,
              sticksToBottom: true,
              framingActive: frame.framingActive,
              child: surface,
            ),
          ),
        ),
      );
    }
    // 其余单画面（观看态 / 横屏编辑面 / 背景位）：整屏 contain，
    // 同一枚取景应用件（未调过 = 恒等显示，与既有整屏 contain 逐位一致）。
    return FramingSelectionView(
      aspectRatio: input.video.aspectRatio,
      framingActive: frame.framingActive,
      child: surface,
    );
  }

  /// 练习侧画面：练习半区内容件——练习面自带它的显示层方向（镜像显示层
  /// 恒在树上、不因开关或路径切换而换结构位）。
  Widget _buildPracticePreview(PicturePracticeInput practice) =>
      practice.surface ?? const SizedBox.shrink();
}

/// 画面播放开关的键盘/读屏替代路径：整块
/// 画面在无障碍树里是一个按钮（名字随播放态在「播放」「暂停」间切换），
/// 键盘空格/回车与语义激活都转调宿主交入的 [PicturePlaybackInput.onTogglePlay]
/// ——与双击同一条写入口。焦点可见性用内缘描边呈现，`IgnorePointer` 包住、
/// 不参与命中，视觉尺寸与全部手势仲裁（轴锁、让路区、灵敏度）逐位不变。
class _PicturePlaySwitch extends StatefulWidget {
  const _PicturePlaySwitch({required this.playback, required this.child});

  final PicturePlaybackInput playback;
  final Widget child;

  @override
  State<_PicturePlaySwitch> createState() => _PicturePlaySwitchState();
}

class _PicturePlaySwitchState extends State<_PicturePlaySwitch> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'picture_play_switch');
  bool _focused = false;

  bool get _canToggle =>
      widget.playback.opened && !widget.playback.openFailed;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    // 只在按下那刻激活（忽略 KeyRepeatEvent）：按住空格不来回切换播放态。
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.space &&
        key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (_canToggle) widget.playback.onTogglePlay();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    return Semantics(
      key: const Key('picture_play_switch'),
      container: true,
      explicitChildNodes: true,
      button: true,
      enabled: _canToggle,
      label: playback.isPlaying ? '暂停画面' : '播放画面',
      onTap: _canToggle ? playback.onTogglePlay : null,
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKeyEvent,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (_focused && _canToggle)
              const Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    key: Key('picture_focus_ring'),
                    decoration: BoxDecoration(
                      border: Border.fromBorderSide(
                        BorderSide(
                          color: kKeyboardFocusHighlight,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 显示层水平翻转件（源侧与练习侧共用的唯一一处镜像变换形状）：`scaleX = -1`
/// 为镜像，对画面子树做水平 [Transform]、不触源文件字节。
Widget _mirroredSurface({
  required Key key,
  required double scaleX,
  required Widget child,
}) => Transform(
  key: key,
  alignment: Alignment.center,
  transform: Matrix4.diagonal3Values(scaleX, 1, 1),
  child: child,
);

/// 源视频面画面件：按输入给出的方向读该面施加的缩放，画面件自己不持有方向
/// 口径。
///
/// 缩放为负时对画面控件做水平 [Transform]，不触源文件字节。播放进入/离开
/// 启用片段区间即翻/复由装配点重算——仅当方向真改变才重建本画面子树（避免
/// 无关每帧重建；`PlaybackEngine.buildVideoSurface` 契约保证画面资源跨
/// rebuild 复用）。
class _SourceVideoSurface extends StatefulWidget {
  const _SourceVideoSurface({
    required this.direction,
    required this.surfaceBuilder,
  });

  /// 源视频面方向（该面的画面即参照系，方向与缩放同值）。
  final FaceDirection direction;

  /// 构建画面控件（资源跨 rebuild 复用）。
  final Widget Function() surfaceBuilder;

  @override
  State<_SourceVideoSurface> createState() => _SourceVideoSurfaceState();
}

class _SourceVideoSurfaceState extends State<_SourceVideoSurface> {
  /// 画面子树宿主的稳定 [GlobalKey]：翻转态（bare ↔ Transform 包裹）切换时
  /// 画面控件元素靠本 key **搬运复用**、不被销毁重建——否则翻转一次即拆重建
  /// 平台画面（Texture 重初始化）→ 短暂黑屏闪。key 宿主恒在，只是在不翻转
  /// （直接返回）与翻转（作 Transform 子级）两种结构间迁移。
  final GlobalKey _surfaceHostKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final host = KeyedSubtree(
      key: _surfaceHostKey,
      child: widget.surfaceBuilder(),
    );
    final scaleX = widget.direction.scaleX;
    if (scaleX > 0) return host;
    return _mirroredSurface(
      key: const Key('mirrored_surface'),
      scaleX: scaleX,
      child: host,
    );
  }
}
