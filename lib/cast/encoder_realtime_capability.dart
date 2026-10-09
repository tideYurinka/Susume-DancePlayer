/// **编码器 1× 实时能力查询**接缝：渲染前问系统一句「这台机器的编码器保证
/// 覆盖得了这次要渲的尺寸吗」（尺寸由 Dart 侧给），答案决定这次按保证档（画面
/// 上限收在问的那一档上）还是降到 720p 渲。
///
/// ## 为什么这是一条接缝
///
/// 答案只能从**系统**拿到（`MediaCodecInfo` 的性能点，见
/// `platform_encoder_realtime_capability.dart` 与 Android 侧的
/// `EncoderRealtimeCapabilityPlugin`），而**渲染决策**（三态 → 分辨率档）必须
/// 能在宿主测试里穷尽——所以两者分开：接缝只负责照**调用方给的目标尺寸**
/// （[CastEncoderQueryTarget]）问，问出来的三态是纯件
/// （`cast_encoder_realtime.dart`）的输入。宽、高、帧率因此由 Dart 侧给出，
/// 原生只照它问性能点（不在原生里硬编 1080p30）。
///
/// 接口 + 真实实现 + Provider 注入，手法沿仓内既有的平台 seam（系统镜像跳转
/// / 系统媒体音量 / 相机采集）：真实实现走手写 MethodChannel，测试注入脚本化
/// 替身（`test/helpers/fake_encoder_realtime_capability.dart`）。真机行为留
/// 真机验收。
///
/// ## 查询失败一律是「问不到」，不是「保证」
///
/// [CastEncoderRealtimeCapability.query] **不抛**：API < 29（性能点是 Android
/// 10 才有的，而本仓 `minSdk` 是 24）、设备不报、通道不在、原生报错，一律回
/// [CastEncoderRealtime.unknown]。于是「问不到」这条常态分支有了唯一落点，
/// 调用方不必自己再判一遍——兜底口径见 `cast_encoder_realtime.dart` 的
/// [castRenderResolutionFor]。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cast_encoder_realtime.dart';
import 'platform_encoder_realtime_capability.dart';

/// 问系统「编码器保证覆盖得了 [target] 这个尺寸吗」的接缝（三态，不是 bool）。
abstract interface class CastEncoderRealtimeCapability {
  /// 照 [target] 问一次（宽 / 高 / 帧率由 Dart 侧给）。**不抛**：任何问不出来
  /// 的情形都回 [CastEncoderRealtime.unknown]（调用方据此按不可保证兜底）。
  Future<CastEncoderRealtime> query(CastEncoderQueryTarget target);
}

/// 编码器能力查询的注入点：真实实现走手写平台通道；测试 override 注入替身。
final castEncoderRealtimeCapabilityProvider =
    Provider<CastEncoderRealtimeCapability>(
      (ref) => PlatformEncoderRealtimeCapability(),
    );
