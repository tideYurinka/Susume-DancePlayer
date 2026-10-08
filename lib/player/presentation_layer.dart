/// 演出层：播放页画面之上的整棵浮层子树收在
/// 本层——数拍跟练浮层、局部镜像标识、备注贴纸、循环/续播/镜像提示、观看态
/// 倍速入口与气泡宿主、取景条、录制钮与回看出口、控制层、备注文本编辑面、
/// 打开失败提示与各短暂提示浮层。
///
/// 契约：[PresentationLayer] 收一个显式的输入值对象
/// [PresentationLayerInput]——页面级 UI 事实（控制层开合、取景态、对比态、
/// 骨架、浮层可见性、提示方向）与域句柄（画面层、引擎、各提示控制器）一次
/// 给全；本层自带 widget 子树，不反向 import 播放页
/// （`player_page.dart`），也不读中枢。
///
/// 依赖方向（单向）：本层 → 画面层、控制层与各域模块的 widget / 控制器 /
/// 提示件；反向无——播放页只组装本层。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/compare_materials.dart' show PracticeClip;
import '../annotation/framing_selection.dart' show FramingSelection;
import '../core/playback/playback_engine_providers.dart'
    show playbackPositionProvider;
import '../surface_direction/surface_direction.dart' show FaceDirection;
import 'annotation_edit.dart' show RemoveNote, ToggleNoteLock;
import 'annotation_editor.dart'
    show
        annotationEditorProvider,
        noteStickersProvider,
        practiceOnscreenFaceProvider;
import 'beat_animation.dart' show beatAnimationStyleProvider;

import 'package:dance_learning_app/camera_capture/camera_capture.dart';

import 'compare_framing_bar.dart'
    show FramingBar, kCompareFramingBarBottomInset;
import 'framing_session_state.dart' show framingStateProvider;
import 'compare_framing_view.dart' show compareFramingPictureRect;
import 'compare_recording.dart'
    show
        CompareRecordButton,
        CompareRecordingPhase,
        compareRecordingPhaseProvider,
        kCompareRecordButtonBottomInset;
import 'compare_recording_clips.dart' show CompareRecordingClips;
import 'cast_picture_area.dart' show CastPictureArea, CastStatusCapsule;
import 'control_layer.dart' show ControlLayer;
import 'editor_entry.dart' show EditorEntry;
import 'editor_skeleton.dart' show EditorSkeleton, cornerPromptAnchor;
import 'engine_seek.dart' show EngineSeek;
import '../core/frame_time.dart' show kDefaultVideoFps;
import 'framing_stage.dart' show singlePictureFramedPictureRectOnScreen;
import 'gesture_arbitration.dart' show GestureArbitration;
import 'gesture_feedback.dart' show GestureFeedbackController;
import 'gestures.dart' show systemGestureYieldInsets;
import 'local_mirror_picture_mark.dart' show LocalMirrorPictureMark;
import 'loop_prompt.dart' show LoopPromptController, LoopPromptOverlay;
import 'metronome_overlay.dart' show MetronomeOverlay;
import 'mirror.dart' show MirrorController, MirrorOverlay;
import 'note_editor.dart'
    show
        NoteTextEditorPanel,
        noteFragmentHighlightProvider,
        noteTextEditorTargetProvider;
import 'note_sticker_layout.dart' show videoContentRectInBox;
import 'note_sticker_overlay.dart' show NoteStickerOverlay;
import 'notice.dart'
    show NoticeHost, NoticeId, NoticeSpec, threeFingerToastDirectionProvider;
import '../core/notice_badge.dart' show NoticeBadge;
import 'picture_layer.dart'
    show
        PictureFaceInput,
        PictureFeedbackInput,
        PictureFrameInput,
        PictureGestureInput,
        PictureLayer,
        PictureLayerInput,
        PicturePlaybackInput,
        PicturePracticeInput,
        PictureVideoInput;
import 'practice_surface.dart' show PracticeSurface;
import 'presentation_session.dart' show PresentationSession;
import 'prep_center_big_number.dart' show PrepCenterBigNumber;
import 'rate_label_slot.dart' show RateTextSlot;
import 'recording_playback_takeover.dart' show RecordingPlaybackTakeover;
import 'resume_prompt.dart' show ResumePromptOverlay;

