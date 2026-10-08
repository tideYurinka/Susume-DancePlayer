/// **接收端发现**接缝：局域网上有哪些设备愿意接我们推过去的片。
///
/// 接口 + 真实实现 + Provider 注入，注入手法沿仓内既有的平台 seam（相机采集
/// / 平台分享通道 / 更新网关）：真实实现走 SSDP + 设备描述
/// （`ssdp_receiver_discovery.dart`），测试注入脚本化替身
/// （`test/helpers/fake_cast_receiver_discovery.dart`）——不碰真网络。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'device_description.dart';
import 'ssdp_receiver_discovery.dart';

/// 一次发现的默认等待：设备在 `MX` 秒内随机挑时刻应答，3 秒覆盖常见家用
/// 设备；准备面板可显式给更短的等待（测试用毫秒级）。
const Duration kCastDiscoveryTimeout = Duration(seconds: 3);

/// 一台**接收端**：同一局域网上接受推送、自己解码播放的那台设备。
class CastReceiver {
  const CastReceiver({
    required this.id,
    required this.friendlyName,
    required this.descriptionUrl,
    required this.controlUrls,
  });

  /// 设备身份（设备描述的 UDN，缺则退到 SSDP 的 USN/设备描述地址）——同一
  /// 台电视在两次发现里是同一个 id。
  final String id;

  /// 用户在列表里看到的名字。
  final String friendlyName;

  /// 设备描述地址（发现时用的那个 `LOCATION`）。
  final Uri descriptionUrl;

  /// 往哪发 SOAP。
  final CastControlUrls controlUrls;

  /// 能不能当投屏对象：有 AVTransport 控制端点才有得遥控。
  bool get canReceiveCast => controlUrls.avTransport != null;

  @override
  bool operator ==(Object other) =>
      other is CastReceiver &&
      other.id == id &&
      other.friendlyName == friendlyName &&
      other.descriptionUrl == descriptionUrl &&
      other.controlUrls == controlUrls;

  @override
  int get hashCode =>
      Object.hash(id, friendlyName, descriptionUrl, controlUrls);

  @override
  String toString() => 'CastReceiver($friendlyName, $id)';
}

/// 接收端发现接缝。
abstract interface class CastReceiverDiscovery {
  /// 发现一次：在局域网上广播一次搜索、收齐应答、连设备描述一起解析成
  /// **可投屏的**接收端。
  ///
  /// 语义上是**问一次答一次**，不是长跑订阅：准备面板重扫就是再调一次。
  /// 一个都没发现时返回空表（**不是失败**——「搜不到」是用户要看见的一种
  /// 状态）；发现本身出不了网（组播发不出去）时同样返回空表，不抛。
  Future<List<CastReceiver>> discover({Duration timeout});
}

/// 接收端发现的注入点：真实实现走 SSDP（组播）；测试 override 注入脚本化
/// 替身。
final castReceiverDiscoveryProvider = Provider<CastReceiverDiscovery>(
  (ref) => SsdpCastReceiverDiscovery(),
);
