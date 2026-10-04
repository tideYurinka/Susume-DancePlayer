/// 按视频编辑偏好域（自持会话生命周期）：恢复、
/// 变更即存与收尾编排同处一库，宿主经 [VideoSettingsPersistence.openFor] 在
/// 打开点启动一次、经 [VideoSettingsPersistence.dispose] 随页面结束收尾。
///
/// 依赖方向（单向，护栏钉住）：只依赖持久化文档/协调器、各偏好 provider 的
/// 归属库（标注编辑模块、预览吸附、浮层位、练习镜像、取景、倍速记忆）、
/// 打开会话与 Flutter/Riverpod 基础类型；零 import 中枢，不 import
/// 播放页与控制层。本库经 `export` 承接按视频协调器读取面。
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/document_read_outcome.dart';
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart';
import '../persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider;
import 'annotation_editor.dart'
    show
        annotationMemberSchemeReadonlyProvider,
        layoutLockedProvider,
        practiceClipActivationProvider,
        practiceClipsProvider;
import 'metronome_overlay.dart' show overlayPlacementProvider;
import 'beat_prompt_memory.dart' show beatPromptMemoryProvider;
import 'framing_session_state.dart' show framingStateProvider;
import 'notice.dart' show NoticeId, noticeTriggerProvider;
import 'open_session.dart';
import 'overlay.dart' show OverlayPlacementCell, OverlayPlacements;
import 'practice_mirror.dart' show practiceMirrorOverrideProvider;
import 'preview_snap.dart' show previewSnapEnabledProvider;
import 'speed_control.dart' show SpeedControlState, speedControlProvider;

// 按视频文档存取与协调器注入点的唯一来源在 persistence 层
// （`video_document_providers.dart`，应用文档目录）；本库保持转发，
// 播放页与持久化套件的读取面统一经此符号集导入。
export '../persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageProvider;

/// 按视频编辑偏好（吸附偏好/锁定分段，归属 local 私密文件；循环前导
/// 拍档是设备级、不随舞）的落盘与恢复编排。
///
/// - [startForVideo]：打开视频后调用，消费打开会话给出的已确认身份
///   （[videoId]，不再自行按路径轮询索引条目）。读该身份的 local 文档把
///   偏好恢复进各 provider（恢复为只读，不产生写盘），再订阅 provider
///   变更——每次变更经协调器对 local 做字段级 patch（值无变化时协调器
///   跳过写盘，满足「无 UI 改动的设置不产生写盘」）。
/// - 会话未识别身份（[videoId] 为 null）或 local 不可读：维持默认会话态，
///   不抛错、不阻塞播放；用户变更在无 videoId 期间不落盘。
/// - 换视频须先 [dispose] 再重新 start：恢复与订阅都锚定本次给出的
///   videoId，各视频文件互不相通。
class VideoSettingsPersistence {
  VideoSettingsPersistence(this._container);

  /// 读写各设置 provider 与按视频协调器的容器（应用级生存期，与
  /// ProviderScope 同源；测试直接注入测试容器）。
  final ProviderContainer _container;

  final List<ProviderSubscription<Object?>> _subscriptions = [];
  String? _videoId;
  bool _disposed = false;

  /// 取景取值有未落盘的变更。只有取景自身的
  /// 变更才写公开标记文件——其余偏好变更不顺带创建/改写 markers，也不把旧
  /// v8 文件提前升级。
  bool _framingDirty = false;

  /// 当前会话的恢复完成（测试同步点）；无会话时立即完成。
  Future<void> get started => _startedCompleter.future;
  Completer<void> _startedCompleter = Completer<void>();

  /// 最近一次落盘写入完成（同步点）：去抖窗口未收口时先强制收口再返回，
  /// 保证返回后窗口内的变更已落盘。
  Future<void> get flush {
    final debounce = _debouncePersistTimer;
    if (debounce != null && debounce.isActive) {
      debounce.cancel();
      if (!_disposed) _persistPreferences();
    }
    return _flush;
  }

