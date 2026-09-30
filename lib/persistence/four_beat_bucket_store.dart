/// 每舞四拍桶分片文档（见词条「四拍桶」；字段声明机制）。
///
/// 桶按舞分片存放：每支舞一份**完全私密**文档（ADR-0002：不进任何分享
/// 包，只随整机备份走），写入只重写该舞那一份。文档内按**本地日 × 桶序号**
/// 嵌套承载 `{墙钟秒, 扫过次数}`，并带一份署名快照（改名 write-through、
/// 删舞后标题可读）。版本门禁、逐层陌生键保底与字段单一声明全部走既有
/// [DocumentCodec] 机制：加字段 = 枚举加一项 → 穷尽 switch 编译报错。
/// 删除一支舞即删该文件；按天会话记录原样保留（时长总量不缩水）。
library;

import 'dart:async';
import 'dart:io';

import '../core/atomic_json_file.dart';
import '../core/local_day.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';
import '../stats/four_beat_bucket.dart';
import 'four_beat_bucket_key.dart';
import 'marker_document.dart' show MarkersDocument;
import 'song_signature.dart';

/// 单个桶的聚合值：某本地日、某桶序号的墙钟秒与扫过次数。
class FourBeatBucketValue {
  const FourBeatBucketValue({
    this.wallSeconds = 0,
    this.sweeps = 0,
    this.extra = const {},
  });

  /// 墙钟秒（倍速不折算）。
  final double wallSeconds;

  /// 扫过次数（越过右边界记 1）。
  final int sweeps;

  /// 元素级陌生键保底区：读入原样带回、写回原样（不参与相等）。
  final Map<String, Object?> extra;

  /// 同桶两笔累加（保底区随接收方保留）。
  FourBeatBucketValue plus(FourBeatBucketValue other) => FourBeatBucketValue(
    wallSeconds: wallSeconds + other.wallSeconds,
    sweeps: sweeps + other.sweeps,
    extra: extra,
  );

  @override
  bool operator ==(Object other) =>
      other is FourBeatBucketValue &&
      other.wallSeconds == wallSeconds &&
      other.sweeps == sweeps;

  @override
  int get hashCode => Object.hash(wallSeconds, sweeps);

  @override
  String toString() => 'FourBeatBucketValue(${wallSeconds}s, 扫过 $sweeps)';
}

/// 桶值字段 id（加字段 = 这里加一项 → 穷尽 switch 编译报错）。
enum FourBeatBucketValueField { wallSeconds, sweeps }

/// 桶值编解码器：字段单一声明 + 元素级陌生键保底。
final RecordCodec<FourBeatBucketValue, FourBeatBucketValueField>
_bucketValueCodec = RecordCodec<FourBeatBucketValue, FourBeatBucketValueField>(
  ids: FourBeatBucketValueField.values,
  decl: (id) => switch (id) {
    FourBeatBucketValueField.wallSeconds => FieldDecl(
      key: 'wallSeconds',
      read: (json) => (json['wallSeconds'] as num?)?.toDouble() ?? 0.0,
      write: (v) => v.wallSeconds,
      equal: (a, b) => a.wallSeconds == b.wallSeconds,
    ),
    FourBeatBucketValueField.sweeps => FieldDecl(
      key: 'sweeps',
      read: (json) => (json['sweeps'] as num?)?.toInt() ?? 0,
      write: (v) => v.sweeps,
      equal: (a, b) => a.sweeps == b.sweeps,
    ),
  },
  build: (values) => FourBeatBucketValue(
    wallSeconds: values[FourBeatBucketValueField.wallSeconds]! as double,
    sweeps: values[FourBeatBucketValueField.sweeps]! as int,
  ),
  extraOf: (v) => v.extra,
  withExtra: (v, extra) => FourBeatBucketValue(
    wallSeconds: v.wallSeconds,
    sweeps: v.sweeps,
    extra: extra,
  ),
);

/// 某一本地日的桶集合：桶键（带记录时倍频身份）→ 桶值；非桶键的陌生键
/// 收进保底区（动态键容器的不认识键原样带回）。
class FourBeatBucketDay {
  const FourBeatBucketDay({this.buckets = const {}, this.extra = const {}});

  /// 桶键（原样档 = 裸整数身份，其余档带倍频值）→ 桶值。
  final Map<FourBeatBucketKey, FourBeatBucketValue> buckets;

