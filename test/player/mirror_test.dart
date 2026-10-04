import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/mirror.dart';
import 'package:dance_learning_app/player/open_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/poll.dart';

/// load 抛错的索引存储：验证镜像解析的防御性兜底（不阻塞播放）。
class _ThrowingStorage implements VideoIndexStorage {
  @override
  Future<VideoIndex> load() async => throw StateError('索引不可读');

  @override
  Future<VideoIndex> update(
    FutureOr<VideoIndex> Function(VideoIndex current) mutate,
  ) async {
    throw StateError('索引不可写');
  }
}

/// 摘要失败（打开会话无身份）的哈希桩。
class _ThrowingHasher implements ContentHasher {
  const _ThrowingHasher();

  @override
  Future<String> hashFile(File file) async => throw StateError('摘要失败');
}

void main() {
  const sourcePath = '/videos/dance.mp4';
  const videoId = 'abc-hash';

  /// 同名同大小不同内容时打开会话给出的新身份（内容摘要）；旧条目仍在索引里。
  const changedId = 'new-hash';

  VideoIndexEntry entryFor({
    bool mirrored = false,
    bool mirrorAsked = false,
    bool localMirrorEnabled = true,
    SongSignature? signatureCache,
    String? path,
  }) {
    return VideoIndexEntry(
      videoId: videoId,
      displayName: 'dance.mp4',
      filePath: path ?? sourcePath,
      sizeBytes: 3,
      fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
      mirrored: mirrored,
      mirrorAsked: mirrorAsked,
      localMirrorEnabled: localMirrorEnabled,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
      signatureCache: signatureCache,
    );
  }

  group('resolve：首次打开询问 / 再次打开按历史应用', () {
    test('索引无条目（首次打开，后台哈希未落盘）→ asking，镜像保持关闭', () async {
      final storage = InMemoryVideoIndexStorage();
      final controller = MirrorController(storage);

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.asking);
      expect(controller.mirrored, isFalse);
    });

    test('条目已落盘但未询问过（后台哈希先于 resolve）：仍按首次打开询问', () async {
      // 竞态回归：哈希先落盘会创建 mirrored=false
      // 的条目；若无「已询问」标记会被误判为「有历史」→ 用户被漏问。
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor(mirrored: false)]),
      );
      final controller = MirrorController(storage);

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrored: false),
        baselineMarkers: null,
      );

      expect(
        controller.phase,
        MirrorPhase.asking,
        reason: '条目未标记「已询问」→ 仍须询问（用户不会被漏问）',
      );
      expect(controller.mirrored, isFalse);
    });

    test('历史条目已询问且 mirrored=true → historyApplied，引擎镜像开启', () async {
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: true, mirrorAsked: true)],
        ),
      );
      final controller = MirrorController(storage);

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.mirrored, isTrue);
    });

    test('历史条目已询问且 mirrored=false → historyApplied，镜像保持关闭', () async {
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: false, mirrorAsked: true)],
        ),
      );
      final controller = MirrorController(storage);

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrored: false, mirrorAsked: true),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.mirrored, isFalse);
    });

    test('「已按历史应用镜像」提示短暂展示后自动消失', () async {
      final storage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: true, mirrorAsked: true)],
        ),
      );
      final controller = MirrorController(
        storage,
        hintDuration: const Duration(milliseconds: 20),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );
      expect(controller.phase, MirrorPhase.historyApplied);

      await pollUntil(() => controller.phase == MirrorPhase.idle);
    });

    test('会话未识别身份（摘要失败）→ 保持默认不询问、不阻塞', () async {
      // 索引存储不可读也不再是本控制器的输入：解析交给打开会话，控制器
      // 只消费会话给出的身份；无身份时保持默认且绝不触碰索引。
      final controller = MirrorController(_ThrowingStorage());

      await controller.resolve(
        sourcePath,
        videoId: null,
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isFalse);
    });
  });

  group('chooseMirrored：选择后立即生效并按 video_id 持久化', () {
    test('选「是」：立即翻转，索引按 video_id 持久化 mirrored=true 且标记已询问', () async {
      final storage = InMemoryVideoIndexStorage();
      final controller = MirrorController(storage);
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );
      expect(controller.phase, MirrorPhase.asking);
      // 后台哈希随后落盘（模拟条目在作答前已写入、未询问）。
      await storage.update((index) => index.upsert(entryFor(mirrored: false)));

      await controller.chooseMirrored(true);

      expect(controller.mirrored, isTrue, reason: '选择后立即生效（渲染层翻转）');
      expect(controller.phase, MirrorPhase.idle);
      await pollUntil(
        () =>
            storage.current.entries.single.mirrored == true &&
            storage.current.entries.single.mirrorAsked == true,
      );
      expect(storage.current.entries.single.videoId, videoId);
    });

    test('选「否」：镜像关闭，索引持久化 mirrored=false 且标记已询问', () async {
      final storage = InMemoryVideoIndexStorage();
      final controller = MirrorController(storage);
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );
      await storage.update((index) => index.upsert(entryFor(mirrored: true)));

      await controller.chooseMirrored(false);

      expect(controller.mirrored, isFalse);
      await pollUntil(
        () =>
            storage.current.entries.single.mirrored == false &&
            storage.current.entries.single.mirrorAsked == true,
      );
    });

    test('作答后索引条目才落盘（模拟首次导入后台哈希）：重试直至持久化', () async {
      final storage = InMemoryVideoIndexStorage();
      final controller = MirrorController(
        storage,
        persistRetryInterval: const Duration(milliseconds: 10),
        maxPersistRetries: 200,
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );

      await controller.chooseMirrored(true);
      expect(controller.mirrored, isTrue, reason: '选择后立即生效，不等索引落盘');

      // 后台哈希随后落盘（先 mirrored=false、未询问，与既有导入管道一致）。
      await storage.update((index) => index.upsert(entryFor(mirrored: false)));
      expect(storage.current.entries.single.mirrored, isFalse);

      // 重试循环应把作答写回条目（镜像按 video_id 存取）。
      await pollUntil(
        () =>
            storage.current.entries.single.mirrored == true &&
            storage.current.entries.single.mirrorAsked == true,
      );
    });

    test('跨会话恢复：新控制器对同一索引 resolve → 按历史应用', () async {
      final storage = InMemoryVideoIndexStorage();
      final first = MirrorController(storage);
      await first.resolve(sourcePath, videoId: videoId, baselineMarkers: null);
      await first.chooseMirrored(true);
      // 后台哈希随后落盘：重试循环把作答写回条目。
      await storage.update((index) => index.upsert(entryFor(mirrored: false)));
      await pollUntil(
        () =>
            storage.current.entries.single.mirrored == true &&
            storage.current.entries.single.mirrorAsked == true,
      );
      first.dispose();

      // 第二个「会话」：新控制器、同一索引 → 自动按历史应用。
      final second = MirrorController(storage);
      await second.resolve(
        sourcePath,
        videoId: videoId,
        entry: storage.current.entries.single,
        baselineMarkers: null,
      );

      expect(second.phase, MirrorPhase.historyApplied);
      expect(second.mirrored, isTrue);
      second.dispose();
    });

    test('已 dispose 后 chooseMirrored 不生效、不写索引', () async {
      final storage = InMemoryVideoIndexStorage();
      final controller = MirrorController(storage);
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );
      controller.dispose();

      await controller.chooseMirrored(true);

      expect(controller.mirrored, isFalse);
      expect(storage.current.entries, isEmpty);
    });
  });

  group('镜像真值迁移与双写', () {
    VideoIndexEntry entryWithSignature({
      bool mirrored = false,
      bool mirrorAsked = false,
      SongSignature? signatureCache,
    }) {
      return VideoIndexEntry(
        videoId: videoId,
        displayName: 'dance.mp4',
        filePath: sourcePath,
        sizeBytes: 3,
        fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
        mirrored: mirrored,
        mirrorAsked: mirrorAsked,
        lastOpenedAt: DateTime(2026, 9, 1, 12),
        signatureCache: signatureCache,
      );
    }

    InMemoryVideoDocumentStorage markersStorageOf(bool mirrored) =>
        InMemoryVideoDocumentStorage(
          markers: MarkersDocument.empty().withMirrored(mirrored).toJson(),
        );

    test(
      'markers 存在（分享文件模拟：无 mirrorAsked 条目）→ 打开直接应用、不询问，index 回写镜像缓存',
      () async {
        final indexStorage = InMemoryVideoIndexStorage(
          initial: VideoIndex(entries: [entryWithSignature()]),
        );
        final coordinator = VideoDocumentCoordinator(markersStorageOf(true));
        final controller = MirrorController(
          indexStorage,
          coordinatorFor: (_) => coordinator,
        );

        await controller.resolve(
          sourcePath,
          videoId: videoId,
          entry: entryWithSignature(),
          baselineMarkers: MarkersDocument.empty().withMirrored(true),
        );

        expect(controller.phase, MirrorPhase.idle, reason: '不弹询问');
        expect(controller.mirrored, isTrue);
        await pollUntil(
          () => indexStorage.current.entries.single.mirrored == true,
          reason: '同步规则：markers 镜像回写 index 缓存',
        );
        expect(
          indexStorage.current.entries.single.mirrorAsked,
          isFalse,
          reason: '回写不触碰「已询问」标记',
        );
      },
    );

    test('markers 存在且镜像为关 → 直接应用 false，不弹询问', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryWithSignature(mirrored: true, mirrorAsked: true)],
        ),
      );
      final coordinator = VideoDocumentCoordinator(markersStorageOf(false));
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(mirrored: true, mirrorAsked: true),
        baselineMarkers: MarkersDocument.empty().withMirrored(false),
      );

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isFalse, reason: 'markers 真值优先于 index 过渡值');
    });

    test('markers 不存在 → 维持 index mirrorAsked 逻辑（已问过按过渡值应用）', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryWithSignature(mirrored: true, mirrorAsked: true)],
        ),
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.mirrored, isTrue);
    });

    test('杀进程重开（index 路径，markers 始终不存在）→ 新控制器仍按 index 历史应用', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryWithSignature(mirrored: true, mirrorAsked: true)],
        ),
      );
      final coordinator = VideoDocumentCoordinator(
        InMemoryVideoDocumentStorage(),
      );
      final first = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );
      await first.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );
      expect(first.phase, MirrorPhase.historyApplied);
      first.dispose();

      final reopened = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );
      await reopened.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );
      expect(reopened.phase, MirrorPhase.historyApplied);
      expect(reopened.mirrored, isTrue);
      reopened.dispose();
    });

    test('作答双写：markers 不存在 → 首建带署名缓存 + 答案镜像；index 照旧标记已询问', () async {
      const signature = SongSignature(song: 'My Love', remark: '9人版');
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryWithSignature(signatureCache: signature)],
        ),
      );
      final markersStorage = InMemoryVideoDocumentStorage();
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(signatureCache: signature),
        baselineMarkers: null,
      );
      expect(controller.phase, MirrorPhase.asking);
      await controller.chooseMirrored(true);

      await pollUntil(() => markersStorage.markersSnapshot.isNotEmpty);
      final markers = MarkersDocument.fromJson(markersStorage.markersSnapshot);
      expect(markers.mirrored, isTrue, reason: '答案镜像落 markers');
      expect(markers.signature?.song, 'My Love', reason: '首建带 index 署名缓存');
      expect(markers.signature?.remark, '9人版');
      expect(indexStorage.current.entries.single.mirrorAsked, isTrue);
    });

    test('切换与杀进程重开：markers 已存在时更新镜像不重种署名；新控制器打开直接应用', () async {
      const oldSignature = SongSignature(song: 'Old');
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryWithSignature(signatureCache: oldSignature)],
        ),
      );
      final markersStorage = InMemoryVideoDocumentStorage();
      final coordinator = VideoDocumentCoordinator(markersStorage);
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(signatureCache: oldSignature),
        baselineMarkers: null,
      );
      expect(controller.phase, MirrorPhase.asking, reason: 'markers 未建，走询问');
      await controller.chooseMirrored(true);
      await pollUntil(
        () => MarkersDocument.fromJson(markersStorage.markersSnapshot).mirrored,
      );
      controller.dispose();

      // 杀进程重开：新控制器、同一持久化状态 → 直接应用不询问。
      final reopened = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );
      await reopened.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryWithSignature(signatureCache: oldSignature),
        baselineMarkers: MarkersDocument.fromJson(
          markersStorage.markersSnapshot,
        ),
      );
      expect(reopened.phase, MirrorPhase.idle);
      expect(reopened.mirrored, isTrue);

      // 控制层切换：再点关掉 → markers 镜像更新，署名不被重种覆盖。
      await reopened.chooseMirrored(false);
      await pollUntil(() {
        final markers = MarkersDocument.fromJson(
          markersStorage.markersSnapshot,
        );
        return markers.mirrored == false;
      });
      final markers = MarkersDocument.fromJson(markersStorage.markersSnapshot);
      expect(markers.signature?.song, 'Old');
      reopened.dispose();
    });
  });

  group('首次导入：会话基线才是镜像真值', () {
    VideoIndexEntry entryOf({
      bool mirrored = false,
      bool mirrorAsked = false,
    }) => VideoIndexEntry(
      videoId: videoId,
      displayName: 'dance.mp4',
      filePath: sourcePath,
      sizeBytes: 3,
      fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
      mirrored: mirrored,
      mirrorAsked: mirrorAsked,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
    );

    test('打开时不在盘 + 未询问过：命名框本次首建的文档（种子）不是答案 → 仍询问', () async {
      // 首次导入：命名框先跑，按索引过渡值首建 markers（mirrored=false 的
      // 种子）；随后镜像 resolve 不得把它当作镜像真值——用户从未被问过。
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryOf()]),
      );
      final markersStorage = InMemoryVideoDocumentStorage(
        markers: MarkersDocument.empty()
            .withSignature(const SongSignature(song: 'My Love'))
            .toJson(),
        markersPresent: true,
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryOf(),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.asking, reason: '跳过了命名照样被问镜像');
      expect(controller.mirrored, isFalse);
    });

    test('打开时不在盘 + 索引已询问过 → 仍按 index 历史应用', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryOf(mirrored: true, mirrorAsked: true)],
        ),
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryOf(mirrored: true, mirrorAsked: true),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.mirrored, isTrue);
    });

    test('打开时已在盘 → 直接应用、不询问，并回写 index 缓存', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryOf(mirrored: false)]),
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryOf(),
        baselineMarkers: MarkersDocument.empty().withMirrored(true),
      );

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isTrue, reason: '基线真值优先于 index 过渡值');
      await pollUntil(
        () => indexStorage.current.entries.single.mirrored == true,
        reason: '在盘真值回写 index 缓存（未询问标记不动）',
      );
      expect(indexStorage.current.entries.single.mirrorAsked, isFalse);
    });
  });

  group('局部镜像总开关', () {
    test('读取路径①文件真值：markers meta.localMirrorEnabled=false → 打开即应用、推给值道、回写 index 缓存', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor(localMirrorEnabled: true)]),
      );
      final markersStorage = InMemoryVideoDocumentStorage(
        markers: MarkersDocument.empty().withLocalMirrorEnabled(false).toJson(),
      );
      final pushed = <bool>[];
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
        onLocalMirrorEnabledChanged: pushed.add,
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(localMirrorEnabled: true),
        baselineMarkers: MarkersDocument.empty().withLocalMirrorEnabled(false),
      );

      expect(controller.phase, MirrorPhase.idle, reason: 'markers 存在即不询问');
      expect(controller.localMirrorEnabled, isFalse, reason: 'markers 真值优先');
      expect(pushed.last, isFalse, reason: '打开读取写值道');
      await pollUntil(
        () => indexStorage.current.entries.single.localMirrorEnabled == false,
        reason: '同步规则：markers 总开关回写 index 过渡值',
      );
      expect(
        indexStorage.current.entries.single.mirrorAsked,
        isFalse,
        reason: '回写不触碰「已询问」标记',
      );
    });

    test('读取路径②本机缓存过渡值：markers 未创建 → 按 index 过渡值应用（已问过走历史路径）', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrorAsked: true, localMirrorEnabled: false)],
        ),
      );
      final pushed = <bool>[];
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
        onLocalMirrorEnabledChanged: pushed.add,
      );

      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrorAsked: true, localMirrorEnabled: false),
        baselineMarkers: null,
      );

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.localMirrorEnabled, isFalse);
      expect(pushed.last, isFalse);
    });

    test('读取路径③首建初值：会话无条目（新视频）/缺键 → 总开关缺省 true', () async {
      // 无条目（会话按摘要给出身份）：无从取 markers/index → 缺省 true。
      final noEntry = MirrorController(
        InMemoryVideoIndexStorage(),
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );
      await noEntry.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );
      expect(noEntry.localMirrorEnabled, isTrue);
      expect(noEntry.phase, MirrorPhase.asking);

      // 条目缺键（旧索引文件）：同样兜底 true。
      final legacy = VideoIndexEntry.fromJson(
        entryFor(mirrorAsked: true).toJson()..remove('localMirrorEnabled'),
      );
      final keyless = MirrorController(
        InMemoryVideoIndexStorage(initial: VideoIndex(entries: [legacy])),
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );
      await keyless.resolve(
        sourcePath,
        videoId: videoId,
        entry: legacy,
        baselineMarkers: null,
      );
      expect(keyless.localMirrorEnabled, isTrue);
    });

    test('切换即写盘：总开关双写 index 过渡值 + markers 真值；杀进程重开恢复', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entryFor(mirrorAsked: true)]),
      );
      final markersStorage = InMemoryVideoDocumentStorage();
      final coordinator = VideoDocumentCoordinator(markersStorage);
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrorAsked: true),
        baselineMarkers: null,
      );

      controller.setLocalMirrorEnabled(false);

      await pollUntil(
        () =>
            MarkersDocument.fromJson(markersStorage.markersSnapshot)
                .localMirrorEnabled ==
            false,
        reason: '公开标记文件里读得到该字段（无「保存」步）',
      );
      expect(
        indexStorage.current.entries.single.localMirrorEnabled,
        isFalse,
        reason: '本机缓存（视频索引）同步回写',
      );
      controller.dispose();

      // 杀进程重开：新控制器、同一持久化状态 → 恢复用户取值。
      final reopened = MirrorController(
        indexStorage,
        coordinatorFor: (_) => coordinator,
      );
      await reopened.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrorAsked: true),
        baselineMarkers: MarkersDocument.fromJson(
          markersStorage.markersSnapshot,
        ),
      );
      expect(reopened.localMirrorEnabled, isFalse);
      expect(reopened.phase, MirrorPhase.idle);
      reopened.dispose();
    });

    test('文件不存在时首建：出生带 index 过渡值（署名/全局镜像/总开关），随后写本次真值', () async {
      const signature = SongSignature(song: 'My Love');
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [
            entryFor(
              mirrored: true,
              mirrorAsked: true,
              localMirrorEnabled: false,
              signatureCache: signature,
            ),
          ],
        ),
      );
      final markersStorage = InMemoryVideoDocumentStorage();
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(
          mirrored: true,
          mirrorAsked: true,
          localMirrorEnabled: false,
          signatureCache: signature,
        ),
        baselineMarkers: null,
      );
      expect(controller.mirrored, isTrue, reason: 'index 过渡值应用');
      expect(controller.localMirrorEnabled, isFalse);

      // 全局镜像作答：markers 不存在 → 首建初值带 index 的总开关过渡值
      //（false 不被默认 true 冲掉），随后写入本次全局镜像。
      await controller.chooseMirrored(false);

      await pollUntil(
        () =>
            MarkersDocument.fromJson(markersStorage.markersSnapshot)
                .localMirrorEnabled ==
            false,
      );
      final markers = MarkersDocument.fromJson(markersStorage.markersSnapshot);
      expect(markers.mirrored, isFalse, reason: '本次全局镜像真值');
      expect(markers.signature?.song, 'My Love', reason: '首建带 index 署名缓存');
      expect(markers.localMirrorEnabled, isFalse, reason: '首建带总开关过渡值');
    });

    test('首次导入条目未落盘：切换后按既有重试兜底写入，条目出现即双写', () async {
      final indexStorage = InMemoryVideoIndexStorage();
      final markersStorage = InMemoryVideoDocumentStorage();
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
        persistRetryInterval: const Duration(milliseconds: 1),
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );

      controller.setLocalMirrorEnabled(false);

      // 后台哈希随后落盘（首次导入的索引条目出现）。
      await indexStorage.update(
        (index) => index.upsert(entryFor(mirrorAsked: true)),
      );

      await pollUntil(
        () =>
            MarkersDocument.fromJson(markersStorage.markersSnapshot)
                .localMirrorEnabled ==
            false,
        reason: '条目出现后重试成功、双写 markers',
      );
      expect(indexStorage.current.entries.single.localMirrorEnabled, isFalse);
    });

    test('写盘失败不阻塞 UI：索引不可写时取值仍立即生效、不抛到调用方', () async {
      final controller = MirrorController(
        _ThrowingStorage(),
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        baselineMarkers: null,
      );

      controller.setLocalMirrorEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.localMirrorEnabled, isFalse, reason: '视图开关立即生效');
    });

    test('创建即生效：关着的总开关被自动打开并落盘；已开着时不产生动作', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrorAsked: true, localMirrorEnabled: false)],
        ),
      );
      final markersStorage = InMemoryVideoDocumentStorage(
        markers: MarkersDocument.empty().withLocalMirrorEnabled(false).toJson(),
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(markersStorage),
      );
      await controller.resolve(
        sourcePath,
        videoId: videoId,
        entry: entryFor(mirrorAsked: true, localMirrorEnabled: false),
        baselineMarkers: MarkersDocument.empty().withLocalMirrorEnabled(false),
      );
      expect(controller.localMirrorEnabled, isFalse);

      var notified = 0;
      controller.addListener(() => notified++);
      controller.enableLocalMirrorForNewFragment();
      expect(controller.localMirrorEnabled, isTrue, reason: '新建片段即生效');
      expect(notified, 1);
      await pollUntil(
        () =>
            MarkersDocument.fromJson(markersStorage.markersSnapshot)
                .localMirrorEnabled ==
            true,
      );

      // 已开着：再创建不重复开关、不再通知。
      controller.enableLocalMirrorForNewFragment();
      expect(notified, 1, reason: '已开着时为无操作');
    });
  });

  group('哈希不符（同名同大小不同内容）：按新视频处理', () {
    test('会话给出新身份、旧条目保留：不套用旧条目，答案写入新视频文档', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: false, mirrorAsked: false)],
        ),
      );
      final changedStorage = InMemoryVideoDocumentStorage();
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (id) => VideoDocumentCoordinator(
          id == changedId ? changedStorage : InMemoryVideoDocumentStorage(),
        ),
      );

      // 打开会话：条目命中但摘要不符 → 身份取摘要、entry 为 null、旧条目保留。
      await controller.resolve(
        sourcePath,
        videoId: changedId,
        baselineMarkers: null,
      );

      expect(
        controller.phase,
        MirrorPhase.asking,
        reason: '摘要不符 → 按新视频，不套用旧条目的「已询问」历史',
      );
      expect(controller.mirrored, isFalse, reason: '不套用旧条目的历史');

      await controller.chooseMirrored(true);
      await pollUntil(
        () => MarkersDocument.fromJson(changedStorage.markersSnapshot).mirrored,
        reason: '答案按会话给出的新身份写入新视频文档',
      );

      final old = indexStorage.current.entries.single;
      expect(old.mirrored, isFalse, reason: '摘要不符时旧条目的镜像缓存不被写');
      expect(old.mirrorAsked, isFalse, reason: '摘要不符时旧条目的「已询问」标记不被写');
    });

    test('新身份已有 markers 真值：直接应用且不回写旧条目缓存', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: false, mirrorAsked: true)],
        ),
      );
      final changedStorage = InMemoryVideoDocumentStorage(
        markers: MarkersDocument.empty().withMirrored(true).toJson(),
      );
      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (id) => VideoDocumentCoordinator(
          id == changedId ? changedStorage : InMemoryVideoDocumentStorage(),
        ),
      );

      await controller.resolve(
        sourcePath,
        videoId: changedId,
        baselineMarkers: MarkersDocument.empty().withMirrored(true),
      );

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isTrue, reason: '新身份 markers 真值优先');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final old = indexStorage.current.entries.single;
      expect(old.mirrored, isFalse, reason: '同步回写按身份守写：旧条目不被写');
    });
  });

  group('resolveFor：消费打开会话的身份与文档快照', () {
    OpenSession sessionFor({
      required VideoIndexStorage indexStore,
      required VideoDocumentCoordinator Function(String videoId) coordinatorFor,
      bool identified = true,
    }) => OpenSession(
      filePath: sourcePath,
      indexStore: indexStore,
      hasher: identified ? const FixedHasher(videoId) : const _ThrowingHasher(),
      coordinatorFor: coordinatorFor,
    );

    test('会话基线 markers 在盘 → 直接应用，不询问、不看 index 历史', () async {
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(
          entries: [entryFor(mirrored: false, mirrorAsked: true)],
        ),
      );
      final docStorage = InMemoryVideoDocumentStorage(
        markers: MarkersDocument.empty().withMirrored(true).toJson(),
      );
      final session = sessionFor(
        indexStore: indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(docStorage),
      );
      await session.establish();

      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(docStorage),
      );
      await controller.resolveFor(session);

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isTrue, reason: '会话基线真值优先于 index 历史');
    });

    test('会话条目已询问、markers 不在盘 → 按历史应用并提示', () async {
      final entry = entryFor(mirrored: true, mirrorAsked: true);
      final indexStorage = InMemoryVideoIndexStorage(
        initial: VideoIndex(entries: [entry]),
      );
      final docStorage = InMemoryVideoDocumentStorage();
      final session = sessionFor(
        indexStore: indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(docStorage),
      );
      await session.establish();

      final controller = MirrorController(
        indexStorage,
        coordinatorFor: (_) => VideoDocumentCoordinator(docStorage),
      );
      await controller.resolveFor(session);

      expect(controller.phase, MirrorPhase.historyApplied);
      expect(controller.mirrored, isTrue);
    });

    test('会话未识别身份（摘要失败）→ 保持默认、不询问', () async {
      final indexStorage = InMemoryVideoIndexStorage();
      final session = sessionFor(
        indexStore: indexStorage,
        coordinatorFor: (_) =>
            VideoDocumentCoordinator(InMemoryVideoDocumentStorage()),
        identified: false,
      );
      await session.establish();

      final controller = MirrorController(indexStorage);
      await controller.resolveFor(session);

      expect(controller.phase, MirrorPhase.idle);
      expect(controller.mirrored, isFalse);
    });
  });
}
