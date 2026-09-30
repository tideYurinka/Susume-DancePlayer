import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_state.dart'
    show
        onboardingFlagFields,
        guideSessionProvider;
import 'package:dance_learning_app/help/guide_units_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/failing_private_json_storage.dart';
import '../helpers/guide_units_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/guide_copy_fixture.dart';

void main() {
  /// 全部单元都已完成的存储（重置的对照面：每行都带「重置」）——按注册表的
  /// 状态位 schema 铺满，单元表增项时这里不用改（要改的是下面那份字面量）。
  final allSeen = {
    'onboarding': {
      for (final field in onboardingFlagFields.values) field: true,
    },
  };

  Finder rowOf(String unitId) => find.byKey(Key('guide_unit_$unitId'));

  Finder statusOf(String unitId) => find.byKey(Key('guide_status_$unitId'));

  Finder resetOf(String unitId) => find.byKey(Key('guide_reset_$unitId'));

  group('清点表', () {
    testWidgets('每行 = 标题 + 一句说明 + 「已完成 / 未完成」，已完成的行才有「重置」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'firstRun': true, 'badgeSpeed': false},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      for (final unit in helpGuideUnits) {
        expect(rowOf(unit.id), findsOneWidget);
        expect(
          find.descendant(of: rowOf(unit.id), matching: find.text(guideUnitTitle(unit.id))),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: rowOf(unit.id),
            matching: find.text(guideUnitDescription(unit.id)),
          ),
          findsOneWidget,
        );
        expect(statusOf(unit.id), findsOneWidget);
      }

      // 已完成 → 「已完成」+ 有「重置」；未完成 → 「未完成」+ 无「重置」。
      expect(
        find.descendant(of: rowOf('first_run'), matching: find.text('已完成')),
        findsOneWidget,
      );
      expect(resetOf('first_run'), findsOneWidget);
      expect(
        find.descendant(of: rowOf('badge_speed'), matching: find.text('未完成')),
        findsOneWidget,
      );
      expect(resetOf('badge_speed'), findsNothing);
    });

    testWidgets('三组「起步 / 播放页 / 功能提示」逐组列出，组内按注册表序', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(),
      );
      await openGuideUnitsPage(tester);

      final headers = [
        for (final group in GuideUnitGroup.values)
          find.byKey(Key('guide_group_${group.name}')),
      ];
      for (var i = 0; i < headers.length; i++) {
        expect(headers[i], findsOneWidget);
      }
      // 组次序：起步 → 播放页 → 功能提示。
      for (var i = 1; i < headers.length; i++) {
        expect(
          tester.getTopLeft(headers[i]).dy,
          greaterThan(tester.getTopLeft(headers[i - 1]).dy),
        );
      }

      // 每个单元都在自己那一组里、组内按注册表序，且上一组的最后一行在
      // 下一组标题之上。
      for (var i = 0; i < GuideUnitGroup.values.length; i++) {
        final group = GuideUnitGroup.values[i];
        final units = helpGuideUnits.where((u) => u.group == group).toList();
        expect(units, isNotEmpty, reason: '${group.label} 组不得为空');
        var previousTop = -1.0;
        for (final unit in units) {
          final top = tester.getTopLeft(rowOf(unit.id)).dy;
          expect(
            top,
            greaterThan(tester.getTopLeft(headers[i]).dy),
            reason: '${unit.id} 在「${group.label}」组标题之下',
          );
          expect(top, greaterThan(previousTop), reason: '${unit.id} 按注册表序排列');
          previousTop = top;
        }
        if (i + 1 < GuideUnitGroup.values.length) {
          expect(
            tester.getTopLeft(headers[i + 1]).dy,
            greaterThan(previousTop),
            reason: '下一组标题在上一组各行之下',
          );
        }
      }
    });

    testWidgets('一条都没做过：页顶无「重置所有教程」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(),
      );
      await openGuideUnitsPage(tester);

      expect(find.byKey(const Key('guide_reset_all')), findsNothing);
    });

    testWidgets('有任意一条已完成：页顶出现「重置所有教程」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'badgeRoster': true},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      final resetAll = find.byKey(const Key('guide_reset_all'));
      expect(resetAll, findsOneWidget);
      expect(
        find.descendant(of: resetAll, matching: find.text('重置所有教程')),
        findsOneWidget,
      );
      // 页顶：在所有单元行之上。
      expect(
        tester.getTopLeft(resetAll).dy,
        lessThan(tester.getTopLeft(rowOf(helpGuideUnits.first.id)).dy),
      );
    });

    testWidgets('手机竖屏宽度（360×800）下不溢出：整表可滚动看全', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(initial: allSeen),
      );
      tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();
      await openGuideUnitsPage(tester);

      expect(find.byKey(const Key('guide_units_list')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '一行两枚按钮，窄屏上不得溢出');

      await tester.scrollUntilVisible(rowOf(helpGuideUnits.last.id), 200);
      expect(rowOf(helpGuideUnits.last.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('状态位读不出（无平台通道）：全部按「未完成」，不弹错', (tester) async {
      await pumpGuideUnitsHarness(tester, storage: FailingPrivateJsonStorage());
      await openGuideUnitsPage(tester);

      for (final unit in helpGuideUnits) {
        expect(
          find.descendant(of: rowOf(unit.id), matching: find.text('未完成')),
          findsOneWidget,
          reason: unit.id,
        );
        expect(resetOf(unit.id), findsNothing);
      }
      expect(find.byKey(const Key('guide_reset_all')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('逐条重置', () {
    testWidgets('点「重置」：该行立刻变「未完成」、按钮消失、页面不退出，随即落盘', (tester) async {
      final storage = InMemoryPrivateJsonStorage(initial: allSeen);
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);

      await tester.tap(resetOf('first_run'));
      await tester.pumpAndSettle();

      expect(find.byType(GuideUnitsPage), findsOneWidget, reason: '页面不退出');
      expect(
        find.descendant(of: rowOf('first_run'), matching: find.text('未完成')),
        findsOneWidget,
      );
      expect(resetOf('first_run'), findsNothing, reason: '未完成的行没有可重置的');
      expect(
        (storage.snapshot['onboarding'] as Map)['firstRun'],
        isFalse,
        reason: '清一项随即落盘',
      );
      // 别的单元不受牵连。
      expect(
        find.descendant(of: rowOf('badge_speed'), matching: find.text('已完成')),
        findsOneWidget,
      );
      expect(resetOf('badge_speed'), findsOneWidget);

      // 页面不退出：可以接着重置下一项。
      await tester.tap(resetOf('badge_speed'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: rowOf('badge_speed'), matching: find.text('未完成')),
        findsOneWidget,
      );
      expect(resetOf('badge_speed'), findsNothing);
    });

    testWidgets('重置只动状态位：舞库、设置等其它顶层字段逐位不变', (tester) async {
      final storage = InMemoryPrivateJsonStorage(
        initial: {
          ...allSeen,
          'mirrorDefault': true,
          'danceLibrary': {
            'dances': [
              {'id': 'd1', 'title': '海草舞'},
            ],
          },
        },
      );
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);

      await tester.tap(resetOf('first_run'));
      await tester.pumpAndSettle();

      final snapshot = storage.snapshot;
      expect(snapshot['mirrorDefault'], isTrue);
      expect(snapshot['danceLibrary'], {
        'dances': [
          {'id': 'd1', 'title': '海草舞'},
        ],
      });
      expect((snapshot['onboarding'] as Map)['firstRun'], isFalse);
    });
  });

  group('重置所有教程', () {
    testWidgets('先弹确认；取消则一位不变', (tester) async {
      final storage = InMemoryPrivateJsonStorage(initial: allSeen);
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);
      final before = storage.snapshot;

      await tester.tap(find.byKey(const Key('guide_reset_all')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('guide_reset_all_dialog')), findsOneWidget);

      await tester.tap(find.byKey(const Key('guide_reset_all_cancel')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('guide_reset_all_dialog')), findsNothing);
      expect(storage.snapshot, before, reason: '取消一位不变');
      for (final unit in helpGuideUnits) {
        expect(resetOf(unit.id), findsOneWidget, reason: unit.id);
      }
    });

    testWidgets('确认后全部回「未完成」、页顶按钮消失、落盘全 false', (tester) async {
      final storage = InMemoryPrivateJsonStorage(
        initial: {...allSeen, 'mirrorDefault': true},
      );
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);

      await tester.tap(find.byKey(const Key('guide_reset_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide_reset_all_confirm')));
      await tester.pumpAndSettle();

      for (final unit in helpGuideUnits) {
        expect(
          find.descendant(of: rowOf(unit.id), matching: find.text('未完成')),
          findsOneWidget,
          reason: unit.id,
        );
        expect(resetOf(unit.id), findsNothing, reason: unit.id);
      }
      expect(find.byKey(const Key('guide_reset_all')), findsNothing);
      final flags = storage.snapshot['onboarding'] as Map;
      expect(flags.keys.toSet(), _allFlagFields.toSet());
      expect(flags.values.every((v) => v == false), isTrue);
      expect(storage.snapshot['mirrorDefault'], isTrue, reason: '重置只动状态位');
    });
  });

  group('状态与状态位同一个事实', () {
    testWidgets('页面读面不缓存：进过页面之后在别处置位，再进页面即显示「已完成」', (tester) async {
      final storage = InMemoryPrivateJsonStorage();
      await pumpGuideUnitsHarness(tester, storage: storage);

      // 先开一次页面（此刻一条都没做过，读面算过一份「全未完成」）。
      await openGuideUnitsPage(tester);
      expect(
        find.descendant(of: rowOf('first_run'), matching: find.text('未完成')),
        findsOneWidget,
      );
      await backFromGuideUnitsPage(tester);

      // 回到首页跳过首启（= 置位）：欢迎卡选「跳过教程」，指认步 ✕ 收场，
      // 再进页面。
      await tester.tap(find.text(welcomeSkipLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();
      await openGuideUnitsPage(tester);

      expect(
        find.descendant(of: rowOf('first_run'), matching: find.text('已完成')),
        findsOneWidget,
        reason: '页面显示的必须是当下的状态位，不能是上次读到的旧口径',
      );
      expect(resetOf('first_run'), findsOneWidget);
      expect(find.byKey(const Key('guide_reset_all')), findsOneWidget);
    });

    testWidgets('跳过即置位：跳过首启后，页面上该项显示「已完成」并带「重置」', (tester) async {
      final storage = InMemoryPrivateJsonStorage();
      await pumpGuideUnitsHarness(tester, storage: storage);
      await tester.tap(find.text(welcomeSkipLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('guide_close')));
      await tester.pumpAndSettle();

      await openGuideUnitsPage(tester);

      expect(
        find.descendant(of: rowOf('first_run'), matching: find.text('已完成')),
        findsOneWidget,
      );
      expect(resetOf('first_run'), findsOneWidget);
      expect(find.byKey(const Key('guide_reset_all')), findsOneWidget);
      // 「跳过教程」这一支收场时其余 13 个单元一次置位：每一条都
      // 显示「已完成」并带「重置」，可逐条捡回。
      for (final unit in helpGuideUnits) {
        if (unit.id == 'first_run') continue;
        expect(
          find.descendant(of: rowOf(unit.id), matching: find.text('已完成')),
          findsOneWidget,
          reason: '${unit.id} 应随「跳过教程」一次置位',
        );
        expect(resetOf(unit.id), findsOneWidget, reason: unit.id);
      }
    });
  });

  group('重置的即时性', () {
    testWidgets('不重启即生效：回首页立刻重演首启（无需任何别的重建源）', (tester) async {
      // 本会话里没有任何引导进度（重启后刚打开帮助中心就是这样）：清掉状态位
      // 必须自己把判定读面作废，否则判定还停在「都看过 → 不弹」的旧结果上。
      final storage = InMemoryPrivateJsonStorage(initial: allSeen);
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);
      await tester.tap(resetOf('first_run'));
      await tester.pumpAndSettle();
      await backFromGuideUnitsPage(tester);

      expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
      expect(find.text(welcomeTourLabel), findsOneWidget);
    });

    testWidgets('清掉本会话里该单元的进度：重置后从第 1 步重头，不再接着第 2 步', (tester) async {
      final storage = InMemoryPrivateJsonStorage(
        initial: const {
          'onboarding': {'firstRun': true},
        },
      );
      await pumpGuideUnitsHarness(tester, storage: storage);
      final container = ProviderScope.containerOf(
        tester.element(find.byKey(const Key('import_video_button'))),
        listen: false,
      );
      // 模拟「本会话里刚走完首启欢迎卡」：会话置位与步进度都在。
      container.read(guideSessionProvider.notifier).markSeen('first_run');
      container
          .read(guideSessionProvider.notifier)
          .markStepDone('first_run_welcome');

      await openGuideUnitsPage(tester);
      await tester.tap(resetOf('first_run'));
      await tester.pumpAndSettle();
      await backFromGuideUnitsPage(tester);

      expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
      expect(
        find.text(welcomeTourLabel),
        findsOneWidget,
        reason: '会话进度一并清掉，从第 1 步重演',
      );
    });

    testWidgets('重置本身不演出：页面上不弹引导层、不跳走', (tester) async {
      final storage = InMemoryPrivateJsonStorage(initial: allSeen);
      await pumpGuideUnitsHarness(tester, storage: storage);
      await openGuideUnitsPage(tester);

      await tester.tap(resetOf('first_run'));
      await tester.pumpAndSettle();

      expect(find.byType(GuideUnitsPage), findsOneWidget);
      expect(find.byKey(const Key('guide_bubble')), findsNothing);
      expect(find.byKey(const Key('guide_highlight')), findsNothing);
    });
  });
}

/// 当前 14 个状态位字段名（`onboarding` 对象 schema）的字面量：
/// 期望值不跟着实现转，单元表增项时按新数量在此更新。
const List<String> _allFlagFields = [
  'firstRun',
  'playerDrill',
  'editorIntro',
  'practiceRange',
  'badgeSegment',
  'badgeAutoSegment',
  'badgeBeatPrompt',
  'badgeSpeed',
  'badgeAvSync',
  'badgeRoster',
  'badgeLocalMirror',
  'badgeSegmentFlag',
  'badgeThreeFingerJump',
  'badgeHalfBeat',
];