import 'song_naming_session.dart' show SongNamingSession;
import '../stats/song_signature.dart' show SongSignatureController;
import 'speed_bubble.dart'
    show SpeedBubbleHost, SpeedBubbleMode, speedBubbleSessionProvider;
import 'speed_control.dart' show speedControlProvider;
import 'surface_face_assembly.dart' show SurfaceFaceScope;
import 'system_ui.dart' show ScreenOrientation;
import 'track_row_table.dart' show TrackRowTable;
import 'track_band_session.dart' show TrackBandSession;
import 'segment_jump.dart' show ThreeFingerSwipeDirection;
import 'visual_tokens.dart' show kHighlightAmber, kNoticeTextStyle;

/// 演出层输入（显式的「这一层要什么」清单）：页面级 UI 事实 + 域句柄 +
/// 三条宿主动作回调（播放暂停、延迟播放与退出回看保留播放页的编排）。
class PresentationLayerInput {
  const PresentationLayerInput({
    required this.engineSeek,
    required this.editorEntry,
    required this.gestures,
    required this.compareRecordingClips,
    required this.loopPrompt,
    required this.mirror,
    required this.signature,
    required this.naming,
    required this.session,
    required this.noticeSpecs,
    required this.presentation,
    required this.camera,
    required this.takeover,
    required this.feedback,
    required this.scrubTarget,
    required this.speedBubbleLink,
    required this.beatBubbleLink,
    required this.faceDirection,
    required this.skeleton,
    required this.rowTable,
    required this.controlOpen,
    required this.framingActive,
    required this.compareWatching,
    required this.isCompare,
    required this.isCast,
    required this.metronomeVisible,
    required this.opened,
    required this.openFailed,
    required this.reviewingClip,
    required this.systemTopInset,
    required this.systemBottomInset,
    required this.videoFilePath,
    required this.systemGestureInsets,
    required this.scrubPictureRectOf,
    required this.landscape,
    required this.onControlLayerBack,
    required this.onOpenFailedBack,
    required this.beatCountContent,
    required this.onTogglePlay,
    required this.onDelayedPlay,
    required this.onExitClipReview,
    required this.onCloseBeatOverlay,
    required this.onRequestOrientation,
    required this.onDisconnectCast,
    required this.onToggleCastPicture,
  });

  final EngineSeek engineSeek;
  final EditorEntry editorEntry;
  final GestureArbitration gestures;
  final CompareRecordingClips compareRecordingClips;
  final LoopPromptController loopPrompt;
  final MirrorController mirror;
  final SongSignatureController signature;
  final SongNamingSession naming;
  final TrackBandSession session;

  /// 提示声明清单（组合根装配）：演出层只挂一条宿主。
  final List<NoticeSpec> noticeSpecs;

  /// 演出层会话（浮层控制器、装配句柄与提示控制器的唯一持有者）。
  final PresentationSession presentation;
  final CameraCaptureService camera;
  final RecordingPlaybackTakeover takeover;
  final GestureFeedbackController feedback;
  final ValueNotifier<Duration> scrubTarget;
  final LayerLink speedBubbleLink;
  final LayerLink beatBubbleLink;

  /// 画面层要的画面方向快照（唯一装配点给出的那一份）。
  final FaceDirection faceDirection;

  /// 竖屏编辑骨架（宿主唯一求值点给出的那一份）。
  final EditorSkeleton skeleton;

  /// 模式对应的轨道行集（骨架整带高与控制层行集共用一份答案）。
  final TrackRowTable rowTable;

  final bool controlOpen;
  final bool framingActive;
  final bool compareWatching;
  final bool isCompare;

  /// 是否处于投屏态（投屏-控制层或投屏-观看态）。投屏态的画面区不画源片
  /// （黑底 + 指路提示，或静音本地预览），且贴纸 / 数拍 / 节拍动画与画面
  /// 标识一律不上屏（它们已在电视上）。
  final bool isCast;

  final bool metronomeVisible;
  final bool opened;
  final bool openFailed;
  final PracticeClip? reviewingClip;

