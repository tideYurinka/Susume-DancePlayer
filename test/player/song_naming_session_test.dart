import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/marker_document.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:dance_learning_app/player/song_naming_contract.dart';
import 'package:dance_learning_app/player/song_naming_session.dart';
import 'package:dance_learning_app/stats/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';

/// 命名会话域直测：不 pump widget、不注容器。
///
/// seam = 会话交出的编排与提交行为：判定是否经呈现接缝弹框、把什么初值与
/// 对话框行为交给宿主、收到结论后如何提交（净化后双写 index + markers）。
/// 署名读写用真实的 [SongSignatureController]；宿主侧对话框用记录型 fake
/// 呈现接缝。统计署名迁移的接线在统计域套件里以「提交信号 → 迁移」直测。
void main() {
  const filePath = '/priv/videos/dance.mp4';

  VideoIndexEntry entry({SongSignature? signatureCache}) {
    return VideoIndexEntry(
      videoId: 'hash-1',
      displayName: 'dance.mp4',
      filePath: filePath,
      sizeBytes: 3,
      fastKey: fastKeyFor(name: 'dance.mp4', sizeBytes: 3),
      mirrored: false,
      mirrorAsked: true,
      lastOpenedAt: DateTime(2026, 9, 1, 12),
      signatureCache: signatureCache,
    );
  }

  late InMemoryVideoIndexStorage index;
  late InMemoryVideoDocumentStorage docs;
  late SongSignatureController signature;
  late _RecordingPresenter presenter;
  late SongNamingSession session;

  void makeSession() {
    index = InMemoryVideoIndexStorage();
    docs = InMemoryVideoDocumentStorage();
    signature = SongSignatureController(
      index,
      coordinatorFor: (_) => VideoDocumentCoordinator(docs),
    );
    session = SongNamingSession(
      signatureController: signature,
      // 读面交来的已是「文件名回落名」（去扩展名）：域不自行去扩展名。
      fallbackName: () => 'dance',
      presentNaming: presenter.call,
    );
  }

  Future<void> openAs({SongSignature? signatureCache}) async {
    await index.update(
      (current) => current.upsert(entry(signatureCache: signatureCache)),
    );
    final current = index.current.findByFilePath(filePath);
    await signature.startForFile(
      filePath,
      videoId: current?.videoId,
      entry: current,
    );
  }

  setUp(() {
    presenter = _RecordingPresenter();
    makeSession();
  });

  group('首次导入判定与呈现接缝', () {
    test('新导入且未署名：经接缝弹导入命名框（场景=导入、三字段空、不可点框外收起）', () async {
      await openAs();

      await session.promptImportIfNeeded(isNewImport: true);

      expect(presenter.calls, hasLength(1));
      final call = presenter.calls.single;
      expect(call.scene, SongNamingScene.import);
      expect(call.initial.song, isEmpty);
      expect(call.initial.dancer, isEmpty);
      expect(call.initial.remark, isEmpty);
      expect(call.fallbackName, 'dance');
      expect(call.barrierDismissible, isFalse);
    });

    test('已署名：不弹命名框', () async {
      await openAs(signatureCache: const SongSignature(song: 'My Love'));

      await session.promptImportIfNeeded(isNewImport: true);

      expect(presenter.calls, isEmpty);
    });

    test('非首次导入：未署名也不弹命名框', () async {
      await openAs();

      await session.promptImportIfNeeded(isNewImport: false);

      expect(presenter.calls, isEmpty);
    });
  });

  group('提交路径（导入命名 / 改名共用）', () {
    test('导入保存：净化后双写 index + markers，标题即时刷新', () async {
      await openAs();
      presenter.result = const SongNamingResult(
        confirmed: true,
        signature: SongSignature(
          dancer: ' 如\n',
          song: 'My Love',
          remark: '9人版\x7f',
        ),
      );

      await session.promptImportIfNeeded(isNewImport: true);

      const applied = SongSignature(
        dancer: '如',
        song: 'My Love',
        remark: '9人版',
      );
      expect(MarkersDocument.fromJson(docs.markersSnapshot).signature, applied);
      expect(index.current.entries.single.signatureCache, applied);
      expect(session.titleText, '「如」My Love - 9人版');
    });

    test('导入退路钮：按文件名回落名署名（双写 index + markers）', () async {
      await openAs();
      presenter.result = const SongNamingResult(
        confirmed: false,
        signature: SongSignature(song: '改一半'),
      );

      await session.promptImportIfNeeded(isNewImport: true);

      const applied = SongSignature(song: 'dance');
      expect(MarkersDocument.fromJson(docs.markersSnapshot).signature, applied);
      expect(index.current.entries.single.signatureCache, applied);
    });

    test('改名：接缝收到场景=改名与带出现值的初值且可点框外收起；保存后提交', () async {
      const current = SongSignature(
        dancer: '如',
        song: 'My Love',
        remark: '9人版',
      );
      await openAs(signatureCache: current);
      presenter.result = const SongNamingResult(
        confirmed: true,
        signature: SongSignature(dancer: '如', song: 'My Love 2', remark: '9人版'),
      );

      await session.rename();

      final call = presenter.calls.single;
      expect(call.scene, SongNamingScene.rename);
      expect(call.initial.song, 'My Love');
      expect(call.initial.dancer, '如');
      expect(call.initial.remark, '9人版');
      expect(call.barrierDismissible, isTrue);
      expect(
        MarkersDocument.fromJson(docs.markersSnapshot).signature,
        const SongSignature(dancer: '如', song: 'My Love 2', remark: '9人版'),
      );
    });

    test('未署名视频改名：初值歌曲名回退文件名，保存即补命名落盘', () async {
      await openAs();
      presenter.result = const SongNamingResult(
        confirmed: true,
        signature: SongSignature(song: '补命名'),
      );

      await session.rename();

      expect(presenter.calls.single.initial.song, 'dance');
      expect(presenter.calls.single.initial.dancer, isEmpty);
      expect(
        MarkersDocument.fromJson(docs.markersSnapshot).signature,
        const SongSignature(song: '补命名'),
      );
    });

    test('改名取消：点框外交回 null 与「取消」都不提交', () async {
      const current = SongSignature(song: 'My Love');
      await openAs(signatureCache: current);

      presenter.result = null;
      await session.rename();
      presenter.result = const SongNamingResult(
        confirmed: false,
        signature: SongSignature(song: '改一半'),
      );
      await session.rename();

      expect(signature.signature, current);
      expect(docs.markersSnapshot, isEmpty);
    });
  });

  test('顶栏显示串：未署名回退文件名回落名', () async {
    await openAs();
    expect(session.titleText, 'dance');

    await openAs(signatureCache: const SongSignature(song: 'My Love'));
    expect(session.titleText, 'My Love');
  });
}

/// 记录型呈现接缝：记下域交来的场景、初值与对话框行为，按 [result] 交回结论。
class _RecordingPresenter {
  final List<
    ({
      SongNamingScene scene,
      SongNamingInitial initial,
      String fallbackName,
      bool barrierDismissible,
    })
  >
  calls = [];

  SongNamingResult? result;

  Future<SongNamingResult?> call({
    required SongNamingScene scene,
    required SongNamingInitial initial,
    required String fallbackName,
    required bool barrierDismissible,
  }) async {
    calls.add((
      scene: scene,
      initial: initial,
      fallbackName: fallbackName,
      barrierDismissible: barrierDismissible,
    ));
    return result;
  }
}
