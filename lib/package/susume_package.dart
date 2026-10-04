/// susume 包模块：本功能唯一那个问题的
/// 一处回答——「一个 susume 包是什么」。清单编解码、包格式版本门、装配
/// 与解析、文件名都只在这里；分享、导入、备份、恢复四条链路只经此模块
/// 理解包格式。
///
/// - **清单自述**：包格式版本、视频标识、方案名、方案标识、可选组员名、
///   可选逐段熟练度快照；媒体按勾选装入。接收方据清单判断这是哪支舞的
///   哪个方案，不依赖文件名。清单编解码逐键手工声明：未知键原样忽略
///   （陌生键保底），必填键缺失按损坏报错。
/// - **包格式版本门：不符即明确报错**（[SusumePackageError.versionMismatch]），
///   不静默降级。这与文档内部的版本纪律（地板 + 按序迁移链；读不懂按
///   「认识多少读多少」打开并只读）刻意相反：那条针对本机自己写的文件，
///   这条针对用户主动拿来的东西（见词条「susume 包」）。
/// - **入参与出参都是纯值**：方案的公开六段内容（标注文档 JSON 值，编解码
///   归既有文档模型）、可选的逐段熟练度、可选的媒体清单、可选组员名。
///   不做编排——建舞、写组员方案、复制媒体是接线层的事。
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';

import '../core/stored_zip.dart';
import '../persistence/song_signature.dart' show songFallbackName;

/// 包格式版本。判据 = 严格相等，不符即 [SusumePackageError.versionMismatch]。
const int kSusumePackageFormatVersion = 1;

/// 包内各条目名（写读两处共用，模块外不出现字面量）。
const String kSusumeManifestEntry = 'manifest.json';
const String _kMarkersEntry = 'markers.json';
const String _kMediaDir = 'media/';

/// 整机包的 payload 条目：备份的整机 JSON 值——
/// 索引、全部舞的方案与私密字段、设备级设置。与舞级包的 `markers.json`
/// 互斥，装哪种由清单的 kind 决定。
const String kSusumeBackupEntry = 'backup.json';

/// 包的装配形态：[dance] = 一支舞一个方案，
/// [backup] = 整机备份。两态共用同一份清单与同一个包格式版本门
/// （见词条「susume 包」），只差 payload 条目与必填字段。
enum SusumePackageKind { dance, backup }

/// 媒体种类：源视频副本 / 练习录像。种类进清单，接收方不必从条目名猜。
enum SusumeMediaKind { sourceVideo, practiceClip }

/// 媒体条目：种类 + 文件名（zip 内条目名由此派生）+ 字节数。装配时带
/// [file]（源文件）；解析出的包中 [file] 为 null。
class SusumeMediaEntry {
  const SusumeMediaEntry({
    required this.kind,
    required this.fileName,
    required this.sizeBytes,
    this.file,
  });

  final SusumeMediaKind kind;
  final String fileName;
  final int sizeBytes;

  /// 装配时的源文件；解析出的条目上为 null。
  final File? file;

  /// zip 内条目名。
  String get entryName => _mediaEntryName(fileName);

  @override
  bool operator ==(Object other) =>
      other is SusumeMediaEntry &&
      other.kind == kind &&
      other.fileName == fileName &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(kind, fileName, sizeBytes);
}

/// 清单值对象：包自述的身份与内容清单。
class SusumeManifest {
  const SusumeManifest({
    this.kind = SusumePackageKind.dance,
    required this.videoId,
    required this.schemeName,
    this.schemeDancer = '',
    this.schemeRemark = '',
    required this.schemeId,
    this.memberName,
    this.mastery,
    this.media = const [],
  });

  /// 装配形态。舞级包不写该键（清单原文不变），整机包写
  /// `'backup'`；解析缺键按 dance 兜底。
  final SusumePackageKind kind;

  /// 视频内容标识（xxHash64 串）。整机包不使用（空串）。
  final String videoId;

  /// 方案名（署名歌曲名；未署名时由调用方以视频文件名代入——清单不存
  /// 回落规则，回落只作用于包文件名）。整机包不使用（空串）。
  final String schemeName;

