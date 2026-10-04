import 'dart:async';

import '../annotation/note_sticker.dart';
import 'video_index.dart' show VideoIndexEntry;
import 'annotation_sections.dart';
import 'document_read_outcome.dart';
import 'local_document.dart';
import 'marker_document.dart';
import 'song_signature.dart';
import 'video_document_store.dart';

/// 一次标注编辑的段级 diff（保存编排的保存单元）。
///
/// 各段 null = 该段本次未变更；非 null 段值为**绝对终值**（不是增量），
/// 合并与补写因此总是安全。四条臂与文件段一一对应：markers 侧
/// [corrections] / [annotations] / [notes] 三条，local 侧 [session] 一条。
class AnnotationSectionDiff {
  const AnnotationSectionDiff({
    this.corrections,
    this.annotations,
    this.session,
    this.notes,
  });

  /// markers `corrections` 段（平移量 + 八拍锚点）。
  final MarkerCorrectionsValue? corrections;

  /// markers `annotations` 段（首尾 + 分段线 + 半拍线 + 重点 + 局部镜像
  /// 片段）。
  final MarkerAnnotationsValue? annotations;

  /// local `session` 段（熟练度 + 激活学习段，绝对终值）。
  final LocalSessionValue? session;

  /// markers `notes` 段（备注贴纸列表，绝对终值整段写回）。
  final List<NoteSticker>? notes;

  bool get isEmpty =>
      corrections == null &&
      annotations == null &&
      session == null &&
      notes == null;
}

/// 标注编辑提交点钩子接口（编辑器面向本接口提交 diff）。
abstract interface class AnnotationSaveSink {
  /// 入队一次完成编辑的段级 diff（不等待落盘完成）。
  void save(AnnotationSectionDiff diff);

  /// 强制落盘挂起变更（切后台/退出播放器调用）；无挂起为空操作。
  Future<void> flush();
}

/// markers 首建初值：index 的署名缓存 + 两个镜像开关的过渡值。
class AnnotationSaveSeed {
  const AnnotationSaveSeed({
    this.signature,
    this.mirrored = false,
    this.localMirrorEnabled = true,
  });

  /// 由打开会话给出的条目取首建初值：条目为 null（会话无身份）时按缺省，
  /// 不套用旧条目。
  factory AnnotationSaveSeed.fromEntry(VideoIndexEntry? entry) => entry == null
      ? const AnnotationSaveSeed()
      : AnnotationSaveSeed(
          signature: entry.signatureCache,
          mirrored: entry.mirrored,
          localMirrorEnabled: entry.localMirrorEnabled,
        );

  /// index 条目的署名缓存（未署名为 null）。
  final SongSignature? signature;

  /// index 条目的镜像值（markers 未创建前的迁移过渡值）。
  final bool mirrored;

  /// index 条目的局部镜像总开关过渡值（缺省 `true` 与 markers
  /// 缺键兜底同口径——标注保存的首建不得把用户关掉的总开关冲成开）。
  final bool localMirrorEnabled;
}

/// markers 首建立底（镜像双写/标注首建共用）：文件不存在/
/// 损坏（[present] = false）时以 [seed]（index 署名缓存 + 两个镜像开关的
/// 过渡值）立底，出生即带完整署名与镜像组态；文件已存在则原样返回（不触碰
/// 现值）。存在但全字段为 v1 缺省值的文件按「存在」对待——该文件不含任何
/// 现值信息，与 index 缓存不冲突。
MarkersDocument firstBuildSeeded(
  MarkersDocument current, {
  required bool present,
  required AnnotationSaveSeed seed,
}) => present
    ? current
    : current
          .withMirrored(seed.mirrored)
          .withLocalMirrorEnabled(seed.localMirrorEnabled)
          .withSignature(seed.signature);

/// 到期合并写的调度 seam（生产用 [TimerSaveScheduler]，测试注入手动/
/// fake 时钟实现控制合并窗口）。
abstract interface class AnnotationSaveScheduler {
  /// 到期执行 [task]。
  void schedule(Duration delay, void Function() task);

  /// 取消当前挂起的到期回调（无挂起时为空操作）。
  void cancel();
}

/// [AnnotationSaveScheduler] 的生产实现：单 [Timer]。
class TimerSaveScheduler implements AnnotationSaveScheduler {
  Timer? _timer;

