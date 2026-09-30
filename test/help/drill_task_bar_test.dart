import 'package:dance_learning_app/help/drill_task_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/guide_assertions.dart';

/// 待办条（动手演练列）：
/// 动作图标 + 待做勾选框 + 一句话 +「N/M」+ 一排进度点 + 带底的「跳过」；
/// 末步的多个子勾以勾片排在文案下方，做对一个亮一个。条身除「跳过」外
/// 一整条不吃触摸——手势照常落到画在其下的画面上。锚点在屏时贴在高亮框旁
/// 否则停靠安全区顶。
void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    bool checked = false,
    String message = '两指张开把这一段放大到好点的大小',
    int stepCount = 3,
    int currentStep = 0,
    List<DrillTaskSubCheck> subChecks = const [],
    String skipLabel = '跳过',
    VoidCallback? onSkip,
    VoidCallback? onBackgroundTap,
    Rect? anchorRect,
  }) async {
    tester.view.physicalSize = const Size(360, 800); // 合成档 360×800dp，非设备档。
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final bar = DrillTaskBar(
      icon: Icons.pinch,
      message: message,
      stepIndicator: stepCount > 1 ? '${currentStep + 1}/$stepCount' : null,
      stepCount: stepCount,
      currentStep: currentStep,
      checked: checked,
      skipLabel: skipLabel,
      subChecks: subChecks,
      onSkip: onSkip ?? () {},
      anchorRect: anchorRect,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // 条子底下的画面：条身覆盖区域里的手势应当落到它身上。
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBackgroundTap ?? () {},
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
              // 停靠时宿主给的是 Positioned.fill 的紧约束；贴框时条子自带
              // Positioned，直接作 Stack 的子。
              if (anchorRect == null) Positioned.fill(child: bar) else bar,
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('条子形状：动作图标、待做的勾选框、一句话、N/M、一排进度点、带底的「跳过」', (tester) async {
    await pumpBar(tester);

    expect(find.byKey(const Key('drill_task_bar')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_icon')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_checkbox')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box_outline_blank,
      reason: '还没做到时勾选框是待做的空框',
    );
    expect(find.text('两指张开把这一段放大到好点的大小'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.byKey(const Key('drill_task_dot_0')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_dot_1')), findsOneWidget);
    expect(find.byKey(const Key('drill_task_dot_2')), findsOneWidget);

    final skip = tester.widget<TextButton>(
      find.byKey(const Key('drill_task_skip')),
    );
    expect(
      skip.style?.backgroundColor?.resolve(const {}),
      isNotNull,
      reason: '「跳过」带底，和一段灰字区分开',
    );
  });

  testWidgets('做到即当场把勾选框填上勾', (tester) async {
    await pumpBar(tester, checked: true);

    expect(
      tester.widget<Icon>(find.byKey(const Key('drill_task_checkbox'))).icon,
      Icons.check_box,
    );
  });

  testWidgets('末步的多个子勾以勾片排在文案下方，做对一个亮一个', (tester) async {
    await pumpBar(
      tester,
      currentStep: 2,
      subChecks: const [
        DrillTaskSubCheck(id: 'double_tap', label: '双击暂停/播放', done: true),
        DrillTaskSubCheck(id: 'long_press', label: '长按临时 2 倍速', done: false),
      ],
    );

    final messageRect = tester.getRect(find.text('两指张开把这一段放大到好点的大小'));
    final doneChip = find.byKey(const Key('drill_task_sub_double_tap'));
    final todoChip = find.byKey(const Key('drill_task_sub_long_press'));
    expect(doneChip, findsOneWidget);
    expect(todoChip, findsOneWidget);
    expect(
      tester.getRect(doneChip).top,
      greaterThanOrEqualTo(messageRect.bottom - 1),
      reason: '子勾片排在文案下方',
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: doneChip, matching: find.byType(Icon)),
          )
          .icon,
      Icons.check_circle,
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(of: todoChip, matching: find.byType(Icon)),
          )
          .icon,
      Icons.radio_button_unchecked,
    );
  });

  testWidgets('条身除「跳过」外不吃触摸：条子覆盖区域里的手势照常落到画面上', (tester) async {
    var backgroundTaps = 0;
    var skipped = 0;
    await pumpBar(
      tester,
      onSkip: () => skipped++,
      onBackgroundTap: () => backgroundTaps++,
    );

    final screenHeight =
        tester.view.physicalSize.height / tester.view.devicePixelRatio;
    final barRect = tester.getRect(find.byKey(const Key('drill_task_bar')));
    expect(barRect.bottom, lessThan(screenHeight), reason: '条子停靠在顶部，不铺满整屏');

    // 条身上的不同位置（文案、图标、进度点）点下去都穿透到画面。
    await tester.tapAt(tester.getCenter(find.text('两指张开把这一段放大到好点的大小')));
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('drill_task_icon'))),
    );
    await tester.pump();
    await tester.tapAt(
      tester.getCenter(find.byKey(const Key('drill_task_dot_0'))),
    );
    await tester.pump();
    expect(backgroundTaps, 3, reason: '条身三处点击都落到条子底下的画面上');

    // 「跳过」是真命中件：点它触发收场、不落到画面。
    await tester.tap(find.byKey(const Key('drill_task_skip')));
    await tester.pump();
    expect(skipped, 1);
    expect(backgroundTaps, 3, reason: '「跳过」不再穿透到画面');
  });

  testWidgets('「跳过」命中盒 ≥48×48（透明外扩，按钮视觉不高过 48）', (tester) async {
    var skipped = 0;
    var backgroundTaps = 0;
    await pumpBar(
      tester,
      onSkip: () => skipped++,
      onBackgroundTap: () => backgroundTaps++,
    );

    // 视觉按钮保持原样（没有为达下限把它撑大）。
    expect(
      tester.getSize(find.byKey(const Key('drill_task_skip'))).height,
      lessThan(48),
      reason: '为达下限把按钮视觉撑大就不是透明外扩',
    );

    final layer = find.byKey(const Key('drill_task_skip_hit'));
    expect(layer, findsOneWidget);
    final size = tester.getSize(layer);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));

    // 按钮下方那段外扩命中域真的由本层接住（不是被条子的 Stack 裁掉只剩
    // 布局尺寸）；按钮自身在其上、中心仍归按钮。
    final center = tester.getCenter(layer);
    final extended = Offset(center.dx, center.dy + 18);
    final layerBox = tester.renderObject<RenderBox>(layer);
    final hit = tester.hitTestOnBinding(extended);
    expect(
      hit.path.any((entry) => entry.target == layerBox),
      isTrue,
      reason: '「跳过」外扩命中域必须由该层接住',
    );

    // 按钮正下方（超出视觉按钮高的位置）仍命中「跳过」、不落到画面。
    await tester.tapAt(Offset(center.dx, center.dy + 18));
    await tester.pump();
    expect(skipped, 1);
    expect(backgroundTaps, 0, reason: '外扩出来的命中区归「跳过」，不穿透');
  });

  testWidgets('贴框落位：条子贴框旁、条宽 320，条身除「跳过」外不吃触摸', (tester) async {
    var skipped = 0;
    var backgroundTaps = 0;
    // 框在屏幕下半 → 条子在框上方 + 朝下箭头（贴框关系由助手逐条断言）。
    const highlight = Rect.fromLTWH(140, 400, 80, 40);
    await pumpBar(
      tester,
      anchorRect: highlight,
      onSkip: () => skipped++,
      onBackgroundTap: () => backgroundTaps++,
    );

    expectDrillBarAnchoredTo(tester, highlight);
    expect(
      tester.getRect(find.byKey(const Key('drill_task_bar'))).width,
      closeTo(320, 1),
      reason: '贴框的条子不近满宽（宽上限 320）',
    );

    // 条身上的不同位置（文案、图标、进度点、箭头）点下去都穿透到画面。
    for (final target in [
      find.text('两指张开把这一段放大到好点的大小'),
      find.byKey(const Key('drill_task_icon')),
      find.byKey(const Key('drill_task_dot_0')),
      find.byKey(const Key('drill_task_arrow')),
    ]) {
      await tester.tapAt(tester.getCenter(target));
      await tester.pump();
    }
    expect(backgroundTaps, 4, reason: '条身四处点击都落到条子底下的画面上');

    // 「跳过」的 48 命中层仍在、仍是真命中件。
    final layer = find.byKey(const Key('drill_task_skip_hit'));
    expect(layer, findsOneWidget);
    expect(tester.getSize(layer).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(layer).height, greaterThanOrEqualTo(48));
    await tester.tap(find.byKey(const Key('drill_task_skip')));
    await tester.pump();
    expect(skipped, 1);
    expect(backgroundTaps, 4, reason: '「跳过」不再穿透到画面');
  });
}
