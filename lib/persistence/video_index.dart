import 'dart:async';
import 'dart:io';

import '../core/atomic_json_file.dart';
import '../core/video_identity.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';
import 'song_signature.dart';

/// 视频索引条目的字段 id 枚举（穷尽 switch 的论域）。
///
/// 加字段 = 枚举加一项 → [VideoIndexEntry.codec] 的穷尽 switch 编译报错
/// → 键名/读/写/相等四处不可能漏。
enum VideoIndexEntryField {
  videoId,
  displayName,
  filePath,
  sizeBytes,
  fastKey,
  mirrored,
  mirrorAsked,
  localMirrorEnabled,
  lastOpenedAt,
  signatureCache,
  lastPositionMs,
}

/// 视频索引（index.json）——import 域。
///
/// 每条索引对应一个已导入视频（[VideoIndexEntry]）；导入时先用快速键
/// （大小 + 文件名）先行匹配立即恢复播放，后台哈希对账一致则刷新最近打开
/// 时间，不一致按新视频导入（旧条目保留）。打开一支已有的舞按 [filePath]
/// 命中条目即取身份，不读视频内容。
///
/// JSON 字段对应：
/// `videoId` ← video_id（内容 xxHash64）、`displayName` ← 显示名、
/// `filePath` ← 文件路径、`sizeBytes` ← 大小、`fastKey` ← 快速键、
/// `mirrored` ← 镜像状态、`mirrorAsked` ← 是否已询问过镜像、
/// `localMirrorEnabled` ← 局部镜像总开关过渡值（真值在 markers）、
/// `lastOpenedAt` ← 最近打开时间。
class VideoIndexEntry {
  const VideoIndexEntry({
    required this.videoId,
    required this.displayName,
    required this.filePath,
    required this.sizeBytes,
    required this.fastKey,
    required this.mirrored,
    this.mirrorAsked = false,
    this.localMirrorEnabled = true,
    required this.lastOpenedAt,
    this.signatureCache,
    this.lastPositionMs = 0,
    this.extra = const {},
  });

  /// 由一份已落位的**视频副本**与它的 [videoId] 新建条目：显示名、路径与
  /// 大小都取自这份副本，快速键由显示名与大小派生（[fastKeyFor]）——落条目
  /// 的字段清单只有这一处，导入首建与打开兜底补建共用。
  ///
  /// 镜像组态在这里落**缺省**（未作答）：同 videoId 已有条目时
  /// [VideoIndex.upsert] 经 [preservedMirrorStateOf] 保住既有组态，本条目
  /// 里的缺省因此不会把用户既有选择冲回默认——保留发生在合并那一步，不在
  /// 这里。
  factory VideoIndexEntry.forVideoCopy({
    required String videoId,
    required String displayName,
    required String filePath,
    required int sizeBytes,
    required DateTime lastOpenedAt,
  }) => VideoIndexEntry(
    videoId: videoId,
    displayName: displayName,
    filePath: filePath,
    sizeBytes: sizeBytes,
    fastKey: fastKeyFor(name: displayName, sizeBytes: sizeBytes),
    mirrored: false,
    lastOpenedAt: lastOpenedAt,
  );

  /// 视频标识：内容 xxHash64（小写十六进制）。
  final String videoId;

  /// 显示名（含扩展名，取自导入时的源文件名，不受私有目录去冲突命名影响）。
  final String displayName;

  /// 应用私有目录内视频副本的绝对路径。
  final String filePath;

  /// 视频大小（字节）。
  final int sizeBytes;

  /// 快速键（大小 + 文件名，见 [fastKeyFor]），打开时先行匹配用。
  final String fastKey;

  /// 镜像状态（默认否；询问/历史应用的「应用值」）。
  final bool mirrored;

  /// 是否已询问过镜像：区分「用户答过『否』」与「还没问过」。
  ///
  /// 首次导入时随内容摘要落条目（默认 false）；用户作答后由
  /// [VideoIndex.setMirrorAnswerByFilePath] 置 true。播放器打开时凭此判定
  /// 「首次打开需询问」还是「按历史应用」——不靠条目是否已落盘判定，
  /// 消除「条目落盘先于 resolve 导致首次打开被误判为有历史」的竞态。
  final bool mirrorAsked;

  /// 局部镜像总开关：与全局 [mirrored] 同一条过渡值通路——
  /// markers 未创建前的取值载体，markers 存在后真值在 `meta.localMirrorEnabled`
  /// （打开时以其为准并回写本缓存）。缺键兜底 `true`（与 markers 缺键口径
  /// 一致：新文件与首建初值都出生为「开」）。
  final bool localMirrorEnabled;

