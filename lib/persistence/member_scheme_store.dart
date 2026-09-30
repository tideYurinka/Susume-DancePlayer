library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/atomic_json_file.dart';
import 'index_file_provider.dart' show importIndexFileProvider;
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';

enum _MemberSchemeField {
  schemeId,
  memberName,
  schemeName,
  mastery,
  importedAtMs,
  markers,
}

/// 条目编解码器：必填 = schemeId（缺失条目按损坏丢弃）。markers 是发送方
/// 公开标注文档的整份 JSON 值，原样存取（编解码归既有文档模型）。
final RecordCodec<MemberSchemeRecord, _MemberSchemeField>
    _memberSchemeCodec = RecordCodec<MemberSchemeRecord, _MemberSchemeField>(
      ids: _MemberSchemeField.values,
      decl: _memberSchemeDecl,
      required: const {_MemberSchemeField.schemeId},
      build: _buildMemberScheme,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => MemberSchemeRecord(
        schemeId: v.schemeId,
        memberName: v.memberName,
        schemeName: v.schemeName,
        mastery: v.mastery,
        importedAt: v.importedAt,
        markers: v.markers,
        extra: extra,
      ),
    );

FieldDecl<MemberSchemeRecord> _memberSchemeDecl(_MemberSchemeField id) =>
    switch (id) {
      _MemberSchemeField.schemeId => FieldDecl(
        key: 'schemeId',
        read: (json) =>
            json['schemeId'] is String ? json['schemeId'] as String : null,
        write: (v) => v.schemeId,
        equal: (a, b) => a.schemeId == b.schemeId,
      ),
      _MemberSchemeField.memberName => FieldDecl(
        key: 'memberName',
        read: (json) =>
            json['memberName'] is String ? json['memberName'] as String : '',
        write: (v) => v.memberName,
        equal: (a, b) => a.memberName == b.memberName,
      ),
      _MemberSchemeField.schemeName => FieldDecl(
        key: 'schemeName',
        read: (json) =>
            json['schemeName'] is String ? json['schemeName'] as String : '',
        write: (v) => v.schemeName,
        equal: (a, b) => a.schemeName == b.schemeName,
      ),
      _MemberSchemeField.mastery => FieldDecl(
        key: 'mastery',
        read: (json) => _readMastery(json['mastery']),
        write: (v) => v.mastery == null
            ? null
            : {
                for (final e in v.mastery!.entries) '${e.key}': e.value,
              },
        equal: (a, b) => _masteryEquals(a.mastery, b.mastery),
      ),
      _MemberSchemeField.importedAtMs => FieldDecl(
        key: 'importedAtMs',
        read: (json) =>
            json['importedAtMs'] is int ? json['importedAtMs'] as int : 0,
        write: (v) => v.importedAt.millisecondsSinceEpoch,
        equal: (a, b) => a.importedAt == b.importedAt,
      ),
      _MemberSchemeField.markers => FieldDecl(
        key: 'markers',
        read: (json) =>
            json['markers'] is Map<String, Object?>
                ? json['markers'] as Map<String, Object?>
                : const <String, Object?>{},
        write: (v) => v.markers,
        equal: (a, b) => jsonDeepEquals(a.markers, b.markers),
      ),
    };

/// 熟练度快照读侧：键非段序、值越界按缺快照兜底（快照是可选值，损坏
/// 不成立条目——条目级损坏判据只有 schemeId）。
Map<int, int>? _readMastery(Object? raw) {
  if (raw is! Map) return null;
  final out = <int, int>{};
  for (final e in raw.entries) {
    final order = int.tryParse('${e.key}');
    if (order == null || e.value is! int) return null;
    out[order] = e.value! as int;
  }
  return out;
}

