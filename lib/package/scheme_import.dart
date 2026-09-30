/// 从分享文件导入：导入编排接线层——建舞、写组员
/// 方案、写成我的标注、复制媒体的编排在此，包格式知识全部经包模块。
///
/// 导入分流是一棵三分支的树，判据只有两个：本机是否已有
/// 该视频标识、包里是否带了逐段熟练度快照（[resolveImportBranch]，纯函数）：
///
/// - 已有这支舞 → 问归属：「写成我的标注」把包里公开标注整份写进我的
///   公开标记文件并清空本地文档的逐段熟练度与激活（沿整机恢复同款直接
///   写入，不经标注编辑的 verb 门禁），「留成TA的方案」依方案标识替换或
///   新增一条只读方案；落成组员方案才问组员名。
/// - 没有这支舞、包里没带熟练度 → 直接建舞并把标注写成我的，不问任何
///   问题。
/// - 没有这支舞、包里带了熟练度 → 问归属：「建成我的标注方案」丢弃他带
///   的熟练度快照，「建成组员方案」落一条带熟练度快照的只读方案。
/// - 包里没有源视频副本 → 一律拒绝并明确告知「请先导入视频」；这一条
///   先于归属选择，对三分支都成立。
///
/// 包的版本门与「根本不是 Susume 包」的报错由包模块给出，本层翻译成
/// 用户看得懂的提示（[SchemeImportFailed.message]）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../import/import_providers.dart'
    show videoIndexStoreProvider, videoImporterProvider;
import '../import/picked_video.dart';
import '../import/video_importer.dart';
import '../persistence/video_index.dart';
import '../dance/dance_library_providers.dart' show danceLibraryWritesProvider;
import '../persistence/document_read_outcome.dart';
import '../persistence/local_document.dart';
import '../persistence/member_scheme_store.dart';
import '../persistence/song_signature.dart';
import '../persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import '../persistence/video_document_store.dart'
    show VideoDocumentCoordinator, VideoDocumentStorage;
import 'susume_package.dart';

/// 导入落成哪种归属（结果提示区分三种落点的依据）：
/// - [writtenAsMine]：包里公开标注整份写成了我的标注（含新建舞写成我的）；
/// - [keptAsMemberScheme]：留成组员方案（本机已有这支舞）；
/// - [createdAsMemberScheme]：建成组员方案（新建舞）。
enum SchemeImportLanding {
  writtenAsMine,
  keptAsMemberScheme,
  createdAsMemberScheme,
}

/// 导入归属（页面选择面的出口落到编排的输入）。编排只认「落成什么」；
/// 「要不要问」由 [resolveImportBranch] 在页面流程回答。
sealed class SchemeImportIntent {
  const SchemeImportIntent();
}

/// 写成我的标注：包里公开标注整份写进我的公开标记文件；落成组员方案的
/// 分支不走这里，熟练度快照因此自然丢弃。
class WriteAsMyMarkers extends SchemeImportIntent {
  const WriteAsMyMarkers();
}

/// 落成组员方案：[memberName] 为空串 = 未署名。
class LandAsMemberScheme extends SchemeImportIntent {
  const LandAsMemberScheme(this.memberName);

  final String memberName;
}

/// 三分支的判定值（纯层可直测，不启动 widget）。
enum SchemeImportBranch {
  /// 已有这支舞：问「写成我的标注 / 留成TA的方案」，还能取消。
  askOwnership,

  /// 没有这支舞、包里没带熟练度：直接建舞写成我的，不问。
  createAsMine,

  /// 没有这支舞、包里带了熟练度：问「建成我的标注方案 / 建成组员方案」。
  askCreateOwnership,
}

SchemeImportBranch resolveImportBranch({
  required bool danceExists,
  required bool packageHasMastery,
}) {
  if (danceExists) return SchemeImportBranch.askOwnership;
  return packageHasMastery
      ? SchemeImportBranch.askCreateOwnership
      : SchemeImportBranch.createAsMine;
}

/// 导入结果（对外可观察值）：导入成功（含落点与是否新建了舞）、明确拒绝、
/// 明确失败。message 均为可直接展示的用户话术。
sealed class SchemeImportOutcome {
  const SchemeImportOutcome();
}

/// 导入成功：[memberName]（发送方署名，落成组员方案时为用户确认的组员名）
/// 的方案挂到了 [danceTitle]；[createdDance] = 本机没有这支舞、由包内源
/// 视频新建了这支舞；[importedAt] = 导入时刻（结果提示「什么时候」的取值
/// 来源）。
class SchemeImported extends SchemeImportOutcome {
  const SchemeImported({
    required this.landing,
    required this.memberName,
    required this.danceTitle,
    required this.createdDance,
    required this.importedAt,
  });

  final SchemeImportLanding landing;
  final String memberName;
  final String danceTitle;
  final bool createdDance;
  final DateTime importedAt;
}

/// 明确拒绝：这支舞的视频不在包里——不建无归属的方案。
class SchemeImportRejected extends SchemeImportOutcome {
  const SchemeImportRejected(this.message);

  final String message;
}

