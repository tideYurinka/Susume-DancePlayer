/// 投屏准备面板：进入**投屏态**之前那一段编排的界面——列同一局域网上的
/// **接收端**、可重扫、把两条**门事实**当场拦下并说明。
///
/// 它只回答一件事：**投到哪台**。选中一台即 pop 出它（起递出通道、连会话、
/// 推片、起播与进入投屏态的编排都在宿主）；取消 / 返回 = null = 进它之前
/// 的样子、零副作用。
///
/// ## 两条门都在面板里当场拦下并说明
///
/// - **副本丢失**（[kCastPrepCopyMissingText]）：这支舞的**视频副本**不在
///   本机——面板只出这一句说明，不出接收端列表（推一份不在盘上的文件没有
///   意义）。存在性问的是全 App 唯一那一处判定
///   （`lib/dance/video_copy_presence.dart`）。
/// - **发现不到接收端**（[kCastPrepNoReceiverText]）：搜到空表（或发现本身
///   出不了网，两者同一口径）——空态说明「手机与电视要在同一个 Wi-Fi、电视
///   别开访客网络」，并把重扫按钮留在眼前。
///
/// 本文件零网络实现：发现走发现接缝（真实实现 SSDP、测试注入脚本化替身）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_receiver.dart';
import '../dance/video_copy_presence.dart' show videoCopyPresenceProvider;
import 'visual_tokens.dart' show kPlayerSkinColor;

/// 副本丢失门的文案（唯一一份生产取值；测试逐字重写期望值，故意不从本
/// 常量取——文案改了要能在测试里看见）。
const String kCastPrepCopyMissingText = '这支舞的视频副本不在本机，先把副本找回来再投屏';

/// 发现不到接收端（不在同一局域网）门的文案。
const String kCastPrepNoReceiverText = '没找到接收端：手机与电视要在同一个 Wi-Fi，电视别开访客网络';

/// 正在搜索的那一句（重扫期间也在）。
const String kCastPrepScanningText = '正在搜索同一局域网上的接收端…';

/// 面板标题。
const String kCastPrepTitle = '投屏到哪台设备';

/// 投屏准备面板（宿主经 `showDialog` 呈现；出参 = 选中的接收端或 null）。
class CastPrepPanel extends ConsumerStatefulWidget {
  const CastPrepPanel({super.key, required this.videoFilePath});

  /// 这支舞的**视频副本**路径（副本存在性判定的输入）。
  final String videoFilePath;

  @override
  ConsumerState<CastPrepPanel> createState() => _CastPrepPanelState();
}

class _CastPrepPanelState extends ConsumerState<CastPrepPanel> {
  bool _scanning = true;
  List<CastReceiver> _receivers = const [];

  @override
  void initState() {
    super.initState();
    // 打开即扫一次；重扫就是再调一次（发现是「问一次答一次」，不是长跑
    // 订阅）。副本丢失时不必扫——那条门先拦住。
    if (!ref.read(videoCopyPresenceProvider).exists(widget.videoFilePath)) {
      _scanning = false;
      return;
    }
    unawaited(_scan());
  }

  /// 副本丢失门的事实：存在性问的是全 App 唯一那一处判定
  /// （`lib/dance/video_copy_presence.dart`）。同步查询，构建期直读。
  bool get _copyMissing =>
      !ref.watch(videoCopyPresenceProvider).exists(widget.videoFilePath);

  Future<void> _scan() async {
    setState(() => _scanning = true);
    List<CastReceiver> found;
    try {
      found = await ref.read(castReceiverDiscoveryProvider).discover();
    } on Object {
      // 发现本身出不了网 / 替身注入失败：与「一台都没发现」同一口径
      // （空表不是失败，见发现接缝）。
      found = const [];
    }
    if (!mounted) return;
    setState(() {
      _receivers = found;
      _scanning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('cast_prep_panel'),
      backgroundColor: kPlayerSkinColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                kCastPrepTitle,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 12),
              if (_copyMissing)
                _gateText(kCastPrepCopyMissingText, const Key('cast_gate_copy'))
              else ...[
                if (_scanning)
                  _gateText(
                    kCastPrepScanningText,
                    const Key('cast_prep_scanning'),
                  )
                else if (_receivers.isEmpty)
                  _gateText(
                    kCastPrepNoReceiverText,
                    const Key('cast_gate_no_receiver'),
                  )
                else
                  for (final receiver in _receivers)
                    ListTile(
                      key: Key('cast_receiver_${receiver.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tv, color: Colors.white70),
                      title: Text(
                        receiver.friendlyName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      // 只列**能当投屏对象**的接收端（有 AVTransport 控制
                      // 端点）——发现接缝已按此过滤，这里不再二次判。
                      onTap: receiver.canReceiveCast
                          ? () => Navigator.of(context).pop(receiver)
                          : null,
                    ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_copyMissing)
                    TextButton(
                      key: const Key('cast_prep_refresh'),
                      onPressed: _scanning ? null : _scan,
                      child: const Text('重新搜索'),
                    ),
                  TextButton(
                    key: const Key('cast_prep_cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gateText(String text, Key key) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
    ),
  );
}