  /// 署名的版本舞者与版本注记（[schemeName] 是歌曲名本身，不整串拼显示
  /// 文本——接收方按三字段结构化落盘）。旧版包缺键按空串兜底；整机包
  /// 不使用（空串）。
  final String schemeDancer;
  final String schemeRemark;

  /// 方案标识：发送方生成的稳定串，同标识再导入即替换、异标识即新增。
  /// 整机包不使用（空串）。
  final String schemeId;

  /// 可选组员名（发送方署的自己的名字）。
  final String? memberName;

  /// 可选的逐段熟练度快照（键 = 段序，值 = 档位数值，即
  /// `LearningMastery` 枚举数值 0–4）；null = 未勾选随包。
  final Map<int, int>? mastery;

  /// 随包装入的媒体（已勾选）。
  final List<SusumeMediaEntry> media;

  @override
  bool operator ==(Object other) =>
      other is SusumeManifest &&
      other.kind == kind &&
      other.videoId == videoId &&
      other.schemeName == schemeName &&
      other.schemeDancer == schemeDancer &&
      other.schemeRemark == schemeRemark &&
      other.schemeId == schemeId &&
      other.memberName == memberName &&
      _mapEquals(other.mastery, mastery) &&
      _listEquals(other.media, media);

  @override
  int get hashCode => Object.hash(
    kind,
    videoId,
    schemeName,
    schemeDancer,
    schemeRemark,
    schemeId,
    memberName,
    Object.hashAll(mastery?.keys ?? const <int>[]),
    Object.hashAll(media),
  );
}

/// 解析出的包：清单 + 标注文档 JSON 值（公开六段，编解码归既有文档模型）。
/// 整机包（[SusumePackageKind.backup]）的整机 payload 在 [backup]，
/// [markers] 为空 Map；舞级包相反。
class SusumePackage {
  const SusumePackage({
    required this.manifest,
    required this.markers,
    this.backup,
  });

  final SusumeManifest manifest;
  final Map<String, Object?> markers;

  /// 整机 payload；舞级包为 null。
  final Map<String, Object?>? backup;

  bool get isBackup => manifest.kind == SusumePackageKind.backup;

  /// 包里是否带了源视频副本（导入分支树的先决判据：没带一律拒绝）。
  bool get hasSourceVideo =>
      manifest.media.any((entry) => entry.kind == SusumeMediaKind.sourceVideo);
}

/// 包错误的种类。每类都是明确报错，不静默降级。
enum SusumePackageError {
  /// 包格式版本不符（更新或更旧的 Susume 所写）。
  versionMismatch,

  /// 根本不是 zip。
  notZip,

  /// zip 可解但内容损坏（清单缺失/非 JSON/必填字段缺失或类型不符）。
  corrupt,
}

/// 包模块的明确报错。
class SusumePackageException implements Exception {
  const SusumePackageException(this.kind, this.message);

  final SusumePackageError kind;
  final String message;

  @override
  String toString() => 'SusumePackageException($kind): $message';
}

/// 包文件名 `<歌名>.susume`；未署名时回落「文件名回落名」——即
/// [songFallbackName] 去扩展名的文件名，规则单处出在纯件里，本层不另写
/// 一份。歌名/回落名中的路径分隔与文件系统非法字符替换为 `_`。
String susumePackageFileName({
  String? songName,
  required String videoFileName,
}) {
  final n = (songName?.trim() ?? '');
  var base = n.isNotEmpty ? n : songFallbackName(videoFileName);
  base = base.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
  return '$base.susume';
}

/// 备份包文件名：`Susume备份_<日期时间>.susume`。备份不含单支舞的身份
/// （清单不靠文件名辨认），名字只求用户在分享面板里认得出、多次备份不
/// 互相覆盖。
String susumeBackupFileName({required DateTime now}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp =
      '${now.year}${two(now.month)}${two(now.day)}'
      '-${two(now.hour)}${two(now.minute)}';
  return 'Susume备份_$stamp.susume';
}

