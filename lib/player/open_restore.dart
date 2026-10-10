/// 按视频打开恢复库（改经打开会话）：打开
/// 会话给出的身份与文档快照在此按装载表逐行落地——复位、恢复、名册装载、
/// 续播、保存编排接通，并触发节拍分析与响度基准。
///
/// 契约：唯一入口 [videoOpenRestorerProvider]；一次打开的编排序列、恢复
/// 顺序与「建立序列不对索引条目做任何等待」的不变量见
/// [VideoOpenRestorer.resolve]。
///
/// 依赖方向（单向）：只依赖打开会话/方案/装载表、标注编辑模块、节拍分析
/// 库、续播库、编辑偏好吸附道、倍速记忆与 persistence 类型，零 import 中枢；
/// 反向不可。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../beat_track_state/beat_track_state.dart'
    show BeatTrackState, beatTrackStateProvider;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../dance/video_copy_presence.dart' show videoCopyPresenceProvider;
import '../import/import_providers.dart'
    show contentHasherProvider, videoIndexStoreProvider;
import '../persistence/video_index.dart' show VideoIndexEntry;
import '../persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveOrchestrator, AnnotationSaveSeed;
import '../persistence/local_document.dart';
// BeatGrid 文档类与 core/beat_grid.dart 的网格 seam 接口同名，别名引入。
import '../persistence/marker_document.dart' as marker_doc;
import '../persistence/member_scheme_store.dart'
    show MemberSchemeRecord, MemberSchemesDocument, memberSchemeStoreProvider;
import '../persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider;
import '../player_session/player_session.dart' show playerSessionProvider;
import 'annotation_editor.dart'
    show
        AnnotationRestoreDocument,
        annotationEditorProvider,
        annotationMemberSchemeReadonlyProvider,
        annotationSaveSinkStateProvider,
        effectiveAnnotationTimelineProvider,
        layoutLockedProvider;
import 'beat_analysis.dart' show beatAnalysisRunnerProvider;
import 'beat_prompt_memory.dart' show beatPromptMemoryProvider;
import 'metronome_sound.dart' show videoMutedProvider;
import 'framing_session_state.dart' show framingStateProvider;
import 'dancer_roster_controller.dart' show dancerRosterControllerProvider;
import 'load_gate.dart' show loadGateActiveProvider;
import 'notice.dart' show NoticeId, noticeTriggerProvider;
import '../persistence/load_table.dart' show LoadDefaults, LoadRowId, LoadTable;
import 'loop_prompt.dart' show tailGuardLog;
import 'open_session.dart';
import 'preview_snap.dart' show previewSnapEnabledProvider;
import 'resume_position.dart'
    show
        ResumeDecision,
        resumeDecision,
        resumePromptProvider,
        resolveResumeTarget;
import 'scheme_open.dart'
    show
        AutoSchemeOpen,
        SchemeOpen,
        masteryFromSnapshot,
        resolveOpenedMemberScheme;
import 'song_loudness.dart'
    show songLoudnessBaselineProvider, songLoudnessCoordinatorProvider;
import 'speed_control.dart' show speedControlProvider;

/// 按视频打开恢复（改经打开会话）：宿主在
/// 播放页装配「打开会话」（建立序列 = 按路径定身份 → 读两份文档 → 建基线快照
/// → 置已建立），本入口消费会话给出的身份与文档快照，按序完成——
///
/// 1. 打开即按新视频语义复位会话态与设置（上一视频的偏好/激活不得串入；
///    恢复命中时随后被覆盖）。节拍轨复位占位并取消上一视频的在途分析
///    （一次只分析一个、中断不写半截）。恢复前清经模块公开入口
///    `clearForVideoRestore`。
/// 2. 会话无身份（兜底摘要失败 / 文档不可读）→ 按无标注空态，不接保存
///    编排、无落盘目标；
/// 3. 名册装载、节拍分析、续播改经会话给出的身份与文档快照；身份按路径取
///    自条目（查不到才兜底算一次并补建条目），照常落盘（内容寻址）；
/// 4. markers 存在（非空态）且条目在册 → 以其署名/镜像回写 index 缓存
///    （仅差异时写盘，恢复本身不写 markers/local）；
/// 5. 注入 per-video [AnnotationSaveOrchestrator]（首建初值 = 条目在册时的
///    署名缓存 + 镜像过渡值；无条目按新视频缺省值），此后标注编辑提交即时
///    落盘。
///
/// 建立序列不对索引条目做任何等待：那一份 600 次 × 100ms 的重试与取消
/// 逻辑整体删除，「条目尚未落盘」不再是错误状态。
final videoOpenRestorerProvider = Provider<VideoOpenRestorer>((ref) {
  return VideoOpenRestorer(ref);
});

