/// 平台画面基准的装配：把纯值的规则表 / adapter
/// （`platform_preview_basis.dart`）接到运行平台这件系统事实与相机引擎的
/// producer 标志上。系统事实与注入点住这里，规则本身不住这里。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'camera_capture.dart';
import 'platform_preview_basis.dart';

/// 相机通路平台的读法（装配点读一次系统事实）：Android 是本 App 今天的相机
/// 通路（`camera` 插件 / CameraX，前置）；其余平台没有相机通路，机型规则表里
/// 没有对应行 ⇒ 判定落到显式兜底。测试注入点（部件用例按 Android 真机行为
/// 布景，不读测试宿主的平台）。
final cameraPlatformProvider = Provider<CameraPlatform>(
  (ref) => Platform.isAndroid ? CameraPlatform.android : CameraPlatform.other,
);

/// 平台事实 adapter 的装配：producer 标志读相机引擎（[cameraCaptureProvider]），
/// 通路平台读 [cameraPlatformProvider]。装配点只读本 provider 的判定结果，
/// 不再持有任何机型校准常量。
final platformPreviewBasisAdapterProvider =
    Provider<PlatformPreviewBasisAdapter>(
      (ref) => PlatformPreviewBasisAdapter(
        platform: ref.watch(cameraPlatformProvider),
        readProducerFlag: () =>
            ref.read(cameraCaptureProvider).platformPreviewBasisFlag,
      ),
    );
