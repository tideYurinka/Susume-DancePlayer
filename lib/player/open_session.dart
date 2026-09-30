import 'dart:io';

import '../core/video_identity.dart';
import '../persistence/video_index.dart';
import '../persistence/local_document.dart';
import '../persistence/marker_document.dart';
import '../persistence/video_document_store.dart';

/// 定身份结果的三支语义（见词条「视频标识」）。
enum OpenIdentityKind {
  /// 条目命中且摘要相符：这支舞，身份取条目。
  matched,

  /// 条目命中但摘要不符：按新视频，身份取摘要，旧条目保留。
  contentChanged,

  /// 条目未命中（条目尚未落盘或索引不可读）：身份取摘要，按新视频语义
  /// 且可落盘——内容寻址使后台任务算出的身份与解析算出的必然相同。
  newVideo,
}

/// 打开会话（零框架纯库）：建立序列 = 定身份 → 读两份文档 → 建基线快照
/// → 置「已建立」。
///
/// 不引 Flutter、不引状态容器，只依赖被注入的索引存取、摘要计算与按视频
/// 文档写链；可脱离 widget 直测。建立序列不对索引条目做任何等待：
/// 「条目尚未落盘」不是错误状态，身份由内容摘要给出。
class OpenSession {
  OpenSession({
    required this.filePath,
    required this.indexStore,
    required this.hasher,
    required this.coordinatorFor,
  });

  /// 应用私有目录内视频副本路径（打开时的快速键，与索引条目一一对应）。
  final String filePath;

  /// 被注入的索引存取（打开时按路径取条目；索引不可读按未命中）。
  final VideoIndexStorage indexStore;

  /// 被注入的内容摘要计算（定身份用）。
  final ContentHasher hasher;

  /// 按视频文档写链的来源（按身份寻址两份文档）。生产传按视频文档协调器
  /// 注入点——会话不另建协调器实例，两份文档因此只有一条写链、一个写入者。
  final VideoDocumentCoordinator Function(String videoId) coordinatorFor;

  bool _established = false;
  String? _videoId;
  OpenIdentityKind? _identity;
  VideoIndexEntry? _entry;
  MarkersDocument _markers = const MarkersDocument.empty();
  MarkersDocument? _markersOnDisk;
  LocalDocument _local = const LocalDocument.empty();
  VideoDocumentCoordinator? _coordinator;

  /// 建立序列是否已走完（含摘要失败、文档不可读等无身份收场）。
  bool get established => _established;

  /// 身份（内容摘要或命中的条目 videoId）；无身份时为 null。
  String? get videoId => _videoId;

  /// 定身份结果；无身份时为 null。
  OpenIdentityKind? get identity => _identity;

  /// 命中且摘要相符的索引条目；其余支语义为 null——哈希不符时旧条目保留
  /// 但不被套用。
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
  /// 全部成功才落身份与基线（all-or-nothing）：摘要失败或文档不可读时
  /// 无身份、无落盘目标，[established] 仍为真（序列已走完）。
  Future<void> establish() async {
    final entry = await _loadEntryByPath();
    final String digest;
    try {
      digest = await hasher.hashFile(File(filePath));
    } on Object {
      _established = true;
      return; // 摘要失败：无身份，按空态且不落盘（行为不变）。
    }
    final matched = entry != null && entry.videoId == digest;
    final videoId = matched ? entry.videoId : digest;
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
    _videoId = videoId;
    if (matched) {
      _identity = OpenIdentityKind.matched;
      _entry = entry;
    } else {
      _identity = entry == null
          ? OpenIdentityKind.newVideo
          : OpenIdentityKind.contentChanged;
    }
    _markers = markers;
    _local = local;
    _coordinator = coordinator;
    _established = true;
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