/// 打开装载的宿主接缝：启动序列里不属于打开
/// 恢复、但按装载表次序排在恢复之后的几段域会话启动。它们各自需要构建上
/// 下文或宿主呈现（命名对话框、统计记账、镜像会话），故由组合根构造，本模
/// 块按序调用——页面只调一次 [VideoOpenRestorer.open]。
abstract interface class OpenLoadHost {
  /// 组合根是否仍在树上（页面销毁后不再往下走后续域会话启动）。
  bool isMounted();

  /// 编辑偏好会话：按会话给出的身份恢复 local 偏好并开始「变更即存」订阅。
  Future<void> openSettings(OpenSession session);

  /// 练舞统计会话启动（署名解析前，避免解析窗口内的播放记到上一支舞）。
  void startStats();

  /// 歌曲署名解析（消费打开会话给出的已确认身份）。
  Future<void> startSignature(OpenSession session);

  /// 署名解析落定后把当前视频交给统计域。
  void syncStatsVideoContext();

  /// 首次导入命名框（先命名、后镜像，两个模态不叠置）。
  Future<void> promptNaming({required bool isNewImport});

  /// 镜像状态机：首次打开询问、再次打开按历史应用并提示。
  Future<void> resolveMirror(OpenSession session);
}

class VideoOpenRestorer {
  VideoOpenRestorer(this._ref);

  final Ref _ref;

  /// 开舞装载的前置半段：引擎 `open(play: true)` 起播之前调用，
  /// 把引擎倍速写回出厂原速、步进归未启用、记忆槽清空——上一支舞的速率不
  /// 带进下一支舞的第一遍。与 [open] 拆成两段只因起播夹在中间：读回这支舞
  /// 记忆的精调由偏好恢复会话随后在同一支舞上完成
  /// （`VideoSettingsPersistence._restore`）。
  ///
  /// 无 IO、无等待：写的是内存态与引擎，不读本地文档。
  Future<void> prepareForOpen() =>
      _ref.read(speedControlProvider.notifier).loadForOpen(null);

