import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/cast/system_mirror.dart'
    show systemMirrorLauncherProvider;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/material_manifest.dart'
    show materialRecordingFileResolverProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/control_layer.dart'
    show kAnnotationToolRowKey;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_session.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_mirror_launcher.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_video_copy_presence.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

/// 投屏全链的宿主测试：顶栏那枚投屏工具 → 投屏准备面板 → 推原片 → 投屏态
/// （底排无槽位、轨道带只留分段轨、顶栏三枚）→ 断开 / 系统返回 / 离开页面；
/// 以及投屏态顶栏那枚**系统镜像**入口（先断开再跳、降级链走不通给一句短暂
/// 提示）。
/// 接收端经 #23 的脚本化替身注入，不碰真网络；原生与真机行为留真机验收
/// （见 `lib/cast/docs/real-device-acceptance.md`）。
void main() {
  late FakePlaybackEngine engine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late FakeCastReceiverDiscovery discovery;
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannel delivery;
  late FakeSystemMirrorLauncher systemMirror;

  const receiverName = '客厅电视';

  CastReceiver receiver() => CastReceiver(
    id: 'udn-$receiverName',
    friendlyName: receiverName,
    descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
    controlUrls: CastControlUrls(
      avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
    ),
  );

  void setWideView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpPlayer(
    WidgetTester tester, {
    String filePath = '/videos/a.mp4',
  }) async {
    final source = Uri.file(filePath);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackEngineProvider.overrideWithValue(engine),
          cameraCaptureProvider.overrideWithValue(camera),
          privateJsonStorageProvider.overrideWithValue(
            InMemoryPrivateJsonStorage(),
          ),
          systemUiControllerProvider.overrideWithValue(systemUi),
          materialRecordingFileResolverProvider.overrideWithValue(
            (videoId) async => File('/tmp/cast_rec.mp4'),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) => InMemoryVideoDocumentStorage(),
          ),
          contentHasherProvider.overrideWithValue(const FixedHasher('seeded')),
          videoIndexStoreProvider.overrideWithValue(
            InMemoryVideoIndexStorage(
              initial: VideoIndex(
                entries: [
                  historyEntry(filePath: source.toFilePath(), mirrored: false),
                ],
              ),
            ),
          ),
          castReceiverDiscoveryProvider.overrideWithValue(discovery),
          castSessionFactoryProvider.overrideWithValue(factory),
          castDeliveryChannelProvider.overrideWithValue(delivery),
          systemMirrorLauncherProvider.overrideWithValue(systemMirror),
          videoCopyPresenceProvider.overrideWithValue(FakeVideoCopyPresence()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open_player'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlayerPage(source: source),
                  ),
                ),
                child: const Text('开播放页'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open_player')));
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(PlayerPage)),
        listen: false,
      );

  PlayerSessionMode modeOf(WidgetTester tester) =>
      containerOf(tester).read(playerSessionProvider).mode;

  /// 单击画面唤出控制层。
  Future<void> openControlLayer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
  }

  /// 从编辑态起投：点投屏工具 → 面板 → 选客厅电视。
  Future<void> startCast(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_receiver_udn-$receiverName')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    engine = FakePlaybackEngine(duration: const Duration(seconds: 30));
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
    discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver()],
      ],
    );
    factory = FakeCastSessionFactory();
    delivery = FakeCastDeliveryChannel();
    systemMirror = FakeSystemMirrorLauncher();
  });

  testWidgets('编辑态顶栏有投屏工具；点它开准备面板、列接收端', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);

    expect(find.byKey(const Key('tool_cast')), findsOneWidget);
    expect(find.text('投屏'), findsOneWidget);

    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(find.text(receiverName), findsOneWidget);
    // 还在编辑态：面板是进入前置、不是投屏态本身。
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(delivery.served, isEmpty);
  });

  testWidgets('取消准备面板：模式值一位不动、零副作用', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cast_prep_cancel')));
    await tester.pumpAndSettle();

    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(
      containerOf(tester).read(playerSessionProvider).pendingEntry,
      isNull,
    );
    expect(factory.connectCalls, 0);
    expect(delivery.served, isEmpty);
  });

  testWidgets('选一台 → 推原片 → 进投屏态：底排无槽位、轨道带只留分段轨、顶栏三枚', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 推的是这支舞的原片（不是任何渲染副本）。
    expect(delivery.served, hasLength(1));
    expect(delivery.served.single.path, '/videos/a.mp4');
    expect(factory.sessions.single.calls, ['push', 'play']);
    expect(modeOf(tester), PlayerSessionMode.castControl);

    // 顶栏换装：断开投屏 + 系统镜像 + 查看引导（编辑态那枚投屏不在场）。
    expect(find.byKey(const Key('tool_cast_disconnect')), findsOneWidget);
    expect(find.text('断开投屏'), findsOneWidget);
    expect(find.byKey(const Key('tool_system_mirror')), findsOneWidget);
    expect(find.text('系统镜像'), findsOneWidget);
    expect(find.byKey(const Key('tool_guide')), findsOneWidget);
    expect(find.byKey(const Key('tool_cast')), findsNothing);
    expect(find.byKey(const Key('tool_compare')), findsNothing);

    // 底排槽位整排不出现（播放控制组仍在——它是遥控电视的那一条路）。
    expect(find.byKey(kAnnotationToolRowKey), findsNothing);
    expect(find.byKey(const Key('control_segment')), findsNothing);
    expect(find.byKey(const Key('control_mastery')), findsNothing);
    expect(find.byKey(const Key('control_layer_toolbar')), findsOneWidget);
    expect(find.byKey(const Key('toolbar_play')), findsOneWidget);

    // 轨道带只留分段轨：片头只剩「分段」，其余行与手柄带行一律不在。
    expect(find.byKey(const Key('track_learning')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('track_prefix_label_learning')))
          .data,
      '分段',
      reason: '片头标签只剩「分段」这一条',
    );
    expect(find.byKey(const Key('track_notes')), findsNothing);
    expect(find.byKey(const Key('track_mirror')), findsNothing);
    expect(find.byKey(const Key('track_beat')), findsNothing);
    // 无柄可拖 = 分段结构性只读。
    expect(find.byKey(const Key('track_handle_strip')), findsNothing);
  });

  testWidgets('系统镜像入口：先断开投屏并停服、再跳系统设置（顺序）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;

    // 跳转被调用的**那一刻**回看投屏侧：会话已断、递出通道已停服——
    // 顺序错了（先跳再断）这里就是 false。
    (bool, bool)? atLaunch;
    systemMirror.onOpen = () => atLaunch = (cast.disconnected, delivery.closed);

    await tester.tap(find.byKey(const Key('tool_system_mirror')));
    await tester.pumpAndSettle();

    expect(systemMirror.openCalls, 1);
    expect(atLaunch, isNotNull, reason: '系统设置跳转没被调用');
    expect(atLaunch, (true, true), reason: '先断开投屏（含立即停服）再跳');
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('cast_interrupted_prompt')), findsNothing);
  });

  testWidgets('系统镜像入口的提示文案说清两条路的代价差（出口上就能看见）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    expect(
      find.byTooltip(
        '整屏镜像：有延迟、手机屏要亮着、控制层也上电视；'
        '我们这条路推的是渲染好的投屏副本',
      ),
      findsOneWidget,
    );
  });

  testWidgets('系统镜像降级链两级都没接住：给一句短暂提示', (tester) async {
    setWideView(tester);
    systemMirror.opened = false;
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    await tester.tap(find.byKey(const Key('tool_system_mirror')));
    await tester.pumpAndSettle();

    expect(systemMirror.openCalls, 1);
    expect(find.byKey(const Key('cast_system_mirror_prompt')), findsOneWidget);
    expect(find.text('这台设备打不开系统投屏设置'), findsOneWidget);
    // 投屏照样断干净、回编辑态——那个入口不因为跳不动就把人留在投屏态。
    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(modeOf(tester), PlayerSessionMode.editing);
  });

  testWidgets('断开投屏（顶栏那枚）：停服 + 断连 + 回编辑态、底排槽位回来', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    await tester.tap(find.byKey(const Key('tool_cast_disconnect')));
    await tester.pumpAndSettle();

    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue, reason: '递出通道随断开立即停服');
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('control_segment')), findsOneWidget);
    expect(find.byKey(const Key('tool_cast')), findsOneWidget);
  });

  testWidgets('左上角退出箭头 = 断开投屏（同一动作）：先断开回编辑态、不离开页面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    await tester.tap(find.byKey(const Key('control_layer_back')));
    await tester.pumpAndSettle();

    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byType(PlayerPage), findsOneWidget, reason: '第一次返回不离开页面');
  });

  testWidgets('系统返回两级：投屏态内先断开回编辑态、再按一次才离开页面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    final first = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(first, isTrue);
    expect(engine.isPlaying, isTrue);
    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byType(PlayerPage), findsOneWidget, reason: '第一次不离开页面');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing, reason: '第二次离开页面');
  });

  testWidgets('离开播放页：断开并停服（触发点收在既有复位一处）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 离开播放页（真实路径是首页/详情页的返回）：组合根销毁 → 既有复位。
    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();

    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
  });

  testWidgets('投屏态内手机遥控电视：播放/暂停作用于接收端', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;
    expect(cast.calls, ['push', 'play']);

    // 底排播放键：本机在播 → 按一下是「暂停」，同时遥控电视暂停。
    expect(engine.isPlaying, isTrue);
    await tester.tap(find.byKey(const Key('toolbar_play')));
    await tester.pumpAndSettle();
    expect(engine.isPlaying, isFalse);
    expect(cast.calls, ['push', 'play', 'pause']);

    // 再按一下：本机复播 + 遥控电视复播。
    await tester.tap(find.byKey(const Key('toolbar_play')));
    await tester.pumpAndSettle();
    expect(cast.calls, ['push', 'play', 'pause', 'play']);
  });

  testWidgets('投屏态内拖进度：手指离手后按最终落点让电视跳一次', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;

    // 收起控制层到投屏-观看态：画面手势面这时在顶层（与真实手势同一面）。
    containerOf(tester).read(playerSessionProvider.notifier).collapse();
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.castWatching);

    // 画面中央单指横向拖（低灵敏度调进度）：逐帧拖动只动本机，
    // 离手后按最终落点镜像一次给接收端。
    final gesture = await tester.startGesture(const Offset(480, 270));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cast.seeks, hasLength(1), reason: '拖动只镜像一次（收口落点）');
    expect(cast.seeks.single, greaterThan(Duration.zero));
  });

  testWidgets('起投失败（连不上）：短暂提示 + 停在编辑态、通道零残留', (tester) async {
    setWideView(tester);
    factory.connectError = const CastReceiverUnreachable('端点连不通');
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('cast_not_started_prompt')), findsOneWidget);
    expect(delivery.closed, isTrue);
  });
}
