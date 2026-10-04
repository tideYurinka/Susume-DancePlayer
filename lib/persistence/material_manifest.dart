/// 素材清单（第五份接入文档）：
/// 单段（`materials`）、写入者 = 录制会话——段与写入者一一对应，整段写
/// 入不覆盖他人字段。条目 = [MaterialRecord]（带 videoId 与源区间）。
///
/// 字段单一声明：字段 id 枚举 + 穷尽 switch 一处给出键名/读/写/相等；
/// 逐层陌生键保底（文档/段/条目）；版本事实只由
/// [MaterialManifestDocument.versionPolicy] 一处声明（地板 2，链为空）。
/// 文件存私有素材目录（不入视频索引目录），素材不入视频索引（不新增舞
/// 条目、不跑节拍分析、不参与续播位置）。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../annotation/compare_materials.dart';
import '../core/atomic_json_file.dart';
import '../core/document_codec.dart';
import '../core/document_version_policy.dart';

enum _MaterialEntryField {
  id,
  videoId,
  createdAtMs,
  durationMs,
  sourceStartMs,
  fileName,
  sizeBytes,
}

/// 元素编解码器：条目级字段声明（必填 = id/videoId/fileName，缺失条目
/// 按损坏丢弃）。
final RecordCodec<MaterialRecord, _MaterialEntryField> _materialEntryCodec =
    RecordCodec<MaterialRecord, _MaterialEntryField>(
      ids: _MaterialEntryField.values,
      decl: _materialEntryDecl,
      required: const {
        _MaterialEntryField.id,
        _MaterialEntryField.videoId,
        _MaterialEntryField.fileName,
      },
      build: _buildMaterialEntry,
      extraOf: (v) => v.extra,
      withExtra: (v, extra) => MaterialRecord(
        id: v.id,
        videoId: v.videoId,
        createdAt: v.createdAt,
        durationMs: v.durationMs,
        sourceStartMs: v.sourceStartMs,
        fileName: v.fileName,
        sizeBytes: v.sizeBytes,
        extra: extra,
      ),
    );

FieldDecl<MaterialRecord> _materialEntryDecl(_MaterialEntryField id) =>
    switch (id) {
      _MaterialEntryField.id => FieldDecl(
        key: 'id',
        read: (json) => json['id'] is String ? json['id'] as String : null,
        write: (v) => v.id,
        equal: (a, b) => a.id == b.id,
      ),
      _MaterialEntryField.videoId => FieldDecl(
        key: 'videoId',
        read: (json) =>
            json['videoId'] is String ? json['videoId'] as String : null,
        write: (v) => v.videoId,
        equal: (a, b) => a.videoId == b.videoId,
      ),
      _MaterialEntryField.createdAtMs => FieldDecl(
        key: 'createdAtMs',
        read: (json) =>
            json['createdAtMs'] is int ? json['createdAtMs'] as int : 0,
        write: (v) => v.createdAt.millisecondsSinceEpoch,
        equal: (a, b) => a.createdAt == b.createdAt,
      ),
      _MaterialEntryField.durationMs => FieldDecl(
        key: 'durationMs',
        read: (json) =>
            json['durationMs'] is int ? json['durationMs'] as int : 0,
        write: (v) => v.durationMs,
        equal: (a, b) => a.durationMs == b.durationMs,
      ),
      _MaterialEntryField.sourceStartMs => FieldDecl(
        key: 'sourceStartMs',
        read: (json) =>
            json['sourceStartMs'] is int ? json['sourceStartMs'] as int : 0,
        write: (v) => v.sourceStartMs,
        equal: (a, b) => a.sourceStartMs == b.sourceStartMs,
      ),
      _MaterialEntryField.fileName => FieldDecl(
        key: 'fileName',
        read: (json) =>
            json['fileName'] is String ? json['fileName'] as String : null,
        write: (v) => v.fileName,
        equal: (a, b) => a.fileName == b.fileName,
      ),
      _MaterialEntryField.sizeBytes => FieldDecl(
        key: 'sizeBytes',
        read: (json) => json['sizeBytes'] is int ? json['sizeBytes'] as int : 0,
        write: (v) => v.sizeBytes,
        equal: (a, b) => a.sizeBytes == b.sizeBytes,
      ),
    };

