import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_speed_tier.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/cast/system_mirror.dart'
    show systemMirrorLauncherProvider;
import 'package:dance_learning_app/dance/video_copy_presence.dart'
    show videoCopyPresenceProvider;
import 'package:dance_learning_app/player/cast_prep_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_receiver_discovery.dart';
import '../helpers/fake_cast_render_executor.dart';
import '../helpers/fake_system_mirror_launcher.dart';
import '../helpers/fake_video_copy_presence.dart';

/// 投屏准备面板直测：两个勾选档与三句实话、列接收端、可重扫、两条门
/// （副本丢失 / 发现不到接收端）当场拦下并说明；「搜不到接收端」空态里还有
/// **同一条系统镜像入口**（与投屏态顶栏那枚同一个动作、同一份文案）；选中一台
/// 即渲染并把**接收端 + 要推的文件**带出（渲好即带出产物，可取消、失败给一句）。
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

  CastRenderRequest request(
    CastRenderChoices choices, [
    CastSpeedTier tier = CastSpeedTier.full,
  ]) => CastRenderRequest(
    videoPath: filePath,
    videoId: 'vid-a',
    duration: const Duration(seconds: 4),
    choices: choices,
    speedTier: tier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
  );

  /// 面板宿主：按钮开面板、把出参记进通知器。
  Future<void> pumpHost(
    WidgetTester tester, {
    required FakeCastReceiverDiscovery discovery,
    required FakeVideoCopyPresence presence,
    required ValueNotifier<CastPrepOutcome?> picked,
    CastRenderRequest Function(CastRenderChoices choices, CastSpeedTier tier)?
    requestOf,
    double manualRate = 1,
    FakeSystemMirrorLauncher? systemMirror,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          castReceiverDiscoveryProvider.overrideWithValue(discovery),
          videoCopyPresenceProvider.overrideWithValue(presence),
          castRenderExecutorProvider.overrideWithValue(executor),
          castRenderCacheDirectoryProvider.overrideWithValue(() async => root),
          systemMirrorLauncherProvider.overrideWithValue(
            systemMirror ?? FakeSystemMirrorLauncher(),
          ),
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
      requestOf: (_, _) => throw StateError('标注还没装载'),
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
}
