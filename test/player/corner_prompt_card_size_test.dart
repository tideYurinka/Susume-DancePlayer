import 'package:dance_learning_app/core/beat_grid.dart'
    show placeholderBeatGrid;
import 'package:dance_learning_app/player/loop_prompt.dart';
import 'package:dance_learning_app/core/notice_badge.dart';
import 'package:dance_learning_app/player/resume_position.dart'
    show resumePromptProvider;
import 'package:dance_learning_app/player/resume_prompt.dart';
import 'package:dance_learning_app/player/visual_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 两张角落提示卡的**卡尺寸缝**。
///
/// 只钉外部可观察的渲染尺寸与命中矩形：号机基准屏上循环提示卡
/// 180 × 48dp；两张卡共用同一套紧凑取值（宽度随各自文案）；卡内动作的
/// 命中矩形高不随收窄缩水；全站其它黑底胶囊的默认档一字一毫不动。
/// 期望值取号机基准（361.1 × 781.7dp，dpr 1.0 即逻辑尺寸）。
void main() {
  /// 号机基准屏（逻辑尺寸即实数）。
  const portrait = Size(361.1, 781.7);

  Future<({ProviderContainer container, FakePlaybackEngine engine})> pumpCards(
    WidgetTester tester, {
    Size screen = portrait,
    ({double left, double bottom})? loopAnchor = (left: 24, bottom: 100),
    ({double left, double bottom})? resumeAnchor = (left: 24, bottom: 200),
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final engine = FakePlaybackEngine(duration: const Duration(seconds: 1));
    final controller = LoopPromptController(
      engine,
      gridOf: () => placeholderBeatGrid,
    );
    addTearDown(controller.dispose);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                LoopPromptOverlay(controller: controller, anchor: loopAnchor),
                ResumePromptOverlay(anchor: resumeAnchor),
              ],
            ),
          ),
        ),
      ),
    );
    // 播放到尾进入 countdown（循环卡出场）+ 弹续播小卡。
    engine.open(Uri.file('/videos/a.mp4'), play: true);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    container.read(resumePromptProvider.notifier).show();
    await tester.pump();
    return (container: container, engine: engine);
  }

  /// 收尾：走完倒计时（自动循环起播）、暂停引擎、撤掉续播自动消失计时，
  /// 不留悬挂计时器。
  Future<void> settle(
    WidgetTester tester,
    ({ProviderContainer container, FakePlaybackEngine engine}) pumped,
  ) async {
    await tester.pump(placeholderBeatGrid.beatsDuration(8));
    pumped.engine.pause();
    pumped.container.read(resumePromptProvider.notifier).dismiss();
    await tester.pump();
  }

  group('卡尺寸（号机基准屏）', () {
    testWidgets('循环提示卡 = 180 × 48dp', (tester) async {
      final pumped = await pumpCards(tester);
      expect(find.byKey(const Key('loop_prompt')), findsOneWidget);

      // 标称 180 × 48dp，容差 ±2dp。
      final size = tester.getSize(find.byKey(const Key('loop_prompt')));
      expect(size.width, closeTo(180, 2));
      expect(size.height, closeTo(48, 2));
      await settle(tester, pumped);
    });

    testWidgets('续播小卡：同一套紧凑取值撑起 48dp 高（宽度随自己的文案）', (tester) async {
      final pumped = await pumpCards(tester);
      expect(find.byKey(const Key('resume_prompt_card')), findsOneWidget);

      // 「已从上次位置继续」（8 字）与「从头播放？」（5 字）比循环卡多 2 字，
      // 宽度因此多 24dp——高度与循环卡同一条命中下限。
      final size = tester.getSize(find.byKey(const Key('resume_prompt_card')));
      expect(size.width, closeTo(204, 2));
      expect(size.height, closeTo(48, 2));
      await settle(tester, pumped);
    });

    testWidgets('拉通档位：竖屏 16:9 画面下两张卡高 ≤ 26%，基准卡宽 ≤ 52%', (tester) async {
      final pumped = await pumpCards(tester);
      final loop = tester.getSize(find.byKey(const Key('loop_prompt')));
      final resume = tester.getSize(
        find.byKey(const Key('resume_prompt_card')),
      );
      // 号机竖屏 16:9 画面 361.1 × 203.1dp。宽随各自文案（续播卡按钮多 2 字，
      // 204/361.1 = 56.5%），故宽度档位只对基准卡成立；两张卡同一条命中下限
      // 撑起的高都 ≤ 26%。
      expect(loop.width / 361.1, lessThanOrEqualTo(0.52));
      expect(loop.height / 203.1, lessThanOrEqualTo(0.26));
      expect(resume.height, loop.height);
      await settle(tester, pumped);
    });

    testWidgets('两张卡的紧凑内边距取自同一处定义', (tester) async {
      final pumped = await pumpCards(tester);

      for (final card in const [
        Key('loop_prompt'),
        Key('resume_prompt_card'),
      ]) {
        final badge = tester.widget<NoticeBadge>(
          find.descendant(
            of: find.byKey(card),
            matching: find.byType(NoticeBadge),
          ),
        );
        expect(badge.padding, kCornerPromptCardPadding, reason: '$card 用紧凑档');
      }
      await settle(tester, pumped);
    });
  });

  group('命中区不缩水', () {
    testWidgets('「不循环」与「从头播放？」的命中矩形高 ≥ 48dp', (tester) async {
      final pumped = await pumpCards(tester);

      // 矩形断言取命中矩形（与命中下限同一来源），不另写数字。
      expect(
        tester.getRect(find.byKey(const Key('loop_dismiss_button'))).height,
        greaterThanOrEqualTo(kHitTargetMinSize),
      );
      expect(
        tester.getRect(find.byKey(const Key('resume_prompt_restart'))).height,
        greaterThanOrEqualTo(kHitTargetMinSize),
      );
      await settle(tester, pumped);
    });

    testWidgets('卡内文案逐字不变', (tester) async {
      final pumped = await pumpCards(tester);

      expect(find.text('即将自动循环播放'), findsOneWidget);
      expect(find.text('不循环'), findsOneWidget);
      expect(find.text('已从上次位置继续'), findsOneWidget);
      expect(find.text('从头播放？'), findsOneWidget);
      await settle(tester, pumped);
    });

    testWidgets('收窄不改配色：正文恒白、按钮仍是浅蓝强调色', (tester) async {
      final pumped = await pumpCards(tester);

      Color? painted(String text) => tester
          .renderObject<RenderParagraph>(find.text(text))
          .text
          .style
          ?.color;

      expect(painted('即将自动循环播放'), kNoticeTextColor);
      expect(painted('已从上次位置继续'), kNoticeTextColor);
      expect(painted('不循环'), Colors.lightBlueAccent);
      expect(painted('从头播放？'), Colors.lightBlueAccent);
      await settle(tester, pumped);
    });
  });
}
