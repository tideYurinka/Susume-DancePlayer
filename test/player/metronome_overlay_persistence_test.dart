import 'dart:async';

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:dance_learning_app/player/metronome_overlay.dart';
import 'package:dance_learning_app/player/overlay.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// `prefs.overlay` 子对象（测试读取用）。
Map<String, dynamic> overlayOf(InMemoryVideoDocumentStorage storage) =>
    (storage.localSnapshot['prefs'] as Map<String, dynamic>)['overlay']
        as Map<String, dynamic>;

void main() {
  const pathA = '/videos/a.mp4';
  const idA = 'vid-a';

  late Map<String, InMemoryVideoDocumentStorage> storages;
  late ProviderContainer container;

  ProviderContainer makeContainer({
    Map<String, Map<String, dynamic>> localFiles = const {},
  }) {
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [historyEntry(filePath: pathA, mirrored: false, videoId: idA)],
      ),
    );
    storages = {
      idA: InMemoryVideoDocumentStorage(local: localFiles[idA] ?? const {}),
    };
    return ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        videoIndexStoreProvider.overrideWithValue(index),
        for (final entry in storages.entries)
          videoDocumentStorageProvider(entry.key)
              .overrideWithValue(entry.value),
      ],
    );
  }

  group('LocalDocument 浮层四格字段（schema 往返）', () {
    test('写入读取往返：四格两键齐全 + 两个共用系数保留', () {
      const doc = LocalDocument(
        overlay: OverlayPlacementFields(
          dx: 24.0,
          dy: 96.0,
          landscapeDx: 11.0,
          landscapeDy: 22.0,
          compareDx: 33.0,
          compareDy: 44.0,
          landscapeCompareDx: 55.0,
          landscapeCompareDy: 66.0,
          rectWidthFactor: 1.5,
          pendulumScale: 0.8,
        ),
      );
      final restored = LocalDocument.fromJson(doc.toJson());
      expect(restored.overlay, doc.overlay);
      expect(restored, doc);
      expect(restored.hashCode, doc.hashCode);
    });

    test('文件键形状：竖屏·普通沿用 dx/dy，其余三格各一对新键', () {
      final json = const LocalDocument(
        overlay: OverlayPlacementFields(
          dx: 1.0,
          dy: 2.0,
          landscapeDx: 3.0,
          landscapeDy: 4.0,
          compareDx: 5.0,
          compareDy: 6.0,
          landscapeCompareDx: 7.0,
          landscapeCompareDy: 8.0,
          rectWidthFactor: 1.25,
          pendulumScale: 1.75,
        ),
      ).toJson();
      expect(json['prefs']['overlay'], {
        'dx': 1.0,
        'dy': 2.0,
        'landscapeDx': 3.0,
        'landscapeDy': 4.0,
        'compareDx': 5.0,
        'compareDy': 6.0,
        'landscapeCompareDx': 7.0,
        'landscapeCompareDy': 8.0,
        'rectWidthFactor': 1.25,
        'pendulumScale': 1.75,
      });
    });

    test('未自定义时 overlay 键不写出（承诺性形状）', () {
      const doc = LocalDocument();
      expect(doc.overlay, isNull);
      expect(doc.toJson()['prefs'].containsKey('overlay'), isFalse);
    });

    test('旧文件迁移：只有 dx/dy 读成竖屏·普通已自定义、其余三格未自定义', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {'dx': 40.0, 'dy': 80.0},
        },
      });
      expect(doc.overlay!.dx, 40.0);
      expect(doc.overlay!.dy, 80.0);
      expect(doc.overlay!.landscapeDx, isNull);
      expect(doc.overlay!.landscapeDy, isNull);
      expect(doc.overlay!.compareDx, isNull);
      expect(doc.overlay!.compareDy, isNull);
      expect(doc.overlay!.landscapeCompareDx, isNull);
      expect(doc.overlay!.landscapeCompareDy, isNull);
    });

    test('未拖过的旧文件（无 overlay 段）读成四格全未自定义', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {'layoutLocked': true},
      });
      expect(doc.overlay, isNull);
    });

    test('缺任一个键的格 = 未自定义（整格不成立）', () {
      final onlyDx = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {'dx': 40.0},
        },
      });
      expect(onlyDx.overlay, isNull);

      final halfLandscape = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {'dx': 40.0, 'dy': 80.0, 'landscapeDx': 5.0},
        },
      });
      expect(halfLandscape.overlay!.dx, 40.0);
      expect(halfLandscape.overlay!.dy, 80.0);
      expect(halfLandscape.overlay!.landscapeDx, isNull);
      expect(halfLandscape.overlay!.landscapeDy, isNull);
    });

    test('清除一格 = 文件里该格的两个键都消失（不写 0 占位）', () {
      const doc = LocalDocument(
        overlay: OverlayPlacementFields(
          dx: 1.0,
          dy: 2.0,
          landscapeDx: 3.0,
          landscapeDy: 4.0,
        ),
      );
      // 整组写：绝对终值里只剩竖屏·普通。
      final cleared = doc.withOverlayPlacements(
        const OverlayPlacementFields(dx: 1.0, dy: 2.0),
      );
      final overlay = cleared.toJson()['prefs']['overlay'] as Map;
      expect(overlay.containsKey('landscapeDx'), isFalse);
      expect(overlay.containsKey('landscapeDy'), isFalse);
      expect(overlay['dx'], 1.0);
      expect(overlay['dy'], 2.0);
    });

    test('非法系数读入钳制进 0.5–3.0（缺键保持未设）', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {
            'dx': 1.0,
            'dy': 2.0,
            'rectWidthFactor': 9.0,
            'pendulumScale': 0.1,
          },
        },
      });
      expect(doc.overlay!.rectWidthFactor, 3.0);
      expect(doc.overlay!.pendulumScale, 0.5);

      final defaults = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {'dx': 1.0, 'dy': 2.0},
        },
      });
      expect(defaults.overlay!.rectWidthFactor, isNull);
      expect(defaults.overlay!.pendulumScale, isNull);
    });

    test('overlay 字段参与相等判定（patch 跳写语义成立）', () {
      expect(
        const LocalDocument(
              overlay: OverlayPlacementFields(dx: 1.0, dy: 0.0),
            ) ==
            const LocalDocument(),
        isFalse,
      );
      expect(
        const LocalDocument(
              overlay: OverlayPlacementFields(rectWidthFactor: 1.5),
            ) ==
            const LocalDocument(
              overlay: OverlayPlacementFields(rectWidthFactor: 1.5),
            ),
        isTrue,
      );
    });

    test('overlay 层未知键原样保留（陌生键保底不破）', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'overlay': {'dx': 1.0, 'dy': 2.0, 'overlayReserved': 'o'},
        },
      });
      expect(doc.toJson()['prefs']['overlay']['overlayReserved'], 'o');
    });

    test('wither 链全程携带浮层字段（任意链序不丢 per-video 浮层位）', () {
      const doc = LocalDocument(
        overlay: OverlayPlacementFields(
          dx: 1.0,
          dy: 2.0,
          landscapeCompareDx: 3.0,
          landscapeCompareDy: 4.0,
          rectWidthFactor: 1.5,
          pendulumScale: 0.8,
        ),
      );
      final chained = doc
          .withSnap(previewSnapEnabled: false)
          .withLayoutLocked(true);
      expect(chained.overlay, doc.overlay);
      expect(chained.layoutLocked, isTrue);
    });
  });

  group('数拍浮层 per-video 持久化（VideoSettingsPersistence）', () {
    test('变更即存：四格位置 + 共用系数写入 local 私密文件、不写 markers', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {
                OverlayPlacementCell.portraitNormal: Offset(32, 64),
                OverlayPlacementCell.landscapeNormal: Offset(11, 22),
                OverlayPlacementCell.portraitCompare: Offset(33, 44),
                OverlayPlacementCell.landscapeCompare: Offset(55, 66),
              },
              rectWidthFactor: 1.5,
              pendulumScale: 0.8,
            ),
          );
      await session.flush;

      final overlay = overlayOf(storages[idA]!);
      expect(overlay['dx'], 32.0);
      expect(overlay['dy'], 64.0);
      expect(overlay['landscapeDx'], 11.0);
      expect(overlay['landscapeDy'], 22.0);
      expect(overlay['compareDx'], 33.0);
      expect(overlay['compareDy'], 44.0);
      expect(overlay['landscapeCompareDx'], 55.0);
      expect(overlay['landscapeCompareDy'], 66.0);
      expect(overlay['rectWidthFactor'], 1.5);
      expect(overlay['pendulumScale'], 0.8);
      expect(storages[idA]!.markersSnapshot, isEmpty);
    });

    test('重开恢复：四格位置与共用系数各自回到会话态 provider', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {
              'overlay': {
                'dx': 40.0,
                'dy': 80.0,
                'landscapeDx': 1.0,
                'landscapeDy': 2.0,
                'compareDx': 3.0,
                'compareDy': 4.0,
                'landscapeCompareDx': 5.0,
                'landscapeCompareDy': 6.0,
                'rectWidthFactor': 1.25,
                'pendulumScale': 1.75,
              },
            },
          },
        },
      );
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(
        container.read(overlayPlacementProvider),
        const OverlayPlacements(
          offsets: {
            OverlayPlacementCell.portraitNormal: Offset(40, 80),
            OverlayPlacementCell.landscapeNormal: Offset(1, 2),
            OverlayPlacementCell.portraitCompare: Offset(3, 4),
            OverlayPlacementCell.landscapeCompare: Offset(5, 6),
          },
          rectWidthFactor: 1.25,
          pendulumScale: 1.75,
        ),
      );
    });

    test('旧文件迁移：只有 dx/dy 恢复成竖屏·普通已自定义、其余三格未自定义', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {
              'overlay': {'dx': 40.0, 'dy': 80.0},
            },
          },
        },
      );
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      final overlay = container.read(overlayPlacementProvider)!;
      expect(
        overlay.offsetFor(OverlayPlacementCell.portraitNormal),
        const Offset(40, 80),
      );
      for (final cell in const [
        OverlayPlacementCell.landscapeNormal,
        OverlayPlacementCell.portraitCompare,
        OverlayPlacementCell.landscapeCompare,
      ]) {
        expect(overlay.offsetFor(cell), isNull);
      }
      expect(overlay.rectWidthFactor, 1.0);
      expect(overlay.pendulumScale, 1.0);
    });

    test('未系数自定义位回落默认：只存位置、未设系数按系数 1 恢复', () async {
      container = makeContainer(
        localFiles: {
          idA: const {
            'version': 3,
            'prefs': {
              'overlay': {'dx': 40.0, 'dy': 80.0},
            },
          },
        },
      );
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      expect(
        container.read(overlayPlacementProvider),
        const OverlayPlacements(
          offsets: {OverlayPlacementCell.portraitNormal: Offset(40, 80)},
          rectWidthFactor: 1.0,
          pendulumScale: 1.0,
        ),
      );
    });

    test('未自定义：恢复不写入会话态（保持 null 默认位）', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;
      await session.flush;

      expect(container.read(overlayPlacementProvider), isNull);
      expect(storages[idA]!.localSnapshot, isEmpty);
    });

    test('落盘去抖：连续变更合并写盘，flush 收口不丢最后一次', () async {
      container = makeContainer();
      addTearDown(container.dispose);
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      // 第一轮：连续两次变更后 flush，只应落最终值。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {OverlayPlacementCell.portraitNormal: Offset(10, 10)},
            ),
          );
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {
                OverlayPlacementCell.portraitNormal: Offset(20, 20),
                OverlayPlacementCell.landscapeNormal: Offset(30, 30),
              },
              rectWidthFactor: 1.5,
            ),
          );
      await session.flush;
      var overlay = overlayOf(storages[idA]!);
      expect(overlay['dx'], 20.0);
      expect(overlay['landscapeDx'], 30.0);

      // 第二轮：去抖窗口未自然到期再次 flush，仍收口最新值。
      container
          .read(overlayPlacementProvider.notifier)
          .set(
            const OverlayPlacements(
              offsets: {
                OverlayPlacementCell.portraitNormal: Offset(30, 40),
                OverlayPlacementCell.landscapeCompare: Offset(50, 60),
              },
              rectWidthFactor: 1.5,
              pendulumScale: 2.0,
            ),
          );
      await session.flush;
      overlay = overlayOf(storages[idA]!);
      expect(overlay['dx'], 30.0);
      expect(overlay['dy'], 40.0);
      expect(overlay['pendulumScale'], 2.0);
      expect(overlay['rectWidthFactor'], 1.5);
      expect(overlay['landscapeCompareDx'], 50.0);
      expect(overlay['landscapeCompareDy'], 60.0);
    });
  });
}
