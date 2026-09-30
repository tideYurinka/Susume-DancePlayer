import 'dart:async';

import 'package:flutter/foundation.dart';

import '../persistence/video_index.dart';
import '../persistence/annotation_save_orchestrator.dart'
    show AnnotationSaveSeed, firstBuildSeeded;
import '../persistence/document_read_outcome.dart';
import '../persistence/marker_document.dart';
import '../persistence/song_signature.dart';
import '../persistence/video_document_store.dart';

/// 歌曲署名会话控制器（改消费打开会话的
/// 已确认身份）：打开视频解析署名现值、导入命名/顶栏改名的持久化执行端。
///
/// - [startForFile]：消费打开会话给出的已确认身份（[videoId] 与 [entry]，
///   不再自行按路径轮询索引条目）；markers 存在 → 以 markers 署名为准并
///   回写 index 署名缓存（同步规则）；无 markers → 用
///   会话给出的命中条目署名缓存（null = 未署名，标题回退文件名）。
/// - [applySignature]：命名/改名提交。净化后更新内存态并双写——先写
///   index 署名缓存，再经协调器 patch markers（markers 不存在/损坏则
///   按 05 首建初值规则以 index 署名缓存 + 镜像过渡值立底，出生即带
///   完整署名与镜像）。markers 写入锚定会话给出的 videoId；写失败静默
///   （内存态已更新，不阻塞 UI）。
///
/// 与 [MirrorController] 同一先例：控制器不持有索引所有权，[dispose]
/// 只标记退出。
class SongSignatureController extends ChangeNotifier {
  SongSignatureController(
    this._indexStore, {
    this.coordinatorFor,
    this.onWriteRejected,
  });

  final VideoIndexStorage _indexStore;

  /// markers 写回被拒（只读文档 / 读与写之间换成只读文件）的呈现缝：
  /// 装配处接到既有短暂提示通道。null = 无提示环境（控制器直测）。
  final void Function()? onWriteRejected;

  /// 按视频文档协调器工厂（family 参数 = videoId）。null = 未接协调器
  /// 的环境只写 index（未按视频接好持久化的测试环境零增量，先例同
  /// [MirrorController.coordinator]）。
  final VideoDocumentCoordinator? Function(String videoId)? coordinatorFor;

  SongSignature? _signature;
  String? _filePath;
  String? _videoId;

  /// 会话给出的已确认条目（仅摘要相符时非空）：无 markers 时的署名现值
  /// 与首建初值只读它——摘要不符 / 无条目时按新视频，不套用旧条目。
  VideoIndexEntry? _entry;
  bool _disposed = false;

  /// 命名/改名提交落定的订阅者（与 [notifyListeners] 的解析通知区分）：
  /// 提交是署名域自己知道的事实，统计域等消费方订阅它做署名快照迁移。
  final List<void Function(SongSignature applied)> _commitListeners = [];

  /// 当前署名（null = 未署名；标题栏回退文件名）。
  SongSignature? get signature => _signature;

  /// 当前视频身份（打开会话给出；null = 会话未识别身份）。练舞统计的
  /// 记账关联与改名写-through 消费。
  String? get videoId => _videoId;

  /// 打开视频后的解析完成（测试同步点）。
  Future<void> get started => _startedCompleter.future;
  Completer<void> _startedCompleter = Completer<void>();

  /// 打开视频后调用：消费打开会话给出的已确认身份并解析署名现值（见类
  /// 文档）。会话未识别身份（[videoId] 为 null）时保持未署名回退，不抛错、
  /// 不阻塞播放。
  Future<void> startForFile(
    String filePath, {
    required String? videoId,
    VideoIndexEntry? entry,
  }) async {
    _disposed = false;
    _startedCompleter = Completer<void>();
    _filePath = filePath;
    _videoId = videoId;
    _entry = entry;
    _signature = null;
    if (videoId != null) {
      await _resolveSignature();
    }
    if (!_startedCompleter.isCompleted) _startedCompleter.complete();
  }