  Future<void> _flush = Future<void>.value();

  /// 浮层落盘去抖窗口。
  static const Duration kDebouncedPersistDelay = Duration(milliseconds: 300);
  Timer? _debouncePersistTimer;

  /// 打开视频后调用：消费打开会话给出的已确认身份（[videoId]，null =
  /// 会话未识别身份），读该身份的 local 文档恢复偏好并开始「变更即存」。
  Future<void> startForVideo(String? videoId) async {
    dispose();
    _disposed = false;
    _framingDirty = false;
    // 换会话即清空片段表：本表是应用级会话值（provider 不随页面销毁），
    // 不清空则上一支舞的片段会留在下一次装载之前；装载随即按本文档重新
    // 恢复。
    _container.read(practiceClipsProvider.notifier).restore(const []);
    // 节拍提示记忆随舞：本表也是应用级会话值，
    // 换会话先清空，上一支舞的记忆与「已读到」标记不留在下一支舞。
    _container.read(beatPromptMemoryProvider.notifier).clear();
    _startedCompleter = Completer<void>();
    if (_disposed || videoId == null) {
      // 倍速记忆随舞：未识别身份也按无记忆打开——换会话即清记忆
      // 槽、引擎写回出厂原速、步进归未启用。已识别身份的写穿由打开恢复域的
      // 前置半段在开播前落下，读回记忆后再由 [_restore] 精调。
      await _container.read(speedControlProvider.notifier).loadForOpen(null);
      if (!_startedCompleter.isCompleted) _startedCompleter.complete();
      return;
    }
    _videoId = videoId;
    await _restore(videoId);
    if (_disposed) return;
    _subscribe();
    // 订阅就绪后补判一次自动置开（判据落点自行核对三条件）
    // ——打开已有节拍数据的舞时，恢复链可能先于偏好恢复把网格置就绪；
    // 补判在「变更即存」订阅挂上之后，置开写进记忆才必然落盘。记忆装载
    // （[_restore] 内 restoreFor）与本补判之间无 await，打开分支不会插
    // 入其间。
    _container
        .read(beatPromptMemoryProvider.notifier)
        .autoEnableFor(videoId, freshAnalysis: false);
    if (!_startedCompleter.isCompleted) _startedCompleter.complete();
  }

  /// 打开视频后调用：由本域消费打开会话给出的已确认身份
  /// （[OpenSession.videoId]，null = 会话未识别身份），编排与 [startForVideo]
  /// 逐点相同。
  Future<void> openFor(OpenSession session) => startForVideo(session.videoId);

  /// 读该身份的 local 文档并恢复偏好（含节拍提示记忆随舞装载——null =
  /// 这支舞无记忆记录，同时按身份落「已读到」标记；
  /// local 不可读按「读到且无记录」收口：盘上没有可恢复的记忆不等于
  /// 「还没读到」，否则这支舞永远等不到自动置开）。恢复为只读装载——
  /// 本方法在订阅挂上之前执行，不产生写盘；自动置开补判由调用方在订阅
  /// 就绪后统一执行。
  Future<void> _restore(String videoId) async {
    LocalDocument? doc;
    try {
      doc = await _container
          .read(videoDocumentCoordinatorProvider(videoId))
          .readLocal();
      if (_disposed) return;
    } on Object {
      doc = null;
    }
    _container
        .read(beatPromptMemoryProvider.notifier)
        .restoreFor(videoId, doc?.beatPrompt);
    // 倍速记忆随舞：null = 这支舞没有意见，按出厂原速打开；
    // 有记忆即写穿引擎，第一遍就是这支舞的倍率。恢复为只读装载，不写盘。
    await _container
        .read(speedControlProvider.notifier)
        .loadForOpen(doc?.speedRate);
    if (_disposed) return;
    if (doc == null) return;
    _setPreviewSnap(doc.previewSnapEnabled);
    _setLayoutLocked(doc.layoutLocked);
    _setOverlayPlacement(doc);
    // 练习侧镜像随舞覆盖：null = 未覆盖（生效值回落设备级默认）。
    _container
        .read(practiceMirrorOverrideProvider.notifier)
        .set(doc.practiceMirror);
    // 练习片段列表随舞恢复：只落会话值，不自动播放、不改
    // 播放位置。读过这张表 ⇒ 本会话的片段表是**该文档的完整视图**，
    // 写回即会话终值（含删除/截取终值）。
    _container.read(practiceClipsProvider.notifier).restore(doc.practiceClips);
    // 片段激活随舞恢复（与学习段激活同段同口径）：id 不在片段
    // 列表时不激活；恢复不自动跳转、不自动播放。
    _container
        .read(practiceClipActivationProvider.notifier)
        .restore(doc.activePracticeClipId, clips: doc.practiceClips);
  }

