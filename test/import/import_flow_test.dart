import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/index_file_provider.dart';
import 'package:dance_learning_app/import/picked_video.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/level_control.dart'
    show systemMediaVolumeControllerProvider;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/song_loudness.dart'
    show songLoudnessProbeProvider, SongLoudnessProbe;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/fake_beat_pipeline.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_system_volume.dart';
import '../helpers/poll.dart';
import '../helpers/fake_video_picker.dart';

/// 轮询等待 index.json 出现 [expected] 条条目（真实事件循环内调用）。
///
/// 读到半截 JSON（写入瞬时快照）时视为「尚未就绪」继续轮询；每轮
/// `tester.pump()`——首页成为舞库后会在启动时读索引，索引存取实例因此
/// 先在 fake 时钟区里建起来，其写链的续体要 pump 才推进（真实 IO 的完成
/// 事件在 fake 区里排队），只等真实定时器会看不到落盘。
Future<void> waitForIndexEntries(
  WidgetTester tester,
  File indexFile,
  int expected,
) {
  return pollUntil(
    () {
      if (!indexFile.existsSync()) return false;
      try {
        final raw =
            jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
        final entries = (raw['entries'] as List?) ?? const [];
        return entries.length >= expected;
      } on FormatException {
        return false; // 写入进行中的瞬时快照，重试。
      }
    },
    onTick: () => tester.pump(),
    reason: '索引应有 $expected 条条目落盘',
  );
}

/// 响度测量桩：不触达 ffmpeg（打开恢复会在已有 beat 时后台补测响度基准）。
class _FixedLoudnessProbe implements SongLoudnessProbe {
  const _FixedLoudnessProbe();

  @override
  Future<double> pcmRms(String videoPath) async => 0.1;
}

/// 同步读取 index.json 的条目列表。
List<Map<String, dynamic>> readIndexEntries(File indexFile) {
  final raw = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
  return [
    for (final e in (raw['entries'] as List? ?? const []))
      e as Map<String, dynamic>,
  ];
}