/// 装配：把清单、标注文档 JSON 值与勾选的媒体写成一个 `.susume` 文件。
/// 条目一律 STORED，媒体经流式分块写出。
///
/// 舞级包（[SusumePackageKind.dance]）必填 videoId/schemeName/schemeId
/// 与 [markers]；整机包（[SusumePackageKind.backup]）必填 [backup]、不
/// 使用舞级字段。装错形态（给整机包传 payload 之外的必填校验不通过、或
/// 给舞级包传 [backup]）即 [ArgumentError]。
Future<void> writeSusumePackage({
  required File output,
  required SusumeManifest manifest,
  required Map<String, Object?> markers,
  Map<String, Object?>? backup,
}) async {
  final isBackup = manifest.kind == SusumePackageKind.backup;
  if (isBackup) {
    if (backup == null) {
      throw ArgumentError.value(backup, 'backup', '整机包必填整机 payload');
    }
  } else {
    if (backup != null) {
      throw ArgumentError.value(backup, 'backup', '舞级包不装整机 payload');
    }
    if (manifest.videoId.isEmpty) {
      throw ArgumentError.value(manifest.videoId, 'videoId', '必填');
    }
    if (manifest.schemeName.isEmpty) {
      throw ArgumentError.value(manifest.schemeName, 'schemeName', '必填');
    }
    if (manifest.schemeId.isEmpty) {
      throw ArgumentError.value(manifest.schemeId, 'schemeId', '必填');
    }
  }

  final manifestJson = <String, Object?>{
    'version': kSusumePackageFormatVersion,
    if (isBackup) 'kind': 'backup',
    if (!isBackup) ...{
      'videoId': manifest.videoId,
      'schemeName': manifest.schemeName,
      'schemeDancer': manifest.schemeDancer,
      'schemeRemark': manifest.schemeRemark,
      'schemeId': manifest.schemeId,
      if (manifest.memberName != null) 'memberName': manifest.memberName!,
      if (manifest.mastery != null)
        'mastery': {
          for (final e in manifest.mastery!.entries) '${e.key}': e.value,
        },
    },
    'media': [
      for (final m in manifest.media)
        {
          'kind': switch (m.kind) {
            SusumeMediaKind.sourceVideo => 'sourceVideo',
            SusumeMediaKind.practiceClip => 'practiceClip',
          },
          'fileName': m.fileName,
          'sizeBytes': m.sizeBytes,
        },
    ],
  };

  final entries = <StoredZipEntry>[
    (
      name: kSusumeManifestEntry,
      bytes: utf8.encode(jsonEncode(manifestJson)),
      file: null,
    ),
    if (isBackup)
      (
        name: kSusumeBackupEntry,
        bytes: utf8.encode(jsonEncode(backup)),
        file: null,
      )
    else
      (
        name: _kMarkersEntry,
        bytes: utf8.encode(jsonEncode(markers)),
        file: null,
      ),
  ];
  for (final m in manifest.media) {
    final file = m.file;
    if (file == null) {
      throw ArgumentError.value(m, 'media', '媒体条目缺少源文件');
    }
    entries.add((name: m.entryName, bytes: null, file: file));
  }
  await writeStoredZip(output, entries);
}

