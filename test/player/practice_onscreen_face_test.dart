import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show
        practiceClipActivationProvider,
        practiceClipsProvider,
        practiceOnscreenFaceProvider;
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show SurfaceFace;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 练习半区在屏是哪一面（取值类型为画面方向库的
/// [SurfaceFace]）：页面、轨道带、标注编辑各消费方
/// 共读这一处派生。取值按**解析出的播放源（含引用有效性）**判定
/// 激活为空或激活片段解析不到（已不在轨道
/// 上）⇒ 相机实时预览；激活片段在轨 ⇒ 回放件在屏。
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(
          FakePlaybackEngine(duration: const Duration(minutes: 1)),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  PracticeClip clip({String id = 'clip_m1'}) => PracticeClip(
    id: id,
    materialId: 'm1',
    materialSourceStartMs: 0,
    inMs: 10000,
    outMs: 20000,
  );

  test('无激活：在屏那面是相机实时预览', () {
    expect(
      container.read(practiceOnscreenFaceProvider),
      SurfaceFace.cameraPreview,
    );
  });

  test('激活片段：在屏那面是片段回放', () {
    final target = clip();
    container.read(practiceClipsProvider.notifier).restore([target]);

    container.read(practiceClipActivationProvider.notifier).toggle(target);

    expect(
      container.read(practiceOnscreenFaceProvider),
      SurfaceFace.clipPlayback,
    );
  });

  test('再点同片段取消：在屏那面回到相机实时预览', () {
    final target = clip();
    container.read(practiceClipsProvider.notifier).restore([target]);
    final activation = container.read(practiceClipActivationProvider.notifier);

    activation.toggle(target);
    activation.toggle(target);

    expect(
      container.read(practiceOnscreenFaceProvider),
      SurfaceFace.cameraPreview,
    );
  });

  test('激活的片段已不在轨道上（解析不到播放源）：钉住回落实时预览', () {
    final target = clip();
    container.read(practiceClipsProvider.notifier).restore([target]);
    container.read(practiceClipActivationProvider.notifier).toggle(target);

    container.read(practiceClipsProvider.notifier).removeByMaterial('m1');

    expect(
      container.read(practiceOnscreenFaceProvider),
      SurfaceFace.cameraPreview,
      reason: '解析不到播放源即停播：练习半区回落实时预览',
    );
    expect(
      container.read(practiceClipActivationProvider),
      isNull,
      reason: '写后不变量：表里没有的片段不能还在回看',
    );
  });

  test('换视频复位清激活：在屏那面回到相机实时预览', () {
    final target = clip();
    container.read(practiceClipsProvider.notifier).restore([target]);
    container.read(practiceClipActivationProvider.notifier).toggle(target);

    container.read(practiceClipActivationProvider.notifier).reset();

    expect(
      container.read(practiceOnscreenFaceProvider),
      SurfaceFace.cameraPreview,
    );
  });
}
