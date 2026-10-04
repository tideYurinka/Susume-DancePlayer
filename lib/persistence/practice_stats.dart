import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/atomic_json_file.dart';
import '../core/local_day.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';
import 'song_signature.dart';

/// 会话合并间隔阈值（同视频间隔 <5 分钟并入开放会话；
/// 阈值常量可配、无 UI）。
const Duration kPracticeSessionMergeGap = Duration(minutes: 5);

/// 本地日所在自然周的周一零点（周一起算）：汇总卡「本周」与年热力图共用的
/// 唯一周起算口径。
DateTime practiceStatsWeekStart(DateTime day) =>
    DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));

/// 练习统计会话记录的字段 id 枚举（穷尽 switch 的论域）。
///
/// 加字段 = 枚举加一项 → [PracticeSessionRecord.codec] 的穷尽 switch
/// 编译报错 → 键名/读/写/相等四处不可能漏。署名三元组以三个平铺键
/// 存储于记录层（沿既有文件形状，不嵌套）。
enum PracticeSessionRecordField {
  start,
  videoId,
  signatureDancer,
  signatureSong,
  signatureRemark,
  wallSeconds,
}

/// 练习统计的会话记录（记录单元，`practice_stats.json`
/// 的 `sessions[]` 成员）。
///
/// 一条记录 = 一次连续会话：[start] 为会话内首次播放时刻（跨零点分桶的
/// 桶键 = 该时刻的本地日），署名以三元组**结构存储**（不存拼接串），
/// [wallSeconds] 为累计墙钟播放秒数（倍速不折算）。记录永不跨日：跨零点
/// 的播放按实际发生的日拆成多条。
@immutable
class PracticeSessionRecord {
  const PracticeSessionRecord({
    required this.start,
    required this.videoId,
    required this.signature,
    this.wallSeconds = 0,
    this.extra = const {},
  });

  /// 会话内首次播放时刻（本地时间）。
  final DateTime start;

  /// 视频内容哈希（video_id）。
  final String videoId;

  /// 署名快照：记录时刻的署名（未署名视频按回退文件名计入，与顶栏回退
  /// 规则一致）；删除视频后展示名来自本快照。
  final SongSignature signature;

  /// 累计墙钟播放秒数（小数；倍速不折算、暂停/拖动不计）。
  final double wallSeconds;

  /// [wallSeconds] 的 [Duration] 表示（微秒精度；倍速不折算口径的唯一换算）。
  Duration get wallDuration =>
      Duration(microseconds: (wallSeconds * 1e6).round());