  /// 数拍浮层位（四格 + 分形态系数）恢复：文件无任何浮层位字段 =
  /// 四格全未自定义（provider 落 null）；
  /// 有则按「一格两键齐全」组装成四格容器（系数读取时已钳制，缺键回落
  /// 1.0）。
  void _setOverlayPlacement(LocalDocument doc) {
    _container
        .read(overlayPlacementProvider.notifier)
        .set(_placementsOf(doc.overlay));
  }

  void _subscribe() {
    _subscriptions.addAll([
      _container.listen(
        previewSnapEnabledProvider,
        (previous, next) => _persistPreferences(),
      ),
      _container.listen(
        layoutLockedProvider,
        (previous, next) => _persistPreferences(),
      ),
      _container.listen(
        overlayPlacementProvider,
        (previous, next) => _scheduleDebouncedPersist(),
      ),
      _container.listen(
        practiceMirrorOverrideProvider,
        (previous, next) => _persistPreferences(),
      ),
      // 源画面取景随舞记忆（取景只有源画面
      // 一份，直写公开标记文件）：手势/复位逐帧变更与浮层位同款去抖——一次
      // 拖动合并为一次落盘，flush 同步点强制收口。
      _container.listen(framingStateProvider, (previous, next) {
        _framingDirty = true;
        _scheduleDebouncedPersist();
      }),
      // 练习片段列表随舞记忆：录制入轨与截取拖动变更
      // 落 local prefs；截取拖动逐帧变更与浮层位同款去抖（一次拖动合并
      // 为一次落盘）。
      _container.listen(
        practiceClipsProvider,
        (previous, next) => _scheduleDebouncedPersist(),
      ),
      // 节拍提示记忆随舞：面板/浮层 ✕ 与自动
      // 置开的写入口都落在记忆槽，变更即存（开关离散变更与吸附同款即时
      // 落盘）；值无变化时协调器跳过写盘。
      _container.listen(
        beatPromptMemoryProvider,
        (previous, next) => _persistPreferences(),
      ),
      // 倍速记忆随舞：只有手动倍率（记忆单元）变更才落盘——步进
      // 启用/档位推进与瞬态倍速都不写记忆（值无变化时协调器也跳过写盘）。
      _container.listen<SpeedControlState>(speedControlProvider, (
        previous,
        next,
      ) {
        if (previous?.memoryRate == next.memoryRate) return;
        _persistPreferences();
      }),
    ]);
  }

  /// 去抖落盘调度（浮层位/取景/练习片段等高频变更域共用：拖把手/捏合/
  /// 截取拖动的逐帧变更合并为窗口内一次 patch，flush 同步点强制收口）。
  void _scheduleDebouncedPersist() {
    _debouncePersistTimer?.cancel();
    _debouncePersistTimer = Timer(kDebouncedPersistDelay, () {
      if (!_disposed) _persistPreferences();
    });
  }

