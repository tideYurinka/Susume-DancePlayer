import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart'
    show CameraPlatform, platformPreviewBasisFallback;
import 'package:dance_learning_app/camera_capture/platform_preview_basis_providers.dart'
    show cameraPlatformProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/practice_mirror.dart';
import 'package:dance_learning_app/player/settings_persistence.dart';
import 'package:dance_learning_app/player/speed_history_store.dart'
    show speedHistoryAutoRestoreProvider;
import 'package:dance_learning_app/player/surface_basis_key.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 基准键的设备级持久化：设备事实落在设备级私密
/// 文件 `global_private.json` 的顶层布尔键（与既有设备级镜像默认键
/// `practiceMirrorDefault` 同文件同形状），供画面方向表读取。
///
/// 读、写、缺失、损坏四条路径都在这里钉住；键读不到（缺失/损坏）时**判定一次
/// 并记住**（producer 标志 → 机型规则 → 判不出兜底为**镜像**），判定结果落进
/// 本键、下次启动直接读回，且全程不阻塞启动。该键**不可随舞覆盖**——随舞覆盖
/// 只作用于练习镜像（`practice_mirror.dart`），本键住设备级文件，与任何一支舞的
/// local 私密文件无关。
///
/// 「键值变化 ⇒ 画面方向表按新键落定」的直测在
/// `surface_basis_key_direction_test.dart`。
void main() {
  const pathA = '/videos/a.mp4';
  const idA = 'vid-a';

  late FakeCameraCaptureService camera;
  late InMemoryPrivateJsonStorage privateJson;
  late InMemoryVideoDocumentStorage localDoc;
  late ProviderContainer container;

  /// 设备等效布景：producer 标志默认读不到（与真实相机引擎同态），通路平台取
  /// 机型规则表之外的一档——于是「平台事实判得出来」这件事被排除，任何非兜底
  /// 取值都只能来自设备级基准键。
  ProviderContainer makeContainer({
    Map<String, dynamic> privateInitial = const {},
    Map<String, Map<String, dynamic>> localFiles = const {},
    CameraPlatform platform = CameraPlatform.other,
    FaceDirection? producerFlag,
  }) {
    camera = FakeCameraCaptureService()..scriptedProducerFlag = producerFlag;
    privateJson = InMemoryPrivateJsonStorage(initial: privateInitial);
    final index = InMemoryVideoIndexStorage(
      initial: VideoIndex(
        entries: [historyEntry(filePath: pathA, mirrored: false, videoId: idA)],
      ),
    );
    localDoc = InMemoryVideoDocumentStorage(local: localFiles[idA] ?? const {});
    return ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
        speedHistoryAutoRestoreProvider.overrideWithValue(false),
        privateJsonStorageProvider.overrideWithValue(privateJson),
        cameraCaptureProvider.overrideWithValue(camera),
        cameraPlatformProvider.overrideWithValue(platform),
        videoIndexStoreProvider.overrideWithValue(index),
        videoDocumentStorageProvider(idA).overrideWithValue(localDoc),
      ],
    );
  }

  Future<FaceDirection?> restored() async {
    await container.read(surfaceBasisKeyProvider.notifier).restoreDone;
    return container.read(surfaceBasisKeyProvider);
  }

  group('持久化四路径：读 / 写 / 缺失 / 损坏', () {
    test('读：设备级文件里的键回到会话，并落进画面方向基线项', () async {
      container = makeContainer(privateInitial: {'surfaceBasisKey': false});
      addTearDown(container.dispose);

      expect(
        await restored(),
        FaceDirection.original,
        reason: '顶层布尔键 false = 原相',
      );
      expect(
        container.read(liveSurfaceBaselinesProvider).basisKey,
        FaceDirection.original,
        reason: '读到的键落进基线项（若读不到，本布景会兜底为镜像）',
      );
    });

    test('读：true = 镜像', () async {
      container = makeContainer(privateInitial: {'surfaceBasisKey': true});
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.mirrored);
      expect(
        container.read(liveSurfaceBaselinesProvider).basisKey,
        FaceDirection.mirrored,
      );
    });

    test('写：按键落成同文件同形状的顶层布尔键，同文件其它键保留', () async {
      container = makeContainer(
        privateInitial: {'practiceMirrorDefault': false},
      );
      addTearDown(container.dispose);
      await restored();

      await container
          .read(surfaceBasisKeyProvider.notifier)
          .set(FaceDirection.mirrored);

      expect(container.read(surfaceBasisKeyProvider), FaceDirection.mirrored);
      expect(privateJson.snapshot, {
        'practiceMirrorDefault': false,
        'surfaceBasisKey': true,
      }, reason: '并列扩键：与设备级镜像默认键同文件同形状，不改动同文件其它键');
    });

    test('写：清除（null = 恢复默认）后键从文件里退场，取值回到兜底', () async {
      container = makeContainer(privateInitial: {'surfaceBasisKey': false});
      addTearDown(container.dispose);
      await restored();

      await container.read(surfaceBasisKeyProvider.notifier).set(null);

      expect(container.read(surfaceBasisKeyProvider), isNull);
      expect(privateJson.snapshot, isEmpty);
      expect(
        container.read(liveSurfaceBaselinesProvider).platformPreviewBasis,
        platformPreviewBasisFallback,
        reason: '键退场 ⇒ 判定不出 ⇒ 兜底为镜像',
      );
    });

    test('缺失：无键文件不阻塞启动，判定一次并记住（判不出 ⇒ 兜底镜像）', () async {
      container = makeContainer();
      addTearDown(container.dispose);

      expect(
        await restored(),
        FaceDirection.mirrored,
        reason: '读不到键 ⇒ 判定：producer 标志读不到、机型规则无此平台 ⇒ 兜底镜像',
      );
      expect(privateJson.snapshot, {
        'surfaceBasisKey': true,
      }, reason: '判定结果落进设备级键（「自动判定一次并记住」）');
      final baselines = container.read(liveSurfaceBaselinesProvider);
      expect(baselines.platformPreviewBasis, platformPreviewBasisFallback);
      expect(baselines.basisKey, FaceDirection.mirrored);
      expect(
        baselines.materialDirection,
        FaceDirection.original,
        reason: '素材方向 = 平台保存基准（键只进相机预览行）',
      );
    });

    test('缺失：判定直接读到的平台事实时记住的是读到的取值', () async {
      container = makeContainer(producerFlag: FaceDirection.original);
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.original);
      expect(privateJson.snapshot, {
        'surfaceBasisKey': false,
      }, reason: '读到的 producer 标志 = 原相 ⇒ 记住原相（顶层布尔键 false）');
    });

    test('缺失：判定到机型规则推导时记住推导值（Android ⇒ 镜像）', () async {
      container = makeContainer(platform: CameraPlatform.android);
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.mirrored);
      expect(privateJson.snapshot, {'surfaceBasisKey': true});
    });

    test('缺失：判定结果跨会话保留（重启等价：重建容器直接读回该键）', () async {
      container = makeContainer();
      expect(await restored(), FaceDirection.mirrored);
      final persisted = privateJson.snapshot;
      final first = container;
      container = makeContainer(privateInitial: persisted);
      first.dispose();
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.mirrored, reason: '第二次启动直接读回判定结果');
      expect(privateJson.snapshot, persisted, reason: '键已落定 ⇒ 不再走判定链、不重写');
    });

    test('读：键读得到就不改写文件（判定链不参与）', () async {
      container = makeContainer(
        platform: CameraPlatform.android,
        privateInitial: {'surfaceBasisKey': false},
      );
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.original);
      expect(privateJson.snapshot, {
        'surfaceBasisKey': false,
      }, reason: '键读得到 ⇒ 直接用它，不重写、也不被 Android 规则（镜像）覆盖');
    });

    test('损坏：键值类型损坏 ⇒ 当作读不到，判定一次并就地修复为合法键', () async {
      container = makeContainer(
        privateInitial: {'surfaceBasisKey': 'mirrored'},
      );
      addTearDown(container.dispose);

      expect(await restored(), FaceDirection.mirrored);
      expect(privateJson.snapshot, {
        'surfaceBasisKey': true,
      }, reason: '损坏值被判定结果就地替换为合法布尔键');
      expect(
        container.read(liveSurfaceBaselinesProvider).basisKey,
        FaceDirection.mirrored,
      );
    });

    test('损坏：存储读取抛错也不阻塞启动，会话态维持尚未落定', () async {
      camera = FakeCameraCaptureService();
      privateJson = InMemoryPrivateJsonStorage();
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          speedHistoryAutoRestoreProvider.overrideWithValue(false),
          privateJsonStorageProvider.overrideWithValue(
            _ThrowingPrivateJsonStorage(),
          ),
          cameraCaptureProvider.overrideWithValue(camera),
          cameraPlatformProvider.overrideWithValue(CameraPlatform.other),
        ],
      );
      addTearDown(container.dispose);

      expect(await restored(), isNull);
      expect(
        container.read(liveSurfaceBaselinesProvider).basisKey,
        FaceDirection.mirrored,
      );
    });
  });

  group('该键不可随舞覆盖：随舞覆盖只作用于练习镜像', () {
    test('随舞覆盖落进 local prefs 的 practiceMirror，不落基准键、也不动设备级键', () async {
      container = makeContainer(
        privateInitial: {
          'surfaceBasisKey': false,
          'practiceMirrorDefault': true,
        },
      );
      addTearDown(container.dispose);
      await restored();
      final session = VideoSettingsPersistence(container);
      unawaited(session.startForVideo(idA));
      await session.started;

      container.read(practiceMirrorOverrideProvider.notifier).set(false);
      await session.flush;

      expect(
        container.read(effectivePracticeMirrorProvider),
        false,
        reason: '随舞覆盖只作用于练习镜像',
      );
      expect(
        container.read(liveSurfaceBaselinesProvider).basisKey,
        FaceDirection.original,
        reason: '设备级基准键不随该支舞的覆盖改变',
      );
      expect(privateJson.snapshot, {
        'surfaceBasisKey': false,
        'practiceMirrorDefault': true,
      }, reason: '随舞写入落在 local 私密文件，设备级文件原样');
      final prefs = localDoc.localSnapshot['prefs'] as Map<String, dynamic>;
      expect(
        prefs['practiceMirror'],
        false,
        reason: '随舞覆盖落在 local prefs 的 practiceMirror',
      );
      expect(
        prefs.containsKey('surfaceBasisKey'),
        isFalse,
        reason: 'local prefs 段没有基准键的位置——设备级键不可随舞覆盖',
      );
    });
  });
}

/// 读取即抛错的存储（模拟磁盘/权限故障）：键读不到，但不阻塞启动。
class _ThrowingPrivateJsonStorage implements PrivateJsonStorage {
  @override
  Future<Map<String, dynamic>> read() => throw const FileSystemException();

  @override
  Future<void> write(Map<String, dynamic> json) async {}

  @override
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  ) async {}
}
