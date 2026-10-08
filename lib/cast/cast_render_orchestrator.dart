/// **投屏渲染编排**：把「一份请求 → 一份可投的产物」这条链收在一处——
/// 命中缓存就用现成的、都不勾就直接给原片、缺了才真渲，并负责进度、取消、
/// 拍声轨与**收尾不留半成品**。
///
/// ## 一次渲染的次序（每一步都有它的理由）
///
/// 1. **都不勾** → 不装配命令、不碰缓存，直接把源片路径交出去（零等待）；
/// 2. **命中** → 交缓存里那一份（券同键同产物；命中时不读拍声资产、不跑
///    命令）；
/// 3. **拍声轨**（声音类才做）→ 把排程合成为一条 WAV，写进缓存目录；
/// 3b. **贴纸图**（画面类且有备注才做）→ 把请求里那份带 alpha 的 PNG 逐条落盘
///    （与拍声轨同款：半成品旁边的临时物，收尾必删）；
/// 3c. **数拍层图序列**（画面类且装了数拍层才做，`#30`）→ 逐格 PNG 落盘 +
///    一份 `-f concat` 清单（每格的时长就是那一拍的半开窗）；
/// 4. **装配 + 执行** → `buildCastRenderArguments` 给命令，执行器跑它并按
///    ffmpeg 统计回调报进度；
/// 5. **收尾**（无论成败）→ 删拍声轨与贴纸图；成功把半成品**换名**成产物
///    （原子）、失败与取消把半成品删掉。
///
/// 所以「取消或失败不留半成品」不是调用方纪律，而是这条链的收尾步骤。
///
/// ## 边界
///
/// 本件不碰界面（进度经回调出去）、不碰投屏会话（产物路径交给起投那一层）、
/// 不碰接收端。一次只渲一份（本域一次投屏只投一支舞和一个倍速档）；#31 的
/// 多档后台渲染在它之上编排，不改本件的契约。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cast_beat_gate.dart';
import 'cast_beat_track.dart';
import 'cast_range_gate.dart' show castCopyDurationOf;
import 'cast_render_cache.dart';
import 'cast_render_executor.dart';
import 'cast_render_plan.dart';
import 'cast_render_request.dart';

/// 一次编排的结局。
enum CastRenderExit {
  /// 命中缓存：用的是上一次渲好的那一份。
  cached,

  /// 这次真渲出来了一份。
  rendered,

  /// 都不勾：直接推原片，没渲染。
  passedThrough,

  /// 被取消（用户按了取消 / 换了路径）。
  cancelled,

  /// 渲染失败（编码器报错、拍声轨出不来、产物没落下）。
  failed,
}

/// 编排结局：可投文件的路径 + 它是怎么来的。
///
/// [filePath] 只在 [CastRenderExit.cached] / [rendered] / [passedThrough]
/// 三种结局下非空——取消与失败**没有**可投的文件（半成品已经删掉了）。
class CastRenderResult {
  const CastRenderResult({required this.exit, required this.filePath});

  final CastRenderExit exit;
  final String? filePath;

  /// 有没有一份可以用来投屏的文件。
  bool get usable => filePath != null;

  @override
  String toString() => 'CastRenderResult($exit, $filePath)';
}

/// 投屏渲染编排器（一次一份）。
class CastRenderOrchestrator {
  CastRenderOrchestrator({
    required this.cache,
    required this.executor,
    required this.loadAssetBytes,
  });

  final CastRenderCache cache;
  final CastRenderExecutor executor;

  /// 读一段随包资产（拍声段）的字节；测试注入内存替身，不触 asset bundle。
  final Future<Uint8List> Function(String assetPath) loadAssetBytes;

  bool _rendering = false;

