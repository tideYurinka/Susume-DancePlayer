import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/share_channel/share_channel.dart';

/// 记录调用的假平台分享通道：出站记录递出的文件（不触碰系统分享面板），
/// 入站分享可脚本化——冷启动留存槽与热启动推送共用同一脚本来源；物化把
/// 脚本字节真实写入目标文件（模拟原生整份复制），断言目标路径落在应用目录内。
class FakeShareChannel implements ShareChannel {
  FakeShareChannel({this.pendingScript = const [], this.materializeFails = false});

  /// takePendingInbound 的逐次脚本（取尽后返回 null）；同时是 inboundShares
  /// 未推送前的冷启动态。
  final List<InboundShare?> pendingScript;
  int _pendingIndex = 0;

  /// 物化是否失败（脚本「content 读不开」路径）。
  bool materializeFails;

  /// 推送给 inboundShares 的入站（测试手动触发以模拟 onNewIntent）。
  final List<InboundShare> pushed = [];

  /// 物化目标（与真实实现同款：应用目录内按 URI 末段命名的固定文件）。
  final List<File> materializedTo = [];
  int takePendingCalls = 0;

  /// 出站：按调用序记录的递出文件。
  final List<File> sharedFiles = [];

  /// [shareFile] 的调用次数（含抛错的那次）：断言「不重试、不二次弹面板」
  /// 只能靠它——失败时 [sharedFiles] 本就不增长，光看它证明不了只调了一次。
  int shareCalls = 0;

  /// 非 null 时 [shareFile] 抛出该错误（失败路径用）。
  Object? throwOnShare;

  /// 模拟原生 onNewIntent 推送。
  void push(InboundShare share) {
    pushed.add(share);
    _controller.add(share);
  }

  final _controller = StreamController<InboundShare>.broadcast();

  @override
  Future<void> shareFile(File file) async {
    shareCalls++;
    final error = throwOnShare;
    if (error != null) throw error;
    sharedFiles.add(file);
  }

  @override
  Future<InboundShare?> takePendingInbound() async {
    takePendingCalls++;
    if (_pendingIndex < pendingScript.length) {
      return pendingScript[_pendingIndex++];
    }
    return null;
  }

  @override
  Stream<InboundShare> get inboundShares => _controller.stream;

  @override
  Future<File> materialize(InboundShare share) async {
    if (materializeFails) {
      throw const ShareMaterializeException('收到的文件复制不进来，导入中止');
    }
    // 不做真实 IO（widget 测试的 fake async 区里不可依赖）；命名与真实
    // 实现共用同一函数，断言的「物化落在哪个路径」口径一致。
    final dest = File(
      '${Directory.systemTemp.path}/susume_inbound/'
      '${inboundMaterializedName(share.contentUri)}',
    );
    materializedTo.add(dest);
    return dest;
  }
}