  final DateTime lastOpenedAt;

  /// 署名缓存：markers 未创建前的名字载体与快速标签；
  /// markers 存在后真值在 markers（打开时以其为准并回写本缓存）。
  /// null 表示未署名（标题栏回退文件名）。
  final SongSignature? signatureCache;

  /// 续播位置毫秒：上次离开播放器时记录，下次打开自动续播；
  /// 上次到尾视为从头。0 表示无续播位置。
  final int lastPositionMs;

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 条目编解码器：字段声明（键名/读/写/相等）在一处的穷尽 switch。
  static final RecordCodec<VideoIndexEntry, VideoIndexEntryField> codec =
      RecordCodec<VideoIndexEntry, VideoIndexEntryField>(
        ids: VideoIndexEntryField.values,
        decl: (id) => switch (id) {
          VideoIndexEntryField.videoId => FieldDecl(
            key: 'videoId',
            read: (json) => json['videoId'] as String,
            write: (v) => v.videoId,
            equal: (a, b) => a.videoId == b.videoId,
          ),
          VideoIndexEntryField.displayName => FieldDecl(
            key: 'displayName',
            read: (json) => json['displayName'] as String,
            write: (v) => v.displayName,
            equal: (a, b) => a.displayName == b.displayName,
          ),
          VideoIndexEntryField.filePath => FieldDecl(
            key: 'filePath',
            read: (json) => json['filePath'] as String,
            write: (v) => v.filePath,
            equal: (a, b) => a.filePath == b.filePath,
          ),
          VideoIndexEntryField.sizeBytes => FieldDecl(
            key: 'sizeBytes',
            read: (json) => json['sizeBytes'] as int,
            write: (v) => v.sizeBytes,
            equal: (a, b) => a.sizeBytes == b.sizeBytes,
          ),
          VideoIndexEntryField.fastKey => FieldDecl(
            key: 'fastKey',
            read: (json) => json['fastKey'] as String,
            write: (v) => v.fastKey,
            equal: (a, b) => a.fastKey == b.fastKey,
          ),
          VideoIndexEntryField.mirrored => FieldDecl(
            key: 'mirrored',
            read: (json) => json['mirrored'] as bool,
            write: (v) => v.mirrored,
            equal: (a, b) => a.mirrored == b.mirrored,
          ),
          VideoIndexEntryField.mirrorAsked => FieldDecl(
            key: 'mirrorAsked',
            // 旧索引文件无此字段 → 视为未询问（升级后首次打开会再询问一次）。
            read: (json) => json['mirrorAsked'] as bool? ?? false,
            write: (v) => v.mirrorAsked,
            equal: (a, b) => a.mirrorAsked == b.mirrorAsked,
          ),
          VideoIndexEntryField.localMirrorEnabled => FieldDecl(
            key: 'localMirrorEnabled',
            // 旧索引文件无此字段 → 缺省「开」（与 markers 同字段兜底同口径）。
            read: (json) => json['localMirrorEnabled'] as bool? ?? true,
            write: (v) => v.localMirrorEnabled,
            equal: (a, b) => a.localMirrorEnabled == b.localMirrorEnabled,
          ),
          VideoIndexEntryField.lastOpenedAt => FieldDecl(
            key: 'lastOpenedAt',
            read: (json) => DateTime.parse(json['lastOpenedAt'] as String),
            write: (v) => v.lastOpenedAt.toIso8601String(),
            equal: (a, b) => a.lastOpenedAt == b.lastOpenedAt,
          ),
          VideoIndexEntryField.signatureCache => FieldDecl(
            key: 'signatureCache',
            // 旧条目缺字段兜底：署名缺失 = 未署名。
            read: (json) {
              final raw = json['signatureCache'];
              return raw is Map<String, dynamic>
                  ? SongSignature.fromJson(raw)
                  : null;
            },
            write: (v) => v.signatureCache?.toJson(),
            equal: (a, b) => a.signatureCache == b.signatureCache,
          ),
          VideoIndexEntryField.lastPositionMs => FieldDecl(
            key: 'lastPositionMs',
            // 旧条目缺字段兜底：位置缺失 = 0。
            read: (json) => json['lastPositionMs'] as int? ?? 0,
            write: (v) => v.lastPositionMs,
            equal: (a, b) => a.lastPositionMs == b.lastPositionMs,
          ),
        },
        build: (values) => VideoIndexEntry(
          videoId: values[VideoIndexEntryField.videoId]! as String,
          displayName: values[VideoIndexEntryField.displayName]! as String,
          filePath: values[VideoIndexEntryField.filePath]! as String,
          sizeBytes: values[VideoIndexEntryField.sizeBytes]! as int,
          fastKey: values[VideoIndexEntryField.fastKey]! as String,
          mirrored: values[VideoIndexEntryField.mirrored]! as bool,
          mirrorAsked: values[VideoIndexEntryField.mirrorAsked]! as bool,
          localMirrorEnabled:
              values[VideoIndexEntryField.localMirrorEnabled]! as bool,
          lastOpenedAt: values[VideoIndexEntryField.lastOpenedAt]! as DateTime,
          signatureCache:
              values[VideoIndexEntryField.signatureCache] as SongSignature?,
          lastPositionMs: values[VideoIndexEntryField.lastPositionMs]! as int,
        ),
        extraOf: (v) => v.extra,
        withExtra: (v, extra) => v.copyWith(extra: extra),
      );

