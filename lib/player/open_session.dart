import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/video_identity.dart';
import '../persistence/video_index.dart';
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart';
import '../persistence/video_document_store.dart';

/// 定身份结果的两支语义（打开路径收窄后；见词条「视频标识」）。
enum OpenIdentityKind {
  /// 按路径命中条目：这支舞，身份取条目——不读视频内容、不校验条目身份与
  /// 文件内容相符（那条对账只保留在导入域）。
  entryHit,

  /// 按路径查不到条目（索引写失败一类罕见情形）：兜底算一次摘要定身份，
  /// 并按算出的身份补建条目，使同一支舞再打开按路径命中、不再兜底。
  fallbackHash,
}

/// 打开会话（零框架纯库）：建立序列 = 按路径定身份 → 读两份文档 → 建基线快照
/// → 置「已建立」。
///
/// 不引 Flutter、不引状态容器，只依赖被注入的索引存取、摘要计算与按视频
/// 文档写链；可脱离 widget 直测。
///
/// 身份按路径由清单条目承载：命中即取条目身份，打开路径**全程不读视频
/// 内容**（不因视频大小而变慢，也不再校验「条目身份与文件内容相符」）。
/// 查不到条目才兜底读一次内容算出身份并补建条目；兜底也算不出（副本不在
/// 一类）→ 无身份空态、不落盘。建立序列不对索引条目做任何等待。
class OpenSession {
  OpenSession({
    required this.filePath,
    required this.indexStore,
    required this.hasher,
    required this.coordinatorFor,
    this.now = DateTime.now,
  });

  /// 应用私有目录内视频副本路径（打开时的快速键，与索引条目一一对应）。
  final String filePath;

  /// 被注入的索引存取（打开时按路径取条目；索引不可读按未命中）。
  final VideoIndexStorage indexStore;

  /// 被注入的内容摘要计算：只在按路径查不到条目时兜底调用一次。
  final ContentHasher hasher;

  /// 按视频文档写链的来源（按身份寻址两份文档）。生产传按视频文档协调器
  /// 注入点——会话不另建协调器实例，两份文档因此只有一条写链、一个写入者。
  final VideoDocumentCoordinator Function(String videoId) coordinatorFor;

  /// 时钟（补建条目时记最近打开时间；测试注入固定时间）。
  final DateTime Function() now;

  bool _established = false;
  String? _videoId;
  OpenIdentityKind? _identity;
  VideoIndexEntry? _entry;
  MarkersDocument _markers = const MarkersDocument.empty();
  MarkersDocument? _markersOnDisk;
  LocalDocument _local = const LocalDocument.empty();
  VideoDocumentCoordinator? _coordinator;

  /// 建立序列是否已走完（含兜底摘要失败、文档不可读等无身份收场）。
  bool get established => _established;

  /// 身份（命中条目的 videoId，或兜底算出的内容摘要）；无身份时为 null。
  String? get videoId => _videoId;

  /// 定身份结果；无身份时为 null。
  OpenIdentityKind? get identity => _identity;

  /// 打开时的索引条目：按路径命中的条目，或兜底定身份后补建的条目；两者
  /// 都不可得（兜底摘要失败，或副本读不到大小而无从补建）时为 null——该支
  /// 按新视频缺省值处理，不套用任何旧条目。
  VideoIndexEntry? get entry => _entry;

  /// 公开标记文件的基线快照。
  MarkersDocument get markers => _markers;

  /// 建立基线时公开标记文件**在盘**的内容；null = 打开时不存在（或损坏
  /// 不可读）。镜像 resolve 据此区分「打开前就有真值」与「本次打开期间才
  /// 首建」（首次导入的命名框）——后者不是镜像答案。
  MarkersDocument? get markersOnDisk => _markersOnDisk;

  /// 本地文档的基线快照。
  LocalDocument get local => _local;

  /// 按身份寻址的两份文档写链；无身份时为 null（无落盘目标）。
  VideoDocumentCoordinator? get coordinator => _coordinator;

  /// 是否已读得基线、可经 [coordinator] 落盘（等价于有身份）。
  bool get identified => _videoId != null;

  /// 走建立序列；调用方（宿主）在打开播放页时装配本会话。
  ///
  /// 全部成功才落身份与基线（all-or-nothing）：兜底摘要失败或文档不可读时
  /// 无身份、无落盘目标，[established] 仍为真（序列已走完）。
  Future<void> establish() async {
    final entry = await _loadEntryByPath();
    final String videoId;
    if (entry != null) {
      // 命中条目即取身份：打开路径不读视频内容、不校验条目身份与内容相符。
      videoId = entry.videoId;
      _identity = OpenIdentityKind.entryHit;
      _entry = entry;
    } else {
      // 兜底：按路径查不到条目（索引写失败一类罕见情形）才读一次内容。
      final String digest;
      try {
        digest = await hasher.hashFile(File(filePath));
      } on Object {
        _established = true;
        return; // 兜底摘要算不出（副本不在一类）：无身份空态、不落盘。
      }
      videoId = digest;
      _identity = OpenIdentityKind.fallbackHash;
      _entry = await _backfillEntry(digest);
    }
    final coordinator = coordinatorFor(videoId);
    final MarkersDocument markers;
    final LocalDocument local;
    try {
      // 经写链读，不另起一份裸读（同一读法只有一处）；在盘与否一并留下
      // （[markersOnDisk]）：缺文件 / 损坏即 null，由消费方按无真值处理。
      _markersOnDisk = await coordinator.readMarkersOrNull();
      markers = _markersOnDisk ?? const MarkersDocument.empty();
      local = await coordinator.readLocal();
    } on Object {
      _established = true;
      return; // 文档不可读（平台路径不可用等）：无基线即无身份可用。
    }
    _markers = markers;
    _local = local;
    _coordinator = coordinator;
    _videoId = videoId;
    _established = true;
  }

  /// 兜底定身份后补建条目：同一支舞再打开按路径命中，不再兜底。
  ///
  /// 按副本现算显示名、大小与快速键（身份与路径由本次打开给出）；大小取一次
  /// **同步** stat（不读内容、不落异步 IO——建立序列不因环境时钟而挂住）；
  /// 返回补建落定后的条目——同 videoId 已有条目时 [VideoIndex.upsert] 合并，
  /// 故返回的是合并结果（既有镜像组态保留）。
  ///
  /// 副本 stat 不到（真摘要算不出时走不到这里，桩实现下才会）或索引不可写
  /// → 本次打开照常（身份已定），下次打开再兜底一次，返回 null。
  Future<VideoIndexEntry?> _backfillEntry(String videoId) async {
    final int sizeBytes;
    try {
      sizeBytes = File(filePath).lengthSync();
    } on Object {
      return null;
    }
    final name = p.basename(filePath);
    final created = VideoIndexEntry(
      videoId: videoId,
      displayName: name,
      filePath: filePath,
      sizeBytes: sizeBytes,
      fastKey: fastKeyFor(name: name, sizeBytes: sizeBytes),
      mirrored: false,
      lastOpenedAt: now(),
    );
    try {
      final index = await indexStore.update(
        (current) => current.upsert(created),
      );
      return index.findById(videoId);
    } on Object {
      return null;
    }
  }

  /// 按打开路径取索引条目；索引不可读按未命中（不等条目）。
  Future<VideoIndexEntry?> _loadEntryByPath() async {
    try {
      return (await indexStore.load()).findByFilePath(filePath);
    } on Object {
      return null;
    }
  }
}