  /// 启动序列：一次打开的**唯一入口**——页面
  /// 只调本方法一次，建立会话、按装载表逐行恢复与随后几段域会话的启动都在
  /// 这里收口编排。
  ///
  /// 「装载未完成」门的开合归本模块持有：建立序列之前置位——对象集本身来自
  /// 尚未装载的文档；打开恢复（[resolve]，含把标注对象集放上时间线那一段）
  /// 落定即落位，同一序列后面的命名框 / 镜像询问 / 署名解析因此不再拖住它。
  /// 无实体文件（不存在 / 平台路径不可用）时不置位：没有可装载的内容，
  /// 「正在装载」不该留下。页面不再碰门的开合，只读门事实。
  ///
  /// 次序与既有实现逐位一致：
  ///
  /// 1. 按路径定身份（命中条目即取、不读视频内容；查不到才兜底算一次并补建
  ///    条目；建立序列的异常按无身份收场、不阻塞播放）；
  /// 2. [resolve] 落定（打开恢复不再后台跑：门的落定点就是它的落定）；
  /// 3. 偏好恢复与「变更即存」订阅（[OpenLoadHost.openSettings]）；
  /// 4. 统计会话启动（署名解析前，避免解析窗口内的播放记到上一支舞）；
  /// 5. 署名解析（[OpenLoadHost.startSignature]），落定后交给统计域；
  /// 6. 首次导入命名框（先命名、后镜像，[OpenLoadHost.promptNaming]）；
  /// 7. 镜像状态机（[OpenLoadHost.resolveMirror]）。
  Future<void> open({
    required Uri source,
    required Duration videoDuration,
    required bool askNaming,
    required OpenLoadHost host,
    SchemeOpen scheme = const AutoSchemeOpen(),
  }) async {
    final session = OpenSession(
      filePath: source.toFilePath(),
      indexStore: _ref.read(videoIndexStoreProvider),
      hasher: _ref.read(contentHasherProvider),
      coordinatorFor: (videoId) =>
          _ref.read(videoDocumentCoordinatorProvider(videoId)),
    );
    final gate = _ref.read(loadGateActiveProvider.notifier);
    if (_shouldArmLoadGate(session.filePath)) gate.begin();
    try {
      try {
        await session.establish();
      } on Object {
        // 建立序列异常：无身份、按空态。
      }
      if (!host.isMounted()) return;
      // 打开恢复接线：落定即落位门（见 [resolve] 的收尾）；恢复失败按无
      // 标注空态，且不阻塞后续域会话。
      try {
        await resolve(
          session: session,
          videoDuration: videoDuration,
          scheme: scheme,
        );
      } on Object {
        // 打开恢复失败：门已在其收尾落位，标注按空态。
      }
      if (!host.isMounted()) return;
      await host.openSettings(session);
      host.startStats();
      await host.startSignature(session);
      if (!host.isMounted()) return;
      host.syncStatsVideoContext();
      await host.promptNaming(isNewImport: askNaming);
      await host.resolveMirror(session);
    } finally {
      // 兜底落位：建立序列没走完、宿主中途卸载时，门也不留成一个永远
      // 挡写的门。
      if (_ref.mounted) gate.settle();
    }
  }

  /// 打开恢复（流程见库头注释）。[session] 由播放页装配并已建立；
  /// [scheme] = 这次打开带的方案参数，缺省 = 不带参数（详情页方案区各行与
  /// 首页卡片各带一份）。
  ///
  /// **落定即落位「装载未完成」门**（门由本模块持有，见 [open]）：本恢复
  /// 收尾——标注对象集与熟练度都放上时间线那一段走完——就是门的落定点，
  /// 不是「建立序列走完」，因此不留「门已经落下、对象集还没上来」的窗口；
  /// 恢复抛异常时同样落位，不留一个永远挡写的门。
  Future<void> resolve({
    required OpenSession session,
    required Duration videoDuration,
    SchemeOpen scheme = const AutoSchemeOpen(),
  }) async {
    try {
      await _resolve(
        session: session,
        videoDuration: videoDuration,
        scheme: scheme,
      );
    } finally {
      // 容器已销毁（测试拆场 / 树先于在途链退场）时不读已销毁的 ref：
      // 门随容器一同消逝，无需落位。
      if (_ref.mounted) _ref.read(loadGateActiveProvider.notifier).settle();
    }
  }