  /// 陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 记录编解码器：字段声明（键名/读/写/相等）在一处的穷尽 switch。
  static final RecordCodec<PracticeSessionRecord, PracticeSessionRecordField>
  codec = RecordCodec<PracticeSessionRecord, PracticeSessionRecordField>(
    ids: PracticeSessionRecordField.values,
    decl: (id) => switch (id) {
      PracticeSessionRecordField.start => FieldDecl(
        key: 'start',
        read: (json) =>
            DateTime.tryParse(json['start'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        write: (v) => v.start.toIso8601String(),
        equal: (a, b) => a.start == b.start,
      ),
      PracticeSessionRecordField.videoId => FieldDecl(
        key: 'videoId',
        read: (json) => json['videoId'] as String? ?? '',
        write: (v) => v.videoId,
        equal: (a, b) => a.videoId == b.videoId,
      ),
      PracticeSessionRecordField.signatureDancer => FieldDecl(
        key: 'dancer',
        read: (json) => json['dancer'] as String? ?? '',
        write: (v) => v.signature.dancer,
        equal: (a, b) => a.signature.dancer == b.signature.dancer,
      ),
      PracticeSessionRecordField.signatureSong => FieldDecl(
        key: 'song',
        read: (json) => json['song'] as String? ?? '',
        write: (v) => v.signature.song,
        equal: (a, b) => a.signature.song == b.signature.song,
      ),
      PracticeSessionRecordField.signatureRemark => FieldDecl(
        key: 'remark',
        read: (json) => json['remark'] as String? ?? '',
        write: (v) => v.signature.remark,
        equal: (a, b) => a.signature.remark == b.signature.remark,
      ),
      PracticeSessionRecordField.wallSeconds => FieldDecl(
        key: 'wallSeconds',
        read: (json) => (json['wallSeconds'] as num?)?.toDouble() ?? 0.0,
        write: (v) => v.wallSeconds,
        equal: (a, b) => a.wallSeconds == b.wallSeconds,
      ),
    },
    build: (values) => PracticeSessionRecord(
      start: values[PracticeSessionRecordField.start]! as DateTime,
      videoId: values[PracticeSessionRecordField.videoId]! as String,
      signature: SongSignature(
        dancer: values[PracticeSessionRecordField.signatureDancer]! as String,
        song: values[PracticeSessionRecordField.signatureSong]! as String,
        remark: values[PracticeSessionRecordField.signatureRemark]! as String,
      ),
      wallSeconds: values[PracticeSessionRecordField.wallSeconds]! as double,
    ),
    extraOf: (v) => v.extra,
    withExtra: (v, extra) => v.copyWith(extra: extra),
  );

  PracticeSessionRecord copyWith({
    DateTime? start,
    String? videoId,
    SongSignature? signature,
    double? wallSeconds,
    Map<String, Object?>? extra,
  }) {
    return PracticeSessionRecord(
      start: start ?? this.start,
      videoId: videoId ?? this.videoId,
      signature: signature ?? this.signature,
      wallSeconds: wallSeconds ?? this.wallSeconds,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() => codec.encode(this);

  /// 结构读取；缺字段按兜底（旧文件/部分写入不崩），陌生键收进保底区
  /// 原样带回。
  factory PracticeSessionRecord.fromJson(Map<String, dynamic> json) =>
      codec.decode(json);

  @override
  bool operator ==(Object other) =>
      other is PracticeSessionRecord && codec.equals(this, other);

  @override
  int get hashCode => codec.hash(this);
}

/// `practice_stats.json` 文档模型（schema v1，设备全局、私密、永不进
/// markers/local）。
@immutable
class PracticeStatsDocument {
  const PracticeStatsDocument({
    this.sessions = const [],
    this.extra = const {},
  });

  const PracticeStatsDocument.empty() : this();

  /// 练舞统计的版本链：地板 2，链为空（地板 = 本版）。v2：
  /// 标识换代（xxHash64）一次性丢弃旧统计属历史、已在地板之下。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 2,
  );

  final List<PracticeSessionRecord> sessions;

  /// 文档级陌生键保底区：读入时原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  static final ListDocumentCodec<
    PracticeStatsDocument,
    PracticeSessionRecord,
    PracticeSessionRecordField
  >
  _codec = ListDocumentCodec(
    policy: versionPolicy,
    listKey: 'sessions',
    elementCodec: PracticeSessionRecord.codec,
    empty: () => const PracticeStatsDocument.empty(),
    build: (elements) => PracticeStatsDocument(sessions: elements),
    listOf: (doc) => doc.sessions,
    extraOf: (doc) => doc.extra,
    withExtra: (doc, extra) =>
        PracticeStatsDocument(sessions: doc.sessions, extra: extra),
  );

  Map<String, dynamic> toJson() => _codec.encode(this);

  /// 容错读取（版本政策）：低于地板（政策判空）、sessions 非
  /// List / 元素非法时按空态兜底，不崩溃；版本头读不出与更高版本按「认识
  /// 多少读多少」打开；陌生键收进保底区原样带回。
  factory PracticeStatsDocument.fromJson(Map<String, dynamic> json) =>
      _codec.decode(json);
}

/// `practice_stats.json` 的原始 JSON 读写 seam。store 只经本接口触达磁盘；
/// 测试注入内存 fake（`test/helpers/in_memory_practice_stats_storage.dart`）
/// 与真实实现双跑。
abstract interface class PracticeStatsStorage {
  /// 读取整份 JSON；缺失/损坏返回 null。
  Future<Map<String, dynamic>?> loadOrNull();

  /// 整份覆盖写入（原子写）。
  Future<void> save(Map<String, dynamic> json);
}

/// [PracticeStatsStorage] 的真实文件实现（设备全局 `practice_stats.json`）。
///
/// [fileFactory] 为文件解析闭包（非现成 Future）：目录解析只在首次真正
/// 读写时发生，容器构建不触发 path_provider（测试环境无插件时不产生无人
/// 消费的失败 Future）。
class AtomicPracticeStatsStorage implements PracticeStatsStorage {
  AtomicPracticeStatsStorage(this._fileFactory);

  final Future<File> Function() _fileFactory;

  AtomicJsonFile? _atomic;
  AtomicJsonFile get _lazy => _atomic ??= AtomicJsonFile(_fileFactory());

  @override
  Future<Map<String, dynamic>?> loadOrNull() => _lazy.readOrNull();

  @override
  Future<void> save(Map<String, dynamic> json) => _lazy.write(json);
}

/// 内存会话条目：记录 + 最近播放时刻（开放会话合并判定的「间隔」基准——
/// 会话含 <5min 间隙，不能用 start+wall 推算，故与会话同存）。
class _SessionEntry {
  _SessionEntry({required this.record, required this.lastActivity});

  PracticeSessionRecord record;
  DateTime lastActivity;
}

/// 练习统计全局 store：`practice_stats.json` 的**唯一读写入口**（设备全局
/// 新文件，不经按视频协调器）。
///
/// - 内存持有会话列表（懒加载一次），写入先改内存、[settle]/[flush] 时整份
///   落盘（「追加式」指会话只在尾部新增/原位扩写，落盘机制与全库一致取
///   原子整份写，读写两侧永不见半截 JSON）；
/// - [recordPlaying]：并入开放会话（同 videoId + 同署名快照 + 同本地日 +
///   距该会话最近播放间隔 < [mergeGap]），否则新开；跨零点的区间按本地
///   午夜拆分（记录不跨日）；
/// - [migrateSignature]：改名/补命名写-through——该 videoId 全部记录
///   （含未 flush 的开放会话）的署名快照改写为新署名；
/// - 磁盘错误静默承接（写失败由调用方承接、不抛到
///   UI），内存态不回滚，下次 settle/flush 重试。
class PracticeStatsStore {
  PracticeStatsStore(this._storage, {this.mergeGap = kPracticeSessionMergeGap});

  final PracticeStatsStorage _storage;

  final Duration mergeGap;

  /// 保存串行链：并发 settle/flush 不互相覆盖。
  Future<void> _saveChain = Future<void>.value();

  List<_SessionEntry> _entries = const [];
  bool _loaded = false;
  bool _dirty = false;

  /// 盘上文件不可写（高于本版 / 版本头读不出，见
  /// [DocumentVersionPolicy.isWritable]）：读面按「认识多少读多少」打开，
  /// 但本机不写回。
  bool _readOnly = false;

  /// 当前全部会话记录（首次调用时从磁盘懒加载；缺失/损坏按空态）。
  Future<List<PracticeSessionRecord>> records() async {
    await _ensureLoaded();
    return List.unmodifiable([for (final e in _entries) e.record]);
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final json = await _storage.loadOrNull();
      _readOnly =
          json != null && !PracticeStatsDocument.versionPolicy.isWritable(json);
      final records = json == null
          ? const <PracticeSessionRecord>[]
          : PracticeStatsDocument.fromJson(json).sessions;
      _entries = [
        // 磁盘载入的会话只有 start+wall 可推算最近播放时刻（合并间隙被
        // 低估 → 倾向新开会话），作为跨重启合并的保守近似。
        for (final record in records)
          _SessionEntry(record: record, lastActivity: _estimatedEnd(record)),
      ];
    } on Object {
      _entries = const [];
    }
  }

  /// 记录一段连续播放：[start]–[end]（本地墙钟）按午夜拆分后逐段并入
  /// 开放会话或新开会话。
  Future<void> recordPlaying({
    required String videoId,
    required SongSignature signature,
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureLoaded();
    if (!end.isAfter(start) || videoId.isEmpty) return;
    var segmentStart = start;
    while (true) {
      final midnight = _nextMidnight(segmentStart);
      final segmentEnd = midnight.isBefore(end) ? midnight : end;
      _recordSegment(
        videoId: videoId,
        signature: signature,
        start: segmentStart,
        end: segmentEnd,
      );
      if (!midnight.isBefore(end)) break;
      segmentStart = midnight;
    }
    _dirty = true;
  }

  void _recordSegment({
    required String videoId,
    required SongSignature signature,
    required DateTime start,
    required DateTime end,
  }) {
    for (var i = _entries.length - 1; i >= 0; i--) {
      final entry = _entries[i];
      final record = entry.record;
      final sameDay = localDay(record.start) == localDay(start);
      final nonNegativeGap = !start.isBefore(entry.lastActivity);
      final withinGap = start.difference(entry.lastActivity) < mergeGap;
      if (record.videoId == videoId &&
          record.signature == signature &&
          sameDay &&
          nonNegativeGap &&
          withinGap) {
        entry.record = record.copyWith(
          wallSeconds: record.wallSeconds + _seconds(start, end),
        );
        entry.lastActivity = end;
        return;
      }
    }
    _entries = [
      ..._entries,
      _SessionEntry(
        record: PracticeSessionRecord(
          start: start,
          videoId: videoId,
          signature: signature,
          wallSeconds: _seconds(start, end),
        ),
        lastActivity: end,
      ),
    ];
  }

  /// 改名/补命名写-through：[videoId] 全部记录（含未 flush 的开放会话）
  /// 的署名快照改写为 [signature]，随后落盘。跨视频同署名的行级聚合由
  /// 展示层按三元组归并，存储不合并不同 videoId 的记录。
  Future<void> migrateSignature(String videoId, SongSignature signature) async {
    await _ensureLoaded();
    if (videoId.isEmpty) return;
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].record.videoId == videoId) {
        _entries[i].record = _entries[i].record.copyWith(signature: signature);
        _dirty = true;
      }
    }
    await settle();
  }

  /// 结算落盘（退出播放器/切后台语义）：有未保存变化才写（无变化不写盘）。
  Future<void> settle() async {
    if (!_dirty) return;
    await _writeAll();
  }

  Future<void> _writeAll() {
    if (!_dirty || _readOnly) return Future<void>.value();
    final json = PracticeStatsDocument(
      sessions: [for (final e in _entries) e.record],
    ).toJson();
    final run = _saveChain.then((_) async {
      await _storage.save(json);
      // 保存成功才清标记；失败保持 dirty，下次 settle 重试。
      _dirty = false;
    });
    _saveChain = run.then<void>((_) {}, onError: (_) {});
    return run.catchError((Object _) {
      // 写失败静默：内存态保留，下次 settle 重试。
    });
  }

  DateTime _estimatedEnd(PracticeSessionRecord record) =>
      record.start.add(record.wallDuration);

  DateTime _nextMidnight(DateTime time) =>
      DateTime(time.year, time.month, time.day + 1);

  double _seconds(DateTime start, DateTime end) =>
      end.difference(start).inMicroseconds / 1e6;
}
