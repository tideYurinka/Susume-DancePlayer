import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_loop_layer.dart';
import '../core/playback/playback_loop_providers.dart';
import '../help/content_registry.dart' show HandsOnCriterion;
import '../help/guide_state.dart'
    show
        GuideEnterWatchingRequest,
        guideEnterWatchingRequestProvider,
        guideSessionProvider;
import '../help/player_drill.dart';
import '../import/import_providers.dart';
import '../persistence/annotation_save_orchestrator.dart';
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'practice_accounting_providers.dart' show practiceStatsRecorderProvider;
import '../plan/system_push_provider.dart' show planPushSyncProvider;
import '../player_session/player_session.dart';
import '../stats/practice_stats_session.dart';
import '../surface_direction/surface_direction.dart';
import 'advanced_gestures.dart';
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'beat_prompt_panel.dart' show beatPromptEnabledProvider;
import 'beat_prompts.dart'
    show
        beatAnalyzingNoticeSpec,
        beatNoDataNoticeSpec,
        beatOverlayCloseNoticeSpec;
import 'control_layer.dart';
import 'editor_entry.dart';
import 'editor_skeleton.dart';
import 'engine_seek.dart';
import 'delayed_play.dart';
import 'gesture_arbitration.dart';
import 'gesture_feedback.dart';
import 'annotation_editor.dart'
    show
        AnnotationSaveSinkModel,
        activeLoopRangeProvider,
        annotationEditorProvider,
        annotationSelectionDomainProvider,
        annotationSaveSinkProvider,
        annotationSaveSinkStateProvider,
        annotationTimelineProvider,
        clearLoopActivationsIfOutside,
        effectiveAnnotationTimelineProvider,
        exitPracticeClipReview,
        localMirrorEnabledProvider,
        localMirrorFragmentsProvider,
        noteStickersProvider,
        practiceClipActivationProvider,
        practiceClipById,
        practiceClipsProvider,
        practiceOnscreenFaceProvider,
        restoreQuietLoopWrite;
import 'load_gate.dart';
import 'loop_binding.dart' show LoopBinding, loopRangeRecord;
import 'tool_slots.dart' show PageWriteEntryId;
import 'visual_tokens.dart' show kNoticeTextStyle, kPlayerSkinColor;
import 'gestures.dart';
import 'level_control.dart';
import 'loop_prompt.dart';
import 'mirror.dart';
import 'metronome_overlay.dart';
import 'beat_presentation.dart' show BeatPresentation, BeatPresentationDriver;
import 'beat_presentation_providers.dart'
    show
        BeatCountContent,
        DelayAnchorModel,
        beatCountPositionProvider,
        beatOverlayContentVisibleProvider,
        beatPresentationFactsProvider,
        beatPresentationProvider,
        delayAnchorProvider;

import 'package:dance_learning_app/camera_capture/camera_capture.dart';

import 'camera_stage.dart';
import 'compare_recording.dart';
import 'compare_recording_clips.dart';
import 'speed_step_entry.dart' show stepEnabledNoticeSpec;
import 'recording_playback_takeover.dart';
import 'compare_framing_view.dart' show compareFramingPictureRect;
import 'framing_session_state.dart' show framingStateProvider;
import 'framing_stage.dart' show singlePictureFramedPictureRectOnScreen;
import 'framing_session.dart';
import 'presentation_session.dart' show PresentationSession;
import 'presentation_layer.dart'
    show PresentationLayer, PresentationLayerInput, threeFingerToastNoticeSpec;
import 'practice_clip_playback.dart'
    show PracticeClipPlaybackController, practiceClipEngineProvider;
import 'surface_basis_key.dart' show liveSurfaceBaselinesProvider;
import 'surface_face_assembly.dart' show SurfaceFaceAssembly, SurfaceFaceScope;
import 'material_library.dart' show currentVideoIdProvider;
import '../annotation/compare_materials.dart' show PracticeClip;
import '../persistence/material_manifest.dart'
    show
        materialManifestStoreProvider,
        materialRecordingFileResolverProvider,
        materialsBaseDirectoryProvider;
import '../core/private_json.dart' show privateJsonStorageProvider;

import 'note_editor.dart';
import 'open_session.dart';
import '../persistence/prep_beats_store.dart'
    show delayedLoopWaitProvider, prepBeatsProvider;
import '../persistence/song_signature.dart' show songFallbackName;
import '../core/beat_grid.dart';
import '../beat_track_state/beat_track_state.dart'
    show beatGridProvider, beatPhaseProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import 'beat_analysis.dart' show BeatAnalysisRunner, beatAnalysisRunnerProvider;
import 'open_restore.dart' show OpenLoadHost, videoOpenRestorerProvider;
import 'resume_position.dart' show ResumeRecorder;
import 'scheme_open.dart';
import 'session_mode_surfaces.dart' show sessionModeSurfacesOf;
import 'settings_persistence.dart';
import 'song_naming.dart';
import 'song_naming_session.dart';
import '../stats/song_signature.dart';
import 'track_row_table.dart' show TrackRowId, TrackRowTable;
import 'track_band_session.dart';
import 'speed_bubble.dart';
import 'speed_control.dart';
import 'system_ui.dart';
import 'notice.dart'
    show
        NoticeId,
        NoticeSpec,
        noticeTriggerProvider,
        threeFingerToastDirectionProvider;
import 'track_band.dart' show transitionNoticeSpec;
import 'no_subject_hint.dart' show noSubjectNoticeSpec;

/// 锁定分段提示内容：一行 = 身份 + 内容 + 定位 key。
Widget _layoutLockNoticeContent(BuildContext _) =>
    const Text('已锁定分段', style: kNoticeTextStyle);

const _layoutLockNoticeSpec = NoticeSpec(
  id: NoticeId.layoutLock,
  content: _layoutLockNoticeContent,
  noticeKey: Key('layout_lock_prompt'),
);

/// 备注内容锁提示内容。
Widget _noteContentLockNoticeContent(BuildContext _) =>
    const Text('备注已锁定', style: kNoticeTextStyle);

const _noteContentLockNoticeSpec = NoticeSpec(
  id: NoticeId.noteContentLock,
  content: _noteContentLockNoticeContent,
  noticeKey: Key('note_content_lock_prompt'),
);

/// 文档只读提示内容：一句话说明这次改动没存进去的原因。
Widget _documentReadOnlyNoticeContent(BuildContext _) =>
    const Text('这份文件只读，改动未存', style: kNoticeTextStyle);

const _documentReadOnlyNoticeSpec = NoticeSpec(
  id: NoticeId.documentReadOnly,
  content: _documentReadOnlyNoticeContent,
  noticeKey: Key('document_read_only_prompt'),
);

/// 短暂提示声明清单：组合根把各域的声明装配成交给
/// 演出层唯一宿主的清单；加一条新短暂提示 = 域内一行声明 + 此处一项。
const List<NoticeSpec> kNoticeSpecs = [
  localMirrorEmptyNoticeSpec,
  beatOverlayCloseNoticeSpec,
  stepEnabledNoticeSpec,
  compareRecordRejectedNoticeSpec,
  _layoutLockNoticeSpec,
  _noteContentLockNoticeSpec,
  beatAnalyzingNoticeSpec,
  beatNoDataNoticeSpec,
  loadGateNoticeSpec,
  noSubjectNoticeSpec,
  threeFingerToastNoticeSpec,
  transitionNoticeSpec,
  _documentReadOnlyNoticeSpec,
];

/// 本帧交付轨道带的实际行集（档位 × 两轨当前空否的**唯一剪裁点**）。
///
/// 常规档（平板）一律给该态全行集——空轨常驻，告诉用户这支舞还有备注轨、
/// 镜像轨这类东西可用。紧凑档下当前**一条片段都没有**的备注轨与局部镜像轨
/// 不占行（行背景、片头标签、命中一并离场），省下的行留给画面；落下第一条
/// 片段那一刻该行出现，删掉最后一条那一刻收走。
///
/// - [compact] 由调用方按本帧屏尺寸求值一次后传入（与骨架同源），本处不
///   重算——本行集与顶栏行集、气泡锚点因此同吃一份档位。
/// - 「当前空否」只读片段清单：备注轨 = 备注清单为空、镜像轨 = 局部镜像片段
///   清单为空；**不看「局部镜像」开关**（轨道的有无只跟着片段数走）。
/// - 装载未完成时按全行集渲染：此刻清单尚未读回，未知不当已知，也避免与
///   用户动作无关的「先矮后高」跳变。
/// - 对比态行集里本就没有局部镜像轨：去掉一个不在行集内的身份是空操作，
///   故本处不必分模式。
///
/// 行缺席不需要任何注销或清理：命中按行身份分派（行不在行集内时该轨内容
/// 不是命中对象，取矩形按既有口径报错），滞留的拖动族声明不可达、行重现时
/// 按同一门禁目标重新登记即覆盖；选中读面已按现势条数校验越界。
TrackRowTable _rowTableForTier({
  required TrackRowTable full,
  required bool compact,
  required bool loading,
  required bool notesEmpty,
  required bool mirrorEmpty,
}) {
  if (loading || !compact) return full;
  return full.withoutRows({
    if (notesEmpty) TrackRowId.note,
    if (mirrorEmpty) TrackRowId.localMirror,
  });
}

