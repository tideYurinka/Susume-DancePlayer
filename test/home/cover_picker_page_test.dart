import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/dance/cover_frame_providers.dart';
import 'package:dance_learning_app/home/cover_picker_page.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/practice_stats.dart';
import 'package:dance_learning_app/persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart';

import '../helpers/video_surface.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cover_generator.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_cover_cache.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/in_memory_practice_stats_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 换封面选帧界面部件测试：FakePlaybackEngine 驱动拖动
/// ——断言暂停先于任何 seek、提交的 seek 目标序列、松手恢复播放态；确认写
/// 入封面位置并使缓存失效重生成；恢复默认清空字段回到跟随首线；返回零写入。
///
/// 取帧执行器与生成编排都是注入 seam：本层只断言「按预览线时刻调用生成」，
/// 命令装配与尺寸/裁切本身归 `test/dance/cover_generator_test.dart` 直测。
void main() {
  const sourcePath = '/videos/v1.mp4';

  testWidgets('进入：打开并暂停，预览线停在当前封面位置，界面只有视频面+时间轴+两个动作', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    expect(find.byKey(const Key('cover_picker_page')), findsOneWidget);
    // 复用同一内核：打开的是该舞源视频。
    expect(harness.engine.source, Uri.file(sourcePath));
    // 进入时打开并暂停。
    expect(harness.engine.isPlaying, isFalse);
    expect(harness.engine.callLog.first, 'pause');
    // 初始预览线 = 当前封面位置，画面按该帧落定。
    expect(harness.engine.seekCalls, [const Duration(seconds: 30)]);
    expect(_timeText(tester), '00:30:00');
    // 视频面来自注入内核的渲染接缝。
    expect(find.byKey(videoSurfacePlaceholderKey), findsOneWidget);
    // 一条覆盖整支舞的时间轴与预览线。
    expect(find.byKey(const Key('cover_picker_timeline')), findsOneWidget);
    expect(find.byKey(const Key('cover_picker_playhead')), findsOneWidget);
    // 简化界面：只有两个动作。
    expect(find.text('用这一帧'), findsOneWidget);
    expect(find.text('恢复为默认'), findsOneWidget);
    // 不做逐帧步进、不做时间轴缩放。
    expect(find.byIcon(Icons.zoom_in), findsNothing);
    expect(find.text('上一帧'), findsNothing);
  });

  testWidgets('拖动预览线：暂停先于任何 seek；落点为累计位移；松手恢复手势前播放态', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    // 模拟手势起手时内核在播：同一条拖动链路应先定格再逐帧 seek，收尾续播。
    await harness.engine.play();
    harness.engine.callLog.clear();
    harness.engine.seekCalls.clear();

    final width = tester
        .getSize(find.byKey(const Key('cover_picker_timeline')))
        .width;
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cover_picker_timeline'))),
    );
    await tester.pump();
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();

    expect(harness.engine.isPlaying, isFalse, reason: '拖起手先暂停定格');
    expect(
      harness.engine.callLog.indexOf('pause'),
      lessThan(harness.engine.callLog.indexOf('seek')),
      reason: 'pause 先于任何 seek',
    );
    // 全程 3 分钟、时间轴宽 W：位移 150px 对应 150 × 180000 / W 毫秒。
    final expected = Duration(
      milliseconds: 30000 + (150 * 180000 / width).round(),
    );
    expect(harness.engine.seekCalls.last, expected);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(harness.engine.callLog.last, 'play', reason: '松手恢复手势前播放态');
    expect(harness.engine.isPlaying, isTrue);
    // 当前时刻文本与预览线目标同源（不读引擎实际 position）：默认视口
    // 时间轴宽 768 → 30s + round(150 × 180000 ÷ 768)ms = 65.156s。
    expect(_timeText(tester), '01:05:04');
    // 收尾暂停，避免用例结束时内核节拍器仍在跑（本轮只验证恢复语义）。
    await harness.engine.pause();
  });

  testWidgets('用这一帧：按当前预览线时刻写入封面位置、缓存失效并按该位置重新生成、读面作废', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    // 拖动 150px 到新的预览时刻，再确认。
    final width = tester
        .getSize(find.byKey(const Key('cover_picker_timeline')))
        .width;
    final picked = Duration(
      milliseconds: 30000 + (150 * 180000 / width).round(),
    );
    await tester.drag(
      find.byKey(const Key('cover_picker_timeline')),
      const Offset(150, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cover_picker_confirm')));
    await tester.pumpAndSettle();

    // 封面位置字段落盘（公开标记文件 meta.coverPositionMs）。
    expect(
      harness.documentStorage.markersSnapshot['meta'],
      containsPair('coverPositionMs', picked.inMilliseconds),
    );
    // 缓存失效后按新位置重新生成。
    expect(harness.coverCache.deleted, contains('v1'));
    expect(harness.generator.calls, [
      (videoId: 'v1', sourcePath: sourcePath, position: picked),
    ]);
    expect(harness.coverCache.ready, contains('v1'));
    // 确认后回到详情。
    expect(find.byKey(const Key('cover_picker_page')), findsNothing);
  });

  testWidgets('恢复为默认：清空封面位置字段，按「跟随首线」的有效位置重新生成封面', (tester) async {
    final harness = _Harness(
      markers: const MarkersDocument(
        coverPositionMs: 42000,
        rangeStartMs: 10000,
        rangeEndMs: 120000,
      ),
    );
    await harness.pump(tester, initialPosition: const Duration(seconds: 42));

    await tester.tap(find.byKey(const Key('cover_picker_reset')));
    await tester.pumpAndSettle();

    // 字段被清空（缺省 = 跟随首线），同文档首尾区间原样保留。
    expect(
      harness.documentStorage.markersSnapshot['meta'],
      isNot(contains('coverPositionMs')),
    );
    final markers = MarkersDocument.fromJson(
      harness.documentStorage.markersSnapshot,
    );
    expect(markers.coverPositionMs, isNull);
    expect(markers.rangeStartMs, 10000);
    // 封面回到跟随首线：按有效区间起点重新生成。
    expect(harness.coverCache.deleted, contains('v1'));
    expect(harness.generator.calls, [
      (
        videoId: 'v1',
        sourcePath: sourcePath,
        position: const Duration(seconds: 10),
      ),
    ]);
    expect(harness.coverCache.ready, contains('v1'));
  });

  testWidgets('取不到帧：位置仍落盘但如实告知「封面生成失败」，不假装封面已换好', (tester) async {
    final harness = _Harness()..generator.result = false;
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    await tester.tap(find.byKey(const Key('cover_picker_confirm')));
    await tester.pumpAndSettle();

    // 位置字段照常落盘（用户意图被记录），缓存按新位置失效但没能重生成。
    expect(
      harness.documentStorage.markersSnapshot['meta'],
      containsPair('coverPositionMs', 30000),
    );
    expect(harness.coverCache.deleted, contains('v1'));
    expect(harness.coverCache.ready, isNot(contains('v1')));
    // 失败如实告知，不静默当成功。
    expect(find.text('封面生成失败'), findsOneWidget);
    expect(find.byKey(const Key('cover_picker_page')), findsNothing);
  });

  testWidgets('返回：不写入任何字段，缓存与生成的触发不在，内核不被释放', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    // 拖了也不提交。
    await tester.drag(
      find.byKey(const Key('cover_picker_timeline')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cover_picker_page')), findsNothing);
    expect(
      harness.documentStorage.markersSnapshot['meta'] ?? const {},
      isNot(contains('coverPositionMs')),
    );
    expect(harness.coverCache.deleted, isEmpty);
    expect(harness.generator.calls, isEmpty);
    // 内核是应用内单例：界面只打开/暂停/seek，不接管生命周期。
    expect(harness.engine.isDisposed, isFalse);
  });

  testWidgets('时间轴高 ≥48 且点按定位：点轴宽 1/4 处 seek 到总时长 1/4', (tester) async {
    final harness = _Harness();
    await harness.pump(tester, initialPosition: const Duration(seconds: 30));

    final timeline = find.byKey(const Key('cover_picker_timeline'));
    final size = tester.getSize(timeline);
    expect(size.height, greaterThanOrEqualTo(48), reason: '时间轴高度取命中盒下限');
    // 视觉件不变：预览线高 22。
    expect(
      tester.getSize(find.byKey(const Key('cover_picker_playhead'))).height,
      22,
    );
    harness.engine.seekCalls.clear();

    await tester.tapAt(
      tester.getTopLeft(timeline) + Offset(size.width / 4, 24),
    );
    await tester.pumpAndSettle();

    // 整支舞 3 分钟 → 1/4 轴宽 = 45 秒。
    expect(harness.engine.seekCalls.last, const Duration(seconds: 45));
    expect(_timeText(tester), '00:45:00');
  });
}

/// 当前预览线时刻文本（键定位，避免与其它文本混淆）。
String _timeText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('cover_picker_time'))).data!;