  /// 布局事实（构建上下文读取留在组合根）：系统栏顶内缩与横竖屏姿态。
  final double systemTopInset;

  /// 布局事实（构建上下文读取留在组合根）：
  /// 系统栏**底**内缩——与顶内缩同一条口径，供横屏编辑态的提示卡占用区
  /// 上缘换算（`屏高 − 底内缩 − 工具行名义高 − 整带高`）。
  final double systemBottomInset;

  /// 布局事实（构建上下文读取留在组合根）：系统手势内缩——
  /// 贴底常驻入口在固定边距上叠加它避开手势让路区；为 0 时落位不变。
  final EdgeInsets systemGestureInsets;

  /// 这支舞的**视频副本**路径（组合根唯一知道的那个路径）：投屏入口
  /// 「副本丢失」门的输入（其余四条的读面在 `cast_entry_gate.dart` 里
  /// 自己接）。
  final String videoFilePath;

  /// 画面矩形现读闭包：组合根解一次、手势仲裁域
  /// 与浮层标记吃同一份；本层只转发，不重写 contain 算术。
  final Rect Function() scrubPictureRectOf;
  final bool landscape;

  /// 宿主导航动作（构建上下文归组合根）：控制层返回与打开失败返回。
  final VoidCallback onControlLayerBack;
  final VoidCallback onOpenFailedBack;

  /// 断开投屏（投屏态顶栏那枚工具）：与投屏态内的左上角退出箭头同义，
  /// 两处入口都调宿主同一处动作。
  final VoidCallback onDisconnectCast;

  /// 画面开关（投屏态顶栏那枚工具）：把画面区从黑底切成静音本地预览、或切
  /// 回黑底。起播定位与静音归投屏预览域，宿主只交出这一下点按。
  final VoidCallback onToggleCastPicture;

  /// 数拍跟练内容（读节拍发布值的自订阅件，由播放页组装后交来）。
  final Widget beatCountContent;

  final VoidCallback onTogglePlay;
  final VoidCallback onDelayedPlay;
  final VoidCallback onExitClipReview;

  /// 浮层 ✕ 关闭（置总开关为关 + 退选中态 + 弹重开提示，归播放页编排）。
  final VoidCallback onCloseBeatOverlay;

  /// 方向动作回调（唯一一枚）：语义 = 「请求屏幕朝向转为 X」。
  /// 竖屏图标的锚在演出层，故回调挂在这里；宿主把它接到方向控制器上。
  final ValueChanged<ScreenOrientation> onRequestOrientation;
}

/// 演出层（层域：自带 widget 子树）。组装顺序即层序，与既有整页渲染逐位
/// 一致；画面方向由外层 [SurfaceFaceScope] 给出，本层经
/// [SurfaceFaceScope.of] 读取。
class PresentationLayer extends ConsumerWidget {
  const PresentationLayer({super.key, required this.input});