  /// 打开恢复本体（流程与门的落定点见 [resolve]）。
  Future<void> _resolve({
    required OpenSession session,
    required Duration videoDuration,
    SchemeOpen scheme = const AutoSchemeOpen(),
  }) async {
    _ref.read(annotationEditorProvider).clearForVideoRestore();
    // 换视频/新视频打开复位播放会话模式值（待命态
    // 是模式取值之一，随复位清空；**锚点数据不丢**）。
    _ref.read(playerSessionProvider.notifier).reset();
    // 视频静音是会话值（不落盘）：换视频即回有声音——播放内核是应用级
    // 单例，静音属性会跨视频留着，这里必须写回不静音。
    _ref.read(videoMutedProvider.notifier).reset();
    _ref.read(resumePromptProvider.notifier).dismiss();
    // 取景会话值随打开复位：上一支舞的选区
    // 不得串入；随后按装载表由公开标记文件行就位。
    _ref.read(framingStateProvider.notifier).reset();
    _resetSettingsToDefaults();
    _ref.read(songLoudnessBaselineProvider.notifier).reset();
    _ref.read(songLoudnessCoordinatorProvider).cancel();
    _ref.read(beatAnalysisRunnerProvider).cancel();
    _ref
        .read(beatTrackStateProvider.notifier)
        .replace(const BeatTrackState.placeholder());
    if (!session.identified) return;
    final coordinator = session.coordinator!;
    final videoId = session.videoId!;
    final entry = session.entry;
    final filePath = session.filePath;

    // 这次打开用哪一份方案：不带参数的打开恒取
    // 我的标注方案，没有例外；方案区的每一行各带自己那一份。装载组员方案时
    // 标注只读（门禁
    // 第三原因的真值在此就位）、熟练度 = 发送方快照且只读，我的落盘激活不读
    // 也不写——它按我的标注方案的段序索引，读进来就会指向完全不同的动作。
    final memberLoad = await _resolveLoadedMemberScheme(
      session,
      videoId,
      scheme,
    );
    if (!_ref.mounted) return;
    _ref
        .read(annotationMemberSchemeReadonlyProvider.notifier)
        .setLoaded(memberLoad != null);
    // 方案公开文档损坏时回落我的方案、不当只读（不弹提示，打开照常）。
    var markersForLoad = session.markers;
    if (memberLoad != null) {
      try {
        markersForLoad = marker_doc.MarkersDocument.fromJson(
          memberLoad.markers,
        );
      } on Object {
        markersForLoad = session.markers;
        _ref
            .read(annotationMemberSchemeReadonlyProvider.notifier)
            .setLoaded(false);
      }
    }

    // 行序由装载表给出：本会话按表逐行执行它承接的行，其余行
    // （偏好 / 镜像 / 署名）在 switch 里显式列出并说明执行归属——不靠
    // 「map 里没有这一项」的缺席表达（见词条「标注工具区」），表加一行而这里
    // 漏接会编译报错。
    //
    // 恢复写回（激活写回自带「来自恢复」出处标记，播放页据此只就位循环
    // 作用域、不执行「跳段首」seek——恢复不自动跳转）。名册装载读 markers
    // 的 roster 段、与恢复写回互不竞争（激活写回只改 local / markers
    // 非名册段），故按表排在编辑器两行之后不改变结果。
    for (final row in LoadTable.standard.rows) {
      switch (row.id) {
        case LoadRowId.editorPublicMarkers:
          _restoreMarkers(markersForLoad, videoDuration);
        case LoadRowId.editorLocalPrivate:
          if (memberLoad == null) {
            _restoreLocal(session.local);
          } else {
            // 组员方案装载：偏好照常恢复；熟练度
            // = 发送方那一次的快照（只读显示）、激活不读我的落盘值。
            _restoreLocalPreferences(session.local);
            _ref
                .read(annotationEditorProvider)
                .restoreDocument(
                  AnnotationRestoreDocument(
                    mastery: masteryFromSnapshot(memberLoad.mastery),
                    activatedSegments: const {},
                  ),
                );
          }
        case LoadRowId.roster:
          await _ref
              .read(dancerRosterControllerProvider)
              .startForVideo(coordinator);
          // 恢复是会被宿主中途舍弃的长链：页面已销毁时不再往下读 provider。
          if (!_ref.mounted) return;
        case LoadRowId.resume:
          // 续播位置按条目：条目在册（按路径命中，或兜底补建）的这支舞才有
          // 旧位置。
          if (entry != null) await _applyResumePosition(entry, videoDuration);
        // 偏好 / 镜像 / 署名：执行归宿主调用点（播放页 `_open` 的偏好
        // 编排、镜像控制器、署名控制器），会话侧按表跳过。
        case LoadRowId.preferences:
        case LoadRowId.mirror:
        case LoadRowId.signature:
          break;
      }
    }

    // markers 存在且条目在册 → 以其署名/镜像回写 index 缓存；无条目时索引
    // 里没有可写的这支舞。回写只看我的公开文档——组员方案装载时署名缓存仍
    // 以我的文件为准。
    if (entry != null &&
        session.markers != const marker_doc.MarkersDocument.empty()) {
      await _writeBackSignatureCache(videoId, session.markers);
    }
    if (!_ref.mounted) return;

    // 接通标注保存编排（per-video 实例）；首建初值取命中条目的 index 缓存。
    _ref
        .read(annotationSaveSinkStateProvider.notifier)
        .set(
          AnnotationSaveOrchestrator(
            coordinator: coordinator,
            seed: () async => _seedFor(entry),
            // 只读文档上的写回被挡（读到了只读版本 / 读与写之间盘上换成
            // 只读文件）：沿既有短暂提示通道当面说明，改动不静默丢失。
            onWriteRejected: (_) => _ref
                .read(noticeTriggerProvider(NoticeId.documentReadOnly).notifier)
                .show(),
          ),
        );

    // 节拍接线：已有 beat 直接消费
    // （零重复分析）；无 beat → 后台自动分析一次（不阻塞播放、不排队），
    // 完成原子写 markers.beat 并即时切真实网格。 markers 空态（缺失/损坏）
    // 同样触发分析（首建即带 beat 段）。组员方案装载时节拍取方案的
    // 公开文档（八拍锚点脱离网格就没有意义，六段全含）。
    final beatDoc = markersForLoad.beat;
    if (beatDoc != null && beatDoc.beats.isNotEmpty) {
      _ref
          .read(beatTrackStateProvider.notifier)
          .replace(BeatTrackState.ready(beatDoc));
      //  路径二：打开一支盘上已有节拍数据、记忆已读到且无记录
      // 的舞——网格直接置就绪，经同一判据落点把两个总开关各自动置开一
      // 次并写进这支舞的记忆（取代旧裁决「打开已有节拍数据的视频不触发
      // 自动打开」）。记忆恢复晚于此处时（偏好恢复与恢复链并行），由
      // 偏好恢复侧读到后按同一落点补判。
      _ref
          .read(beatPromptMemoryProvider.notifier)
          .autoEnableFor(videoId, freshAnalysis: false);
    } else {
      unawaited(
        _ref
            .read(beatAnalysisRunnerProvider)
            .start(
              videoPath: filePath,
              coordinator: coordinator,
              seed: () async => _seedFor(entry),
              videoId: videoId,
            ),
      );
    }

    // 歌曲响度基准对齐：已有 beat（本次不分析）→ 缓存命中即用、
    // 无缓存后台补测一次后更新；无 beat → 本次分析解码顺带测量（见
    // beatAnalysisRunner.start），无需另起补测。
    if (beatDoc != null && beatDoc.beats.isNotEmpty) {
      unawaited(
        _ref
            .read(songLoudnessCoordinatorProvider)
            .ensureBaseline(videoPath: filePath, videoId: videoId),
      );
    }
  }