  /// 渲 [request]；[onProgress] 可多次调用。
  Future<CastRenderResult> render(
    CastRenderRequest request, {
    void Function(CastRenderProgress progress)? onProgress,
  }) async {
    if (!request.choices.renders) {
      return CastRenderResult(
        exit: CastRenderExit.passedThrough,
        filePath: request.videoPath,
      );
    }

    final hit = await cache.find(request);
    if (hit != null) {
      // 命中就是这一次**投**用了那一份：刷新它的最近使用时间，缓存账按这一刻
      // 重排淘汰次序（天天投的那一支不该因为渲得早而被淘汰）。
      await cache.markUsed(request);
      return CastRenderResult(exit: CastRenderExit.cached, filePath: hit.path);
    }

    // 上次崩在中途留下的半成品：先清掉，免得这次失败时与它纠缠。
    final part = await cache.partFileFor(request);
    await cache.discard(part);

    File? clickTrack;
    final stickerFiles = <File>[];
    final beatSheetFiles = <File>[];
    File? beatSlidesList;
    _rendering = true;
    try {
      if (request.choices.sound) {
        clickTrack = await _writeClickTrack(request, part);
      }
      if (request.choices.picture && request.stickers.isNotEmpty) {
        stickerFiles.addAll(await _writeStickerSheets(request, part));
      }
      // **数拍层**（#30）：逐格 PNG（一格一拍的半开窗）+ 一份 `-f concat` 清单
      // ——与拍声轨、贴纸图同款：半成品旁边的临时物，收尾必删。
      if (request.choices.picture && castBeatCountActive(request.beatOverlay)) {
        final overlay = request.beatOverlay!;
        for (var i = 0; i < overlay.rows.length; i++) {
          final file = File('${part.path}.beat$i.png');
          await file.writeAsBytes(await overlay.imageBytesOf(i), flush: true);
          beatSheetFiles.add(file);
        }
        beatSlidesList = File('${part.path}.beats.txt');
        await beatSlidesList.writeAsString(
          castBeatSlidesContent(
            rows: overlay.rows,
            paths: [for (final file in beatSheetFiles) file.path],
          ),
          flush: true,
        );
      }
      final arguments = buildCastRenderArguments(
        request: request,
        outputPath: part.path,
        beatTrackPath: clickTrack?.path,
        beatSlidesPath: beatSlidesList?.path,
        stickerPaths: [for (final file in stickerFiles) file.path],
      );
      final verdict = await executor.run(
        CastRenderJob(
          arguments: arguments,
          // 分母是**产物**的期望时长，不是源时长：范围生效时产物只有首线→
          // 尾线那一段，再按倍速档换算（`setpts=PTS/rate` 让 0.5× 档的产物长
          // 一倍）。拿源时长当分母会在 ffmpeg 走到源片时长那一刻就报 100%
          // （那时产物还有一半没渲完），拿整片当分母则会让收窄过的那一档一
          // 直停在开头。
          total: castCopyDurationOf(request),
        ),
        onProgress: onProgress,
      );
      if (verdict != CastRenderVerdict.succeeded) {
        await cache.discard(part);
        return CastRenderResult(
          exit: verdict == CastRenderVerdict.cancelled
              ? CastRenderExit.cancelled
              : CastRenderExit.failed,
          filePath: null,
        );
      }
      final product = await cache.promote(part, request);
      return CastRenderResult(
        exit: CastRenderExit.rendered,
        filePath: product.path,
      );
    } on Object {
      // 拍声轨合不出来、命令没装配起来、执行器自己抛：都按这次渲染失败收口，
      // 半成品删干净——界面只需要一个「没渲成」。
      await cache.discard(part);
      return const CastRenderResult(
        exit: CastRenderExit.failed,
        filePath: null,
      );
    } finally {
      _rendering = false;
      if (clickTrack != null) await cache.discard(clickTrack);
      for (final file in stickerFiles) {
        await cache.discard(file);
      }
      for (final file in beatSheetFiles) {
        await cache.discard(file);
      }
      if (beatSlidesList != null) await cache.discard(beatSlidesList);
    }
  }

  /// 取消正在跑的那一次渲染；没在跑时是空操作。
  Future<void> cancel() async {
    if (!_rendering) return;
    await executor.cancel();
  }

  /// 把拍声排程合成一条 WAV，落在半成品旁边（渲染收尾必删）。
  Future<File> _writeClickTrack(CastRenderRequest request, File part) async {
    if (request.duration <= Duration.zero) {
      // 素材时长未知：拍声轨没有可对齐的时间轴，宁可不渲也不投一条错拍的轨。
      throw StateError('素材时长未知，拍声轨无从对齐');
    }
    final assets = <String, Uint8List>{};
    for (final click in request.beatClicks) {
      if (assets.containsKey(click.asset)) continue;
      assets[click.asset] = await loadAssetBytes(click.asset);
    }
    final bytes = buildCastBeatTrackWav(
      clicks: request.beatClicks,
      assets: assets,
      duration: request.duration,
    );
    final file = File('${part.path}.clicks.wav');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// 把请求里的贴纸图逐条落到半成品旁边（渲染收尾必删）。
  ///
  /// 字节由**播放页侧**按上屏同一份 span 与样式光栅化
  /// （`CastSticker.imageBytesOf` 那个惰性口）
  /// ——投屏域不 import 播放页、也不自己画字；这里只负责它是文件这件事，与拍声轨
  /// 同款。路径表与请求里的贴纸**一一对应**：空窗的贴纸照样落一个文件、照样占
  /// 一个输入位（错位比多喂一个输入危险得多）。
  Future<List<File>> _writeStickerSheets(
    CastRenderRequest request,
    File part,
  ) async {
    final files = <File>[];
    for (var i = 0; i < request.stickers.length; i++) {
      final file = File('${part.path}.sticker$i.png');
      await file.writeAsBytes(
        await request.stickers[i].imageBytesOf(),
        flush: true,
      );
      files.add(file);
    }
    return files;
  }
}

/// 拍声段资产的字节读取口：生产走 asset bundle，测试注入内存替身。
final castBeatAssetBytesProvider =
    Provider<Future<Uint8List> Function(String assetPath)>((ref) {
      return (assetPath) async {
        final data = await rootBundle.load(assetPath);
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      };
    });

/// 渲染编排注入点（唯一实例）。
final castRenderOrchestratorProvider = Provider<CastRenderOrchestrator>((ref) {
  return CastRenderOrchestrator(
    cache: ref.watch(castRenderCacheProvider),
    executor: ref.watch(castRenderExecutorProvider),
    loadAssetBytes: ref.watch(castBeatAssetBytesProvider),
  );
});
