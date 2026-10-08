/// **投屏缓存**（设备级私有目录里的一块渲染缓存区，ADR-0005）：把一份渲染
/// **请求**（按它的缓存键）对到盘上的一份**投屏副本**。
///
/// ## 它只管三件事
///
/// - **命中**：[find] —— 产物在不在（只问最终产物，**半成品不算命中**）；
/// - **落位**：[partFileFor] 给出渲染中的临时名、[promote] 把临时名**换名**成
///   产物名（同目录换名是原子的：中断在换名前，盘上就只有半成品，下次渲染
///   重新来过）；
/// - **收尾**：[discard] 删掉半成品——取消与失败都走它，所以「取消或失败不留
///   半成品」是缓存契约的结构性后果，不是调用方的纪律。
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
/// 建目录 / 换名 / 删中间文件都走 `*Sync`：这三下都在**交互路径**上（面板起
/// 渲染、收尾），而异步文件 IO 在 widget 测试的假时钟下**不可完成**（仓内既有
/// 口径：`lib/dance/video_copy_presence.dart` 与素材库删除同款先例）。文件很小、
/// 操作是元数据级的，同步不影响帧；渲染本身（ffmpeg 与拍声轨写盘）才走异步。
///
/// ## 不属本件
///
/// 容量上限、按最近使用淘汰、占用统计与「详细设置」里的清空入口归 #34
/// （缓存账）；本件只保证键与产物的对应关系。缓存**不写任何文档、不进
/// susume 包、不随整机备份**（ADR-0005）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/video_identity.dart' show XxHash64;
import 'cast_render_request.dart';

/// 渲染缓存基目录：应用支持目录下 `cast_render/`——**独立于** `materials/`
/// （练习素材）与出站分享目录，按 ADR-0005 的落位口径。生产默认实现；
/// 测试经 [castRenderCacheDirectoryProvider] 覆盖成临时目录。
Future<Directory> defaultCastRenderCacheDirectory() =>
    getApplicationSupportDirectory().then(
      (dir) => Directory(p.join(dir.path, 'cast_render')),
    );

/// 渲染缓存基目录注入点（返回目录解析器的 provider seam；测试覆盖为临时
/// 目录，不触 path_provider）。
final castRenderCacheDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => defaultCastRenderCacheDirectory,
);

/// 投屏渲染缓存目录（`<基目录>/`）。
class CastRenderCache {
  const CastRenderCache({required this.directory});

  /// 缓存基目录的解析器（每次用时才解析——不在构造期触 path_provider）。
  final Future<Directory> Function() directory;

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

  /// 落定：把 [part] 换名成这份请求的产物，返回产物文件。
  ///
  /// [part] 不在盘上（执行器没写出来）时抛 [FileSystemException]——那是一次
  /// 声明成功却没产物的渲染，调用方按失败收口。
  Future<File> promote(File part, CastRenderRequest request) async {
    final product = await productFileFor(request);
    // 同目录换名：元数据级操作，同步即可（见库头）。
    part.renameSync(product.path);
    return product;
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
}

/// 渲染缓存注入点（唯一实例）。
final castRenderCacheProvider = Provider<CastRenderCache>(
  (ref) =>
      CastRenderCache(directory: ref.watch(castRenderCacheDirectoryProvider)),
);
