/// 练习面（相机与练习面域）：练习侧画面子树的
/// 层域 widget。
///
/// [PracticeSurface] 自带练习侧镜像显示层与**在屏那一路画面件**（相机实时
/// 预览，或片段回看期间的片段回放件）：
/// - 显示层水平缩放读画面方向库该面的施加缩放（`F = R ⊕ D`），本件不硬写
///   翻转符号，方向口径只有库内那张表；
/// - 练习镜像是**活输入**（订阅生效值，录制中拨开关当场生效）；
/// - 基线项在录制期取会话冻结的那份（[armedSurfaceBaselinesProvider]），其余
///   时间取设备事实的当前取值——「录制期」这一事实取自
///   [RecordingPlaybackTakeover.active]，方向单向（接管域不依赖本件）。
///
/// 显示层**恒在树上**（不做显示层翻转时 `scaleX = 1`）：平台画面件不因开关或
/// 路径切换而换结构位。
///
/// 依赖方向（单向）：本件 → 画面方向库、相机接缝、接管域与练习镜像/基线
/// provider；零 import 中枢、不 import 播放页，接管域与
/// 相机接缝不依赖本件。反向不可。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera_capture/camera_capture.dart';
import '../surface_direction/surface_direction.dart';
import 'compare_recording.dart' show armedSurfaceBaselinesProvider;
import 'practice_mirror.dart' show effectivePracticeMirrorProvider;
import 'recording_playback_takeover.dart';
import 'surface_basis_key.dart' show liveSurfaceBaselinesProvider;
import 'surface_face_assembly.dart' show assemblePracticeFaceDirection;

/// 练习面：练习侧镜像显示层包住**在屏那一路画面**。
class PracticeSurface extends ConsumerWidget {
  const PracticeSurface({
    super.key,
    required this.camera,
    required this.takeover,
    required this.face,
    required this.buildClipPicture,
  });

  /// 实时预览件来源（相机接缝）。
  final CameraCaptureService camera;

  /// 录制期播放接管域：本件由它取得「录制期」这一事实——练习侧基线项在
  /// 录制期取会话冻结的那份，其余时间取设备事实的当前取值。
  final RecordingPlaybackTakeover takeover;

  /// 练习半区此刻在屏的那一路画面（相机预览 / 片段回放）。
  final SurfaceFace face;

  /// 片段回看在屏那一路的画面件（按需构建，避免页面构建时取到未就位的画面）。
  final Widget Function() buildClipPicture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveSurfaceBaselinesProvider);
    final frozen = ref.watch(armedSurfaceBaselinesProvider) ?? live;
    final direction = assemblePracticeFaceDirection(
      practiceMirror: ref.watch(effectivePracticeMirrorProvider),
      // 冻结基线只在接管期（录制期）被写入；`active` 一侧即该事实的唯一
      // 判据，未处接管期一律取设备事实的当前取值。
      baselines: takeover.active ? frozen : live,
    );
    return Transform(
      key: const Key('practice_mirrored_surface'),
      alignment: Alignment.center,
      transform: Matrix4.diagonal3Values(direction.surfaceScaleX(face), 1, 1),
      child: face == SurfaceFace.clipPlayback
          ? KeyedSubtree(
              key: const Key('practice_clip_playback'),
              child: buildClipPicture(),
            )
          : camera.buildPreview(),
    );
  }
}
