import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/player/cast_prep_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_video_copy_presence.dart';

/// 投屏准备面板直测：列接收端、可重扫、两条门（副本丢失 / 发现不到接收端）
/// 当场拦下并说明；选中一台即带出（起投编排在宿主，本面板不碰）。
void main() {
  const filePath = '/videos/a.mp4';

  CastReceiver receiver(String name) => CastReceiver(
    id: 'udn-$name',
    friendlyName: name,
    descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
    controlUrls: CastControlUrls(
      avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
    ),
  );

  /// 面板宿主：按钮开面板、把出参（选中的接收端）记进通知器。
  Future<void> pumpHost(
    WidgetTester tester, {
    required FakeCastReceiverDiscovery discovery,
    required FakeVideoCopyPresence presence,
    required ValueNotifier<CastReceiver?> picked,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          castReceiverDiscoveryProvider.overrideWithValue(discovery),
          videoCopyPresenceProvider.overrideWithValue(presence),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open_panel'),
                onPressed: () async {
                  picked.value = await showDialog<CastReceiver>(
                    context: context,
                    builder: (_) => const CastPrepPanel(
                      videoFilePath: filePath,
                    ),
                  );
                },
                child: const Text('开面板'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_panel')));
    await tester.pumpAndSettle();
  }

  testWidgets('列出发现到的接收端；选中一台即带出它', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视'), receiver('卧室盒子')],
      ],
    );
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );

    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(find.text('客厅电视'), findsOneWidget);
    expect(find.text('卧室盒子'), findsOneWidget);
    expect(discovery.discoverCalls, 1, reason: '打开即扫一次');

    await tester.tap(find.byKey(const Key('cast_receiver_udn-卧室盒子')));
    await tester.pumpAndSettle();

    expect(picked.value?.friendlyName, '卧室盒子');
    expect(find.byKey(const Key('cast_prep_panel')), findsNothing);
  });

  testWidgets('取消：不带出任何接收端（宿主据此零副作用）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    await tester.tap(find.byKey(const Key('cast_prep_cancel')));
    await tester.pumpAndSettle();

    expect(picked.value, isNull);
  });

  testWidgets('重新搜索：再调一次发现、列表按新结果换', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
        [receiver('卧室盒子')],
      ],
    );
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    expect(find.text('客厅电视'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cast_prep_refresh')));
    await tester.pumpAndSettle();

    expect(discovery.discoverCalls, 2, reason: '重扫就是再调一次');
    expect(find.text('客厅电视'), findsNothing);
    expect(find.text('卧室盒子'), findsOneWidget);
  });

  testWidgets('副本丢失门：当场说明、不出接收端列表、也不扫', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(missingPaths: const {filePath}),
      picked: picked,
    );

    expect(find.byKey(const Key('cast_gate_copy')), findsOneWidget);
    expect(find.text(kCastPrepCopyMissingText), findsOneWidget);
    expect(find.text('客厅电视'), findsNothing);
    expect(discovery.discoverCalls, 0, reason: '副本丢失时没什么可投的，不必扫');
    // 重扫按钮也离场——这条门下没有可做的事。
    expect(find.byKey(const Key('cast_prep_refresh')), findsNothing);
  });

  testWidgets('发现不到接收端门：说明同一 Wi-Fi / 访客网络，并把重扫留在眼前', (tester) async {
    final discovery = FakeCastReceiverDiscovery(script: [const []]);
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );

    expect(find.byKey(const Key('cast_gate_no_receiver')), findsOneWidget);
    expect(find.text(kCastPrepNoReceiverText), findsOneWidget);
    expect(find.byKey(const Key('cast_prep_refresh')), findsOneWidget);

    // 重扫到一台 → 空态换列表（门是当场拦下、不是死路）。
    discovery.script.add([receiver('客厅电视')]);
    await tester.tap(find.byKey(const Key('cast_prep_refresh')));
    await tester.pumpAndSettle();
    expect(discovery.discoverCalls, 2);
    expect(find.text('客厅电视'), findsOneWidget);
  });

  testWidgets('发现本身出错：与「一台都没发现」同一口径（空态说明，不炸）', (tester) async {
    final discovery = FakeCastReceiverDiscovery()..error = StateError('组播发不出去');
    final picked = ValueNotifier<CastReceiver?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );

    expect(tester.takeException(), isNull);
    expect(find.text(kCastPrepNoReceiverText), findsOneWidget);
  });
}
