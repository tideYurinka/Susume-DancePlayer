import 'dart:io';

import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';

/// 记录调用的假相机采集服务：权限结果可脚本化，
/// 开/关计数断言生命周期；预览件为固定 Key 的占位盒。
///
/// 录制：起录/停录参数全量记录；停录产出脚本化时长与起录方向的
/// [RecordingOutput]，并在输出路径落一个假素材文件（同步写，模拟编码产物
/// 真实存在）；起录失败路径经 [startRecordingFails] 脚本化。
///
/// 起录连贯：**起录不换 controller 实例**（真实现只在活着的预览上
/// 挂录像用例），换实例只发生在开流与停录重开；[start] 与真实现一样幂等。
/// 失败路径的形状 = 「编码未开始」：不记录起录参数、不落产物、实例不动。
class FakeCameraCaptureService implements CameraCaptureService {
  FakeCameraCaptureService({this.permissionResult = CameraPermissionStatus.granted});

  /// [requestPermission] 的脚本化结果；每次询问后自动收严为
  /// permanentlyDenied（模拟「再次询问系统不再弹窗」），可手动改写。
  CameraPermissionStatus permissionResult;

  /// 预览变更信号（与真实实现对齐）：controller 开流/换实例/重开/关流时
  /// 通知。[buildPreview] 内部订阅它重建。
  final ChangeNotifier _previewChanges = ChangeNotifier();

  @override
  Listenable get previewChanges => _previewChanges;

  /// 相机引擎的 producer 标志：脚本化「读得到」的
  /// 那一态；null（默认）与真实引擎一致 = 读不到 ⇒ 平台预览基准走机型规则。
  FaceDirection? scriptedProducerFlag;

  @override
  FaceDirection? get platformPreviewBasisFlag => scriptedProducerFlag;

  /// 当前预览 controller 实例序号（0 = 未开流）：**开流**与**停录重开**各
  /// 递增一次，模拟真实实现换 CameraController 实例的可见效应。起录**不
  /// 递增**——起录只在同一实例上挂录像用例。
  int previewInstance = 0;
  int _instanceSeq = 0;

  /// 推进预览 controller 代次并通知（开流/停录重开共用）。
  int _advancePreviewGeneration() {
    previewInstance = ++_instanceSeq;
    _previewChanges.notifyListeners();
    return previewInstance;
  }

  /// 历次开流带的录制分辨率档（进入对比态开流时按档创建；档位只在开流时
  /// 生效——会话中途改档不换实例、下次开流才带上新档）。
  final List<RecordingResolution> openResolutions = [];

  /// 当前流诞生时的档位（起录档 = 本值：起录不再接受档位）。
  RecordingResolution streamResolution = RecordingResolution.fhd1080p;

  int requestPermissionCount = 0;
  int startCount = 0;
  int stopCount = 0;
  int openSettingsCount = 0;

  /// 开流是否成功（false 模拟异常设备）。
  bool startSucceeds = true;

  /// 起录请求记录（按序）。
  final List<RecordingStartParams> startRecordingCalls = [];

  int stopRecordingCount = 0;

  /// 起录是否失败（true 模拟设备异常，[startRecording] 抛错）。
  bool startRecordingFails = false;

  /// 起录耗时：真实现的 `startVideoRecording()` **直到系统报告
  /// 录像已开始才返回**（其间有一次 capture session 重配）——这段时间里
  /// 编码器还没在写。默认 0 = 微任务里瞬间完成，**会把起录演成理想时序**
  /// （缺陷赖以存在的时间形状一次都进不了断言）；涉起录时机的用例必须显式
  /// 设成非零。
  Duration startRecordingLatency = Duration.zero;

  /// 停录耗时（同上：停录收尾也不在微任务里瞬间完成）。
  Duration stopRecordingLatency = Duration.zero;

  /// 停录脚本的素材时长（模拟编码产物时长）。
  Duration scriptedRecordingDuration = const Duration(seconds: 10);

  /// 停录是否返回 null（未在录时停录的兜底路径）。
  bool stopRecordingReturnsNull = false;

  @override
  CameraPermissionStatus get permissionStatus => _status;
  CameraPermissionStatus _status = CameraPermissionStatus.notDetermined;

  @override
  Future<CameraPermissionStatus> requestPermission() async {
    requestPermissionCount++;
    _status = permissionResult;
    permissionResult = CameraPermissionStatus.permanentlyDenied;
    return _status;
  }

  @override
  Future<void> start({required RecordingResolution resolution}) async {
    if (!startSucceeds) {
      throw StateError('fake camera start failed');
    }
    // 真实现：[start] 幂等——已在流上再开流不换实例、不改档。
    if (previewInstance != 0) return;
    startCount++;
    openResolutions.add(resolution);
    streamResolution = resolution;
    _advancePreviewGeneration();
  }

  @override
  Future<void> stop() async {
    stopCount++;
    // 关流：预览回到未开流（占位语义）。
    previewInstance = 0;
    _previewChanges.notifyListeners();
  }

  @override
  Widget buildPreview() => ListenableBuilder(
    listenable: _previewChanges,
    builder: (context, _) => ColoredBox(
      key: const Key('fake_camera_preview'),
      color: const Color(0xFF202020),
      // 实例标识件：随 controller 实例变更（可见行为断言点）。
      child: SizedBox.expand(
        key: previewInstance == 0
            ? const Key('fake_camera_preview_placeholder')
            : Key('fake_camera_preview_instance_$previewInstance'),
      ),
    ),
  );

  @override
  Future<void> openSystemSettings() async => openSettingsCount++;

  @override
  bool get isRecording => startRecordingCalls.length > stopRecordingCount;

  @override
  Future<void> startRecording({
    required String outputPath,
    required RecordingOrientation orientation,
  }) async {
    if (startRecordingFails) {
      throw StateError('fake camera startRecording failed');
    }
    // 重配延迟走完编码器才在写——起录参数在延迟**之后**才记账，
    // 于是「武装了但编码器还没在写」这段窗口在替身里真实存在。
    if (startRecordingLatency > Duration.zero) {
      await Future<void>.delayed(startRecordingLatency);
    }
    startRecordingCalls.add(
      RecordingStartParams(
        outputPath: outputPath,
        // 起录不接受档位：素材档 = 本实例（开流）的档。
        resolution: streamResolution,
        orientation: orientation,
      ),
    );
    // 起录**不换实例**：真实现只在活着的预览上挂录像用例。此处刻意
    // 什么都不做——留一段「起录同步换实例并通知」就是用替身复现缺陷，会让
    // 实例号断言假绿。
    // 模拟编码产物真实存在（素材入库读文件字节数的依据）。
    File(outputPath).writeAsStringSync('FAKE_MP4');
  }

  @override
  Future<RecordingOutput?> stopRecording() async {
    stopRecordingCount++;
    if (startRecordingCalls.isEmpty) return null;
    if (stopRecordingReturnsNull) return null;
    if (stopRecordingLatency > Duration.zero) {
      await Future<void>.delayed(stopRecordingLatency);
    }
    final params = startRecordingCalls.last;
    // 真实实现停录后恢复实时预览（重开流）：换实例并通知。
    _advancePreviewGeneration();
    return RecordingOutput(
      filePath: params.outputPath,
      duration: scriptedRecordingDuration,
      orientation: params.orientation,
      resolution: params.resolution,
    );
  }
}
