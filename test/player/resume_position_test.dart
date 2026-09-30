import 'dart:io';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        activeLoopRangeProvider,
        annotationTimelineProvider,
        layoutLockedProvider,
        learningEmphasisProvider,
        learningMasteryProvider;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/level_control.dart'
    show screenBrightnessControllerProvider;
import 'package:dance_learning_app/player/open_restore.dart'
    show VideoOpenRestorer, videoOpenRestorerProvider;
import 'package:dance_learning_app/player/open_session.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/persistence/prep_beats_store.dart'
    show delayedLoopProvider;
import 'package:dance_learning_app/player/preview_snap.dart'
    show previewSnapEnabledProvider;
import 'package:dance_learning_app/player/resume_position.dart'
    show
        ResumeDecision,
        recordResumePosition,
        resolveResumeTarget,
        resumeDecision,
        resumePromptAutoDismiss,
        resumePromptProvider;
import 'package:dance_learning_app/player/system_ui.dart' show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_brightness.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 固定值哈希（打开恢复的内容哈希校验桩，open_restore_test 同款）。
class _FixedHasher implements ContentHasher {
  const _FixedHasher(this.value);

  final String value;

  @override
  Future<String> hashFile(File file) async => value;
}

const Duration kDuration = Duration(minutes: 3);
const String kFilePath = '/videos/a.mp4';

VideoIndexEntry _entry({String videoId = 'seeded', int lastPositionMs = 0}) {
  return VideoIndexEntry(
    videoId: videoId,
    displayName: 'a.mp4',
    filePath: kFilePath,
    sizeBytes: 1,
    fastKey: '1:a.mp4',
    mirrored: false,
    mirrorAsked: true,
    lastOpenedAt: DateTime(2026, 9, 1),
    signatureCache: const SongSignature(song: 'a'),
    lastPositionMs: lastPositionMs,
  );
}

class _Probe {
  _Probe({
    required this.container,
    required this.engine,
    required this.indexStorage,
    required this.hasher,
  });

  final ProviderContainer container;
  final FakePlaybackEngine engine;
  final InMemoryVideoIndexStorage indexStorage;
  final ContentHasher hasher;

  VideoOpenRestorer get restorer => container.read(videoOpenRestorerProvider);

  /// 建立打开会话（宿主装配点）+ 走打开恢复。
  Future<void> open({String filePath = kFilePath}) async {
    final session = OpenSession(
      filePath: filePath,
      indexStore: indexStorage,
      hasher: hasher,
      coordinatorFor: (videoId) =>
          container.read(videoDocumentCoordinatorProvider(videoId)),
    );
    await session.establish();
    await restorer.resolve(session: session, videoDuration: kDuration);
  }
}

_Probe _makeProbe({
  required VideoIndexEntry entry,
  ContentHasher hasher = const _FixedHasher('seeded'),
}) {
  final indexStorage = InMemoryVideoIndexStorage(
    initial: VideoIndex(entries: [entry]),
  );
  final engine = FakePlaybackEngine(duration: kDuration);
  VideoDocumentStorage documentStorage(String videoId) =>
      InMemoryVideoDocumentStorage();
  final container = ProviderContainer(
    overrides: [
      playbackEngineProvider.overrideWithValue(engine),
      videoIndexStoreProvider.overrideWithValue(indexStorage),
      contentHasherProvider.overrideWithValue(hasher),
      videoDocumentStorageFactoryProvider.overrideWithValue(documentStorage),
    ],
  );
  // 容器内无 widget 监听，保持恢复目标 provider 存活（open_restore_test
  // 同款接线）。
  container.listen(annotationTimelineProvider, (_, _) {});
  container.listen(learningMasteryProvider, (_, _) {});
  container.listen(learningEmphasisProvider, (_, _) {});
  container.listen(selectedLearningSegmentsProvider, (_, _) {});
  container.listen(activeLoopRangeProvider, (_, _) {});
  container.listen(previewSnapEnabledProvider, (_, _) {});
  container.listen(delayedLoopProvider, (_, _) {});
  container.listen(layoutLockedProvider, (_, _) {});
  addTearDown(container.dispose);
  return _Probe(
    container: container,
    engine: engine,
    indexStorage: indexStorage,
    hasher: hasher,
  );
}