  /// 这次打开用哪一份组员方案：判定纯函数见
  /// [resolveOpenedMemberScheme]——不带参数恒用我的方案（我的方案为空也不
  /// 改用组员方案）；方案区各行各带自己的参数。方案文件读失败按无组员方案
  /// 处理。
  Future<MemberSchemeRecord?> _resolveLoadedMemberScheme(
    OpenSession session,
    String videoId,
    SchemeOpen scheme,
  ) async {
    final MemberSchemesDocument doc;
    try {
      // 有界等待：方案文件读不可达（宿主测试无路径通道、极端 IO 挂起）
      // 时按无组员方案装载——只回落「用我的方案」，零写、不拖住恢复
      // 装载。生产里该文件与索引同目录、打开前已随首页读面预热。
      doc = await _ref
          .read(memberSchemeStoreProvider(videoId))
          .read()
          .timeout(
            const Duration(milliseconds: 50),
            onTimeout: () => MemberSchemesDocument.empty,
          );
    } on Object {
      return null;
    }
    return resolveOpenedMemberScheme(open: scheme, schemes: doc.schemes);
  }

  /// 标注首建初值：条目命中时取 index 的署名/镜像过渡值；无条目或摘要
  /// 不符时按新视频缺省（不套用旧条目）。
  AnnotationSaveSeed _seedFor(VideoIndexEntry? entry) {
    if (entry == null) return const AnnotationSaveSeed();
    return AnnotationSaveSeed(
      signature: entry.signatureCache,
      mirrored: entry.mirrored,
      localMirrorEnabled: entry.localMirrorEnabled,
    );
  }