  @override
  void schedule(Duration delay, void Function() task) {
    _timer = Timer(delay, task);
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// 标注保存编排器：标注编辑提交点钩子的落盘执行端。
///
/// 语义：每次**完成**的编辑提交经 [save] 入队；
/// 同类 burst 合并 latest-wins（到期窗口内只落盘一次、写终态），拖动
/// 中间态由提交点过滤、不入队；[flush] 供切后台/退出播放器强制落盘；
/// 写失败静默吞掉、清空挂起、不阻塞后续保存（diff 为绝对值，补写即
/// 恢复一致）。
///
/// markers 首建（文件不存在/损坏）以 [seed] 供给的 index 署名缓存 +
/// 镜像过渡值为初值，只在首个 markers 写时取一次；文件已存在则完全不
/// 触碰署名/镜像现值。
class AnnotationSaveOrchestrator implements AnnotationSaveSink {
  AnnotationSaveOrchestrator({
    required VideoDocumentCoordinator coordinator,
    AnnotationSaveScheduler? scheduler,
    Future<AnnotationSaveSeed> Function()? seed,
    void Function(DocumentReadOnlyReason reason)? onWriteRejected,
    this.burstDelay = const Duration(milliseconds: 300),
  }) {
    _coordinator = coordinator;
    _scheduler = scheduler ?? TimerSaveScheduler();
    _seed = seed;
    _onWriteRejected = onWriteRejected;
  }

  late final VideoDocumentCoordinator _coordinator;
  late final AnnotationSaveScheduler _scheduler;
  late final Future<AnnotationSaveSeed> Function()? _seed;
  late final void Function(DocumentReadOnlyReason reason)? _onWriteRejected;

  /// burst 合并窗口：窗口内的连续入队只触发一次合并写。
  final Duration burstDelay;

  // 挂起合并区（latest-wins：各段独立覆盖为最新绝对终值）。
  MarkerCorrectionsValue? _pendingCorrections;
  MarkerAnnotationsValue? _pendingAnnotations;
  LocalSessionValue? _pendingSession;
  List<NoteSticker>? _pendingNotes;

  bool _scheduled = false;
  bool _seedApplied = false;

  @override
  void save(AnnotationSectionDiff diff) {
    if (diff.isEmpty) return;
    if (diff.corrections != null) _pendingCorrections = diff.corrections;
    if (diff.annotations != null) _pendingAnnotations = diff.annotations;
    if (diff.session != null) _pendingSession = diff.session;
    if (diff.notes != null) _pendingNotes = diff.notes;
    if (!_scheduled) {
      _scheduled = true;
      _scheduler.schedule(burstDelay, () {
        _scheduled = false;
        unawaited(flush());
      });
    }
  }

  /// 强制落盘全部挂起变更（切后台/退出播放器调用）；无挂起为空操作。
  ///
  /// 写失败静默：吞掉异常、同样清空挂起（后续任一次保存以绝对值补写）。
  @override
  Future<void> flush() async {
    final corrections = _pendingCorrections;
    final annotations = _pendingAnnotations;
    final session = _pendingSession;
    final notes = _pendingNotes;
    _pendingCorrections = null;
    _pendingAnnotations = null;
    _pendingSession = null;
    _pendingNotes = null;
    _scheduler.cancel();
    _scheduled = false;

    // markers 侧三条写回臂（corrections / annotations / notes），共写一次
    // 文件。写回只从**可写读结局**发生：只读结局没有写回成员，拒写沿
    // [onWriteRejected] 呈现（写不进去不再静默）。
    if (corrections != null || annotations != null || notes != null) {
      final seed = await _takeSeed();
      try {
        final outcome = await _coordinator.readMarkersOutcome();
        if (outcome is DocumentReadOnly<MarkersDocument>) {
          _onWriteRejected?.call(outcome.reason);
        } else if (outcome is WritableDocumentReadOutcome<MarkersDocument>) {
          final result = await outcome.write((context) async {
            var next = context.document;
            if (seed != null) {
              // 首建判定在串行写链内进行（文件不存在/损坏才立初值，存在
              // 即不触碰现值），不受并发首写竞态影响。
              next = firstBuildSeeded(
                next,
                present: context.present,
                seed: seed,
              );
            }
            if (annotations != null) next = next.withAnnotations(annotations);
            if (corrections != null) next = next.withCorrections(corrections);
            if (notes != null) next = next.withNotes(notes);
            return next;
          });
          if (result is DocumentWriteRejected<MarkersDocument>) {
            _onWriteRejected?.call(result.reason);
          }
        }
      } on Object {
        // markers 写失败不抛 UI；local 写独立进行，互不拖累。
      }
    }
    // local 侧一条写回臂（session）。
    if (session != null) {
      try {
        // 保存编排只写 local 的 `session` 段（段与写入者
        // 一一对应，不触碰 `prefs` 段的编辑偏好）。
        final outcome = await _coordinator.readLocalOutcome();
        if (outcome is DocumentReadOnly<LocalDocument>) {
          _onWriteRejected?.call(outcome.reason);
        } else if (outcome is WritableDocumentReadOutcome<LocalDocument>) {
          final result = await outcome.write(
            (context) => context.document.withSession(session),
          );
          if (result is DocumentWriteRejected<LocalDocument>) {
            _onWriteRejected?.call(result.reason);
          }
        }
      } on Object {
        // local 写失败同样静默（不阻塞后续任务）。
      }
    }
  }

  /// 首个 markers 写时取一次首建初值；之后恒为 null（不覆盖现值）。
  Future<AnnotationSaveSeed?> _takeSeed() async {
    if (_seedApplied) return null;
    _seedApplied = true;
    final seed = _seed;
    if (seed == null) return null;
    try {
      return await seed();
    } on Object {
      // 初值供给失败按空初值首建，不阻塞本次标注落盘。
      return null;
    }
  }
}
