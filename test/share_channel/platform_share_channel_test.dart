import 'dart:io';

import 'package:dance_learning_app/share_channel/platform_share_channel.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 平台分享通道 Dart 侧直测：经 test messenger 模拟
/// 原生侧——冷启动拉取（留存槽容量 1，取走即清）、热启动推送（onInboundShare）、
/// 入站物化（materializeInbound 转发 uri 与目标路径）。原生留存与 content
/// 复制归原生实现，宿主测试覆盖不到（真机验收清单）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('susume/share_channel');
  const codec = StandardMethodCodec();

  final pendingReplies = <String?>[
    'content://com.tencent.mm/xxx/歌.susume',
    null,
  ];
  var pendingIndex = 0;
  final materializedCalls = <Map<String, Object?>>[];
  late PlatformShareChannel service;
  late Directory baseDir;

  setUp(() async {
    baseDir = await Directory.systemTemp.createTemp('share_channel_test');
    service = PlatformShareChannel(resolveBaseDirectory: () async => baseDir);
    pendingIndex = 0;
    materializedCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'takePendingInbound':
              return pendingIndex < pendingReplies.length
                  ? pendingReplies[pendingIndex++]
                  : null;
            case 'materializeInbound':
              materializedCalls.add(
                Map<String, Object?>.from(call.arguments as Map),
              );
              return true;
          }
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (baseDir.existsSync()) baseDir.deleteSync(recursive: true);
  });

  test('冷启动：拉取返回原生留存的入站分享，再拉返回 null（容量 1、取走即清）', () async {
    final share = await service.takePendingInbound();
    expect(share?.contentUri, 'content://com.tencent.mm/xxx/歌.susume');
    expect(await service.takePendingInbound(), isNull);
  });

  test('热启动：原生推送 onInboundShare 到达 inboundShares 流', () async {
    // 槽为空（推送前已被消费/无留存）的常态。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'takePendingInbound') return null;
          return null;
        });
    final received = <InboundShare>[];
    final sub = service.inboundShares.listen(received.add);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'susume/share_channel',
          codec.encodeMethodCall(
            const MethodCall('onInboundShare', 'content://a/b.susume'),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);
    expect(received.single.contentUri, 'content://a/b.susume');
    await sub.cancel();
  });

  test('推送即消费：收到推送后 Dart 回拉清空原生槽，同一条不被再导一次', () async {
    final takenCalls = <String?>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'takePendingInbound':
              // 推送后回拉：槽里仍是同一条（原生推送不清槽），被取走即清。
              takenCalls.add(call.method);
              return 'content://a/b.susume';
            case 'materializeInbound':
              materializedCalls.add(
                Map<String, Object?>.from(call.arguments as Map),
              );
              return true;
          }
          return null;
        });
    final received = <InboundShare>[];
    final sub = service.inboundShares.listen(received.add);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'susume/share_channel',
          codec.encodeMethodCall(
            const MethodCall('onInboundShare', 'content://a/b.susume'),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);
    expect(takenCalls, hasLength(1), reason: '推送后立即回拉原生留存槽');
    expect(received, hasLength(1), reason: '槽里同一条不补发——推送已消费');
    await sub.cancel();
  });

  test('入站物化：把 content URI 与目标路径交原生复制，返回本地文件', () async {
    final file = await service.materialize(
      const InboundShare(contentUri: 'content://a/b/歌.susume'),
    );
    expect(materializedCalls.single['uri'], 'content://a/b/歌.susume');
    expect(materializedCalls.single['destPath'], file.path);
    expect(file.path, endsWith('.susume'));
  });
}
