import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../surface_direction/surface_direction.dart';
import 'camera_kit_capture_service.dart';

/// 相机采集服务：练习侧前置摄像头
/// 实时预览的唯一接缝——开/关前置摄像头、权限状态与询问、预览件、
/// 永久拒绝后去系统设置；录制（起录/停录/素材落盘/方向锁定元数据）为
///  的同缝扩展。
///
/// 权限走系统流程（系统弹窗），不引额外权限框架；真实实现 = `camera`
/// 插件（仅前置摄像头），测试注入 fake（`test/helpers/
/// fake_camera_capture_service.dart`，注入手法沿 `fake_system_ui.dart`）。
abstract interface class CameraCaptureService {
  /// 当前权限状态（[requestPermission] 后更新）。
  CameraPermissionStatus get permissionStatus;

  /// 按系统流程询问相机权限：首次弹系统窗；授权返回 granted、拒绝返回
  /// denied（可重试）、再次失败（系统不再弹窗）返回 permanentlyDenied。
  Future<CameraPermissionStatus> requestPermission();

  /// 开前置摄像头（进入对比态调用；授权前提由宿主编排保证）。按
  /// [resolution]（当前录制分辨率档）建预览控制器——**预览与录制共用同一个
  /// 控制器实例**是硬结构要求：档位只在**开流这一刻**生效，
  /// 会话中途改档不换实例、下次开流（下次进入对比态）才生效。
  Future<void> start({required RecordingResolution resolution});

  /// 关前置摄像头（离开对比态、退后台调用）。
  Future<void> stop();

  /// 预览变更信号：controller 被创建/释放/替换（进入对比态开流、停录重开、
  /// 关流）时通知——起录**不在此列**（起录只在同一个实例上挂录像用例）。
  /// [buildPreview] 返回的预览件内部订阅它自行重建——widget 层不感知
  /// controller 状态（薄接缝约束）。
  Listenable get previewChanges;

  /// 相机引擎的 producer 标志：**平台预览基准**
  /// 这件设备事实——实时预览件相对录像文件是否已被平台镜像；非 null 即引擎
  /// 直接给出的取值（读得到就直接读）。引擎不暴露该标志时返回 null。
  ///
  /// 读不到 ⇒ 由平台事实 adapter（`platform_preview_basis.dart`）按机型规则
  /// 推导（该文件记着 Android 一行取值「镜像」的通路与同帧读数依据）。今天的
  /// 真实引擎读不到：`camera` 插件不把前置预览的镜像状态放在平台接口上（其
  /// 前置镜像做在 `RotatedPreviewDelegate` 的 `ImageReaderRotatedPreview` 分支
  /// 里，判据 `handlesCropAndRotation` 是引擎/插件的内部状态，不在插件的 Dart
  /// 接口上），故真实实现恒返 null。
  FaceDirection? get platformPreviewBasisFlag;

  /// 实时预览件：练习半区内 contain（整帧可见）、方向跟随设备方向。
  ///
  /// 本件含相机通路自己的前置自拍镜像——那是本面的**自身原始朝向**（画面
  /// 方向库的 R，取 [platformPreviewBasisFlag] 那件设备事实）；练习半区外层的
  /// 显示层按镜像开关统一翻转是应用侧那一次（换算见 `player_page.dart` 的
  /// `_practiceSurfaceScaleX`），两者合成才是用户看到的方向。未开流时给占位件。
  /// 件内部订阅 [previewChanges]，controller 换实例后自动重建（否则界面挂在已
  /// dispose 的旧实例上、练习半区全程黑屏）。
  Widget buildPreview();

  /// 跳系统设置页（永久拒绝后的授权路径）。
  Future<void> openSystemSettings();

  bool get isRecording;

  /// 起录：输出到 [params.outputPath]（调用方保证落在私有素材
  /// 目录）、按**开流档**出图（见 [start]——起录不接受档位，会话中途改的档
  /// 不会由起录路径漏进素材）、纯画面无声（不录环境音）；按
  /// [params.orientation] 在**起录瞬间**锁定画面方向（录制中旋转不跟转）。
  /// 起录只在**已在流上的同一个控制器实例**上挂录像用例，预览流全程不断；
  /// 失败（设备异常/编码不可用/未开流）抛错，调用方按起录失败收尾。
  Future<void> startRecording({
    required String outputPath,
    required RecordingOrientation orientation,
  });

  /// 停录：产出素材文件与方向锁定元数据；未在录时返回 null。
  /// 停录后回到实时预览（重开流并经 [previewChanges] 通知）——仅片段
  /// 激活回看期间才停摄像头。
  Future<RecordingOutput?> stopRecording();
}

/// 录制分辨率档：默认 1080p/30fps，设备级设置可切 720p。
enum RecordingResolution { hd720p, fhd1080p }

/// 起录瞬间的画面方向（锁定元数据；录制中旋转不跟转）。
enum RecordingOrientation { portrait, landscape }

/// 一次录制的请求/生效参数快照。
class RecordingStartParams {
  const RecordingStartParams({
    required this.outputPath,
    required this.resolution,
    required this.orientation,
  });

  /// 素材输出文件路径（私有素材目录内）。
  final String outputPath;

  /// **本次录制生效的**分辨率档 = 开流档（起录不再接受档位，见
  /// [CameraCaptureService.start]）。
  final RecordingResolution resolution;

  final RecordingOrientation orientation;
}

/// 一次录制的产出：素材文件 + 方向锁定元数据 + 分辨率档。
class RecordingOutput {
  const RecordingOutput({
    required this.filePath,
    required this.duration,
    required this.orientation,
    required this.resolution,
  });

  /// 素材文件路径（真实存在于私有素材目录）。
  final String filePath;

  final Duration duration;

  /// 起录瞬间锁定的方向（元数据经本 seam 输出）。
  final RecordingOrientation orientation;

  final RecordingResolution resolution;
}

/// 相机权限状态：未询问 / 已授权 / 拒绝（可重试）/ 永久拒绝（去设置）。
enum CameraPermissionStatus {
  notDetermined,
  granted,
  denied,
  permanentlyDenied,
}

/// 相机采集注入点：真实实现走 `camera` 插件；测试 override 注入 fake。
final cameraCaptureProvider = Provider<CameraCaptureService>(
  (ref) => CameraKitCaptureService(),
);