bool _masteryEquals(Map<int, int>? a, Map<int, int>? b) {
  if (a == null || b == null) return identical(a, b);
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

MemberSchemeRecord _buildMemberScheme(
  Map<_MemberSchemeField, Object?> values,
) =>
    MemberSchemeRecord(
      schemeId: values[_MemberSchemeField.schemeId]! as String,
      memberName: values[_MemberSchemeField.memberName]! as String,
      schemeName: values[_MemberSchemeField.schemeName]! as String,
      mastery: values[_MemberSchemeField.mastery] as Map<int, int>?,
      importedAt: DateTime.fromMillisecondsSinceEpoch(
        values[_MemberSchemeField.importedAtMs]! as int,
      ),
      markers: values[_MemberSchemeField.markers]! as Map<String, Object?>,
    );

/// 一条组员方案。
class MemberSchemeRecord {
  const MemberSchemeRecord({
    required this.schemeId,
    this.memberName = '',
    this.schemeName = '',
    this.mastery,
    required this.importedAt,
    this.markers = const {},
    this.extra = const {},
  });

  /// 方案标识：发送方生成的稳定串，同标识替换、异标识新增。
  final String schemeId;

  /// 组员名（发送方署名；导入时可改）。
  final String memberName;

  /// 方案名（发送方的署名歌曲名）。
  final String schemeName;

  /// 发送方那一次的逐段熟练度快照（键 = 段序，值 = 档位数值 0–4）；
  /// null = 未随包。
  final Map<int, int>? mastery;

  final DateTime importedAt;

  /// 发送方的整套公开标注文档 JSON 值（六段全含）。
  final Map<String, Object?> markers;

  /// 条目级陌生键保底区。
  final Map<String, Object?> extra;

  @override
  bool operator ==(Object other) =>
      other is MemberSchemeRecord && _memberSchemeCodec.equals(this, other);

  @override
  int get hashCode => _memberSchemeCodec.hash(this);
}

/// 组员方案文档：`version` + 一个方案列表。
class MemberSchemesDocument {
  const MemberSchemesDocument({
    this.schemes = const [],
    this.extra = const {},
  });

  /// 空态（文件缺失/损坏/低于地板兜底）。
  static const MemberSchemesDocument empty = MemberSchemesDocument();

  /// 组员方案的版本链：地板 1；v1 → v2 把 `schemes.entries` 上提为
  /// `schemes`（旧段级陌生键按留档保原文丢弃）。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 1,
    steps: [MigrationStep(1, _migrateMemberSchemesV1ToV2)],
  );

  final List<MemberSchemeRecord> schemes;

  final Map<String, Object?> extra;
}

/// v1 → v2 迁移：`schemes` 由「段对象（`entries` + 段级陌生键）」摊平为
/// 条目列表；只改形状、不写版本号。幂等：只认 `version = 1`。
Map<String, Object?> _migrateMemberSchemesV1ToV2(Map<String, Object?> json) {
  if (json['version'] != 1) return json;
  final schemes = json['schemes'];
  if (schemes is! Map) return Map<String, Object?>.of(json);
  return Map<String, Object?>.of(json)..['schemes'] = schemes['entries'];
}

final ListDocumentCodec<
  MemberSchemesDocument,
  MemberSchemeRecord,
  _MemberSchemeField
>
_memberSchemesDocCodec = ListDocumentCodec(
  policy: MemberSchemesDocument.versionPolicy,
  listKey: 'schemes',
  elementCodec: _memberSchemeCodec,
  empty: () => MemberSchemesDocument.empty,
  build: (elements) => MemberSchemesDocument(schemes: elements),
  listOf: (doc) => doc.schemes,
  extraOf: (doc) => doc.extra,
  withExtra: (doc, extra) =>
      MemberSchemesDocument(schemes: doc.schemes, extra: extra),
);

/// 组员方案文件原始 JSON 读写 seam（真实实现委托 [AtomicJsonFile]；测试
/// 注入内存实现）。
abstract interface class MemberSchemeStorage {
  /// 读取整份 JSON；缺失/损坏兜底空 Map。
  Future<Map<String, dynamic>> load();

  /// 整份覆盖写入。
  Future<void> save(Map<String, dynamic> json);

  /// 删除整份文件（随舞删除；缺失视作已删、不抛错）。
  Future<void> delete();
}

/// [MemberSchemeStorage] 的文件实现（原子写，读侧不见半截 JSON）。
class MemberSchemeFileStore implements MemberSchemeStorage {
  MemberSchemeFileStore(FutureOr<File> file) : _atomic = AtomicJsonFile(file);

  final AtomicJsonFile _atomic;

  @override
  Future<Map<String, dynamic>> load() => _atomic.read();

  @override
  Future<void> save(Map<String, dynamic> json) => _atomic.write(json);

