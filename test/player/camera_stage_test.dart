import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/player/camera_stage.dart';
import 'package:dance_learning_app/player/compare_recording.dart'
    show ArmedSurfaceBaselinesModel, armedSurfaceBaselinesProvider;
import 'package:dance_learning_app/player/practice_mirror.dart'
    show effectivePracticeMirrorProvider;
import 'package:dance_learning_app/player/practice_surface.dart';
import 'package:dance_learning_app/player/recording_playback_takeover.dart';
import 'package:dance_learning_app/player/surface_basis_key.dart'
    show liveSurfaceBaselinesProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/practice_mirror_surface.dart';

/// 相机与练习面域直测：权限门与预览起停以显式
/// 依赖驱动（不注容器、不 pump 播放页）；练习面以值驱动的 provider 注入直接
/// pump 该模块（不经过播放页、不需要约十二个 provider 替换）。
void main() {
  const androidBaselines = SurfaceBaselines(
    platformPreviewBasis: FaceDirection.mirrored,
    platformSaveBasis: FaceDirection.original,
  );

  RecordingPlaybackTakeover takeover() => RecordingPlaybackTakeover(
    disableRecordingLoop: () {},
    restoreLearningSegmentLoop: () {},
    setRecordingMarker: (_) {},
    endScrubSession: () async {},
    interruptPendingDelayedPlay: () {},
    stopRecordingSession: () async {},
  );

  /// 会话侧构造的默认宿主事实：单测只覆盖自己那一项。
  CameraStage stageWith(
    FakeCameraCaptureService camera, {
    bool Function()? isCompare,
    bool Function()? isMounted,
    bool Function()? hasPendingEntry,
    RecordingResolution Function()? resolution,
    void Function()? onPreviewChanged,
    Future<bool> Function(CameraPermissionStatus status)? promptDenied,
  }) => CameraStage(
    camera: camera,
    isCompare: isCompare ?? () => false,
    isMounted: isMounted ?? () => true,
    hasPendingEntry: hasPendingEntry ?? () => true,
    resolution: resolution ?? () => RecordingResolution.fhd1080p,
    onPreviewChanged: onPreviewChanged ?? () {},
    promptDenied: promptDenied ?? (_) async => false,
  );

  group('相机授权门', () {
    test('已在对比态：直接放行、不询问', () async {
      final camera = FakeCameraCaptureService();
      final stage = stageWith(
        camera,
        isCompare: () => true,
        promptDenied: (_) async => fail('已在对比态不应弹提示'),
      );

      expect(await stage.requestEntryPermission(), isTrue);
      expect(camera.requestPermissionCount, 0);
    });

    test('授权：一次询问即成立，不弹提示', () async {
      final camera = FakeCameraCaptureService();
      final prompted = <CameraPermissionStatus>[];
      final stage = stageWith(
        camera,
        promptDenied: (status) async {
          prompted.add(status);
          return false;
        },
      );

      expect(await stage.requestEntryPermission(), isTrue);
      expect(camera.requestPermissionCount, 1);
      expect(prompted, isEmpty);
    });

    test('拒绝：弹可重试提示，重试即再问一次；永久拒绝后再问仍不成立', () async {
      final camera = FakeCameraCaptureService(
        permissionResult: CameraPermissionStatus.denied,
      );
      final prompted = <CameraPermissionStatus>[];
      var retries = 0;
      final stage = stageWith(
        camera,
        promptDenied: (status) async {
          prompted.add(status);
          // 第一次重试；第二次（永久拒绝）不再重试。
          return retries++ == 0;
        },
      );

      expect(await stage.requestEntryPermission(), isFalse);
      expect(camera.requestPermissionCount, 2);
      expect(prompted, [
        CameraPermissionStatus.denied,
        CameraPermissionStatus.permanentlyDenied,
      ]);
    });

    test('待办被取消：中止本次授权门且不弹提示', () async {
      final camera = FakeCameraCaptureService(
        permissionResult: CameraPermissionStatus.denied,
      );
      final prompted = <CameraPermissionStatus>[];
      final stage = stageWith(
        camera,
        hasPendingEntry: () => false,
        promptDenied: (status) async {
          prompted.add(status);
          return true;
        },
      );

      expect(await stage.requestEntryPermission(), isFalse);
      expect(camera.requestPermissionCount, 1);
      expect(prompted, isEmpty);
    });

    test('页面已卸载：不询问即中止', () async {
      final camera = FakeCameraCaptureService();
      final stage = stageWith(camera, isMounted: () => false);

      expect(await stage.requestEntryPermission(), isFalse);
      expect(camera.requestPermissionCount, 0);
    });
  });

  group('预览起停', () {
    test('未授权：静默不开流、不刷新画面区', () async {
      final camera = FakeCameraCaptureService();
      var previewChanged = 0;
      final stage = stageWith(
        camera,
        resolution: () => RecordingResolution.hd720p,
        onPreviewChanged: () => previewChanged++,
      );

      await stage.openPreview();
      expect(camera.startCount, 0);
      expect(previewChanged, 0);
    });

    test('已授权：按调用时刻的档开流、刷新一次', () async {
      final camera = FakeCameraCaptureService();
      await camera.requestPermission();
      var previewChanged = 0;
      final stage = stageWith(
        camera,
        resolution: () => RecordingResolution.hd720p,
        onPreviewChanged: () => previewChanged++,
      );

      await stage.openPreview();
      expect(camera.startCount, 1);
      expect(camera.openResolutions, [RecordingResolution.hd720p]);
      expect(previewChanged, 1);
    });

    test('开流失败：静默且不刷新画面区', () async {
      final camera = _StartFailsCamera();
      await camera.requestPermission();
      var previewChanged = 0;
      final stage = stageWith(camera, onPreviewChanged: () => previewChanged++);

      await stage.openPreview();
      expect(camera.startCount, 0);
      expect(previewChanged, 0);
    });

    test('关流：关一次', () async {
      final camera = FakeCameraCaptureService();
      await stageWith(camera).closePreview();
      expect(camera.stopCount, 1);
    });
  });

  group('练习面渲染', () {
    Future<void> pumpSurface(
      WidgetTester tester, {
      required RecordingPlaybackTakeover recorder,
      required SurfaceFace face,
      required bool practiceMirror,
      required SurfaceBaselines live,
      SurfaceBaselines? armed,
      Widget Function()? buildClipPicture,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            effectivePracticeMirrorProvider.overrideWithValue(practiceMirror),
            liveSurfaceBaselinesProvider.overrideWithValue(live),
            armedSurfaceBaselinesProvider.overrideWith(
              () => _ArmedBaselines(armed),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PracticeSurface(
                camera: FakeCameraCaptureService(),
                takeover: recorder,
                face: face,
                buildClipPicture:
                    buildClipPicture ?? () => const Text('clip-picture'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('相机预览在屏：显示层 = 画面方向库该面的施加缩放', (tester) async {
      await pumpSurface(
        tester,
        recorder: takeover(),
        face: SurfaceFace.cameraPreview,
        practiceMirror: true,
        live: practiceFaceBaselines(),
      );

      expect(find.byKey(const Key('fake_camera_preview')), findsOneWidget);
      final direction = checkedPracticePaneDirection(
        tester,
        const Key('fake_camera_preview'),
        face: SurfaceFace.cameraPreview,
        direction: practiceFaceDirection(practiceMirror: true),
      );
      // 本机平台预览基准 = 镜像、保存基准 = 原相：练习镜像开 ⇒ 用户可见方向
      // 为镜像（照镜子）。
      expect(direction, FaceDirection.mirrored);
    });

    testWidgets('拨练习镜像当场翻：显示层按模块取值当场切换、画面件不换结构位', (tester) async {
      await pumpSurface(
        tester,
        recorder: takeover(),
        face: SurfaceFace.cameraPreview,
        practiceMirror: true,
        live: practiceFaceBaselines(),
      );
      final opened = practicePaneScaleX(
        tester,
        const Key('fake_camera_preview'),
      );

      await pumpSurface(
        tester,
        recorder: takeover(),
        face: SurfaceFace.cameraPreview,
        practiceMirror: false,
        live: practiceFaceBaselines(),
      );
      final closed = practicePaneScaleX(
        tester,
        const Key('fake_camera_preview'),
      );

      expect(closed, isNot(opened), reason: '拨动练习镜像 ⇒ 在屏那路画面当场翻');
      expect(
        find.byKey(const Key('fake_camera_preview')),
        findsOneWidget,
        reason: '翻转只换包裹层，画面件本身仍在练习半区',
      );
    });

    testWidgets('录制期取冻结基线：显示层按冻结那份的方向求值', (tester) async {
      const frozen = SurfaceBaselines(
        platformPreviewBasis: FaceDirection.original,
        platformSaveBasis: FaceDirection.mirrored,
      );
      final active = takeover()..engage(suppressLoop: false);

      await pumpSurface(
        tester,
        recorder: active,
        face: SurfaceFace.cameraPreview,
        practiceMirror: true,
        live: androidBaselines,
        armed: frozen,
      );
      expect(
        practicePaneScaleX(tester, const Key('fake_camera_preview')),
        _expectedScaleX(
          face: SurfaceFace.cameraPreview,
          mirror: true,
          baselines: frozen,
        ),
        reason: '接管期（录制期）取会话冻结的基线项',
      );

      // 接管期而冻结值未落定（准备期未武装）：回落设备事实的当前取值。
      await pumpSurface(
        tester,
        recorder: takeover()..engage(suppressLoop: false),
        face: SurfaceFace.cameraPreview,
        practiceMirror: true,
        live: androidBaselines,
      );
      expect(
        practicePaneScaleX(tester, const Key('fake_camera_preview')),
        _expectedScaleX(
          face: SurfaceFace.cameraPreview,
          mirror: true,
          baselines: androidBaselines,
        ),
        reason: '接管期无冻结值 ⇒ 取设备事实的当前取值',
      );

      // 非录制期无冻结值：取设备事实的当前取值。
      await pumpSurface(
        tester,
        recorder: takeover(),
        face: SurfaceFace.cameraPreview,
        practiceMirror: true,
        live: androidBaselines,
      );
      expect(
        practicePaneScaleX(tester, const Key('fake_camera_preview')),
        _expectedScaleX(
          face: SurfaceFace.cameraPreview,
          mirror: true,
          baselines: androidBaselines,
        ),
        reason: '非录制期取设备事实的当前取值',
      );
    });

    testWidgets('片段回看在屏：渲染片段画面件而非相机预览件', (tester) async {
      await pumpSurface(
        tester,
        recorder: takeover(),
        face: SurfaceFace.clipPlayback,
        practiceMirror: false,
        live: practiceFaceBaselines(),
        buildClipPicture: () =>
            const ColoredBox(key: Key('clip_picture'), color: Colors.blue),
      );

      expect(find.byKey(const Key('practice_clip_playback')), findsOneWidget);
      expect(find.byKey(const Key('clip_picture')), findsOneWidget);
      expect(find.byKey(const Key('fake_camera_preview')), findsNothing);
    });
  });
}

/// 测试用期望值：画面方向库给出的该面施加缩放（独立于渲染落点的读数）。
double _expectedScaleX({
  required SurfaceFace face,
  required bool mirror,
  required SurfaceBaselines baselines,
}) => SurfaceDirection(
  moment: SurfaceMoment.practiceOnly(
    practiceMirror: mirror,
    baselines: baselines,
  ),
).surfaceScaleX(face);

class _ArmedBaselines extends ArmedSurfaceBaselinesModel {
  _ArmedBaselines(this._value);

  final SurfaceBaselines? _value;

  @override
  SurfaceBaselines? build() => _value;
}

/// 开流抛错（真实现的设备/编码异常是 `CameraException` 一族——`Exception`，
/// 域按「失败静默」收掉）。
class _StartFailsCamera extends FakeCameraCaptureService {
  @override
  Future<void> start({required RecordingResolution resolution}) async {
    throw const FormatException('设备异常');
  }
}
