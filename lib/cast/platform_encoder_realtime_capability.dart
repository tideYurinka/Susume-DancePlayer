/// 编码器 1× 实时能力查询的真实实现：手写 MethodChannel
/// `susume/encoder_realtime`（Android 侧 `EncoderRealtimeCapabilityPlugin`），
/// **一条方法**——`realtimeGuarantee` 回一句三态线值：
///
/// - `guaranteed`：系统给的编码器**性能点**覆盖得了**调用方给的那一档尺寸**；
/// - `notGuaranteed`：性能点答得出来、但覆盖不了；
/// - `unknown`：**问不到**——性能点是 **API 29+**（本仓 `minSdk` 是 24，故
///   API 24–28 上这门 API 根本不存在）、设备不报、通道不在、原生报错。
///
/// 目标尺寸（宽 / 高 / 帧率）**随调用一起过桥**（三个入参名与原生侧共用同一
/// 份常量），原生不再硬编 1080p30。
///
/// 三条线值与 Android 侧逐字对应，并在 `platform_encoder_realtime_capability_
/// test.dart` 里按 Kotlin 文件正文对齐（声明的事实）；真机上的读数留真机验收
/// （步骤见 `lib/cast/docs/real-device-acceptance.md`）。
///
/// **这里不替调用方决定降不降级**：本口只把三态老实地过桥，认不得的答案一律
/// [CastEncoderRealtime.unknown]（绝不退化成「保证」）；三态 → 分辨率档那条
/// 决策住在 `cast_encoder_realtime.dart`（可直测）。
library;

import 'package:flutter/services.dart';

import 'cast_encoder_realtime.dart';
import 'encoder_realtime_capability.dart';

/// 平台通道名。
const String kCastEncoderRealtimeChannelName = 'susume/encoder_realtime';

/// 通道上唯一的方法名。
const String kCastEncoderRealtimeMethod = 'realtimeGuarantee';

/// 目标尺寸的三个入参名（原生侧逐字同名地读）。
const String kCastEncoderTargetWidthArgument = 'width';
const String kCastEncoderTargetHeightArgument = 'height';
const String kCastEncoderTargetFpsArgument = 'fps';

/// 线值：保证 1× 实时。
const String kCastEncoderRealtimeGuaranteedAnswer = 'guaranteed';

/// 线值：不保证 1× 实时。
const String kCastEncoderRealtimeNotGuaranteedAnswer = 'notGuaranteed';

/// 线值：问不到（API < 29 / 设备不报 / 读不出来）。
const String kCastEncoderRealtimeUnknownAnswer = 'unknown';

/// 线值 → 三态。认不得的答案（null、别的字、别的类型）一律
/// [CastEncoderRealtime.unknown]：**问不到的兜底那一侧，不是保证那一侧**。
CastEncoderRealtime castEncoderRealtimeFromWire(Object? answer) {
  return switch (answer) {
    kCastEncoderRealtimeGuaranteedAnswer => CastEncoderRealtime.guaranteed,
    kCastEncoderRealtimeNotGuaranteedAnswer =>
      CastEncoderRealtime.notGuaranteed,
    _ => CastEncoderRealtime.unknown,
  };
}

/// 编码器能力查询的真实实现（手写平台通道，不引第三方包）。
class PlatformEncoderRealtimeCapability
    implements CastEncoderRealtimeCapability {
  static const _channel = MethodChannel(kCastEncoderRealtimeChannelName);

  @override
  Future<CastEncoderRealtime> query(CastEncoderQueryTarget target) async {
    try {
      return castEncoderRealtimeFromWire(
        await _channel.invokeMethod<Object?>(kCastEncoderRealtimeMethod, {
          kCastEncoderTargetWidthArgument: target.width,
          kCastEncoderTargetHeightArgument: target.height,
          kCastEncoderTargetFpsArgument: target.fps,
        }),
      );
    } on Object {
      // 通道不在（非 Android 宿主 / 插件未注册）、原生读性能点失败、过桥
      // 本身出别的岔子：都是同一个口径——**问不到**，不向上抛（不把一次查询
      // 失败升级成渲染失败）。
      return CastEncoderRealtime.unknown;
    }
  }
}