  /// 非桶序号（或值非对象）的陌生键保底区。
  final Map<String, Object?> extra;

  FourBeatBucketDay copyWith({
    Map<FourBeatBucketKey, FourBeatBucketValue>? buckets,
    Map<String, Object?>? extra,
  }) => FourBeatBucketDay(
    buckets: buckets ?? this.buckets,
    extra: extra ?? this.extra,
  );
}

/// 每舞桶分片文档模型（`four_beat_buckets_<videoId>.json`）。
class FourBeatBucketShard {
  const FourBeatBucketShard({
    this.signature = const SongSignature(),
    this.signatureExtra = const {},
    this.days = const {},
    this.daysExtra = const {},
    this.extra = const {},
  });

  const FourBeatBucketShard.empty() : this();

  /// 桶分片的版本链：地板 1，链为空（地板 = 本版）。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 1,
  );

  /// 署名快照（改名 write-through；删舞后标题可读）。
  final SongSignature signature;

  /// 署名段陌生键保底区。
  final Map<String, Object?> signatureExtra;

  /// 本地日键（`yyyy-MM-dd`） → 该日桶集合。
  final Map<String, FourBeatBucketDay> days;

  /// 账本段陌生键保底区。
  final Map<String, Object?> daysExtra;

  /// 文档级陌生键保底区。
  final Map<String, Object?> extra;

  /// 无桶数据（不落文件）。
  bool get isEmpty => days.isEmpty;

  FourBeatBucketShard copyWith({
    SongSignature? signature,
    Map<String, Object?>? signatureExtra,
    Map<String, FourBeatBucketDay>? days,
    Map<String, Object?>? daysExtra,
    Map<String, Object?>? extra,
  }) => FourBeatBucketShard(
    signature: signature ?? this.signature,
    signatureExtra: signatureExtra ?? this.signatureExtra,
    days: days ?? this.days,
    daysExtra: daysExtra ?? this.daysExtra,
    extra: extra ?? this.extra,
  );

  static final DocumentCodec<FourBeatBucketShard, _ShardSection> _codec =
      DocumentCodec<FourBeatBucketShard, _ShardSection>(
        policy: versionPolicy,
        ids: _ShardSection.values,
        decl: _shardSectionDecl,
        empty: () => const FourBeatBucketShard.empty(),
        build: (sections) {
          final signature =
              sections[_ShardSection.signature]! as _SignatureValue;
          final ledger = sections[_ShardSection.ledger]! as _LedgerValue;
          return FourBeatBucketShard(
            signature: signature.signature,
            signatureExtra: signature.extra,
            days: ledger.days,
            daysExtra: ledger.extra,
          );
        },
        extraOf: (doc) => doc.extra,
        withExtra: (doc, extra) => doc.copyWith(extra: extra),
      );

  Map<String, dynamic> toJson() =>
      Map<String, dynamic>.from(_codec.encode(this));

  /// 容错读取：低于地板 / 列表形状不符 → 空态兜底；版本头读不出与更高
  /// 版本按「认识多少读多少」打开（见 [versionPolicy]）；相符 → 逐层读，
  /// 损坏的日/桶条目按项跳过或收进保底区，各层陌生键原样带回。
  factory FourBeatBucketShard.fromJson(Map<String, dynamic> json) =>
      _codec.decode(json);
}

/// 桶分片文档的段 id（加段 = 这里加一项 → 穷尽 switch 编译报错）。
enum _ShardSection { signature, ledger }

SectionDecl<FourBeatBucketShard> _shardSectionDecl(_ShardSection id) =>
    switch (id) {
      _ShardSection.signature => SectionDecl(
        key: 'signature',
        codec: _signatureCodec,
        sectionOf: (doc) => _SignatureValue(
          signature: doc.signature,
          extra: doc.signatureExtra,
        ),
      ),
      _ShardSection.ledger => SectionDecl(
        key: 'ledger',
        codec: _ledgerCodec,
        sectionOf: (doc) => _LedgerValue(days: doc.days, extra: doc.daysExtra),
      ),
    };

class _SignatureValue {
  const _SignatureValue({required this.signature, this.extra = const {}});

  final SongSignature signature;
  final Map<String, Object?> extra;
}

enum _SignatureField { dancer, song, remark }

