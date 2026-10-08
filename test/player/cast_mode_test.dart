import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_render_activity.dart'
    show castRenderInProgressProvider;
import 'package:dance_learning_app/cast/cast_render_cache.dart'
    show castRenderCacheDirectoryProvider;
import 'package:dance_learning_app/cast/cast_render_executor.dart'
    show castRenderExecutorProvider;
import 'package:dance_learning_app/cast/cast_render_request.dart'
    show CastSpeedTier;
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
import 'package:dance_learning_app/player/av_sync.dart'
    show
        AudioOutputDeviceController,
        AvSyncDeviceInfo,
        audioOutputDeviceControllerProvider;
import 'package:dance_learning_app/player/av_sync_session.dart'
    show avSyncCalibrationSessionProvider;
import 'package:dance_learning_app/player/compare_recording.dart'
    show CompareRecordingPhase, compareRecordingPhaseProvider;
import 'package:dance_learning_app/player/cast_prep_panel.dart'
    show castPrepTierKey;
import 'package:dance_learning_app/player/cast_run.dart' show castRunProvider;
import 'package:dance_learning_app/player/cast_speed_panel.dart'
    show castSpeedOptionKey, kCastSpeedSwitchingText, kCastSpeedWaitText;
import 'package:dance_learning_app/player/control_layer.dart'
    show kAnnotationToolRowKey;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kToolSlotDisabledIconColor;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_render_executor.dart';
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
/// （底排无槽位、轨道带只留分段轨、顶栏四枚）→ 断开 / 系统返回 / 离开页面；
/// 以及投屏态顶栏那枚**系统镜像**入口（先断开再跳、降级链走不通给一句短暂
/// 提示）与那枚**画面开关**（黑底 ↔ 静音本地预览）。
/// 接收端经 #23 的脚本化替身注入，不碰真网络；原生与真机行为留真机验收
/// （见 `lib/cast/docs/real-device-acceptance.md`）。
void main() {
  late FakePlaybackEngine engine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late FakeCastReceiverDiscovery discovery;
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannelFactory delivery;
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
    FakeVideoCopyPresence? presence,
    List<Override> extraOverrides = const [],
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
                  // 「换视频」用例要开的另一支舞（同一个索引里两份条目）。
                  if (source.toFilePath() != '/videos/b.mp4')
                    historyEntry(filePath: '/videos/b.mp4', mirrored: false),
                ],
              ),
            ),
          ),
          castReceiverDiscoveryProvider.overrideWithValue(discovery),
          castSessionFactoryProvider.overrideWithValue(factory),
          castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
          systemMirrorLauncherProvider.overrideWithValue(systemMirror),
          videoCopyPresenceProvider.overrideWithValue(
            presence ?? FakeVideoCopyPresence(),
          ),
          ...extraOverrides,
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

  /// 从编辑态起投：点投屏工具 → 面板 → **两个勾选都取消（都不勾 = 直接推
  /// 原片）** → 选客厅电视。投屏态这一票的用例只关心会话与换装，不把真渲染
  /// 拉进来（渲染链的宿主测试在 `cast_prep_panel_test.dart`）。
  Future<void> startCast(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
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
    delivery = FakeCastDeliveryChannelFactory();
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

    // 顶栏换装：倍速切换 + 画面开关 + 断开投屏 + 系统镜像 + 查看引导（编辑态
    // 那枚投屏不在场）。
    expect(find.byKey(const Key('tool_cast_speed')), findsOneWidget);
    expect(find.text('倍速切换'), findsOneWidget);
    expect(find.byKey(const Key('tool_cast_picture')), findsOneWidget);
    expect(find.text('画面开关'), findsOneWidget);
    expect(find.byKey(const Key('tool_cast_disconnect')), findsOneWidget);
    expect(find.text('断开投屏'), findsOneWidget);
    expect(find.byKey(const Key('tool_system_mirror')), findsOneWidget);
    expect(find.text('系统镜像'), findsOneWidget);
    expect(find.byKey(const Key('tool_guide')), findsOneWidget);
    expect(find.byKey(const Key('tool_cast')), findsNothing);
    expect(find.byKey(const Key('tool_compare')), findsNothing);
    // 投屏态对两条既有互斥的明确回答：音画同步校准与录制/取景那几枚入口
    // 结构性不在场（投屏期不改任何会被渲染的设置、也不与校准抢播放）。
    expect(find.byKey(const Key('tool_av_sync')), findsNothing);
    expect(find.byKey(const Key('tool_framing_adjust')), findsNothing);
    expect(find.byKey(const Key('tool_mirror')), findsNothing);
    expect(find.byKey(const Key('tool_speed_settings')), findsNothing);

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

  // ---- 投屏倍速档切换（票 #31）：一档一份、换文件续播 ----

  testWidgets('投屏态倍速切换：面板列三档、未渲好的不可点；点已渲好的换文件续播、有过程态', (tester) async {
    setWideView(tester);
    final root = Directory.systemTemp.createTempSync('cast_mode_speed');
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    final executor = FakeCastRenderExecutor();
    // 起投档（面板里渲的那一份）放行，后台渲 0.5× 那一档挂住——只有它才是
    // 「还没渲好」的样子。
    executor.runGate = Completer<void>();
    executor.gateFromRun = 1;
    // 进度分母是**产物**的时长：30 秒素材在 0.5× 档上是 60 秒的副本，
    // 走到 30 秒即一半（分母错用源时长会在这一刻读到 100%）。
    executor.progressScript = const [Duration(seconds: 30)];

    await pumpPlayer(
      tester,
      extraOverrides: [
        castRenderExecutorProvider.overrideWithValue(executor),
        castRenderCacheDirectoryProvider.overrideWithValue(() async => root),
      ],
    );
    await openControlLayer(tester);

    // 准备：勾上 0.5×（默认就近的是 1×），只勾画面类（widget 假时钟下不做
    // 异步的拍声轨写盘）。
    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_receiver_udn-$receiverName')));
    await tester.pumpAndSettle();

    // 起投档渲好即开投：推的是它那一份，其余档在后台接着渲。
    expect(modeOf(tester), PlayerSessionMode.castControl);
    expect(factory.sessions.single.calls, ['push', 'play']);
    expect(
      containerOf(tester).read(castRunProvider).activeTier,
      CastSpeedTier.full,
    );
    // 倍速步进结构性不在场：那枚「倍速设置」不在投屏态顶栏。
    expect(find.byKey(const Key('tool_speed_settings')), findsNothing);
    expect(find.text('倍速步进'), findsNothing);

    await tester.tap(find.byKey(const Key('tool_cast_speed')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cast_speed_panel')), findsOneWidget);
    expect(find.text('正在播'), findsOneWidget, reason: '1× 那一档正在电视上放');
    expect(find.text('准备中 50%'), findsOneWidget, reason: '0.5× 那一档的进度');
    expect(
      find.text(kCastSpeedWaitText),
      findsOneWidget,
      reason: '起播等待与跳转精度不由我们决定这条事实写进文案',
    );

    // 未渲好的档不可点：点它什么都不发生。
    await tester.tap(find.byKey(castSpeedOptionKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();
    expect(factory.sessions.single.pushes, hasLength(1), reason: '没换文件');
    expect(
      containerOf(tester).read(castRunProvider).activeTier,
      CastSpeedTier.full,
    );

    // 渲好即变可切。
    executor.runGate!.complete();
    for (var i = 0; i < 200; i++) {
      final ready = containerOf(tester)
          .read(castRunProvider)
          .canSwitchTo(CastSpeedTier.half);
      if (ready) break;
      await tester.pump(const Duration(milliseconds: 1));
    }
    expect(
      containerOf(tester).read(castRunProvider).canSwitchTo(CastSpeedTier.half),
      isTrue,
    );
    await tester.pumpAndSettle();
    expect(find.text('可切'), findsOneWidget);

    // 换档：过程态在场，成功前当前档不翻。
    final pushGate = Completer<void>();
    factory.sessions.single.pushGate = pushGate;
    await tester.tap(find.byKey(castSpeedOptionKey(CastSpeedTier.half)));
    await tester.pump();
    await tester.pump();
    expect(
      find.byKey(const Key('cast_speed_switching')),
      findsOneWidget,
      reason: '切换有明确过程态',
    );
    expect(find.text(kCastSpeedSwitchingText), findsOneWidget);
    expect(
      containerOf(tester).read(castRunProvider).activeTier,
      CastSpeedTier.full,
    );

    pushGate.complete();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cast_speed_panel')), findsNothing);
    expect(
      containerOf(tester).read(castRunProvider).activeTier,
      CastSpeedTier.half,
    );
    expect(delivery.served, hasLength(2), reason: '换档 = 让接收端换一个文件播');
    expect(factory.sessions.single.calls, [
      'push',
      'play',
      'position',
      'push',
      'seek',
      'play',
    ]);
  });

  // ---- 投屏入口的五条门（票 #35）：置灰 + 按下去只解释原因 ----

  /// 顶栏工具槽内第一个 Icon 的颜色（置灰 = 不可用视觉 token）。
  Color toolIconColor(WidgetTester tester, String toolKey) => tester
      .widget<Icon>(
        find.descendant(
          of: find.byKey(Key(toolKey)),
          matching: find.byType(Icon),
        ),
      )
      .color!;

  /// 灰着那枚按下去：弹原因、什么都不做（不落待办、不开面板、不起通道、
  /// 不连会话、模式值一位不动）。
  Future<void> pressBlockedCast(WidgetTester tester, String reason) async {
    expect(
      toolIconColor(tester, 'tool_cast'),
      kToolSlotDisabledIconColor,
      reason: '门命中时入口要置灰',
    );
    final modeBefore = modeOf(tester);

    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pump();

    expect(find.byKey(const Key('cast_entry_blocked_prompt')), findsOneWidget);
    expect(find.text(reason), findsOneWidget);
    expect(find.byKey(const Key('cast_prep_panel')), findsNothing);
    expect(
      containerOf(tester).read(playerSessionProvider).pendingEntry,
      isNull,
    );
    expect(modeOf(tester), modeBefore, reason: '模式值一位不动');
    expect(discovery.discoverCalls, 0);
    expect(delivery.served, isEmpty);
    expect(factory.connectCalls, 0);
  }

  testWidgets('门①副本丢失：入口置灰、按下去只解释原因', (tester) async {
    setWideView(tester);
    await pumpPlayer(
      tester,
      presence: FakeVideoCopyPresence(missingPaths: const {'/videos/a.mp4'}),
    );
    await openControlLayer(tester);

    await pressBlockedCast(tester, '这支舞的视频副本不在本机，先把副本找回来再投屏');
  });

  testWidgets('门②音画同步校准中：入口置灰、按下去只解释原因', (tester) async {
    setWideView(tester);
    await pumpPlayer(
      tester,
      extraOverrides: [
        audioOutputDeviceControllerProvider.overrideWithValue(_NoAudioDevice()),
      ],
    );
    await openControlLayer(tester);

    await containerOf(tester)
        .read(avSyncCalibrationSessionProvider.notifier)
        .enter();
    await tester.pumpAndSettle();

    await pressBlockedCast(tester, '音画同步校准中，先退出校准再投屏');
  });

  testWidgets('门③录制中或录制准备中：两值都置灰、按下去只解释原因', (tester) async {
    for (final phase in const [
      CompareRecordingPhase.preparing,
      CompareRecordingPhase.recording,
    ]) {
      setWideView(tester);
      await pumpPlayer(tester);
      await openControlLayer(tester);

      containerOf(tester)
          .read(compareRecordingPhaseProvider.notifier)
          .set(phase);
      await tester.pumpAndSettle();

      expect(
        toolIconColor(tester, 'tool_cast'),
        kToolSlotDisabledIconColor,
        reason: '$phase',
      );

      await tester.tap(find.byKey(const Key('tool_cast')));
      await tester.pump();
      expect(find.text('录制中（含准备中）不能投屏，先停录'), findsOneWidget);
      expect(find.byKey(const Key('cast_prep_panel')), findsNothing);
      expect(
        containerOf(tester).read(playerSessionProvider).pendingEntry,
        isNull,
      );

      // 本页拆掉再放下一个相位：两棵树不互相串状态。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('门④对比态：入口置灰、按下去只解释原因（对比-控制层里那枚还在）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);

    containerOf(tester)
        .read(playerSessionProvider.notifier)
        .enter(PlayerSessionMode.compareEditing);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tool_cast')), findsOneWidget);
    await pressBlockedCast(tester, '先退出对比或取景调整，再投屏');
  });

  testWidgets('门⑤渲染进行中：入口置灰、按下去只解释原因', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);

    containerOf(tester).read(castRenderInProgressProvider.notifier).begin();
    await tester.pumpAndSettle();

    await pressBlockedCast(tester, '正在渲染投屏副本，渲完再投');
  });

  testWidgets('门都不命中：入口正常、点得开准备面板（门不是拦路虎）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);

    expect(
      toolIconColor(tester, 'tool_cast'),
      isNot(kToolSlotDisabledIconColor),
    );
    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(find.byKey(const Key('cast_entry_blocked_prompt')), findsNothing);
  });

  // ---- 失败分流（票 #35）：会话没建立起来的失败 ----

  testWidgets('搜不到接收端：准备面板当场说明同一 Wi-Fi / 访客网络，并把重扫留在眼前', (tester) async {
    setWideView(tester);
    discovery = FakeCastReceiverDiscovery(script: [const []]);
    await pumpPlayer(tester);
    await openControlLayer(tester);

    await tester.tap(find.byKey(const Key('tool_cast')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(find.text('没找到接收端：手机与电视要在同一个 Wi-Fi，电视别开访客网络'), findsOneWidget);
    expect(find.byKey(const Key('cast_prep_refresh')), findsOneWidget);
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(delivery.served, isEmpty);
  });

  testWidgets('推片被拒：短暂提示 + 停在编辑态、通道零残留', (tester) async {
    setWideView(tester);
    factory.configure = (session) =>
        session.pushError = const CastActionRefused('拒播');
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('cast_not_started_prompt')), findsOneWidget);
    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(
      containerOf(tester).read(playerSessionProvider).pendingEntry,
      isNull,
    );
  });

  testWidgets('递出通道起不来：短暂提示 + 停在编辑态、零残留', (tester) async {
    setWideView(tester);
    delivery.serveError = StateError('没有可用的局域网地址');
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byKey(const Key('cast_not_started_prompt')), findsOneWidget);
    expect(factory.connectCalls, 0, reason: '通道没起起来就不连接收端');
    expect(
      containerOf(tester).read(playerSessionProvider).pendingEntry,
      isNull,
    );
  });

  // ---- 断开触发点收在既有复位一处 ----

  testWidgets('系统返回两级：投屏-观看态内先断开回编辑态、再按一次才离开页面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    containerOf(tester).read(playerSessionProvider.notifier).collapse();
    await tester.pumpAndSettle();
    expect(modeOf(tester), PlayerSessionMode.castWatching);

    final first = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(first, isTrue);
    expect(factory.sessions.single.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(find.byType(PlayerPage), findsOneWidget, reason: '第一次不离开页面');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing, reason: '第二次离开页面');
  });

  testWidgets('换视频：上一支舞的投屏断开并停服（与离开页面同一个复位触发点）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final first = factory.sessions.single;
    expect(modeOf(tester), PlayerSessionMode.castControl);

    // 换视频：在播放页之上再开一支舞——新页的打开恢复经既有复位一处。
    unawaited(
      Navigator.of(tester.element(find.byType(PlayerPage))).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerPage(source: Uri.file('/videos/b.mp4')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(first.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(modeOf(tester), PlayerSessionMode.watching, reason: '复位回观看态');
    expect(find.byKey(const Key('tool_cast_disconnect')), findsNothing);
  });

  // ---- 失败分流：会话建立之后的失败 ----

  testWidgets('电视端停止：回前台问一次状态，那边停了就断开回编辑态并给短暂提示', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;
    // 电视那边被按了停（或片子被卸了）：App 退后台再回来才知道。
    cast.reportedState = CastPlaybackState.stopped;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(cast.calls, contains('playbackState'), reason: '回前台问的就是接收端');
    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(cast.disconnected, isTrue);
    expect(delivery.closed, isTrue);
    expect(find.byKey(const Key('cast_interrupted_prompt')), findsOneWidget);
  });

  testWidgets('电视端还在播：回前台问一次，投屏一位不动', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(modeOf(tester), PlayerSessionMode.castControl);
    expect(cast.disconnected, isFalse);
    expect(delivery.closed, isFalse);
    expect(find.byKey(const Key('cast_interrupted_prompt')), findsNothing);
  });
}

/// 无输出设备替身（校准会话进入流程不碰平台通道）。
class _NoAudioDevice implements AudioOutputDeviceController {
  @override
  Future<AvSyncDeviceInfo?> get() async => null;

  @override
  Stream<AvSyncDeviceInfo?> get deviceStream => const Stream.empty();
}
