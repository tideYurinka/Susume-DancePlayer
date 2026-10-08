/// 投屏失败的三类明确结局：**不吞错**——连不上、拒播、中途掉线在调用方看
/// 来是三件不同的事，界面也就有三种说法。
library;

/// 投屏失败的共同基类。
sealed class CastFailure implements Exception {
  const CastFailure(this.message);

  /// 给日志与失败面用的原因（不面向用户的那份字）。
  final String message;

  @override
  String toString() => '$runtimeType：$message';
}

/// **连不上**：SSDP 应答指到的设备描述拉不回来、控制端点连不通，或会话还没
/// 建立就断了。
final class CastReceiverUnreachable extends CastFailure {
  const CastReceiverUnreachable(super.message);
}

/// **拒播**：会话在，但接收端明确回绝了这次动作（SOAP Fault、非 2xx），或
/// 应答读不出。带着设备的 UPnP 错误码（读不出时是
/// `kCastSoapUnparsableErrorCode`）。
final class CastActionRefused extends CastFailure {
  const CastActionRefused(super.message, {this.upnpErrorCode});

  final int? upnpErrorCode;

  @override
  String toString() => '${super.toString()}（UPnP 错误码 $upnpErrorCode）';
}

/// **中途掉线**：会话建立过，之后某次遥控或状态查询断了（接收端关掉、
/// 换了网络、连接被掐）。
final class CastSessionDropped extends CastFailure {
  const CastSessionDropped(super.message);
}