final RecordCodec<_SignatureValue, _SignatureField> _signatureCodec =
    RecordCodec<_SignatureValue, _SignatureField>(
      ids: _SignatureField.values,
      decl: (id) => switch (id) {
        _SignatureField.dancer => FieldDecl(
          key: 'dancer',
          read: (json) => json['dancer'] as String? ?? '',
          write: (v) => v.signature.dancer,
          equal: (a, b) => a.signature.dancer == b.signature.dancer,
        ),
        _SignatureField.song => FieldDecl(
          key: 'song',
          read: (json) => json['song'] as String? ?? '',
          write: (v) => v.signature.song,
          equal: (a, b) => a.signature.song == b.signature.song,
        ),
        _SignatureField.remark => FieldDecl(
          key: 'remark',
          read: (json) => json['remark'] as String? ?? '',
          write: (v) => v.signature.remark,
          equal: (a, b) => a.signature.remark == b.signature.remark,
        ),
      },
      build: (values) => _SignatureValue(
        signature: SongSignature(
          dancer: values[_SignatureField.dancer]! as String,
          song: values[_SignatureField.song]! as String,
          remark: values[_SignatureField.remark]! as String,
        ),
      ),
      extraOf: (v) => v.extra,
      withExtra: (v, extra) =>
          _SignatureValue(signature: v.signature, extra: extra),
    );

/// 账本段值：本地日 → 该日桶集合。
class _LedgerValue {
  const _LedgerValue({this.days = const {}, this.extra = const {}});

  final Map<String, FourBeatBucketDay> days;
  final Map<String, Object?> extra;
}

enum _LedgerField { days }

final RecordCodec<_LedgerValue, _LedgerField> _ledgerCodec =
    RecordCodec<_LedgerValue, _LedgerField>(
      ids: _LedgerField.values,
      decl: (id) => switch (id) {
        _LedgerField.days => FieldDecl(
          key: 'days',
          read: (json) => _decodeDays(json['days']),
          write: (v) => _encodeDays(v.days),
          equal: (a, b) =>
              jsonDeepEquals(_encodeDays(a.days), _encodeDays(b.days)),
        ),
      },
      build: (values) => _LedgerValue(
        days: values[_LedgerField.days]! as Map<String, FourBeatBucketDay>,
      ),
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => _LedgerValue(days: v.days, extra: extra),
    );

Map<String, Object?> _encodeDays(Map<String, FourBeatBucketDay> days) => {
  for (final entry in days.entries) entry.key: _encodeDay(entry.value),
};

Map<String, FourBeatBucketDay> _decodeDays(Object? raw) {
  final map = _asJsonMap(raw);
  if (map == null) return const {};
  final days = <String, FourBeatBucketDay>{};
  for (final entry in map.entries) {
    final day = _decodeDay(entry.value);
    // 日值非对象 = 损坏条目，按项跳过（与元素/桶级容错同款）。
    if (day != null) days[entry.key] = day;
  }
  return days;
}

/// 单日编码：保底区先展开（含非桶键的陌生键），已登记桶值后写。
Map<String, Object?> _encodeDay(FourBeatBucketDay day) => {
  ...day.extra,
  for (final bucket in day.buckets.entries)
    encodeFourBeatBucketKey(bucket.key): _bucketValueCodec.encode(bucket.value),
};

FourBeatBucketDay? _decodeDay(Object? raw) {
  final map = _asJsonMap(raw);
  if (map == null) return null;
  final buckets = <FourBeatBucketKey, FourBeatBucketValue>{};
  final extra = <String, Object?>{};
  for (final entry in map.entries) {
    final key = parseFourBeatBucketKey(entry.key);
    final valueRaw = key == null ? null : _asJsonMap(entry.value);
    if (key == null || key.index < 0 || valueRaw == null) {
      extra[entry.key] = entry.value;
      continue;
    }
    buckets[key] = _bucketValueCodec.decode(valueRaw);
  }
  return FourBeatBucketDay(buckets: buckets, extra: extra);
}

Map<String, Object?>? _asJsonMap(Object? raw) =>
    raw is Map ? Map<String, Object?>.from(raw) : null;