/// 全屏播放器页。
///
/// - 打开即播放（引擎 `open(play: true)`）
/// - 画面 contain 显示不裁剪：竖屏源视频横屏时两侧留黑
/// - 随设备横竖屏自动旋转（不锁定方向，[SystemUiController] 接管沉浸模式）
/// - 基础手势：单一 ScaleGestureRecognizer 按
///   pointerCount 分支——单指左右滑调进度（低灵敏度）、双指左右滑调进度
///   （高灵敏度）、右侧上下滑调音量、左侧上下滑调亮度；
/// - 高级手势：单指双击暂停/播放、双指双击延迟播放（一个八拍后
///   开始播放、期间播放占位提示音、任意操作中断）——双击类手势用自定义
///   [PlayerDoubleTapGestureRecognizer]（自带实现会把双指并击误判为双击）
///   经 [RawGestureDetector] 接入；
/// - 三指滑动跳转：并入单一 ScaleGestureRecognizer 流程
///   （pointerCount==3 分支）——自定义识别器与 scale 的 gesture arena 争斗在
///   真机不可靠（曾致三指被误判为调进度）；横向累计位移首次超过阈值即
///   一次性跳转（无分段线时左滑跳视频首、右滑跳视频尾；只跳转不改标记）；
/// - 三指跳转短提示：跳转瞬间屏幕正中显示「方向图标 + 已跳转」
///   短提示（通用文案、不带首/尾断言，跳最近分段线仍正确），约 0.6s
///   后自动淡出；纯视觉（IgnorePointer）不拦截触摸，只随跳转出现一次；
/// - 播放到结尾自动进入暂停态并弹左下角循环提示
/// - 进度拖动定格实时预览：单/双指横向进度手势自轴锁定起进入
///   scrubbing 相位——若在播先暂停，画面随拖动逐帧 seek 定格在目标帧；
///   松手恢复手势前播放态（原先在播 → play 从落点继续、原已暂停 → 保持
///   暂停）；scrubbing 预览期间不显示暂停态中央大播放图标（预览结束按
///   真实状态如实显示）；手势反馈状态控制器（idle/scrubbing/levelAdjust）
///   + IgnorePointer 浮层宿主为指示内容提供共享骨架
/// - 音量/亮度调节反馈：单指垂直滑自轴锁定起，
///   屏幕正中显示横向滑条（约屏宽 [kLevelAdjustSliderWidthFraction]，图标
///   在条左端区分太阳/喇叭、无数字，填充按当前值 0..1 从左到右实时更新），
///   松手即消失（无延迟淡出）；调节期间不暂停播放、不出现进度反馈
/// - 镜像：首次打开询问「需要镜像吗？」并给出两栏
///   依据（左「不需要镜像」/ 右「需要镜像」）、选择后立即生效（渲染层水平
///   翻转，不修改源文件字节）；镜像状态按 video_id 存于视频索引，再次打开
///   自动按历史应用并提示「已按历史应用镜像」（无需确认）
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.source,
    this.askNaming = false,
    this.scheme = const AutoSchemeOpen(),
  });

  /// 待播放视频（已复制到应用私有目录的 `file://` URI）。
  final Uri source;

  /// 首次导入的新视频：打开成功且署名解析为未署名时弹歌曲
  /// 命名框（先命名、关掉之后才问镜像）；已命名视频与遗留旧视频不弹。
  final bool askNaming;

  /// 这次打开带的方案参数：首页卡片与详情页
  /// 「打开续播」不带参数，方案区的每一行各带自己那一份。播放器内不提供
  /// 方案切换——要看另一份，退出回详情页再点。
  final SchemeOpen scheme;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage>
    with WidgetsBindingObserver
    implements OpenLoadHost {
  /// 引擎与 seek/scrub 域：播放内核的持有与
  /// 生命周期、seek 提交与拖动会话的起止都收在本域。播放页只把闭包接进去，
  /// seek 提交器与拖动会话由本域持有。
  late final EngineSeek _engineSeek;

  /// 编辑器入口编排域：入口请求、入口门禁、
  /// 画布准备、待办串联、收起与退出都收在本域。模式取值仍归播放会话模式
  /// 小库的单一 owner（本域只消费其读面与写缝）；其余跨域事实由本页经显式
  /// 闭包注入，本域不读构建上下文、不注容器。
  late final EditorEntry _editorEntry;

  /// 「进观看态」注入：组合根
  /// 把演出层装配点交来的收起把手挂进帮助域的请求注入点——引导域在推进到
  /// 三指跳转单元第二步的一帧经它请求，播放页执行（幂等；控制层未装配/
  /// 未展开时是 no-op）。闭包存字段：挂入与摘除按同一引用恒等。
  late final GuideEnterWatchingRequest _guideEnterWatching = ref.read(
    guideEnterWatchingRequestProvider,
  );

  /// 播放手势仲裁域：轴锁、突发指针锁定、取消区
  /// 语义、三指跳转、长按二倍速与取景手势分支都收在本域；识别器由本域持有，
  /// 播放页只把它的识别器与回调交给画面层手势件、把浮层专属时机经钩子转发。
  late final GestureArbitration _gestures;

  /// 上一次构建骨架时读到的画面宽高比：位置流监听据此发现
  /// 「首帧就绪、宽高比落定」并重建一次，让骨架重算重排。
  double? _skeletonAspectRatio;

  /// 最近一次 build 求得的编辑骨架：取景域宿主经它读单画面取景态的贴底
  /// 分支几何，不再自己重算一份（取景入口都在控制层内，到达调节前必经一次
  /// build）。
  EditorSkeleton? _lastSkeleton;

  /// 系统 UI/方向控制接缝（缓存：dispose 收尾用）。
  late final SystemUiController _systemUi;

  /// 相机采集接缝：对比态前置摄像头预览的开/关与权限流。
  late final CameraCaptureService _camera;

  /// 相机与练习面域：权限门与预览起停的编排归它，页面只接线。
  late final CameraStage _cameraStage;

  late final LevelControl _level;
  late final LoopPromptController _loopPrompt;
  late final PlaybackLoopLayer _loopLayer;
  late final DelayedPlayController _delayedPlay;

  /// 延迟锚值道模型（dispose 复位用；初始化于 initState）。
  DelayAnchorModel? _delayAnchorModel;

  /// 全屏单指长按 2×：长按阈值到后调
  /// [SpeedControlModel.beginTransientRate] 进入临时 2×、松开经
  /// [SpeedControlModel.endTransientRate] 恢复手势前倍速（瞬态
  /// 倍速收进倍速模型，引擎 rate 唯一写穿）。initState 缓存（dispose 收尾用）。
  late final SpeedControlModel _speedControl;

  /// 镜像状态机：首次打开询问/历史应用/按 video_id 持久化。
  late final MirrorController _mirror;

  /// 续播落盘会话：索引存取、打开路径与位置/
  /// 时长/尾线取数都收在域内；本页只在暂停 / 切后台 / 离页 / 播放完成四个
  /// 时机调一次。
  late final ResumeRecorder _resumeRecorder;

  /// 歌曲署名会话：打开解析署名现值、命名/改名双写
  /// index + markers。
  late final SongSignatureController _signature;

  /// 命名会话域：自持首次导入判定、命名/改名编排与提交路径；
  /// 对话框由本页经 [_presentNaming] 呈现（域出编排与提交、页面出对话框）。
  late final SongNamingSession _naming;

  /// 练舞统计记账会话：自持会话启动、当前是哪支舞的更新与
  /// 收尾落盘；null = 未接统计的环境零行为。
  PracticeStatsSession? _statsSession;

  /// 编辑偏好持久化会话：吸附偏好/延迟循环拍档/锁定分段随
  /// local 私密文件落盘与恢复；didChangeDependencies 创建（需容器），
  /// dispose 结束会话。
  VideoSettingsPersistence? _settingsPersistence;

  /// 打开落定标记（引擎 `open` 成功返回后置真）：打开完成前中央播放指示
  /// 一律不显示——那一刻引擎还没有可报的播放态，画出来就是「看起来暂停了、
  /// 其实还没打开」；打开失败另有 [_openFailed] 收口。
  ///
  /// **播放态本身在页面上不留副本**：中央
  /// 播放指示与控制层播放键一律直读引擎 `PlaybackEngine.isPlaying`，引擎与
  /// seek/scrub 域的播放态边沿订阅（[EngineSeek.attach]）只把边沿翻译成一次
  /// 重建（见 [_onPlayingEdge]）。
  bool _opened = false;

  /// 打开失败（源不可读等）。
  bool _openFailed = false;

  /// 倍速气泡锚点：观看态右下胶囊为 [CompositedTransformTarget]，
  /// 气泡（[SpeedBubble]）锚定其上方；开关状态统一存于
  /// [speedBubbleSessionProvider]（与编辑态控制层同一状态来源）。
  final LayerLink _speedBubbleLink = LayerLink();

  /// 节拍提示气泡锚点：观看态数拍浮层选中态左下角工具为
  /// [CompositedTransformTarget]，气泡锚定工具上方；与倍速气泡共享
  /// [speedBubbleSessionProvider] 单值互斥会话。
  final LayerLink _beatBubbleLink = LayerLink();

  /// 控制层（标注编辑外壳）是否展开——由播放会话
  /// 模式值派生（[PlayerSession.controlOpen]：观看为否，其余为是），页面
  /// 内不再有可独立写的展开位布尔。展开时为不透明命中测试的顶层覆盖层
  /// （[ControlLayer]），其命中测试阻断下层播放手势层 → 播放手势（双击
  /// 暂停、进度/音量/亮度滑动、单击唤出）在编辑态不生效（手势作用域切换）；
  /// 收起后移除覆盖层即恢复。回调面经本 getter 读现值。
  bool get _controlOpen => ref.read(playerSessionProvider).controlOpen;

  /// 手势反馈状态控制器：scrubbing 相位驱动
  /// 拖动定格预览期间暂停态大图标抑制与浮层宿主显隐。
  final GestureFeedbackController _feedback = GestureFeedbackController();

  /// 演出层会话：浮层控制器、装配句柄、选中/
  /// 混区/全局缩放状态机与三指提示都自持在它里面；本页只建会话、交给手势域
  /// 与演出层两个消费方，收尾时释放。
  late final PresentationSession _presentation;

  /// 节拍呈现对象：宿主一处构造节拍上下文、
  /// 每帧喂 `onFrame`；屏幕数拍数字与节拍动画读它的发布值，拍声也由它的
  /// 发声排程产出。
  late final BeatPresentation _beatPresentation;

  /// 节拍呈现驱动：素材变化、位置报位与前后台
  /// 事实三条重驱入口收在模块；宿主只做 provider 接线与两条会话事实上报。
  late final BeatPresentationDriver _beatDriver;

  /// scrubbing 指示浮层显示的目标位置：每次 seek 动作按钳制后
  /// 目标更新——游标/时间文本与入队 seek 同源，不读引擎实际 position
  /// （串行 latest-wins seek 期间引擎位置会滞后于目标）。
  ///
  /// 每帧 seek 不触发 setState（避免整页重建），指示内容经
  /// [ValueListenableBuilder] 订阅本通知器即时刷新。显示位由引擎与
  /// seek/scrub 域（[EngineSeek]）持有，本页只把它接进指示浮层。
  final ValueNotifier<Duration> _scrubTarget = ValueNotifier(Duration.zero);

  /// 标注保存编排器接缝（dispose 收尾用，initState 缓存：dispose 内不可
  /// 用 ref 读 provider）。null = 未接编排器，flush 零行为。打开恢复接线
  /// 在按路径取到身份后注入 per-video 实例，经下方 listenManual
  /// 同步到本缓存。
  AnnotationSaveSink? _saveSink;

  /// 保存编排器注入点的模型（dispose 收尾清空，避免跨视频残留——下一视频
  /// 未接线前编辑不得写入上一视频的文件）。
  AnnotationSaveSinkModel? _saveSinkModel;

  /// Provider 容器缓存（didChangeDependencies 取）：dispose 收尾用的节拍
  /// 分析运行器实例（dispose 内不可读 provider，缓存实例后 cancel 仅翻
  /// 代际号，无 provider 访问）。
  BeatAnalysisRunner? _beatRunner;

  /// 模式值模型缓存：dispose 收尾复位用（didChangeDependencies
  /// 缓存，dispose 内不可读 provider）。
  PlayerSessionModel? _sessionModel;

  /// 对比录制与练习片段域：录制相位与四个值道、
  /// 录制钮的起停、素材入轨、练习片段的回放都收在域内；本页只把读取事实、
  /// 写缝与宿主动作接进去。
  late final CompareRecordingClips _compareRecordingClips;

  /// 学习段循环接线域：激活范围变化到区间循环
  /// 作用域的编排（作用域起停、循环提示区间语义、激活即起播序号机、片段
  /// 循环前导取值与循环层两条事件流）都自持在它里面；本页只把 provider 变化
  /// 接到它的入口。
  late final LoopBinding _loopBinding;

  /// 录制期播放接管域（新增 seam 二）：六条纪律
  /// （播放态同步、录制期拒绝 scrub、录制期循环停用、录制态标记、学段循环
  /// 同步、scrub 会话收尾）收进本域——引擎/seek 面只读它的 [active] 事实，
  /// 对比录制面只经它施加/复位播放面纪律；两个原域各自单向依赖本域。
  /// 组装处的闭包是唯一的接线点（本域零 import、不读构建上下文）。
  late final RecordingPlaybackTakeover _takeover;

  /// dispose 收尾用的容器缓存（续播记录钳制需读尾线，dispose 内
  /// 不可用 ref 读 provider，didChangeDependencies 缓存容器实例）。
  ProviderContainer? _containerCache;

  /// 轨道带会话域：本页面创建的**唯一实例**，
  /// 经演出层输入下传给控制层、设置簇与轨道带——缩放窗口、预览线显示值、
  /// 拖动标记、编辑态微调与跨面捏合都活过控制层收起/展开（编辑态↔播放态↔
  /// 对比态↔取景态），随页面销毁（关闭这支舞 / 换下一支舞 / 重新打开）一并
  /// 失效回全片。「谁必须和谁一起传」由这一个句柄承担。
  late final TrackBandSession _trackBandSession;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _containerCache ??= ProviderScope.containerOf(context);
    _beatRunner ??= _containerCache!.read(beatAnalysisRunnerProvider);
    // 模式值模型缓存：dispose 收尾复位用（dispose 内不可读
    // provider，didChangeDependencies 缓存模型实例）。
    _sessionModel ??= _containerCache!.read(playerSessionProvider.notifier);
    _settingsPersistence ??= VideoSettingsPersistence(
      ProviderScope.containerOf(context),
    );
    // 浮层视口 seam：按当前方向注入播放页逻辑尺寸（方向/
    // 尺寸变化经 MediaQuery 依赖重建触发），控制器据此做生效尺寸上限
    // 联动视口与位置屏内钳制。钳制盒取值与模式无关（对比态与非对比态一律
    // 整屏——浮层因此可拖到屏幕上任意位置，含压在练习侧相机预览上）。
    // 姿态/尺寸变化同时重解析当前格（姿态 = 视口宽高口径，非设备传感器
    // 方向）：横屏左右两向共用一格、竖屏上下两向共用一格。视口注入与切格
    // 由演出层会话自持（[PresentationSession.applyViewport]），本页只把视口
    // 事实与当前格读好传入。
    _presentation.applyViewport(
      viewport: MediaQuery.sizeOf(context),
      landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
      compare: ref.read(playerSessionProvider).isCompare,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 演出层会话：浮层控制器在这一处建齐，此后手势域与演出层共同消费同一
    // 份；本页不再单独持有它。
    final metronome = MetronomeOverlayController();
    _presentation = PresentationSession(
      metronome: metronome,
      isControlOpen: () => _controlOpen,
      metronomeVisible: () => ref.read(beatOverlayContentVisibleProvider),
    );
    // 保存编排器接缝：注入点值随打开恢复接线变化（会话取到身份
    // 后才有 per-video 实例），监听保持缓存同步；dispose 经控制器清空。
    _saveSinkModel = ref.read(annotationSaveSinkStateProvider.notifier);
    ref.listenManual(
      annotationSaveSinkProvider,
      (_, next) => _saveSink = next,
      fireImmediately: true,
    );
    // 八拍矫正入口：非宿主发起的进入以**待办**表达——入口落
    // 待办，宿主听待办槽完成编排（画布兜底、浮层退选中）后经唯一提交入口
    // [PlayerSessionModel.commit] 提交，不成立则
    // [PlayerSessionModel.cancelPendingEntry]（模式值一位不动）。本监听只在
    // 待办从无到有（或被新待办取代）时触发——无待办
    // （含初始注册）不编排；发起路径可多、提交点唯一（宿主自身发起的单击
    // 画面走同一条编排与提交通路）。
    ref.listenManual(
      playerSessionProvider.select((session) => session.pendingEntry),
      (previous, next) {
        if (!mounted || next == null || identical(previous, next)) return;
        unawaited(_editorEntry.orchestratePendingEntry());
      },
    );
    // 方向不由模式值驱动：转屏钮一次请求即粘住——收起控制层
    // 不解除锁定、不发出任何方向请求；退出播放器由 restoreDefaultUi 落回
    // 全局竖屏锁。
    // 对比态边沿：进/出对比态分发相机预览生命周期——
    // 进入对比态开前置摄像头、离开关，与控制层展开位无关（对比-控制层内
    // 预览照常实时）。开流以已授权为前提（进入编排的相机门保证；直落对比
    // 取值的旁路路径不开未授权的流）。浮层钳制盒**不再**随此边沿重注入
    // （取值与模式无关，方向/尺寸变化仍由 didChangeDependencies 的
    // MediaQuery 依赖覆盖）。
    ref.listenManual(playerSessionProvider, (previous, next) {
      if (!mounted ||
          previous == null ||
          previous.isCompare == next.isCompare) {
        return;
      }
      // 对比会话进出 = 唯一会切「对比格 ↔ 普通格」的边沿：切格
      // 不动选中态与锁定态，生效位置与命中区随即由新格派生（控制器通知
      // 同步注册几何）。展开/收起控制层不在对比边沿上，故不切格。
      _presentation.setCell(
        landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
        compare: next.isCompare,
      );
      if (next.isCompare) {
        // 进对比态接管练习侧（片段回看恢复就位不自动播；无激活照常开实时
        // 预览）与离开对比态（录制中自动停并入库，再关相机）都由对比录制与
        // 练习片段域编排；在屏是哪一路读唯一派生（含引用有效性：片段已不在
        // 轨道时该面答预览）。
        unawaited(_compareRecordingClips.enterCompare());
      } else {
        unawaited(_compareRecordingClips.exitCompare());
      }
    });
    // 数拍浮层（经内容类声明的几何存取面）：持久化
    // 恢复接线（local → 会话态 → 控制器）与「变更即存」回写（控制器 →
    // 会话态 → VideoSettingsPersistence 落盘）都由演出层会话装配
    //（[PresentationSession.attachGeometry]）；本页只把会话态投影实现交进去。
    _presentation.attachGeometry(store: OverlayPlacementSessionStore(ref));
    // 浮层存在性 = 内容可见性：内容转为为空即退出选中态
    // （浮层不存在时不可保持选中；隐藏期间位置/缩放记忆不受影响）。
    ref.listenManual(beatOverlayContentVisibleProvider, (_, bool visible) {
      _presentation.onContentVisibilityChanged(visible);
    });
    // 引擎实例先就位（速率单一来源）：节拍上下文、延迟播放与节拍呈现都读
    // 同一只内核；引擎与 seek/scrub 域在接管域就位后由本处组装。
    final engine = ref.read(playbackEngineProvider);
    // 节拍呈现对象：发声排程在对象内（生产 seam 见 [beatPresentationProvider]）；
    // 上下文装配与重驱编排收在 [BeatPresentationDriver]——本页只接素材
    // provider 的一次聚合订阅；引擎位置报位与播放态边沿由驱动自订。
    _beatPresentation = ref.read(beatPresentationProvider);
    _beatDriver = BeatPresentationDriver(
      presentation: _beatPresentation,
      readFacts: () => ref.read(beatPresentationFactsProvider),
      readTransport: () => (rate: engine.rate, playing: engine.isPlaying),
      readPosition: () => ref.read(playbackPositionProvider).value,
    );
    unawaited(_beatPresentation.attach());
    _beatDriver.attach(engine);
    // 素材变化（provider 变化合成一条）：上下文是产品状态唯一入口，下一帧
    // 生效；暂停下锚点/半拍线变化也即时重发布。
    ref.listenManual(beatPresentationFactsProvider, (_, _) {
      _beatDriver.resync();
    });
    // 首帧就绪重排：画面宽高比由内核异步落定（media_kit 的
    // videoParams 流在 open 之后到达），而骨架在 build 里读它。基准取当前
    // 取值；后随位置报位发现宽高比落定即重建一次（见 [_onEnginePosition]）。
    _skeletonAspectRatio = engine.videoAspectRatio;

    // 延迟播放控制器须先于其它 fireImmediately 接线就位：seek 提交口与
    // 打断接线都引用它。
    // 延迟播放：双指双击/控制层按钮触发——倒回「起点
    // 前 N 拍」连续播到起点，越过起点即起播并交出延迟锚。相位来源走
    // provider 注入（占位/异常网格不产生八拍点 → 该次走兜底）；预备拍数
    // N 读设备级设置；有效区间与录制侧同一份时间线区间。
    // 延迟锚随控制器通知写入 delayAnchorProvider（数拍锚点链消费）；预备期
    // 相位写入 delayedPlayPreparingProvider（练习记账事实道）。
    _delayedPlay = DelayedPlayController(
      engine,
      phaseOf: () => ref.read(beatGridProvider).hasRealBeats
          ? ref.read(beatPhaseProvider)
          : null,
      prepBeatsOf: () => ref.read(prepBeatsProvider).delayedPlay,
      validRangeOf: () {
        final timeline = ref.read(effectiveAnnotationTimelineProvider);
        final rangeStart = timeline.rangeStart;
        final rangeEnd = timeline.rangeEnd;
        if (rangeEnd > Duration.zero) {
          return (start: rangeStart, end: rangeEnd);
        }
        final duration = engine.duration;
        return duration == null ? null : (start: rangeStart, end: duration);
      },
      gridOf: () => ref.read(beatGridProvider),
      mediaPositionOf: () => ref.read(beatCountPositionProvider),
      isTakenOverOf: () => _engineSeek.takenOver,
    );
    _delayedPlay.attachChannels(
      writeAnchor: (anchor) =>
          ref.read(delayAnchorProvider.notifier).set(anchor),
      writePreparing: (preparing) =>
          ref.read(delayedPlayPreparingProvider.notifier).set(preparing),
    );
    // 延迟锚值道模型引用（dispose 复位用，同款形状）。
    _delayAnchorModel = ref.read(delayAnchorProvider.notifier);
    // 打开编辑面即暂停：三处入口（新建即弹 / 片段
    // 选中后再单击 / 贴纸右上角）都汇到 [noteTextEditorTargetProvider] 这
    // 一条写路径，宿主在 provider 边沿统一暂停——一处实现、三处一致；位
    // 置在那一刻读取（预览线在哪、备注就落在哪）。收起后**不自动恢复**
    // 播放——与 scrub / 拖线预览那类「借一下画面就还」的会话刻意不对称：
    // 写备注是「我要停下来写字」，何时继续由用户决定。
    ref.listenManual(noteTextEditorTargetProvider, (previous, next) {
      if (next != null && engine.isPlaying) unawaited(_engineSeek.pause());
    });
    // 长按 2× 收尾（dispose 内不可用 ref）：进页即缓存倍速模型。
    _speedControl = ref.read(speedControlProvider.notifier);
    _systemUi = ref.read(systemUiControllerProvider);
    _camera = ref.read(cameraCaptureProvider);
    _resumeRecorder = ResumeRecorder(
      indexStore: ref.read(videoIndexStoreProvider),
      filePath: widget.source.toFilePath(),
      positionOf: () => _engineSeek.engine.position,
      videoDurationOf: () => _engineSeek.engine.duration,
      rangeEndOf: () {
        final timeline = _containerCache?.read(
          effectiveAnnotationTimelineProvider,
        );
        if (timeline == null || timeline.videoDuration <= Duration.zero) {
          return null;
        }
        return timeline.rangeEnd;
      },
    );
    // 相机与练习面域：权限门与预览起停的编排归本域，页面只把宿主
    // 事实（是否已在对比态、是否仍在树上、待办是否在槽、开流档、刷新回调）
    // 与权限提示 UI 交进去。此处即需就位——片段回看的初始化接线会经它开/关
    // 预览。
    _cameraStage = CameraStage(
      camera: _camera,
      isCompare: () => ref.read(playerSessionProvider).isCompare,
      isMounted: () => mounted,
      hasPendingEntry: () =>
          ref.read(playerSessionProvider).pendingEntry != null,
      resolution: () => ref.read(recordingResolutionProvider),
      onPreviewChanged: () {
        if (mounted) setState(() {});
      },
      promptDenied: _promptCameraDenied,
    );
    // 亮度/音量域：域自持初始化与写入路径，宿主只建会话。
    _level = LevelControl(
      brightnessController: ref.read(screenBrightnessControllerProvider),
      volumeController: ref.read(systemMediaVolumeControllerProvider),
    );

    // 循环提示：播放到尾左下角弹提示，延迟一个八拍后自动
    // 从头重新播放；「不循环」后本次播放会话不再自动循环。
    // 自动循环开始即一次全片循环：步进作用于全片时推进一档
    // （「不循环」后事件不再发生 → 无循环不推进）。
    _loopPrompt =
        LoopPromptController(engine, gridOf: () => ref.read(beatGridProvider))
          // 自动循环起播的 UI 重建由引擎播放态边沿承担（循环提示
          // 先 play 再回调本钩子）。
          ..onAutoLoopStarted = () {
            ref.read(speedControlProvider.notifier).onWholeVideoLoop();
          };
    _loopLayer = ref.read(playbackLoopLayerProvider);
    // 循环跳回打断延迟（打断表「任何 seek」）：段循环到
    // 尾的回跳 seek 在循环层内部发生，宿主经圈数事件获知——每圈跳回即撤
    // 锚并作废在途预备。位置跳变由节拍呈现对象按前后跳自判，回跳
    // 后循环前导不再被 seek 补发位置的回声打断。
    // 引擎与 seek/scrub 域：播放页只把闭包接进去——seek 提交口读
    // effective 派生时间线与完整清循环 helper，seek 与拖动都先打断在途延迟
    // 起播；拖动收口落点回报循环提示放行；拖动相位与显示位接给手势反馈与
    // 指示浮层；位置报位、播放态边沿与播放完成事件由本域订阅后转发，收尾
    // 先摘订阅再停播（见 dispose）。接管事实取自接管域（惰性解析：本域先于
    // 接管域就位）。
    _engineSeek = EngineSeek(
      engine: engine,
      takeoverOf: () => _takeover,
      timeline: () => ref.read(effectiveAnnotationTimelineProvider),
      clearLoops: (timeline, position) =>
          clearLoopActivationsIfOutside(ref.read, timeline, position),
      interruptPendingDelayedPlay: _delayedPlay.interrupt,
      onScrubCommitted: _loopPrompt.markManualSeek,
      feedback: _feedback,
      scrubTarget: _scrubTarget,
      onPlayingEdge: _onPlayingEdge,
      onPosition: _onEnginePosition,
      onCompleted: _resumeRecorder.save,
      isMounted: () => mounted,
    )..attach();
    // 轨道带会话域：组合根建唯一实例——
    // 引擎与时间线读取、清循环回调、控制层宽读取显式接进去；三个消费方只
    // 持这个句柄，不再各自持有窗口控制器/预览线/拖动标记/微调会话。
    _trackBandSession = TrackBandSession(
      engine: engine,
      timeline: () => ref.read(effectiveAnnotationTimelineProvider),
      clearLoops: (timeline, position) =>
          clearLoopActivationsIfOutside(ref.read, timeline, position),
      layerWidth: () => MediaQuery.sizeOf(context).width,
      onScrubCommitted: _loopPrompt.markManualSeek,
    );
    // 录制期播放接管域：六条纪律的接线点。闭包是本域触碰原域的
    // 唯一方式——录制期循环停用、退出时学段循环作用域复位（只就位、不跳
    // 段首）、循环提示的录制态标记、起录前的 scrub 会话收尾、撤在途延迟起播
    // 挂账、以及播放动作转停录。先于对比录制与练习片段域就位（后者单向依赖
    // 本域）。
    _takeover = RecordingPlaybackTakeover(
      disableRecordingLoop: _loopLayer.disableLoop,
      restoreLearningSegmentLoop: () => _loopBinding.syncLearningSegment(
        loopRangeRecord(ref.read(activeLoopRangeProvider)),
        activate: false,
        timeline: ref.read(annotationTimelineProvider),
        segmentLoopActive: ref.read(activeLoopRangeProvider) != null,
      ),
      setRecordingMarker: _loopPrompt.setRecordingActive,
      endScrubSession: () => _engineSeek.endScrub(),
      interruptPendingDelayedPlay: _delayedPlay.interrupt,
      stopRecordingSession: () => _compareRecordingClips.stop(),
    );
    _compareRecordingClips = _buildCompareRecordingClips();
    _loopBinding = LoopBinding(
      engineSeek: _engineSeek,
      loopLayer: _loopLayer,
      loopPrompt: _loopPrompt,
      delayedPlay: _delayedPlay,
      effectiveLoopWaitOf: _compareRecordingClips.effectiveLoopWait,
      delayedLoopWaitOf: () => ref.read(delayedLoopWaitProvider),
      isMounted: () => mounted,
      onDelayedLoopActive: () => _beatDriver.resync(),
    )..attach();
    // 编辑器入口编排域：模式取值 owner 直接交给本域消费；装载门、
    // 录制接管事实、校准会话、相机授权门、引擎时长、时间线复位与浮层退选中
    // 都经显式闭包注入。此处就位（早于任何手势/待办事件），待办监听旋即经它
    // 编排。
    _editorEntry = EditorEntry(
      session: ref.read(playerSessionProvider.notifier),
      readSession: () => ref.read(playerSessionProvider),
      blocksWrite: () => loadGateBlocksWrite(ref, PageWriteEntryId.editorEntry),
      takenOver: () => _engineSeek.takenOver,
      avSyncActive: () => ref.read(avSyncCalibrationSessionProvider).active,
      requestCameraPermission: () => _cameraStage.requestEntryPermission(),
      readTimeline: () => ref.read(annotationTimelineProvider),
      readVideoDuration: () => _engineSeek.engine.duration,
      resetTimeline: (duration) =>
          ref.read(annotationEditorProvider).resetForVideo(duration),
      clearExclusiveSelections: _presentation.clearExclusiveSelections,
      isMounted: () => mounted,
    );
    // 「进观看态」注入：闭包就位后即可被引导域请求；dispose 摘除。
    _guideEnterWatching.attach(_presentation.collapseControlLayer);
    // 片段激活回看：激活 = 停摄像头（回看期间不录"站着不动看
    // 回放"）+ 练习侧切片段回放画面（第二播放源按截取范围循环）+ 前导
    // 归零；退出激活 = 回放退场 + 恢复实时预览（仍在对比态时）。触发条件
    // = 播放源变化（在屏派生含引用有效性）：解析不到即停播回落。
    // fireImmediately：打开恢复先于/后于本接线就位都要同步（恢复不自动
    // 跳转、不自动播放——就位回放但不 seek、不播）。
    ref.listenManual(practiceOnscreenFaceProvider, (previous, next) {
      if (!mounted || previous == next) return;
      _loopBinding.syncClipLoopWait();
      _compareRecordingClips.syncClipPlayback();
    }, fireImmediately: true);
    // 单一循环范围：临时衔接段优先、否则真实学习段合并范围——
    // 两类激活互斥，区间循环接线（enableLoop + 队首 seek）只看本来源。
    // 恢复应用期间只就位循环作用域、不执行「跳段首」seek。
    ref.listenManual(
      activeLoopRangeProvider,
      (_, next) => _loopBinding.syncLearningSegment(
        loopRangeRecord(next),
        activate: !restoreQuietLoopWrite(ref),
        timeline: ref.read(annotationTimelineProvider),
        segmentLoopActive: next != null,
      ),
      fireImmediately: true,
    );
    // 循环前导：前导是否生效 = 胶囊拍数（不延迟 = 0 = 关，
    // 无面板独立开关），拍数 × 拍时长写入区间循环层——每圈到段尾 seek
    // 段首−前导拍数连续播放；不延迟 → 立即回段首且不影响节拍器。设置
    // 变化即时生效。与整片「循环提示」八拍延迟完全隔离。
    ref.listenManual(
      delayedLoopWaitProvider,
      (_, _) => _loopBinding.syncClipLoopWait(),
      fireImmediately: true,
    );
    // 循环前导：前导激活随段首重同步当拍一声，此后前导
    // 声由播放位置推进驱动（无独立自由计时器）；前导激活期间节拍器静默；
    // 结束/打断清锚（前导 = 位置在锚点之前，由节拍呈现按发布值
    // 同一条派生自判）。异常态（无节拍网格）与暂停不发声。
    ref.listenManual(
      annotationTimelineProvider,
      (_, next) => _loopPrompt.syncToTimeline(
        next,
        segmentLoopActive: ref.read(activeLoopRangeProvider) != null,
      ),
      fireImmediately: true,
    );

    // 镜像：打开成功后按视频路径查索引——首次打开询问、
    // 再次打开自动应用历史并提示；镜像为渲染层翻转（不改源文件字节）。
    // 控制器同时管**全局镜像**与**局部镜像总开关**（逐点相同的落盘
    // 通路）——两个开关都按 videoId 取协调器读写 markers，总开关的每次取值
    // 经写缝推给会话值道（渲染翻转门与顶栏槽位琥珀都只读该值道，不读文件）。
    _mirror = MirrorController(
      ref.read(videoIndexStoreProvider),
      coordinatorFor: (videoId) =>
          ref.read(videoDocumentCoordinatorProvider(videoId)),
      onLocalMirrorEnabledChanged: (value) =>
          ref.read(localMirrorEnabledProvider.notifier).replace(value),
      // 只读公开标记文件上的写回被挡：沿既有短暂提示通道当面说明。
      onWriteRejected: _showDocumentReadOnly,
    );

    // 歌曲署名：打开解析现值（markers 真值优先并回写
    // index 缓存）；命名/改名经同一控制器双写 index + markers。
    _signature = SongSignatureController(
      ref.read(videoIndexStoreProvider),
      coordinatorFor: (videoId) =>
          ref.read(videoDocumentCoordinatorProvider(videoId)),
      onWriteRejected: _showDocumentReadOnly,
    );
    // 改名成功即补一次推送同步：顶栏改名走同一条署名提交信号，
    // 已排的系统通知标题随新名差分重排。导入命名也发信号，无 DDL 时同步
    // 为空操作。
    _signature.addCommitListener(
      (_) => unawaited(ref.read(planPushSyncProvider)()),
    );

    // 练舞统计记账会话：域自持会话启动、当前是哪支舞的更新
    // 与收尾；videoId/署名解析后与署名变化时由会话跟随署名域同步（未署名
    // 按文件名回退在记录器内处理）。练习素材库同读该 videoId 会话值。
    _statsSession = PracticeStatsSession(
      recorder: ref.read(practiceStatsRecorderProvider),
      signatureController: _signature,
      fallbackName: () => _fallbackSongName,
      statsStore: ref.read(practiceStatsStoreProvider),
      bucketStore: ref.read(fourBeatBucketStoreProvider),
      onVideoIdChanged: (videoId) =>
          ref.read(currentVideoIdProvider.notifier).set(videoId),
    );

    // 命名会话域：域自持首次导入判定、命名/改名编排与提交；
    // 提交落盘后署名域自己发出提交通知，统计域订阅它做署名快照迁移
    // （单向：统计域 → 署名域，命名域不经宿主回调绕行跨域写-through）。
    _naming = SongNamingSession(
      signatureController: _signature,
      fallbackName: () => _fallbackSongName,
      presentNaming: _presentNaming,
    );

    // 值道复位（keepAlive 会话值 = 一个复位方法 + 两个触发
    // 点——本页面就位（含换视频后重开）与离开播放页各一次）：上一会话若在
    // **准备期中**离开，dispose 已先摘监听再停止会话（见 dispose），相位与
    // 可视数拍就停在离开那一刻——不复位的话下次打开时数拍浮层还挂着上一
    // 会话的第 0 个八拍顺数。
    _compareRecordingClips.resetValueChannels();
    unawaited(
      ref
          .read(recordingResolutionProvider.notifier)
          .restore(ref.read(privateJsonStorageProvider)),
    );

    // 所在层改动打断延迟（打断表）：离开观看态即撤锚并作废在途预备；
    // 收起控制层（回观看态）不在此列——编辑态点延迟钮 = 先收起后触发，
    // 收起在触发之前。interrupt 对 idle 是 no-op，多火无害。
    ref.listenManual(playerSessionProvider, (previous, next) {
      if (next.mode != PlayerSessionMode.watching) _delayedPlay.interrupt();
    });

    _gestures = _buildGestureArbitration();

    _systemUi.enterPlayerMode();
    _level.start();
    // 打开序列改 provider（开舞装载写穿引擎等），不得落在 initState 的
    // build 期：让出一次微任务，首次 build 完成后再启动。
    unawaited(Future.microtask(_open));
  }

  /// 组装对比录制与练习片段域：录制相位与四个值道、录制钮的起停、
  /// 素材入轨、练习片段的回放都收在域内；此处把读取闭包、写缝与宿主动作一次
  /// 给全（组合根的第五项职责：组装层域）。
  CompareRecordingClips _buildCompareRecordingClips() {
    return CompareRecordingClips(
      engine: _engineSeek.engine,
      camera: _camera,
      cameraStage: _cameraStage,
      takeover: _takeover,
      recordingEnv: CallbackCompareRecordingEnv(
        // 录制准备拍数读设备级设置（`prepBeats` 键，详细设置页落盘），
        // 不读随舞私密 prefs 段；读取面实时生效——
        // 每次按下录制即取当前值。
        resolvePrepBeatsOf: () async => ref.read(prepBeatsProvider).recording,
        // 准备拍序列与拒录阈值的唯一来源（非空）：**占位态照传占位均匀
        // 网格**——口径裁决：占位（节拍分析
        // 未就绪）沿用既有语义「占位即均匀节奏来源」，分析中按下录制仍得到
        // 120bpm 的准备拍前导与数字；异常态传秒制兜底网格，判据（无数字、
        // 无声、秒制兜底前导）由纯函数读性质自行落定，「无网格」不编码
        // 成空值。
        beatGridOf: () => ref.read(beatGridProvider),
        // 起录点吸附的相位来源：与延迟播放同一取法——
        // 就绪网格才产生八拍点（含八拍锚点重定相），占位/异常网格传 null
        // = 起录点保持按下位置原样（既有口径）。
        phaseOf: () => ref.read(beatGridProvider).hasRealBeats
            ? ref.read(beatPhaseProvider)
            : null,
        rangeStartOf: () => ref.read(annotationTimelineProvider).rangeStart,
        rangeEndOf: () {
          final rangeEnd = ref.read(annotationTimelineProvider).rangeEnd;
          if (rangeEnd > Duration.zero) return rangeEnd;
          return _engineSeek.engine.duration ?? Duration.zero;
        },
        activeLoopRangeOf: () =>
            loopRangeRecord(ref.read(activeLoopRangeProvider)),
        videoIdOf: () => _signature.videoId,
        orientationOf: () =>
            MediaQuery.orientationOf(context) == Orientation.portrait
            ? RecordingOrientation.portrait
            : RecordingOrientation.landscape,
        // 设备事实的读取点（画面方向基线项）：武装落定那一刻现读一次，此后本
        // 会话只读那份冻结值。键的启动恢复在页面首帧即发起（一次
        // 小文件读），远早于武装入口可达，故这里读到的是已落定的取值。
        surfaceBaselinesOf: () => ref.read(liveSurfaceBaselinesProvider),
      ),
      channels: NotifierCompareRecordingChannels(
        phase: ref.read(compareRecordingPhaseProvider.notifier),
        prepBeat: ref.read(recordingPrepBeatProvider.notifier),
        recordingStart: ref.read(compareRecordingStartProvider.notifier),
        armedBaselines: ref.read(armedSurfaceBaselinesProvider.notifier),
      ),
      clipsEnv: CallbackCompareClipsEnv(
        reviewClipOf: () {
          final active = ref.read(practiceClipActivationProvider);
          if (active == null ||
              ref.read(practiceOnscreenFaceProvider) !=
                  SurfaceFace.clipPlayback) {
            return null;
          }
          return practiceClipById(
            ref.read(practiceClipsProvider),
            active.clipId,
          );
        },
        activeClipIdOf: () => ref.read(practiceClipActivationProvider)?.clipId,
        clipPlaybackOnscreenOf: () =>
            ref.read(practiceOnscreenFaceProvider) == SurfaceFace.clipPlayback,
        restoreQuietWriteOf: () => restoreQuietLoopWrite(ref),
        isCompareOf: () => ref.read(playerSessionProvider).isCompare,
        isMountedOf: () => mounted,
      ),
      resolveOutputFile: () {
        final videoId = _signature.videoId;
        if (videoId == null) {
          throw StateError('videoId 未解析：素材不能脱离所属舞入库');
        }
        return ref.read(materialRecordingFileResolverProvider)(videoId);
      },
      readManifestOf: () async {
        final container = _containerCache;
        if (container == null) throw StateError('容器不可用');
        return container.read(materialManifestStoreProvider).read();
      },
      baseDirectoryOf: () async {
        final container = _containerCache;
        if (container == null) throw StateError('容器不可用');
        return container.read(materialsBaseDirectoryProvider)();
      },
      host: CallbackCompareRecordingClipsHost(
        addClipFromMaterialOf: (record, preambleMs) {
          final container = _containerCache;
          if (container == null) return;
          container
              .read(practiceClipsProvider.notifier)
              .addFromMaterial(record, preambleMs: preambleMs);
        },
        appendMaterialOf: (record) async {
          final container = _containerCache;
          if (container == null) return;
          await container.read(materialManifestStoreProvider).append(record);
        },
        createClipPlaybackOf: () => PracticeClipPlaybackController(
          engine: ref.read(practiceClipEngineProvider),
          resolveSource: _compareRecordingClips.resolveClipSource,
        ),
        blocksRecordingWriteOf: () =>
            loadGateBlocksWrite(ref, PageWriteEntryId.recording),
        endTransientRateOf: _speedControl.endTransientRate,
        showRejectedPromptOf: () => ref
            .read(
              noticeTriggerProvider(NoticeId.compareRecordRejected).notifier,
            )
            .show(),
        exitClipReviewOf: () => exitPracticeClipReview(ref),
      ),
    );
  }

  /// scrub 取消区的画面矩形（**唯一求解点**）：
  /// 组合根解一次，手势仲裁域（取消区圆心/半径）与浮层标记经现读闭包吃同一
  /// 份答案。对比态取源侧半区画面矩形（与取景渲染共用的
  /// [compareFramingPictureRect]）；观看态走整屏 contain 居中（宽高比未知时
  /// 退化为系统栏内的屏幕可用区）；编辑态微调不走本路径。
  ///
  /// 取景生效时改取**取景后的画面矩形**；取景态内画面显示整帧，故
  /// 取景态按未取景；未调过即未取景的画面矩形。
  Rect _scrubPictureRect() {
    final media = MediaQuery.of(context);
    // 取景读数：取景态内画面显示整帧，读数按未取景；退出后按选区。
    final selection = _framingActive
        ? null
        : ref.read(framingStateProvider).source;
    if (ref.read(playerSessionProvider).isCompare) {
      return compareFramingPictureRect(
        screen: media.size,
        landscape: media.orientation == Orientation.landscape,
        aspectRatio: _engineSeek.engine.videoAspectRatio,
        selection: selection,
      );
    }
    final framed = singlePictureFramedPictureRectOnScreen(
      screen: media.size,
      systemTopInset: media.padding.top,
      skeleton: null,
      aspectRatio: _engineSeek.engine.videoAspectRatio,
      selection: selection,
    );
    if (framed != null) return framed;
    return videoPictureRect(
      screen: media.size,
      systemTopInset: media.padding.top,
      videoAspectRatio: _engineSeek.engine.videoAspectRatio,
    );
  }

  /// 组装播放手势仲裁域：识别器与整个仲裁会话由本域持有；此处按层
  /// 域入口形状（一个显式的输入值对象）把五个目标域句柄与跨域事实一次给全。
  GestureArbitration _buildGestureArbitration() {
    return GestureArbitration(
      input: GestureArbitrationInput(
        engineSeek: _engineSeek,
        level: _level,
        framing: _framing,
        editorEntry: _editorEntry,
        takeover: _takeover,
        feedback: _feedback,
        isFramingActive: () => _framingActive,
        isControlOpen: () => _controlOpen,
        isMounted: () => mounted,
        viewportSize: () => MediaQuery.sizeOf(context),
        pictureRect: _scrubPictureRect,
        // 系统手势让路：现读系统上报的
        // 手势内缩，经几何纯件按每边 max(上报值, 固定下限) 求值——转屏与
        // 窗口变化后按新值重算。
        yieldSystemInsets: () => systemGestureYieldInsets(
          system: MediaQuery.systemGestureInsetsOf(context),
        ),
        readTimeline: () => ref.read(effectiveAnnotationTimelineProvider),
        beginTransientRate: () =>
            _speedControl.beginTransientRate(kLongPressDoubleSpeedRate),
        endTransientRate: () => _speedControl.endTransientRate(),
        onDoubleTap: _togglePlayPause,
        onTwoFingerDoubleTap: _delayedPlay.triggerNow,
        writeThreeFingerDirection: (direction) {
          ref.read(threeFingerToastDirectionProvider.notifier).write(direction);
          // 三指跳转做到过：提示触发（方向写面被调）即记入判据
          // 闩——引导域只读它，不要求滑的是刚标记的那条线。
          ref
              .read(guideSessionProvider.notifier)
              .latch(HandsOnCriterion.threeFingerJumpPerformed);
        },
        showNotice: (id) => ref.read(noticeTriggerProvider(id).notifier).show(),
        presentation: _presentation,
      ),
    );
  }

  Future<void> _open() async {
    // 微任务延迟启动：页面可能在首次 build 前就被销毁，先落宿主存活门。
    if (!mounted) return;
    // 换视频/重开打断延迟（打断表）：撤锚并作废在途预备。
    _delayedPlay.interrupt();
    // 「装载未完成」门的开合归打开恢复自己持有（见
    // `open_restore.dart`）：建立前置位、打开恢复落定即落位；无实体文件
    // 不置位。本页只读门事实（写入口置灰、点一下弹「正在装载」），不管开合。
    //
    // 开舞装载前置半段：开播前先把引擎写回出厂原速、步进归零，
    // 上一支舞的速率不带进下一支舞的第一遍；读回本地文档后再精调成这支舞
    // 的记忆值（`VideoSettingsPersistence._restore`）。次序（前置 → 引擎 open
    // → 恢复会话）收在打开恢复域，本页只按序调用。
    try {
      await ref.read(videoOpenRestorerProvider).prepareForOpen();
      if (!mounted) return;
      await _engineSeek.open(widget.source, play: true);
      if (!mounted) return;
      final duration = _engineSeek.engine.duration;
      if (duration != null) {
        ref.read(annotationEditorProvider).resetForVideo(duration);
      }
      // 打开落定：此前的帧引擎还没有可报的播放态，中央播放
      // 指示一律不画；此后按引擎真实播放态显示（起播边沿另触发重建）。
      setState(() => _opened = true);
      // 启动序列：打开会话建立、按装载表逐行恢复与偏好/统计/
      // 署名/命名/镜像几段域会话的启动都收在打开恢复模块的 open 里；本页
      // 只调一次，域会话由组合根构造、经 OpenLoadHost 接缝按序启动。
      await ref
          .read(videoOpenRestorerProvider)
          .open(
            source: widget.source,
            videoDuration: duration ?? Duration.zero,
            askNaming: widget.askNaming,
            scheme: widget.scheme,
            host: this,
          );
    } on Object {
      if (!mounted) return;
      setState(() => _openFailed = true);
    }
  }

  /// 打开装载宿主接缝：不属于打开恢复、但按装载表次序排在恢复
  /// 之后的几段域会话启动；会话由组合根构造，打开恢复模块按序调用。
  @override
  bool isMounted() => mounted;

  @override
  Future<void> openSettings(OpenSession session) async {
    // 编辑偏好：按会话身份恢复 local 偏好并开始「变更即存」。
    await _settingsPersistence?.openFor(session);
  }

  @override
  void startStats() {
    // 统计会话启动在署名解析前：复用同一引擎重开视频时，解析窗口内的播放
    // 不得记到上一个视频名下。
    _statsSession?.start();
  }

  @override
  Future<void> startSignature(OpenSession session) => _signature.startForFile(
    session.filePath,
    videoId: session.videoId,
    entry: session.entry,
  );

  @override
  void syncStatsVideoContext() => _statsSession?.syncVideoContext();

  @override
  Future<void> promptNaming({required bool isNewImport}) =>
      _naming.promptImportIfNeeded(isNewImport: isNewImport);

  @override
  Future<void> resolveMirror(OpenSession session) =>
      _mirror.resolveFor(session);

  Future<void> _togglePlayPause() async {
    // 录制期（含准备期）双击 = **停录**：与录制钮同一个动作——准备期 =
    // 取消并丢弃已武装的那段，录制中 = 停录入库。双击不是播放语义：录制不
    // 跟停（自动停是一次性墙钟、起录那一刻已退订位置流），若当播放放行，
    // 素材照录满而声明的源区间比实际内容多出被暂停的那一段。播放态同步：
    // 接管期内的播放动作由接管域转成停录请求。
    if (_engineSeek.takenOver) {
      await _takeover.handlePlaybackToggle();
      return;
    }
    // 「其它操作即清除」：播放控制不针对选中线。
    // 清除写点直连选中域。
    ref.read(annotationSelectionDomainProvider).clear();
    // 单一真源：按引擎真实播放态取反，翻过来的那一刻引擎自己
    // 发出播放态边沿、UI 随之重建。
    if (_engineSeek.engine.isPlaying) {
      await _engineSeek.pause();
      // 暂停即记录续播位置：杀进程后可从暂停处续播。
      await _resumeRecorder.save();
    } else {
      //  越尾线加固：播放头在尾线右侧时从原地起播；显式手动拖右带
      // 放行标记则放行到片尾，无标记（续播/边界改写残留）由
      // LoopPromptController 按到尾语义钳回尾线并提示。
      await _engineSeek.play();
    }
  }

  // 首/尾线按下即拖：写入经标注编辑模块拖动会话
  // （beginRangeDrag→moveTo→end）在轨道带内收口；复位亦统一走模块，播放页
  // 没有手写复位编排与散点写路径。控制层直接经标注编辑模块提交。

  /// 播放页的「文件名回落名」读面：本页凡把视频文件名当**名字**用的地方
  /// （未署名顶栏标题、命名框回退文本与改名初值、练舞统计记账回落名）都取
  /// 它——打开 source 路径末段经 [songFallbackName] 去扩展名（无法取得路径末
  /// 段时用占位「视频」）。把文件名当**文件**用的地方（快速键、私有副本取
  /// 唯一名）不读这里，仍吃原始文件名。
  String get _fallbackSongName {
    final segments = widget.source.pathSegments;
    final last = segments.isEmpty ? '' : segments.last;
    return songFallbackName(last.isEmpty ? '视频' : last);
  }

  /// 命名对话框呈现（「域出编排与提交、页面出对话框」接线）：
  /// 命名会话域交来场景、初值、回退名（「文件名回落名」）与是否可点框外收起，
  /// 本页负责按构建上下文弹出 [SongNamingDialog]（场景原样透传，不反推）并交回
  /// 用户结论；页面已卸载时交回 null（不提交）。
  Future<SongNamingResult?> _presentNaming({
    required SongNamingScene scene,
    required SongNamingInitial initial,
    required String fallbackName,
    required bool barrierDismissible,
  }) async {
    if (!mounted) return null;
    final result = await showDialog<SongNamingResult>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (_) => SongNamingDialog(
        scene: scene,
        initialSong: initial.song,
        initialDancer: initial.dancer,
        initialRemark: initial.remark,
        fallbackText: fallbackName,
      ),
    );
    if (!mounted) return null;
    return result;
  }

  /// 相机权限被拒提示：拒绝（可重试）与永久拒绝（去系统设置）各给一条
  /// 路径。「去系统设置」即结束本次进入编排（关闭对话框、待办取消）——
  /// 不在跳设置返回的瞬间重问（应用尚在回前台途中，重问时机不可靠）；
  /// 用户在系统设置授权后回来再点「对比练习」，相机门按已授权放行。
  Future<bool> _promptCameraDenied(CameraPermissionStatus status) async {
    final permanent = status == CameraPermissionStatus.permanentlyDenied;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('camera_permission_dialog'),
        title: const Text('无法打开相机'),
        content: Text(
          permanent ? '相机权限已被永久拒绝，请前往系统设置开启后再试。' : '未获相机权限，无法进入对比练习；可重试授权。',
        ),
        actions: [
          TextButton(
            key: const Key('camera_permission_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          if (permanent)
            TextButton(
              key: const Key('camera_permission_open_settings'),
              onPressed: () async {
                await _camera.openSystemSettings();
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop(false);
                }
              },
              child: const Text('去系统设置'),
            )
          else
            TextButton(
              key: const Key('camera_permission_retry'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('重试'),
            ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 引擎位置报位（引擎与 seek/scrub 域 [EngineSeek.attach] 的转发）：页面级
  /// 只做一件事——画面宽高比由内核异步落定后重排一次骨架；宽高比变了才
  /// 重建（位置每帧推进不触发整页重建）。节拍重驱由 [BeatPresentationDriver]
  /// 自订位置流。
  void _onEnginePosition() {
    final ratio = _engineSeek.engine.videoAspectRatio;
    if (ratio == _skeletonAspectRatio) return;
    _skeletonAspectRatio = ratio;
    if (mounted) setState(() {});
  }

  /// 引擎播放态边沿（单一真源的重建信号）：触发一次重建——指示的可见条件
  /// 与控制层播放键都直读引擎，页面不留播放态副本，因此「引擎变了」＝
  /// 「重建一次」就是全部接线。
  ///
  /// [mounted] 守卫外还有 dispose 次序保证：离页收尾先取消本订阅再 pause
  /// 引擎（见 dispose），不会在元素已 defunct 时再进重建。
  void _onPlayingEdge(bool playing) {
    // 页面级只做一次重建：节拍重驱、延迟打断、片段回放同步都已由各域自订
    // 引擎播放态边沿（见各自 attach/构造），页面不再转发。
    if (mounted) setState(() {});
  }

  /// 取景域宿主会话：取景调节态内「进入（取基准）
  /// → 调节（平移/缩放）→ 退出（清会话）」的编排由模块自持，本页只做取值
  /// 接线——视口事实按当前 `MediaQuery` 读好传入，会话态读写交给显式回调。
  late final FramingSessionHost _framing = FramingSessionHost(
    readViewport: () {
      final session = ref.read(playerSessionProvider);
      final single = session.mode == PlayerSessionMode.framing;
      final media = MediaQuery.of(context);
      return FramingViewport(
        size: media.size,
        landscape: media.orientation == Orientation.landscape,
        sourceAspectRatio: _engineSeek.engine.videoAspectRatio,
        // 单画面路径：基线 = contain 画面矩形，
        // 竖屏编辑态贴底分支为贴底画面带（骨架随取景态保留）。
        singlePicture: single,
        editingSkeleton: single ? _lastSkeleton : null,
        systemTopInset: media.padding.top,
      );
    },
    isActive: () => _framingActive,
    readCommitted: () => ref.read(framingStateProvider),
    applySource: (selection) =>
        ref.read(framingStateProvider.notifier).applySource(selection),
    // 退出三路之三（点画面外）：对比路径回对比-控制层、单画面路径回编辑态
    // （分派归宿主入口域）。
    exitFraming: _editorEntry.exitFraming,
  );

  /// 取景调节态谓词：取「模式 → 界面」声明表（唯一映射，不在此另写
  /// 取值分支）。
  bool get _framingActive =>
      sessionModeSurfacesOf(ref.read(playerSessionProvider).mode).framingActive;

  /// 切后台强制 flush 标注保存：挂起 burst 不等到期窗口；
  /// 未接编排器（null sink）时零行为。写失败由编排器静默兜底。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // 显式停声（+）：退后台 = 不应活（应活门控含应用
      // 前台），下一帧 onFrame 收口 flush + 停流，口径与暂停一致。会话
      // 事实上报给节拍呈现驱动（播放态合成的一路）。
      _beatDriver.setAppPaused(true);
      unawaited(_saveSink?.flush());
      // 练舞统计：切后台由统计域会话结算开放缓冲并落盘。
      unawaited(_statsSession?.settle());
      // 切后台记录续播位置：后台被杀可从当前处续播。
      unawaited(_resumeRecorder.save());
      // 校准会话：退后台 = 等同取消（丢弃试听值并退出会话）。
      unawaited(ref.read(avSyncCalibrationSessionProvider.notifier).cancel());
      // 延迟播放（打断表）：退后台即打断——撤锚并作废
      // 在途预备（引擎若在预备/延迟播中，其停沿亦会触发同一打断，此处为
      // 显式收口，不依赖内核的退后台停播行为）。
      _delayedPlay.interrupt();
      // 对比-录制：退后台自动停止录制并正常入库，再关相机。
      unawaited(_compareRecordingClips.stop());
      // 相机：退后台即关前置摄像头。
      unawaited(_cameraStage.closePreview());
    } else if (state == AppLifecycleState.resumed) {
      // 回前台：解除不应活，下一帧 onFrame 按引擎真实播放态重开流。
      _beatDriver.setAppPaused(false);
      // 相机：回前台若仍处对比态则恢复预览。
      if (ref.read(playerSessionProvider).isCompare) {
        unawaited(_cameraStage.openPreview());
      }
    }
  }

  /// 按视频文档只读、写回被挡时的呈现（既有短暂提示通道）。
  void _showDocumentReadOnly() => ref
      .read(noticeTriggerProvider(NoticeId.documentReadOnly).notifier)
      .show();

  /// provider 写入不允许发生在 widget 生命周期内：推迟到树收尾后的微任务；
  /// 容器已随应用/测试收尾销毁时写入会抛，静默跳过（复位本就无事可做）。
  void _deferProviderReset(void Function() reset) {
    scheduleMicrotask(() {
      try {
        reset();
      } on Exception {
        // 容器已销毁：无需复位。
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 「进观看态」闭包随页面摘除：页面不在场后引导域的请求为
    // no-op（注入点动作缺席）。
    _guideEnterWatching.detach(_presentation.collapseControlLayer);
    // 离开播放器强制 flush 标注保存（同切后台语义）。
    unawaited(_saveSink?.flush());
    // 离开播放器关相机：对比态离开页面即释放前置摄像头。
    unawaited(_cameraStage.closePreview());
    // 取消在途节拍分析（离开页面中断不写半截）。运行器实例在
    // didChangeDependencies 缓存（dispose 内不可读 provider）；cancel 只
    // 翻代际号，无 provider 访问。
    _beatRunner?.cancel();
    final sinkModel = _saveSinkModel;
    _saveSinkModel = null;
    if (sinkModel != null) _deferProviderReset(() => sinkModel.set(null));
    // 离开播放器记录续播位置：下次打开从此处续播（到尾
    // 视为从头）；写失败静默。
    unawaited(_resumeRecorder.save());
    // 模式值复位：展开位由页面内布尔迁入常驻模式值后，「离开
    // 播放页即退出模式」由复位承载——页面内布尔随页面消亡的既有寿命在此
    // 对齐（复位幂等）。
    final sessionModel = _sessionModel;
    if (sessionModel != null) _deferProviderReset(sessionModel.reset);
    // 引擎流订阅先退订：下面那次 pause 会发一条转停沿，而此刻元素已在
    // 收尾（State.mounted 仍真但已 defunct）——先 detach，收尾路径就不可能
    // 再走 [_onPlayingEdge] 的重建。
    _engineSeek.detach();
    _loopBinding.dispose();
    // 延迟播放收尾必须先于引擎 pause：控制器自订引擎转停沿，pause 的落停沿
    // 若在 dispose 前到达会经值道写面写 provider（widget 生命周期内改
    // provider 的禁令），先收流再停播。锚值道随复位微任务清空。
    _delayedPlay.dispose();
    final delayAnchorModel = _delayAnchorModel;
    if (delayAnchorModel != null) {
      _deferProviderReset(() => delayAnchorModel.set(null));
    }
    // 离开播放页后停止播放；引擎随 ProviderScope 存活，供再次打开复用。
    _engineSeek.pause();
    // 对比录制与练习片段域：离开页面先摘相位监听、复位值道
    // （离开播放页这一触发点），再停录制并释放回放控制器。
    _compareRecordingClips.dispose();
    // 练舞统计：退出播放器经会话结算开放缓冲并落盘（含暂停
    // 边沿在途结算——settleAndFlush 等边沿链排空后再 flush）。
    unawaited(_statsSession?.settle());
    _level.dispose();
    // 节拍呈现对象收流：flush + 停流，不依赖
    // dispose 时序；provider 侧 dispose 亦收口，幂等。驱动先收尾，
    // 在途重驱微任务不再读已失效的宿主读面。
    _beatDriver.dispose();
    unawaited(_beatPresentation.detach());
    _loopPrompt.dispose();
    _mirror.dispose();
    _statsSession?.dispose();
    _signature.dispose();
    _settingsPersistence?.dispose();
    _gestures.dispose();
    // 离开页收尾：若 2× 覆盖尚在生效（指针被系统取消等），恢复手势前倍速，
    // 避免引擎滞留 2×（end 幂等，未生效时无副作用）。
    unawaited(_speedControl.endTransientRate());
    _feedback.dispose();
    _presentation.dispose();
    _scrubTarget.dispose();
    _trackBandSession.dispose();
    // 恢复系统 UI（退出沉浸模式）并落回全局竖屏锁（首页等后续页面一律竖屏）。
    _systemUi.restoreDefaultUi();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 模式值一次读取派生三个面：控制层展开位、
    // 对比-播放态、取景调节态。
    final session = ref.watch(playerSessionProvider);
    final controlOpen = session.controlOpen;
    // 模式 → 界面三处换装（底排槽集 / 轨道行集 / 取景态谓词）取同一份声明表：
    // 取景调节态（对比分屏 + 单画面）两值共用同一套「控制层收起、手势独占、
    // 取景条」的面。
    final surfaces = sessionModeSurfacesOf(session.mode);
    final framingActive = surfaces.framingActive;
    final compareWatching = session.mode == PlayerSessionMode.compareWatching;
    // 回看中的练习片段（画面常驻出口件的出现条件）：build 期 watch——不
    // 用 read，避免在 build 里强制刷新被失效的 provider（与调度器同帧刷新
    // 相撞）。引用悬空（激活在、片段已被移出轨道）= 无可退出的回看。
    final reviewingClipId = ref.watch(practiceClipActivationProvider)?.clipId;
    final reviewingClip = reviewingClipId == null
        ? null
        : practiceClipById(ref.watch(practiceClipsProvider), reviewingClipId);
    // 模式 → 轨道行集：骨架（整带高）与控制层（行集）消费同一份取值。具名
    // 行集是该态的**全行集**，紧凑档下再由本处按「两轨当前空否」剪裁
    // （见 [_rowTableForTier]）。
    final fullRowTable = surfaces.rowTable;
    // 竖屏编辑骨架：方向判定与骨架分配都收成具名纯件
    // （`editor_skeleton.dart`），视频带落位与控制层消费同一份答案；取景域
    // 宿主也读本处缓存的 [_lastSkeleton]。宽高比未知时纯件按「剩余区够用」
    // 处理；就绪后由位置流监听触发一次重建，同式重算。
    //
    // 落位按选区内容宽高比：取景态内画面显示
    // 整帧，故取景态的骨架仍按源画面宽高比。
    final media = MediaQuery.of(context);
    final screen = Size(
      media.size.width,
      media.size.height - media.padding.top - media.padding.bottom,
    );
    // 档位判定：本帧只在此求值一次（阈值算术的唯一函数 [editorIsCompact]），
    // 结果转交骨架透出——轨道带剪裁、顶栏行集与气泡锚点三处读同一份
    // （[EditorSkeleton.compact]）。只看屏尺寸、不吃字号档，视口一变
    // （小窗/分屏/转屏）即随这次布局重算。
    final compact = editorIsCompact(screen);
    final rowTable = _rowTableForTier(
      full: fullRowTable,
      compact: compact,
      loading: ref.watch(loadGateActiveProvider),
      // 只订阅「空否」这一个派生位：行集只随它与档位变，逐条编辑不重建整页。
      notesEmpty: ref.watch(
        noteStickersProvider.select((notes) => notes.isEmpty),
      ),
      mirrorEmpty: ref.watch(
        localMirrorFragmentsProvider.select((fragments) => fragments.isEmpty),
      ),
    );
    final sourceAspectRatio = _engineSeek.engine.videoAspectRatio;
    final framingSelection = framingActive
        ? null
        : ref.watch(framingStateProvider.select((s) => s.source));
    final framingAspectRatio =
        framingSelection != null &&
            sourceAspectRatio != null &&
            sourceAspectRatio > 0
        ? framingSelection.contentAspectRatio(sourceAspectRatio)
        : null;
    final skeleton = editorSkeletonFor(
      screen: screen,
      compact: compact,
      trackBandHeight: rowTable.totalHeight,
      videoAspectRatio: sourceAspectRatio,
      framingAspectRatio: framingAspectRatio,
    );
    _lastSkeleton = skeleton;
    return PopScope(
      // 系统返回：对比-播放态先退对比态回单画面；取景调节态（对比路径）
      // 先退回对比-控制层、（单画面路径）退回编辑态。
      canPop: !(compareWatching || framingActive),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        if (framingActive) {
          _editorEntry.exitFraming();
        } else if (compareWatching) {
          _editorEntry.exitCompare();
        }
      },
      child: Scaffold(
        // 播放器皮肤（固定深色，见 kPlayerSkinColor），非主题 surface。
        backgroundColor: kPlayerSkinColor,
        // 全屏播放页不被软件键盘顶起。
        resizeToAvoidBottomInset: false,
        body: Listener(
          // 指针被系统强制取消（来电打断等）：收尾进行中的反馈会话。
          onPointerCancel: (_) => _gestures.onSystemPointerCancel(),
          // 播放场景：**唯一一处**源视频面装配——视频画面件与注解层都读这里
          // 给出的方向；演出层据此构建整棵浮层子树。
          child: Stack(
            fit: StackFit.expand,
            children: [
              SurfaceFaceAssembly(
                mirror: _mirror,
                builder: (context, direction) => SurfaceFaceScope(
                  snapshot: direction,
                  child: PresentationLayer(
                    input: _presentationLayerInput(
                      direction: direction,
                      skeleton: skeleton,
                      rowTable: rowTable,
                      controlOpen: controlOpen,
                      framingActive: framingActive,
                      compareWatching: compareWatching,
                      isCompare: session.isCompare,
                      reviewingClip: reviewingClip,
                    ),
                  ),
                ),
              ),
              // 手势演练（帮助域层域）：组合根只挂这一个 widget，读面经输入
              // 值对象给出（不接管手势）。
              PlayerDrill(
                input: PlayerDrillInput(
                  scrub: DrillScrubFace(
                    changes: _feedback,
                    isScrubbing: () => _feedback.isScrubbing,
                    startPointerCount: () => _feedback.startPointerCount,
                  ),
                  playingFlips: _engineSeek.engine.isPlayingStream,
                  transientRateActive: speedControlProvider.select(
                    (s) => s.transientActive,
                  ),
                  delayedPlayPreparing: delayedPlayPreparingProvider,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 转屏钮方向动作接线：把演出层的要求落到方向控制器；粘性
  /// 锁定由「此后不再请求跟随」表达。
  void _requestOrientation(ScreenOrientation target) {
    switch (target) {
      case ScreenOrientation.portrait:
        unawaited(_systemUi.lockPortrait());
      case ScreenOrientation.landscape:
        unawaited(_systemUi.lockLandscape());
    }
  }

  /// 控制层返回（对比态内先退对比态回单画面，再按才回首页）：导航与构建
  /// 上下文读取留在组合根，演出层只收回调。
  void _onControlLayerBack() {
    if (ref.read(playerSessionProvider).isCompare) {
      _editorEntry.exitCompare();
      return;
    }
    ref.read(playerSessionProvider.notifier).enter(PlayerSessionMode.editing);
    Navigator.of(context).maybePop();
  }

  /// 组装演出层输入：页面级 UI 事实、域句柄与三条宿主动作一次给全；
  /// 演出层自带 widget 子树，不反向读本页、不读中枢。
  PresentationLayerInput _presentationLayerInput({
    required SurfaceDirection direction,
    required EditorSkeleton skeleton,
    required TrackRowTable rowTable,
    required bool controlOpen,
    required bool framingActive,
    required bool compareWatching,
    required bool isCompare,
    required PracticeClip? reviewingClip,
  }) {
    final padding = MediaQuery.paddingOf(context);
    return PresentationLayerInput(
      engineSeek: _engineSeek,
      editorEntry: _editorEntry,
      gestures: _gestures,
      compareRecordingClips: _compareRecordingClips,
      loopPrompt: _loopPrompt,
      mirror: _mirror,
      signature: _signature,
      naming: _naming,
      session: _trackBandSession,
      noticeSpecs: kNoticeSpecs,
      presentation: _presentation,
      camera: _camera,
      takeover: _takeover,
      feedback: _feedback,
      scrubTarget: _scrubTarget,
      speedBubbleLink: _speedBubbleLink,
      beatBubbleLink: _beatBubbleLink,
      faceDirection: direction.directionOf(SurfaceFace.sourceVideo),
      skeleton: skeleton,
      rowTable: rowTable,
      controlOpen: controlOpen,
      framingActive: framingActive,
      compareWatching: compareWatching,
      isCompare: isCompare,
      metronomeVisible: ref.watch(beatOverlayContentVisibleProvider),
      opened: _opened,
      openFailed: _openFailed,
      reviewingClip: reviewingClip,
      landscape: MediaQuery.orientationOf(context) == Orientation.landscape,
      systemTopInset: padding.top,
      // 系统栏底内缩：与顶内缩同一条口径，
      // 供横屏编辑态的提示卡占用区上缘换算。
      systemBottomInset: padding.bottom,
      // 系统手势内缩：组合根一次读出交入演出层，贴底常驻入口
      // 叠加它避开手势让路区。
      systemGestureInsets: MediaQuery.systemGestureInsetsOf(context),
      scrubPictureRectOf: _scrubPictureRect,
      onControlLayerBack: _onControlLayerBack,
      onOpenFailedBack: () => Navigator.of(context).maybePop(),
      onRequestOrientation: _requestOrientation,
      beatCountContent: const BeatCountContent(),
      onTogglePlay: () => unawaited(_togglePlayPause()),
      onDelayedPlay: _delayedPlay.triggerNow,
      onExitClipReview: () => exitPracticeClipReview(ref),
      // 浮层 ✕：置总开关为关（面板开关同步）+ 退出选中态，并触发
      // 中央「重开方式」提示。
      onCloseBeatOverlay: () {
        ref.read(beatPromptEnabledProvider.notifier).set(false);
        _presentation.metronome.deselect();
        ref
            .read(noticeTriggerProvider(NoticeId.beatOverlayClose).notifier)
            .show();
      },
    );
  }
}