  final PresentationLayerInput input;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = this.input;
    final controlOpen = input.controlOpen;
    final framingActive = input.framingActive;
    final isCompare = input.isCompare;
    final isCast = input.isCast;
    // 取景读数：取景态内画面按整帧显示，
    // 故此刻一切下游读数也按未取景；退出后按选区内容重新取值。
    final framing = framingActive
        ? null
        : ref.watch(framingStateProvider.select((s) => s.source));
    final beatAnimationStyle = ref.watch(beatAnimationStyleProvider);
    // 录制中（含准备期）：转屏钮不出现——录制画面方向在起录瞬间已锁定，
    // 中途改布局只会让预览与素材不一致。
    final recording =
        ref.watch(compareRecordingPhaseProvider) != CompareRecordingPhase.idle;
    // 避开系统手势让路区：叠加组合根传入的系统上报内缩，
    // 为 0 时落位不变。
    final gesture = input.systemGestureInsets;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 播放手势层与画面层自带子树：本层只把入口值对象一次给全。
        PictureLayer(
          input: _pictureLayerInput(
            ref,
            faceDirection: input.faceDirection,
            isCompare: isCompare,
          ),
        ),
        // 局部镜像画面标识：层序 = 视频画面之后、用户浮层内容之前。
        // 投屏态不挂：画面区画的是投屏侧那份面（黑底指路 / 静音预览），
        // 画面标识属于源片标注的呈现，已在电视上。
        if (!isCast)
          LayoutBuilder(
            builder: (context, constraints) {
              if (!SurfaceFaceScope.localMirrorActiveOf(context)) {
                return const SizedBox.shrink();
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fromRect(
                    rect: _pictureMarkRect(
                      isCompare: isCompare,
                      box: constraints.biggest,
                      editingSkeleton: controlOpen ? input.skeleton : null,
                      selection: framing,
                    ),
                    child: const LocalMirrorPictureMark(),
                  ),
                ],
              );
            },
          ),
        // 数拍跟练浮层：只在内容可见时挂载（幽灵浮层修复）。投屏态不挂：
        // 数拍与节拍动画已在电视上（且它们是渲染那一刻算出来的），手机上
        // 再画一份只会与本地预览打架。
        if (!isCast && !input.openFailed && input.metronomeVisible)
          MetronomeOverlay(
            controller: input.presentation.metronome,
            style: beatAnimationStyle,
            readOnly: controlOpen || framingActive,
            onClose: input.onCloseBeatOverlay,
            beatBubbleLink: input.beatBubbleLink,
            onToggleBeatBubble: () {
              final session = ref.read(speedBubbleSessionProvider);
              final bubble = ref.read(speedBubbleSessionProvider.notifier);
              if (session.open == SpeedBubbleMode.beat) {
                bubble.close();
              } else {
                bubble.open(SpeedBubbleMode.beat);
              }
            },
            child: input.beatCountContent,
          ),
        // 备注贴纸浮层：窗内显隐由播放头驱动、渲染矩形同步注册表。
        // 投屏态不挂本层：贴纸已在电视上那份投屏副本里，手机上这份画面区
        // 只画视频画面本身。
        LayoutBuilder(
          builder: (context, constraints) {
            if (isCast) return const SizedBox.shrink();
            final faceDirection = SurfaceFaceScope.of(context);
            return Stack(
              fit: StackFit.expand,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final position = ref.watch(playbackPositionProvider).value;
                    return NoteStickerOverlay(
                      positionMs: position?.inMilliseconds ?? 0,
                      contentRect: _framedPictureRect(
                        isCompare: isCompare,
                        box: constraints.biggest,
                        editingSkeleton: controlOpen ? input.skeleton : null,
                        selection: framing,
                      ),
                      framingSelection: framing,
                      faceDirection: faceDirection,
                      readOnly: controlOpen || framingActive,
                      registration: input.presentation.noteSticker,
                      onDelete: (note) {
                        final notes = ref.read(noteStickersProvider);
                        final index = notes.indexWhere(
                          (n) => n.startMs == note.startMs,
                        );
                        if (index < 0) return;
                        ref
                            .read(annotationEditorProvider)
                            .submit(RemoveNote(index: index));
                      },
                      onOpenEditor: (note) => ref
                          .read(noteTextEditorTargetProvider.notifier)
                          .open(note.startMs),
                      onJumpToFragment: (note) {
                        ref
                            .read(noteFragmentHighlightProvider.notifier)
                            .highlight(note.startMs);
                        input.editorEntry.requestEntry();
                      },
                      onToggleLock: (note) {
                        final notes = ref.read(noteStickersProvider);
                        final index = notes.indexWhere(
                          (n) => n.startMs == note.startMs,
                        );
                        if (index < 0) return;
                        ref
                            .read(annotationEditorProvider)
                            .submit(ToggleNoteLock(index: index));
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
        // 打开失败提示（自带「返回」按钮，独立接管点击）。
        if (input.openFailed) _openFailedOverlay(input.onOpenFailedBack),
        // 镜像询问/历史提示覆盖层。
        MirrorOverlay(controller: input.mirror),
        // 观看态倍速入口与气泡宿主（仅控制层收起显示）。投屏态不挂：
        // 投屏-观看态屏上只留一枚只作状态提示的投屏胶囊（倍速是投屏倍速档
        // 的事，不在这一票的范围里）。
        if (!controlOpen && !framingActive && !isCast) ...[
          Positioned(
            right: 12 + gesture.right,
            bottom: 12 + gesture.bottom,
            child: CompositedTransformTarget(
              link: input.speedBubbleLink,
              child: Consumer(
                builder: (context, ref, _) {
                  final open = ref.watch(speedBubbleSessionProvider).open;
                  return _SpeedEntryButton(
                    onPressed: () {
                      final bubble = ref.read(
                        speedBubbleSessionProvider.notifier,
                      );
                      open == SpeedBubbleMode.speed
                          ? bubble.close()
                          : bubble.open(SpeedBubbleMode.speed);
                    },
                  );
                },
              ),
            ),
          ),
          SpeedBubbleHost(
            linkFor: (mode) => switch (mode) {
              SpeedBubbleMode.speed => input.speedBubbleLink,
              SpeedBubbleMode.beat ||
              SpeedBubbleMode.beatAlign ||
              SpeedBubbleMode.beatDensity => input.beatBubbleLink,
              SpeedBubbleMode.avSync => input.speedBubbleLink,
            },
            targetAnchor: Alignment.topCenter,
            followerAnchor: Alignment.bottomCenter,
            offset: const Offset(0, -8),
          ),
        ],
        // 取景条：取景调节态画面底部居中的操作条。
        if (framingActive)
          Positioned(
            left: 0,
            right: 0,
            bottom: kCompareFramingBarBottomInset,
            child: Center(
              child: FramingBar(
                onReset: () => ref.read(framingStateProvider.notifier).reset(),
                onDone: input.editorEntry.exitFraming,
              ),
            ),
          ),
        // 对比-播放态常驻录制钮：底部居中、底边留 24 + 系统手势
        // 内缩；取景调节态内不画（底部居中让给取景条）。录制期（含准备期）
        // 一律拒绝进入取景调节态，故「取消准备 / 停止录制」的出口不会丢。
        // 本钮不承载任何引导锚点与触达器。
        if (input.compareWatching)
          Positioned(
            left: 0,
            right: 0,
            bottom: kCompareRecordButtonBottomInset + gesture.bottom,
            child: Center(
              child: CompareRecordButton(
                controller: input.compareRecordingClips.controller,
                onTap: input.compareRecordingClips.onRecordButtonTap,
              ),
            ),
          ),
        // 回看出口件：回看中常驻，仍在右下角既有落位（「底 116 / 右 12 + 手势
        // 内缩」——不再与底部居中的录制钮同列，也不再在它正上方一行）。
        if ((input.compareWatching || framingActive) &&
            input.reviewingClip != null &&
            input.compareRecordingClips.phase == CompareRecordingPhase.idle)
          Positioned(
            right: 12 + gesture.right,
            bottom: 116 + gesture.bottom,
            child: _ClipReviewExitChip(onTap: input.onExitClipReview),
          ),
        // 投屏胶囊：投屏-观看态（控制层收起）屏上唯一常驻件，只作状态提示
        // （「投屏中 · 接收端名」）。它不接任何手势、点它不产生任何状态变化；
        // 要展开控制层就点画面（胶囊之外）——那条是既有画面点按路径。
        if (isCast && !controlOpen) const CastStatusCapsule(),
        // 控制层（标注编辑外壳）：展开时为顶层覆盖层。竖屏转屏钮与气泡覆盖层
        // 的层序住在控制层内部（见 [ControlLayer]）。
        if (controlOpen)
          ListenableBuilder(
            listenable: input.signature,
            builder: (context, _) {
              // 「进观看态」把手随装配点交入演出层会话：引导域的
              // 请求经会话间接驱动同一条收起路径，不绕过本装配点。幂等覆盖。
              input.presentation.attachCollapseControlLayer(
                input.editorEntry.collapse,
              );
              return ControlLayer(
                session: input.session,
                title: input.naming.titleText,
                mirror: input.mirror,
                playing: input.engineSeek.engine.isPlaying,
                onTogglePlay: input.onTogglePlay,
                onDelayedPlay: input.onDelayedPlay,
                onBack: input.onControlLayerBack,
                onCollapse: input.editorEntry.collapse,
                onEditSignature: () => unawaited(input.naming.rename()),
                skeleton: input.skeleton,
                rowTable: input.rowTable,
                // 录制门禁读取一次（本层已在读），横屏文字钮与竖屏图标同门。
                recording: recording,
                // 横屏文字钮复用同一枚方向动作回调。
                onRequestOrientation: input.onRequestOrientation,
                onDisconnectCast: input.onDisconnectCast,
                onToggleCastPicture: input.onToggleCastPicture,
                onScrubCommitted: input.loopPrompt.markManualSeek,
                // 投屏入口「副本丢失」门的输入：路径取自组合根。
                videoFilePath: input.videoFilePath,
              );
            },
          ),
        // 两张左下角提示卡（循环提示 / 续播提示）：层序 = 控制层之后、
        // 备注文本编辑器与屏幕中央提示之前
        // （卡在控制层空白手势面之上是它可点的唯一手段）；两张卡拿同一份
        // 锚——每帧算一次，落位规则只有一条（`cornerPromptAnchor`）。
        LayoutBuilder(
          builder: (context, constraints) {
            final anchor = _promptAnchor(
              constraints.biggest,
              selection: framing,
            );
            return Stack(
              fit: StackFit.expand,
              children: [
                LoopPromptOverlay(controller: input.loopPrompt, anchor: anchor),
                ResumePromptOverlay(anchor: anchor),
              ],
            );
          },
        ),
        // 备注文本编辑器面：Stack 顶层、控制层之上。
        const NoteTextEditorPanel(),
        // 屏幕中央短暂提示（整页最后绘制）：唯一宿主只渲染当前这一条。
        NoticeHost(specs: input.noticeSpecs),
      ],
    );
  }

  /// 组装画面层输入：这一层要的画面方向快照、宽高比、骨架、对比取景、
  /// 练习面方向、反馈会话、播放态与手势层件入参一次给全。
  PictureLayerInput _pictureLayerInput(
    WidgetRef ref, {
    required FaceDirection faceDirection,
    required bool isCompare,
  }) {
    final input = this.input;
    final engine = input.engineSeek.engine;
    // 单画面取景态控制层已收起，但竖屏
    // 编辑面的贴底骨架仍在（未调过的整帧按贴底落位）；其余收起面不落骨架。
    final keepSkeleton =
        input.controlOpen || (input.framingActive && !input.isCompare);
    return PictureLayerInput(
      face: PictureFaceInput(source: faceDirection),
      video: PictureVideoInput(
        aspectRatio: engine.videoAspectRatio,
        surfaceBuilder: engine.buildVideoSurface,
      ),
      frame: PictureFrameInput(
        skeleton: keepSkeleton ? input.skeleton : null,
        // 系统栏顶内缩是布局事实：宿主现读后交给画面层，层不碰构建上下文。
        systemTopInset: input.systemTopInset,
        compareActive: isCompare,
        framingActive: input.framingActive,
      ),
      // 练习侧只在对比态装配（非对比态不读练习面 provider，与「练习面仅对比态
      // 渲染」逐位一致）。
      practice: isCompare
          ? PicturePracticeInput(
              surface: PracticeSurface(
                camera: input.camera,
                takeover: input.takeover,
                face: ref.watch(practiceOnscreenFaceProvider),
                buildClipPicture: () =>
                    input.compareRecordingClips.clipEngine
                        ?.buildVideoSurface() ??
                    const SizedBox.shrink(),
              ),
            )
          : const PicturePracticeInput(surface: null),
      feedback: PictureFeedbackInput(
        controller: input.feedback,
        scrubTarget: input.scrubTarget,
        durationOf: () => engine.duration,
        frameRateOf: () => engine.videoFps ?? kDefaultVideoFps,
        pictureRectOf: input.scrubPictureRectOf,
      ),
      playback: PicturePlaybackInput(
        isPlaying: engine.isPlaying,
        opened: input.opened,
        openFailed: input.openFailed,
        // 画面播放开关的语义/键盘激活与双击同源（宿主装配点交入）。
        onTogglePlay: input.onTogglePlay,
      ),
      gesture: PictureGestureInput(
        doubleTapRecognizer: input.gestures.doubleTapRecognizer,
        longPressRecognizer: input.gestures.longPressRecognizer,
        onScaleStart: input.gestures.onScaleStart,
        onScaleUpdate: input.gestures.onScaleUpdate,
        onScaleEnd: input.gestures.onScaleEnd,
        onPointerDown: input.gestures.onPointerDown,
        onPointerUp: input.gestures.onPointerUp,
        onPointerCancel: input.gestures.onPointerCancel,
      ),
      // 视频区正中大数字与长按 2× 提示是页面级自订阅的层内叠加件——画面层
      // 只负责摆位（层序与既有整页渲染逐位一致）。投屏态两者都不上屏：
      // 画面区只画视频画面本身（黑底指路 / 静音本地预览）。
      prepCenterNumber: input.isCast
          ? const SizedBox.shrink()
          : const PrepCenterBigNumber(),
      doubleSpeedBadge: input.isCast
          ? const SizedBox.shrink()
          : const _DoubleSpeedOverlay(),
      // 投屏态的画面区覆盖件：源片不上手机屏（电视上那份才是正的）。
      pictureOverride: input.isCast ? const CastPictureArea() : null,
    );
  }

  /// 两张提示卡落位的**唯一求解点**：
  /// 每帧算一次、两张卡拿同一份。画面矩形取既有两份读面——非对比态 = 备注
  /// 贴纸同一份画面内容矩形（含竖屏编辑态贴底画面带分支）、对比态 = 组合根
  /// 那座画面矩形读面（源半区）；不新写 contain 算术。
  ///
  /// `cornerPromptAnchor` 给的是屏幕坐标（卡底边的 y）；卡收 `Positioned`
  /// 语义（距屏底的距离），换算只在本处收一次。
  ({double left, double bottom})? _promptAnchor(
    Size screen, {
    required FramingSelection? selection,
  }) {
    final input = this.input;
    // 控制层展开时的那份编辑面骨架（画面矩形与占用区上缘共用同一份）。
    final editingSkeleton = input.controlOpen ? input.skeleton : null;
    // 系统手势让路带 = `lib/player/CONTEXT.md`「系统手势让路区」：系统上报内缩与固定下限
    // 逐边取大（下限只有 `gestures.dart` 一处声明），故零上报设备也让路。
    final yieldInsets = systemGestureYieldInsets(
      system: input.systemGestureInsets,
    );
    final pictureRect = input.isCompare
        ? input.scrubPictureRectOf()
        : _framedPictureRect(
            isCompare: false,
            box: screen,
            editingSkeleton: editingSkeleton,
            selection: selection,
          );
    final anchor = cornerPromptAnchor(
      pictureRect: pictureRect,
      screen: screen,
      systemTopInset: input.systemTopInset,
      systemBottomInset: input.systemBottomInset,
      // 让路带取 `lib/player/CONTEXT.md` 的系统手势让路区（每边 max(上报值, 固定下限)）。
      gestureLeft: yieldInsets.left,
      gestureBottom: yieldInsets.bottom,
      editingSkeleton: editingSkeleton,
      trackBandHeight: input.rowTable.totalHeight,
    );
    if (anchor == null) return null;
    return (left: anchor.left, bottom: screen.height - anchor.bottom);
  }

  /// 画面矩形（注解层读数基准，与视频画面件渲染的是同一块）：单画面路径 =
  /// 观看看态整屏 contain / 竖屏编辑贴底画面带 / 编辑态背景位；对比路径 =
  /// 源半区 contain。[selection] 非空时按**取景选区**取值（取景后的
  /// 画面矩形）；`null` = 未调过，即未取景的画面矩形。
  Rect _framedPictureRect({
    required bool isCompare,
    required Size box,
    required EditorSkeleton? editingSkeleton,
    required FramingSelection? selection,
  }) {
    final aspectRatio = input.engineSeek.engine.videoAspectRatio;
    if (!isCompare) {
      final framed = singlePictureFramedPictureRectOnScreen(
        screen: box,
        systemTopInset: input.systemTopInset,
        skeleton: editingSkeleton,
        aspectRatio: aspectRatio,
        selection: selection,
      );
      // 宽高比未知（画面即容器）时退化为宿主框整体。
      return framed ??
          videoContentRectInBox(box: box, aspectRatio: aspectRatio);
    }
    // 对比源侧半区同口径：读数一律落到源半区的画面矩形（未调过 =
    // 整帧 contain、取景后 = 选区内容 contain）——未调过与「选区恰好覆盖整
    // 帧」在显示上不可区分。
    return compareFramingPictureRect(
      screen: box,
      landscape: input.landscape,
      aspectRatio: aspectRatio,
      selection: selection,
    );
  }

  /// 局部镜像画面标识的矩形：非对比态 = 画面矩形；对比态 = 源视频半区的
  /// 画面矩形（取景后 = 该半区取景后的画面矩形）。
  Rect _pictureMarkRect({
    required bool isCompare,
    required Size box,
    required EditorSkeleton? editingSkeleton,
    required FramingSelection? selection,
  }) {
    if (!isCompare) {
      return _framedPictureRect(
        isCompare: false,
        box: box,
        editingSkeleton: editingSkeleton,
        selection: selection,
      );
    }
    return compareFramingPictureRect(
      screen: box,
      landscape: input.landscape,
      aspectRatio: input.engineSeek.engine.videoAspectRatio,
      selection: selection,
    );
  }
}

/// 打开失败提示（自带「返回」按钮，独立接管点击）：导航动作由宿主交入，
/// 本层不碰构建上下文。
Widget _openFailedOverlay(VoidCallback onBack) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.white70),
        const SizedBox(height: 12),
        const Text(
          '视频打开失败',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onBack, child: const Text('返回')),
      ],
    ),
  );
}

