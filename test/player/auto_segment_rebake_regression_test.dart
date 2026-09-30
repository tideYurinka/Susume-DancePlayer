import 'dart:convert';

import 'package:dance_learning_app/annotation/learning_segments.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/dance/segment_practice_aggregation.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_providers.dart';
import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show annotationEditorProvider, annotationTimelineProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_four_beat_bucket_storage.dart';
import '../helpers/uniform_test_grid.dart';

/// 自动分段收口回归（／见词条「自动分段」）：「练舞统计不在这个问题里」
/// 的可观察证据——替换分段线只换段练习的展示分组，四拍桶历史原样不动。
void main() {
  const total = Duration(minutes: 1);
  const ten = Duration(seconds: 10);
  const videoId = 'hash-1';

  late ProviderContainer container;
  late InMemoryFourBeatBucketStorage bucketStorage;

  setUp(() {
    bucketStorage = InMemoryFourBeatBucketStorage();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: total),
        ),
        fourBeatBucketStorageProvider.overrideWithValue(bucketStorage),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('自动分段替换分段线：四拍桶历史一个字节不变，段练习按新分段重新聚合', () async {
    // 预算桶历史（原样档裸整数键；桶 n 的左边界 = n × 2s，500ms/拍）。
    bucketStorage.setRaw(videoId, {
      'version': 1,
      'signature': {'dancer': '', 'song': '曲子', 'remark': ''},
      'ledger': {
        'days': {
          '2026-09-15': {
            for (var i = 0; i < 10; i++)
              '$i': {'wallSeconds': 1.0, 'sweeps': 1},
          },
        },
      },
    });
    final bytesBefore = jsonEncode(bucketStorage.savedJsonFor(videoId));
    final savesBefore = bucketStorage.saveCount;

    final store = container.read(fourBeatBucketStoreProvider);
    final editor = container.read(annotationEditorProvider);
    final grid = UniformTestGrid(
      beatInterval: const Duration(milliseconds: 500),
      beatCount: 64,
    );

    editor.submit(AddSegmentLine(at: ten));
    final before = aggregateSegmentPractice(
      segments: deriveLearningSegments(
        container.read(annotationTimelineProvider),
      ),
      grid: grid,
      buckets: _readFace(await store.shard(videoId)),
    );
    expect(before.map((p) => p.practiceDuration), [
      const Duration(seconds: 5),
      const Duration(seconds: 5),
    ]);

    // 自动分段把分区换成 [0,5)/[5,20)：只有分段线变，桶历史与本动作无关。
    editor.submit(
      const AutoSegment(
        start: Duration.zero,
        end: Duration(seconds: 20),
        cuts: [Duration(seconds: 5)],
      ),
    );
    await store.settle();

    final after = aggregateSegmentPractice(
      segments: deriveLearningSegments(
        container.read(annotationTimelineProvider),
      ),
      grid: grid,
      buckets: _readFace(await store.shard(videoId)),
    );
    expect(after.map((p) => p.practiceDuration), [
      const Duration(seconds: 3),
      const Duration(seconds: 7),
    ]);
    expect(
      after.map((p) => p.practiceCount),
      [1, 1],
      reason: '换分组后同桶仍完整经过一遍',
    );

    // 历史一个字节不变：既没写盘（saveCount 不动），落盘内容也逐字节相同。
    expect(bucketStorage.saveCount, savesBefore);
    expect(jsonEncode(bucketStorage.savedJsonFor(videoId)), bytesBefore);
  });
}

/// 分片 → 纯值层可聚合读面：走生产同一条读取时投影（`projectShardToCurrentGrid`）。
Map<String, Map<int, SegmentBucketValue>> _readFace(FourBeatBucketShard shard) =>
    {
      for (final day in projectShardToCurrentGrid(shard, null).entries)
        day.key: {
          for (final bucket in day.value.entries)
            bucket.key: SegmentBucketValue(
              wallSeconds: bucket.value.wallSeconds,
              sweeps: bucket.value.sweeps,
            ),
        },
    };