MaterialRecord _buildMaterialEntry(Map<_MaterialEntryField, Object?> values) =>
    MaterialRecord(
      id: values[_MaterialEntryField.id]! as String,
      videoId: values[_MaterialEntryField.videoId]! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        values[_MaterialEntryField.createdAtMs]! as int,
      ),
      durationMs: values[_MaterialEntryField.durationMs]! as int,
      sourceStartMs: values[_MaterialEntryField.sourceStartMs]! as int,
      fileName: values[_MaterialEntryField.fileName]! as String,
      sizeBytes: values[_MaterialEntryField.sizeBytes]! as int,
    );

/// 素材清单文档：`version` + 一个素材列表。
class MaterialManifestDocument {
  const MaterialManifestDocument({
    this.materials = const [],
    this.extra = const {},
  });

  /// 空态（文件缺失/损坏/低于地板兜底）。
  static const MaterialManifestDocument empty = MaterialManifestDocument();

  /// 素材清单的版本链：地板 2；v2 → v3 把 `materials.entries` 上提为
  /// `materials`（旧段级陌生键按留档保原文丢弃）。v2 之前标识换代
  /// （xxHash64）一次性丢弃旧清单属历史、已在地板之下。
  static final DocumentVersionPolicy versionPolicy = DocumentVersionPolicy(
    floor: 2,
    steps: [MigrationStep(2, _migrateMaterialManifestV2ToV3)],
  );

  final List<MaterialRecord> materials;

  final Map<String, Object?> extra;
}

/// v2 → v3 迁移：`materials` 由「段对象（`entries` + 段级陌生键）」摊平为
/// 条目列表；只改形状、不写版本号。幂等：只认 `version = 2`。
Map<String, Object?> _migrateMaterialManifestV2ToV3(Map<String, Object?> json) {
  if (json['version'] != 2) return json;
  final materials = json['materials'];
  if (materials is! Map) return Map<String, Object?>.of(json);
  return Map<String, Object?>.of(json)..['materials'] = materials['entries'];
}

final ListDocumentCodec<
  MaterialManifestDocument,
  MaterialRecord,
  _MaterialEntryField
>
_materialManifestCodec = ListDocumentCodec(
  policy: MaterialManifestDocument.versionPolicy,
  listKey: 'materials',
  elementCodec: _materialEntryCodec,
  empty: () => MaterialManifestDocument.empty,
  build: (elements) => MaterialManifestDocument(materials: elements),
  listOf: (doc) => doc.materials,
  extraOf: (doc) => doc.extra,
  withExtra: (doc, extra) =>
      MaterialManifestDocument(materials: doc.materials, extra: extra),
);

/// 素材清单原始 JSON 读写 seam（真实实现委托 [AtomicJsonFile]；测试注入
/// 内存实现）。
abstract interface class MaterialManifestStorage {
  /// 读取整份 JSON；缺失/损坏兜底空 Map。
  Future<Map<String, dynamic>> load();

  /// 整份覆盖写入。
  Future<void> save(Map<String, dynamic> json);
}

/// [MaterialManifestStorage] 的文件实现（原子写，读侧不见半截 JSON）。
class MaterialManifestFileStore implements MaterialManifestStorage {
  MaterialManifestFileStore(FutureOr<File> file)
    : _atomic = AtomicJsonFile(file);

  final AtomicJsonFile _atomic;

  @override
  Future<Map<String, dynamic>> load() => _atomic.read();

  @override
  Future<void> save(Map<String, dynamic> json) => _atomic.write(json);
}

/// 素材清单存取：读取 + 串行「读 → 改 → 写」追加（单条写链，并发追加
/// 无 lost-update）。
class MaterialManifestStore {
  MaterialManifestStore(this._storage);

  final MaterialManifestStorage _storage;

  Future<void> _chain = Future<void>.value();

  /// 读当前清单（缺失按空态；不可写的文件按「认识多少读多少」打开）。
  Future<MaterialManifestDocument> read() async =>
      _materialManifestCodec.decode(await _storage.load());

  /// 追加一条素材记录（录制入库唯一写入口）并返回追加后的清单。
  Future<MaterialManifestDocument> append(MaterialRecord record) => _mutate(
    (current) => MaterialManifestDocument(
      materials: [...current.materials, record],
      extra: current.extra,
    ),
  );