  Map<String, dynamic> toJson() => codec.encode(this);

  factory VideoIndexEntry.fromJson(Map<String, dynamic> json) =>
      codec.decode(json);

  VideoIndexEntry copyWith({
    String? displayName,
    String? filePath,
    int? sizeBytes,
    String? fastKey,
    bool? mirrored,
    bool? mirrorAsked,
    bool? localMirrorEnabled,
    DateTime? lastOpenedAt,
    SongSignature? signatureCache,
    bool clearSignatureCache = false,
    int? lastPositionMs,
    Map<String, Object?>? extra,
  }) {
    return VideoIndexEntry(
      videoId: videoId,
      displayName: displayName ?? this.displayName,
      filePath: filePath ?? this.filePath,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      fastKey: fastKey ?? this.fastKey,
      mirrored: mirrored ?? this.mirrored,
      mirrorAsked: mirrorAsked ?? this.mirrorAsked,
      localMirrorEnabled: localMirrorEnabled ?? this.localMirrorEnabled,
      lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
      signatureCache: clearSignatureCache
          ? null
          : signatureCache ?? this.signatureCache,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      extra: extra ?? this.extra,
    );
  }

  /// 保留 [other] 的镜像组态（[mirrored]/[mirrorAsked]/[localMirrorEnabled]），
  /// 其余字段取本条目——导入刷新场景用：镜像组态**按 video_id 存取**，导入
  /// 新落盘的条目不得把用户既有选择冲回缺省。字段清单集中在这一处，新增
  /// 镜像类字段只改这里（[VideoIndex.upsert] 因此不必手抄字段表）。
  VideoIndexEntry preservedMirrorStateOf(VideoIndexEntry other) => copyWith(
    mirrored: other.mirrored,
    mirrorAsked: other.mirrorAsked,
    localMirrorEnabled: other.localMirrorEnabled,
  );

  @override
  bool operator ==(Object other) =>
      other is VideoIndexEntry && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// 视频索引的内存模型（不可变）。
class VideoIndex {
  const VideoIndex({required this.entries, this.extra = const {}});

  static const empty = VideoIndex(entries: []);

  /// 视频索引的版本链：地板 2，链为空（地板 = 本版）。v2：
  /// 标识换代（xxHash64）一次性丢弃旧索引属历史、已在地板之下。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 2,
  );

  final List<VideoIndexEntry> entries;

  /// 文档级陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  static final ListDocumentCodec<
    VideoIndex,
    VideoIndexEntry,
    VideoIndexEntryField
  >
  _codec = ListDocumentCodec(
    policy: versionPolicy,
    listKey: 'entries',
    elementCodec: VideoIndexEntry.codec,
    empty: () => VideoIndex.empty,
    build: (elements) => VideoIndex(entries: elements),
    listOf: (doc) => doc.entries,
    extraOf: (doc) => doc.extra,
    withExtra: (doc, extra) => VideoIndex(entries: doc.entries, extra: extra),
  );

  /// 以新条目列表重建索引：陌生键保底区随行。漏带保底区 = 静默丢陌生
  /// 键（正是保底区要挡住的失败模式），故所有变更方法经此一处收口。
  VideoIndex _withEntries(List<VideoIndexEntry> updated) =>
      VideoIndex(entries: updated, extra: extra);

