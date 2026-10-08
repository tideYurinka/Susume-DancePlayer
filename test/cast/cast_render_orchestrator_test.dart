import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_orchestrator.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/cast/cast_speed_tier.dart'
    show castCopyDuration;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_cast_render_executor.dart';

/// 渲染编排直测：命中不重渲、都不勾直接推原片、进度上报、可取消、**取消或
/// 失败不留半成品**——经脚本化执行器接缝测，不跑进程；缓存用真实临时目录。
void main() {
  late Directory root;
  late FakeCastRenderExecutor executor;
  late CastRenderCache cache;
  late CastRenderOrchestrator orchestrator;
  final loadedAssets = <String>[];

  setUp(() {
    root = Directory.systemTemp.createTempSync('cast_render_orchestrator_test');
    executor = FakeCastRenderExecutor();
    cache = CastRenderCache(directory: () async => root);
    loadedAssets.clear();
    orchestrator = CastRenderOrchestrator(
      cache: cache,
      executor: executor,
      loadAssetBytes: (asset) async {
        loadedAssets.add(asset);
        return _wav(samples: const [1000, 1000]);
      },
    );
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  CastRenderRequest request({
    CastRenderChoices choices = const CastRenderChoices(
      picture: false,
      sound: true,
    ),
    List<CastBeatClick> beatClicks = const [
      CastBeatClick(
        time: Duration(milliseconds: 500),
        asset: 'assets/sounds/metronome_beat.wav',
        volume: 0.5,
      ),
    ],
    List<CastSticker> stickers = const [],
    CastBeatCountOverlay? beatOverlay,
    Duration duration = const Duration(seconds: 2),
    CastSpeedTier speedTier = CastSpeedTier.full,
  }) => CastRenderRequest(
    videoPath: p.join(root.path, 'source.mp4'),
    videoId: 'vid-a',
    duration: duration,
    choices: choices,
    speedTier: speedTier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
    stickers: stickers,
    beatOverlay: beatOverlay,
    beatClicks: beatClicks,
  );

  List<String> fileNames() => FakeCastRenderExecutor.fileNamesIn(root.path);

  group('不渲染与命中', () {
    test('都不勾：直接推原片，一条命令都不装配', () async {
      final result = await orchestrator.render(
        request(choices: const CastRenderChoices.none()),
      );

      expect(result.exit, CastRenderExit.passedThrough);
      expect(result.filePath, p.join(root.path, 'source.mp4'));
      expect(executor.ran, isFalse);
      expect(fileNames(), isEmpty, reason: '不渲染不落任何文件');
    });

    test('命中缓存：不重渲，直接给那一份产物', () async {
      final req = request();
      final product = await cache.productFileFor(req);
      File(product.path).writeAsStringSync('rendered');

      final result = await orchestrator.render(req);

      expect(result.exit, CastRenderExit.cached);
      expect(result.filePath, product.path);
      expect(executor.ran, isFalse, reason: '命中就不该再跑一次渲染');
      expect(loadedAssets, isEmpty, reason: '命中时连拍声资产都不必读');
    });

    test('命中即记一次使用：那一份的最近使用时间刷新到现在', () async {
      final req = request();
      final product = await cache.productFileFor(req);
      File(product.path).writeAsStringSync('rendered');
      final longAgo = DateTime(2020, 1, 1);
      product.setLastModifiedSync(longAgo);

      final result = await orchestrator.render(req);

      expect(result.exit, CastRenderExit.cached);
      expect(
        product.statSync().modified.isAfter(longAgo),
        isTrue,
        reason: '投出去的那一份要排到淘汰队尾（缓存账按最近使用淘汰）',
      );
    });

    test('缓存没命中：跑一次并把产物落定到那把键上', () async {
      final req = request();
      final result = await orchestrator.render(req);

      expect(result.exit, CastRenderExit.rendered);
      expect(executor.ran, isTrue);
      expect(await cache.find(req), isNotNull, reason: '落定后立刻命中');
      expect(result.filePath, (await cache.find(req))!.path);

      // 再投一次同一份请求：走命中，不重渲。
      executor.runs.clear();
      final again = await orchestrator.render(req);
      expect(again.exit, CastRenderExit.cached);
      expect(executor.ran, isFalse);
    });

    test('盘上只有产物：半成品与拍声轨都收了', () async {
      final req = request();
      await orchestrator.render(req);

      expect(fileNames().length, 1, reason: '半成品与拍声轨都不留在缓存里');
      expect(p.extension(fileNames().single), '.mp4');
    });
  });

  group('声音类：拍声轨是第二路输入', () {
    test('渲染时拍声轨真的在盘上（资产经注入点读）', () async {
      String? clickTrack;
      bool existedDuringRun = false;
      executor.onRun = (job, _) {
        clickTrack = job.arguments.firstWhere(
          (a) => a.endsWith('.clicks.wav'),
          orElse: () => '',
        );
        existedDuringRun = File(clickTrack!).existsSync();
      };

      await orchestrator.render(request());

      expect(loadedAssets, ['assets/sounds/metronome_beat.wav']);
      expect(clickTrack, isNotNull);
      expect(existedDuringRun, isTrue, reason: '命令跑起来时拍声轨必须已经写好');
      expect(File(clickTrack!).existsSync(), isFalse, reason: '渲染收尾要删掉它');
    });

    test('拍声资产读不到：这次渲染失败，不留半个产物', () async {
      final failing = CastRenderOrchestrator(
        cache: cache,
        executor: executor,
        loadAssetBytes: (_) async => throw StateError('资产缺失'),
      );

      final result = await failing.render(request());

      expect(result.exit, CastRenderExit.failed);
      expect(result.filePath, isNull);
      expect(executor.ran, isFalse, reason: '命令都没装配起来');
      expect(fileNames(), isEmpty);
    });

    test('素材时长未知（0）：不渲那条错拍的轨，按失败收口', () async {
      final result = await orchestrator.render(
        CastRenderRequest(
          videoPath: p.join(root.path, 'source.mp4'),
          videoId: 'vid-a',
          duration: Duration.zero,
          choices: const CastRenderChoices(picture: false, sound: true),
          speedTier: CastSpeedTier.full,
          settings: const CastRenderSettings(),
          annotationFingerprint: 'fp-1',
          beatClicks: const [
            CastBeatClick(time: Duration.zero, asset: 'a.wav', volume: 1),
          ],
        ),
      );

      expect(result.exit, CastRenderExit.failed);
      expect(executor.ran, isFalse);
      expect(fileNames(), isEmpty);
    });

    test('画面类不勾声音：不读拍声资产、没有拍声轨输入', () async {
      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
        ),
      );

      expect(loadedAssets, isEmpty);
      expect(
        executor.lastArguments.any((a) => a.endsWith('.clicks.wav')),
        isFalse,
      );
      expect(
        executor.lastArguments,
        containsAllInOrder(['-c:a', 'copy']),
        reason: '不勾声音就不重编码音轨',
      );
    });
  });

  group('进度与取消', () {
    test('进度照执行器报的原样转出去', () async {
      final seen = <CastRenderProgress>[];
      executor.onRun = (job, _) {
        // 假执行器没有真 ffmpeg 的统计回调，这里手工把两条进度递出去。
        seen.add(
          CastRenderProgress(
            rendered: const Duration(milliseconds: 250),
            total: job.total,
          ),
        );
      };

      await orchestrator.render(request(), onProgress: seen.add);

      expect(seen.length, 1);
      expect(seen.single.fraction, 0.125, reason: '250ms / 2s');
    });

    test('进度分母按倍速档换算：三档各自是产物的期望时长', () async {
      // 源片 6 秒：0.5× 档产物 12 秒、0.75× 档 8 秒、1× 档 6 秒
      // （`setpts=PTS/rate`；分母用源时长会在过半时就读到 100%）。
      for (final tier in CastSpeedTier.values) {
        await orchestrator.render(
          request(duration: const Duration(seconds: 6), speedTier: tier),
        );
      }

      expect(
        executor.totals,
        const [
          Duration(seconds: 12),
          Duration(seconds: 8),
          Duration(seconds: 6),
        ],
        reason: '执行器拿到的分母逐档是产物的期望时长',
      );
    });

    test('半数进度对应的时间：0.5× 档走到源时长那一刻只算一半', () {
      const source = Duration(seconds: 30);
      // 进度读到「源片时长」这一刻：0.5× 档的产物还有一半没渲完。
      final progress = CastRenderProgress(
        rendered: source,
        total: castCopyDuration(source, CastSpeedTier.half),
      );

      expect(progress.total, const Duration(seconds: 60));
      expect(progress.fraction, closeTo(0.5, 1e-9));
      // 分母错用源时长时的读数（曾经的缺陷）：同一刻报 100%。
      expect(
        const CastRenderProgress(rendered: source, total: source).fraction,
        1,
      );
    });

    test('取消：结局是取消、盘上不留半成品、也不给可推的文件', () async {
      executor.runGate = Completer<void>();
      final pending = orchestrator.render(request());
      await _until(() => executor.ran);

      await orchestrator.cancel();
      final result = await pending;

      expect(executor.cancelCalls, 1);
      expect(result.exit, CastRenderExit.cancelled);
      expect(result.filePath, isNull);
      expect(fileNames(), isEmpty, reason: '取消不留半成品');
    });

    test('没在跑时取消：空操作', () async {
      await orchestrator.cancel();
      expect(executor.cancelCalls, 0, reason: '没在渲就没有可取消的东西');
    });

    test('失败：结局是失败、半成品删掉、已有产物不受影响', () async {
      final req = request();
      executor.verdict = CastRenderVerdict.failed;

      final result = await orchestrator.render(req);

      expect(result.exit, CastRenderExit.failed);
      expect(result.filePath, isNull);
      expect(fileNames(), isEmpty, reason: '失败不留半成品');
      expect(await cache.find(req), isNull);
    });

    test('执行器抛异常：按失败收口，不留半成品', () async {
      executor.runError = StateError('ffmpeg 起不来');

      final result = await orchestrator.render(request());

      expect(result.exit, CastRenderExit.failed);
      expect(fileNames(), isEmpty);
    });

    test('上次崩在中途留下的半成品：这次渲染前先清掉', () async {
      final req = request();
      final stale = await cache.partFileFor(req);
      File(stale.path).writeAsStringSync('stale');

      final result = await orchestrator.render(req);

      expect(result.exit, CastRenderExit.rendered);
      expect(fileNames().length, 1, reason: '只剩这一份产物');
      expect(p.extension(fileNames().single), '.mp4');
    });
  });

  group('贴纸图：画面类里的第二路输入，收尾必删', () {
    CastSticker sheet({int startMs = 200, int endMs = 900}) => CastSticker(
      imageBytesOf: () async =>
          Uint8List.fromList(const [0x89, 0x50, 0x4e, 0x47, 7, 7, 7]),
      startMs: startMs,
      endMs: endMs,
      centerX: 0.3,
      centerY: 0.2,
      widthFraction: 0.25,
      heightFraction: 0.1,
    );

    test('渲染时贴纸图真的在盘上（字节就是请求里那一份），命令按它作第二路输入', () async {
      String? stickerPath;
      var existed = false;
      var bytes = const <int>[];
      executor.onRun = (job, _) {
        stickerPath = job.arguments.firstWhere(
          (a) => a.endsWith('.sticker0.png'),
          orElse: () => '',
        );
        existed = File(stickerPath!).existsSync();
        bytes = File(stickerPath!).readAsBytesSync();
      };

      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
          stickers: [sheet()],
        ),
      );

      expect(existed, isTrue, reason: '命令跑起来时贴纸图必须已经写好');
      expect(bytes, <int>[0x89, 0x50, 0x4e, 0x47, 7, 7, 7]);
      expect(
        executor.lastArguments,
        containsAllInOrder(['-i', stickerPath!]),
        reason: '贴纸是第二路输入',
      );
      expect(
        File(stickerPath!).existsSync(),
        isFalse,
        reason: '渲染收尾要删掉它（它是本次渲染的临时物，不是缓存里那一份）',
      );
      expect(fileNames().length, 1, reason: '盘上只剩产物');
    });

    test('多条贴纸：逐条落盘、路径表与请求一一对应', () async {
      final seen = <String>[];
      executor.onRun = (job, _) {
        seen.addAll(job.arguments.where((a) => a.endsWith('.png')).toList());
      };

      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
          stickers: [sheet(), sheet(startMs: 1200, endMs: 1800)],
        ),
      );

      expect(seen, hasLength(2));
      expect(seen[0], endsWith('.sticker0.png'));
      expect(seen[1], endsWith('.sticker1.png'));
      expect(fileNames(), hasLength(1));
    });

    test('失败：贴纸图与半成品一并收掉', () async {
      executor.verdict = CastRenderVerdict.failed;

      final result = await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
          stickers: [sheet()],
        ),
      );

      expect(result.exit, CastRenderExit.failed);
      expect(fileNames(), isEmpty);
    });

    test('不勾画面类：贴纸图不落盘、命令里没有第二路输入', () async {
      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: false, sound: false),
          beatClicks: const [],
          stickers: [sheet()],
        ),
      );

      expect(executor.ran, isFalse, reason: '都不勾 = 直接推原片');
      expect(fileNames(), isEmpty);
    });
  });

  group('数拍层：逐格 PNG + 图像序列清单，收尾必删（#30）', () {
    CastBeatCountOverlay beatOverlay({int rows = 3}) => CastBeatCountOverlay(
      rows: <CastBeatCountRow>[
        for (var i = 0; i < rows; i++)
          CastBeatCountRow(
            startMs: i * 500,
            endMs: (i + 1) * 500,
            text: i == 0
                ? null
                : CastBeatCountText(
                    eightCount: '1',
                    beatCount: '$i',
                  ),
          ),
      ],
      centerX: 0.4,
      centerY: 0.3,
      widthFraction: 0.2,
      heightFraction: 0.1,
      imageBytesOf: (index) async =>
          Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, index]),
    );

    test('渲染时逐格 PNG 与清单都在盘上，命令按 `-f concat` 读它', () async {
      var listBody = '';
      var listPath = '';
      var sheetPaths = const <String>[];
      var allExisted = false;
      executor.onRun = (job, _) {
        listPath = job.arguments.firstWhere(
          (a) => a.endsWith('.beats.txt'),
          orElse: () => '',
        );
        listBody = File(listPath).readAsStringSync();
        // 逐格图的路径只在清单里（序列是一路输入，不是几十路 -i）。
        sheetPaths = RegExp(r"^file '(.+)'$", multiLine: true)
            .allMatches(listBody)
            .map((m) => m.group(1)!)
            .toList(growable: false);
        allExisted = sheetPaths.every((f) => File(f).existsSync());
      };

      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
          beatOverlay: beatOverlay(),
        ),
      );

      expect(allExisted, isTrue, reason: '命令跑起来时每一格图都必须已经写好');
      // 三格各一条 file，末条重列一次（共四条）。
      expect(sheetPaths, hasLength(4));
      expect(sheetPaths[0], endsWith('.beat0.png'));
      expect(sheetPaths[1], endsWith('.beat1.png'));
      expect(sheetPaths.last, sheetPaths[2]);
      expect(listPath, isNotEmpty);
      expect(
        executor.lastArguments,
        containsAllInOrder(<String>['-f', 'concat', '-safe', '0', '-i', listPath]),
      );
      // 时长就是那一拍的半开窗（0.5s 一拍）。
      expect(listBody, contains('duration 0.500'));
      expect(
        File(listPath).existsSync(),
        isFalse,
        reason: '渲染收尾要删掉清单（它是本次渲染的临时物）',
      );
      for (final path in sheetPaths.toSet()) {
        expect(File(path).existsSync(), isFalse, reason: '逐格图也要删干净');
      }
      expect(fileNames().length, 1, reason: '盘上只剩产物');
    });

    test('失败：逐格图、清单与半成品一并收掉', () async {
      executor.verdict = CastRenderVerdict.failed;

      final result = await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: true, sound: false),
          beatClicks: const [],
          beatOverlay: beatOverlay(),
        ),
      );

      expect(result.exit, CastRenderExit.failed);
      expect(fileNames(), isEmpty);
    });

    test('不勾画面类：数拍层一格都不落盘', () async {
      await orchestrator.render(
        request(
          choices: const CastRenderChoices(picture: false, sound: false),
          beatClicks: const [],
          beatOverlay: beatOverlay(),
        ),
      );

      expect(executor.ran, isFalse);
      expect(fileNames(), isEmpty);
    });
  });
}

/// 等一个条件成立（编排里夹着真实文件 IO，不能只靠一次 microtask 让路）。
Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 2000 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  if (!ready()) fail('等不到条件成立');
}

/// 造一段最小 16 位 PCM WAV（合成轨的输入资产）。
Uint8List _wav({required List<int> samples}) {
  final dataBytes = samples.length * 2;
  final bytes = Uint8List(44 + dataBytes);
  final view = ByteData.view(bytes.buffer);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, 1, Endian.little);
  view.setUint32(24, 22050, Endian.little);
  view.setUint32(28, 22050 * 2, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return bytes;
}