/// 明确失败：包读不开（版本不符 / 损坏 / 不是 Susume 包）。
class SchemeImportFailed extends SchemeImportOutcome {
  const SchemeImportFailed(this.message);

  final String message;
}

/// 「包里没带源视频」的拒绝话术（编排与页面流程两道拦截共用一处）。
const schemeImportSourceVideoMissingMessage = '这支舞的视频不在包里，请先导入视频';

/// 包报错 → 用户话术（唯一出处，编排与页面共用）。
String translateSusumePackageError(SusumePackageException error) =>
    switch (error.kind) {
      SusumePackageError.versionMismatch => '这个文件来自更新版本的 Susume，请先升级',
      SusumePackageError.notZip ||
      SusumePackageError.corrupt => '文件损坏或不是 Susume 包，无法导入',
    };

/// 导入编排。
class SchemeImporter {
  SchemeImporter({
    required this.indexStore,
    required this.videoImporter,
    required this.schemeStoreFor,
    required this.documentStorageFor,
    this.titleWriter,
    this.now = DateTime.now,
  });

  final VideoIndexStorage indexStore;
  final VideoImporter videoImporter;

  /// 组员方案存取入口（同一 videoId 必须取同一实例 = 单条写链；生产经
  /// [memberSchemeStoreProvider]）。
  final MemberSchemeStore Function(String videoId) schemeStoreFor;

  /// 按舞双文档写入口（「写成我的标注」沿整机恢复同款直接整份写入；
  /// 生产经 [videoDocumentStorageFactoryProvider]）。
  final VideoDocumentStorage Function(String videoId) documentStorageFor;

  /// 建舞分支的署名写入（生产经 [DanceLibraryWrites.rename]：markers 署名
  /// 真值 + 索引署名缓存两条都写）。新建的舞只有源视频文件名可显示——
  /// 舞名以包清单的方案名（署名歌曲名）立底，不依赖文件名。null = 不写
  /// （默认回落文件名）。best-effort：写失败不阻断导入。
  final Future<bool> Function(String videoId, SongSignature signature)?
  titleWriter;
  final DateTime Function() now;

  /// 本机是否已有该视频标识（页面流程回答「要不要问归属」用）。
  Future<bool> hasDance(String videoId) async =>
      (await indexStore.load()).findById(videoId) != null;

  /// 落一条组员方案：导入时间的取值只在此一处。
  Future<void> _writeScheme({
    required String videoId,
    required SusumePackage package,
    required String memberName,
  }) async {
    await schemeStoreFor(videoId).upsert(
      MemberSchemeRecord(
        schemeId: package.manifest.schemeId,
        memberName: memberName,
        schemeName: package.manifest.schemeName,
        mastery: package.manifest.mastery,
        importedAt: now(),
        markers: package.markers,
      ),
    );
  }

  /// 「写成我的标注」：包里公开标注整份写进我的公开标记
  /// 文件，不逐字段挑、不合并；同时清空本地文档里的逐段熟练度与激活
  /// （几何已换、按段序的派生量即失效），编辑偏好、浮层几何、取景取值、
  /// 练习片段列表与素材策略原样。直接写入先例 = 整机恢复，不经标注编辑
  /// 模块的 verb 门禁——门禁管的是编辑，管不到「换一套标注」。
  /// 包里公开标注整份写进我的公开标记文件（不逐字段挑、不合并）。
  Future<void> _writeMarkersWhole(String videoId, SusumePackage package) =>
      documentStorageFor(videoId)
          .saveMarkers(Map<String, dynamic>.from(package.markers));

  Future<void> _overwriteMyMarkers(
    String videoId,
    SusumePackage package,
  ) async {
    await _writeMarkersWhole(videoId, package);
    final storage = documentStorageFor(videoId);
    final outcome = await VideoDocumentCoordinator(storage).readLocalOutcome();
    if (outcome is! WritableDocumentReadOutcome<LocalDocument>) return;
    await outcome.write(
      (context) => context.document
          .withMasteryMap(const {})
          .withActivatedSegments(const []),
    );
  }

  /// 舞标题：署名缓存优先、显示名兜底（与舞库卡片口径同源）。
  String _danceTitle(VideoIndexEntry entry) =>
      signatureDisplayText(entry.signatureCache, entry.displayName);

  /// 完整导入：解析包 → 视频判据 → 按 [intent] 落成归属 → 返回结果。
  /// [package] 传入时不再重复解析（页面流程已读过一次）。
  Future<SchemeImportOutcome> importScheme({
    required PickedVideo picked,
    required SchemeImportIntent intent,
    SusumePackage? package,
    bool? danceExists,
  }) async {
    if (package == null) {
      try {
        package = await readPackage(picked);
      } on SusumePackageException catch (error) {
        return SchemeImportFailed(translateSusumePackageError(error));
      }
    }
    final resolved = package;

    // 「包里没带源视频」先于归属选择：三分支一律拒绝并说清下一步。
    if (!resolved.hasSourceVideo) {
      return const SchemeImportRejected(schemeImportSourceVideoMissingMessage);
    }

    final videoId = resolved.manifest.videoId;
    // 页面流程已按同一判据选过面；传入 danceExists 时以它为准，分支判定
    // 全程只查一次索引（两处各查会在竞态下让面与落点不一致）。
    final existing = danceExists == false
        ? null
        : (await indexStore.load()).findById(videoId);
    return switch (intent) {
      WriteAsMyMarkers() =>
        existing != null
            ? await _writeAsMineToExisting(videoId, resolved, existing)
            : await _createDance(picked, resolved, memberName: null),
      LandAsMemberScheme(:final memberName) =>
        existing != null
            ? await _landAsMemberScheme(
                videoId: videoId,
                package: resolved,
                memberName: memberName,
                entry: existing,
              )
            : await _createDance(picked, resolved, memberName: memberName),
    };
  }

