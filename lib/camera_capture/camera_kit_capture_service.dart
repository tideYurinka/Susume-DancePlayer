import 'dart:async';
import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../surface_direction/surface_direction.dart';
import 'camera_capture.dart';

/// [CameraCaptureService] 真实实现：`camera` 插件，仅前置
/// 摄像头。权限走系统流程——初始化失败即视为拒绝，连续两次失败视为
/// 永久拒绝（系统不再弹窗；插件不暴露 rationale 位）。
class CameraKitCaptureService implements CameraCaptureService {
  CameraController? _controller;
  bool _deniedBefore = false;

  /// 当前控制器**诞生时**的档位（[start] 传入；会话中途改档不改本实例）。
  /// 也是停录重开流与素材元数据（[RecordingOutput.resolution]）取档的单一
  /// 来源——一次录制不可能与它所在实例的档不一致。
  RecordingResolution _streamResolution = RecordingResolution.fhd1080p;

  /// 流是否已开（[start] 打开、[stop] 关闭；停录重开不动它，重开失败则回
  /// 落未开）。[start] 靠它做到幂等：**已经在流上再开流不换实例**，于是
  /// 「会话中途改档换掉了正在显示的实例」在结构上不可能。
  bool _streamOpen = false;

  /// controller 变更信号：创建/释放/替换时通知（代次自增触发），预览件
  /// 内部订阅重建。
  final ValueNotifier<int> _previewChanges = ValueNotifier<int>(0);

  @override
  Listenable get previewChanges => _previewChanges;

  /// 真实引擎不暴露 producer 标志：`camera` 插件的
  /// 平台接口上没有「预览是否被镜像」这一项——前置镜像只发生在插件内部的
  /// `RotatedPreviewDelegate` / `ImageReaderRotatedPreview` 分支里，而决定走哪
  /// 个分支的 `handlesCropAndRotation` 与 CameraX 的 mirror mode 都不在 Dart
  /// 侧可读。故此处恒为「读不到」，平台预览基准由机型规则推导。
  @override
  FaceDirection? get platformPreviewBasisFlag => null;

  @override
  CameraPermissionStatus get permissionStatus => _status;
  CameraPermissionStatus _status = CameraPermissionStatus.notDetermined;

  @override
  Future<CameraPermissionStatus> requestPermission() async {
    try {
      await _ensureController();
      _status = CameraPermissionStatus.granted;
    } on CameraException {
      // 授权成功后控制器常驻，重问不再走系统窗仍失败的场景由
      // [start] 前的授权前提排除；此处失败 = 系统窗被拒（或已永久拒）。
      _status = _deniedBefore
          ? CameraPermissionStatus.permanentlyDenied
          : CameraPermissionStatus.denied;
      _deniedBefore = true;
      await _disposeController();
    }
    return _status;
  }

  @override
  Future<void> start({required RecordingResolution resolution}) async {
    // 幂等：已经在流上就什么都不做（不换实例、不重读档）——「档位只在开流
    // 这一刻生效、会话中途改档不换实例」由此是结构，不靠调用点自律。
    if (_streamOpen) return;
    // 权限探测（[requestPermission]）会留下一个实例，而它诞生在任何档位被
    // 确定之前：档位不同就按 [resolution] 重生。此刻流尚未打开、预览件还没
    // 挂上（未进对比态），重生没有可见代价，也不是「打断正在显示的预览」。
    if (_controller != null && _streamResolution != resolution) {
      await _disposeController();
    }
    await _ensureController(preset: resolution);
    _streamOpen = true;
  }

  @override
  Future<void> stop() async {
    _streamOpen = false;
    await _disposeController();
  }

  @override
  Widget buildPreview() {
    // 预览件内部订阅 [previewChanges]：开流、停录重开、关流都会通知，此处
    // 即时重读 [_controller] 重建——界面无需（也不会）因 controller 换实例
    // 而重建，否则预览挂在已 dispose 的旧实例上、练习半区全程黑屏。起录
    // **不在**通知来源里（见 [CameraCaptureService.previewChanges]）。
    return ListenableBuilder(
      listenable: _previewChanges,
      builder: (context, _) {
        final controller = _controller;
        if (controller == null || !controller.value.isInitialized) {
          return _CameraPreviewPlaceholder();
        }
        // contain：半区约束是紧的（Expanded），须先由 Center 松开，再把宽高比
        // 交给 `CameraPreview` 自带的那张——它按当前设备方向取比值（竖屏取
        // 传感器比值的倒数），与本件外的 `RotatedBox` 同源；此处**不再叠一张
        // 自己的 `AspectRatio`**：`AspectRatio` 给子件的是紧约束，会把它那张
        // 压成空操作，于是竖屏下留出横屏形状的盒、画面被横向拉伸。
        // 整帧可见、不裁切不拉伸；`CameraPreview` 自带相机通路的前置自拍镜像
        // （即 [CameraCaptureService.platformPreviewBasisFlag] 那件设备事实）；
        // 应用侧那一次翻转在练习半区外层（按镜像开关）。
        return Center(child: CameraPreview(controller));
      },
    );
  }