  /// 偏好落盘：此刻同步取好各域值与取景写回门禁，再排进写链对 local 做
  /// 字段级 patch（patch 内容无变化时协调器跳过写盘）。取值不留给写链——
  /// 收尾排队的写入会跨过页面销毁与下一会话的恢复，写链里再读 provider 会
  /// 把上一支舞的值写成下一支舞的。写失败不抛到 UI。
  void _persistPreferences() {
    final videoId = _videoId;
    if (videoId == null) return;
    final previewSnapEnabled = _container.read(previewSnapEnabledProvider);
    final layoutLocked = _container.read(layoutLockedProvider);
    final practiceMirror = _container.read(practiceMirrorOverrideProvider);
    final practiceClips = _container.read(practiceClipsProvider);
    final overlay = _container.read(overlayPlacementProvider);
    final beatPrompt = _container.read(beatPromptMemoryProvider);
    final speedRate = _container.read(speedControlProvider).memoryRate;
    final framingSource = _container.read(framingStateProvider).source;
    final framingDirty = _framingDirty;
    _framingDirty = false;
    final framingWritable = !_container.read(
      annotationMemberSchemeReadonlyProvider,
    );
    _flush = _flush.then((_) async {
      try {
        final coordinator = _container.read(
          videoDocumentCoordinatorProvider(videoId),
        );
        final local = await coordinator.readLocalOutcome();
        if (local is DocumentReadOnly<LocalDocument>) {
          _showDocumentReadOnly();
        }
        if (local is WritableDocumentReadOutcome<LocalDocument>) {
          final written = await local.write((context) {
            final next = context.document
                .withSnap(previewSnapEnabled: previewSnapEnabled)
                .withLayoutLocked(layoutLocked)
                .withPracticeMirror(practiceMirror)
                .withPracticeClips(practiceClips);
            // 整组写绝对终值（含 null = 四格全未自定义）：清掉唯一自定义格
            // 后不许旧键残留，故 null 也要落到文档（`withOverlayPlacements`
            // 对 null 清空整个 `prefs.overlay`），不能沿用「null 就跳过」。
            // 节拍提示记忆同为整组绝对终值：null = 会话无记忆
            // 记录，写侧省键，不残留旧键。
            final updated = next
                .withOverlayPlacements(
                  overlay == null ? null : _fieldsOf(overlay),
                )
                .withBeatPrompt(beatPrompt);
            // 倍速记忆：null = 这支舞没有意见（写侧省键，不
            // 制造一份 1.0× 的记录）。
            return speedRate == null
                ? updated
                : updated.withSpeedRate(speedRate);
          });
          if (written is DocumentWriteRejected<LocalDocument>) {
            _showDocumentReadOnly();
          }
        }
        // 源画面取景选区直写公开标记文件 `meta` 段：绝对终值（null = 清除），
        // 不入撤销史、不受锁定分段门禁；
        // 组员方案装载期间不落盘——方案的值生效，调整只改会话值（沿「续播
        // 位置读而不写」的先例）。目标值与盘上现值相同即无事发生：打开恢复
        // 的装载（与用户改动共用同一写入口）因此不落盘、也不对只读文件弹
        // 提示；打开恢复如今在本订阅挂上之前就落定，装载本身更不产生写
        // 事件。
        if (framingDirty && framingWritable) {
          final markers = await coordinator.readMarkersOutcome();
          if (markers.document.framingSelection != framingSource) {
            if (markers is DocumentReadOnly<MarkersDocument>) {
              _showDocumentReadOnly();
            }
            if (markers is WritableDocumentReadOutcome<MarkersDocument>) {
              final written = await markers.write(
                (context) =>
                    context.document.withFramingSelection(framingSource),
              );
              if (written is DocumentWriteRejected<MarkersDocument>) {
                _showDocumentReadOnly();
              }
            }
          }
        }
      } on Object {
        // 写失败不阻塞后续任务、不抛到 UI。
      }
    });
  }

  void _setPreviewSnap(bool value) {
    final model = _container.read(previewSnapEnabledProvider.notifier);
    if (_container.read(previewSnapEnabledProvider) == value) return;
    model.toggle();
  }

