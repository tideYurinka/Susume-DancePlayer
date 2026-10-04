import 'dart:math' as math;

import 'package:dance_learning_app/core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'package:dance_learning_app/import/import_providers.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/player/player_page.dart';
import 'package:dance_learning_app/player/rate_label_slot.dart';
import 'package:dance_learning_app/player/speed_control.dart';
import 'package:dance_learning_app/player/speed_step.dart' show formatRate;
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';
import '../helpers/fake_system_ui.dart';
import '../helpers/in_memory_video_index_storage.dart';
import '../helpers/video_index_fixtures.dart';

void main() {
  // 倍速文字固定槽位——宽度 = 可能的最宽显示文本，文字居中。
  group('固定槽位宽度纯函数（Testing Decisions：纯函数 seam）', () {
    const style = TextStyle(fontSize: 14);

    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    test('槽位宽度 ≥ 任一可达倍率的显示文本宽度（含 1x / 1.05x / 2x）', () {
      final slot = rateLabelSlotWidth(style);
      for (final rate in const [speedRateMin, 1.0, 1.05, 1.5, speedRateMax]) {
        expect(
          slot,
          greaterThanOrEqualTo(textWidth('${formatRate(rate)}x', style)),
          reason: '槽位须容纳 ${formatRate(rate)}x',
        );
      }
    });

    test('槽位宽度 = 候选集最宽文本宽度 + 前后内边距（内边距含入）', () {
      final candidates = rateLabelCandidates();
      expect(candidates, isNotEmpty);
      var widest = 0.0;
      for (final rate in candidates) {
        widest = math.max(widest, textWidth('${formatRate(rate)}x', style));
      }
      expect(
        rateLabelSlotWidth(style),
        widest + 2 * kRateSlotHorizontalPadding,
      );
      // 两位小数文本等宽（同字符数）：最宽文本宽度不因具体取值抖动。
      expect(textWidth('${formatRate(1.05)}x', style), widest);
    });
  });

  group('槽宽缩放口径（量测吃调用处缩放，定宽下限 1）', () {
    const style = TextStyle(fontSize: 14);

    double scaledTextWidth(String text, TextStyle style, TextScaler scaler) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final w = painter.width;
      painter.dispose();
      return w;
    }

    test('textScaler < 1：槽宽不收缩（紧约束槽比内容窄会溢出）', () {
      expect(
        rateLabelSlotWidth(style, textScaler: TextScaler.linear(0.8)),
        rateLabelSlotWidth(style),
      );
    });

    test('textScaler > 1：槽宽随缩放放大，容纳缩放后的最宽文本（1.3/1.6/2.0 档）', () {
      for (final factor in const [1.3, 1.6, 2.0]) {
        final scaler = TextScaler.linear(factor);
        final scaled = rateLabelSlotWidth(style, textScaler: scaler);
        expect(scaled, greaterThan(rateLabelSlotWidth(style)));
        var widest = 0.0;
        for (final rate in rateLabelCandidates()) {
          widest = math.max(
            widest,
            scaledTextWidth('${formatRate(rate)}x', style, scaler),
          );
        }
        expect(scaled, widest + 2 * kRateSlotHorizontalPadding);
      }
    });

    test('缓存键含缩放：先取 1.3× 再取默认，两档互不命中', () {
      final scaled = rateLabelSlotWidth(
        style,
        textScaler: TextScaler.linear(1.3),
      );
      expect(rateLabelSlotWidth(style), lessThan(scaled));
      expect(
        rateLabelSlotWidth(style, textScaler: TextScaler.linear(1.3)),
        scaled,
      );
    });
  });

  group('RateTextSlot 随系统字号（widget seam）', () {
    const style = TextStyle(fontSize: 14);

    Future<Size> pumpSlot(WidgetTester tester, double scale) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: RateTextSlot(rate: 1.05, style: style)),
          ),
        ),
      );
      return tester.renderObject<RenderBox>(find.byType(RateTextSlot)).size;
    }

    testWidgets('1.3×：槽宽随缩放放大且容纳缩放后的读数文本', (tester) async {
      final slotWidth = await pumpSlot(tester, 1.3);
      expect(
        slotWidth.width,
        rateLabelSlotWidth(style, textScaler: TextScaler.linear(1.3)),
      );
      final textBox = tester.renderObject<RenderBox>(find.text('1.05x'));
      expect(textBox.size.width, lessThanOrEqualTo(slotWidth.width));
    });

    testWidgets('0.8×：槽宽不收缩（与默认档同宽）', (tester) async {
      final shrunken = await pumpSlot(tester, 0.8);
      expect(shrunken.width, rateLabelSlotWidth(style));
    });
  });

  group('观看态胶囊/顶栏倍速工具几何恒定（widget seam）', () {
    Future<ProviderContainer> pumpPlayer(
      WidgetTester tester, {
      required FakePlaybackEngine engine,
    }) async {
      final resolvedSource = Uri.file('/videos/a.mp4');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackEngineProvider.overrideWithValue(engine),
            systemUiControllerProvider.overrideWithValue(FakeSystemUi()),
            videoIndexStoreProvider.overrideWithValue(
              InMemoryVideoIndexStorage(
                initial: VideoIndex(
                  entries: [
                    historyEntry(
                      filePath: resolvedSource.toFilePath(),
                      mirrored: false,
                    ),
                  ],
                ),
              ),
            ),
          ],
          child: MaterialApp(home: PlayerPage(source: resolvedSource)),
        ),
      );
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(PlayerPage)));
    }

    /// 单击唤出控制层：等双击判定窗口过（识别器回调孤立单指单击）后渲染。
    Future<void> singleTapShow(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('player_surface')));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 30));
      await tester.pump();
    }

    testWidgets('观看态胶囊：1x → 1.05x 按钮宽与几何中心恒定', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpPlayer(tester, engine: engine);

      RenderBox capsuleBox() => tester.renderObject<RenderBox>(
        find.byKey(const Key('speed_entry_button')),
      );
      Rect globalRect(RenderBox box) =>
          box.localToGlobal(Offset.zero) & box.size;

      final beforeSize = capsuleBox().size;
      final beforeRect = globalRect(capsuleBox());
      expect(find.text('1x'), findsOneWidget);

      await container.read(speedControlProvider.notifier).setRate(1.05);
      await tester.pumpAndSettle();

      expect(find.text('1.05x'), findsOneWidget);
      expect(capsuleBox().size, beforeSize, reason: '槽位固定 → 按钮宽不变');
      expect(globalRect(capsuleBox()), beforeRect, reason: '几何中心恒定');
    });

    testWidgets('顶栏倍速工具：1.05x → 1.5x 工具宽与几何中心恒定', (tester) async {
      final engine = FakePlaybackEngine(duration: const Duration(minutes: 3));
      final container = await pumpPlayer(tester, engine: engine);
      await singleTapShow(tester);

      // 基线取「生效中」激活态（1.0 不激活、标签为「倍速设置」）：两种倍率
      // 位数下工具几何必须恒定。
      await container.read(speedControlProvider.notifier).setRate(1.05);
      await tester.pump();

      RenderBox toolBox() => tester.renderObject<RenderBox>(
        find.byKey(const Key('tool_speed_settings')),
      );
      Rect globalRect(RenderBox box) =>
          box.localToGlobal(Offset.zero) & box.size;

      final beforeSize = toolBox().size;
      final beforeRect = globalRect(toolBox());
      expect(find.text('1.05x'), findsOneWidget);

      await container.read(speedControlProvider.notifier).setRate(1.5);
      await tester.pump();

      expect(find.text('1.5x'), findsOneWidget);
      expect(toolBox().size, beforeSize, reason: '槽位固定 → 工具宽不变');
      expect(globalRect(toolBox()), beforeRect, reason: '气泡锚点中心恒定');
    });
  });
}