  /// 快速键匹配：命中条目按最近打开时间倒序（最新在前）。
  List<VideoIndexEntry> byFastKey(String fastKey) {
    final hits = entries.where((e) => e.fastKey == fastKey).toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return hits;
  }

  /// 按视频标识（内容哈希）精确查找。
  VideoIndexEntry? findById(String videoId) {
    for (final e in entries) {
      if (e.videoId == videoId) return e;
    }
    return null;
  }

  /// 按应用私有目录副本路径精确查找（打开时定身份与镜像历史恢复用）。
  ///
  /// 导入后副本路径不变且与 videoId 一一对应，打开一支舞以自身 source 路径
  /// 匹配即可取到条目与镜像偏好——不读视频内容、不等任何摘要。
  VideoIndexEntry? findByFilePath(String filePath) {
    for (final e in entries) {
      if (e.filePath == filePath) return e;
    }
    return null;
  }

  /// 命中首个满足 [test] 的条目并以 [change] 结果替换（返回 null = 删除该
  /// 条目）；未命中原样返回（同一实例，调用方据此跳过写盘）。
  VideoIndex _mapEntry(
    bool Function(VideoIndexEntry entry) test,
    VideoIndexEntry? Function(VideoIndexEntry entry) change,
  ) {
    final i = entries.indexWhere(test);
    if (i == -1) return this;
    final next = change(entries[i]);
    final updated = entries.toList();
    if (next == null) {
      updated.removeAt(i);
    } else {
      updated[i] = next;
    }
    return _withEntries(updated);
  }

  /// 按应用私有目录副本路径记录镜像作答（持久化路径）。
  ///
  /// 播放器打开时只有副本路径，按路径找条目写入镜像状态并标记
  /// 「已询问」；索引里没有该副本路径的条目时原样返回（同一实例，调用方
  /// 据此跳过写盘，不重试）。
  VideoIndex setMirrorAnswerByFilePath(
    String filePath, {
    required bool mirrored,
  }) => _mapEntry(
    (e) => e.filePath == filePath,
    (e) => e.copyWith(mirrored: mirrored, mirrorAsked: true),
  );

  /// 回写镜像缓存（同步规则）：markers 存在的打开场景
  /// 以 markers 镜像为准回写 index 过渡值；不触碰「已询问」标记
  /// （markers 一旦存在即不再询问，该标记只由作答路径设置）。未命中
  /// 原样返回（同一实例，调用方据此跳过写盘）。
  VideoIndex setMirroredByFilePath(String filePath, {required bool mirrored}) =>
      _mapEntry(
        (e) => e.filePath == filePath,
        (e) => e.copyWith(mirrored: mirrored),
      );

  /// 写入局部镜像总开关过渡值——两条通路共用：切换时双写 index
  /// 侧，以及 markers 为真值的打开场景按 markers 现值回写缓存。与
  /// [setMirroredByFilePath] 同款：未命中原样返回（同一实例，调用方据此
  /// 跳过写盘），不触碰「已询问」标记。
  VideoIndex setLocalMirrorEnabledByFilePath(
    String filePath, {
    required bool localMirrorEnabled,
  }) => _mapEntry(
    (e) => e.filePath == filePath,
    (e) => e.copyWith(localMirrorEnabled: localMirrorEnabled),
  );

  /// 按应用私有目录副本路径写入署名缓存（导入命名/改名双写
  /// index 侧；markers 真值打开时的回写亦走此入口）。未命中原样返回
  /// （同一实例，调用方据此跳过写盘）。
  VideoIndex setSignatureCacheByFilePath(
    String filePath,
    SongSignature? signature,
  ) => _mapEntry(
    (e) => e.filePath == filePath,
    (e) => e.copyWith(
      signatureCache: signature,
      clearSignatureCache: signature == null,
    ),
  );

  /// 写入 [entry]：同 videoId 已存在时以新条目替换（路径/时间刷新），
  /// 否则追加。同内容（同 videoId）不会产生重复条目；替换时保留既有
  /// 条目的镜像组态（镜像按 video_id 存取，见
  /// [VideoIndexEntry.preservedMirrorStateOf]）。
  VideoIndex upsert(VideoIndexEntry entry) => findById(entry.videoId) == null
      ? _withEntries([...entries, entry])
      : _mapEntry(
          (e) => e.videoId == entry.videoId,
          (e) => entry.preservedMirrorStateOf(e),
        );