/// 桶分片 → 当前桶格读面（读取时投影见词条「四拍桶」，
/// 装配点：舞库层不 import stats 纯件，唯一转换经本函数）。
///
/// 每条记录按它自己的倍频重建当时桶格、换算成绝对时间区间、归入当前桶格
/// （当前档 = 该舞公开标记文件人工修正段的倍频），秒守恒、次数细分复制
/// 合并取最小。磁盘上的桶明细一个字节不动。网格未分析时无桶格，裸键
/// 原样透出。返回本地日 → 当前桶序号 →（墙钟秒, 扫过次数）。
Map<String, Map<int, ({double wallSeconds, int sweeps})>>
projectShardToCurrentGrid(FourBeatBucketShard shard, MarkersDocument? markers) {
  final docBeat = markers?.beat;
  final beats = docBeat?.beats ?? const [];
  if (beats.isEmpty) {
    return {
      for (final day in shard.days.entries)
        day.key: {
          for (final bucket in day.value.buckets.entries)
            if (bucket.key.isBare)
              bucket.key.index: (
                wallSeconds: bucket.value.wallSeconds,
                sweeps: bucket.value.sweeps,
              ),
        },
    };
  }
  final shiftMs = (docBeat!.shift * 1000).round();
  FourBeatBucketLines linesOf(double density) =>
      FourBeatBucketLines.of(beats: beats, shiftMs: shiftMs, density: density);
  final projected = projectFourBeatBuckets(
    days: {
      for (final day in shard.days.entries)
        day.key: [
          for (final bucket in day.value.buckets.entries)
            RecordedBucket(
              key: bucket.key,
              wallSeconds: bucket.value.wallSeconds,
              sweeps: bucket.value.sweeps,
            ),
        ],
    },
    recordGridOf: linesOf,
    currentGrid: linesOf(docBeat.density),
  );
  return {
    for (final day in projected.entries)
      day.key: {
        for (final bucket in day.value.entries)
          bucket.key: (
            wallSeconds: bucket.value.wallSeconds,
            sweeps: bucket.value.sweeps,
          ),
      },
  };
}

/// 每舞桶分片的原始 JSON 读写 seam：store 只经本接口触达磁盘；测试注入
/// 内存 fake 与真实实现双跑。读取失败（文件缺失/损坏）返回 null，不抛错。
abstract interface class FourBeatBucketStorage {
  /// 读取该舞分片整份 JSON；缺失/损坏返回 null。
  Future<Map<String, dynamic>?> loadOrNull(String videoId);

  /// 整份覆盖写入该舞分片（原子写）。
  Future<void> save(String videoId, Map<String, dynamic> json);

  /// 删除该舞分片文件（缺失视作已删、不抛错）。
  Future<void> delete(String videoId);
}

/// [FourBeatBucketStorage] 的真实文件实现：每舞一个 [AtomicJsonFile]
/// （一文件一实例、单条串行写链）。[fileFactory] 为按 videoId 解析文件的
/// 闭包（生产由 path_provider 异步解析，测试直接传临时文件）。
class AtomicFourBeatBucketStorage implements FourBeatBucketStorage {
  AtomicFourBeatBucketStorage(this._fileFactory);

  final FutureOr<File> Function(String videoId) _fileFactory;

  final Map<String, AtomicJsonFile> _files = {};

  AtomicJsonFile _fileFor(String videoId) =>
      _files.putIfAbsent(videoId, () => AtomicJsonFile(_fileFactory(videoId)));

  @override
  Future<Map<String, dynamic>?> loadOrNull(String videoId) =>
      _fileFor(videoId).readOrNull();

  @override
  Future<void> save(String videoId, Map<String, dynamic> json) =>
      _fileFor(videoId).write(json);

  @override
  Future<void> delete(String videoId) => _fileFor(videoId).delete();
}

/// 每舞桶分片 store：桶分片的**唯一读写入口**（每舞一份内存态，写入先改
/// 内存、[settle]/[flush] 时整份落盘；写失败静默承接，内存态不回滚，下次
/// settle/flush 重试——与会话 store 同款纪律）。
class FourBeatBucketStore {
  FourBeatBucketStore(this._storage);

  final FourBeatBucketStorage _storage;

  final Map<String, FourBeatBucketShard> _shards = {};
  final Map<String, Future<void>> _loadFutures = {};
  final Set<String> _dirty = {};

  /// 盘上文件不可写（高于本版 / 版本头读不出，见
  /// [DocumentVersionPolicy.isWritable]）的舞：读面按「认识多少读多少」
  /// 打开，但本机不写回。
  final Set<String> _readOnly = {};

  /// 保存串行链：并发 settle/flush 不互相覆盖。
  Future<void> _saveChain = Future<void>.value();