  void _setLayoutLocked(bool value) {
    final model = _container.read(layoutLockedProvider.notifier);
    if (_container.read(layoutLockedProvider) == value) return;
    model.toggle();
  }

  /// 只读文档、写回被挡时的呈现（既有短暂提示通道）：偏好改动没存进去
  /// 不静默。
  void _showDocumentReadOnly() => _container
      .read(noticeTriggerProvider(NoticeId.documentReadOnly).notifier)
      .show();

  /// 结束当前会话：把去抖窗口内待落盘的变更落盘，再取消订阅、丢弃 videoId
  /// （离开播放页与换会话都调用）。落盘不等待完成；要等落盘完成用 [flush]。
  void dispose() {
    final pending = _debouncePersistTimer;
    _debouncePersistTimer = null;
    if (pending != null) {
      // 先判窗口是否未收口再取消：cancel 之后计时器一律非活跃。
      final windowOpen = pending.isActive;
      pending.cancel();
      if (windowOpen) _persistPreferences();
    }
    _disposed = true;
    if (!_startedCompleter.isCompleted) _startedCompleter.complete();
    for (final subscription in _subscriptions) {
      subscription.close();
    }
    _subscriptions.clear();
    _videoId = null;
  }
}

/// `prefs.overlay` 原始数值 → 四格容器：一格的两个键同时存在才算已
/// 自定义；四格全未自定义时返回 null（= 无自定义位）。
///
/// 文件层的「缺一键即整格未自定义」由 codec 读取时归一（`_buildOverlay`
/// 的 pair）；这里的判空是类型层护栏——`OverlayPlacementFields` 也可由
/// 调用方直接构造，而 `Offset` 需要两个分量都非空。
OverlayPlacements? _placementsOf(OverlayPlacementFields? fields) {
  if (fields == null) return null;
  final offsets = <OverlayPlacementCell, Offset>{};
  void put(OverlayPlacementCell cell, double? dx, double? dy) {
    if (dx != null && dy != null) offsets[cell] = Offset(dx, dy);
  }

  put(OverlayPlacementCell.portraitNormal, fields.dx, fields.dy);
  put(
    OverlayPlacementCell.landscapeNormal,
    fields.landscapeDx,
    fields.landscapeDy,
  );
  put(OverlayPlacementCell.portraitCompare, fields.compareDx, fields.compareDy);
  put(
    OverlayPlacementCell.landscapeCompare,
    fields.landscapeCompareDx,
    fields.landscapeCompareDy,
  );
  if (offsets.isEmpty) return null;
  return OverlayPlacements(
    offsets: offsets,
    rectWidthFactor: fields.rectWidthFactor ?? 1.0,
    pendulumScale: fields.pendulumScale ?? 1.0,
  );
}

/// 四格容器 → `prefs.overlay` 原始数值（整组写的绝对终值；缺席的格两
/// 个键都落 null）。
OverlayPlacementFields _fieldsOf(OverlayPlacements placements) {
  Offset? at(OverlayPlacementCell cell) => placements.offsetFor(cell);
  return OverlayPlacementFields(
    dx: at(OverlayPlacementCell.portraitNormal)?.dx,
    dy: at(OverlayPlacementCell.portraitNormal)?.dy,
    landscapeDx: at(OverlayPlacementCell.landscapeNormal)?.dx,
    landscapeDy: at(OverlayPlacementCell.landscapeNormal)?.dy,
    compareDx: at(OverlayPlacementCell.portraitCompare)?.dx,
    compareDy: at(OverlayPlacementCell.portraitCompare)?.dy,
    landscapeCompareDx: at(OverlayPlacementCell.landscapeCompare)?.dx,
    landscapeCompareDy: at(OverlayPlacementCell.landscapeCompare)?.dy,
    rectWidthFactor: placements.rectWidthFactor,
    pendulumScale: placements.pendulumScale,
  );
}