/// 记录删除调用并保持就绪状态的内存封面缓存（换封面使缓存失效的断言用）。
class _SpyCoverCache extends InMemoryCoverCache {
  final List<String> deleted = [];

  @override
  Future<void> deleteFor(String videoId) async {
    deleted.add(videoId);
    return super.deleteFor(videoId);
  }
}

class _Harness {
  _Harness({MarkersDocument markers = const MarkersDocument.empty()})
    : indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry('v1')]),
      ),
      documentStorage = InMemoryVideoDocumentStorage(markers: markers.toJson()),
      coverCache = _SpyCoverCache(),
      engine = FakePlaybackEngine(duration: const Duration(minutes: 3));

  final InMemoryVideoIndexStorage indexStorage;
  final InMemoryVideoDocumentStorage documentStorage;
  final _SpyCoverCache coverCache;
  final FakePlaybackEngine engine;
  final InMemoryPracticeStatsStorage statsStorage =
      InMemoryPracticeStatsStorage();
  final InMemoryFourBeatBucketStorage bucketStorage =
      InMemoryFourBeatBucketStorage();
  late final FakeCoverGenerator generator = FakeCoverGenerator(
    cache: coverCache,
  );

  Future<void> pump(
    WidgetTester tester, {
    required Duration initialPosition,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoIndexStoreProvider.overrideWithValue(indexStorage),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (id) => documentStorage,
          ),
          practiceStatsStoreProvider.overrideWithValue(
            PracticeStatsStore(statsStorage),
          ),
          fourBeatBucketStoreProvider.overrideWithValue(
            FourBeatBucketStore(bucketStorage),
          ),
          coverCacheProvider.overrideWith((ref) => coverCache),
          coverGeneratorProvider.overrideWith((ref) async => generator),
          playbackEngineProvider.overrideWithValue(engine),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('open_cover_picker'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => CoverPickerPage(
                        videoId: 'v1',
                        sourcePath: '/videos/v1.mp4',
                        initialPosition: initialPosition,
                      ),
                    ),
                  ),
                  child: const Text('打开换封面'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_cover_picker')));
    await tester.pumpAndSettle();
  }
}

VideoIndexEntry _entry(String videoId) => VideoIndexEntry(
  videoId: videoId,
  displayName: '$videoId.mp4',
  filePath: '/videos/$videoId.mp4',
  sizeBytes: 1,
  fastKey: 'k-$videoId',
  mirrored: false,
  lastOpenedAt: DateTime(2026, 9, 1),
);
