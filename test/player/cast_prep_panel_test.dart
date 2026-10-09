import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/cast_range_gate.dart' show CastRange;
import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_speed_tier.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/cast/encoder_realtime_capability.dart';
import 'package:dance_learning_app/cast/system_mirror.dart'
    show systemMirrorLauncherProvider;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/persistence/local_document.dart'
    show CastPrepMemoryFields, LocalDocument;
import 'package:dance_learning_app/player/cast_prep_memory.dart';
import 'package:dance_learning_app/player/cast_prep_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_render_executor.dart';
import '../helpers/fake_encoder_realtime_capability.dart';
import '../helpers/fake_system_mirror_launcher.dart';
import '../helpers/fake_video_copy_presence.dart';

/// 投屏准备面板直测：两个勾选档与三句实话、列接收端、可重扫、两条门
/// （副本丢失 / 发现不到接收端）当场拦下并说明；「搜不到接收端」空态里还有
/// **同一条系统镜像入口**（与投屏态顶栏那枚同一个动作、同一份文案）；选中一台
/// 即渲染并把**接收端 + 要推的文件**带出（渲好即带出产物，可取消、失败给一句）；
/// **编码器保证不了 1× 实时**时当场说一句、并把请求按 720p 档装配（#36）。
///
/// 渲染链路经脚本化执行器与临时目录注入——widget 测试的假时钟下不做异步文件
/// IO，所以「真渲一次」的路径由 `cast_render_orchestrator_test.dart` 覆盖，
/// 这里覆盖面板看得见的行为。
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

  late Directory root;
  late FakeCastRenderExecutor executor;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cast_prep_panel_test');
    executor = FakeCastRenderExecutor();
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// 这支舞的**首尾线**（源时间轴上的半开区间 #37）：`null` = 未设（整片）。
  /// 面板那句「这一档收不住首尾线」正看这一样。
  const rangeStart = Duration(seconds: 1);
  const rangeEnd = Duration(seconds: 3);
  const setRange = CastRange(start: rangeStart, end: rangeEnd);

  CastRenderRequest request(
    CastRenderChoices choices, [
    CastSpeedTier tier = CastSpeedTier.full,
    CastRenderResolution resolution = CastRenderResolution.source,
  ]) => CastRenderRequest(
    videoPath: filePath,
    videoId: 'vid-a',
    duration: const Duration(seconds: 4),
    choices: choices,
    speedTier: tier,
    resolution: resolution,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
  );

  /// 设了首尾线（1s–3s，半开）的那份请求：复制档 + 有范围 = 那句实话的现场。
  CastRenderRequest requestWithRange(
    CastRenderChoices choices, [
    CastSpeedTier tier = CastSpeedTier.full,
    CastRenderResolution resolution = CastRenderResolution.source,
  ]) => CastRenderRequest(
    videoPath: filePath,
    videoId: 'vid-a',
    duration: const Duration(seconds: 4),
    choices: choices,
    speedTier: tier,
    resolution: resolution,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
    range: setRange,
  );

  /// 面板宿主：按钮开面板、把出参记进通知器。
  Future<void> pumpHost(
    WidgetTester tester, {
    required FakeCastReceiverDiscovery discovery,
    required FakeVideoCopyPresence presence,
    required ValueNotifier<CastPrepOutcome?> picked,
    CastRenderRequest Function(
      CastRenderChoices choices,
      CastSpeedTier tier,
      CastRenderResolution resolution,
    )?
    requestOf,
    double manualRate = 1,
    FakeSystemMirrorLauncher? systemMirror,
    CastPrepMemoryPort? memory,
    FakeEncoderRealtimeCapability? capability,
    // riverpod 3.4.2 未公开导出 Override 类型（与 settings_persistence_test
    // 同款）：用 List<dynamic> 承接，展开处照常判类型。
    List<dynamic> extraOverrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          castReceiverDiscoveryProvider.overrideWithValue(discovery),
          videoCopyPresenceProvider.overrideWithValue(presence),
          castRenderExecutorProvider.overrideWithValue(executor),
          castRenderCacheDirectoryProvider.overrideWithValue(() async => root),
          // 缺省：这台机器保证 1× 实时（按源分辨率渲、不出降级那一句）——
          // 要验降级的用例各自注入别的答案。
          castEncoderRealtimeCapabilityProvider.overrideWithValue(
            capability ?? FakeEncoderRealtimeCapability(),
          ),
          systemMirrorLauncherProvider.overrideWithValue(
            systemMirror ?? FakeSystemMirrorLauncher(),
          ),
          ...extraOverrides,
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                key: const Key('open_panel'),
                onPressed: () async {
                  picked.value = await showDialog<CastPrepOutcome>(
                    context: context,
                    builder: (_) => CastPrepPanel(
                      videoFilePath: filePath,
                      manualRate: manualRate,
                      requestOf: requestOf ?? request,
                      memory: memory,
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

  /// 等一个条件成立：靠 `pump` 推进假时钟（widget 测试里 `Future.delayed`
  /// 不自己走）。
  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    if (!ready()) fail('等不到条件成立');
  }

  testWidgets('列出发现到的接收端；都不勾 = 直接带出原片', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视'), receiver('卧室盒子')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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

    // 两个勾选都取消 = 不渲染。
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_receiver_udn-卧室盒子')));
    await tester.pumpAndSettle();

    expect(picked.value?.receiver.friendlyName, '卧室盒子');
    expect(picked.value?.filePath, filePath, reason: '不渲染就推原片');
    expect(executor.ran, isFalse);
    expect(find.byKey(const Key('cast_prep_panel')), findsNothing);
  });

  testWidgets('两个勾选默认全选；三种组合各给一句实话', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );

    bool checked(Key key) =>
        tester.widget<CheckboxListTile>(find.byKey(key)).value ?? false;

    expect(checked(const Key('cast_choice_picture')), isTrue);
    expect(checked(const Key('cast_choice_sound')), isTrue);
    expect(find.text(kCastPrepSentencePicture), findsOneWidget);
    // 勾了画面类还要说清数拍数字的已接受偏差（#30）：数字冻结在渲染那一刻。
    expect(find.text(kCastPrepBeatFreezeText), findsOneWidget);
    expect(
      find.byKey(const Key('cast_beat_freeze_sentence')),
      findsOneWidget,
    );

    // 取消画面类 → 只勾声音类：秒级那一句（数拍不进副本，偏差那句随之消失）。
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
    expect(find.text(kCastPrepSentencePicture), findsNothing);
    expect(find.text(kCastPrepBeatFreezeText), findsNothing);

    // 再取消声音类 → 都不勾：直接推那一句。
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();
    expect(find.text(kCastPrepSentencePassThrough), findsOneWidget);
  });

  testWidgets('渲好即带出产物路径（命中缓存那一份）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    // 预置一份「已经渲好」的产物：面板这次走命中，不跑执行器。
    final product = await CastRenderCache(directory: () async => root)
        .productFileFor(request(const CastRenderChoices.all()));
    File(product.path)
      ..createSync(recursive: true)
      ..writeAsStringSync('rendered');

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pumpAndSettle();

    expect(picked.value?.receiver.friendlyName, '客厅电视');
    expect(picked.value?.filePath, product.path);
    expect(executor.ran, isFalse, reason: '命中缓存不重渲');
  });

  testWidgets('渲染中：进度在场、取消后回列表且不留半成品', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );

    // 只勾画面类（不勾声音类）：这条路径不合成拍声轨，widget 测试的假时钟下
    // 也不会碰异步文件 IO。
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();

    executor.runGate = Completer<void>();
    executor.progressScript = const [Duration(seconds: 2)]; // 4 秒素材 → 50%

    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pump();
    await until(tester, () => executor.ran);
    await tester.pump();

    expect(find.byKey(const Key('cast_render_progress')), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
    expect(find.byKey(const Key('cast_prep_refresh')), findsNothing);
    expect(
      tester
          .widget<CheckboxListTile>(
            find.byKey(const Key('cast_choice_picture')),
          )
          .onChanged,
      isNull,
      reason: '渲染期间勾选不可改',
    );

    await tester.tap(find.byKey(const Key('cast_render_cancel')));
    await tester.pump();
    await until(tester, () => executor.cancelCalls > 0);
    await tester.pumpAndSettle();

    expect(executor.cancelCalls, 1);
    expect(picked.value, isNull, reason: '取消不带出任何东西');
    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(find.byKey(const Key('cast_render_progress')), findsNothing);
    expect(
      FakeCastRenderExecutor.fileNamesIn(root.path),
      isEmpty,
      reason: '取消不留半成品',
    );
  });

  testWidgets('渲染中把面板关掉（点外面）：在飞的那次渲染一并取消', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();

    executor.runGate = Completer<void>();
    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pump();
    await until(tester, () => executor.ran);

    // 点面板外面把它关掉（对话框返回 null）。
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(picked.value, isNull);
    expect(executor.cancelCalls, 1, reason: '面板不在时不该留一条 ffmpeg 在跑');
    expect(FakeCastRenderExecutor.fileNamesIn(root.path), isEmpty);
  });

  testWidgets('渲染失败：给一句失败话并留在列表（可以再试）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();

    executor.verdict = CastRenderVerdict.failed;
    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pumpAndSettle();

    expect(picked.value, isNull);
    expect(find.text(kCastPrepRenderFailedText), findsOneWidget);
    expect(find.text('客厅电视'), findsOneWidget, reason: '回到列表，接收端还在');
    expect(FakeCastRenderExecutor.fileNamesIn(root.path), isEmpty);
  });

  testWidgets('装配请求就失败（读面未就绪）：当场说明，不起渲染', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      requestOf: (_, _, _) => throw StateError('标注还没装载'),
    );
    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pumpAndSettle();

    expect(picked.value, isNull);
    expect(find.text(kCastPrepRenderFailedText), findsOneWidget);
    expect(executor.ran, isFalse);
  });

  testWidgets('取消：不带出任何接收端（宿主据此零副作用）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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

  testWidgets('搜不到接收端：空态里同一条系统镜像入口在场，说清代价并送用户过去', (tester) async {
    final discovery = FakeCastReceiverDiscovery(script: [const []]);
    final systemMirror = FakeSystemMirrorLauncher();
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      systemMirror: systemMirror,
    );

    // 同一条入口 = 同一个动作 + 同一份文案：投屏态顶栏那枚承担的那句取舍说明
    // 在这里逐字相同（故意逐字重写，不从常量取——文案改了要能在测试里看见）。
    expect(find.byKey(const Key('cast_prep_system_mirror')), findsOneWidget);
    expect(
      find.text(
        '整屏镜像：有延迟、手机屏要亮着、控制层也上电视；'
        '我们这条路推的是渲染好的投屏副本',
      ),
      findsOneWidget,
    );
    expect(systemMirror.openCalls, 0);

    await tester.tap(find.byKey(const Key('cast_prep_system_mirror')));
    await tester.pumpAndSettle();

    expect(systemMirror.openCalls, 1);
    // 跳系统设置不改准备面板的出参：面板照旧开着，选接收端那条路照旧。
    expect(find.byKey(const Key('cast_prep_panel')), findsOneWidget);
    expect(picked.value, isNull);
  });

  testWidgets('副本丢失门里没有系统镜像入口：那一条门只解释副本的事', (tester) async {
    final discovery = FakeCastReceiverDiscovery();
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(missingPaths: const {filePath}),
      picked: picked,
    );

    expect(find.byKey(const Key('cast_prep_system_mirror')), findsNothing);
  });

  testWidgets('发现本身出错：与「一台都没发现」同一口径（空态说明，不炸）', (tester) async {
    final discovery = FakeCastReceiverDiscovery()..error = StateError('组播发不出去');
    final picked = ValueNotifier<CastPrepOutcome?>(null);
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

  // ---- 投屏倍速档多选（票 #31）：默认就近、至少一档、先投后渲 ----

  bool tierChecked(WidgetTester tester, CastSpeedTier tier) =>
      tester
          .widget<CheckboxListTile>(find.byKey(castPrepTierKey(tier)))
          .value ??
      false;

  testWidgets('倍速档多选：默认勾与手动倍率最接近的一档；可加勾；至少留一档', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 0.75,
    );

    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isFalse);
    expect(tierChecked(tester, CastSpeedTier.full), isFalse);

    // 加勾一档：两档都在（多选）。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();
    expect(tierChecked(tester, CastSpeedTier.half), isTrue);

    // 取消另一档：只剩 0.5×。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.threeQuarter)));
    await tester.pumpAndSettle();
    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isFalse);

    // 取消最后一档是空操作：投屏总得有一份可播的。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();
    expect(tierChecked(tester, CastSpeedTier.half), isTrue, reason: '至少留一档');
  });

  testWidgets('手动倍率不在三档内：默认勾就近那一档（1.3 → 1×）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 1.3,
    );

    expect(tierChecked(tester, CastSpeedTier.full), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isFalse);
    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isFalse);
  });

  testWidgets('出参带档计划与各档请求；面板只渲起投档那一份', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 1,
    );
    // 再加勾 0.5×；只勾声音那条路不合成拍声轨（widget 假时钟下不做异步 IO）。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pumpAndSettle();

    final outcome = picked.value!;
    expect(outcome.plan.tiers, [CastSpeedTier.half, CastSpeedTier.full]);
    expect(outcome.plan.startTier, CastSpeedTier.full, reason: '手动倍率 1× 就近');
    expect(outcome.plan.pending, [CastSpeedTier.half]);
    expect(outcome.requests.keys.toSet(), {
      CastSpeedTier.half,
      CastSpeedTier.full,
    });
    expect(outcome.requests[CastSpeedTier.half]!.speedTier, CastSpeedTier.half);
    expect(executor.runs, hasLength(1), reason: '面板只渲起投档那一份');
    expect(
      executor.runs.single.last,
      contains(outcome.filePath),
      reason: '渲的就是带出去的那一份',
    );
  });

  testWidgets('都不勾渲染档：三档置灰、只剩原片这一档（1×）并说明', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 0.5,
    );
    expect(
      tierChecked(tester, CastSpeedTier.half),
      isTrue,
      reason: '默认就近 0.5×',
    );

    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cast_choice_sound')));
    await tester.pumpAndSettle();

    expect(tierChecked(tester, CastSpeedTier.full), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isFalse);
    expect(find.text(kCastPrepTierPassThrough), findsOneWidget);
    for (final tier in CastSpeedTier.values) {
      expect(
        tester
            .widget<CheckboxListTile>(find.byKey(castPrepTierKey(tier)))
            .onChanged,
        isNull,
        reason: '${tier.name}：没有副本可换，三档一律置灰',
      );
    }

    await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
    await tester.pumpAndSettle();

    final outcome = picked.value!;
    expect(outcome.filePath, filePath, reason: '不渲染就推原片');
    expect(outcome.plan.tiers, [CastSpeedTier.full], reason: '只有原片这一档');
    expect(executor.ran, isFalse);
  });

  test('先投后渲那句实话逐形状唯一（纯件）', () {
    expect(
      castPrepTierSentenceFor(
        CastSpeedTierPlan(
          tiers: const [CastSpeedTier.full],
          startTier: CastSpeedTier.full,
        ),
      ),
      '只备「1×」这一档：投上之后没有别的档要渲',
    );
    expect(
      castPrepTierSentenceFor(
        CastSpeedTierPlan(
          tiers: const [
            CastSpeedTier.half,
            CastSpeedTier.threeQuarter,
            CastSpeedTier.full,
          ],
          startTier: CastSpeedTier.full,
        ),
      ),
      '先渲「1×」这一档，投上之后其余 2 档在后台接着渲',
    );
  });

  test('三句实话逐组合唯一（纯件）', () {
    expect(
      castPrepRenderSentenceFor(const CastRenderChoices.none()),
      kCastPrepSentencePassThrough,
    );
    expect(
      castPrepRenderSentenceFor(
        const CastRenderChoices(picture: false, sound: true),
      ),
      kCastPrepSentenceSoundOnly,
    );
    expect(
      castPrepRenderSentenceFor(
        const CastRenderChoices(picture: true, sound: false),
      ),
      kCastPrepSentencePicture,
    );
    expect(
      castPrepRenderSentenceFor(const CastRenderChoices.all()),
      kCastPrepSentencePicture,
    );
  });

  test('只勾声音那句话随起投档如实变化（纯件，逐档）', () {
    const soundOnly = CastRenderChoices(picture: false, sound: true);

    expect(
      castPrepRenderSentenceFor(soundOnly, tier: CastSpeedTier.full),
      kCastPrepSentenceSoundOnly,
      reason: '1× 档视频流原样复制，是秒级',
    );
    for (final tier in const [
      CastSpeedTier.half,
      CastSpeedTier.threeQuarter,
    ]) {
      expect(
        castPrepRenderSentenceFor(soundOnly, tier: tier),
        kCastPrepSentenceSoundOnlySlowed,
        reason: '${tier.token}× 档改不了时长，视频要重编码，不是秒级',
      );
      expect(
        castPrepRenderSentenceFor(soundOnly, tier: tier),
        isNot(kCastPrepSentenceSoundOnly),
        reason: '${tier.token}× 档不该沿用 1× 档那句「秒级出结果」',
      );
      expect(
        castPrepRenderSentenceFor(soundOnly, tier: tier),
        allOf(contains('重编码'), contains('不是秒级')),
        reason: '${tier.token}× 档要说清这一档的代价',
      );
    }

    // 勾了画面类（或都不勾）那两句与档无关：它们本就说清了代价。
    for (final tier in CastSpeedTier.values) {
      expect(
        castPrepRenderSentenceFor(const CastRenderChoices.all(), tier: tier),
        kCastPrepSentencePicture,
      );
      expect(
        castPrepRenderSentenceFor(const CastRenderChoices.none(), tier: tier),
        kCastPrepSentencePassThrough,
      );
    }
  });

  testWidgets('只勾声音 + 非 1× 起投档：面板那一句不再说「秒级」', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      // 手动倍率 0.5：默认就近勾 0.5×（非 1× 档）。
      manualRate: 0.5,
    );
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();

    expect(find.text(kCastPrepSentenceSoundOnly), findsNothing);
    expect(find.text(kCastPrepSentenceSoundOnlySlowed), findsOneWidget);

    // 换成只剩 1× 这一档：视频流原样复制，那一句回到「秒级」。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.full)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();

    expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
    expect(find.text(kCastPrepSentenceSoundOnlySlowed), findsNothing);
  });

  testWidgets('只勾声音 + 1× 且这支舞设了首尾线：面板当场说清这一档收不住范围', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      requestOf: requestWithRange,
    );
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();

    // 只勾声音 + 1×（视频原样复制）+ 有首尾线：两句都在场——秒级那句是实话，
    // 收不住范围那句是它缺的那半句（#37 明确接受这一档，但不能不说）。
    expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
    expect(
      find.text(kCastPrepSentenceSoundOnlyTail),
      findsOneWidget,
      reason: '设了首尾线的舞看到的是片头，用户故事 31 的预期会被打破',
    );
    expect(
      find.byKey(const Key('cast_sound_only_tail_sentence')),
      findsOneWidget,
    );
  });

  testWidgets('没设首尾线：那一句一个字都不多说', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
    );
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();

    expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
    expect(find.text(kCastPrepSentenceSoundOnlyTail), findsNothing);
  });

  testWidgets('勾了画面类（视频要重编码、范围收得住）：那一句也不出', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      requestOf: requestWithRange,
    );

    expect(find.text(kCastPrepSentencePicture), findsOneWidget);
    expect(
      find.text(kCastPrepSentenceSoundOnlyTail),
      findsNothing,
      reason: '画面重编码的档收得住范围，那句话在这里是假话',
    );
  });

  testWidgets('设了首尾线、这次备的档里有 1× 复制档：那一句照样出', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      requestOf: requestWithRange,
      // 手动倍率 0.5：默认只勾 0.5×（那一档收得住范围）。
      manualRate: 0.5,
    );
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    expect(
      find.text(kCastPrepSentenceSoundOnlyTail),
      findsNothing,
      reason: '只有 0.5× 一档时视频要重编码，范围收得住，别说假话',
    );

    // 勾上 1×（复制档）：这次就会有从片头放到片尾的那一份。
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.full)));
    await tester.pumpAndSettle();

    expect(
      find.text(kCastPrepSentenceSoundOnlyTail),
      findsOneWidget,
      reason: '备的档里有 1× 复制档，那一份收不住首尾线',
    );
  });

  // ---- 投屏准备记忆（票 #40）：按舞预置与回写 ----

  bool choiceChecked(WidgetTester tester, Key key) =>
      tester.widget<CheckboxListTile>(find.byKey(key)).value ?? false;

  testWidgets('注入的取值来源：面板按记忆预置（两个勾选档与多档集合都按它）', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);
    final memory = _RecordingCastPrepMemoryPort(
      const CastPrepMemory(
        choices: CastRenderChoices(picture: false, sound: true),
        tiers: {CastSpeedTier.half, CastSpeedTier.full},
      ),
    );

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      memory: memory.port,
      // 手动倍率 1× 在记忆在场时不再决定初值：默认只会勾 1× 一档，
      // 记忆里是两档。
      manualRate: 1,
    );

    expect(choiceChecked(tester, const Key('cast_choice_picture')), isFalse);
    expect(choiceChecked(tester, const Key('cast_choice_sound')), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isTrue);
    expect(tierChecked(tester, CastSpeedTier.full), isTrue);
    expect(
      tierChecked(tester, CastSpeedTier.threeQuarter),
      isFalse,
      reason: '记忆里没有这一档',
    );
    // 那一句实话跟着预置的起投档走：手动倍率 1× 就近，起投是 1× 档。
    expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
    expect(memory.writes, isEmpty, reason: '只是打开面板不该回写');
  });

  testWidgets('改动即回写：取消面板后重开，取值按上次的表态预置', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);
    final memory = _RecordingCastPrepMemoryPort();

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      memory: memory.port,
    );
    // 打开时是默认（全选 + 就近 1×）。
    expect(choiceChecked(tester, const Key('cast_choice_picture')), isTrue);
    expect(tierChecked(tester, CastSpeedTier.full), isTrue);

    // 取消画面类、加勾 0.5×：两次改动各回写一次。
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(castPrepTierKey(CastSpeedTier.half)));
    await tester.pumpAndSettle();

    expect(memory.writes, hasLength(2), reason: '改一次回写一次');
    expect(
      memory.memory?.choices,
      const CastRenderChoices(picture: false, sound: true),
    );
    expect(memory.memory?.tiers, {CastSpeedTier.half, CastSpeedTier.full});

    // 关掉面板（取消不是失败：不带出任何东西）……
    await tester.tap(find.byKey(const Key('cast_prep_cancel')));
    await tester.pumpAndSettle();
    expect(picked.value, isNull);

    // ……再开一次：预置就是上次那套取值（「面板关闭即丢」已修）。
    await tester.tap(find.byKey(const Key('open_panel')));
    await tester.pumpAndSettle();

    expect(choiceChecked(tester, const Key('cast_choice_picture')), isFalse);
    expect(choiceChecked(tester, const Key('cast_choice_sound')), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isTrue);
    expect(tierChecked(tester, CastSpeedTier.full), isTrue);
  });

  testWidgets('默认装配（会话记忆槽）：文档字段形状的记忆经面板预置', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 1,
      extraOverrides: [
        castPrepMemoryProvider.overrideWith(
          () => _SeededCastPrepMemory(
            const CastPrepMemoryFields(
              picture: false,
              sound: false,
              tiers: ['0.5', '0.75'],
            ),
          ),
        ),
      ],
    );

    expect(choiceChecked(tester, const Key('cast_choice_picture')), isFalse);
    expect(choiceChecked(tester, const Key('cast_choice_sound')), isFalse);
    // 都不勾渲染档：三档置灰、界面只显示原片这一档（既有语义不变）——记忆
    // 里的档表此刻不显示，但没被抹掉（下面重勾画面类即可看见它回来）。
    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isFalse);
    expect(tierChecked(tester, CastSpeedTier.half), isFalse);
    expect(tierChecked(tester, CastSpeedTier.full), isTrue);
    expect(find.text(kCastPrepTierPassThrough), findsOneWidget);

    // 重新勾上画面类：记忆里的档表立刻回来（面板这一路没把记忆改掉）。
    await tester.tap(find.byKey(const Key('cast_choice_picture')));
    await tester.pumpAndSettle();
    expect(choiceChecked(tester, const Key('cast_choice_picture')), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isTrue);
    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isTrue);
  });

  testWidgets('槽里的记忆非法 / 已不可用：静默降级回默认，不炸也不提示', (tester) async {
    final discovery = FakeCastReceiverDiscovery(
      script: [
        [receiver('客厅电视')],
      ],
    );
    final picked = ValueNotifier<CastPrepOutcome?>(null);
    addTearDown(picked.dispose);

    await pumpHost(
      tester,
      discovery: discovery,
      presence: FakeVideoCopyPresence(),
      picked: picked,
      manualRate: 0.75,
      extraOverrides: [
        castPrepMemoryProvider.overrideWith(
          () => _SeededCastPrepMemory(
            // 盘上那份记录经**文档层**读回（词表外的记号在那一层就拦下）。
            _memoryFieldsFromFile(const {
              'picture': true,
              'tiers': ['2', 'double'],
            }),
          ),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    // 逐字段降级：缺席的 sound 回默认（全选），档表剔空后回就近那一档。
    expect(choiceChecked(tester, const Key('cast_choice_picture')), isTrue);
    expect(choiceChecked(tester, const Key('cast_choice_sound')), isTrue);
    expect(tierChecked(tester, CastSpeedTier.threeQuarter), isTrue);
    expect(tierChecked(tester, CastSpeedTier.half), isFalse);
    expect(
      find.byKey(const Key('cast_gate_copy')),
      findsNothing,
      reason: '静默降级：不出任何说明文案',
    );
  });

  group('编码器保证不了 1× 实时：当场说一句、请求按 720p 档装配（#36）', () {
    /// 开面板（当场核对那一句在不在）、选一台接收端、带出结局。
    Future<ValueNotifier<CastPrepOutcome?>> pickOne(
      WidgetTester tester, {
      required FakeEncoderRealtimeCapability capability,
      required bool noteOnPanel,
    }) async {
      final discovery = FakeCastReceiverDiscovery(
        script: [
          [receiver('客厅电视')],
        ],
      );
      final picked = ValueNotifier<CastPrepOutcome?>(null);
      addTearDown(picked.dispose);

      await pumpHost(
        tester,
        discovery: discovery,
        presence: FakeVideoCopyPresence(),
        picked: picked,
        capability: capability,
      );
      // 那一句在面板上**当场**出（还没开始渲），且逐字就是那条常量。
      expect(
        find.text(kCastPrepResolutionDowngradedText),
        noteOnPanel ? findsOneWidget : findsNothing,
      );
      // 只勾画面类（不勾声音类）：这条路径不合成拍声轨，widget 测试的假时钟下
      // 也不会碰异步文件 IO（沿既有用例）。
      await tester.tap(find.byKey(const Key('cast_choice_sound')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cast_receiver_udn-客厅电视')));
      await tester.pumpAndSettle();
      return picked;
    }

    testWidgets('保证 1× 实时：不多说，请求按源分辨率渲', (tester) async {
      final picked = await pickOne(
        tester,
        capability: FakeEncoderRealtimeCapability(
          answer: CastEncoderRealtime.guaranteed,
        ),
        noteOnPanel: false,
      );

      expect(
        picked.value?.requests[CastSpeedTier.full]?.resolution,
        CastRenderResolution.source,
      );
    });

    testWidgets('不保证 1× 实时：那一句逐字在场，请求带 720p 档', (tester) async {
      final picked = await pickOne(
        tester,
        capability: FakeEncoderRealtimeCapability(
          answer: CastEncoderRealtime.notGuaranteed,
        ),
        noteOnPanel: true,
      );

      expect(
        picked.value?.requests[CastSpeedTier.full]?.resolution,
        CastRenderResolution.p720,
      );
    });

    testWidgets('问不到（API < 29 / 设备不报）：与不保证同一侧——明说并降级', (tester) async {
      final picked = await pickOne(
        tester,
        capability: FakeEncoderRealtimeCapability(
          answer: CastEncoderRealtime.unknown,
        ),
        noteOnPanel: true,
      );

      expect(
        picked.value?.requests[CastSpeedTier.full]?.resolution,
        CastRenderResolution.p720,
        reason: '问不到 = 按不可保证处理（宁可降分辨率，也不给没底的进度条）',
      );
    });

    testWidgets('查询自己失败：面板不崩，按问不到兜底', (tester) async {
      final picked = await pickOne(
        tester,
        capability: FakeEncoderRealtimeCapability()
          ..failure = StateError('通道炸了'),
        noteOnPanel: true,
      );

      expect(
        picked.value?.requests[CastSpeedTier.full]?.resolution,
        CastRenderResolution.p720,
      );
    });

    testWidgets('降级那句就在面板上（还没选接收端也说得早）', (tester) async {
      final discovery = FakeCastReceiverDiscovery(
        script: [
          [receiver('客厅电视')],
        ],
      );
      final picked = ValueNotifier<CastPrepOutcome?>(null);
      addTearDown(picked.dispose);

      await pumpHost(
        tester,
        discovery: discovery,
        presence: FakeVideoCopyPresence(),
        picked: picked,
        capability: FakeEncoderRealtimeCapability(
          answer: CastEncoderRealtime.notGuaranteed,
        ),
      );

      expect(find.text(kCastPrepResolutionDowngradedText), findsOneWidget);
      expect(
        find.byKey(const Key('cast_resolution_downgraded')),
        findsOneWidget,
        reason: '逐字断言那条常量 + 那枚 key 都在',
      );
      expect(picked.value, isNull, reason: '只是说明，还没开始渲');
    });

    testWidgets('只勾声音 + 1×（视频原样复制）：没有可降的编码，那一句不出现', (tester) async {
      final discovery = FakeCastReceiverDiscovery(
        script: [
          [receiver('客厅电视')],
        ],
      );
      final picked = ValueNotifier<CastPrepOutcome?>(null);
      addTearDown(picked.dispose);

      await pumpHost(
        tester,
        discovery: discovery,
        presence: FakeVideoCopyPresence(),
        picked: picked,
        capability: FakeEncoderRealtimeCapability(
          answer: CastEncoderRealtime.notGuaranteed,
        ),
      );
      await tester.tap(find.byKey(const Key('cast_choice_picture')));
      await tester.pumpAndSettle();

      expect(find.text(kCastPrepSentenceSoundOnly), findsOneWidget);
      expect(
        find.text(kCastPrepResolutionDowngradedText),
        findsNothing,
        reason: '视频流原样复制，说「降到 720p」就是假话',
      );
    });
  });
}

/// 注入用的记忆槽：把一份文档字段形状的记忆当初始值。
class _SeededCastPrepMemory extends CastPrepMemoryModel {
  _SeededCastPrepMemory(this._initial);

  final CastPrepMemoryFields? _initial;

  @override
  CastPrepMemoryFields? build() => _initial;
}

/// 盘上那份 `prefs.castPrep` 经文档层读回来的字段（词表校验的边界就在那里）。
CastPrepMemoryFields _memoryFieldsFromFile(Map<String, Object?> json) =>
    LocalDocument.fromJson({
      'version': 3,
      'prefs': {'castPrep': json},
    }).castPrep!;

/// 注入用的取值来源与回写口：记住最后一次回写的取值（两个钩子与真实装配
/// 同形；[port] 交给面板）。
class _RecordingCastPrepMemoryPort {
  _RecordingCastPrepMemoryPort([this.memory]);

  CastPrepMemory? memory;
  final List<CastPrepMemory> writes = [];

  CastPrepMemoryPort get port => CastPrepMemoryPort(
    presetFor: (manualRate) => memory ?? defaultCastPrepMemoryFor(manualRate),
    remember: (next) {
      memory = next;
      writes.add(next);
    },
  );
}