  /// 续播接线（续播行为）：按路径取到的条目身份即这支舞，
  /// 据此读 index 的续播位置决策——有效位置 seek（页面打开即播 → 自动续播），
  /// 位置超出头部阈值再弹「从头播放？」小卡；头部阈值内静默续播；上次
  /// 到尾（含记录值 0）从头播放、不弹卡。续播位置越自定义尾线钳回尾线
  /// （续播恢复钳制：打开不再落到尾线右侧，跨尾线拦截照常生效），
  /// 钳制语义唯一实现于 `resolveResumeTarget` seam。
  Future<void> _applyResumePosition(
    VideoIndexEntry entry,
    Duration videoDuration,
  ) async {
    final raw = Duration(milliseconds: entry.lastPositionMs);
    final timeline = _ref.read(effectiveAnnotationTimelineProvider);
    final target = resolveResumeTarget(
      position: raw,
      videoDuration: videoDuration,
      rangeEnd: timeline.videoDuration > Duration.zero
          ? timeline.rangeEnd
          : null,
    );
    // 到尾归 0 是既有存储编码的「从头」语义、非越界钳制，与记录侧同类
    // 日志口径对齐只记尾线钳回。
    if (target != raw && raw < videoDuration) {
      tailGuardLog('续播恢复越界：$raw > 尾线 → 钳回 $target');
    }
    final decision = resumeDecision(
      lastPosition: target,
      videoDuration: videoDuration,
    );
    if (decision == ResumeDecision.none) return;
    try {
      await _ref.read(playbackEngineProvider).seek(target);
    } on Object {
      return; // seek 失败视为位置无效，不弹卡。
    }
    if (!_ref.mounted) return;
    if (decision == ResumeDecision.continueWithPrompt) {
      _ref.read(resumePromptProvider.notifier).show();
    }
  }

  /// 设置复位到出厂态（打开新视频 / 新视频语义的基线）。
  ///
  /// 局部镜像**总开关**不在此复位：它是视图开关，唯一写者是镜像
  /// 控制器——[MirrorController.resolve] 每次打开先把值复位到缺省、再按
  /// markers 真值 / index 过渡值 / 首建初值三条路径写入并推值道。本入口
  /// 与它同时写会变成「谁后跑谁赢」的隐式次序依赖（`_resetSettingsToDefaults`
  /// 恰在前只因 restorer 的同步前缀先于镜像 resolve 执行），故不写。
  void _resetSettingsToDefaults() {
    final defaults = LoadDefaults.preferences;
    _ref
        .read(previewSnapEnabledProvider.notifier)
        .replace(defaults.previewSnapEnabled);
    // 循环前导不在此复位：设备级设置，跨视频通用，
    // 会话档位由 prepBeatsProvider 启动恢复后经 delayedLoopProvider 派生就位。
    _ref.read(layoutLockedProvider.notifier).replace(defaults.layoutLocked);
  }