/// 解析：读清单、过包格式版本门、取标注文档 JSON 值与媒体清单。
/// 非 zip / 损坏 / 版本不符各得明确报错，不静默降级。
Future<SusumePackage> readSusumePackage(String path) async {
  // 先核 zip 签名（本地文件头 PK\x03\x04 或空包 PK\x05\x06）：解码器对
  // 任意字节流会安静地返回空包，签名不在才谈得上「不是 zip」
  final head = await File(path)
      .openRead(0, 4)
      .fold<List<int>>(<int>[], (acc, chunk) => acc..addAll(chunk));
  final isZip =
      head.length == 4 &&
      head[0] == 0x50 &&
      head[1] == 0x4b &&
      (head[2] == 0x03 || head[2] == 0x05 || head[2] == 0x07);
  if (!isZip) {
    throw const SusumePackageException(
      SusumePackageError.notZip,
      '不是 susume 包（不是 zip 容器）',
    );
  }

  final Archive archive;
  final stream = InputFileStream(path);
  try {
    archive = ZipDecoder().decodeStream(stream);
  } on FormatException {
    // ArchiveException 是 FormatException 的子类：签名在而结构损坏
    throw const SusumePackageException(
      SusumePackageError.corrupt,
      '包损坏（zip 结构不完整）',
    );
  } finally {
    await stream.close();
  }

  ArchiveFile? find(String name) {
    for (final f in archive.files) {
      if (f.name == name) return f;
    }
    return null;
  }

  final manifestFile = find(kSusumeManifestEntry);
  if (manifestFile == null) {
    throw const SusumePackageException(SusumePackageError.corrupt, '包内缺少清单');
  }

  final Object? manifestRaw;
  try {
    manifestRaw = jsonDecode(utf8.decode(manifestFile.content));
  } on FormatException {
    throw const SusumePackageException(
      SusumePackageError.corrupt,
      '清单不是合法 JSON',
    );
  }
  if (manifestRaw is! Map) {
    throw const SusumePackageException(
      SusumePackageError.corrupt,
      '清单不是 JSON 对象',
    );
  }
  final manifestJson = manifestRaw.cast<String, Object?>();

  final version = manifestJson['version'];
  if (version is! int || version != kSusumePackageFormatVersion) {
    throw SusumePackageException(
      SusumePackageError.versionMismatch,
      '包格式版本不符：$version（本机支持 $kSusumePackageFormatVersion）',
    );
  }

  // 装配形态：缺键按舞级兜底（舞级清单没有该键）；写了不认识的值按
  // 损坏报错，不猜。
  final kind = switch (manifestJson['kind']) {
    null || 'dance' => SusumePackageKind.dance,
    'backup' => SusumePackageKind.backup,
    _ => throw const SusumePackageException(
      SusumePackageError.corrupt,
      '清单 kind 值不认识',
    ),
  };
  final isBackup = kind == SusumePackageKind.backup;

  String required(String key) {
    final v = manifestJson[key];
    if (v is! String || v.isEmpty) {
      throw SusumePackageException(SusumePackageError.corrupt, '清单缺少必填字段 $key');
    }
    return v;
  }

  // 舞级必填字段只在舞级包上要求：整机包没有单支舞的身份。
  final videoId = isBackup ? '' : required('videoId');
  final schemeName = isBackup ? '' : required('schemeName');
  final schemeId = isBackup ? '' : required('schemeId');
  // 旧版包无这两个键：按空串兜底（陌生键保底的同族纪律）。
  String optionalText(String key) {
    final v = isBackup ? '' : manifestJson[key];
    return v is String ? v : '';
  }

  final schemeDancer = optionalText('schemeDancer');
  final schemeRemark = optionalText('schemeRemark');
  final memberNameRaw = isBackup ? null : manifestJson['memberName'];
  final memberName = memberNameRaw is String && memberNameRaw.isNotEmpty
      ? memberNameRaw
      : null;

  Map<int, int>? mastery;
  final masteryRaw = manifestJson['mastery'];
  if (masteryRaw != null) {
    if (masteryRaw is! Map) {
      throw const SusumePackageException(
        SusumePackageError.corrupt,
        '清单 mastery 字段类型不符',
      );
    }
    // mastery 是清单已声明的数据（不是陌生键）：键非段序、值非 0–4 档位
    // 一律按损坏报错，不静默缺段——静默缺段会把「少了一段」伪装成发送方
    // 没练过，一路传进导入编排
    final masteryJson = masteryRaw.cast<String, Object?>();
    mastery = {};
    for (final e in masteryJson.entries) {
      final order = int.tryParse(e.key);
      final value = e.value;
      if (order == null || value is! int || value < 0 || value > 4) {
        throw SusumePackageException(
          SusumePackageError.corrupt,
          '清单 mastery 键值不合法：${e.key}=$value',
        );
      }
      mastery[order] = value;
    }
  }

  final media = <SusumeMediaEntry>[];
  final mediaRaw = manifestJson['media'];
  if (mediaRaw != null) {
    if (mediaRaw is! List) {
      throw const SusumePackageException(
        SusumePackageError.corrupt,
        '清单 media 字段类型不符',
      );
    }
    for (final item in mediaRaw) {
      if (item is! Map) {
        throw const SusumePackageException(
          SusumePackageError.corrupt,
          '媒体条目不是 JSON 对象',
        );
      }
      final entryJson = item.cast<String, Object?>();
      final kindName = entryJson['kind'];
      final kind = switch (kindName) {
        'sourceVideo' => SusumeMediaKind.sourceVideo,
        'practiceClip' => SusumeMediaKind.practiceClip,
        _ => throw const SusumePackageException(
          SusumePackageError.corrupt,
          '媒体条目种类不明',
        ),
      };
      final fileName = entryJson['fileName'];
      final sizeBytes = entryJson['sizeBytes'];
      if (fileName is! String || fileName.isEmpty || sizeBytes is! int) {
        throw const SusumePackageException(
          SusumePackageError.corrupt,
          '媒体条目缺少必填字段',
        );
      }
      media.add(
        SusumeMediaEntry(kind: kind, fileName: fileName, sizeBytes: sizeBytes),
      );
    }
  }

  Map<String, Object?>? backup;
  var markers = const <String, Object?>{};
  if (isBackup) {
    backup = _decodeJsonEntry(
      find(kSusumeBackupEntry),
      missing: '整机包内缺少整机内容',
      notJson: '整机内容不是合法 JSON',
      notObject: '整机内容不是 JSON 对象',
    );
  } else {
    markers = _decodeJsonEntry(
      find(_kMarkersEntry),
      missing: '包内缺少标注内容',
      notJson: '标注内容不是合法 JSON',
      notObject: '标注内容不是 JSON 对象',
    );
  }

  return SusumePackage(
    manifest: SusumeManifest(
      kind: kind,
      videoId: videoId,
      schemeName: schemeName,
      schemeDancer: schemeDancer,
      schemeRemark: schemeRemark,
      schemeId: schemeId,
      memberName: memberName,
      mastery: mastery,
      media: media,
    ),
    markers: markers,
    backup: backup,
  );
}