void main() {
  group('resumeDecision（纯函数 seam：续播位置 → 决策）', () {
    test('无位置（0）→ 不续播不弹卡', () {
      expect(
        resumeDecision(
          lastPosition: Duration.zero,
          videoDuration: kDuration,
        ),
        ResumeDecision.none,
      );
    });

    test('位置在头部阈值内（<5s）→ 静默续播、不弹卡', () {
      expect(
        resumeDecision(
          lastPosition: const Duration(seconds: 4, milliseconds: 999),
          videoDuration: kDuration,
        ),
        ResumeDecision.continueSilently,
      );
    });

    test('位置有效且超出头部阈值 → 续播并弹「从头播放？」', () {
      expect(
        resumeDecision(lastPosition: const Duration(seconds: 5), videoDuration: kDuration),
        ResumeDecision.continueWithPrompt,
      );
      expect(
        resumeDecision(lastPosition: const Duration(minutes: 1), videoDuration: kDuration),
        ResumeDecision.continueWithPrompt,
      );
    });

    test('上次到尾（位置 ≥ 时长）→ 从头播放、不弹卡', () {
      expect(
        resumeDecision(lastPosition: kDuration, videoDuration: kDuration),
        ResumeDecision.none,
      );
      expect(
        resumeDecision(
          lastPosition: kDuration + const Duration(seconds: 1),
          videoDuration: kDuration,
        ),
        ResumeDecision.none,
      );
    });

    test('视频时长未知 → 不续播（位置无从校验）', () {
      expect(
        resumeDecision(lastPosition: const Duration(minutes: 1), videoDuration: Duration.zero),
        ResumeDecision.none,
      );
    });
  });

  group('resolveResumeTarget（纯函数 seam：越尾钳制目标位）', () {
    test('到尾（position == videoDuration）→ 0（尾部视为从头）', () {
      expect(
        resolveResumeTarget(
          position: kDuration,
          videoDuration: kDuration,
          rangeEnd: null,
        ),
        Duration.zero,
      );
    });

    test('越过尾（position > videoDuration）→ 0', () {
      expect(
        resolveResumeTarget(
          position: kDuration + const Duration(seconds: 1),
          videoDuration: kDuration,
          rangeEnd: null,
        ),
        Duration.zero,
      );
    });

    test('恰在尾线（position == rangeEnd）→ 原样不钳', () {
      const rangeEnd = Duration(seconds: 120);
      expect(
        resolveResumeTarget(
          position: rangeEnd,
          videoDuration: kDuration,
          rangeEnd: rangeEnd,
        ),
        rangeEnd,
      );
    });

    test('越尾线（position > rangeEnd 且 rangeEnd < videoDuration）→ 钳到尾线', () {
      expect(
        resolveResumeTarget(
          position: const Duration(seconds: 150),
          videoDuration: kDuration,
          rangeEnd: const Duration(seconds: 120),
        ),
        const Duration(seconds: 120),
      );
    });

    test('尾线等于时长（rangeEnd == videoDuration）→ 不钳、走尾部语义', () {
      expect(
        resolveResumeTarget(
          position: kDuration + const Duration(seconds: 1),
          videoDuration: kDuration,
          rangeEnd: kDuration,
        ),
        Duration.zero,
      );
    });

    test('视频时长未知（videoDuration == null）→ 尾线钳制照常生效', () {
      expect(
        resolveResumeTarget(
          position: const Duration(seconds: 150),
          videoDuration: null,
          rangeEnd: const Duration(seconds: 120),
        ),
        const Duration(seconds: 120),
      );
    });

    test('无尾线（rangeEnd == null）→ 原样', () {
      expect(
        resolveResumeTarget(
          position: const Duration(minutes: 1),
          videoDuration: kDuration,
          rangeEnd: null,
        ),
        const Duration(minutes: 1),
      );
    });

    test('位置为 0 → 原样 0', () {
      expect(
        resolveResumeTarget(
          position: Duration.zero,
          videoDuration: kDuration,
          rangeEnd: const Duration(seconds: 120),
        ),
        Duration.zero,
      );
    });
  });

  group('recordResumePosition（index 条目记录续播位置）', () {
    test('中途离开 → 记录当前位置毫秒', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry()]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: const Duration(seconds: 95, milliseconds: 500),
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 95500);
    });

    test('到尾离开 → 记录 0（尾部视为从头）', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry(lastPositionMs: 60000)]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: kDuration,
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 0);
    });

    test('无位置（0）且条目本无位置 → 不产生写盘', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry()]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: Duration.zero,
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 0);
    });

    test('位置 0（本次未开播）不改写已有续播位置', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry(lastPositionMs: 60000)]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: Duration.zero,
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 60000);
    });

    test('位置 ≥ 自定义尾线 → 记尾线内侧（钳制）', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry()]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: const Duration(seconds: 150),
        videoDuration: kDuration,
        rangeEnd: const Duration(seconds: 120),
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 120000);
    });

    test('位置与现值一致 → 不产生写盘', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry(lastPositionMs: 95000)]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: const Duration(seconds: 95),
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 95000);
      expect(indexStorage.mutationCount, 0);
    });

    test('尾线内位置（position < rangeEnd）不受钳制，原样记录', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [_entry()]),
      );
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: kFilePath,
        position: const Duration(seconds: 100),
        videoDuration: kDuration,
        rangeEnd: const Duration(seconds: 120),
      );
      expect(indexStorage.current.entries.single.lastPositionMs, 100000);
    });

    test('条目不存在（新视频语义）→ 不崩溃、不新增条目', () async {
      final indexStorage = InMemoryVideoIndexStorage(initial: VideoIndex.empty);
      await recordResumePosition(
        indexStore: indexStorage,
        filePath: '/videos/other.mp4',
        position: const Duration(seconds: 30),
        videoDuration: kDuration,
      );
      expect(indexStorage.current.entries, isEmpty);
    });
  });

  group('打开恢复续播接线（VideoOpenRestorer.resolve）', () {
    test('位置有效：打开即 seek 到续播位置并弹「从头播放？」', () async {
      final probe = _makeProbe(entry: _entry(lastPositionMs: 60000));
      await probe.open();
      expect(probe.engine.seekCalls, [const Duration(seconds: 60)]);
      expect(probe.container.read(resumePromptProvider), isTrue);
    });

    test('位置在头部阈值内：seek 静默续播、不弹卡', () async {
      final probe = _makeProbe(entry: _entry(lastPositionMs: 2000));
      await probe.open();
      expect(probe.engine.seekCalls, [const Duration(seconds: 2)]);
      expect(probe.container.read(resumePromptProvider), isFalse);
    });

    test('上次到尾：不 seek（从头播放）、不弹卡', () async {
      final probe = _makeProbe(entry: _entry(lastPositionMs: 180000));
      await probe.open();
      expect(probe.engine.seekCalls, isEmpty);
      expect(probe.container.read(resumePromptProvider), isFalse);
    });

    test('无续播位置：不 seek、不弹卡（新视频/首次打开行为不变）', () async {
      final probe = _makeProbe(entry: _entry());
      await probe.open();
      expect(probe.engine.seekCalls, isEmpty);
      expect(probe.container.read(resumePromptProvider), isFalse);
    });

    test('内容哈希不一致（按新视频处理）：不按旧位置续播', () async {
      final probe = _makeProbe(
        entry: _entry(videoId: 'hash-old', lastPositionMs: 60000),
        hasher: const _FixedHasher('hash-new'),
      );
      await probe.open();
      expect(probe.engine.seekCalls, isEmpty);
      expect(probe.container.read(resumePromptProvider), isFalse);
    });
  });

  group('播放页接线（widget：小卡显隐与交互）', () {
    Future<FakePlaybackEngine> pumpPlayer(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
      required InMemoryVideoIndexStorage indexStorage,
    }) async {
      final source = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            screenBrightnessControllerProvider.overrideWithValue(
              FakeScreenBrightnessController(),
            ),
            videoIndexStoreProvider.overrideWithValue(indexStorage),
            contentHasherProvider.overrideWithValue(const _FixedHasher('seeded')),
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (videoId) => InMemoryVideoDocumentStorage(),
            ),
          ],
          child: MaterialApp(home: PlayerPage(source: source)),
        ),
      );
      await tester.pumpAndSettle();
      return engine;
    }

    InMemoryVideoIndexStorage seededIndex({required int lastPositionMs}) {
      return InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            _entry().copyWith(lastPositionMs: lastPositionMs),
          ],
        ),
      );
    }

    testWidgets('切后台（lifecycle paused）记录当前续播位置', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      final indexStorage = seededIndex(lastPositionMs: 0);
      await pumpPlayer(tester, engine: engine, indexStorage: indexStorage);

      // 播放 3 秒后切后台。
      await tester.pump(const Duration(seconds: 3));
      tester
          .binding
          .handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        indexStorage.current.entries.single.lastPositionMs,
        inInclusiveRange(3000, 3400),
      );

      tester
          .binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    testWidgets('打开即从续播位置播放，左下角出现「从头播放？」小卡', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      await pumpPlayer(
        tester,
        engine: engine,
        indexStorage: seededIndex(lastPositionMs: 60000),
      );

      expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 60)));
      expect(engine.position, lessThan(const Duration(seconds: 61)));
      expect(engine.isPlaying, isTrue);
      expect(find.byKey(const Key('resume_prompt_card')), findsOneWidget);
      expect(find.text('已从上次位置继续'), findsOneWidget);
      expect(find.byKey(const Key('resume_prompt_restart')), findsOneWidget);
    });

    testWidgets('点「从头播放？」跳回 0 并继续播放、小卡消失', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      await pumpPlayer(
        tester,
        engine: engine,
        indexStorage: seededIndex(lastPositionMs: 60000),
      );

      await tester.tap(find.byKey(const Key('resume_prompt_restart')));
      await tester.pumpAndSettle();

      // 跳回 0 继续播放（引擎在播，断言容一个推进节拍）。
      expect(engine.position, lessThan(const Duration(milliseconds: 500)));
      expect(engine.isPlaying, isTrue);
      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);
    });

    testWidgets('不点小卡：约数秒后自动消失、不打断播放', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      await pumpPlayer(
        tester,
        engine: engine,
        indexStorage: seededIndex(lastPositionMs: 60000),
      );

      await tester.pump(resumePromptAutoDismiss);
      await tester.pump();

      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);
      expect(engine.isPlaying, isTrue);
    });

    testWidgets('位置在头部阈值内：打开不弹卡、静默从该位置播放', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      await pumpPlayer(
        tester,
        engine: engine,
        indexStorage: seededIndex(lastPositionMs: 2000),
      );

      expect(engine.position, greaterThanOrEqualTo(const Duration(seconds: 2)));
      expect(engine.position, lessThan(const Duration(seconds: 3)));
      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);
    });

    testWidgets('无续播位置（新视频）：行为不变、不弹卡', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      await pumpPlayer(
        tester,
        engine: engine,
        indexStorage: seededIndex(lastPositionMs: 0),
      );

      expect(engine.position, lessThan(const Duration(seconds: 1)));
      expect(find.byKey(const Key('resume_prompt_card')), findsNothing);
    });

    testWidgets('暂停播放 → index 记录当前续播位置', (tester) async {
      final engine = FakePlaybackEngine(duration: kDuration);
      final indexStorage = seededIndex(lastPositionMs: 0);
      await pumpPlayer(tester, engine: engine, indexStorage: indexStorage);

      // 播放 5 秒后暂停（双击画面切换播放/暂停）；FakeEngine 每拍推进
      // 100ms，断言容一个节拍内的漂移。
      await tester.pump(const Duration(seconds: 5));
      await doubleTap(tester, find.byKey(const Key('player_surface')));
      expect(engine.isPlaying, isFalse);
      expect(engine.position, lessThan(const Duration(seconds: 6)));

      // 离开播放页（dispose 记录续播位置）。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(
        indexStorage.current.entries.single.lastPositionMs,
        inInclusiveRange(5000, 5900),
      );
    });
  });
}

/// 双击手势（player_page_test 同款）：两次 tap 间隔 < kDoubleTapTimeout。
Future<void> doubleTap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 50));
}