  /// markers 恢复（分段线含 flag/首尾/重点 + 局部镜像片段）；文档为空态
  /// 或视频时长未知时跳过（时间线几何无从构建）。装载经模块恢复入口。
  ///
  /// 局部镜像**总开关**不在此恢复（同上）：标记文件里的现值由
  /// 镜像控制器读出，本入口不写该值道。
  void _restoreMarkers(marker_doc.MarkersDocument markers, Duration duration) {
    // 源画面取景选区随公开标记文件就位（装载表
    // 把取景留在公开标记文件行——声明次序即恢复次序；组员方案装载时
    // markersForLoad 就是方案文档，方案里的构图生效）。打开复位已把会话值
    // 归零，这里只读装载、不写盘；旧 v8 取景字段已在版本迁移里丢掉 = 复位。
    _ref
        .read(framingStateProvider.notifier)
        .restoreSource(markers.framingSelection);
    if (duration <= Duration.zero) return;
    final hasRange = markers.rangeStartMs != 0 || markers.rangeEndMs != 0;
    final timeline = hasRange
        ? AnnotationTimeline.normalized(
            videoDuration: duration,
            rangeStart: Duration(milliseconds: markers.rangeStartMs),
            rangeEnd: Duration(milliseconds: markers.rangeEndMs),
            segmentLines: markers.segmentLines,
            halfBeatLines: markers.halfBeatLines,
          )
        : AnnotationTimeline.wholeVideo(duration);
    _ref
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            timeline: timeline,
            emphasizedSegments: {...markers.emphasizedSegments},
            segmentDensities: {...markers.segmentDensities},
            localMirrorFragments: List.of(markers.localMirrorFragments),
            notes: List.of(markers.notes),
          ),
        );
  }

  /// local 恢复（熟练度/激活/吸附偏好/延迟循环/锁定分段）；文档为空态
  /// （缺失/损坏按空态兜底）时保持默认。激活与熟练度按恢复后时间线的
  /// 段数过滤越界段序。
  void _restoreLocal(LocalDocument local) {
    // 熟练度/激活按段序挂靠，几何真值在 markers：markers 空态或视频时长
    // 未知时无从推导段序，两者按空态处理（取舍：宁丢不挂错段），预览吸附/
    // 延迟循环/锁定分段等无几何依赖的设置照常恢复。
    if (local == const LocalDocument.empty()) return;
    // 熟练度/激活经模块恢复入口就位（段数按恢复后时间线在模块内派生并
    // 过滤越界段序）。
    _ref
        .read(annotationEditorProvider)
        .restoreDocument(
          AnnotationRestoreDocument(
            mastery: local.mastery,
            activatedSegments: {...local.activatedSegments},
          ),
        );
    _restoreLocalPreferences(local);
  }

  /// local 偏好恢复（吸附/锁定分段；组员方案装载
  /// 路径只走这一半——熟练度与激活不来自我的本地文档）。循环前导不再随
  /// 舞恢复：设备级设置，组员方案从此不携带。
  void _restoreLocalPreferences(LocalDocument local) {
    if (local == const LocalDocument.empty()) return;
    _ref
        .read(previewSnapEnabledProvider.notifier)
        .replace(local.previewSnapEnabled);
    _ref.read(layoutLockedProvider.notifier).replace(local.layoutLocked);
  }

  /// 命中条目 → 以 markers 的署名/镜像为准回写 index 缓存（同步
  /// 规则）；现值已一致时不产生写盘（[VideoIndexStorage.update] 同实例跳写）。
  ///
  /// 读-改-写在 [VideoIndexStorage.update] 的串行链内完成（链内重读当前
  /// 条目），不拿会话建立时的条目快照整条替换——否则同条目其它字段
  /// （如续播位置）在建立与回写之间的并发写会被旧快照回退。
  Future<void> _writeBackSignatureCache(
    String videoId,
    marker_doc.MarkersDocument markers,
  ) async {
    try {
      await _ref.read(videoIndexStoreProvider).update((index) {
        final current = index.findById(videoId);
        if (current == null) return index;
        if (current.signatureCache == markers.signature &&
            current.mirrored == markers.mirrored) {
          return index;
        }
        return index.replaceEntry(
          current.copyWith(
            signatureCache: markers.signature,
            clearSignatureCache: markers.signature == null,
            mirrored: markers.mirrored,
          ),
        );
      });
    } on Object {
      // 回写失败不阻塞播放（非关键路径，下次打开再对账）。
    }
  }

  /// 「装载未完成」门要不要置位：没有实体视频副本（不存在 / 平台路径不可用）
  /// 时不置位——没有可装载的内容，「正在装载」不该留下。
  ///
  /// 「副本在不在」只问 [videoCopyPresenceProvider] 这一处（见词条「副本
  /// 丢失」），本模块不自己查一次文件系统；副本丢失的判定与拦截发生在打开
  /// 入口之前。
  bool _shouldArmLoadGate(String filePath) =>
      _ref.read(videoCopyPresenceProvider).exists(filePath);
}