/// 倍速入口按钮：右下角显示当前生效倍率，点击展开/收起；步进启用时附徽标。
class _SpeedEntryButton extends ConsumerWidget {
  const _SpeedEntryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final control = ref.watch(speedControlProvider);
    return Material(
      color: Colors.black.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        key: const Key('speed_entry_button'),
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.speed, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              RateTextSlot(
                rate: control.effectiveRate,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (control.stepEnabled) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: kHighlightAmber.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '步进',
                    style: TextStyle(color: kHighlightAmber, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按 2× 提示浮层：瞬态倍速生效期间画面中央叠加「2 倍速」提示。
class _DoubleSpeedOverlay extends ConsumerWidget {
  const _DoubleSpeedOverlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(
      speedControlProvider.select((state) => state.transientActive),
    );
    if (!active) return const SizedBox.shrink();
    return IgnorePointer(
      child: Center(
        child: const NoticeBadge(
          key: Key('double_speed_badge'),
          child: Text('2 倍速', style: kNoticeTextStyle),
        ),
      ),
    );
  }
}

/// 回看出口件（画面常驻）：文字 + 停止图标，点按 = 退出回看。
class _ClipReviewExitChip extends StatelessWidget {
  const _ClipReviewExitChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const label = '退出回看';
    return Semantics(
      key: const Key('clip_review_exit_chip'),
      button: true,
      label: label,
      onTap: onTap,
      // 可见文字与图标只是名字的视觉呈现：不排除会让合并节点多出一段
      // 同名 label（读屏重复播报，语义断言也拿不到干净名字）。
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.stop_circle_outlined,
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 三指跳转「已跳转」声明：方向经
/// [threeFingerToastDirectionProvider] 注入点读取，内容声明因此是常量；
/// 渲染归演出层唯一宿主，触发面由触发跳转的那一处只报身份。
const threeFingerToastNoticeSpec = NoticeSpec(
  id: NoticeId.threeFingerToast,
  noticeKey: Key('three_finger_toast'),
  content: _threeFingerToastContent,
);

/// 三指跳转提示内容：方向图标（左滑回退 / 右滑前进）+ 通用文案「已跳转」。
Widget _threeFingerToastContent(BuildContext _) =>
    const _ThreeFingerToastContent();

class _ThreeFingerToastContent extends ConsumerWidget {
  const _ThreeFingerToastContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final left =
        ref.watch(threeFingerToastDirectionProvider) ==
        ThreeFingerSwipeDirection.left;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          left ? Icons.fast_rewind : Icons.fast_forward,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(width: 8),
        const Text('已跳转', style: kNoticeTextStyle),
      ],
    );
  }
}