  /// 以 [entry]（同 videoId）整体替换既有条目；未命中原样返回（同一实例，
  /// 调用方据此跳过写盘）。供「以权威源整条回写」场景使用（如打开恢复时
  /// 以 markers 的署名/镜像回写 index 缓存）——[upsert] 会保留
  /// 既有镜像值，不适用本场景。
  VideoIndex replaceEntry(VideoIndexEntry entry) =>
      _mapEntry((e) => e.videoId == entry.videoId, (e) => entry);

  /// 删除指定 videoId 的条目（舞被删除时索引侧的唯一写入口）；未命中
  /// 原样返回（同一实例，调用方据此跳过写盘）。陌生键保底区随行。
  VideoIndex remove(String videoId) =>
      _mapEntry((e) => e.videoId == videoId, (e) => null);

  /// 刷新指定 videoId 条目的显示信息与最近打开时间；未命中原样返回
  /// （同一实例，调用方据此跳过写盘）。
  ///
  /// 仅更新 [displayName]/[fastKey]/[lastOpenedAt]，videoId、文件路径、
  /// 大小与镜像组态（含「已询问」标记）保持不变（快速键命中、哈希
  /// 一致的场景）——保留其余字段靠 [VideoIndexEntry.copyWith] 自身缺省，
  /// 不手抄字段表（新增字段不可能在刷新路径被漏掉）。
  VideoIndex refresh(
    String videoId, {
    String? displayName,
    String? fastKey,
    DateTime? lastOpenedAt,
  }) => _mapEntry(
    (e) => e.videoId == videoId,
    (e) => e.copyWith(
      displayName: displayName ?? e.displayName,
      fastKey: fastKey ?? e.fastKey,
      lastOpenedAt: lastOpenedAt ?? e.lastOpenedAt,
    ),
  );

  Map<String, dynamic> toJson() => _codec.encode(this);

  factory VideoIndex.fromJson(Map<String, dynamic> json) => _codec.decode(json);
}

/// 视频索引的读写能力（import 域对外暴露的最小接口）。
///
/// 与实现（[VideoIndexStore] 真实文件存储）解耦，供镜像询问/历史应用
/// （player 域）等消费方注入：widget 测试用内存实现
/// （`test/helpers/in_memory_video_index_storage.dart`），避免真实文件 IO
/// 在 fake async 时钟下不可完成的问题。
abstract interface class VideoIndexStorage {
  /// 读取当前索引；文件缺失/损坏等不可读情况由实现兜底（空索引）。
  Future<VideoIndex> load();

  /// 串行「读 → [mutate] → 写」；[mutate] 返回与入参相同实例时跳过写盘。
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  );
}

/// index.json 的读写存储。
///
/// 文件不存在或损坏时视为空索引（不抛错，首次启动/升级兜底）；
/// [update] 通过内部写链串行化「读 → 改 → 写」，并发后台任务
/// （多次导入的哈希落盘）不会互相覆盖丢失条目。
class VideoIndexStore implements VideoIndexStorage {
  VideoIndexStore(FutureOr<File> file) : _atomic = AtomicJsonFile(file);

  /// 索引文件机制（原子读/原子写/串行写链）委托给共享深模块。
  final AtomicJsonFile _atomic;

  @override
  Future<VideoIndex> load() async {
    // 文件缺失/损坏由 AtomicJsonFile 兜底为空 Map（空 Map 解析为空索引）；
    // 字段类型错误仍在本层兜底为空索引。
    try {
      return VideoIndex.fromJson(await _atomic.read());
    } on TypeError {
      return VideoIndex.empty;
    }
  }

  /// 串行「读 → [mutate] → 写」：返回写盘后的索引。
  ///
  /// [mutate] 返回与入参相同实例时跳过写盘（未变更）。盘上文件不可写
  /// （高于本版 / 版本头读不出，见 [DocumentVersionPolicy.isWritable]）时
  /// 跳过写盘、返回「认识多少读多少」的读取结果。
  /// 写盘先落临时文件再原子重命名，避免读侧（打开视频时快速键匹配）
  /// 读到半截 JSON。
  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) {
    var result = VideoIndex.empty;
    final run = _atomic.mutate((json, {required bool present}) async {
      VideoIndex current;
      try {
        current = VideoIndex.fromJson(json);
      } on TypeError {
        current = VideoIndex.empty;
      }
      if (!VideoIndex.versionPolicy.isWritable(json)) {
        result = current;
        return;
      }
      final next = await mutate(current);
      result = next;
      if (identical(next, current)) return; // 未变更：内容不变即跳写。
      json
        ..clear()
        ..addAll(next.toJson());
    });
    return run.then((_) => result);
  }
}
