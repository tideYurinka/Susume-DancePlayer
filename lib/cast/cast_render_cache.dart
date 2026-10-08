/// **投屏缓存**（设备级私有目录里的一块投屏缓存区，ADR-0005）：把一份渲染
/// **请求**（按它的缓存键）对到盘上的一份**投屏副本**。
///
/// ## 它管两件事：**键 → 产物** 与 **缓存账**
///
/// 键那一侧：
///
/// - **命中**：[find] —— 产物在不在（只问最终产物，**半成品不算命中**）；
/// - **落位**：[partFileFor] 给出渲染中的临时名、[promote] 把临时名**换名**成
///   产物名（同目录换名是原子的：中断在换名前，盘上就只有半成品，下次渲染
///   重新来过）；
/// - **收尾**：[discard] 删掉半成品——取消与失败都走它，所以「取消或失败不留
///   半成品」是缓存契约的结构性后果，不是调用方的纪律。
///
/// 账那一侧（ADR-0005 的容量账，票 #34）：
///
/// - **占用**：[usageBytes] —— 这块盘上现在被缓存占了多少（递归算真实字节，
///   产物与半成品都算）；
/// - **上限与淘汰**：[limitBytes] 是全局上限，[promote] 落定即按它收紧、按
///   **最近使用**从旧到新淘汰（[markUsed] 刷新一份的最近使用时间）；
/// - **清空**：[clear] 把缓存区里的东西全删——「详细设置」那一行走它。
///
/// ## 落位：键落在目录上，文件名沿用这支舞的源片名
///
/// `<基目录>/<键摘要>/<源片名>`。两个理由：
///
/// - 键（五个分量）合起来是一条长串，直接进文件名既不好看也未必合法——摘要
///   十六进制把它收成一个定长目录名，**同键同目录、任一分量变了即换目录**；
/// - **递出通道拿文件名当片名**（`dlna_cast_session.dart` 的 `_titleOf`），
///   所以产物叫什么名字，电视上就显示什么名字。产物名沿用源片名，电视上因此
///   还是这支舞的名字，而不是一个摘要——渲染过一次不该把片名弄丢。
///
/// ## 文件操作是**同步**的
///
/// 建目录 / 换名 / 删中间文件 / 统计占用 / 淘汰 / 清空都走 `*Sync`：它们都在
/// **交互路径**上（面板起渲染、收尾、设置页那一行），而异步文件 IO 在 widget
/// 测试的假时钟下**不可完成**（仓内既有口径：`lib/dance/video_copy_presence.dart`
/// 与素材库删除同款先例）。文件很小、操作是元数据级的，同步不影响帧；渲染本身
/// （ffmpeg 与拍声轨写盘）才走异步。
///
/// ## 缓存不进任何包
///
/// 缓存**不写任何文档、不进 susume 包、不随整机备份**（ADR-0005）：它落在独立
/// 的缓存区里，两条载荷清单因此一个字都不用改——`test/cast/
/// cast_cache_payload_manifest_test.dart` 把两条清单逐位钉住。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/video_identity.dart' show XxHash64;
import 'cast_render_request.dart';

/// 投屏缓存基目录：应用支持目录下 `cast_render/`——**独立于** `materials/`
/// （练习素材）与出站分享目录，按 ADR-0005 的落位口径。生产默认实现；
/// 测试经 [castRenderCacheDirectoryProvider] 覆盖成临时目录。
Future<Directory> defaultCastRenderCacheDirectory() =>
    getApplicationSupportDirectory().then(
      (dir) => Directory(p.join(dir.path, 'cast_render')),
    );

/// **投屏缓存的全局容量上限**：2 GiB。
///
/// 取值的口径：一支 1080p 的舞一份副本约几十到几百兆，三个**投屏倍速档**各一
/// 份；2 GiB 大致够几支舞同时在缓存里轮着练，超过它就该把最久没用过的那几份
/// 腾出去（投屏副本可再生——重渲一次而已，占满用户的盘才是真代价）。
const int kCastRenderCacheLimitBytes = 2 * 1024 * 1024 * 1024;

/// 投屏缓存基目录注入点（返回目录解析器的 provider seam；测试覆盖为临时
/// 目录，不触 path_provider）。
final castRenderCacheDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultCastRenderCacheDirectory,
);

/// 投屏缓存目录（`<基目录>/`）。
class CastRenderCache {
  const CastRenderCache({
    required this.directory,
    this.limitBytes = kCastRenderCacheLimitBytes,
  });

  /// 缓存基目录的解析器（每次用时才解析——不在构造期触 path_provider）。
  final Future<Directory> Function() directory;

