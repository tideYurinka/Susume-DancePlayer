import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/player/resume_position.dart'
    show ResumeRecorder;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_video_index_storage.dart';

/// 续播落盘会话测试：取数经显式闭包，写面落
/// index 条目的私密续播位置；越尾线钳回尾线（语义唯一实现于 [recordResumePosition]）。
void main() {
  const filePath = '/videos/a.mp4';
  const duration = Duration(minutes: 3);

  VideoIndexEntry entry() => VideoIndexEntry(
    videoId: 'seeded',
    displayName: 'a.mp4',
    filePath: filePath,
    sizeBytes: 1,
    fastKey: '1:a.mp4',
    mirrored: false,
    mirrorAsked: true,
    lastOpenedAt: DateTime(2026, 9, 1),
    signatureCache: const SongSignature(song: 'a'),
  );

  test('save 把现读位置写进索引条目', () async {
    final store = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entry()]),
    );
    final recorder = ResumeRecorder(
      indexStore: store,
      filePath: filePath,
      positionOf: () => const Duration(seconds: 42),
      videoDurationOf: () => duration,
      rangeEndOf: () => null,
    );

    await recorder.save();

    final saved = (await store.load()).findByFilePath(filePath);
    expect(saved?.lastPositionMs, const Duration(seconds: 42).inMilliseconds);
  });

  test('位置 ≥ 自定义尾线时钳回尾线记录', () async {
    final store = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entry()]),
    );
    final recorder = ResumeRecorder(
      indexStore: store,
      filePath: filePath,
      positionOf: () => const Duration(seconds: 100),
      videoDurationOf: () => duration,
      rangeEndOf: () => const Duration(seconds: 60),
    );

    await recorder.save();

    final saved = (await store.load()).findByFilePath(filePath);
    expect(saved?.lastPositionMs, const Duration(seconds: 60).inMilliseconds);
  });

  test('位置为零不写入（开头无从续播）', () async {
    final store = InMemoryVideoIndexStorage(
      initial: VideoIndex(entries: [entry()]),
    );
    final recorder = ResumeRecorder(
      indexStore: store,
      filePath: filePath,
      positionOf: () => Duration.zero,
      videoDurationOf: () => duration,
      rangeEndOf: () => null,
    );

    await recorder.save();

    final saved = (await store.load()).findByFilePath(filePath);
    expect(saved?.lastPositionMs, 0);
  });
}