/// 把包内的一个媒体条目解出到 [dest]（接线层复制媒体时用）。
///
/// 每次调用重新解码整包（zip 中央目录在文件尾、条目按名寻址经完整解析）；
/// 接线层解出多个媒体条目时宜逐条调用一次而非按条目数重复扫同一遍——
/// 这是流式/寻址约束下的取舍，媒体条目数通常只有个位数。
Future<void> extractMediaEntry(String path, String entryName, File dest) async {
  final stream = InputFileStream(path);
  try {
    final archive = ZipDecoder().decodeStream(stream);
    for (final f in archive.files) {
      if (f.name == entryName) {
        final out = OutputFileStream(dest.path);
        try {
          f.decompress(out);
        } finally {
          await out.close();
        }
        return;
      }
    }
    throw SusumePackageException(
      SusumePackageError.corrupt,
      '包内没有媒体条目 $entryName',
    );
  } finally {
    await stream.close();
  }
}

/// 解出包内一个 JSON 对象条目；缺失/非 JSON/非对象各得明确报错。
Map<String, Object?> _decodeJsonEntry(
  ArchiveFile? file, {
  required String missing,
  required String notJson,
  required String notObject,
}) {
  if (file == null) {
    throw SusumePackageException(SusumePackageError.corrupt, missing);
  }
  final Object? raw;
  try {
    raw = jsonDecode(utf8.decode(file.content));
  } on FormatException {
    throw SusumePackageException(SusumePackageError.corrupt, notJson);
  }
  if (raw is! Map) {
    throw SusumePackageException(SusumePackageError.corrupt, notObject);
  }
  return raw.cast<String, Object?>();
}

String _mediaEntryName(String fileName) {
  final safe = fileName.replaceAll(RegExp(r'[/\\]'), '_');
  return '$_kMediaDir$safe';
}

bool _mapEquals(Map<int, int>? a, Map<int, int>? b) {
  if (a == null || b == null) return identical(a, b);
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    if (a[k] != b[k]) return false;
  }
  return true;
}

bool _listEquals(List<SusumeMediaEntry> a, List<SusumeMediaEntry> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