  /// **全局容量上限**（字节）：缓存区总占用超过它时按最近使用淘汰。
  ///
  /// 构造期注入（测试用小值构造超限），落定即按它收紧——见 [promote]。
  final int limitBytes;

  /// 这份请求对应的**产物**（最终文件；不保证存在）。
  Future<File> productFileFor(CastRenderRequest request) async {
    final dir = await _keyDirectory(request, create: true);
    return File(p.join(dir.path, deliveredNameFor(request)));
  }

  /// 这份请求对应的**半成品**（渲染中的临时名；与产物名不同，所以中断不会被
  /// 当成命中）。
  Future<File> partFileFor(CastRenderRequest request) async {
    final product = await productFileFor(request);
    return File('${product.path}.part');
  }

  /// 命中：产物在盘上就是它，否则 null（只问产物，不问半成品）。
  ///
  /// **只读**：连这把键的目录都不建——问一次命中不该在盘上留下任何东西。
  Future<File?> find(CastRenderRequest request) async {
    final dir = await _keyDirectory(request, create: false);
    final file = File(p.join(dir.path, deliveredNameFor(request)));
    return file.existsSync() ? file : null;
  }

  /// 落定：把 [part] 换名成这份请求的产物，返回产物文件；随后**按 [limitBytes]
  /// 收紧缓存区**（超限即淘汰最久没用过的那些）。
  ///
  /// [part] 不在盘上（执行器没写出来）时抛 [FileSystemException]——那是一次
  /// 声明成功却没产物的渲染，调用方按失败收口。
  ///
  /// 收紧收在这里而不是调用方：缓存只在落定时长大，于是「上限真正生效」不是
  /// 调用方纪律，而是落定的结构性后果——将来多档后台渲染再多，也绕不过这一下。
  Future<File> promote(File part, CastRenderRequest request) async {
    final product = await productFileFor(request);
    // 同目录换名：元数据级操作，同步即可（见库头）。
    part.renameSync(product.path);
    await _evictOldestUntilWithinLimit(protected: product.parent);
    return product;
  }

  /// **记一次使用**：把这份产物的最近使用时间刷新到现在（命中缓存即用了一次）。
  ///
  /// 产物不在盘上（没渲过、或刚被淘汰）是空操作：连这把键的目录都不建。
  /// 「最近使用」= 这一份最后一次被**投**出去的时刻，不是它被渲出来的时刻——
  /// 天天投的那一支不该因为渲得早而被淘汰。
  Future<void> markUsed(CastRenderRequest request) async {
    final dir = await _keyDirectory(request, create: false);
    final file = File(p.join(dir.path, deliveredNameFor(request)));
    if (!file.existsSync()) return;
    try {
      file.setLastModifiedSync(DateTime.now());
    } on Object {
      // 刷新不了时间戳：这一份按它原来的时刻参与淘汰，不影响别的。
    }
  }

  /// **当前占用**：缓存区里所有文件的字节和（递归；产物与半成品都算——它答的
  /// 是「这块盘上现在被投屏缓存占了多少」）。缓存区还没建就是 0。
  Future<int> usageBytes() async {
    final base = await directory();
    return base.existsSync() ? _bytesIn(base) : 0;
  }

  /// **清空**：缓存区里的东西全删——产物、半成品、拍声轨残渣与来源不明的
  /// 孤儿文件都算。缓存区还没建是空操作。
  ///
  /// 它**只动缓存区这块盘**：标注（两份文档）、设备级设置与练习素材都不住在
  /// 这里（ADR-0005：缓存区独立于 `materials/` 与出站分享目录），所以「清空
  /// 不影响标注与设置」是落位的结构性后果。
  ///
  /// 删不掉的留一个孤儿在盘上：占用那一行会如实显示它（清空不掩盖失败），
  /// 下次渲染会覆盖它。
  Future<void> clear() async {
    final base = await directory();
    if (!base.existsSync()) return;
    for (final entity in base.listSync(followLinks: false)) {
      try {
        entity.deleteSync(recursive: true);
      } on Object {
        // 删不掉：留着，占用如实计它。
      }
    }
  }

  /// 收尾：删掉一个中间文件（半成品 / 拍声轨）。文件不在是空操作；删除失败
  /// 不抛——调用方正走在失败或取消的收尾路径上，不能被一次删文件挡住。
  Future<void> discard(File file) async {
    try {
      if (file.existsSync()) file.deleteSync();
    } on Object {
      // 删不掉：只留一个孤儿文件，下次渲染会覆盖它。
    }
  }

