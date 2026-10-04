import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'share_channel.dart';

/// 平台分享通道真实实现：MethodChannel `susume/share_channel`，Android 侧
/// 为 `ShareChannelPlugin`——出站 shareFile 与入站三条方法同在这条通道。
class PlatformShareChannel implements ShareChannel {
  static const _channel = MethodChannel('susume/share_channel');

  // 广播流：首页状态在导航往返中重建，重听不炸（每期监听各自收推送）。
  final _inboundController = StreamController<InboundShare>.broadcast();

  /// 物化落点的目录解析（注入手法沿视频导入管道的落点工厂；缺省 =
  /// path_provider 的应用临时目录，测试传临时目录直测）。
  final Future<Directory> Function() resolveBaseDirectory;

  PlatformShareChannel({Future<Directory> Function()? resolveBaseDirectory})
    : resolveBaseDirectory = resolveBaseDirectory ?? getTemporaryDirectory {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  @override
  Future<void> shareFile(File file) =>
      _channel.invokeMethod<void>('shareFile', file.path);

  Future<Object?> _onNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'onInboundShare':
        final uri = call.arguments as String?;
        if (uri != null) {
          _inboundController.add(InboundShare(contentUri: uri));
          // 推送即消费：清掉原生留存槽里的同一条——推送成功后槽不清，
          // 此后的拉取（首页状态重建重拉）会把同一个包再导一次。
          unawaited(_drainSlotAfter(uri));
        }
    }
    return null;
  }

  Future<void> _drainSlotAfter(String pushedUri) async {
    try {
      final pending = await _channel.invokeMethod<String>('takePendingInbound');
      // 槽里是推送那条之外的更新入站（容量 1 内的覆盖）才补发。
      if (pending != null && pending != pushedUri) {
        _inboundController.add(InboundShare(contentUri: pending));
      }
    } on PlatformException {
      // 通道不在/槽已空：推送已是唯一一份，无事可做。
    }
  }

  @override
  Future<InboundShare?> takePendingInbound() async {
    final uri = await _channel.invokeMethod<String>('takePendingInbound');
    return uri == null ? null : InboundShare(contentUri: uri);
  }

  @override
  Stream<InboundShare> get inboundShares => _inboundController.stream;

  @override
  Future<File> materialize(InboundShare share) async {
    final base = await resolveBaseDirectory();
    // 固定落点、逐次覆盖：物化件只是导入的中转，导入编排产生的都是私有副本。
    final dest = File(
      p.join(base.path, inboundMaterializedName(share.contentUri)),
    );
    final copied = await _channel.invokeMethod<bool>('materializeInbound', {
      'uri': share.contentUri,
      'destPath': dest.path,
    });
    if (copied != true) {
      throw ShareMaterializeException('收到的文件复制不进来，导入中止');
    }
    return dest;
  }
}
