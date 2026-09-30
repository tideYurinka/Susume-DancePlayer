/// 平台分享通道：系统分享面板与 App 之间那条通路的唯一接缝，出站与入站
/// 走同一个 MethodChannel `susume/share_channel`。接口 + 真实实现 + Fake
/// 注入，注入手法沿相机采集服务（本仓唯一既有原生 seam）。
///
/// 出站递出 [ShareChannel.shareFile]：把应用目录内的原文件交给系统分享
/// 面板，零复制——原生用自建 FileProvider 把路径换 content URI + 读权限，
/// 拉起 `ACTION_SEND`；**不引 share_plus**（它无条件整份复制待分享文件）。
///
/// 入站两条路径：冷启动的 intent 由原生侧留存、Dart 拉
/// （[ShareChannel.takePendingInbound]，平台→Dart 的推送缓冲容量为 1）；
/// 热启动走 `onNewIntent`，经 [ShareChannel.inboundShares] 推送。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'platform_share_channel.dart';

/// 一次入站分享：系统投进来的 content URI（只读授权，不可随机寻址）。
class InboundShare {
  const InboundShare({required this.contentUri});

  final String contentUri;

  @override
  bool operator ==(Object other) =>
      other is InboundShare && other.contentUri == contentUri;

  @override
  int get hashCode => contentUri.hashCode;
}

/// 入站物化失败：content 读不开或复制中断（渠道层给出，导入流程按导入
/// 失败出声，不静默）。
class ShareMaterializeException implements Exception {
  const ShareMaterializeException(this.message);

  final String message;

  @override
  String toString() => 'ShareMaterializeException: $message';
}

/// 平台分享通道接缝。真实实现 = [PlatformShareChannel]（MethodChannel
/// `susume/share_channel`，Android 侧 `ShareChannelPlugin`）；测试注入 fake
/// （`test/helpers/fake_share_channel.dart`）。
abstract interface class ShareChannel {
  /// 出站：把 [file]（应用目录内的真实文件）递给系统分享面板。失败（平台
  /// 侧出错/无面板可接）抛错，由调用方出声，不静默。
  Future<void> shareFile(File file);

  /// 拉取冷启动时原生侧留存的入站分享；无则 null，取走即清（容量 1）。
  Future<InboundShare?> takePendingInbound();

  /// 热启动入站流：原生 `onNewIntent` 经通道推送。
  Stream<InboundShare> get inboundShares;

  /// 入站物化：把收到的 content URI **整份复制进应用
  /// 目录**，返回本地文件——只读授权下不保证可随机寻址，而 zip 的中央
  /// 目录在文件尾。失败抛 [ShareMaterializeException]。
  Future<File> materialize(InboundShare share);
}

/// 入站物化落点的文件名：取 content URI 末段（文件系统非法字符替换
/// `_`），取不到回落固定名。仅用于用户在报错里认得出；包身份不依赖
/// 文件名（清单自述）。真实实现与测试 Fake 共用，保证「断言物化路径」
/// 的口径一致。
String inboundMaterializedName(String contentUri) {
  final raw = Uri.tryParse(contentUri)?.pathSegments.lastOrNull;
  final name = (raw == null || raw.isEmpty) ? null : p.basename(raw);
  if (name == null || name == '/' || name == '.') return 'inbound.susume';
  return name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
}

/// 平台分享通道注入点：真实实现走 MethodChannel；测试 override 注入 fake。
final shareChannelProvider = Provider<ShareChannel>(
  (ref) => PlatformShareChannel(),
);