  Future<void> _resolveSignature() async {
    final coordinatorFor = this.coordinatorFor;
    final videoId = _videoId;
    final entry = _entry;
    if (coordinatorFor != null && videoId != null) {
      final coordinator = coordinatorFor(videoId);
      if (coordinator != null) {
        try {
          final markers = await coordinator.readMarkersOrNull();
          if (markers != null) {
            _signature = markers.signature;
            notifyListeners();
            // 同步规则：markers 存在 → 以其署名为准回写 index 缓存。
            if (entry != null && entry.signatureCache != markers.signature) {
              await _indexStore.update(
                (index) => index.setSignatureCacheByFilePath(
                  _filePath!,
                  markers.signature,
                ),
              );
            }
            return;
          }
        } on Object {
          // markers 侧不可读：退回 index 缓存路径。
        }
      }
    }
    _signature = entry?.signatureCache;
    notifyListeners();
  }

  /// 命名/改名提交：净化（歌曲名空回退 [fallbackSong]）后立即生效于
  /// 内存态，并双写 index + markers（见类文档）。落盘后回调提交订阅者
  /// （[addCommitListener]，写-through 消费方据此迁移署名快照），返回净化
  /// 后的署名。
  Future<SongSignature> applySignature(
    SongSignature raw, {
    required String fallbackSong,
  }) async {
    final sanitized = sanitizeSignature(raw, fallbackSong: fallbackSong);
    _signature = sanitized;
    notifyListeners();
    await _persist(sanitized);
    for (final listener in List.of(_commitListeners)) {
      listener(sanitized);
    }
    return sanitized;
  }

  /// 订阅「命名/改名提交落定」（与 [notifyListeners] 的解析通知区分）：
  /// 提交写盘后收到净化值。仅供需要跟随提交做写-through 的域使用。
  void addCommitListener(void Function(SongSignature applied) listener) {
    _commitListeners.add(listener);
  }

  /// 摘除提交订阅（先例同 [MirrorController] 的监听收尾）。
  void removeCommitListener(void Function(SongSignature applied) listener) {
    _commitListeners.remove(listener);
  }

  /// 双写持久化：index 署名缓存按路径写，且只在索引条目与已确认身份一致时
  /// 才写（条目未落盘 = 无操作，缺省由下次打开经 markers 回写补齐；摘要不符
  /// 时旧条目保留、不被写）；markers 锚定会话给出的 videoId。写失败静默，
  /// 不抛到 UI。
  Future<void> _persist(SongSignature signature) async {
    final filePath = _filePath;
    final videoId = _videoId;
    if (filePath == null || videoId == null) return;
    try {
      await _indexStore.update((current) {
        final entry = current.findByFilePath(filePath);
        if (entry == null || entry.videoId != videoId) return current;
        return current.setSignatureCacheByFilePath(filePath, signature);
      });
    } on Object {
      // 写盘失败：放弃（内存态已更新，下次打开重试），不抛到 UI。
      return;
    }
    await _writeMarkers(signature);
  }

  /// 署名双写 markers：文件不存在/损坏 → 以会话给出的命中条目署名缓存 +
  /// 镜像过渡值立首建初值（出生即带完整署名与镜像），随后写入本次署名。
  /// 首建判定在协调器串行写链内进行；写失败静默（index 缓存兜底）。
  Future<void> _writeMarkers(SongSignature signature) async {
    final coordinatorFor = this.coordinatorFor;
    final videoId = _videoId;
    if (coordinatorFor == null || videoId == null || _disposed) return;
    try {
      final coordinator = coordinatorFor(videoId);
      if (coordinator == null) return;
      final entry = _entry;
      final outcome = await coordinator.readMarkersOutcome();
      if (outcome is DocumentReadOnly<MarkersDocument>) {
        onWriteRejected?.call();
        return;
      }
      if (outcome is! WritableDocumentReadOutcome<MarkersDocument>) return;
      final result = await outcome.write((context) {
        final seeded = firstBuildSeeded(
          context.document,
          present: context.present,
          seed: AnnotationSaveSeed.fromEntry(entry),
        );
        return seeded.withSignature(signature);
      });
      if (result is DocumentWriteRejected<MarkersDocument>) {
        onWriteRejected?.call();
      }
    } on Object {
      // markers 写失败静默：index 署名缓存兜底。
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _commitListeners.clear();
    super.dispose();
  }
}
