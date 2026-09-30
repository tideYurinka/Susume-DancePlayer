/// 相机与练习面域：前置摄像头的权限门与预览
/// 起停的编排宿主。
///
/// 接口：
/// - [CameraStage.requestEntryPermission]：进入对比态前的相机授权门——按系统
///   流程询问权限，拒绝时经注入口给出的提示可重试，待办被取消或页面已卸载即
///   中止。提示本身是宿主 UI（对话框要构建上下文），本域只持那条循环。
/// - [CameraStage.openPreview] / [closePreview]：开前置摄像头预览与关流。
///   开流以**已授权**为前提（权限门之外的旁路路径静默不开未授权的流），按
///   调用时刻的录制分辨率档建实例，失败静默。
///
/// 练习面的画面与练习镜像取值归同域的 [PracticeSurface]（`practice_surface.dart`）：
/// 会话侧不收容器句柄、不读构建上下文，层侧自带 widget。
///
/// 依赖方向：**单向**——宿主（播放页）依赖本域，本域不 import 播放页、不
/// import 中枢。
library;

import '../camera_capture/camera_capture.dart';

/// 相机与练习面域的会话侧。
///
/// 全部依赖显式注入（读取闭包 + 回调 + 相机接缝），不收容器句柄；
/// 提示对话框由宿主注入（`promptDenied`），本类不碰构建上下文。
class CameraStage {
  CameraStage({
    required this._camera,
    required this._isCompare,
    required this._isMounted,
    required this._hasPendingEntry,
    required this._resolution,
    required this._onPreviewChanged,
    required this._promptDenied,
  });

  final CameraCaptureService _camera;

  /// 页面已处于对比态（在对比态内展开不重问权限）。
  final bool Function() _isCompare;

  /// 页面仍在树上（提示未决期间离页即中止）。
  final bool Function() _isMounted;

  /// 进入待办仍在槽（被取消即中止本次授权门）。
  final bool Function() _hasPendingEntry;

  /// 调用时刻的录制分辨率档（开流档：起录不接受档位）。
  final RecordingResolution Function() _resolution;

  /// 开流完成后刷新画面区（挂上预览件）。
  final void Function() _onPreviewChanged;

  /// 权限被拒提示：宿主 UI 给出「重试」是否被选择（永久拒绝的去系统设置路径
  /// 也在宿主的提示里处置）。
  final Future<bool> Function(CameraPermissionStatus status) _promptDenied;

  /// 进入对比态前的相机授权门：授权返回成立；拒绝弹可重试提示（重试即按系统
  /// 流程再问）；待办取消或页面卸载即中止。本方法不改模式值——由调用方按结果
  /// 取消或提交待办。
  Future<bool> requestEntryPermission() async {
    if (_isCompare()) return true;
    while (_isMounted()) {
      final status = await _camera.requestPermission();
      if (!_isMounted()) return false;
      if (status == CameraPermissionStatus.granted) return true;
      if (!_hasPendingEntry()) return false;
      final retry = await _promptDenied(status);
      if (!_isMounted() || retry != true) return false;
    }
    return false;
  }

  /// 开前置摄像头预览：以**已授权**为前提（旁路路径未授权时静默不开流，练习
  /// 侧留在占位件）；按当前录制分辨率档建预览控制器。开流完成后经
  /// [_onPreviewChanged] 刷新画面区；失败静默。
  Future<void> openPreview() async {
    if (_camera.permissionStatus != CameraPermissionStatus.granted) return;
    try {
      await _camera.start(resolution: _resolution());
    } on Exception {
      return;
    }
    _onPreviewChanged();
  }

  /// 关前置摄像头预览（离开对比态、退后台、进入片段回看）。
  Future<void> closePreview() => _camera.stop();
}
