import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/annotation/segment_line.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentCoordinatorProvider, videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/open_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

const String kVideoId = 'hash-1';
const String kFilePath = '/videos/a.mp4';

/// 按视频文档存储 · 可闸门版：每次 [loadMarkers] 读到旧文档后停在闸门上，
/// 直到 [releaseAll] 放行。两个写者交错时，两条读改写会各自读到同一份旧
/// 文档、再先后覆盖写回——复现「刚提交的标注被退回上一版」。
class GatedVideoDocumentStorage implements VideoDocumentStorage {
  GatedVideoDocumentStorage(this._inner);

  final VideoDocumentStorage _inner;

  /// 置真后 [loadMarkers] 读到内容即停闸。
  bool holdLoads = false;

  final List<Completer<void>> _releases = [];

  @override
  Future<Map<String, dynamic>> loadMarkers() async {
    final json = await _inner.loadMarkers();
    if (holdLoads) {
      final release = Completer<void>();
      _releases.add(release);
      await release.future;
    }
    return json;
  }

  @override
  Future<Map<String, dynamic>?> loadMarkersOrNull() =>
      _inner.loadMarkersOrNull();

  @override
  Future<void> saveMarkers(Map<String, dynamic> json) =>
      _inner.saveMarkers(json);

  @override
  Future<Map<String, dynamic>> loadLocal() => _inner.loadLocal();

  @override
  Future<Map<String, dynamic>?> loadLocalOrNull() =>
      _inner.loadLocalOrNull();

  @override
  Future<void> saveLocal(Map<String, dynamic> json) => _inner.saveLocal(json);

  @override
  Future<void> delete() => _inner.delete();

  @override
  Future<void> mutateMarkers(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present}) apply,
  ) =>
      _inner.mutateMarkers(apply);

  @override
  Future<void> mutateLocal(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present}) apply,
  ) =>
      _inner.mutateLocal(apply);

  /// 放行全部停在闸门上的读。
  void releaseAll() {
    holdLoads = false;
    for (final release in _releases) {
      if (!release.isCompleted) release.complete();
    }
  }
}

/// 装配并建立打开会话（播放页 `_restoreForVideo` 等价接线）。
Future<OpenSession> establishFor(ProviderContainer container) async {
  final session = OpenSession(
    filePath: kFilePath,
    indexStore: container.read(videoIndexStoreProvider),
    hasher: const FixedHasher(kVideoId),
    coordinatorFor: (videoId) =>
        container.read(videoDocumentCoordinatorProvider(videoId)),
  );
  await session.establish();
  return session;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('single_writer_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  /// 真实文件与内存替身双跑。
  VideoDocumentStorage makeReal(Directory dir) => AtomicVideoDocumentStorage(
    markersFile: File(p.join(dir.path, 'markers_$kVideoId.json')),
    localFile: File(p.join(dir.path, 'local_$kVideoId.json')),
  );

  for (final (label, make) in [
    ('真实文件', makeReal),
    ('内存 fake', (Directory dir) => InMemoryVideoDocumentStorage()),
  ]) {
    group(label, () {
      test('两个写者交错：写链按文档身份共享，两字段都存活（先红后绿）', () async {
        // 同一份文档被两个协调器包裹（「两个写者」）——若两条写链独立，
        // 交错时后写的一份会把前一份的字段退回上一版。
        final storage = GatedVideoDocumentStorage(make(tempDir));
        final mirrorWriter = VideoDocumentCoordinator(storage);
        final annotationWriter = VideoDocumentCoordinator(storage);

        storage.holdLoads = true;
        final mirrorWrite = mirrorWriter.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        final annotationWrite = annotationWriter.patchMarkers(
          (doc) => doc.withSegmentLines(const [
            SegmentLine(position: Duration(seconds: 30)),
          ]),
        );
        // 让两个写者都读到同一份旧文档并停在闸门上，再一起放行：独立写链时
        // 两条读改写各以旧文档为基础、后写的一份把另一字段退回上一版。
        await Future<void>.delayed(const Duration(milliseconds: 100));
        storage.releaseAll();
        await Future.wait([mirrorWrite, annotationWrite]);

        final markers = await mirrorWriter.readMarkers();
        expect(markers.mirrored, isTrue, reason: '镜像开关字段存活');
        expect(
          markers.segmentLines,
          hasLength(1),
          reason: '刚提交的标注未被退回上一版',
        );
      });

      test('生产装配：会话与消费方取得同一条写链', () async {
        final gated = GatedVideoDocumentStorage(make(tempDir));
        final container = ProviderContainer(
          overrides: [
            videoDocumentStorageFactoryProvider.overrideWithValue(
              (_) => gated,
            ),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(initial: VideoIndex.empty),
            ),
            contentHasherProvider.overrideWithValue(const FixedHasher(kVideoId)),
          ],
        );
        addTearDown(container.dispose);

        final session = await establishFor(container);
        expect(session.videoId, kVideoId);

        // 会话持有的写链（保存编排/节拍/名册入口）与生产消费方经注入点拿到
        // 的写链（镜像/署名/偏好）必须是同一份；会话若自建协调器，
        // `identical` 即红。
        final sessionChain = session.coordinator!;
        final consumerChain = container.read(
          videoDocumentCoordinatorProvider(kVideoId),
        );
        expect(identical(sessionChain, consumerChain), isTrue);

        gated.holdLoads = true;
        final mirrorWrite = sessionChain.patchMarkers(
          (doc) => doc.withMirrored(true),
        );
        final annotationWrite = consumerChain.patchMarkers(
          (doc) => doc.withSegmentLines(const [
            SegmentLine(position: Duration(seconds: 30)),
          ]),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        gated.releaseAll();
        await Future.wait([mirrorWrite, annotationWrite]);

        final markers = await sessionChain.readMarkers();
        expect(markers.mirrored, isTrue, reason: '镜像开关字段存活');
        expect(
          markers.segmentLines,
          hasLength(1),
          reason: '刚提交的标注未被退回上一版',
        );
      });
    });
  }
}
