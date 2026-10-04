import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/player/speed_bubble.dart';
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/speed_step.dart';
import 'package:dance_learning_app/player/speed_step_preset.dart';
import 'package:dance_learning_app/player/speed_step_preset_store.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/bubble_clamp_assertions.dart';
import '../helpers/fake_playback_engine.dart';
import '../helpers/in_memory_private_json_storage.dart';
import '../helpers/semantics_assertions.dart';

/// 量测单行文本宽（纯函数断言用；与气泡内同 baseStyle 时结果一致）。
double _textWidth(String text, double fontSize, [TextStyle? baseStyle]) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: (baseStyle ?? const TextStyle()).merge(
        TextStyle(fontSize: fontSize),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return w;
}

void main() {
  group('气泡族取值集合', () {
    test('SpeedBubbleMode 取值集合：步进并入倍速气泡后无独立步进取值', () {
      expect(SpeedBubbleMode.values.toSet(), const {
        SpeedBubbleMode.speed,
        SpeedBubbleMode.beat,
        SpeedBubbleMode.beatAlign,
        SpeedBubbleMode.beatDensity,
        SpeedBubbleMode.avSync,
      });
    });

    test('两栏几何纯函数：列距 17、分隔线在左栏右缘 + 8、内容宽单源累计', () {
      // 列距口径与节拍提示气泡共用（8 + 1px 线 + 8 = 17）。
      expect(mergedBubbleColumnGap, 17);
      expect(
        mergedBubbleColumnGap,
        mergedBubbleColumnGapSide * 2 + mergedBubbleColumnSeparatorWidth,
      );

      final layout = mergedSpeedBubbleColumns(speedColumnNaturalWidth: 171);
      expect(layout.stepWidth, mergedStepColumnWidth);
      expect(layout.stepWidth, 280);
      expect(layout.speedWidth, 171);
      // 分隔线线中心 = 左栏（步进栏）右缘 + 8（线前间距）。
      expect(
        layout.separatorOffset,
        mergedStepColumnWidth + mergedBubbleColumnGapSide,
      );
      // 内容总宽 = 左栏 + 列距 + 右栏（单源累计，不写死魔法数）。
      expect(
        layout.width,
        layout.stepWidth + mergedBubbleColumnGap + layout.speedWidth,
      );
      expect(layout.width, 468);
      // 气泡外宽 = 内容宽 + 左 8 + 右 12 = 488。
      expect(
        layout.width + speedBubblePaddingLeft + speedBubblePaddingRight,
        488,
      );
      expect(layout.stacked, isFalse, reason: '无可用宽约束时保持并排');
    });

    test('两栏几何纯函数：可用宽不足以并排时上下堆叠、分隔线改横向', () {
      final horizontal = mergedSpeedBubbleColumns(speedColumnNaturalWidth: 171);
      final horizontalBubbleWidth =
          horizontal.width + speedBubblePaddingLeft + speedBubblePaddingRight;
      final stacked = mergedSpeedBubbleColumns(
        speedColumnNaturalWidth: 171,
        availableWidth: horizontalBubbleWidth - 1,
      );

      expect(stacked.stacked, isTrue, reason: '可用宽 < 并排气泡外宽 → 堆叠');
      // 堆叠宽回到既有 300 内容上限；两栏同宽。
      expect(stacked.width, speedBubbleMaxWidth);
      expect(stacked.stepWidth, stacked.width);
      expect(stacked.speedWidth, stacked.width);
      // 横线中心 = 上栏内容高 + 线前间距（竖线的 8+1+8 口径随之旋转）。
      expect(
        stacked.separatorOffset,
        mergedBubbleColumnHeight + mergedBubbleColumnGapSide,
      );
    });

    test('两栏几何纯函数：断点按气泡外宽（含盒边距）判定', () {
      final horizontal = mergedSpeedBubbleColumns(speedColumnNaturalWidth: 171);
      final horizontalBubbleWidth =
          horizontal.width + speedBubblePaddingLeft + speedBubblePaddingRight;
      expect(
        mergedSpeedBubbleColumns(
          speedColumnNaturalWidth: 171,
          availableWidth: horizontalBubbleWidth,
        ).stacked,
        isFalse,
        reason: '可用宽恰等于并排气泡外宽时仍并排',
      );
      expect(
        mergedSpeedBubbleColumns(
          speedColumnNaturalWidth: 171,
          availableWidth: horizontalBubbleWidth - 1,
        ).stacked,
        isTrue,
        reason: '差 1px 放不下气泡留白即堆叠（不留「并排但缩一点」的中间态）',
      );
      // 堆叠内容宽恒为既有 300 上限（倍速栏自然宽更宽也不越过上限）。
      expect(
        mergedSpeedBubbleColumns(
          speedColumnNaturalWidth: 340,
          availableWidth: 100,
        ).width,
        speedBubbleMaxWidth,
      );
    });
  });

  late FakePlaybackEngine engine;
  late InMemoryPrivateJsonStorage storage;
  late ProviderContainer container;

  setUp(() {
    engine = FakePlaybackEngine();
    storage = InMemoryPrivateJsonStorage();
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(engine),
        speedStepPresetStorageProvider.overrideWithValue(
          SpeedStepPresetStore(storage),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  SpeedControlModel model() => container.read(speedControlProvider.notifier);

  Future<void> pumpBubble(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SpeedBubble(key: const Key('speed_bubble_under_test')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void open(SpeedBubbleMode mode) =>
      container.read(speedBubbleSessionProvider.notifier).open(mode);

  SpeedBubbleSessionState session() =>
      container.read(speedBubbleSessionProvider);

  /// 宿主 seam：锚点控件贴屏幕右缘（观看态胶囊 / 编辑态近右缘图标同一宿主
  /// 路径），气泡被水平钳制进屏；[placeAnchor] 决定锚点位置。
  Future<void> pumpHost(
    WidgetTester tester, {
    required LayerLink link,
    required Positioned Function(Widget target) placeAnchor,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                placeAnchor(
                  CompositedTransformTarget(
                    link: link,
                    child: const SizedBox(
                      key: Key('bubble_anchor'),
                      width: 80,
                      height: 40,
                    ),
                  ),
                ),
                SpeedBubbleHost(
                  linkFor: (_) => link,
                  targetAnchor: Alignment.topCenter,
                  followerAnchor: Alignment.bottomCenter,
                  offset: const Offset(0, -8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('倍速气泡（顶部输入标题条 + 横向三列）', () {
    testWidgets('主体三列：常规档位列六档（无 2.0）| 历史列 | 竖向滑条', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('speed_columns_row')), findsOneWidget);
      expect(find.byKey(const Key('speed_quick_column')), findsOneWidget);
      expect(find.byKey(const Key('speed_history_column')), findsOneWidget);

      for (final rate in commonSpeeds) {
        expect(
          find.byKey(Key('speed_quick_${rate.toString()}')),
          findsOneWidget,
          reason: '常规档位 $rate 应在快捷列展示',
        );
      }
      // 2.0 已移出快捷档。
      expect(find.byKey(const Key('speed_quick_2.0')), findsNothing);
      // 不再有「自定义…」纵向折叠入口。
      expect(find.text('自定义…'), findsNothing);

      // 竖向滑条（自定义竖滑条）：竖轨厚度 ≈28dp。
      final track = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider_track')),
      );
      expect(
        (track.size.width - speedSliderTrackThickness).abs(),
        lessThan(0.5),
        reason: '竖轨厚度≈28dp',
      );
    });

    testWidgets('常驻/历史两列均分左区宽——两列等宽、列宽只由左区宽决定、文字居中且字号 13', (tester) async {
      RenderBox boxOf(Key key) =>
          tester.renderObject<RenderBox>(find.byKey(key));
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final columnsRow = boxOf(const Key('speed_columns_row'));
      final resident = boxOf(const Key('speed_quick_column'));
      final history = boxOf(const Key('speed_history_column'));

      // 常驻/历史两列等宽，各列 = (左区宽 − 列距)/2（列宽只由左区宽决定，
      // 与内容/历史有无无关；此处历史为空亦与常驻列同宽、不收缩）。
      expect(
        find.byKey(const Key('speed_history_empty')),
        findsOneWidget,
        reason: '无历史时显示「暂无历史」占位',
      );
      expect(
        (resident.size.width - history.size.width).abs(),
        lessThan(0.5),
        reason: '常驻/历史两列等宽（均分左区）',
      );
      final expectedColumn = (columnsRow.size.width - speedGroupGap) / 2;
      expect(
        (resident.size.width - expectedColumn).abs(),
        lessThan(0.5),
        reason: '列宽 = (左区宽 − 列距)/2，只由左区宽决定',
      );

      // 常驻列按钮与列同宽、文字居中、字号 13。
      for (final rate in commonSpeeds) {
        final key = Key('speed_quick_$rate');
        final box = boxOf(key);
        expect(
          (box.size.width - resident.size.width).abs(),
          lessThan(0.5),
          reason: '$rate 按钮与列同宽',
        );
        final text = tester.widget<Text>(
          find.descendant(of: find.byKey(key), matching: find.byType(Text)),
        );
        expect(text.textAlign, TextAlign.center, reason: '$rate 文字居中');
        expect(text.style?.fontSize, rateOptionFontSize, reason: '$rate 字号 13');
      }
    });

    testWidgets('组间距 = 列间距 = 6（常量锚定 + 实测）', (tester) async {
      expect(speedGroupGap, 6, reason: '组间距 = 列间距常量 = 6dp');

      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 常规列与历史列实际间距 = 6dp。
      final quick = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_quick_column')),
      );
      final history = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_history_column')),
      );
      final gap =
          history.localToGlobal(Offset.zero).dx -
          (quick.localToGlobal(Offset.zero).dx + quick.size.width);
      expect((gap - speedGroupGap).abs(), lessThan(0.5), reason: '两列间实际间距 6dp');
    });

    testWidgets('「×」不换行——档位按钮单钮高 32、同列等高、space-between 行距 g=4', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final tops = <double>[];
      for (final rate in commonSpeeds) {
        final box = tester.renderObject<RenderBox>(
          find.byKey(Key('speed_quick_$rate')),
        );
        // 单钮高 32（上下 padding 7 + 单行文本）。
        expect(
          box.size.height,
          speedRateButtonHeight,
          reason: '$rate 单钮高 32（单行不换行）',
        );
        tops.add(box.localToGlobal(Offset.zero).dy);
      }
      expect(tops.toSet().length, 6, reason: '六钮纵位互异（space-between 铺满）');

      // 行距 g = 4：定高列 212 内 space-between 均铺——相邻钮间距恒为
      // 32 + g = 36（±0.5 浮点容差；遍历序与渲染序相反，取绝对差）。
      for (var i = 1; i < tops.length; i++) {
        expect(
          ((tops[i] - tops[i - 1]).abs() -
                  (speedRateButtonHeight + speedRateRowGap))
              .abs(),
          lessThan(0.5),
          reason: '相邻档位行距 g = ${speedRateRowGap}dp（唯一纵向自由参数）',
        );
      }
    });

    testWidgets('档位按钮 padding 横 3 / 纵 7——单钮高 32（仍可点：点档生效）', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // padding：横向 3dp、纵向 7（单钮加高便于触控）。
      final padding = tester.widget<Padding>(
        find
            .descendant(
              of: find.byKey(Key('speed_quick_${commonSpeeds.first}')),
              matching: find.byType(Padding),
            )
            .first,
      );
      expect(
        padding.padding,
        const EdgeInsets.symmetric(
          horizontal: rateOptionHorizontalPadding,
          vertical: speedRateOptionVerticalPadding,
        ),
      );
      expect(rateOptionHorizontalPadding, 3, reason: '档位按钮横向 padding 3dp');
      expect(speedRateOptionVerticalPadding, 7, reason: '档位按钮纵向 padding 7');

      // 仍保证触控可用：点档即生效并收起。
      await tester.tap(find.byKey(const Key('speed_quick_0.75')));
      await tester.pumpAndSettle();
      expect(engine.rate, 0.75);
    });

    testWidgets('点常规档位即生效并收起', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speed_quick_0.75')));
      await tester.pumpAndSettle();

      expect(engine.rate, 0.75);
      expect(session().open, isNull, reason: '速选档点选即生效并收起');
    });

    testWidgets('合并两栏：左步进栏 280 | 列距 17（满高竖分隔线）| 右倍速栏；气泡宽 = 内容宽 + 盒边距', (
      tester,
    ) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final step = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_step_column')),
      );
      final rate = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );

      // 左栏（步进栏）定宽 280。
      expect(step.size.width, mergedStepColumnWidth);
      // 列距 = 17（8 + 1px 线 + 8）；分隔线画在列距中央（纯函数口径）。
      final gap =
          rate.localToGlobal(Offset.zero).dx -
          (step.localToGlobal(Offset.zero).dx + step.size.width);
      expect(gap, closeTo(mergedBubbleColumnGap, 0.5));
      // 气泡宽 = 左栏宽 + 列距 + 右栏宽 + 盒边距（派生关系，不写死）。
      expect(
        bubble.size.width,
        closeTo(
          step.size.width +
              mergedBubbleColumnGap +
              rate.size.width +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
          0.5,
        ),
      );
      // 两栏顶对齐。
      expect(
        (step.localToGlobal(Offset.zero).dy -
                rate.localToGlobal(Offset.zero).dy)
            .abs(),
        lessThan(0.5),
      );
      // 分隔线位置与纯函数单源（左栏右缘 + 线前间距）；并排时为竖线。
      final layout = mergedSpeedBubbleColumns(
        speedColumnNaturalWidth: rate.size.width,
      );
      expect(
        layout.separatorOffset,
        step.size.width + mergedBubbleColumnGapSide,
      );
      final sepRect = tester.getRect(
        find.byKey(const Key('speed_merged_separator')),
      );
      expect(sepRect.height, greaterThan(sepRect.width), reason: '并排分隔线为竖线');
      expect(
        sepRect.center.dx,
        closeTo(
          step.localToGlobal(Offset.zero).dx +
              layout.separatorOffset +
              mergedBubbleColumnSeparatorWidth / 2,
          0.5,
        ),
      );
    });

    testWidgets('气泡总高恒为 260（= 8 + 栏内容 240 + 12），左栏（步进栏）定高 240', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      expect(mergedBubbleHeight, 260);
      expect(
        mergedBubbleHeight,
        speedBubblePaddingTop +
            mergedBubbleColumnHeight +
            speedBubblePaddingBottom,
      );
      expect(
        mergedBubbleColumnHeight,
        speedTitleHeight + speedTitleColumnGap + speedColumnsBlockHeight,
        reason: '步进栏定高 = 倍速栏内容高（派生）',
      );
      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final step = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_step_column')),
      );
      expect(bubble.size.height, mergedBubbleHeight);
      expect(step.size.height, mergedBubbleColumnHeight);
    });

    testWidgets('步进栏栏头「倍速步进」；步进生效时右端「已启用」、停用后消失且选中保留', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      expect(find.text('倍速步进'), findsOneWidget);
      expect(find.byKey(const Key('speed_step_enabled_badge')), findsNothing);

      await container
          .read(speedStepPresetProvider.notifier)
          .select('builtin_review');
      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_step_enabled_badge')), findsOneWidget);

      await container.read(speedControlProvider.notifier).setStepEnabled(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_step_enabled_badge')), findsNothing);
      expect(
        container.read(speedStepPresetProvider).selectedId,
        'builtin_review',
        reason: '停用只撤「已启用」，「选中」保留',
      );
    });

    testWidgets('滑条整高派生——高 = 列高+22 = 234、顶 = 标题顶+6、底 = 列底', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 派生常量锁定（唯一自由参数 g → 一切派生随之）。
      expect(speedColumnsBlockHeight, 212, reason: '列高 = 6×32 + 5×4 = 212');
      expect(
        speedSliderColumnHeight,
        speedColumnsBlockHeight + 22,
        reason: '滑条整高 = 列高 + 22（派生，不独立定值）',
      );
      expect(speedSliderColumnHeight, 234);

      final title = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_title')),
      );
      final slider = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider')),
      );
      final columnsRow = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_columns_row')),
      );
      // 顶 = 标题顶 + 6（锚定约束①）。
      expect(
        (slider.localToGlobal(Offset.zero).dy -
                (title.localToGlobal(Offset.zero).dy + speedSliderTopOffset))
            .abs(),
        lessThan(2),
        reason: '滑条顶 = 标题顶 + 6',
      );
      // 底 = 双列块底（锚定约束②）。
      expect(
        ((slider.localToGlobal(Offset.zero).dy + slider.size.height) -
                (columnsRow.localToGlobal(Offset.zero).dy +
                    columnsRow.size.height))
            .abs(),
        lessThan(2),
        reason: '滑条底 = 列底（派生关系锁定）',
      );
      // 整高 = 234（显式定高）。
      expect(slider.size.height, speedSliderColumnHeight);
    });

    testWidgets('竖滑条左侧常驻刻度尺——大刻度数字 + 细分小刻度、与取值同步', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 刻度尺常驻：位于竖轨左侧（气泡展开即存在）。
      final ruler = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_ruler')),
      );
      final track = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider_track')),
      );
      expect(
        ruler.localToGlobal(Offset.zero).dx + ruler.size.width,
        lessThanOrEqualTo(track.localToGlobal(Offset.zero).dx),
        reason: '刻度尺在竖轨左侧',
      );

      // 带文字标签 = 0.1（最低）/0.5/1.0/1.5（最高），734。
      for (final label in const ['0.1', '0.5', '1.0', '1.5']) {
        expect(
          find.byKey(Key('speed_rate_ruler_label_$label')),
          findsOneWidget,
          reason: '刻度标签 $label（端点/主刻度）带数字',
        );
      }

      // 刻度与滑条取值同步：标签纵位 = 该值在 0.1–1.5 线性映射的位置。
      final rulerTop = ruler.localToGlobal(Offset.zero).dy;
      for (final entry in const {
        '0.1': 0.1,
        '0.5': 0.5,
        '1.0': 1.0,
        '1.5': 1.5,
      }.entries) {
        final value = entry.value;
        final expectedTopFraction =
            1 - (value - speedRateMin) / (speedSliderMax - speedRateMin);
        final box = tester.renderObject<RenderBox>(
          find.byKey(Key('speed_rate_ruler_label_${entry.key}')),
        );
        final centerDy =
            box.localToGlobal(box.size.center(Offset.zero)).dy - rulerTop;
        expect(
          (centerDy - expectedTopFraction * ruler.size.height).abs(),
          lessThan(2),
          reason: '标签 ${entry.key} 纵位与滑条取值 $value 线性同步',
        );
      }
    });

    testWidgets('移除拇指旁动态数值——实时值只由标题栏显示并随拖动同步', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 拇指旁无动态数值。
      expect(
        find.byKey(const Key('speed_rate_slider_value')),
        findsNothing,
        reason: '拇指旁不再有动态数值',
      );

      // 拖动滑条：倍速实时生效，标题栏同步显示新值，且无任何拇指数值出现。
      await tester.drag(
        find.byKey(const Key('speed_rate_slider')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(engine.rate, greaterThan(1.0), reason: '向上拖 = 加速');
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('${formatRate(engine.rate)}x'),
        ),
        findsOneWidget,
        reason: '实时值只由标题栏显示并随拖动同步',
      );
      expect(
        find.byKey(const Key('speed_rate_slider_value')),
        findsNothing,
        reason: '拖动后也不出现拇指旁数值',
      );
      // 刻度尺标签为静态（不随值重排）：拖动后仍是 0.1/0.5/1.0/1.5。
      for (final label in const ['0.1', '0.5', '1.0', '1.5']) {
        expect(
          find.byKey(Key('speed_rate_ruler_label_$label')),
          findsOneWidget,
          reason: '刻度尺标签静态（端点/主刻度）',
        );
      }
    });

    testWidgets('滑条报滑条角色、当前值与可增减；增减确实改倍率', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final slider = find.byKey(const Key('speed_rate_slider_semantics'));
      final data = tester.getSemantics(slider).getSemanticsData();

      // 角色 + 名字：滑条并报得出它是什么（不是一串「按钮」里的一个无名
      // 可点区）；装饰档的刻度数字不拼进这个名字。
      expect(data.flagsCollection.isSlider, isTrue, reason: '滑条角色');
      expect(data.label, '倍速', reason: '滑条名字');
      // 当前值 + 可增减的下一步结果：读屏问得出「现在多少、按了会变成多少」。
      expect(data.value, '${formatRate(engine.rate)}x', reason: '当前值');
      expect(
        data.increasedValue,
        '${formatRate(engine.rate + speedSliderStep)}x',
        reason: '增大后的值',
      );
      expect(
        data.decreasedValue,
        '${formatRate(engine.rate - speedSliderStep)}x',
        reason: '减小后的值',
      );
      expect(data.hasAction(SemanticsAction.increase), isTrue);
      expect(data.hasAction(SemanticsAction.decrease), isTrue);
      // 拖动/点按的原始手势动作不另生无名节点（可操作面就是增减）。
      expect(data.hasAction(SemanticsAction.scrollUp), isFalse);
      expect(data.hasAction(SemanticsAction.scrollDown), isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);

      // 增减确实改倍率：与拖动同一个写入口，一步 = 一个 step。
      // 测试绑定的语义树挂在 binding.pipelineOwner（rootPipelineOwner 之外）。
      // ignore: deprecated_member_use
      final owner = tester.binding.pipelineOwner.semanticsOwner!;
      final before = engine.rate;
      owner.performAction(
        tester.getSemantics(slider).id,
        SemanticsAction.increase,
      );
      await tester.pumpAndSettle();
      expect(
        engine.rate,
        closeTo(before + speedSliderStep, 1e-9),
        reason: '增大动作真的加速',
      );

      owner.performAction(
        tester.getSemantics(slider).id,
        SemanticsAction.decrease,
      );
      await tester.pumpAndSettle();
      expect(engine.rate, closeTo(before, 1e-9), reason: '减小动作真的减速');
      handle.dispose();
    });

    testWidgets('刻度列显式定高——刻度尺/竖轨高度恒为固定常量、标签在气泡可视范围内', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 定高实现：刻度尺列与竖轨高度 = 显式固定常量（不依赖
      // IntrinsicHeight 链的高度推断——真机上推断可为 0 使标签不可见）。
      final ruler = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_ruler')),
      );
      final track = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider_track')),
      );
      expect(ruler.size.height, speedSliderColumnHeight, reason: '刻度尺列显式定高');
      expect(track.size.height, speedSliderColumnHeight, reason: '竖轨同高');
      expect(ruler.size.height, greaterThan(0));

      // 定高常量与左列的派生关系显式化：
      // 双列块实际高度 = 派生常量 212（6×32 + 5×g），滑条列高 = 列高 + 22。
      final columnsRow = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_columns_row')),
      );
      expect(
        columnsRow.size.height,
        speedColumnsBlockHeight,
        reason: '双列块实际高度 = 派生常量（6×32 + 5×g = 212）',
      );
      expect(
        ruler.size.height,
        speedColumnsBlockHeight + 22,
        reason: '滑条整高 = 列高 + 22（派生关系锁定）',
      );

      // 标签整体落在气泡可视范围内（真机回归锚：标签不再锚出可视区）。
      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final bubbleTop = bubble.localToGlobal(Offset.zero).dy;
      final bubbleBottom = bubbleTop + bubble.size.height;
      for (final label in const ['0.1', '0.5', '1.0', '1.5']) {
        final box = tester.renderObject<RenderBox>(
          find.byKey(Key('speed_rate_ruler_label_$label')),
        );
        final top = box.localToGlobal(Offset.zero).dy;
        expect(
          top,
          greaterThanOrEqualTo(bubbleTop - 1),
          reason: '标签 $label 顶部在气泡内',
        );
        expect(
          top + box.size.height,
          lessThanOrEqualTo(bubbleBottom + 1),
          reason: '标签 $label 底部在气泡内',
        );
      }
    });

    test('刻度尺纵位映射纯函数——min 在下比例 1、max 在上比例 0、中间线性、越界钳制', () {
      expect(
        speedRulerTopFraction(
          value: speedRateMin,
          min: speedRateMin,
          max: speedSliderMax,
        ),
        1,
      );
      expect(
        speedRulerTopFraction(
          value: speedSliderMax,
          min: speedRateMin,
          max: speedSliderMax,
        ),
        0,
      );
      final mid = speedRulerTopFraction(
        value: (speedRateMin + speedSliderMax) / 2,
        min: speedRateMin,
        max: speedSliderMax,
      );
      expect((mid - 0.5).abs(), lessThan(1e-9), reason: '中点线性映射 0.5');
      // 越界钳制：映射只在 [0, 1]。
      expect(
        speedRulerTopFraction(value: 0, min: speedRateMin, max: speedSliderMax),
        1,
      );
      expect(
        speedRulerTopFraction(
          value: 99,
          min: speedRateMin,
          max: speedSliderMax,
        ),
        0,
      );
    });

    test('刻度尺刻度布局纯函数——标签 0.1/0.5/1.0/1.5（端点+主刻度）+ 细分小刻度无字、恒在值域内', () {
      final ticks = speedRulerTicks(min: speedRateMin, max: speedSliderMax);
      // 带文字标签 = 取值范围端点（最低 0.1/最高 1.5）叠加 0.5 主刻度
      // （0.5/1.0/1.5）→ 标签集 {0.1, 0.5, 1.0, 1.5}。
      final majors = ticks.where((t) => t.major).toList();
      expect([for (final t in majors) t.value], [0.1, 0.5, 1.0, 1.5]);
      expect([for (final t in majors) t.label], ['0.1', '0.5', '1.0', '1.5']);
      // 细分小刻度无字、不含端点、落在值域内、升序无重复、在 0.1 网格。
      final minors = ticks.where((t) => !t.major).toList();
      expect(minors.length, greaterThan(3), reason: '存在细分小刻度');
      expect(
        [for (final t in minors) t.label],
        everyElement(isNull),
        reason: '细分小刻度无文字标签（仅主刻度/端点带字）',
      );
      expect(
        minors.map((t) => t.value),
        isNot(contains(speedRateMin)),
        reason: '最低值已是大刻度标签，不在细分小刻度里',
      );
      expect(
        minors.map((t) => t.value),
        isNot(contains(speedSliderMax)),
        reason: '最高值已是大刻度标签，不在细分小刻度里',
      );
      for (final t in minors) {
        expect(t.value, inInclusiveRange(speedRateMin, speedSliderMax));
      }
      final values = [for (final t in ticks) t.value];
      expect(values, orderedEquals(values.toSet()), reason: '无重复');
      expect(values, values.toList()..sort(), reason: '升序');
      for (final t in minors) {
        expect(
          ((t.value * 10).round()) % 1,
          0,
          reason: '${t.value} 在 0.1 细分网格',
        );
      }
    });

    test('取值范围端点即使非 0.5 主刻度也带字（与取值范围同步）', () {
      // 端点 min=0.3 / max=1.3 在 0.1 网格上但非 0.5 主刻度：仅因是取值端点
      // 即带文字标签（而非仅主刻度带字）。标签集 = {0.3, 0.5, 1.0, 1.3}。
      final ticks = speedRulerTicks(min: 0.3, max: 1.3);
      final majors = ticks.where((t) => t.major).map((t) => t.value).toList();
      expect(majors.first, 0.3, reason: '最低端点恒带文字标签');
      expect(majors.last, 1.3, reason: '最高端点恒带文字标签');
      expect(majors, containsAllInOrder([0.3, 0.5, 1.0, 1.3]));
    });

    testWidgets('历史列与常驻列同宽、宽度不随历史有无/内容收缩；气泡宽两态不变', (tester) async {
      RenderBox boxOf(Key key) =>
          tester.renderObject<RenderBox>(find.byKey(key));
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 无历史时历史槽显示「暂无历史」占位，列宽 = 常驻列宽（不隐藏不收缩）。
      expect(find.byKey(const Key('speed_history_empty')), findsOneWidget);
      final residentEmpty = boxOf(const Key('speed_quick_column')).size.width;
      final historyEmpty = boxOf(const Key('speed_history_column')).size.width;
      final bubbleEmpty = boxOf(const Key('speed_bubble')).size.width;
      expect(
        (residentEmpty - historyEmpty).abs(),
        lessThan(0.5),
        reason: '无历史时历史列与常驻列等宽（空态不收缩）',
      );

      // 记录非快捷档历史后：两列仍等宽、常驻列宽与气泡宽均不变（两态零移动）。
      final model2 = container.read(speedControlProvider.notifier);
      for (final r in const [0.8, 1.8, 2.0]) {
        model2.recordHistory(r);
      }
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_history_empty')), findsNothing);
      final residentFilled = boxOf(const Key('speed_quick_column')).size.width;
      final historyFilled = boxOf(const Key('speed_history_column')).size.width;
      final bubbleFilled = boxOf(const Key('speed_bubble')).size.width;
      expect(
        (residentFilled - historyFilled).abs(),
        lessThan(0.5),
        reason: '有历史时历史列与常驻列仍等宽',
      );
      expect(
        (residentFilled - residentEmpty).abs(),
        lessThan(0.5),
        reason: '历史有无切换不改变列宽',
      );
      expect(
        (bubbleFilled - bubbleEmpty).abs(),
        lessThan(0.5),
        reason: '历史有无切换气泡宽严格不变（布局不移动）',
      );
      // 历史档按钮与列同宽。
      for (final r in const [0.8, 1.8, 2.0]) {
        final key = Key('speed_history_$r');
        expect(find.byKey(key), findsOneWidget, reason: '历史档 $r 展示');
        expect(
          (boxOf(key).size.width - historyFilled).abs(),
          lessThan(0.5),
          reason: '历史档 $r 按钮与列等宽',
        );
      }
    });

    test('档位列宽纯函数——列宽 = 最宽文本 + 2×横向内边距 + 布局余量（更宽文本 → 更宽列）', () {
      // seam 仅推导单列内容所需宽度（同时是常驻列内容下限）。
      expect(
        rateOptionColumnWidth(['1x']),
        lessThan(rateOptionColumnWidth(['1.25x'])),
        reason: '列宽随最宽文本增长',
      );
      expect(
        rateOptionColumnWidth(['1.25x']),
        lessThan(rateOptionColumnWidth(['1.25x', '1.125x'])),
        reason: '取最宽文本推导（加入更宽文本后列宽增大）',
      );
      expect(
        rateOptionColumnWidth(['1.25x']),
        closeTo(
          _textWidth('1.25x', rateOptionFontSize) +
              rateOptionHorizontalPadding * 2 +
              rateOptionWidthSlack,
          0.5,
        ),
        reason: '列宽 = 最宽文本宽 + 2×横向内边距 + 布局余量',
      );
    });

    test('标题自然宽纯函数——稳定，且 ≥ 标签+间距+最宽候选值文本（值文本永不越界的前提）', () {
      // 稳定：同参数重复调用结果一致。
      expect(measureRateTitleWidth(), measureRateTitleWidth());
      // 下限：至少容纳「当前倍速」标签(12px) + 间距(8) + 最宽候选项值文本
      // (16px)。若最宽候选扫描误删/杂项为负，此下限即被打破——配合 widget
      // 几何用例（0.25x/1x/2x 不越左缘）共同锚定标题自然宽。
      final widestValue = rateCandidates()
          .map((r) => _textWidth('${formatRate(r)}x', 16))
          .reduce((a, b) => a > b ? a : b);
      expect(
        measureRateTitleWidth(),
        greaterThanOrEqualTo(_textWidth('当前倍速', 12) + 8 + widestValue),
        reason: '标题自然宽至少容纳标签+间距+最宽值文本',
      );
    });

    testWidgets('历史档位展示条数设上限（单气泡不滚动的兜底；不改记录语义）', (tester) async {
      expect(speedHistoryDisplayLimit, greaterThanOrEqualTo(1));

      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final model2 = container.read(speedControlProvider.notifier);
      const extra = [0.3, 0.35, 0.4, 0.45, 0.55, 0.6, 0.65, 0.7];
      for (final r in extra) {
        model2.recordHistory(r);
      }
      await tester.pumpAndSettle();

      final shown = find.byWidgetPredicate(
        (w) =>
            w.key is ValueKey<String> &&
            RegExp(r'^speed_history_\d')
                .hasMatch((w.key as ValueKey<String>).value),
      );
      expect(
        tester.widgetList(shown).length,
        lessThanOrEqualTo(speedHistoryDisplayLimit),
        reason: '历史列展示条数 ≤ 上限（记录本身不裁剪）',
      );
      // 记录语义不变：模型历史仍含全部记录。
      expect(
        container.read(speedControlProvider).history.length,
        greaterThanOrEqualTo(extra.length),
      );
    });

    testWidgets('整面板单气泡完整显示——内容量上限内零可滚距离（含满历史）', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 气泡外壳（@scaffold 的滚动兜底）在内容量上限内滚动距离恒为 0。
      double outerMaxScrollExtent() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .maxScrollExtent;
      expect(outerMaxScrollExtent(), 0, reason: '合并气泡外壳无滚动距离');

      // 满历史（达展示上限）仍完整显示、无滚动。
      final model2 = container.read(speedControlProvider.notifier);
      for (final r in const [0.3, 0.35, 0.4, 0.45, 0.55, 0.6, 0.65, 0.7]) {
        model2.recordHistory(r);
      }
      await tester.pumpAndSettle();
      expect(outerMaxScrollExtent(), 0, reason: '历史上限兜底后仍单气泡完整显示');

      // 步进栏（预设列表 + 编辑器）在上限内同样完整显示、无滚动。
      double stepMaxScrollExtent() => tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(const Key('speed_step_column_scroll')),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position
          .maxScrollExtent;
      expect(stepMaxScrollExtent(), 0, reason: '步进栏列表无滚动距离');
      await tester.tap(find.byKey(const Key('speed_step_edit_builtin_first')));
      await tester.pumpAndSettle();
      expect(stepMaxScrollExtent(), 0, reason: '步进栏编辑器无滚动距离');
      expect(outerMaxScrollExtent(), 0, reason: '编辑器仍不改变气泡外壳滚动');
    });

    testWidgets('历史列：空态占位；有历史时去重最近在前、点历史档生效收起', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 空态占位。
      expect(find.byKey(const Key('speed_history_empty')), findsOneWidget);

      // 0.5/1.25 是快捷档：历史列不重复展示（无历史条目、空态保持）。
      model().recordHistory(1.25);
      model().recordHistory(0.5);
      model().recordHistory(1.25); // 去重：1.25 提到最前。
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_history_1.25')), findsNothing);
      expect(find.byKey(const Key('speed_history_empty')), findsOneWidget);

      // 非快捷档的自定义历史值显示在历史列（空态消失）。
      model().recordHistory(0.8);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_history_0.8')), findsOneWidget);
      expect(find.byKey(const Key('speed_history_empty')), findsNothing);

      await tester.tap(find.byKey(const Key('speed_history_0.8')));
      await tester.pumpAndSettle();
      expect(engine.rate, 0.8);
      expect(session().open, isNull);
    });

    testWidgets('历史列按倍速值降序渲染（忽略最近先后、去重）；非快捷值落入历史列', (tester) async {
      double topOf(Key key) => tester
          .renderObject<RenderBox>(find.byKey(key))
          .localToGlobal(Offset.zero)
          .dy;
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 以「最近在前」插入 0.3 / 1.8（历史模型语义去重最近在前）。插入序
      // 使最近 = 1.8（最大）——借此证明展示序忽略最近先后、只看值。
      model().recordHistory(0.3);
      model().recordHistory(1.8);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_history_0.3')), findsOneWidget);
      expect(find.byKey(const Key('speed_history_1.8')), findsOneWidget);

      // 忽略最近先后、按倍速值降序：1.8 在 0.3 之上（展示序只看值不看
      // 最近先后）。
      expect(
        topOf(const Key('speed_history_1.8')),
        lessThan(topOf(const Key('speed_history_0.3'))),
        reason: '历史列按倍速值降序（1.8x 在 0.3x 之上，忽略最近先后）',
      );
      // 去重：同值只渲染一次。
      for (final r in const [0.3, 1.8]) {
        expect(
          find.byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key as ValueKey<String>).value == 'speed_history_$r',
          ),
          findsOneWidget,
          reason: '$r 同值历史去重、不重复渲染',
        );
      }
    });

    testWidgets('常驻/历史两列顶部均无列标题', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 两列顶部无列标题：不渲染「常驻/常用/历史」等列头文字。
      // find.text 默认整串匹配，「暂无历史」空态占位不误命中「历史」。
      for (final header in const ['常驻', '常用', '历史']) {
        expect(find.text(header), findsNothing, reason: '不应渲染列标题「$header」');
      }
    });

    testWidgets('标题条为倍率下拉，选中合法值即生效且不收起', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 标题条初值 = 当前实际倍速（默认 1x）。
      expect(find.byKey(const Key('speed_rate_title')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('1x'),
        ),
        findsOneWidget,
      );

      // 1.8 先入历史（历史置顶 → 在菜单可见区内；菜单列表虚拟化只构建
      // 可见项）。下拉选择 1.8：即生效、气泡保持展开（无手输、越界值不可达）。
      model().recordHistory(1.8);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_rate_select')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1.8x').last);
      await tester.pumpAndSettle();

      expect(engine.rate, 1.8);
      expect(session().open, SpeedBubbleMode.speed, reason: '下拉选中生效不收起');
      // 标题跟随新值（双向同步）。
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('1.8x'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('下拉候选集 = 当前值 + 常用/历史置顶 + 0.05 全档', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      model().recordHistory(1.8);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_rate_select')));
      await tester.pumpAndSettle();

      // 菜单列表虚拟化（只构建可见项）：限定菜单 ListView（下拉按钮自身
      // 也构建选中项）。断言已构建项都在 0.05 全档内（全档完备性由候选集
      // 纯函数用例覆盖），并断言置顶次序。
      final optionKeys = tester
          .widgetList<DropdownMenuItem<double>>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(DropdownMenuItem<double>),
            ),
          )
          .map((item) => (item.key as ValueKey<String>).value)
          .map((key) => key.replaceFirst('speed_rate_option_', ''))
          .toList();
      final gridKeys = rateCandidates().map((r) => '$r').toSet();
      for (final key in optionKeys) {
        expect(
          gridKeys.contains(key),
          isTrue,
          reason: '候选 $key 应在 0.1–2.0 步 0.05 全档内',
        );
      }
      // 置顶次序：当前值（1.0）→ 常用 → 历史（1.8 紧随常用其后）→ 全档。
      expect(optionKeys.first, '1.0', reason: '当前值置顶');
      expect(optionKeys[1], '0.25', reason: '常用次之');
      expect(optionKeys.indexOf('1.8'), 6, reason: '历史值紧跟常用之后（1.0 去重）');
    });

    testWidgets('双向同步：点档生效后重开，标题条跟随新值；滑条拖动后标题跟随', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speed_quick_0.5')));
      await tester.pumpAndSettle();
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('0.5x'),
        ),
        findsOneWidget,
        reason: '档位生效 → 标题条跟随',
      );

      // 滑条拖动（向上拖 = 加速）实时生效，标题跟随、气泡不收起。
      await tester.drag(
        find.byKey(const Key('speed_rate_slider')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(engine.rate, greaterThan(0.5), reason: '竖向滑条拖动实时生效');
      expect(session().open, SpeedBubbleMode.speed, reason: '滑条拖动不收起');
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('${formatRate(engine.rate)}x'),
        ),
        findsOneWidget,
        reason: '滑条生效 → 标题条双向同步',
      );
    });

    testWidgets('滑条 0.1–1.5 步 0.05——拖动结果恒在 0.05 网格上', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('speed_rate_slider')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(engine.rate, greaterThan(1.0), reason: '向上拖 = 加速');
      expect(engine.rate, lessThanOrEqualTo(speedSliderMax));
      final gridUnits = (engine.rate * 100).round();
      expect(
        gridUnits % 5,
        0,
        reason: '步长 0.05：拖动结果恒在 0.05 网格（实得 $engine.rate）',
      );
    });

    test('布局常量锚定——盒边距 8/12、组距=列距=6、标题高 24、单钮 32、g=4', () {
      expect(speedBubblePaddingLeft, 8, reason: '盒边距左 8');
      expect(speedBubblePaddingRight, 12, reason: '盒边距右 12（不对称）');
      expect(speedGroupGap, 6, reason: '组间距 = 列间距 = 6');
      expect(speedTitleHeight, 24, reason: '标题栏高 24');
      expect(speedTitleColumnGap, 4, reason: '列顶 = 标题底 + 4（锚定约束④）');
      expect(speedRateButtonHeight, 32, reason: '单钮高 32（上下 padding 7）');
      expect(speedRateRowGap, 4, reason: '行距 g = 4（唯一纵向自由参数定稿）');
      expect(
        speedColumnsBlockHeight,
        6 * speedRateButtonHeight + 5 * speedRateRowGap,
        reason: '列高派生：6×32 + 5×g',
      );
      expect(speedColumnsBlockHeight, 212);
      expect(
        speedSliderColumnHeight,
        speedColumnsBlockHeight + 22,
        reason: '滑条整高 = 列高 + 22（派生关系锁定）',
      );
      expect(speedSliderColumnHeight, 234);
    });

    test('刻度线几何纯函数——线 6×2 贴尺右缘、线中心 = 分度值位置（1px 线高补偿）', () {
      final rect = speedRulerTickRect(rulerWidth: 26, top: 100);
      expect(rect.width, speedRulerTickWidth, reason: '线宽 6');
      expect(rect.height, speedRulerTickHeight, reason: '线高 2');
      expect(rect.right, 26, reason: '线贴尺右缘（滑条侧）');
      expect(rect.center.dy, 100, reason: '线中心 = 分度值纵位（含 1px 补偿）');
      // 同参数重复调用几何稳定。
      expect(speedRulerTickRect(rulerWidth: 26, top: 100), rect);
    });

    testWidgets('气泡宽随内容派生（左栏定宽 + 列距 + 右栏自然宽 + 盒边距）', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final step = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_step_column')),
      );
      final rate = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );
      // 右栏（倍速栏）自然宽 = 双列块 + 组距 + 滑条区（仍随内容派生，不再恒 300）。
      final columnsRow = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_columns_row')),
      );
      final slider = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider')),
      );
      expect(
        (rate.size.width -
                (columnsRow.size.width + speedGroupGap + slider.size.width))
            .abs(),
        lessThan(1),
        reason: '倍速栏宽 = 双列块 + 组距 6 + 滑条区',
      );
      // 气泡宽 = 左盒边距 8 + 左栏 280 + 列距 17 + 右栏自然宽 + 右盒边距 12。
      final expected =
          speedBubblePaddingLeft +
          step.size.width +
          mergedBubbleColumnGap +
          rate.size.width +
          speedBubblePaddingRight;
      expect(
        (bubble.size.width - expected).abs(),
        lessThan(1),
        reason: '气泡宽 = 8 + 280 + 17 + 倍速栏 + 12（随内容派生）',
      );
      // 整高 = 上边距 8 + 内容 240（标题 24 + 间距 4 + 列高 212）+ 下边距
      // 12 = 260。
      final expectedHeight =
          speedBubblePaddingTop +
          speedTitleHeight +
          speedTitleColumnGap +
          speedColumnsBlockHeight +
          speedBubblePaddingBottom;
      expect(expectedHeight, 260);
      expect(
        (bubble.size.height - expectedHeight).abs(),
        lessThan(1),
        reason: '气泡整高 = 8 + 240 + 12 = 260',
      );
    });

    testWidgets('标题栏高 24、随值伸缩且永不越出气泡左缘（0.25x/1x/2x 均验证）', (tester) async {
      RenderBox boxOf(Key key) =>
          tester.renderObject<RenderBox>(find.byKey(key));
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 高 24（单行不折行）。
      expect(
        boxOf(const Key('speed_rate_title')).size.height,
        speedTitleHeight,
      );

      // 标题居中于左区：容器中点 = 双列块中点。
      double assertAligned() {
        final title = boxOf(const Key('speed_rate_title'));
        final columnsRow = boxOf(const Key('speed_columns_row'));
        final titleCenter = title
            .localToGlobal(title.size.center(Offset.zero))
            .dx;
        final columnsCenter = columnsRow
            .localToGlobal(columnsRow.size.center(Offset.zero))
            .dx;
        expect(
          (titleCenter - columnsCenter).abs(),
          lessThan(2),
          reason: '标题容器中点 = 双列块中点（随值变化同步居中）',
        );
        return title.localToGlobal(Offset.zero).dx;
      }

      // 标题左缘永不低于左区内容左缘（气泡左缘 + 左盒边距）——不越出气泡
      // 左缘；标题右缘不超过双列块右缘
      //（不会与右侧滑条区重叠）。气泡可能因内容伸缩被水平钳制平移，故每态
      // 就地重算气泡左缘与双列块右缘。
      // 0.25x / 1x / 2x 逐一切换验证，标题内容伸缩但永不越左缘。
      for (final rate in const [1.0, 0.25, 2.0, 0.25]) {
        await model().setRate(rate);
        await tester.pumpAndSettle();
        final title = boxOf(const Key('speed_rate_title'));
        final columnsRow = boxOf(const Key('speed_columns_row'));
        final bubble = boxOf(const Key('speed_bubble'));
        final titleLeft = title.localToGlobal(Offset.zero).dx;
        final titleRight = title
            .localToGlobal(title.size.topRight(Offset.zero))
            .dx;
        final bubbleContentLeft =
            bubble.localToGlobal(Offset.zero).dx + speedBubblePaddingLeft;
        final columnsRight =
            columnsRow.localToGlobal(Offset.zero).dx + columnsRow.size.width;
        expect(
          titleLeft,
          greaterThanOrEqualTo(bubbleContentLeft - 0.5),
          reason: '$rate 标题不越出气泡左缘',
        );
        expect(
          titleRight,
          lessThanOrEqualTo(columnsRight + 0.5),
          reason: '$rate 标题不越出双列块右缘（不与滑条重叠）',
        );
        expect(title.size.height, speedTitleHeight);
      }
      assertAligned();
    });

    testWidgets('稳健档：系统字号放大（1.3×）+ 最宽候选值下标题仍不越界', (tester) async {
      // 标题量测须跟随实际渲染的字号缩放（防字号缩放重新引入标题越界）。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 最宽候选项值文本之一（5 字符：1.05x），该取向下标题仍整体落在左区
      // 内、不越界（越界会抛 RenderFlex overflow，测试即失败）。
      await model().setRate(1.05);
      await tester.pumpAndSettle();
      final title = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_title')),
      );
      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final columnsRow = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_columns_row')),
      );
      final contentLeft =
          bubble.localToGlobal(Offset.zero).dx + speedBubblePaddingLeft;
      final titleLeft = title.localToGlobal(Offset.zero).dx;
      final titleRight = title
          .localToGlobal(title.size.topRight(Offset.zero))
          .dx;
      final columnsRight =
          columnsRow.localToGlobal(Offset.zero).dx + columnsRow.size.width;
      expect(
        titleLeft,
        greaterThanOrEqualTo(contentLeft - 0.5),
        reason: '缩放下标题仍不越出气泡左缘',
      );
      expect(
        titleRight,
        lessThanOrEqualTo(columnsRight + 0.5),
        reason: '缩放下标题仍不越出双列块右缘',
      );
    });

    testWidgets('常驻列按倍速值降序渲染（1.5x 顶 → 0.25x 底）；下拉候选顺序不变', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 常驻列：自上而下 1.5 → 1.25 → 1.0 → 0.75 → 0.5 → 0.25（大值在
      // 顶、与竖向滑条「min 在下、max 在上」同向，降序）。
      double topOf(double rate) => tester
          .renderObject<RenderBox>(find.byKey(Key('speed_quick_$rate')))
          .localToGlobal(Offset.zero)
          .dy;
      final descending = List<double>.from(commonSpeeds)
        ..sort((a, b) => b.compareTo(a));
      for (var i = 1; i < descending.length; i++) {
        expect(
          topOf(descending[i - 1]),
          lessThan(topOf(descending[i])),
          reason: '${descending[i - 1]}x 在 ${descending[i]}x 之上（降序）',
        );
      }
      expect(topOf(1.5), lessThan(topOf(0.25)), reason: '最快在顶');

      // 常量本身不反转（下拉候选、其他消费方顺序不变——由既有下拉置顶
      // 断言与 speed_control_test 锚定）。
      expect(commonSpeeds.first, 0.25);
      expect(commonSpeeds.last, 1.5);
    });

    testWidgets('刻度线贴滑条侧（尺右缘）、数字文字在外侧（尺左缘）；四标签纵位随 234 线性重算', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final ruler = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_ruler')),
      );
      final track = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider_track')),
      );
      // 尺右缘紧贴滑条侧（间隙 = speedRulerGap 4）。
      final rulerRight = ruler.localToGlobal(Offset.zero).dx + ruler.size.width;
      expect(
        (track.localToGlobal(Offset.zero).dx - rulerRight - speedRulerGap)
            .abs(),
        lessThan(0.5),
        reason: '刻度尺右缘（刻度线侧）贴滑条',
      );

      // 数字文字在外侧：标签左缘 = 尺左缘（Positioned left 0）。
      for (final label in const ['0.1', '0.5', '1.0', '1.5']) {
        final box = tester.renderObject<RenderBox>(
          find.byKey(Key('speed_rate_ruler_label_$label')),
        );
        expect(
          (box.localToGlobal(Offset.zero).dx -
                  ruler.localToGlobal(Offset.zero).dx)
              .abs(),
          lessThan(1),
          reason: '标签 $label 在尺左缘（外侧）',
        );
      }

      // 纵位线性映射随 234 重算：top = (1.5 − v)/1.4 × 234（±2px 风格）。
      final rulerHeight = ruler.size.height;
      expect(rulerHeight, 234);
      final rulerTop = ruler.localToGlobal(Offset.zero).dy;
      for (final entry in const {
        '0.1': 0.1,
        '0.5': 0.5,
        '1.0': 1.0,
        '1.5': 1.5,
      }.entries) {
        final value = entry.value;
        final expectedTop =
            (speedSliderMax - value) /
            (speedSliderMax - speedRateMin) *
            rulerHeight;
        final box = tester.renderObject<RenderBox>(
          find.byKey(Key('speed_rate_ruler_label_${entry.key}')),
        );
        final centerDy =
            box.localToGlobal(box.size.center(Offset.zero)).dy - rulerTop;
        expect(
          (centerDy - expectedTop).abs(),
          lessThan(2),
          reason: '标签 ${entry.key} 纵位 = (1.5−v)/1.4×234 线性映射',
        );
      }
    });
  });

  group('步进激活后两处倍速面板放开', () {
    testWidgets('步进启用中面板不置灰：速选/历史/标题下拉/滑条均可操作，改档即退步进并应用', (tester) async {
      await model().setRate(0.8);
      model().recordHistory(0.8);
      // 步进开启后再开倍速气泡（观看态与编辑态同一组件）。
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 步进首档 a=0.5（默认），面板如实显示当前生效倍速。
      expect(engine.rate, 0.5, reason: '步进启用中生效的是步进首档');

      InkWell chipOf(Key key) => tester.widget<InkWell>(
        find.descendant(of: find.byKey(key), matching: find.byType(InkWell)),
      );
      // 不置灰：速选/历史可点、标题下拉可开。
      expect(chipOf(const Key('speed_quick_0.75')).onTap, isNotNull);
      expect(chipOf(const Key('speed_history_0.8')).onTap, isNotNull);
      expect(
        tester
            .widget<DropdownButton<double>>(
              find.byKey(const Key('speed_rate_select')),
            )
            .onChanged,
        isNotNull,
      );

      // 改倍速（速选档位）→ setRate → 模型自动退步进并应用新倍速。
      await tester.tap(find.byKey(const Key('speed_quick_0.75')));
      await tester.pumpAndSettle();
      expect(engine.rate, 0.75, reason: '改倍速应用新倍速');
      expect(
        container.read(speedControlProvider).stepEnabled,
        isFalse,
        reason: '改倍速自动退出步进（模型互斥保留）',
      );
    });

    testWidgets('步进启用中拖动竖滑条：实时改倍速并自动退步进、气泡不收起', (tester) async {
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.drag(
        find.byKey(const Key('speed_rate_slider')),
        const Offset(0, -80),
      );
      await tester.pumpAndSettle();
      expect(engine.rate, greaterThan(0.5), reason: '滑条拖动实时改倍速生效');
      expect(
        container.read(speedControlProvider).stepEnabled,
        isFalse,
        reason: '滑条改倍速即自动退步进',
      );
      expect(session().open, SpeedBubbleMode.speed, reason: '滑条拖动不收起');
    });

    testWidgets('步进启用中面板当前倍速随档位推进实时更新（不改则步进保持）', (tester) async {
      await container
          .read(speedControlProvider.notifier)
          .setStepEnabled(true, scope: SpeedStepScope.wholeVideo);
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      expect(engine.rate, 0.5, reason: '首档 a=0.5');

      // 全片循环推进满默认每档 3 遍 → 第二档 0.6。
      final notifier = container.read(speedControlProvider.notifier);
      for (var i = 0; i < 3; i++) {
        await notifier.onWholeVideoLoop();
      }
      await tester.pumpAndSettle();

      expect(engine.rate, 0.6, reason: '步进推进到第二档 0.6');
      expect(
        container.read(speedControlProvider).stepEnabled,
        isTrue,
        reason: '未改倍速 → 步进保持',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('speed_rate_select')),
          matching: find.text('0.6x'),
        ),
        findsOneWidget,
        reason: '面板当前倍速随档位推进实时更新（0.6）',
      );
    });
  });

  group('历史提交时机（打开快照 → 关闭变化才记一次）', () {
    testWidgets('气泡内滑条/档位调整不逐档入史；关闭且最终值≠快照才记一次', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 打开快照 = 1.0（默认）。气泡内多次调整。
      await model().setRate(0.5);
      await model().setRate(0.75);
      await model().setRate(0.6);
      await tester.pumpAndSettle();
      expect(
        container.read(speedControlProvider).history,
        isEmpty,
        reason: '气泡打开期间不记历史',
      );

      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();
      expect(container.read(speedControlProvider).history, [
        0.6,
      ], reason: '关闭时只记最终值一次');
    });

    testWidgets('最终值=快照则不记', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      // 调出去再调回快照值 1.0。
      await model().setRate(0.5);
      await model().setRate(1.0);
      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();

      expect(container.read(speedControlProvider).history, isEmpty);
    });

    testWidgets('回到 1.0 相对非 1.0 快照也算变化（含 1.0）', (tester) async {
      await model().setRate(0.5);
      model().recordHistory(0.5);
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await model().setRate(1.0);
      container.read(speedBubbleSessionProvider.notifier).close();
      await tester.pumpAndSettle();

      expect(container.read(speedControlProvider).history, [
        1.0,
        0.5,
      ], reason: '1.0 相对快照 0.5 变化，应记一次且最近在前');
    });

    testWidgets('速选档点选即收起路径同样只记一次', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speed_quick_0.75')));
      await tester.pumpAndSettle();

      expect(engine.rate, 0.75);
      expect(session().open, isNull);
      expect(container.read(speedControlProvider).history, [0.75]);
    });
  });

  group('气泡水平钳制', () {
    // 纯函数 seam：居中矩形超屏时的水平平移量（负 = 向左）。
    test('放得下不平移', () {
      expect(
        speedBubbleClampShift(
          bubbleLeft: 250,
          bubbleWidth: 300,
          screenWidth: 800,
        ),
        0,
      );
    });

    test('右缘溢出 → 向左平移到留边处', () {
      // 居中后 600..900，右缘溢出 → 平移 -108（792 - 900）。
      expect(
        speedBubbleClampShift(
          bubbleLeft: 600,
          bubbleWidth: 300,
          screenWidth: 800,
        ),
        -108,
      );
    });

    test('左缘溢出 → 向右平移到留边处', () {
      expect(
        speedBubbleClampShift(
          bubbleLeft: -50,
          bubbleWidth: 300,
          screenWidth: 800,
        ),
        58,
      );
    });

    test('气泡比屏还宽 → 贴左留边（右缘尽力而为）', () {
      expect(
        speedBubbleClampShift(
          bubbleLeft: 100,
          bubbleWidth: 900,
          screenWidth: 800,
        ),
        -92,
      );
    });

    testWidgets('锚点贴右缘：气泡完整进屏、右缘留边、滑条可达可拖', (tester) async {
      final link = LayerLink();
      await pumpHost(
        tester,
        link: link,
        placeAnchor: (target) =>
            Positioned(right: 12, bottom: 12, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expectBubbleClampedOnScreen(bubble, screenWidth: 800);

      // 最右列（竖滑条）可达：命中测试命中滑条自身。
      final slider = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_slider')),
      );
      expectHitReachable(slider);

      // 可拖（存活断言，值域/步进归滑条用例）：钳制平移下竖滑
      // 拖动仍实时改倍速——按住后向下拖应离开 1.0。
      final sliderCenter = slider.localToGlobal(
        slider.size.center(Offset.zero),
      );
      final gesture = await tester.startGesture(sliderCenter);
      await tester.pump();
      await gesture.moveBy(const Offset(0, 40)); // 向下拖 = 减速。
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        container.read(speedControlProvider).manualRate,
        isNot(1.0),
        reason: '按住中心后向下拖 40dp 应离开 1.0（值直接跳到触点、实时生效）',
      );
    });

    testWidgets('居中放得下时观感保持：不平移、中心对齐', (tester) async {
      final link = LayerLink();
      await pumpHost(
        tester,
        link: link,
        // 中心 290：气泡 300 宽居中 → 140..440，在屏内。
        placeAnchor: (target) => Positioned(left: 250, top: 100, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final anchor = tester.renderObject<RenderBox>(
        find.byKey(const Key('bubble_anchor')),
      );
      final bubbleCenter = bubble.localToGlobal(
        bubble.size.center(Offset.zero),
      );
      final anchorCenter = anchor.localToGlobal(
        anchor.size.center(Offset.zero),
      );
      expect(
        (bubbleCenter.dx - anchorCenter.dx).abs(),
        lessThan(1),
        reason: '放得下时保持中心对齐（不平移）',
      );
    });

    testWidgets('窄屏（竖屏 360 逻辑宽）：锚点贴右缘气泡完整进屏、倍速栏可达', (tester) async {
      // 竖屏可用宽不足以并排 → 上下堆叠，气泡宽回到 300 上限，
      // 水平钳制后完整进屏（左右留边）。
      tester.view.physicalSize = const Size(
        720,
        1440,
      ); // 合成档 360.0×720.0dp（dpr 2），非设备基准。
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final link = LayerLink();
      await pumpHost(
        tester,
        link: link,
        placeAnchor: (target) =>
            Positioned(right: 12, bottom: 12, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final rect = bubbleGlobalRect(bubble);
      expectBubbleClampedOnScreen(bubble, screenWidth: 360);
      expect(rect.left, greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5));
      expectHitReachable(
        tester.renderObject<RenderBox>(
          find.byKey(const Key('speed_rate_slider')),
        ),
      );
    });
  });

  group('气泡两轴钳位', () {
    // 纯函数 seam：竖直平移量（负 = 向上），与水平规则对称。
    group('纯函数 speedBubbleVerticalClampShift', () {
      test('放得下不平移', () {
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: 100,
            bubbleHeight: 300,
            screenHeight: 800,
          ),
          0,
        );
      });

      test('底缘越界 → 向上平移到留边处', () {
        // 600..900，底缘 900 溢出 → dy = -108（792 − 900）。
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: 600,
            bubbleHeight: 300,
            screenHeight: 800,
          ),
          -108,
        );
      });

      test('顶缘越界 → 向下平移到留边处', () {
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: -50,
            bubbleHeight: 300,
            screenHeight: 800,
          ),
          58,
        );
      });

      test('气泡比屏还高 → 贴上留边（底缘尽力而为）', () {
        // 100..1000：先上移 −208 贴底留边，顶缘 −108 < 8 → 改贴顶 dy = −92。
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: 100,
            bubbleHeight: 900,
            screenHeight: 800,
          ),
          -92,
        );
      });

      test('等于即不钳（底缘恰在留边、顶缘恰在留边）', () {
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: 492,
            bubbleHeight: 300,
            screenHeight: 800,
          ),
          0,
          reason: '底缘 792 = 屏高 − 留边，不钳',
        );
        expect(
          speedBubbleVerticalClampShift(
            bubbleTop: 8,
            bubbleHeight: 300,
            screenHeight: 800,
          ),
          0,
          reason: '顶缘 8 = 留边，不钳',
        );
      });
    });

    group('纯函数 bubbleClampFit 两轴扩展', () {
      test('仅竖直越界：竖直平移生效、不触发缩放兜底', () {
        // 宽 300 在屏 800 内放得下 → scale 1；高 1000 超屏 → 贴顶。
        final fit = bubbleClampFit(
          bubbleLeft: 250,
          bubbleWidth: 300,
          screenWidth: 800,
          bubbleTop: 0,
          bubbleHeight: 1000,
          screenHeight: 800,
        );
        expect(fit.scale, 1.0, reason: '竖直不参与等比缩小兜底');
        expect(fit.dx, 0.0);
        expect(fit.dy, speedBubbleScreenMargin);
      });

      test('水平与竖直同时越界：两者叠加生效', () {
        final fit = bubbleClampFit(
          bubbleLeft: 600,
          bubbleWidth: 300,
          screenWidth: 800,
          bubbleTop: 600,
          bubbleHeight: 300,
          screenHeight: 800,
        );
        expect(fit.dx, -108);
        expect(fit.dy, -108);
      });

      test('不传竖直参数时 dy 为 0（既有水平用例口径不变）', () {
        final fit = bubbleClampFit(
          bubbleLeft: 250,
          bubbleWidth: 300,
          screenWidth: 800,
        );
        expect(fit.dy, 0.0);
        expect(fit.scale, 1.0);
      });
    });

    /// 编辑态宿主 seam：锚点在画面工具带（气泡向下展开，target
    /// bottomCenter / follower topCenter），竖屏下气泡底缘越屏 → 上移钳位。
    Future<void> pumpEditHost(
      WidgetTester tester, {
      required LayerLink link,
      required Positioned Function(Widget target) placeAnchor,
    }) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  placeAnchor(
                    CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(
                        key: Key('bubble_anchor'),
                        width: 80,
                        height: 40,
                      ),
                    ),
                  ),
                  SpeedBubbleHost(
                    linkFor: (_) => link,
                    targetAnchor: Alignment.bottomCenter,
                    followerAnchor: Alignment.topCenter,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('竖屏真机基准（361.1×781.7）编辑态倍速气泡：四边在屏内、滑条可达', (tester) async {
      tester.view.physicalSize = const Size(722.2, 1563.4);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final link = LayerLink();
      await pumpEditHost(
        tester,
        link: link,
        placeAnchor: (target) => Positioned(right: 12, top: 60, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expectBubbleClampedOnScreen(
        bubble,
        screenWidth: 361.1,
        screenHeight: 781.7,
      );

      // 钳位后最下/最右的内容（竖滑条：右栏整列、堆叠排布下亦居底）仍可达：
      // 命中测试命中滑条自身。
      expectHitReachable(
        tester.renderObject<RenderBox>(
          find.byKey(const Key('speed_rate_slider')),
        ),
      );
    });

    testWidgets('竖屏编辑态：节拍提示/节拍对齐/节拍倍频/音画同步同样四边在屏内', (tester) async {
      tester.view.physicalSize = const Size(722.2, 1563.4);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final link = LayerLink();
      await pumpEditHost(
        tester,
        link: link,
        placeAnchor: (target) => Positioned(right: 12, top: 60, child: target),
      );
      for (final mode in [
        SpeedBubbleMode.beat,
        SpeedBubbleMode.beatAlign,
        SpeedBubbleMode.beatDensity,
        SpeedBubbleMode.avSync,
      ]) {
        open(mode);
        // 固定帧推进（beat 侧气泡内有持续动画，pumpAndSettle 不收敛）：
        // 首帧布局 + 次帧应用帧末量测出的钳位。
        await tester.pump();
        await tester.pump();

        final bubble = tester.renderObject<RenderBox>(
          find.byKey(const Key('speed_bubble')),
        );
        expectBubbleClampedOnScreen(
          bubble,
          screenWidth: 361.1,
          screenHeight: 781.7,
          reason: '$mode 气泡四边都在屏内',
        );
      }
    });

    testWidgets('观看态：气泡超高屏时才被钳回（顶部贴留边、底缘尽力）', (tester) async {
      // 视口压到 120 高：气泡自然高超过可用高 → 贴顶留边、底缘尽力。
      tester.view.physicalSize = const Size(
        800,
        120,
      ); // 合成档 800.0×120.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final link = LayerLink();
      await pumpHost(
        tester,
        link: link,
        placeAnchor: (target) => Positioned(left: 250, top: 100, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final rect = bubbleGlobalRect(bubble);
      expect(
        rect.top,
        closeTo(speedBubbleScreenMargin, 0.5),
        reason: '比屏还高 → 贴上留边',
      );
      expect(
        rect.bottom,
        greaterThan(120 - speedBubbleScreenMargin),
        reason: '底缘尽力而为（高到装不下时允许越屏底，对称水平右缘裁切）',
      );
    });

    testWidgets('观看态常规尺寸：位置不变（dy = 0，气泡底缘仍贴锚点上方）', (tester) async {
      final link = LayerLink();
      await pumpHost(
        tester,
        link: link,
        placeAnchor: (target) => Positioned(left: 250, top: 400, child: target),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final anchor = tester.renderObject<RenderBox>(
        find.byKey(const Key('bubble_anchor')),
      );
      final rect = bubbleGlobalRect(bubble);
      expect(
        rect.bottom,
        closeTo(anchor.localToGlobal(Offset.zero).dy - 8, 0.5),
        reason: '观看态常规尺寸下不竖直钳位（气泡仍在锚点上方原位）',
      );
    });

    testWidgets('第一帧即钳位到位：量测帧后紧接的一帧矩形已进屏', (tester) async {
      tester.view.physicalSize = const Size(722.2, 1563.4);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final link = LayerLink();
      await pumpEditHost(
        tester,
        link: link,
        placeAnchor: (target) => Positioned(right: 12, top: 60, child: target),
      );
      open(SpeedBubbleMode.speed);
      // 首帧：postFrame 量测（此刻不可见）；次帧：钳位与可见性一并生效。
      await tester.pump();
      await tester.pump();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expectBubbleClampedOnScreen(
        bubble,
        screenWidth: 361.1,
        screenHeight: 781.7,
        reason: '首个可见帧即已钳位（无「先溢出再拉回」）',
      );
    });
  });

  group('节拍气泡兜底等比缩小', () {
    // 纯函数 seam：中心锚点 + 水平钳位 + 兜底缩放（仅 beat 模式接线）。
    group('纯函数 bubbleClampFit', () {
      test('放得下：不缩放、不平移', () {
        final fit = bubbleClampFit(
          bubbleLeft: 250,
          bubbleWidth: 300,
          screenWidth: 800,
        );
        expect(fit.scale, 1.0);
        expect(fit.dx, 0.0);
      });

      test('可用宽不足：整泡等比缩小到恰好进屏（缩后宽 = 屏宽 − 2×留边）', () {
        // 气泡 800，屏 800：可用宽 784 → 缩放 784/800 = 0.98，
        // 缩后有效宽 784 恰好贴两侧留边，中心未越界 → dx 0。
        final fit = bubbleClampFit(
          bubbleLeft: 0,
          bubbleWidth: 800,
          screenWidth: 800,
        );
        expect(fit.scale, closeTo(784 / 800, 1e-9));
        expect(fit.dx, 0.0);
      });

      test('缩放下限 0.8：可用宽更小时只缩到 0.8', () {
        final fit = bubbleClampFit(
          bubbleLeft: 0,
          bubbleWidth: 1000,
          screenWidth: 800,
        );
        expect(fit.scale, bubbleMinScale);
      });

      test('0.8 后仍放不下：钳到左留边（右缘允许裁切）', () {
        // 有效宽 1000×0.8 = 800 > 可用 784 → 缩后左缘钳到 8
        //（缩后左缘 100 + dx = 8），右缘 808 溢出（允许水平裁切）。
        final fit = bubbleClampFit(
          bubbleLeft: 0,
          bubbleWidth: 1000,
          screenWidth: 800,
        );
        expect(fit.dx, -92.0);
      });
    });

    /// 宿主 seam（beat 模式）：气泡自然宽超可用宽时整泡 transform scale
    /// 等比缩小（下限 0.8）、缩后钳位进屏。
    Future<void> pumpBeatAtRightEdge(WidgetTester tester) async {
      final link = LayerLink();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    right: 4,
                    top: 100,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(
                        key: Key('bubble_anchor'),
                        width: 80,
                        height: 40,
                      ),
                    ),
                  ),
                  SpeedBubbleHost(
                    linkFor: (_) => link,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.bottomCenter,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      open(SpeedBubbleMode.beat);
      await tester.pumpAndSettle();
    }

    testWidgets('beat 模式：竖屏堆叠宽仍超屏 → 整泡缩到恰好进屏（有效宽 = 屏宽 − 16）', (tester) async {
      // beat 气泡放不下并排即三段堆叠（内容宽 312 + 盒边距 = 332）——
      // 屏取 300 才超可用宽 284，此时仍走兜底等比缩小（缩小口径不变）。
      tester.view.physicalSize = const Size(
        300,
        600,
      ); // 合成档 300.0×600.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpBeatAtRightEdge(tester);

      final box = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final rect = bubbleGlobalRect(box);
      // 屏 300、留边 8：缩后有效宽应恰为 284（可用宽）。
      expect(rect.width, closeTo(300 - 2 * speedBubbleScreenMargin, 0.5));
      expect(rect.left, greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5));
      expect(
        rect.right,
        lessThanOrEqualTo(300 - speedBubbleScreenMargin + 0.5),
      );
    });

    testWidgets('beat 模式：0.8 下限钳到左留边（允许裁切，不崩溃）', (tester) async {
      // 堆叠宽 332；屏 270 → 可用 254 < 堆叠宽 × 0.8 = 265.6 →
      // 触发下限钳制。
      tester.view.physicalSize = const Size(
        270,
        600,
      ); // 合成档 270.0×600.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpBeatAtRightEdge(tester);

      final box = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final rect = bubbleGlobalRect(box);
      expect(rect.left, closeTo(speedBubbleScreenMargin, 0.5));
      // 有效宽 = 堆叠宽 × 0.8 > 可用宽 254 → 右缘允许溢出（裁切）。
      expect(rect.width, greaterThan(270 - 2 * speedBubbleScreenMargin));
    });

    testWidgets('倍速气泡（speed）参与兜底缩放：可用宽不足时整泡缩到恰好进屏', (tester) async {
      // 屏 300、留边 8：可用宽 284 < 竖屏堆叠自然外宽（内容 300 + 盒边距
      // 20 = 320）→ 整泡缩到 284 恰好进屏（不裁切）。
      tester.view.physicalSize = const Size(
        300,
        600,
      ); // 合成档 300.0×600.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final link = LayerLink();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    right: 4,
                    top: 100,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(
                        key: Key('bubble_anchor'),
                        width: 80,
                        height: 40,
                      ),
                    ),
                  ),
                  SpeedBubbleHost(
                    linkFor: (_) => link,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.bottomCenter,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final rect = bubbleGlobalRect(
        tester.renderObject<RenderBox>(find.byKey(const Key('speed_bubble'))),
      );
      expect(rect.width, closeTo(300 - 2 * speedBubbleScreenMargin, 0.5));
      expect(rect.left, greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5));
      expect(
        rect.right,
        lessThanOrEqualTo(300 - speedBubbleScreenMargin + 0.5),
      );
    });

    test('兜底缩放参与模式：节拍侧 + 倍速气泡参与，其余非节拍侧不参与', () {
      expect(SpeedBubbleMode.beat.usesScaleFallback, isTrue);
      expect(SpeedBubbleMode.beatAlign.usesScaleFallback, isTrue);
      expect(
        SpeedBubbleMode.speed.usesScaleFallback,
        isTrue,
        reason: '合并模式纳入整泡等比缩小兜底',
      );
      expect(SpeedBubbleMode.avSync.usesScaleFallback, isFalse);
    });

    // 782×400：刻意放宽的**合成档**（真机横屏逻辑宽 781.7 取整到 782，
    // 高度收窄到 400dp；非设备基准）。
    testWidgets('横屏合成档 782 逻辑宽：合并气泡一次完整放下、零缩放、不越屏', (tester) async {
      tester.view.physicalSize = const Size(782, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final link = LayerLink();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Positioned(
                    right: 4,
                    top: 20,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(
                        key: Key('bubble_anchor'),
                        width: 80,
                        height: 40,
                      ),
                    ),
                  ),
                  SpeedBubbleHost(
                    linkFor: (_) => link,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.bottomCenter,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final box = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      final rect = bubbleGlobalRect(box);
      final step = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_step_column')),
      );
      final rate = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );
      // 一次完整放下（左/右各留边）。
      expect(rect.left, greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5));
      expect(
        rect.right,
        lessThanOrEqualTo(782 - speedBubbleScreenMargin + 0.5),
      );
      // 零缩放：宽即两栏内容宽 + 盒边距（派生，不写死字体相关魔法数）。
      expect(
        rect.width,
        closeTo(
          step.size.width +
              mergedBubbleColumnGap +
              rate.size.width +
              speedBubblePaddingLeft +
              speedBubblePaddingRight,
          0.5,
        ),
        reason: '自然外宽一次放下，零缩放',
      );
    });
  });

  group('倍速气泡竖排与屏内适配', () {
    /// 宿主 seam（观看态胶囊位置：右下贴角）+ 共享气泡宿主；[screen] 逻辑尺寸。
    Future<void> pumpAt(WidgetTester tester, Size screen) async {
      tester.view.physicalSize = screen;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpHost(
        tester,
        link: LayerLink(),
        placeAnchor: (target) =>
            Positioned(right: 12, bottom: 12, child: target),
      );
    }

    RenderBox boxOf(WidgetTester tester, Key key) =>
        tester.renderObject<RenderBox>(find.byKey(key));

    /// 分隔线可见几何：并排为竖线（高 > 宽）、堆叠为横线（宽 > 高）。
    void expectSeparatorOrientation(
      WidgetTester tester, {
      required bool stacked,
    }) {
      final rect = tester.getRect(
        find.byKey(const Key('speed_merged_separator')),
      );
      if (stacked) {
        expect(rect.width, greaterThan(rect.height), reason: '堆叠分隔线为横线');
      } else {
        expect(rect.height, greaterThan(rect.width), reason: '并排分隔线为竖线');
      }
    }

    testWidgets('竖屏可用宽不足：两栏上下堆叠、横分隔线、气泡宽回到 300 上限、完整进屏', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final left = boxOf(tester, const Key('speed_rate_column'));
      final step = boxOf(tester, const Key('speed_step_column'));
      final leftRect = bubbleGlobalRect(left);
      final stepRect = bubbleGlobalRect(step);

      // 上下堆叠：步进栏在倍速栏下方、两栏同宽同左缘；分隔线改横线。
      expect(stepRect.top, greaterThanOrEqualTo(leftRect.bottom - 0.5));
      expect(stepRect.left, closeTo(leftRect.left, 0.5));
      expect(stepRect.width, closeTo(leftRect.width, 0.5));
      expectSeparatorOrientation(tester, stacked: true);

      // 气泡宽回到既有 300 内容上限（不超过）；竖排零缩放。
      expect(left.size.width, speedBubbleMaxWidth, reason: '内容宽取纯函数给出的 300 上限');
      final bubble = bubbleGlobalRect(boxOf(tester, const Key('speed_bubble')));
      expect(
        bubble.width,
        closeTo(
          left.size.width + speedBubblePaddingLeft + speedBubblePaddingRight,
          0.5,
        ),
      );
      // 完整进屏（左右留边、不越屏）。
      expect(bubble.left, greaterThanOrEqualTo(speedBubbleScreenMargin - 0.5));
      expect(
        bubble.right,
        lessThanOrEqualTo(390 - speedBubbleScreenMargin + 0.5),
      );
    });

    testWidgets('竖屏内容超高：整泡滚动兜底（外层滚动而非栏内滚）、关键控件不被裁', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final pn = container.read(speedStepPresetProvider.notifier);
      for (var i = 0; i < 12; i++) {
        await pn.createCustom('预设 $i');
      }
      await tester.pumpAndSettle();

      // 先确认确为堆叠布局（并排时本用例的其余断言也会成立，无法区分）。
      final rateBefore = boxOf(tester, const Key('speed_rate_column'));
      final stepRect = bubbleGlobalRect(
        boxOf(tester, const Key('speed_step_column')),
      );
      expect(
        stepRect.top,
        greaterThanOrEqualTo(bubbleGlobalRect(rateBefore).bottom - 0.5),
        reason: '堆叠布局',
      );

      // 内容超高 → 气泡高受既有上限（0.7 视口）约束；超高部分由**外层**
      // 整泡滚动兜底（堆叠时栏内滚无余量）。
      final bubble = boxOf(tester, const Key('speed_bubble'));
      expect(bubble.size.height, closeTo(844 * 0.7, 1));
      final scrollables = tester.stateList<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('speed_bubble')),
          matching: find.byType(Scrollable),
        ),
      );
      final outer = scrollables.firstWhere(
        (s) => s.position.maxScrollExtent > 0,
        orElse: () => fail('应有可滚动的整泡滚动容器'),
      );
      expect(
        scrollables.where((s) => s.position.maxScrollExtent > 0).length,
        1,
        reason: '堆叠时只有整泡外层可滚，栏内滚无余量',
      );

      // 整泡滚动：拖动后倍速栏随之上移（并排时倍速栏固定不动）。
      final rateTopBefore = bubbleGlobalRect(rateBefore).top;
      await tester.drag(
        find
            .descendant(
              of: find.byKey(const Key('speed_bubble')),
              matching: find.byType(Scrollable),
            )
            .first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
      expect(outer.position.pixels, greaterThan(0));
      expect(
        bubbleGlobalRect(boxOf(tester, const Key('speed_rate_column'))).top,
        lessThan(rateTopBefore - 1),
        reason: '整泡滚动（倍速栏随之上移）',
      );

      // 关键控件不被裁：倍速下拉与竖滑条命中可达且落在气泡可视矩形内。
      final bubbleRect = bubbleGlobalRect(bubble);
      for (final key in const [
        Key('speed_rate_select'),
        Key('speed_rate_slider'),
      ]) {
        // 滚回顶部后再校验关键控件可见。
        outer.position.jumpTo(0);
        await tester.pumpAndSettle();
        final box = boxOf(tester, key);
        final rect = bubbleGlobalRect(box);
        expect(
          rect.top,
          greaterThanOrEqualTo(bubbleRect.top - 0.5),
          reason: '$key 不被上缘裁掉',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(bubbleRect.bottom + 0.5),
          reason: '$key 不被下缘裁掉',
        );
        expectHitReachable(box);
      }
    });

    testWidgets('横竖屏来回切换即重排；选中 / 已启用与展开中的编辑器不丢', (tester) async {
      await pumpAt(tester, const Size(390, 844));
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      // 步进栏状态：选中一条预设 + 步进已启用 + 打开该预设的编辑器。
      await container
          .read(speedStepPresetProvider.notifier)
          .select('builtin_review');
      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_step_edit_builtin_review')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_step_editor')), findsOneWidget);

      void expectLayout({required bool stacked}) {
        final rate = bubbleGlobalRect(
          boxOf(tester, const Key('speed_rate_column')),
        );
        final step = bubbleGlobalRect(
          boxOf(tester, const Key('speed_step_column')),
        );
        if (stacked) {
          expect(
            step.top,
            greaterThanOrEqualTo(rate.bottom - 0.5),
            reason: '竖屏上下堆叠：步进栏在倍速栏下方',
          );
        } else {
          expect(
            rate.left,
            greaterThanOrEqualTo(step.right - 0.5),
            reason: '横屏并排：步进栏在倍速栏左侧',
          );
        }
        expectSeparatorOrientation(tester, stacked: stacked);
      }

      // 竖 → 横：重排为并排，两类状态与编辑器保持。
      tester.view.physicalSize = const Size(
        844,
        390,
      ); // 合成档 281.3×130.0dp（dpr 3），非设备基准。
      await tester.pumpAndSettle();
      expectLayout(stacked: false);
      expect(
        find.byKey(const Key('speed_step_editor')),
        findsOneWidget,
        reason: '展开中的编辑器不丢',
      );
      expect(
        find.byKey(const Key('speed_step_enabled_badge')),
        findsOneWidget,
        reason: '已启用不丢',
      );
      expect(
        container.read(speedStepPresetProvider).selectedId,
        'builtin_review',
      );

      // 横 → 竖：重排回堆叠，状态仍在。
      tester.view.physicalSize = const Size(
        390,
        844,
      ); // 合成档 130.0×281.3dp（dpr 3），非设备基准。
      await tester.pumpAndSettle();
      expectLayout(stacked: true);
      expect(find.byKey(const Key('speed_step_editor')), findsOneWidget);
      expect(find.byKey(const Key('speed_step_enabled_badge')), findsOneWidget);
      expect(
        container.read(speedStepPresetProvider).selectedId,
        'builtin_review',
      );
    });
  });

  group('步进栏（合并气泡左栏；预设行列表 + 逐行编辑/删除 + 新增占位行）', () {
    Future<void> pumpOpenStep(WidgetTester tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
    }

    SpeedStepPresetDoc doc() => container.read(speedStepPresetProvider);

    /// 进入某预设的编辑子视图（点该行右侧编辑钮）。
    Future<void> openEditor(WidgetTester tester, String id) async {
      await tester.tap(find.byKey(Key('speed_step_edit_$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('编辑器四参数行横向均匀分布（Expanded 等分）', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      final row = find.byKey(const Key('speed_step_editor_params_row'));
      expect(row, findsOneWidget);
      final widths = <double>[];
      for (final key in const [
        Key('speed_step_editor_start_rate'),
        Key('speed_step_editor_max_rate'),
        Key('speed_step_editor_laps_per_rate'),
        Key('speed_step_editor_rate_increment'),
      ]) {
        // 只认参数行内的 Expanded（步进栏滚动区自身亦为 Expanded，非本行）。
        final box = find.descendant(
          of: row,
          matching: find.ancestor(
            of: find.byKey(key),
            matching: find.byType(Expanded),
          ),
        );
        expect(box, findsOneWidget, reason: '$key 由 Expanded 等分');
        widths.add(tester.renderObject<RenderBox>(find.byKey(key)).size.width);
      }
      expect(widths.toSet().length, 1, reason: '四参数列等宽（均匀分布）');
    });

    testWidgets('预设行列表：两内置行（名称 + 参数摘要）+ 右侧编辑/删除钮（同一枚）', (tester) async {
      await pumpOpenStep(tester);

      expect(
        find.byKey(const Key('speed_step_preset_builtin_first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_preset_builtin_review')),
        findsOneWidget,
      );
      expect(find.text('初见·大量练习'), findsOneWidget);
      expect(find.text('复习'), findsOneWidget);
      expect(
        find.textContaining('起步 0.5 → 封顶 1 · 每档 3 遍 · +0.1'),
        findsOneWidget,
      );
      expect(
        find.textContaining('起步 0.5 → 封顶 1 · 每档 2 遍 · +0.25'),
        findsOneWidget,
      );
      // 内置与自定义同一枚删除钮：内置行也有编辑钮 + 删除钮。
      expect(
        find.byKey(const Key('speed_step_edit_builtin_first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_edit_builtin_review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_delete_builtin_first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('speed_step_delete_builtin_review')),
        findsOneWidget,
      );
      // 无启用开关、无「参数设置…」折叠。
      expect(find.byKey(const Key('speed_step_switch')), findsNothing);
      expect(find.byKey(const Key('speed_step_settings_toggle')), findsNothing);
      // 列表尾「＋ 新增预设」占位整行存在。
      expect(find.byKey(const Key('speed_step_add_preset')), findsOneWidget);
      expect(find.text('新增预设'), findsOneWidget);
    });

    testWidgets('点行三态·未启用：选中并启用该预设（范围外先三选一），确认后收起气泡', (tester) async {
      await pumpOpenStep(tester);

      await tester.tap(
        find.byKey(const Key('speed_step_preset_builtin_review')),
      );
      await tester.pumpAndSettle();

      // 无分段线：预览在激活范围外 → 先弹既有三选一。
      expect(find.byKey(const Key('speed_step_scope_dialog')), findsOneWidget);
      expect(doc().selectedId, 'builtin_review');

      await tester.tap(find.byKey(const Key('speed_step_scope_whole_video')));
      await tester.pumpAndSettle();

      expect(container.read(speedControlProvider).stepEnabled, isTrue);
      expect(engine.rate, 0.5, reason: '按该预设首档起跑');
      expect(session().open, isNull, reason: '三态都收起气泡');
    });

    testWidgets('点行三态·已启用点「已启用」那行：停用并收起气泡，选中保留', (tester) async {
      await container
          .read(speedStepPresetProvider.notifier)
          .select('builtin_first');
      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      await pumpOpenStep(tester);
      expect(find.byKey(const Key('speed_step_enabled_badge')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('speed_step_preset_builtin_first')),
      );
      await tester.pumpAndSettle();

      expect(container.read(speedControlProvider).stepEnabled, isFalse);
      expect(engine.rate, 1.0, reason: '停用回到手动倍率');
      expect(session().open, isNull, reason: '三态都收起气泡');
      expect(doc().selectedId, 'builtin_first', reason: '停用只撤「已启用」，「选中」保留');
    });

    testWidgets('点行三态·已启用点别的行：切换（旧的跑停、按新预设起跑），不重走三选一、收起气泡', (tester) async {
      // 让「复习」首档与「初见」不同以观察起跑。
      await container
          .read(speedStepPresetProvider.notifier)
          .updatePreset(
            id: 'builtin_review',
            params: const SpeedStepParams(
              startRate: 0.8,
              maxRate: 1.0,
              lapsPerRate: 2,
              rateIncrement: 0.25,
            ),
          );
      await container
          .read(speedStepPresetProvider.notifier)
          .select('builtin_first');
      await container.read(speedControlProvider.notifier).setStepEnabled(true);
      expect(engine.rate, 0.5, reason: '内置 first 首档 0.5');

      await pumpOpenStep(tester);
      await tester.tap(
        find.byKey(const Key('speed_step_preset_builtin_review')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('speed_step_scope_dialog')),
        findsNothing,
        reason: '切换不重走范围三选一',
      );
      expect(container.read(speedControlProvider).stepEnabled, isTrue);
      expect(doc().selectedId, 'builtin_review');
      expect(engine.rate, 0.8, reason: '旧的跑停、按新预设首档起跑');
      expect(session().open, isNull, reason: '三态都收起气泡');
    });

    testWidgets('预设编辑器只替换步进栏内容：气泡总宽与总高不变、倍速栏原地不动', (tester) async {
      await pumpOpenStep(tester);

      final bubbleBefore = tester
          .renderObject<RenderBox>(find.byKey(const Key('speed_bubble')))
          .size;
      final rateBefore = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );
      final rateTopBefore = rateBefore.localToGlobal(Offset.zero);

      await openEditor(tester, 'builtin_first');

      expect(find.byKey(const Key('speed_step_editor')), findsOneWidget);
      expect(
        find.byKey(const Key('speed_step_preset_builtin_first')),
        findsNothing,
        reason: '编辑器替换步进栏内容',
      );
      final bubbleAfter = tester
          .renderObject<RenderBox>(find.byKey(const Key('speed_bubble')))
          .size;
      final rateAfter = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_rate_column')),
      );
      expect(bubbleAfter.width, bubbleBefore.width, reason: '气泡总宽不变');
      expect(bubbleAfter.height, bubbleBefore.height, reason: '气泡总高不变');
      expect(rateAfter.size, rateBefore.size, reason: '倍速栏原地不动');
      expect(rateAfter.localToGlobal(Offset.zero), rateTopBefore);
    });

    testWidgets('步进栏内容超高在栏内滚动、倍速栏不随之滚动；气泡总高恒 260', (tester) async {
      await pumpOpenStep(tester);

      // 加足够多自定义预设，撑出步进栏内滚动。
      final pn = container.read(speedStepPresetProvider.notifier);
      for (var i = 0; i < 12; i++) {
        await pn.createCustom('预设 $i');
      }
      await tester.pumpAndSettle();

      final rateTop = tester
          .renderObject<RenderBox>(find.byKey(const Key('speed_rate_column')))
          .localToGlobal(Offset.zero);
      final position = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byKey(const Key('speed_step_column_scroll')),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      expect(position.maxScrollExtent, greaterThan(0), reason: '步进栏内容超高可滚');

      await tester.drag(
        find.byKey(const Key('speed_step_column_scroll')),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0), reason: '步进栏在栏内滚动');

      expect(
        tester
            .renderObject<RenderBox>(find.byKey(const Key('speed_bubble')))
            .size
            .height,
        mergedBubbleHeight,
        reason: '气泡总高恒 260',
      );
      expect(
        tester
            .renderObject<RenderBox>(find.byKey(const Key('speed_rate_column')))
            .localToGlobal(Offset.zero),
        rateTop,
        reason: '倍速栏不随步进栏滚动',
      );
    });

    testWidgets('编辑子视图：名称 + 四参数下拉 + 保存/返回；无模态对话框', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      expect(find.byType(AlertDialog), findsNothing, reason: '就地编辑器非模态');
      expect(find.byKey(const Key('speed_step_editor_back')), findsOneWidget);
      expect(find.byKey(const Key('speed_step_editor_name')), findsOneWidget);
      for (final fieldKey in const [
        Key('speed_step_editor_start_rate'),
        Key('speed_step_editor_max_rate'),
        Key('speed_step_editor_laps_per_rate'),
        Key('speed_step_editor_rate_increment'),
      ]) {
        expect(find.byKey(fieldKey), findsOneWidget);
      }
      // 内置编辑含「恢复默认」。
      expect(
        find.byKey(const Key('speed_step_restore_default')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('speed_step_editor_save')), findsOneWidget);
    });

    testWidgets('编辑子视图返回箭头报出中文名', (tester) async {
      final semanticsHandle = tester.ensureSemantics();
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      expectButtonSemantics(
        tester,
        const Key('speed_step_editor_back'),
        label: '返回预设列表',
      );
      semanticsHandle.dispose();
    });

    testWidgets('编辑保存即存：改名称 + 起步参数，保存后写入预设并返回列表', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      // 改名称。
      await tester.enterText(
        find.byKey(const Key('speed_step_editor_name')),
        '精修起步',
      );
      // 起步下拉选 0.6（紧邻当前 0.5，菜单向下可见区即达）。
      await tester.tap(find.byKey(const Key('speed_step_editor_start_rate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.6').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();

      final edited = doc().presets.firstWhere((p) => p.id == 'builtin_first');
      expect(edited.name, '精修起步');
      expect(edited.params.startRate, 0.6);
      expect(doc().selectedId, 'builtin_first', reason: '保存不改选中');
      // 已回到列表视图。
      expect(
        find.byKey(const Key('speed_step_preset_builtin_first')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('speed_step_editor')), findsNothing);
    });

    testWidgets('编辑返回钮：丢弃未保存改动回到列表', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      await tester.enterText(
        find.byKey(const Key('speed_step_editor_name')),
        '不改',
      );
      await tester.tap(find.byKey(const Key('speed_step_editor_back')));
      await tester.pumpAndSettle();

      expect(
        doc().presets.firstWhere((p) => p.id == 'builtin_first').name,
        '初见·大量练习',
      );
      expect(find.byKey(const Key('speed_step_editor')), findsNothing);
    });

    testWidgets('内置编辑恢复默认：参数回出厂并落盘', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      // 先改成非法组合会触发错误演示除外；改起步 0.6 后恢复默认。
      await tester.tap(find.byKey(const Key('speed_step_editor_start_rate')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.6').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_step_restore_default')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();

      expect(
        doc().presets.firstWhere((p) => p.id == 'builtin_first').params,
        const SpeedStepParams(),
      );
    });

    testWidgets('编辑器四参数候选集受限（起步/遍数/递增）', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      // 起步候选 ⊆ 0.1–2.0 步 0.05。
      await tester.tap(find.byKey(const Key('speed_step_editor_start_rate')));
      await tester.pumpAndSettle();
      final startItems = tester
          .widgetList<DropdownMenuItem<double>>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(DropdownMenuItem<double>),
            ),
          )
          .map((item) => item.value)
          .toSet();
      expect(startItems, isNotEmpty);
      expect(
        startItems.difference(rateCandidates().toSet()),
        isEmpty,
        reason: '起步候选全部落在全档 0.05 网格（完备性由纯函数用例覆盖）',
      );
      await tester.tap(find.text('0.5').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 遍数候选 ⊆ 1–20。
      await tester.tap(
        find.byKey(const Key('speed_step_editor_laps_per_rate')),
      );
      await tester.pumpAndSettle();
      final lapItems = tester
          .widgetList<DropdownMenuItem<int>>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(DropdownMenuItem<int>),
            ),
          )
          .map((item) => item.value)
          .toSet();
      expect(lapItems, isNotEmpty);
      expect(lapItems.difference(lapsPerRateCandidates.toSet()), isEmpty);
      await tester.tap(find.text('3').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      // 递增量候选 ⊆ 固定集合。
      await tester.tap(
        find.byKey(const Key('speed_step_editor_rate_increment')),
      );
      await tester.pumpAndSettle();
      final incItems = tester
          .widgetList<DropdownMenuItem<double>>(
            find.descendant(
              of: find.byType(ListView),
              matching: find.byType(DropdownMenuItem<double>),
            ),
          )
          .map((item) => item.value)
          .toSet();
      expect(incItems, isNotEmpty);
      expect(incItems.difference(rateIncrementCandidates.toSet()), isEmpty);
    });

    testWidgets('非法组合（封顶 < 起步）在编辑保存时提示错误、不写入', (tester) async {
      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');

      // 封顶下拉选 0.2（< 起步 0.5）；菜单按选中 1.0 滚动，先拖回顶部。
      await tester.tap(find.byKey(const Key('speed_step_editor_max_rate')));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 800));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('0.2').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('speed_step_editor_error')), findsOneWidget);
      expect(
        doc().presets.firstWhere((p) => p.id == 'builtin_first').params.maxRate,
        1.0,
        reason: '组合非法不写入预设',
      );
    });

    testWidgets('「＋ 新增预设」：进入新建编辑器（默认名自定义 N），保存即建', (tester) async {
      await pumpOpenStep(tester);

      await tester.tap(find.byKey(const Key('speed_step_add_preset')));
      await tester.pumpAndSettle();

      // 新建编辑器：默认名预填「自定义 1」，无恢复默认（非内置）。
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('speed_step_editor_name')))
            .controller!
            .text,
        '自定义 1',
      );
      expect(find.byKey(const Key('speed_step_restore_default')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('speed_step_editor_name')),
        '我的节奏',
      );
      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();
      expect(doc().presets.length, 3);
      final custom = doc().presets.last;
      expect(custom.name, '我的节奏');
      expect(custom.builtin, isFalse);
      expect(doc().selectedId, custom.id);
      // 自定义行出现删除钮（列表视图）。
      expect(find.byKey(Key('speed_step_delete_${custom.id}')), findsOneWidget);
      expect(find.byKey(Key('speed_step_edit_${custom.id}')), findsOneWidget);
    });

    testWidgets('清空名称直接保存：新建兜底默认名「自定义 N」', (tester) async {
      await pumpOpenStep(tester);

      await tester.tap(find.byKey(const Key('speed_step_add_preset')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('speed_step_editor_name')),
        '',
      );
      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();

      expect(doc().presets.length, 3);
      expect(doc().presets.last.name, '自定义 1');
    });

    testWidgets('删除自定义：二次确认弹窗；确认删除、取消保留', (tester) async {
      await pumpOpenStep(tester);
      await tester.tap(find.byKey(const Key('speed_step_add_preset')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('speed_step_editor_name')),
        '临时',
      );
      await tester.tap(find.byKey(const Key('speed_step_editor_save')));
      await tester.pumpAndSettle();
      final customId = doc().presets.last.id;

      // 取消：不删除。
      await tester.tap(find.byKey(Key('speed_step_delete_$customId')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_step_delete_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed_step_delete_cancel')));
      await tester.pumpAndSettle();
      expect(doc().presets.length, 3, reason: '取消删除不生效');

      // 确认：删除自定义。
      await tester.tap(find.byKey(Key('speed_step_delete_$customId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('speed_step_delete_confirm')));
      await tester.pumpAndSettle();
      expect(doc().presets.length, 2);
      expect(doc().presets.where((p) => p.id == customId), isEmpty);
    });

    group('内置预设可删', () {
      /// 点某行删除钮并在二次确认弹窗里确认。
      Future<void> deleteVia(
        WidgetTester tester,
        String id, {
        bool confirm = true,
      }) async {
        await tester.tap(find.byKey(Key('speed_step_delete_$id')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            Key(
              confirm
                  ? 'speed_step_delete_confirm'
                  : 'speed_step_delete_cancel',
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('同一枚删除钮 + 同一个二次确认弹窗（标题「删除预设」）；确认后内置从列表消失', (tester) async {
        await pumpOpenStep(tester);

        await tester.tap(
          find.byKey(const Key('speed_step_delete_builtin_review')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('speed_step_delete_dialog')),
          findsOneWidget,
        );
        expect(find.text('删除预设'), findsOneWidget);
        expect(find.text('删除「复习」？此操作不可撤销。'), findsOneWidget);

        await tester.tap(find.byKey(const Key('speed_step_delete_confirm')));
        await tester.pumpAndSettle();

        expect(doc().presets.map((p) => p.id), ['builtin_first']);
        expect(
          find.byKey(const Key('speed_step_preset_builtin_review')),
          findsNothing,
        );
        expect(find.text('复习'), findsNothing);
        // 跨会话：已按新列表落盘。
        final stored = (storage.snapshot['speedStepPresets']['presets'] as List)
            .cast<Map<String, dynamic>>();
        expect(stored.map((p) => p['id']), ['builtin_first']);
      });

      testWidgets('取消二次确认：内置保留', (tester) async {
        await pumpOpenStep(tester);

        await deleteVia(tester, 'builtin_review', confirm: false);

        expect(doc().presets.length, 2);
        expect(
          find.byKey(const Key('speed_step_preset_builtin_review')),
          findsOneWidget,
        );
      });

      testWidgets('删掉正在生效的预设：步进一并停用、「已启用」标记消失、倍速回手动值', (tester) async {
        await container
            .read(speedStepPresetProvider.notifier)
            .select('builtin_first');
        await container
            .read(speedControlProvider.notifier)
            .setStepEnabled(true);
        await pumpOpenStep(tester);
        expect(
          find.byKey(const Key('speed_step_enabled_badge')),
          findsOneWidget,
        );

        await deleteVia(tester, 'builtin_first');

        expect(container.read(speedControlProvider).stepEnabled, isFalse);
        expect(engine.rate, 1.0, reason: '停用回到手动倍率');
        expect(find.byKey(const Key('speed_step_enabled_badge')), findsNothing);
        expect(doc().presets.map((p) => p.id), ['builtin_review']);
        expect(doc().selectedId, 'builtin_review', reason: '选中回退列表首个');
      });

      testWidgets('删掉当前选中但未启用的预设：选中回退列表首个并应用其参数', (tester) async {
        await pumpOpenStep(tester);

        await deleteVia(tester, 'builtin_first');

        expect(doc().selectedId, 'builtin_review');
        expect(
          container.read(speedControlProvider).stepParams,
          const SpeedStepParams(
            startRate: 0.5,
            maxRate: 1.0,
            lapsPerRate: 2,
            rateIncrement: 0.25,
          ),
          reason: '回退预设的参数已应用',
        );
        expect(container.read(speedControlProvider).stepEnabled, isFalse);
      });

      testWidgets('剩余仅一条时删除被拒绝：列表不会变成空', (tester) async {
        await container
            .read(speedStepPresetProvider.notifier)
            .delete('builtin_review');
        await pumpOpenStep(tester);
        expect(doc().presets.map((p) => p.id), ['builtin_first']);

        await deleteVia(tester, 'builtin_first');

        expect(doc().presets.map((p) => p.id), ['builtin_first']);
        expect(
          find.byKey(const Key('speed_step_preset_builtin_first')),
          findsOneWidget,
        );
      });

      testWidgets('先新建一条自定义垫底，两条内置都可删光', (tester) async {
        await pumpOpenStep(tester);
        await tester.tap(find.byKey(const Key('speed_step_add_preset')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('speed_step_editor_name')),
          '替代',
        );
        await tester.tap(find.byKey(const Key('speed_step_editor_save')));
        await tester.pumpAndSettle();
        final customId = doc().presets.last.id;

        await deleteVia(tester, 'builtin_first');
        await deleteVia(tester, 'builtin_review');

        expect(doc().presets.map((p) => p.id), [customId]);
        expect(find.byKey(Key('speed_step_preset_$customId')), findsOneWidget);
        expect(
          find.byKey(const Key('speed_step_delete_builtin_first')),
          findsNothing,
        );
      });

      testWidgets('被删内置不再有「恢复默认」入口；仍在的内置保持恢复默认与可改名改参', (tester) async {
        await pumpOpenStep(tester);

        await deleteVia(tester, 'builtin_review');

        // 被删内置无行、无编辑入口。
        expect(
          find.byKey(const Key('speed_step_edit_builtin_review')),
          findsNothing,
        );
        // 仍在的内置：编辑器含「恢复默认」，且改名改参照旧生效。
        await openEditor(tester, 'builtin_first');
        expect(
          find.byKey(const Key('speed_step_restore_default')),
          findsOneWidget,
        );
        await tester.enterText(
          find.byKey(const Key('speed_step_editor_name')),
          '初见·改',
        );
        await tester.tap(find.byKey(const Key('speed_step_editor_start_rate')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('0.6').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('speed_step_editor_save')));
        await tester.pumpAndSettle();

        final edited = doc().presets.firstWhere((p) => p.id == 'builtin_first');
        expect(edited.name, '初见·改');
        expect(edited.params.startRate, 0.6);
        expect(edited.builtin, isTrue);
      });
    });

    testWidgets('键盘弹出时气泡随 viewInsets 压缩且内容不重叠', (tester) async {
      tester.view.physicalSize = const Size(
        800,
        600,
      ); // 合成档 800.0×600.0dp（dpr 1），非设备基准。
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpOpenStep(tester);
      await openEditor(tester, 'builtin_first');
      await tester.pumpAndSettle();

      final before = tester
          .renderObject<RenderBox>(find.byKey(const Key('speed_bubble')))
          .size
          .height;
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();

      final bubble = tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_bubble')),
      );
      expect(
        bubble.size.height,
        lessThan(before),
        reason: '气泡高度随键盘 viewInsets 压缩',
      );
      expect(bubble.size.height, lessThanOrEqualTo(600 * 0.7 - 300 + 1));
      expect(
        find.byKey(const Key('speed_step_editor_start_rate')),
        findsOneWidget,
      );
    });

    testWidgets('选中态跨会话恢复：预置存储后重建气泡内容，选中预设保持', (tester) async {
      await storage.write({
        'speedStepPresets': SpeedStepPresetDoc(
          presets: builtinSpeedStepPresets,
          selectedId: 'builtin_review',
        ).toJson(),
      });
      await pumpOpenStep(tester);

      expect(doc().selectedId, 'builtin_review');
      expect(
        container.read(speedControlProvider).stepParams.startRate,
        0.5,
        reason: '重启等价：选中预设参数随之应用',
      );
    });
  });

  group('倍率选择化（数字输入移除、候选集受限）', () {
    testWidgets('倍速气泡：无任何数字输入框', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing, reason: '倍速标题已下拉化');
    });

    testWidgets('步进栏：四参数均为下拉、唯一输入 = 编辑/新建的预设名称', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      // 列表视图：无任何输入框（参数下拉只在编辑子视图内）。
      expect(find.byType(TextField), findsNothing);

      // 进入内置预设编辑器：四参数为下拉（key 保留）、名称输入保留。
      await tester.tap(find.byKey(const Key('speed_step_edit_builtin_first')));
      await tester.pumpAndSettle();
      for (final fieldKey in const [
        Key('speed_step_editor_start_rate'),
        Key('speed_step_editor_max_rate'),
        Key('speed_step_editor_laps_per_rate'),
        Key('speed_step_editor_rate_increment'),
      ]) {
        expect(find.byKey(fieldKey), findsOneWidget, reason: '$fieldKey 为下拉');
      }
      // 唯一保留的输入 = 编辑器内预设名称。
      expect(
        find.byType(TextField),
        findsOneWidget,
        reason: '唯一保留的输入 = 编辑子视图内的预设名称',
      );
    });

    test('候选集纯函数：全档 0.05 网格、遍数 1–20、递增固定集合、置顶去重', () {
      final grid = rateCandidates();
      expect(grid.length, 39);
      expect(grid.first, 0.1);
      expect(grid.last, 2.0);
      for (final rate in grid) {
        expect(((rate * 100).round()) % 5, 0, reason: '$rate 在 0.05 网格');
      }

      expect(lapsPerRateCandidates, List.generate(20, (i) => i + 1));
      expect(rateIncrementCandidates, [0.05, 0.1, 0.2, 0.25, 0.5]);

      final pinned = pinnedRateCandidates(
        current: 0.75,
        common: commonSpeeds,
        history: const [1.8, 0.75],
      );
      expect(pinned.first, 0.75, reason: '当前值置顶');
      expect(pinned, pinned.toSet().toList(), reason: '去重');
      expect(
        pinned.indexOf(1.8),
        lessThan(pinned.indexOf(0.1)),
        reason: '历史置顶于全档尾部',
      );
      expect(pinned.length, 39, reason: '全档补齐（0.75/1.8 去重）');
    });
  });

  group('Esc 与浮层退出路径', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: [
          playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
          speedStepPresetStorageProvider.overrideWithValue(
            SpeedStepPresetStore(InMemoryPrivateJsonStorage()),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    Future<void> pumpHost(WidgetTester tester) async {
      final link = LayerLink();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: CompositedTransformTarget(
                      link: link,
                      child: const SizedBox(width: 80, height: 40),
                    ),
                  ),
                  SpeedBubbleHost(
                    linkFor: (_) => link,
                    targetAnchor: Alignment.topCenter,
                    followerAnchor: Alignment.bottomCenter,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    void open(SpeedBubbleMode mode) =>
        container.read(speedBubbleSessionProvider.notifier).open(mode);

    testWidgets('按 Esc 收起气泡：气泡与遮罩都不在场', (tester) async {
      await pumpHost(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_bubble_scrim')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        isNull,
        reason: 'Esc 应走会话 close 路径',
      );
      expect(find.byKey(const Key('speed_bubble_scrim')), findsNothing);
      expect(find.byType(SpeedBubble), findsNothing);
    });

    testWidgets('遮罩自报退出语义：dismiss 动作触发收起', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(
        find.byKey(const Key('speed_bubble_scrim')),
      );
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.dismiss),
        isTrue,
      );
      expect(semantics.getSemanticsData().label, contains('收起'));

      // 测试绑定的语义树挂在 binding.pipelineOwner（rootPipelineOwner 之外）。
      // ignore: deprecated_member_use
      tester.binding.pipelineOwner.semanticsOwner!.performAction(
        semantics.id,
        SemanticsAction.dismiss,
      );
      await tester.pumpAndSettle();
      expect(container.read(speedBubbleSessionProvider).open, isNull);
      handle.dispose();
    });

    testWidgets('点气泡外收起路径保持不变', (tester) async {
      await pumpHost(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 300));
      await tester.pumpAndSettle();

      expect(container.read(speedBubbleSessionProvider).open, isNull);
      expect(find.byKey(const Key('speed_bubble_scrim')), findsNothing);
    });

    testWidgets('非 Esc 按键不收起气泡', (tester) async {
      await pumpHost(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(
        container.read(speedBubbleSessionProvider).open,
        SpeedBubbleMode.speed,
      );
    });
  });

  group('命中盒下限', () {
    testWidgets('档位钮命中层 ≥ 48；点每个钮的中心仍就是哪个档就是哪个档', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final resident = List<double>.from(commonSpeeds.reversed);
      final column = tester.getRect(
        find.byKey(const Key('speed_quick_column')),
      );
      for (final rate in resident) {
        final hit = tester.getRect(find.byKey(Key('speed_quick_hit_$rate')));
        expect(
          hit.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$rate 命中层宽 ≥ 48',
        );
        expect(
          hit.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$rate 命中层高 ≥ 48',
        );
        // 命中层与视觉按钮同列宽（列宽不变）。
        expect(hit.width, column.width);
        // 命中层整个落在列内（没有越出可测界的部分）。
        expect(
          hit.top,
          greaterThanOrEqualTo(column.top - 0.01),
          reason: '$rate 命中层不越出列上缘',
        );
        expect(
          hit.bottom,
          lessThanOrEqualTo(column.bottom + 0.01),
          reason: '$rate 命中层不越出列下缘',
        );
      }
      // 视觉按钮仍 32 高（外扩未改样子）。
      for (final rate in resident) {
        expect(
          tester.getSize(find.byKey(Key('speed_quick_$rate'))).height,
          speedRateButtonHeight,
        );
      }
      // 点每个钮的中心：命中不互吞，生效的就是被点的那档。
      for (final rate in resident) {
        await tester.tap(find.byKey(Key('speed_quick_$rate')));
        await tester.pumpAndSettle();
        expect(engine.rate, rate, reason: '点 $rate 生效 $rate（相邻钮不互吞）');
        if (container.read(speedBubbleSessionProvider).open == null) {
          open(SpeedBubbleMode.speed);
          await tester.pumpAndSettle();
        }
      }
      // 命中层真的外扩：点视觉钮下缘 2dp（在命中层里、不在视觉钮上）仍生效。
      final midHit = tester.getRect(
        find.byKey(Key('speed_quick_hit_${resident[2]}')),
      );
      await tester.tapAt(Offset(midHit.center.dx, midHit.top + 34));
      await tester.pumpAndSettle();
      expect(engine.rate, resident[2], reason: '命中层下缘外扩区也能点到该档');
      // 相邻钮不互吞（逐处证明）：点某钮视觉下缘 1dp 仍归它、点下一钮视觉
      // 上缘 1dp 归下一钮——重叠命中层不夺走邻钮的视觉区。
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      final upper = tester.getRect(
        find.byKey(Key('speed_quick_${resident[2]}')),
      );
      await tester.tapAt(Offset(upper.center.dx, upper.bottom - 1));
      await tester.pumpAndSettle();
      expect(engine.rate, resident[2], reason: '上钮视觉下缘归上钮');
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();
      final lower = tester.getRect(
        find.byKey(Key('speed_quick_${resident[3]}')),
      );
      await tester.tapAt(Offset(lower.center.dx, lower.top + 1));
      await tester.pumpAndSettle();
      expect(engine.rate, resident[3], reason: '下钮视觉上缘归下钮');
    });

    testWidgets('历史档位命中层 ≥ 48 且可点生效', (tester) async {
      await model().setRate(1.0);
      model().recordHistory(0.8);
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      final hit = tester.getRect(
        find.byKey(const Key('speed_history_hit_0.8')),
      );
      expect(hit.width, greaterThanOrEqualTo(kHitTargetMinSize));
      expect(hit.height, greaterThanOrEqualTo(kHitTargetMinSize));
      final column = tester.getRect(
        find.byKey(const Key('speed_history_column')),
      );
      expect(hit.top, greaterThanOrEqualTo(column.top - 0.01));
      expect(hit.bottom, lessThanOrEqualTo(column.bottom + 0.01));
      // 点视觉钮下缘之外、命中层内的区域（只有命中层覆盖该点）。
      await tester.tapAt(Offset(hit.center.dx, hit.top + 40));
      await tester.pumpAndSettle();
      expect(engine.rate, 0.8);
    });

    testWidgets('预设行编辑/删除钮与返回箭头命中盒 ≥ 48；视觉图标仍 18dp', (tester) async {
      await pumpBubble(tester);
      open(SpeedBubbleMode.speed);
      await tester.pumpAndSettle();

      for (final key in const [
        Key('speed_step_edit_builtin_first'),
        Key('speed_step_delete_builtin_first'),
      ]) {
        final rect = tester.getRect(find.byKey(key));
        expect(
          rect.width,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中盒宽 ≥ 48',
        );
        expect(
          rect.height,
          greaterThanOrEqualTo(kHitTargetMinSize),
          reason: '$key 命中盒高 ≥ 48',
        );
        expect(
          tester
              .getRect(
                find.descendant(
                  of: find.byKey(key),
                  matching: find.byType(Icon),
                ),
              )
              .size,
          const Size(18, 18),
          reason: '$key 图标仍 18dp',
        );
      }
      // 删除钮仍可点：弹二次确认。
      await tester.tap(
        find.byKey(const Key('speed_step_delete_builtin_first')),
      );
      await tester.pumpAndSettle();
      expect(find.text('删除预设'), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed_step_delete_cancel')));
      await tester.pumpAndSettle();

      // 返回箭头命中盒 ≥ 48，且仍能返回列表。
      await tester.tap(find.byKey(const Key('speed_step_edit_builtin_first')));
      await tester.pumpAndSettle();
      final back = tester.getRect(
        find.byKey(const Key('speed_step_editor_back')),
      );
      expect(back.width, greaterThanOrEqualTo(kHitTargetMinSize));
      expect(back.height, greaterThanOrEqualTo(kHitTargetMinSize));
      expect(
        tester
            .getRect(
              find.descendant(
                of: find.byKey(const Key('speed_step_editor_back')),
                matching: find.byType(Icon),
              ),
            )
            .size,
        const Size(18, 18),
        reason: '返回箭头图标仍 18dp',
      );
      await tester.tap(find.byKey(const Key('speed_step_editor_back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('speed_step_editor')), findsNothing);
    });
  });
}
