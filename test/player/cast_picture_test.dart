import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart'
    show CastActionRefused, CastSessionDropped;
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_screen_awake.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/camera_capture/camera_capture.dart';
import 'package:dance_learning_app/core/private_json.dart'
    show privateJsonStorageProvider;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/player/beat_analysis.dart'
    show beatAnalysisPipelineProvider;
import 'package:dance_learning_app/player/cast_preview.dart'
    show castPreviewEngineProvider, castPreviewProvider;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlay;
import 'package:dance_learning_app/player/note_sticker_overlay.dart'
    show NoteStickerOverlay;
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/persistence/material_manifest.dart'
    show materialRecordingFileResolverProvider;
import 'package:dance_learning_app/persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/beat_test_seam.dart'
    show hangingBeatPipeline, turnBeatAnimationOn;
import '../helpers/fake_camera_capture_service.dart';
import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_screen_awake.dart';
import '../helpers/fake_cast_session.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/fake_video_copy_presence.dart';
import '../helpers/fixed_hasher.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';
import '../helpers/video_surface.dart'
    show VideoSurfacePlaceholder, videoSurfacePlaceholderKey;

/// 投屏态的画面开关与投屏胶囊（票 #32，规格 #21）：
///
/// - 画面区默认**黑底 + 一行指路提示**（源片不上屏），顶栏那枚**画面开关**
///   打开后切到**静音本地预览**；
/// - 预览是**与主内核并列的兄弟播放**：按**接收端上报的当前位置**定位后
///   静音起播，只画视频画面本身（不含贴纸 / 数拍 / 节拍动画）、不可交互；
/// - 播放控件始终遥控电视，**不被本地预览驱动、也不反向驱动它**；
/// - 投屏-观看态屏上留一枚**只作状态提示、点不动**的投屏胶囊；点画面即
///   展开回控制层（走既有画面点按路径）。
///
/// 另有**投屏期屏幕常亮**（#39）那几条：画面开关在场不重复持有、收起不放掉，
/// 以及「再确认落在源画面件退场之后」——源画面件退场时会放开同一个平台开关，
/// 那条时序就是投屏期不熄屏的判据。
///
/// 接收端经 #23 的脚本化替身注入，预览内核是第二只 FakePlaybackEngine
/// （与 `practiceClipEngineProvider` 同款兄弟实例手法），不碰真网络与真解码。
void main() {
  late FakePlaybackEngine engine;
  late FakePlaybackEngine previewEngine;
  late FakeSystemUi systemUi;
  late FakeCameraCaptureService camera;
  late FakeCastReceiverDiscovery discovery;
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannelFactory delivery;
  late FakeCastScreenAwake awake;

  /// 唤醒的拿 / 放 / 再确认与**源画面件退场**共用的时序表（票 #39：顺序本身就
  /// 是那条「退场那一次放开不能踩掉投屏期常亮」的判据）。
  late List<String> timeline;

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
          // 画面开关的预览播放：与主内核并列的兄弟实例。替身按生产同款接线
          // 释放（容器销毁即 dispose——否则它那条播放节拍会留在 fake 时钟里）。
          castPreviewEngineProvider.overrideWith((ref) {
            ref.onDispose(previewEngine.dispose);
            return previewEngine;
          }),
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
          castDeliveryChannelFactoryProvider.overrideWithValue(delivery.call),
          // 投屏期屏幕唤醒（#39）：替身记录拿 / 放次数——真平台上「屏幕到底
          // 熄不熄」归真机验收，这里钉的是「谁在什么时候拿、什么时候放」。
          castScreenAwakeProvider.overrideWithValue(awake),
          videoCopyPresenceProvider.overrideWithValue(FakeVideoCopyPresence()),
          // 节拍分析挂起：数拍浮层的显隐由测试自行置开（画面开关那条断言
          // 要的是「投屏态不挂它」，不是分析结果）。
          beatAnalysisPipelineProvider.overrideWithValue(hangingBeatPipeline),
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
  /// 原片）** → 选客厅电视。画面开关这一票的用例只关心投屏态的画面区，不把
  /// 真渲染拉进来（渲染链的宿主测试在 `cast_prep_panel_test.dart`）。
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

  /// 打开画面开关（投屏态顶栏那枚）。
  Future<void> turnPictureOn(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tool_cast_picture')));
    await tester.pumpAndSettle();
  }

  /// 投屏-控制层 → 投屏-观看态（收起控制层）。
  Future<void> collapseToCastWatching(WidgetTester tester) async {
    containerOf(tester).read(playerSessionProvider.notifier).collapse();
    await tester.pumpAndSettle();
  }

  setUp(() {
    timeline = [];
    // 主内核的画面件替身：退场时往时序表记一笔（真内核那份画面件在 dispose 时
    // 会放开同一个平台开关——本文件的 #39 用例要看的正是那一刻的先后）。
    engine = _WakeReleasingEngine(
      log: timeline,
      duration: const Duration(seconds: 30),
    );
    previewEngine = FakePlaybackEngine(
      duration: const Duration(seconds: 30),
      videoAspectRatio: 16 / 9,
    );
    systemUi = FakeSystemUi();
    camera = FakeCameraCaptureService();
    discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver()],
      ],
    );
    factory = FakeCastSessionFactory();
    delivery = FakeCastDeliveryChannelFactory();
    awake = FakeCastScreenAwake(onCall: timeline.add);
  });

  testWidgets('画面区默认黑底 + 指路提示；开关打开后才出现本地画面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 默认：黑底 + 一行指路提示，源片不上屏（画面区不画视频画面）。
    expect(find.byKey(const Key('cast_picture_area')), findsOneWidget);
    expect(find.byKey(const Key('cast_picture_hint')), findsOneWidget);
    expect(find.byKey(videoSurfacePlaceholderKey), findsNothing);
    expect(find.byKey(const Key('cast_preview_surface')), findsNothing);
    expect(previewEngine.source, isNull, reason: '没开开关就不起预览播放');

    // 开关打开：本地画面出现、提示退场。
    await turnPictureOn(tester);
    expect(find.byKey(const Key('cast_picture_hint')), findsNothing);
    expect(find.byKey(const Key('cast_preview_surface')), findsOneWidget);
    expect(
      find.byKey(videoSurfacePlaceholderKey),
      findsOneWidget,
      reason: '画面区这时画的是预览内核那条画面',
    );

    // 再关一次：回黑底 + 指路。
    await turnPictureOn(tester);
    expect(find.byKey(const Key('cast_picture_hint')), findsOneWidget);
    expect(find.byKey(const Key('cast_preview_surface')), findsNothing);
  });

  testWidgets('投屏期手机不出声：主内核静音、预览静音，离开投屏恢复', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 投屏期手机是遥控器：主内核先静音（不然电视与手机同时出声）。
    expect(engine.muted, isTrue, reason: '声音归电视');
    expect(previewEngine.mutedCalls, isEmpty, reason: '还没开画面开关');

    await turnPictureOn(tester);
    expect(previewEngine.muted, isTrue, reason: '预览只给眼睛看');
    expect(previewEngine.mutedCalls, [true]);

    await tester.tap(find.byKey(const Key('tool_cast_disconnect')));
    await tester.pumpAndSettle();
    expect(engine.muted, isFalse, reason: '离开投屏态恢复本机声音');
  });

  testWidgets('预览的起播位置 = 接收端上报位置；不给「对齐」之类的额外操作', (tester) async {
    setWideView(tester);
    factory.configure = (session) =>
        session.reportedPosition = const Duration(seconds: 12);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;

    await turnPictureOn(tester);

    expect(cast.calls, contains('position'), reason: '起播位置问接收端要');
    expect(previewEngine.seekCalls, [const Duration(seconds: 12)]);
    expect(previewEngine.isPlaying, isTrue, reason: '定位后静音起播');

    // 每次打开都重问一次当前位置（电视那边可能已经走远了）。
    cast.reportedPosition = const Duration(seconds: 20);
    await turnPictureOn(tester);
    await turnPictureOn(tester);
    expect(previewEngine.seekCalls, [
      const Duration(seconds: 12),
      const Duration(seconds: 20),
    ]);

    // 画面区只有画面本身：没有按钮、没有「对齐」这类额外操作。
    expect(
      find.descendant(
        of: find.byKey(const Key('cast_picture_area')),
        matching: find.byType(InkWell),
      ),
      findsNothing,
    );
    expect(find.textContaining('对齐'), findsNothing);
  });

  testWidgets('预览只画视频画面本身：不含贴纸 / 数拍 / 节拍动画', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    // 编辑态布景：数拍浮层与备注贴纸浮层都在场（否则「投屏态不挂」是空断言）。
    turnBeatAnimationOn(tester);
    await tester.pumpAndSettle();
    expect(find.byType(MetronomeOverlay), findsOneWidget);
    expect(find.byType(NoteStickerOverlay), findsOneWidget);

    await openControlLayer(tester);
    await startCast(tester);
    await turnPictureOn(tester);

    expect(find.byType(MetronomeOverlay), findsNothing, reason: '数拍与节拍动画已在电视上');
    expect(find.byType(NoteStickerOverlay), findsNothing, reason: '贴纸已在电视上');
  });

  testWidgets('预览不可交互：手势只走遥控那条路，预览内核不被驱动', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    await turnPictureOn(tester);
    final cast = factory.sessions.single;
    final previewCallsBefore = [...previewEngine.callLog];
    final previewSeeksBefore = [...previewEngine.seekCalls];

    // 预览件自身没有任何手势识别件（点按落到底层那条既有手势面）。
    expect(
      find.descendant(
        of: find.byKey(const Key('cast_preview_surface')),
        matching: find.byType(GestureDetector),
      ),
      findsNothing,
    );

    // 收起控制层到投屏-观看态：画面中央单指横向拖（既有遥控路径）。
    await collapseToCastWatching(tester);
    final gesture = await tester.startGesture(const Offset(480, 270));
    for (var i = 0; i < 4; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(cast.seeks, hasLength(1), reason: '拖动照旧遥控电视（既有路径）');
    expect(
      previewEngine.callLog,
      previewCallsBefore,
      reason: '预览内核不因画面上的手势被驱动',
    );
    expect(previewEngine.seekCalls, previewSeeksBefore);
  });

  testWidgets('播放控件始终遥控电视：不被本地预览驱动、也不反向驱动它', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final mainCallsBefore = [...engine.callLog];
    final mainSeeksBefore = [...engine.seekCalls];
    final cast = factory.sessions.single;

    await turnPictureOn(tester);

    // 打开画面开关只动预览那侧：主内核（播放控件的真实来源）一位不动。
    expect(engine.callLog, mainCallsBefore, reason: '预览不被控件驱动，也不反向驱动控件那条路');
    expect(engine.seekCalls, mainSeeksBefore);
    expect(previewEngine.isPlaying, isTrue);

    // 底排播放键：主内核与电视一起暂停；预览照旧在放（控件不反向驱动它）。
    await tester.tap(find.byKey(const Key('toolbar_play')));
    await tester.pumpAndSettle();

    expect(cast.calls, contains('pause'), reason: '控件遥控电视');
    expect(engine.isPlaying, isFalse);
    expect(previewEngine.isPlaying, isTrue, reason: '预览不被播放控件驱动（它与控件是两条路）');
  });

  testWidgets('投屏胶囊：只作状态提示、零命中——点它不产生任何状态变化', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    await turnPictureOn(tester);
    await collapseToCastWatching(tester);
    final cast = factory.sessions.single;
    final previewCallsBefore = [...previewEngine.callLog];

    final capsule = find.byKey(const Key('cast_status_capsule'));
    expect(capsule, findsOneWidget);
    expect(find.text('投屏中 · $receiverName'), findsOneWidget);
    // 胶囊自身没有任何手势识别件（「不接任何手势」）。
    expect(
      find.descendant(of: capsule, matching: find.byType(GestureDetector)),
      findsNothing,
    );

    await tester.tapAt(tester.getCenter(capsule));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(
      modeOf(tester),
      PlayerSessionMode.castWatching,
      reason: '点胶囊不产生任何状态变化（防误触）',
    );
    expect(cast.disconnected, isFalse, reason: '没把投屏断了');
    expect(previewEngine.callLog, previewCallsBefore, reason: '预览也不被动');
  });

  testWidgets('点画面从投屏-观看态展开回控制层（走既有画面点按路径）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    await collapseToCastWatching(tester);
    expect(modeOf(tester), PlayerSessionMode.castWatching);

    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(modeOf(tester), PlayerSessionMode.castControl);
    expect(
      find.byKey(const Key('tool_cast_picture')),
      findsOneWidget,
      reason: '展开回来的就是投屏-控制层（顶栏那三枚在场）',
    );
  });

  testWidgets('问不到接收端位置（设备这一问答不上）：静默降级、从头起', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;
    // 会话还在，但这一问被回绝（设备不报位置一类）。
    cast.positionError = const CastActionRefused('设备不报位置');

    await turnPictureOn(tester);

    expect(modeOf(tester), PlayerSessionMode.castControl, reason: '投屏照旧');
    expect(cast.disconnected, isFalse);
    expect(previewEngine.seekCalls, [Duration.zero], reason: '问不到就从头起（静默降级）');
    expect(previewEngine.isPlaying, isTrue);
  });

  testWidgets('问不到接收端位置（连接断了）：走既有失败收口，不留半开的面', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    final cast = factory.sessions.single;
    cast.positionError = const CastSessionDropped('设备掉线');

    await turnPictureOn(tester);

    expect(modeOf(tester), PlayerSessionMode.editing, reason: '失败一律回编辑态');
    expect(find.byKey(const Key('cast_interrupted_prompt')), findsOneWidget);
    expect(cast.disconnected, isTrue);
    expect(delivery.closed, isTrue, reason: '递出通道随收口立即停服');
    expect(previewEngine.source, isNull, reason: '没定位成功就不起预览（黑底 + 指路提示原样）');
  });

  testWidgets('离开投屏态：预览收起来、开关回默认关', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    await turnPictureOn(tester);
    expect(previewEngine.isPlaying, isTrue);

    await tester.tap(find.byKey(const Key('tool_cast_disconnect')));
    await tester.pumpAndSettle();

    expect(modeOf(tester), PlayerSessionMode.editing);
    expect(previewEngine.isPlaying, isFalse, reason: '离开投屏态即收预览');
    expect(previewEngine.callLog, contains('pause'));
    expect(containerOf(tester).read(castPreviewProvider), isFalse);
    expect(find.byKey(const Key('cast_picture_area')), findsNothing);
  });

  testWidgets('投屏期屏幕常亮：画面开关在场不重复持有、收起不放掉（#39）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 进投屏态持有一次；画面区接管那一帧的帧末再确认一次——退场的源画面件
    // 在同一帧收尾时会放开**同一个**平台开关（它不是引用计数的），不补按这
    // 一下，投屏期照样会熄。
    expect(awake.calls, ['hold', 'reassert'], reason: '进投屏态持有 + 画面区接管那一帧末再确认');
    expect(awake.held, 1, reason: '再确认不是第二份持有');

    // 画面开关打开：本地预览在场。投屏期那份唤醒**还是那一份**——预览件不在
    // 唤醒上再插一手（生产装配里它那只内核 `holdsScreenAwake: false`，见
    // `test/cast/cast_screen_awake_test.dart` 的结构护栏）。
    await turnPictureOn(tester);
    expect(awake.calls, ['hold', 'reassert'], reason: '画面开关在场不重复持有');
    expect(awake.held, 1);
    expect(awake.releaseCalls, 0);

    // 收起画面开关：只收预览，不放掉投屏那一份（两处打在同一个平台开关上
    // 就会互相打架——投屏期屏幕照旧不该熄）。
    await turnPictureOn(tester);
    expect(awake.calls, ['hold', 'reassert'], reason: '收起预览不放掉投屏那一份');
    expect(awake.held, 1);

    await tester.tap(find.byKey(const Key('tool_cast_disconnect')));
    await tester.pumpAndSettle();

    expect(awake.calls, ['hold', 'reassert', 'release'], reason: '离开投屏态才放掉');
    expect(awake.held, 0, reason: '断开后恢复系统行为');
  });

  testWidgets('投屏-观看态来回切换不重挂画面区：唤醒不再重复确认（#39）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);
    expect(awake.reassertCalls, 1);

    // 收起控制层 → 投屏-观看态 → 再点画面展开回控制层：画面区始终是同一个
    // 元素（只有控制层在换装），唤醒不该被反复再确认。
    await collapseToCastWatching(tester);
    await tester.tap(find.byKey(const Key('player_surface')));
    await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
    await tester.pumpAndSettle();

    expect(modeOf(tester), PlayerSessionMode.castControl);
    expect(awake.calls, ['hold', 'reassert'], reason: '画面区不重挂，唤醒不再重复确认');
  });

  testWidgets('再确认落在源画面件退场之后：退场那一次放开踩不掉投屏期常亮（#39）', (tester) async {
    setWideView(tester);
    await pumpPlayer(tester);
    await openControlLayer(tester);
    await startCast(tester);

    // 真内核的画面件在 dispose 时会放开自己那份唤醒，打的是**同一个**平台开关
    // （那个开关不是引用计数的）——那一刻在替身上对应 `source_surface_dispose`
    // 这一笔。投屏期的常亮因此必须在那之后**再确认一次**。
    expect(timeline, [
      'hold',
      'source_surface_dispose',
      'reassert',
    ], reason: '顺序就是判据：起投持有 → 源画面件退场（放开同一个开关）→ 再确认');
  });
}

/// 主内核替身：**画面件退场时往 [log] 记一笔**——真内核（media_kit）的画面件
/// 在 dispose 时会放开自己那份唤醒，打的是投屏侧同一个平台开关。#39 那条
/// 「再确认必须落在源画面件退场之后」的用例靠它把两件事放进同一条时序表。
class _WakeReleasingEngine extends FakePlaybackEngine {
  _WakeReleasingEngine({required this.log, super.duration});

  final List<String> log;

  @override
  Widget buildVideoSurface() => _WakeReleasingSurface(log: log);
}

class _WakeReleasingSurface extends StatefulWidget {
  const _WakeReleasingSurface({required this.log});

  final List<String> log;

  @override
  State<_WakeReleasingSurface> createState() => _WakeReleasingSurfaceState();
}

class _WakeReleasingSurfaceState extends State<_WakeReleasingSurface> {
  @override
  void dispose() {
    widget.log.add('source_surface_dispose');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      const VideoSurfacePlaceholder(videoAspectRatio: null);
}
