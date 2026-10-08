import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_orchestrator.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
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
  }) => CastRenderRequest(
    videoPath: p.join(root.path, 'source.mp4'),
    videoId: 'vid-a',
    duration: const Duration(seconds: 2),
    choices: choices,
    speedTier: CastSpeedTier.full,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
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