  @override
  Future<void> openSystemSettings() =>
      AppSettings.openAppSettings(type: AppSettingsType.settings);

  @override
  bool get isRecording => _controller?.value.isRecordingVideo ?? false;

  @override
  Future<void> startRecording({
    required String outputPath,
    required RecordingOrientation orientation,
  }) async {
    // 起录**不销毁也不重建**控制器：
    // 预览件挂在控制器实例上，销毁即黑屏，重建失败就再没人重开流。插件
    // （CameraX）本来就允许预览与录像并发——起录只是在活着的预览上挂一个
    // 录像用例，预览流全程不断。
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw CameraException('cameraNotStarted', '预览未开流，不能起录');
    }
    // 起录瞬间的真实设备方向（补正）：预览控制器一直在跟踪传感器，
    // 且起录不再换实例，故此处读到的一直是活的真实方向——把方向压成「竖/
    // 横」二值会丢掉横屏左右与竖屏倒置，锁错一侧即预览与素材整体差 180°。
    final locked = controller.value.deviceOrientation;
    // 录制中旋转设备不跟转素材：锁定值取起录瞬间的真实方向。
    await controller.lockCaptureOrientation(locked);
    _pendingOutputPath = outputPath;
    _recordingOrientation = orientation;
    await controller.startVideoRecording();
    // 真实编码时长的**起边沿**：`startVideoRecording()` 直到系统
    // 报告录像已开始才返回，之前那段是起录前的等待（插件层的会话重配），
    // 编码器还没在写——把它算进素材时长就是系统性多报。故秒表在调用**返回
    // 之后**才起跑。
    _recordingStopwatch
      ..reset()
      ..start();
  }

  @override
  Future<RecordingOutput?> stopRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isRecordingVideo) return null;
    // 真实编码时长的**止边沿**：停录请求到真正停下之间是停录的
    // 收尾，同样不算素材内容，故秒表在调用**之前**就停。
    _recordingStopwatch.stop();
    final recorded = await controller.stopVideoRecording();
    final outputPath = _pendingOutputPath;
    _pendingOutputPath = null;
    await _disposeController();
    // 停录后恢复实时预览（仅
    // 片段激活回看期间才停摄像头，见）——先重开流（经
    // [_previewChanges] 通知预览件重建、尽量缩短占位间隙），再做文件
    // 收尾。重开按**本会话的档**（会话中途改档不改本实例）。重开失败不
    // 阻断停录产出（素材已落盘），但流要落回未开——否则后续开流边沿的
    // [start] 会因幂等守卫直接返回，预览件就此永远停在占位件。
    try {
      await _ensureController(preset: _streamResolution);
    } on Object {
      _streamOpen = false;
    }
    // 插件产出到临时路径：挪到调用方给定的素材目录路径（同分区改名）。
    if (recorded.path != outputPath) {
      await File(recorded.path).rename(outputPath ?? recorded.path);
    }
    return RecordingOutput(
      filePath: outputPath ?? recorded.path,
      duration: _recordingStopwatch.elapsed,
      orientation: _recordingOrientation,
      // 素材档 = 本实例的档（起录不接受档位，见 [startRecording]）。
      resolution: _streamResolution,
    );
  }

  final Stopwatch _recordingStopwatch = Stopwatch();
  RecordingOrientation _recordingOrientation = RecordingOrientation.landscape;
  String? _pendingOutputPath;

  /// 确保有活实例：没有就按 [preset] 建一个（档位随之记为 [_streamResolution]）。
  /// **本方法只建不销毁**——已有实例时是 no-op，因此它不可能打断正在显示的
  /// 预览；换实例只发生在两处显式边沿：[start]（重生探测实例，此时流未开）
  /// 与关流（[stop] / [stopRecording] 的重开）。
  Future<void> _ensureController({
    RecordingResolution preset = RecordingResolution.fhd1080p,
  }) async {
    if (_controller != null) return;
    final cameras = await availableCameras();
    // 仅前置摄像头：无前置相机不静默退回其它镜头。
    final fronts = cameras.where(
      (c) => c.lensDirection == CameraLensDirection.front,
    );
    if (fronts.isEmpty) {
      throw CameraException('cameraNotFound', '无可用前置相机');
    }
    // 纯画面无声：enableAudio = false，不录环境音。
    final controller = CameraController(
      fronts.first,
      _presetOf(preset),
      enableAudio: false,
    );
    await controller.initialize();
    _streamResolution = preset;
    _controller = controller;
    _previewChanges.value++;
  }

  static ResolutionPreset _presetOf(RecordingResolution resolution) =>
      switch (resolution) {
        // camera 插件档位映射：high = 720p、veryHigh = 1080p。
        RecordingResolution.hd720p => ResolutionPreset.high,
        RecordingResolution.fhd1080p => ResolutionPreset.veryHigh,
      };

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    await controller?.dispose();
    _previewChanges.value++;
  }
}

/// 未开流时的占位件（练习半区底色）。
class _CameraPreviewPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      key: Key('camera_preview_placeholder'),
      color: Color(0xFF101010),
    );
  }
}