  Future<SchemeImported> _writeAsMineToExisting(
    String videoId,
    SusumePackage package,
    VideoIndexEntry entry,
  ) async {
    await _overwriteMyMarkers(videoId, package);
    return SchemeImported(
      landing: SchemeImportLanding.writtenAsMine,
      memberName: package.manifest.memberName ?? '',
      danceTitle: _danceTitle(entry),
      createdDance: false,
      importedAt: now(),
    );
  }

  Future<SchemeImported> _landAsMemberScheme({
    required String videoId,
    required SusumePackage package,
    required String memberName,
    required VideoIndexEntry entry,
  }) async {
    final name = memberName.trim();
    await _writeScheme(videoId: videoId, package: package, memberName: name);
    return SchemeImported(
      landing: SchemeImportLanding.keptAsMemberScheme,
      memberName: name,
      danceTitle: _danceTitle(entry),
      createdDance: false,
      importedAt: now(),
    );
  }

  /// 建舞分支：包内源视频解出到临时文件，交既有视频导入管道（复制进私有
  /// 目录、算内容哈希、建索引）。[memberName] = null 落成我的标注（熟练度
  /// 快照丢弃），否则落一条带熟练度快照的组员方案。
  Future<SchemeImported> _createDance(
    PickedVideo picked,
    SusumePackage package, {
    required String? memberName,
  }) async {
    // 源视频判据在 importScheme 先行拦下：走到这里必然带着源视频。
    final sourceEntry = _sourceVideoOf(package)!;
    final tempDir = await Directory.systemTemp.createTemp('susume_import');
    try {
      final extracted = File(p.join(tempDir.path, sourceEntry.fileName));
      await extractMediaEntry(
        picked.sourceUri.toFilePath(),
        sourceEntry.entryName,
        extracted,
      );
      final dance = await videoImporter.importDanceFile(
        PickedVideo(
          name: sourceEntry.fileName,
          sourceUri: extracted.uri,
          sizeBytes: sourceEntry.sizeBytes,
        ),
      );
      final SchemeImportLanding landing;
      if (memberName == null) {
        await _writeMarkersWhole(dance.videoId, package);
        landing = SchemeImportLanding.writtenAsMine;
      } else {
        final name = memberName.trim();
        await _writeScheme(
          videoId: dance.videoId,
          package: package,
          memberName: name,
        );
        landing = SchemeImportLanding.createdAsMemberScheme;
      }
      final title = package.manifest.schemeName;
      if (title.isNotEmpty && titleWriter != null) {
        try {
          await titleWriter!(
            dance.videoId,
            SongSignature(
              song: title,
              dancer: package.manifest.schemeDancer,
              remark: package.manifest.schemeRemark,
            ),
          );
        } on Object {
          // 署名写失败不阻断导入：舞名回落文件名，方案已挂上。
        }
      }
      final entry = (await indexStore.load()).findById(dance.videoId);
      return SchemeImported(
        landing: landing,
        memberName: memberName?.trim() ?? package.manifest.memberName ?? '',
        danceTitle: entry == null ? dance.video.name : _danceTitle(entry),
        createdDance: true,
        importedAt: now(),
      );
    } finally {
      // 解出物是私有副本的中转，管道复制完即无用了。
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    }
  }

  /// 解析包（页面流程先经此取清单做归属面与组员名预填；测试注入 fake
  /// 覆盖本方法即可走通整条页面流程）。
  Future<SusumePackage> readPackage(PickedVideo picked) =>
      readSusumePackage(picked.sourceUri.toFilePath());

  SusumeMediaEntry? _sourceVideoOf(SusumePackage package) {
    for (final entry in package.manifest.media) {
      if (entry.kind == SusumeMediaKind.sourceVideo) return entry;
    }
    return null;
  }
}

final schemeImporterProvider = Provider<SchemeImporter>((ref) {
  return SchemeImporter(
    indexStore: ref.watch(videoIndexStoreProvider),
    videoImporter: ref.watch(videoImporterProvider),
    schemeStoreFor: (videoId) => ref.watch(memberSchemeStoreProvider(videoId)),
    documentStorageFor: ref.watch(videoDocumentStorageFactoryProvider),
    titleWriter: (videoId, signature) async {
      final entry = (await ref.watch(videoIndexStoreProvider).load()).findById(
        videoId,
      );
      if (entry == null) return false;
      return ref
          .watch(danceLibraryWritesProvider)
          .rename(entry: entry, input: signature);
    },
  );
});