  @override
  Future<void> delete() => _atomic.delete();
}

/// 组员方案存取：读取 + 串行「读 → 改 → 写」upsert / remove（单条写链，
/// 并发导入无 lost-update）。
class MemberSchemeStore {
  MemberSchemeStore(this._storage);

  final MemberSchemeStorage _storage;

  Future<void> _chain = Future<void>.value();

  /// 读当前文档（缺失按空态；不可写的文件按「认识多少读多少」打开）。
  Future<MemberSchemesDocument> read() async =>
      _memberSchemesDocCodec.decode(await _storage.load());

  /// 导入落盘唯一写入口：同 [MemberSchemeRecord.schemeId] 替换那一条、
  /// 异标识追加一条，返回写后的文档。替换在原位置进行，不打乱其余条目的
  /// 落盘次序。
  Future<MemberSchemesDocument> upsert(MemberSchemeRecord record) =>
      _mutate((current) {
        final exists = current.schemes.any(
          (existing) => existing.schemeId == record.schemeId,
        );
        return MemberSchemesDocument(
          schemes: [
            for (final existing in current.schemes)
              existing.schemeId == record.schemeId ? record : existing,
            if (!exists) record,
          ],
          extra: current.extra,
        );
      });

  /// 删除一条组员方案（详情页删方案唯一写入口，接线）；标识
  /// 不存在时文档原样（仍整份重写）。
  Future<MemberSchemesDocument> remove(String schemeId) => _mutate(
    (current) => MemberSchemesDocument(
      schemes: [
        for (final existing in current.schemes)
          if (existing.schemeId != schemeId) existing,
      ],
      extra: current.extra,
    ),
  );

  /// 写链：一次「读 → 改 → 写」，返回改后的文档（[upsert] / [remove]
  /// 共用，不互相覆盖）。盘上文件不可写（高于本版 / 版本头读不出，见
  /// [DocumentVersionPolicy.isWritable]）时跳过写盘、返回读取结果。
  Future<MemberSchemesDocument> _mutate(
    MemberSchemesDocument Function(MemberSchemesDocument current) change,
  ) => _enqueue(() async {
    final json = await _storage.load();
    final current = _memberSchemesDocCodec.decode(json);
    if (!MemberSchemesDocument.versionPolicy.isWritable(json)) {
      return current;
    }
    final next = change(current);
    await _storage.save(_memberSchemesDocCodec.encode(next));
    return next;
  });

  /// 按舞清除（随舞删除的唯一写入口）：整份文件删掉，读回空态。
  Future<void> clear() => _enqueue<void>(() async {
        await _storage.delete();
      });

  /// 单条写链：串行「读 → 改 → 写」，并发写不互相覆盖。
  Future<T> _enqueue<T>(Future<T> Function() body) {
    final run = _chain.then((_) => body());
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

/// 组员方案文件（`schemes_<hash>.json`）：与该舞两份文档同级放在应用文档
/// 目录（位置自 [importIndexFileProvider] 派生，测试覆盖该 provider 即同时
/// 覆盖本工厂）。随舞删除走 [MemberSchemeStorage.delete]。
final memberSchemeStorageProvider =
    Provider.family<MemberSchemeStorage, String>((ref, videoId) {
  return MemberSchemeFileStore(
    ref.watch(importIndexFileProvider).then(
          (indexFile) => File(
            p.join(indexFile.parent.path, 'schemes_$videoId.json'),
          ),
        ),
  );
});

/// 组员方案存取注入点（family 参数 = videoId）：写链随实例存在，编排层
/// 一律经此取实例（同一 videoId 单实例 = 单条写链），不自建。
final memberSchemeStoreProvider = Provider.family<MemberSchemeStore, String>((
  ref,
  videoId,
) {
  return MemberSchemeStore(ref.watch(memberSchemeStorageProvider(videoId)));
});

/// 组员方案读面（详情页「组员方案」区用）：autoDispose，页面不在场即释放；
/// 删一条等写动作落盘后由页面 invalidate 重读。
final memberSchemesProvider =
    FutureProvider.autoDispose.family<MemberSchemesDocument, String>((
      ref,
      videoId,
    ) {
      return ref.watch(memberSchemeStoreProvider(videoId)).read();
    });
