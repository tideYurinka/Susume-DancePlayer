import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_state.dart'
    show onboardingFlagFields;
import 'package:dance_learning_app/help/help_boxes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/guide_units_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 新手引导页的版式：页顶总览方框的读数与进度条、三组图例方框的
/// 组名与组内计数、每行的状态方框与「已完成 / 未完成」小字同屏，以及窄屏
/// 大字号下的排版兜底。重置的行为语义由 `guide_units_reset_test` 钉住。
void main() {
  Finder rowOf(String unitId) => find.byKey(Key('guide_unit_$unitId'));

  Finder statusBoxOf(String unitId) =>
      find.byKey(Key('guide_status_box_$unitId'));

  Finder statusOf(String unitId) => find.byKey(Key('guide_status_$unitId'));

  Finder groupBoxOf(GuideUnitGroup group) =>
      find.byKey(Key('guide_group_${group.name}'));

  Finder summary() => find.byKey(const Key('guide_summary'));

  group('总览方框', () {
    testWidgets('显示「已完成的引导」、已完成数 / 总项数、百分比与进度条，读数与状态位一致', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'firstRun': true, 'badgeSpeed': true},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      expect(summary(), findsOneWidget);
      expect(
        find.descendant(of: summary(), matching: find.text('已完成的引导')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary(), matching: find.text('2 / 14')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary(), matching: find.text('14%')),
        findsOneWidget,
      );
      final bar = tester.widget<LinearProgressIndicator>(
        find.descendant(
          of: summary(),
          matching: find.byType(LinearProgressIndicator),
        ),
      );
      expect(bar.value, closeTo(2 / 14, 0.001));
    });

    testWidgets('一条都没做过：总览方框仍在，读数为 0 / 14、0%，框内无「重置所有教程」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(),
      );
      await openGuideUnitsPage(tester);

      expect(summary(), findsOneWidget);
      expect(
        find.descendant(of: summary(), matching: find.text('0 / 14')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary(), matching: find.text('0%')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('guide_reset_all')), findsNothing);
    });

    testWidgets('有任意一条已完成：总览方框内出现「重置所有教程」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'badgeRoster': true},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      expect(
        find.descendant(
          of: summary(),
          matching: find.byKey(const Key('guide_reset_all')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('老数据只带已撤下的 badgeCompare：不计入 14 项，读数仍是 0 / 14', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'badgeCompare': true},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      expect(
        find.descendant(of: summary(), matching: find.text('0 / 14')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summary(), matching: find.text('0%')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('guide_reset_all')), findsNothing);
      for (final unit in helpGuideUnits) {
        expect(
          find.descendant(of: rowOf(unit.id), matching: find.text('未完成')),
          findsOneWidget,
          reason: '${unit.id}：旧键不点亮任何一行',
        );
      }
    });
  });

  group('图例方框', () {
    testWidgets('三组各一个图例方框，框顶写组名与「组内已完成数 / 组内项数」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'firstRun': true, 'badgeSpeed': true},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      // 期望值按注册表的固定分组字面量给出，不跟实现转。
      const expected = {
        GuideUnitGroup.start: '1 / 1',
        GuideUnitGroup.player: '0 / 3',
        GuideUnitGroup.hint: '1 / 10',
      };
      for (final group in GuideUnitGroup.values) {
        final box = groupBoxOf(group);
        expect(box, findsOneWidget);
        expect(
          find.descendant(of: box, matching: find.text(group.label)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: box, matching: find.text(expected[group]!)),
          findsOneWidget,
          reason: '${group.label} 的组内计数',
        );
      }
    });

    testWidgets('每组框内只有本组各行，且按注册表序自上而下', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(),
      );
      await openGuideUnitsPage(tester);

      for (final group in GuideUnitGroup.values) {
        final box = groupBoxOf(group);
        final units = helpGuideUnits.where((u) => u.group == group).toList();
        var previousTop = tester.getTopLeft(box).dy;
        for (final unit in units) {
          expect(
            find.descendant(of: box, matching: rowOf(unit.id)),
            findsOneWidget,
            reason: '${unit.id} 在「${group.label}」框内',
          );
          final top = tester.getTopLeft(rowOf(unit.id)).dy;
          expect(top, greaterThan(previousTop), reason: '${unit.id} 按注册表序');
          previousTop = top;
        }
        // 别的组的行不落进本框。
        for (final other in helpGuideUnits.where((u) => u.group != group)) {
          expect(
            find.descendant(of: box, matching: rowOf(other.id)),
            findsNothing,
            reason: '${other.id} 不在「${group.label}」框内',
          );
        }
      }
    });
  });

  group('每一行', () {
    testWidgets('状态方框与「已完成 / 未完成」小字同屏：已完成 = 填底的勾，未完成 = 空框', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: const {
            'onboarding': {'firstRun': true, 'badgeSpeed': false},
          },
        ),
      );
      await openGuideUnitsPage(tester);

      final doneRow = rowOf('first_run');
      expect(statusBoxOf('first_run'), findsOneWidget);
      expect(statusOf('first_run'), findsOneWidget);
      expect(
        find.descendant(of: doneRow, matching: statusBoxOf('first_run')),
        findsOneWidget,
        reason: '状态方框与状态小字落在同一行',
      );
      expect(
        find.descendant(
          of: statusBoxOf('first_run'),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );

      final pendingRow = rowOf('badge_speed');
      expect(statusBoxOf('badge_speed'), findsOneWidget);
      expect(statusOf('badge_speed'), findsOneWidget);
      expect(
        find.descendant(of: pendingRow, matching: statusBoxOf('badge_speed')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: statusBoxOf('badge_speed'),
          matching: find.byIcon(Icons.check),
        ),
        findsNothing,
      );
    });

    testWidgets('命中盒不低于 48：逐条「重置」与「重置所有教程」', (tester) async {
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: {
            'onboarding': {
              for (final field in onboardingFlagFields.values) field: true,
            },
          },
        ),
      );
      await openGuideUnitsPage(tester);

      for (final unit in helpGuideUnits) {
        final size = tester.getSize(find.byKey(Key('guide_reset_${unit.id}')));
        expect(size.width, greaterThanOrEqualTo(48), reason: unit.id);
        expect(size.height, greaterThanOrEqualTo(48), reason: unit.id);
      }
      final resetAll = tester.getSize(find.byKey(const Key('guide_reset_all')));
      expect(resetAll.width, greaterThanOrEqualTo(48));
      expect(resetAll.height, greaterThanOrEqualTo(48));
    });

    testWidgets('窄屏 320 × 2.0 倍字号：整页不溢出、可滚动看全', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpGuideUnitsHarness(
        tester,
        storage: InMemoryPrivateJsonStorage(
          initial: {
            'onboarding': {
              for (final field in onboardingFlagFields.values) field: true,
            },
          },
        ),
      );
      tester.view.physicalSize = const Size(320, 3000); // 合成档 320×3000dp，非设备档。
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpAndSettle();
      await openGuideUnitsPage(tester);

      expect(tester.takeException(), isNull, reason: '320 宽 + 2.0 倍字号下不得溢出');
      expect(rowOf(helpGuideUnits.first.id), findsOneWidget);
      await tester.scrollUntilVisible(rowOf(helpGuideUnits.last.id), 200);
      expect(rowOf(helpGuideUnits.last.id), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('共用件', () {
    testWidgets('图标方框：描边方框内居中一个图标，占列表缩略图同一个 64×44 槽位', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: HelpIconBox(key: Key('box'), icon: Icons.help_outline),
          ),
        ),
      );
      expect(find.byKey(const Key('box')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('box')),
          matching: find.byIcon(Icons.help_outline),
        ),
        findsOneWidget,
      );
      expect(tester.getSize(find.byKey(const Key('box'))), const Size(64, 44));
    });
  });
}
