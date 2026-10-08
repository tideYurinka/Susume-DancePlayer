import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_delivery_channel.dart';
import 'package:dance_learning_app/cast/cast_failure.dart';
import 'package:dance_learning_app/cast/cast_receiver.dart';
import 'package:dance_learning_app/cast/cast_render_cache.dart';
import 'package:dance_learning_app/cast/cast_render_executor.dart'
    show CastRenderVerdict, castRenderExecutorProvider;
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/cast/cast_session.dart';
import 'package:dance_learning_app/cast/cast_speed_tier.dart';
import 'package:dance_learning_app/cast/device_description.dart'
    show CastControlUrls;
import 'package:dance_learning_app/player/cast_run.dart';
import 'package:dance_learning_app/player/notice.dart'
    show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_cast_delivery_channel.dart';
import '../helpers/fake_cast_render_executor.dart';
import '../helpers/fake_cast_session.dart';

/// 投屏**倍速档**运行账直测（票 #31）：一档一份副本、当前档先渲好即开投、
/// 其余档后台顺序渲且前台遥控不等它、未渲好的档不可切、换档 = 换文件 + 按
/// 比例换算位置续播、失败回退旧文件并提示、断开把在飞的后台渲染一并取消、
/// 遥控跳转按当前档换算坐标。
///
/// 经 #23 的三条接缝（发现 / 会话 / 递出通道）与 #26 的渲染执行器替身测，
/// 不碰真网络、不跑进程、不启动 widget。
void main() {
  const sourcePath = '/videos/这支舞.mp4';
  const startPath = '/cache/full.mp4';

  CastReceiver receiverNamed(String name) => CastReceiver(
    id: 'udn-$name',
    friendlyName: name,
    descriptionUrl: Uri.parse('http://192.168.1.9:8080/desc.xml'),
    controlUrls: CastControlUrls(
      avTransport: Uri.parse('http://192.168.1.9:8080/avt'),
      renderingControl: Uri.parse('http://192.168.1.9:8080/rcs'),
    ),
  );

  late Directory root;
  late FakeCastSessionFactory factory;
  late FakeCastDeliveryChannel delivery;
  late FakeCastRenderExecutor executor;
  late ProviderContainer container;

  CastRunModel run() => container.read(castRunProvider.notifier);
  CastRunState state() => container.read(castRunProvider);
  FakeCastSession session() => factory.sessions.single;

  /// 一份渲染请求（素材 60 秒——0.5× 档副本就是 120 秒）。
  CastRenderRequest requestOf(
    CastSpeedTier tier, {
    Duration duration = const Duration(seconds: 60),
  }) => CastRenderRequest(
    videoPath: sourcePath,
    videoId: 'vid-a',
    duration: duration,
    choices: const CastRenderChoices.all(),
    speedTier: tier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
  );

  Map<CastSpeedTier, CastRenderRequest> requestsFor(
    List<CastSpeedTier> tiers,
  ) => {for (final tier in tiers) tier: requestOf(tier)};

  /// 等一个条件成立：后台渲染是 fire-and-forget（不阻塞前台），测试靠轮询
  /// 推进真实事件循环等它落位——真实文件 IO（拍声轨写盘）不吃假时钟。
  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 500 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    if (!ready()) fail('等不到条件成立');
  }

  /// 等某一档渲完（或判失败）。
  Future<void> settleTier(CastSpeedTier tier) => until(
    () => state().renderFor(tier)!.status != CastTierRenderStatus.rendering,
  );

  /// 起投：起投档那一份文件已经在手上（准备面板渲好的）。
  Future<void> startWith({
    required List<CastSpeedTier> tiers,
    required CastSpeedTier startTier,
    String file = startPath,
    ({Duration start, Duration end})? practiceSpan,
  }) => run().start(
    receiver: receiverNamed('客厅电视'),
    file: File(file),
    plan: CastSpeedTierPlan(tiers: tiers, startTier: startTier),
    requests: requestsFor(tiers),
    practiceSpan: practiceSpan,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('cast_speed_run_test');
    factory = FakeCastSessionFactory();
    delivery = FakeCastDeliveryChannel();
    executor = FakeCastRenderExecutor();
    container = ProviderContainer(
      overrides: [
        castSessionFactoryProvider.overrideWithValue(factory),
        castDeliveryChannelProvider.overrideWithValue(delivery),
        castRenderExecutorProvider.overrideWithValue(executor),
        castRenderCacheDirectoryProvider.overrideWithValue(() async => root),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
  });

  group('先投后渲', () {
    test('起投档先推上去在播；其余档在后台按声明次序逐档渲、各自进缓存', () async {
      await startWith(
        tiers: [
          CastSpeedTier.half,
          CastSpeedTier.threeQuarter,
          CastSpeedTier.full,
        ],
        startTier: CastSpeedTier.full,
      );

      // 起投这一刻：只递出起投档那一份，会话已经推上去并起播。
      expect(delivery.served.map((file) => file.path), [startPath]);
      expect(session().calls, ['push', 'play']);
      expect(state().activeTier, CastSpeedTier.full);
      expect(state().renderFor(CastSpeedTier.full)!.ready, isTrue);
      expect(
        state().renderFor(CastSpeedTier.threeQuarter)!.status,
        CastTierRenderStatus.queued,
        reason: '后台顺序渲：后面那档还没轮到',
      );

      await settleTier(CastSpeedTier.half);
      await settleTier(CastSpeedTier.threeQuarter);

      // 两档依次渲好（一次只跑一条命令），产物路径各自独立。
      expect(state().renderFor(CastSpeedTier.half)!.ready, isTrue);
      expect(state().renderFor(CastSpeedTier.threeQuarter)!.ready, isTrue);
      expect(executor.runs, hasLength(2));
      expect(
        {
          state().renderFor(CastSpeedTier.half)!.filePath,
          state().renderFor(CastSpeedTier.threeQuarter)!.filePath,
        },
        hasLength(2),
        reason: '一档一份副本',
      );
      expect(state().renderingTiers, isFalse);
      // 在飞的档没有留下半成品：盘上只有两份产物。
      expect(
        FakeCastRenderExecutor.fileNamesIn(root.path),
        everyElement(isNot(endsWith('.part'))),
      );
    });

    test('后台渲染不阻塞前台：渲染挂着时遥控照旧、会话照旧', () async {
      executor.runGate = Completer<void>();
      executor.progressScript = const [Duration(seconds: 3)]; // 60 秒素材 → 5%

      await startWith(
        tiers: [
          CastSpeedTier.half,
          CastSpeedTier.threeQuarter,
          CastSpeedTier.full,
        ],
        startTier: CastSpeedTier.full,
      );
      await until(() => executor.ran);

      expect(executor.runs, hasLength(1), reason: '后台一次只跑一条命令');
      expect(
        state().renderFor(CastSpeedTier.half)!.status,
        CastTierRenderStatus.rendering,
      );
      expect(state().renderFor(CastSpeedTier.half)!.fraction, 0.05);
      expect(
        state().renderFor(CastSpeedTier.threeQuarter)!.status,
        CastTierRenderStatus.queued,
      );

      // 前台遥控不等后台渲染。
      await run().pause();
      await run().seek(const Duration(seconds: 6));
      expect(session().calls, ['push', 'play', 'pause', 'seek']);
      expect(session().seeks, [const Duration(seconds: 6)]);
      expect(state().active, isTrue);

      executor.runGate!.complete();
      await settleTier(CastSpeedTier.half);
      expect(state().renderFor(CastSpeedTier.half)!.ready, isTrue);
      await until(() => executor.runs.length == 2);
      expect(executor.runs, hasLength(2), reason: '第一档渲完才起第二档');
    });

    test('未渲好的档不可切：结构上不可点，换档是空操作', () async {
      executor.runGate = Completer<void>();
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await until(() => executor.ran);
      expect(state().canSwitchTo(CastSpeedTier.half), isFalse);

      await run().switchTier(CastSpeedTier.half);

      expect(state().activeTier, CastSpeedTier.full);
      expect(state().switching, isFalse);
      expect(delivery.served, hasLength(1), reason: '没换文件');
      expect(session().pushes, hasLength(1));
    });

    test('同一份副本不必重渲：已渲好的档命中缓存，不跑执行器', () async {
      final product = await CastRenderCache(directory: () async => root)
          .productFileFor(requestOf(CastSpeedTier.half));
      File(product.path)
        ..createSync(recursive: true)
        ..writeAsStringSync('rendered');

      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);

      expect(state().renderFor(CastSpeedTier.half)!.filePath, product.path);
      expect(executor.ran, isFalse, reason: '命中缓存不重渲');
    });

    test('这一档没渲出来：标失败、不可切，其余档照旧可用', () async {
      executor.verdict = CastRenderVerdict.failed;
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);

      expect(
        state().renderFor(CastSpeedTier.half)!.status,
        CastTierRenderStatus.failed,
      );
      expect(state().canSwitchTo(CastSpeedTier.half), isFalse);
      expect(state().canSwitchTo(CastSpeedTier.full), isFalse);
    });
  });

  group('换档 = 换一个文件播', () {
    test('顺序：递出新文件 → 推片 → 按比例换算位置 → 续播；当前档翻过去', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);
      // 电视此刻在 1× 那一份的第 20 秒。
      session().reportedPosition = const Duration(seconds: 20);

      await run().switchTier(CastSpeedTier.half);

      final half = state().renderFor(CastSpeedTier.half)!;
      expect(delivery.served.map((file) => file.path), [
        startPath,
        half.filePath,
      ]);
      expect(session().calls.sublist(2), [
        'position',
        'push',
        'seek',
        'play',
      ], reason: '换档 = 先问旧档位置 → 换文件 → 跳 → 播');
      expect(session().seeks, [
        const Duration(seconds: 40),
      ], reason: '新位置 = 旧位置 × 旧率 ÷ 新率（20 × 1 ÷ 0.5）');
      expect(state().activeTier, CastSpeedTier.half);
      expect(state().switching, isFalse);
    });

    test('换档过程中：过程态在场，成功前当前档不翻', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);
      final gate = Completer<void>();
      session().pushGate = gate;

      final switching = run().switchTier(CastSpeedTier.half);
      await until(() => state().switching);

      expect(state().switching, isTrue);
      expect(state().activeTier, CastSpeedTier.full);
      expect(
        state().canSwitchTo(CastSpeedTier.half),
        isFalse,
        reason: '换档中不可再切',
      );

      gate.complete();
      await switching;
      expect(state().switching, isFalse);
      expect(state().activeTier, CastSpeedTier.half);
    });

    test('换档失败：回退旧文件 + 换算回旧档位置 + 提示；投屏照旧', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);
      session().reportedPosition = const Duration(seconds: 20);
      // 第二次 push（换档那一次）失败，第三次（回退那一次）成功。
      session().onPush = (index) {
        session().pushError = index == 1
            ? const CastActionRefused('这份拉不到')
            : null;
      };

      await run().switchTier(CastSpeedTier.half);

      expect(delivery.served.map((file) => file.path), [
        startPath,
        state().renderFor(CastSpeedTier.half)!.filePath,
        startPath,
      ], reason: '回退就是把旧文件重新递出去');
      expect(session().seeks, [
        const Duration(seconds: 20),
      ], reason: '换档那次没推到，回退时把位置换算回去（20 秒的新档位置 → 旧档 20 秒）');
      expect(state().activeTier, CastSpeedTier.full);
      expect(state().switching, isFalse);
      expect(state().active, isTrue, reason: '换档失败不把投屏整条收掉');
      expect(
        container.read(noticeTriggerProvider(NoticeId.castSpeedSwitchFailed)),
        1,
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.castInterrupted)),
        0,
      );
    });

    test('回退也失败（连接没了）：落回「会话建立之后的失败」收口', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);
      session().onPush = (index) {
        if (index >= 1) session().pushError = const CastSessionDropped('连接没了');
      };

      await run().switchTier(CastSpeedTier.half);

      expect(state().active, isFalse);
      expect(session().disconnected, isTrue);
      expect(delivery.closed, isTrue);
      expect(
        container.read(playerSessionProvider).mode,
        PlayerSessionMode.editing,
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.castInterrupted)),
        1,
      );
      expect(
        container.read(noticeTriggerProvider(NoticeId.castSpeedSwitchFailed)),
        0,
      );
    });

    test('切到同一档 / 未投屏：都是空操作', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await settleTier(CastSpeedTier.half);

      await run().switchTier(CastSpeedTier.full);
      expect(delivery.served, hasLength(1));
      expect(state().switching, isFalse);

      await run().disconnect();
      await run().switchTier(CastSpeedTier.half);
      expect(state().active, isFalse);
      expect(delivery.served, hasLength(1));
    });
  });

  group('断开把在飞的后台渲染一并取消', () {
    test('断开：取消在飞的渲染、不留半成品、后续档不再起渲', () async {
      executor.runGate = Completer<void>();
      await startWith(
        tiers: [
          CastSpeedTier.half,
          CastSpeedTier.threeQuarter,
          CastSpeedTier.full,
        ],
        startTier: CastSpeedTier.full,
      );
      await until(() => executor.ran);
      expect(executor.runs, hasLength(1));
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);

      await run().disconnect();
      await until(() => state().tiers.isEmpty);

      expect(executor.cancelCalls, 1, reason: '在飞的那条命令被取消');
      expect(executor.runs, hasLength(1), reason: '后面的档不再起渲');
      expect(state().active, isFalse);
      expect(state().tiers, isEmpty);
      expect(FakeCastRenderExecutor.fileNamesIn(root.path), isEmpty);
      expect(delivery.closed, isTrue);
    });

    test('换视频（既有复位一处）同样取消在飞的后台渲染', () async {
      executor.runGate = Completer<void>();
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );
      await until(() => executor.ran);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.castControl);

      container.read(playerSessionProvider.notifier).reset();
      await until(() => !state().active);

      expect(executor.cancelCalls, 1);
      expect(state().active, isFalse);
    });
  });

  group('遥控跳转按当前档换算坐标', () {
    test('起投档就是 0.5× 时：源片位置换成副本位置（并钳到副本时长）', () async {
      await startWith(
        tiers: [CastSpeedTier.half],
        startTier: CastSpeedTier.half,
      );

      await run().seek(const Duration(seconds: 10));
      expect(session().seeks, [const Duration(seconds: 20)]);

      // 源片 100 秒 → 副本 200 秒，但这一档只有 120 秒（60 秒素材）。
      await run().seek(const Duration(seconds: 100));
      expect(session().seeks.last, const Duration(seconds: 120));
    });

    test('1× 档：源片位置原样（不换算）', () async {
      await startWith(
        tiers: [CastSpeedTier.full],
        startTier: CastSpeedTier.full,
      );

      await run().seek(const Duration(seconds: 7));
      expect(session().seeks, [const Duration(seconds: 7)]);
    });

    test('接收端上报的位置换成源片坐标（本地预览用）', () async {
      await startWith(
        tiers: [CastSpeedTier.half],
        startTier: CastSpeedTier.half,
      );
      session().reportedPosition = const Duration(seconds: 20);

      expect(await run().reportedPosition(), const Duration(seconds: 10));
    });

    test('学习段：续播位置钳进换算后的段内（段外不续播）', () async {
      await startWith(
        tiers: [CastSpeedTier.half, CastSpeedTier.full],
        startTier: CastSpeedTier.full,
        practiceSpan: (
          start: const Duration(seconds: 4),
          end: const Duration(seconds: 6),
        ),
      );
      await settleTier(CastSpeedTier.half);
      // 电视报了个远超段尾的位置（源 30 秒，段是 4–6 秒）。
      session().reportedPosition = const Duration(seconds: 30);

      await run().switchTier(CastSpeedTier.half);

      expect(session().seeks, [
        const Duration(seconds: 12),
      ], reason: '段尾源 6 秒 → 0.5× 档 12 秒（钳进段内）');
      expect(state().activeTier, CastSpeedTier.half);
    });
  });

  group('单档路（老调用方 / 都不勾）', () {
    test('不给档计划：只有 1× 这一档、没有后台渲染', () async {
      await run().start(receiver: receiverNamed('客厅电视'), file: File(startPath));

      expect(state().activeTier, CastSpeedTier.full);
      expect(state().tiers, hasLength(1));
      expect(state().renderFor(CastSpeedTier.full)!.ready, isTrue);
      expect(executor.ran, isFalse);
    });
  });
}
