import 'package:dance_learning_app/camera_capture/platform_preview_basis_providers.dart'
    show cameraPlatformProvider;
import 'package:dance_learning_app/camera_capture/platform_preview_basis.dart'
    show CameraPlatform;
import 'package:flutter_riverpod/misc.dart' show Override;

/// 相机通路平台按 Android 注入：受审行为是 Android
/// 真机行为，而部件用例的宿主不是 Android（读宿主平台事实会落到机型规则表之
/// 外）。凡进入对比练习、练习半区画面会出场的布景都在 `overrides` 里带上它。
Override androidCameraPlatform() =>
    cameraPlatformProvider.overrideWithValue(CameraPlatform.android);