void main() {
  // 等真实文件 IO 的轮询预算：并行全量下真实 IO 被饿死，
  // 默认 300×10ms≈3s 偏紧，放宽到 15s。
  const ioPollTries = 1500;

  testWidgets('导入 → 自动进入全屏播放：复制、清缓存、后台哈希写入索引', (tester) async {
    // 夹具文件操作全部用同步 IO：widget 测试体在 fake async 时钟下，
    // 真实异步 IO 需在 tester.runAsync 中完成。
    final tempDir = Directory.systemTemp.createTempSync('import_flow_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final sourceFile = File(p.join(tempDir.path, 'dance.mp4'))
      ..writeAsBytesSync([1, 2, 3]);

    final engine = FakePlaybackEngine();
    final picker = FakeVideoPicker(
      PickedVideo(name: 'dance.mp4', sourceUri: sourceFile.uri, sizeBytes: 3),
    );
    final videosDir = Directory(p.join(tempDir.path, 'videos'));
    final indexFile = File(p.join(tempDir.path, 'index.json'));
    final systemUi = FakeSystemUi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          importIndexFileProvider.overrideWith((ref) async => indexFile),
          systemUiControllerProvider.overrideWithValue(systemUi),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 首页：从首页到全屏不超过两步——第 1 步点「导入视频」。
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(find.byType(PlayerPage), findsNothing);

    // 第 2 步选择文件（fake 选择器立即返回）；复制与后台哈希/索引是
    // 真实文件 IO，在 runAsync 的真实事件循环中完成。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import_video_button')));
      final copied = File(p.join(videosDir.path, 'dance.mp4'));
      // 轮询直至：真实复制完成（文件出现）且真实异步链推进到首页 push
      // 播放器（pump 推进 fake 时钟区里排队的续体）。
      await pollUntil(
        () => copied.existsSync() && tester.any(find.byType(PlayerPage)),
        onTick: () => tester.pump(),
        reason: '导入应把视频复制到私有目录并 push 播放器页',
      );
      // 后台 SHA-256 + 索引写入完成（不阻塞进入播放，但最终落盘）。
      await waitForIndexEntries(tester, indexFile, 1);
      expect(find.byType(PlayerPage), findsOneWidget, reason: '导入成功后应自动进入全屏播放');
    });
    await tester.pumpAndSettle();

    // 导入成功后自动进入全屏播放状态。
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(engine.isPlaying, isTrue);
    expect(systemUi.enterCount, 1);

    // 引擎打开的是复制到私有目录的文件（源文件字节不变）。
    final copied = File(engine.source!.toFilePath());
    expect(copied.path, startsWith(videosDir.path));
    expect(copied.path, isNot(sourceFile.path));
    expect(copied.readAsBytesSync(), [1, 2, 3]);
    expect(sourceFile.readAsBytesSync(), [1, 2, 3]);

    // 索引条目字段完整（videoId/显示名/路径/大小/快速键/镜像状态/最近打开）。
    final entry = readIndexEntries(indexFile).single;
    expect(entry['videoId'], isNotEmpty);
    expect(entry['displayName'], 'dance.mp4');
    expect(entry['filePath'], copied.path);
    expect(entry['sizeBytes'], 3);
    expect(entry['fastKey'], '3:dance.mp4');
    expect(entry['mirrored'], isFalse);
    expect(entry['lastOpenedAt'], isNotEmpty);

    // 选择器缓存已清理。
    expect(picker.clearCacheCalled, isTrue);
  });

  testWidgets('再次打开同一视频：快速键命中立即播放既有副本，索引不新增条目', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('import_reopen_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final sourceFile = File(p.join(tempDir.path, 'dance.mp4'))
      ..writeAsBytesSync([1, 2, 3]);
    final videosDir = Directory(p.join(tempDir.path, 'videos'));
    final indexFile = File(p.join(tempDir.path, 'index.json'));
    final picker = FakeVideoPicker(
      PickedVideo(name: 'dance.mp4', sourceUri: sourceFile.uri, sizeBytes: 3),
    );

    // 第一次「会话」：导入 → 全屏播放 → 索引写入 1 条。
    // KeyedSubtree(UniqueKey)：两次 pumpWidget 之间强制整树重建，
    // 模拟跨会话重新拉起 App（否则 const DanceLearningApp 会被复用）。
    final engine1 = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine1),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          importIndexFileProvider.overrideWith((ref) async => indexFile),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        ],
        child: KeyedSubtree(key: UniqueKey(), child: const DanceLearningApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import_video_button')));
      await waitForIndexEntries(tester, indexFile, 1);
    });
    await tester.pumpAndSettle();
    final firstEntry = readIndexEntries(indexFile).single;
    expect(engine1.source!.toFilePath(), firstEntry['filePath']);

    // 第二次「会话」：重新拉起 App（同一 index.json 与私有目录，模拟
    // 跨会话再次打开同一视频）——快速键命中立即播放既有私有副本，
    // 后台哈希校验一致 → 索引仍只有 1 条、videoId 不变。
    final engine2 = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine2),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          importIndexFileProvider.overrideWith((ref) async => indexFile),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        ],
        child: KeyedSubtree(key: UniqueKey(), child: const DanceLearningApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import_video_button')));
      // 等导入链（真实 IO）完成并 push 播放器页：Navigator 的 history
      // 在 push 时同步更新，无需驱动帧即可轮询；pump 用来推进 fake 时钟区
      // 里排队的索引写续体（同上）。
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      await pollUntil(
        () => navigator.canPop(),
        onTick: () => tester.pump(),
        reason: '导入后应已 push 播放器页',
      );
    });
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsOneWidget);
    expect(
      engine2.source!.toFilePath(),
      firstEntry['filePath'],
      reason: '快速键命中：播放既有私有副本，不重新复制',
    );
    final entries = readIndexEntries(indexFile);
    expect(entries.length, 1, reason: '哈希一致：不新增条目');
    expect(entries.single['videoId'], firstEntry['videoId']);
  });

  testWidgets('取消选择（选择器返回 null）：留在首页，不进入播放', (tester) async {
    final engine = FakePlaybackEngine();
    final picker = FakeVideoPicker(null);
    final tempDir = Directory.systemTemp.createTempSync('import_cancel_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith(
            (ref) async => Directory(p.join(tempDir.path, 'videos')),
          ),
          importIndexFileProvider.overrideWith(
            (ref) async => File(p.join(tempDir.path, 'index.json')),
          ),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('import_video_button')));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerPage), findsNothing);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(engine.source, isNull);
    expect(picker.clearCacheCalled, isFalse);
  });

  testWidgets('镜像：首次打开询问并选「是」→ 按 video_id 保留；再次打开自动应用并提示', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('import_mirror_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final sourceFile = File(p.join(tempDir.path, 'dance.mp4'))
      ..writeAsBytesSync([1, 2, 3]);
    final videosDir = Directory(p.join(tempDir.path, 'videos'));
    final indexFile = File(p.join(tempDir.path, 'index.json'));
    final picker = FakeVideoPicker(
      PickedVideo(name: 'dance.mp4', sourceUri: sourceFile.uri, sizeBytes: 3),
    );

    // 首次「会话」：默认真实哈希管道。首次打开询问是确定性的——resolve
    // 时索引无条目（哈希后台计算）或条目未标记「已询问」（哈希先落盘）
    // 都会进入询问，不受哈希时序影响（竞态已由 mirrorAsked 消除）。
    final engine1 = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine1),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          importIndexFileProvider.overrideWith((ref) async => indexFile),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        ],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import_video_button')));
      // 等导入链（真实 IO）完成并 push 播放器页、命名框弹出（首次
      // 导入先命名、后镜像；命名框关掉之后才开始镜像询问）。
      await pollUntil(
        () => tester.any(find.byKey(const Key('song_naming_dialog'))),
        onTick: () => tester.pump(),
        reason: '首次导入应先弹命名框',
      );
      expect(
        tester.any(find.byKey(const Key('mirror_question_scrim'))),
        isFalse,
        reason: '命名框未关：镜像询问尚未开始',
      );
      // 关掉命名框（跳过 = 按文件名署名）→ 镜像询问开始。
      await tester.tap(find.byKey(const Key('naming_skip')));
      await tester.pump();
      await pollUntil(
        () => tester.any(find.text('需要镜像吗？')),
        onTick: () => tester.pump(),
        reason: '命名框关掉后应弹「需要镜像吗？」两栏依据询问',
      );
      expect(engine1.isPlaying, isTrue, reason: '询问不阻塞播放');

      // 选「是」：立即生效（渲染层翻转标记）。
      await tester.tap(find.byKey(const Key('mirror_yes_button')));
      await tester.pump();
      expect(
        tester.any(find.byKey(const Key('mirrored_surface'))),
        isTrue,
        reason: '选择后立即生效（渲染层翻转）',
      );

      // 后台哈希落盘后镜像重试循环把作答按 video_id 写回索引并标记
      //「已询问」。widget 侧 chooseMirrored 在 fake zone 启动持久化重试
      //（Future.delayed 为 fake 定时器），onTick 用 pump 推进。
      await pollUntil(
        () {
          if (!indexFile.existsSync()) return false;
          try {
            final entries = readIndexEntries(indexFile);
            return entries.isNotEmpty &&
                entries.single['mirrored'] == true &&
                entries.single['mirrorAsked'] == true;
          } on FormatException {
            return false; // 写入瞬时快照，重试。
          }
        },
        onTick: () => tester.pump(const Duration(milliseconds: 200)),
        reason: '镜像状态按 video_id 持久化且标记已询问',
      );
      expect(readIndexEntries(indexFile).single['videoId'], isNotEmpty);
      // 镜像真值以文档目录 markers 文档为准（与 index.json 同级）：
      // index 的 mirrored/mirrorAsked 先落盘，markers 的 meta.mirrored 由
      // 后台双写补上——不等它就绪，第二个会话可能读到缺文件/旧值的
      // markers，导致历史镜像不生效。
      final videoId = readIndexEntries(indexFile).single['videoId'] as String;
      final markersFile = File(p.join(tempDir.path, 'markers_$videoId.json'));
      await pollUntil(
        () {
          if (!markersFile.existsSync()) return false;
          try {
            final doc =
                jsonDecode(markersFile.readAsStringSync()) as Map<String, dynamic>;
            final meta = doc['meta'] as Map<String, dynamic>?;
            return meta?['mirrored'] == true;
          } on FormatException {
            return false; // 写入瞬时快照，重试。
          }
        },
        onTick: () => tester.pump(),
        maxTries: ioPollTries,
        reason: 'markers 文档 meta.mirrored 真值落盘',
      );
      // 源文件字节不变（镜像为渲染层翻转，不写源文件）。
      expect(sourceFile.readAsBytesSync(), [1, 2, 3]);
    });
    await tester.pumpAndSettle();

    // 再次「会话」：重新拉起 App（同一 index.json 与私有目录）——快速键
    // 命中既有副本，自动按历史应用镜像并提示，无需确认。
    final engine2 = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine2),
          systemMediaVolumeControllerProvider.overrideWithValue(
            FakeSystemMediaVolumeController(),
          ),
          beatAnalysisPipelineProvider.overrideWithValue(FakeBeatPipeline()),
          songLoudnessProbeProvider.overrideWithValue(const _FixedLoudnessProbe()),
          videoPickerProvider.overrideWithValue(picker),
          importVideosDirectoryProvider.overrideWith((ref) async => videosDir),
          importIndexFileProvider.overrideWith((ref) async => indexFile),
          systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
        ],
        child: KeyedSubtree(key: UniqueKey(), child: const DanceLearningApp()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('import_video_button')));
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      // 并行全量下真实 IO 被饿死，放宽轮询预算（默认 300×10ms≈3s 偏紧）。
      await pollUntil(
        () => navigator.canPop(),
        onTick: () => tester.pump(),
        maxTries: ioPollTries,
        reason: '导入后应已 push 播放器页',
      );

      // resolve 读取索引（真实 IO）→ markers 真值在（镜像真值以文档目录
      // markers 为准，路径）→ 直接应用、不询问、不提示，渲染层翻转。
      await pollUntil(
        () => tester.any(find.byKey(const Key('mirrored_surface'))),
        onTick: () => tester.pump(),
        maxTries: ioPollTries,
        reason: '再次打开自动应用历史镜像（markers 真值）并翻转渲染层',
      );
      expect(tester.any(find.text('需要镜像吗？')), isFalse, reason: '按历史应用，无需确认');
      expect(
        tester.any(find.byKey(const Key('mirrored_surface'))),
        isTrue,
        reason: '自动应用历史镜像设置 + 渲染层水平翻转生效',
      );
    });
  });
}
