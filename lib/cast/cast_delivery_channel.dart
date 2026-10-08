/// **递出通道**接缝：只在**投屏会话期内**存在的那条局域网可达的 HTTP 通路。
///
/// 本机只为这次会话、这一个文件开一个服务，路径是**一次性随机**的（不可
/// 枚举、猜不到），支持 `Range`（接收端要能拖进度），会话结束**立即停服**。
/// 这与可见性三级无关：副本本身始终是完全私密，见 ADR-0005。
///
/// 接口 + 真实实现（`lan_cast_delivery_channel.dart`）+ Provider 注入 +
/// 脚本化替身（`test/helpers/fake_cast_delivery_channel.dart`）。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lan_cast_delivery_channel.dart';

/// 递出通道已经停服：会话结束后再要一份地址是编程错误，**不静默重开**。
class CastDeliveryClosed implements Exception {
  const CastDeliveryClosed();

  @override
  String toString() => 'CastDeliveryClosed：递出通道已停服';
}

/// 递出通道接缝。
abstract interface class CastDeliveryChannel {
  /// 把 [file] 按一次性随机路径暴露给局域网，返回接收端能拉的地址。
  ///
  /// 每次调用都换一个新路径：**上一个立刻失效**（一次会话只递一份文件）。
  /// 已经 [close] 过时抛 [CastDeliveryClosed]。
  Future<Uri> serve(File file);

  /// 会话结束：**立即停服**（在飞的连接一并断掉）。重复调用是空操作。
  Future<void> close();
}

/// 递出通道的注入点：真实实现起本机 HTTP 服务；测试 override 注入脚本化
/// 替身，或直接用真实实现打环回。
///
/// 注入的是**取一份新通道的工厂**（`CastDeliveryChannel Function()`），不是
/// 通道本身：一个通道实例是**一次性**的（[CastDeliveryChannel.close] 之后
/// [CastDeliveryChannel.serve] 抛 [CastDeliveryClosed]），而「投 → 断开 →
/// 重选 → 再投」在会话之外要反复进行——每次起投取一份新的、收尾关掉当次那
/// 一份。容器级单例在这里会把第二次起投变成必然失败（与
/// `castSessionFactoryProvider` 同款：接缝注入点给工厂，不留跨会话复用的
/// 实例）。
final castDeliveryChannelFactoryProvider =
    Provider<CastDeliveryChannel Function()>(
      (ref) => LanCastDeliveryChannel.new,
    );

/// 一次 `Range` 请求的解析结局。
sealed class CastRangeRequest {
  const CastRangeRequest();
}

/// 没有 `Range` 头，或写法不认（别的单位、多重区间、语法不对）：**整份发**。
final class CastRangeAbsent extends CastRangeRequest {
  const CastRangeAbsent();
}

/// 解析出的闭区间（字节偏移，含两端）。
final class CastRangeResolved extends CastRangeRequest {
  const CastRangeResolved({required this.start, required this.end});

  final int start;
  final int end;

  int get length => end - start + 1;

  @override
  bool operator ==(Object other) =>
      other is CastRangeResolved && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'CastRangeResolved($start-$end)';
}

/// 请求的范围落在文件之外：回 `416`（附 `Content-Range: bytes */<长度>`）。
final class CastRangeUnsatisfiable extends CastRangeRequest {
  const CastRangeUnsatisfiable();
}

/// 解析 `Range` 头。
///
/// 只认**单个** `bytes=` 区间（`N-M`、`N-`、`-N`）：多重区间一律按「整份
/// 发」处理——接收端拖进度只发单区间；语法不对同样整份发，而不是回错。
/// 真正越界的（起点在文件之外、后缀长度为 0、空文件上的任何区间）才回
/// [CastRangeUnsatisfiable]。
CastRangeRequest parseCastRangeHeader(String? header, int length) {
  final raw = header?.trim() ?? '';
  if (raw.isEmpty) return const CastRangeAbsent();
  final lower = raw.toLowerCase();
  if (!lower.startsWith('bytes=')) return const CastRangeAbsent();
  final spec = raw.substring('bytes='.length).trim();
  if (spec.isEmpty || spec.contains(',')) return const CastRangeAbsent();

  final dash = spec.indexOf('-');
  if (dash < 0) return const CastRangeAbsent();
  final startText = spec.substring(0, dash).trim();
  final endText = spec.substring(dash + 1).trim();

  // `-N`：末尾 N 个字节。
  if (startText.isEmpty) {
    final suffix = int.tryParse(endText);
    if (suffix == null || suffix < 0) return const CastRangeAbsent();
    if (suffix == 0 || length == 0) return const CastRangeUnsatisfiable();
    if (suffix >= length) return CastRangeResolved(start: 0, end: length - 1);
    return CastRangeResolved(start: length - suffix, end: length - 1);
  }

  final start = int.tryParse(startText);
  if (start == null || start < 0) return const CastRangeAbsent();
  if (length == 0 || start >= length) return const CastRangeUnsatisfiable();

  // `N-`：从 N 到文件尾。
  if (endText.isEmpty) return CastRangeResolved(start: start, end: length - 1);

  final end = int.tryParse(endText);
  if (end == null || end < 0) return const CastRangeAbsent();
  if (end < start) return const CastRangeAbsent();
  return CastRangeResolved(start: start, end: end >= length ? length - 1 : end);
}