  /// 递出时对外用的**片名**：源片名（电视上看到的就是这个名字）；源片名取
  /// 不出时给一句兜底。
  static String deliveredNameFor(CastRenderRequest request) {
    final name = p.basename(request.videoPath);
    return name.isEmpty ? 'cast.mp4' : name;
  }

  /// 键 → 目录名：键是**可读记号**，目录名取它的摘要（定长、只含十六进制）。
  static String keyDirectoryName(CastRenderKey key) =>
      (XxHash64()..update(key.token.codeUnits)).digest();

  Future<Directory> _keyDirectory(
    CastRenderRequest request, {
    required bool create,
  }) async {
    final base = await directory();
    final dir = Directory(
      p.join(base.path, keyDirectoryName(request.cacheKey)),
    );
    if (create && !dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// 超限就淘汰，直到总占用回到 [limitBytes] 以内。
  ///
  /// - **缓存区根上的裸文件先走**：半成品与拍声轨都住在键目录里，根上不属于
  ///   任何一把键的只可能是残渣；它们计进占用（见 [usageBytes]），所以也得能
  ///   被清掉，否则上限在「有残渣」时收不拢。
  /// - **淘汰次序 = 最近使用时间升序**（最久没用过的先走）；同一时刻用过的按
  ///   目录名定序，所以淘汰次序可复现、不靠盘的枚举次序。
  /// - **[protected] 那一份不参与**：刚落定的产物永远不被自己挤掉。
  /// - **只剩一份时停手**：一份比上限还大时，宁可如实超限，也不给用户一个
  ///   「渲完就被删、下次再渲」的循环。
  Future<void> _evictOldestUntilWithinLimit({Directory? protected}) async {
    final base = await directory();
    if (!base.existsSync()) return;

    final leftovers = <File>[];
    final entries = <_CacheEntry>[];
    var total = 0;
    for (final entity in base.listSync(followLinks: false)) {
      if (entity is File) {
        leftovers.add(entity);
        total += _sizeOf(entity);
        continue;
      }
      if (entity is! Directory) continue;
      final bytes = _bytesIn(entity);
      total += bytes;
      entries.add((
        directory: entity,
        lastUsedAt: _lastUsedAt(entity),
        bytes: bytes,
      ));
    }
    if (total <= limitBytes) return;

    for (final file in leftovers) {
      if (total <= limitBytes) return;
      final bytes = _sizeOf(file);
      try {
        file.deleteSync();
      } on Object {
        // 删不掉：留着，占用如实超限。
        continue;
      }
      total -= bytes;
    }

    entries.sort((a, b) {
      final byTime = a.lastUsedAt.compareTo(b.lastUsedAt);
      return byTime != 0
          ? byTime
          : a.directory.path.compareTo(b.directory.path);
    });

    var remaining = entries.length;
    for (final entry in entries) {
      if (total <= limitBytes || remaining <= 1) return;
      if (protected != null && entry.directory.path == protected.path) continue;
      try {
        entry.directory.deleteSync(recursive: true);
      } on Object {
        // 这一份删不掉：留着它，继续看更近用过的那些。
        continue;
      }
      total -= entry.bytes;
      remaining--;
    }
  }

  /// 一个文件的字节数（统计期间刚被别处删掉时算 0）。
  static int _sizeOf(File file) {
    try {
      return file.lengthSync();
    } on Object {
      return 0;
    }
  }

  /// 一把键那块盘上所有文件的字节和（文件刚被别处删掉时跳过它）。
  static int _bytesIn(Directory dir) {
    var total = 0;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      total += _sizeOf(entity);
    }
    return total;
  }

  /// 一把键的**最近使用时间**：那块盘上最新的文件时间；一个文件都没有
  /// （只剩空目录）时取目录自己的时间。
  static DateTime _lastUsedAt(Directory dir) {
    DateTime? newest;
    for (final entity in dir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final DateTime at;
      try {
        at = entity.statSync().modified;
      } on Object {
        continue;
      }
      if (newest == null || at.isAfter(newest)) newest = at;
    }
    return newest ?? dir.statSync().modified;
  }
}

/// 缓存区里一把键那一份的账：目录、最近使用时间、占的字节数。
typedef _CacheEntry = ({Directory directory, DateTime lastUsedAt, int bytes});

/// 投屏缓存注入点（唯一实例）。
final castRenderCacheProvider = Provider<CastRenderCache>(
  (ref) =>
      CastRenderCache(directory: ref.watch(castRenderCacheDirectoryProvider)),
);