  /// 读该舞分片（首次调用懒加载；缺失/损坏按空态）。
  Future<FourBeatBucketShard> shard(String videoId) async {
    if (videoId.isEmpty) return const FourBeatBucketShard.empty();
    await _ensureLoaded(videoId);
    return _shards[videoId]!;
  }

  /// 首读该舞分片；同一舞的并发首读共等同一个在飞 future——慢读窗口内后到
  /// 者不得越过加载直接读内存态（否则读到 null / 空账面）。
  Future<void> _ensureLoaded(String videoId) =>
      _loadFutures.putIfAbsent(videoId, () async {
        try {
          final json = await _storage.loadOrNull(videoId);
          if (json == null) {
            _shards[videoId] = const FourBeatBucketShard.empty();
          } else {
            _shards[videoId] = FourBeatBucketShard.fromJson(json);
            if (!FourBeatBucketShard.versionPolicy.isWritable(json)) {
              _readOnly.add(videoId);
            }
          }
        } on Object {
          _shards[videoId] = const FourBeatBucketShard.empty();
        }
      });

  /// 把一批桶账并入该舞分片（同桶累加墙钟与扫过），并刷新署名快照。
  Future<void> recordCredits({
    required String videoId,
    required SongSignature signature,
    required List<FourBeatBucketCredit> credits,
  }) async {
    if (videoId.isEmpty || credits.isEmpty) return;
    await _ensureLoaded(videoId);
    final current = _shards[videoId]!;
    final days = <String, FourBeatBucketDay>{...current.days};
    for (final credit in credits) {
      final key = localDayKey(credit.day);
      final day = days[key] ?? const FourBeatBucketDay();
      final buckets = Map<FourBeatBucketKey, FourBeatBucketValue>.of(
        day.buckets,
      );
      final bucketKey = FourBeatBucketKey(credit.density, credit.bucket);
      final previous = buckets[bucketKey] ?? const FourBeatBucketValue();
      buckets[bucketKey] = previous.plus(
        FourBeatBucketValue(
          wallSeconds: credit.wallSeconds,
          sweeps: credit.sweeps,
        ),
      );
      days[key] = day.copyWith(buckets: buckets);
    }
    _shards[videoId] = current.copyWith(signature: signature, days: days);
    _dirty.add(videoId);
  }

  /// 改名/补命名写-through：该舞分片署名快照改写为新署名并落盘；无桶数据
  /// 时不建分片文件（磁盘上不留永远看不到的数据）。
  Future<void> migrateSignature(String videoId, SongSignature signature) async {
    if (videoId.isEmpty) return;
    await _ensureLoaded(videoId);
    final current = _shards[videoId]!;
    if (current.isEmpty) return;
    if (current.signature != signature) {
      _shards[videoId] = current.copyWith(signature: signature);
      _dirty.add(videoId);
    }
    await settle();
  }

  /// 删除该舞分片（文件 + 内存态）：先等已排队的写落定再删，避免在途
  /// settle 把刚删的文件又写回来；未落盘的舞照常删除既存文件。
  Future<void> deleteShard(String videoId) async {
    if (videoId.isEmpty) return;
    _shards.remove(videoId);
    _loadFutures.remove(videoId);
    _dirty.remove(videoId);
    _readOnly.remove(videoId);
    await _saveChain;
    await _storage.delete(videoId);
  }

  /// 结算落盘（退出播放器/切后台语义）：有未保存变化才写（无变化不写
  /// 盘）；不可写（高版本 / 版本头读不出）的舞跳过写盘。
  Future<void> settle() async {
    if (_dirty.isEmpty) return;
    final dirtyIds = _dirty.where((id) => !_readOnly.contains(id)).toList();
    if (dirtyIds.isEmpty) return;
    final json = <String, Map<String, dynamic>>{
      for (final id in dirtyIds) id: _shards[id]!.toJson(),
    };
    final run = _saveChain.then((_) async {
      for (final id in dirtyIds) {
        await _storage.save(id, json[id]!);
        // 保存成功才清标记；失败保持 dirty，下次 settle 重试。
        _dirty.remove(id);
      }
    });
    _saveChain = run.then<void>((_) {}, onError: (_) {});
    await run.catchError((Object _) {
      // 写失败静默：内存态保留，下次 settle 重试。
    });
  }
}