  /// 删除一条素材记录（素材库删除的唯一写入口）并返回删除后的清单；
  /// [materialId] 不存在时清单原样（仍整份重写）。
  Future<MaterialManifestDocument> remove(String materialId) =>
      _removeWhere((entry) => entry.id == materialId);

  /// 删除某个 videoId 的全部素材记录（所属舞被删除时的唯一写入口）并返回
  /// 删除后的清单；该舞没有条目时清单原样（仍整份重写）。
  Future<MaterialManifestDocument> removeByVideo(String videoId) =>
      _removeWhere((entry) => entry.videoId == videoId);

  /// 两条删除入口共用的写链。
  Future<MaterialManifestDocument> _removeWhere(
    bool Function(MaterialRecord entry) shouldRemove,
  ) => _mutate(
    (current) => MaterialManifestDocument(
      materials: [
        for (final entry in current.materials)
          if (!shouldRemove(entry)) entry,
      ],
      extra: current.extra,
    ),
  );

  /// 写链：一次「读 → 改 → 写」，返回改后的清单（各写入口共用，不互相
  /// 覆盖）。盘上文件不可写（高于本版 / 版本头读不出，见
  /// [DocumentVersionPolicy.isWritable]）时跳过写盘、返回读取结果。
  Future<MaterialManifestDocument> _mutate(
    MaterialManifestDocument Function(MaterialManifestDocument current) change,
  ) {
    final run = _chain.then((_) async {
      final json = await _storage.load();
      final current = _materialManifestCodec.decode(json);
      if (!MaterialManifestDocument.versionPolicy.isWritable(json)) {
        return current;
      }
      final next = change(current);
      await _storage.save(_materialManifestCodec.encode(next));
      return next;
    });
    _chain = run.then<void>((_) {}, onError: (_) {});
    return run;
  }
}

/// 私有素材基目录：应用支持目录下 `materials/`
/// ——不入视频索引目录（索引在应用文档目录）。生产默认实现；测试经
/// [materialsBaseDirectoryProvider] 覆盖。
Future<Directory> defaultMaterialsBaseDirectory() =>
    getApplicationSupportDirectory().then(
      (dir) => Directory(p.join(dir.path, 'materials')),
    );

/// 私有素材基目录注入点（返回目录解析器的 provider seam；测试覆盖为
/// 临时目录，不触 path_provider）。
final materialsBaseDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultMaterialsBaseDirectory,
);

/// 素材清单文件（`<素材基目录>/manifest.json`）。
final materialManifestStorageProvider = Provider<MaterialManifestStorage>((
  ref,
) {
  return MaterialManifestFileStore(
    ref
        .watch(materialsBaseDirectoryProvider)()
        .then((dir) => File(p.join(dir.path, 'manifest.json'))),
  );
});

final materialManifestStoreProvider = Provider<MaterialManifestStore>(
  (ref) => MaterialManifestStore(ref.watch(materialManifestStorageProvider)),
);

/// 素材文件在素材基目录下的落位（唯一来源）：`<base>/<videoId>/<fileName>`
/// ——录制输出解析与素材库删除共用此布局，改落位只动这里。
String materialFilePathIn(String basePath, String videoId, String fileName) =>
    p.join(basePath, videoId, fileName);

/// 删除某支舞的全部素材文件：素材按舞分目录，整目录删净——清单条目对应的
/// 文件与未入清单的录制残留（中断的录制、`.tmp`、清单写失败产物）一起消失，
/// 不留再也进不去的孤儿素材。目录不存在视作已删；失败向上抛（调用方
/// best-effort）。布局的唯一来源同 [materialFilePathIn]。
Future<void> deleteMaterialFilesForVideo(
  String basePath,
  String videoId,
) async {
  final directory = Directory(p.join(basePath, videoId));
  if (directory.existsSync()) directory.deleteSync(recursive: true);
}

/// 录制输出文件解析：`<素材基目录>/<videoId>/rec_<时间戳>.mp4`
/// ——素材文件落私有素材目录，不入视频索引目录。测试可覆盖。
final materialRecordingFileResolverProvider =
    Provider<Future<File> Function(String videoId)>((ref) {
      return (videoId) async {
        final base = await ref.watch(materialsBaseDirectoryProvider)();
        final dir = Directory(p.join(base.path, videoId))
          ..createSync(recursive: true);
        return File(
          p.join(dir.path, 'rec_${DateTime.now().microsecondsSinceEpoch}.mp4'),
        );
      };
    });
