import 'package:dance_learning_app/cast/cast_beat_count.dart'
    show CastBeatCountText;
import 'package:dance_learning_app/core/current_beat.dart'
    show PracticeBeatCount;
import 'package:dance_learning_app/player/beat_animation.dart'
    show
        BeatAnimationStyle,
        kBeatBarAnimationHeight,
        kBeatPendulumAnimationHeight;
import 'package:dance_learning_app/player/beat_count_layout.dart';
import 'package:dance_learning_app/player/cast_beat_sheet.dart'
    show measureCastBeatRow;
import 'package:dance_learning_app/player/metronome_overlay.dart'
    show BeatCountNumbers, beatCountTextOf;
import 'package:dance_learning_app/player/overlay.dart'
    show kPendulumBaseContentSize;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **数拍数字在浮层内容区里的布局算术**与**真实 Flutter 布局**逐项对：把上屏
/// `BeatCountContent` 那一套（`Center` + 底衬内边距 + `Column[数字行, 间距,
/// 动画位]`）在测试里搭出来，量出数字行的真实中心，再与
/// [beatNumbersCenterInContent] 的算术比——两形态与系统字号各一跑。
///
/// 动画位在测试里用同高的占位盒代替（这套布局只关心它占的高度）：这正是副本里
/// 「不画动画、但把动画那一格高度留着」的依据。
void main() {
  const display = PracticeBeatCount(eightCount: 3, beatCount: 5);
  final text = beatCountTextOf(display);

  CastBeatCountText castText() => CastBeatCountText(
    eightCount: text.eightCount,
    group: text.group,
    beatCount: text.beatCount,
  );

  /// 上屏那一套内容：`Center` + 底衬（内边距与圆角）+ `Column[数字, 间距, 动画]`。
  Widget content({required double animationHeight}) => Center(
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kBeatPillPaddingH,
        vertical: kBeatPillPaddingV,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(kBeatPillRadius),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BeatCountNumbers(display: display),
          const SizedBox(height: kBeatNumbersGap),
          SizedBox(height: animationHeight, width: 100),
        ],
      ),
    ),
  );

  /// 数字行中心（屏幕坐标）与算术（内容区左上角 + 推导中心）比。
  void expectCenterMatches({
    required WidgetTester tester,
    required Size contentSize,
    required BeatAnimationStyle style,
    required TextScaler textScaler,
    required double textScale,
  }) {
    final actual = tester
        .getRect(find.byKey(const Key('beat_count_practice')))
        .center;
    final measured = measureCastBeatRow(
      text: castText(),
      textScaler: textScaler,
    )!.size;
    final expected =
        tester.getTopLeft(find.byKey(const Key('content_box'))) +
        beatNumbersCenterInContent(
          contentSize: contentSize,
          numbersSize: measured,
          style: style,
          textScale: textScale,
        );

    expect(actual.dx, closeTo(expected.dx, 0.01));
    expect(actual.dy, closeTo(expected.dy, 0.01));
  }

  testWidgets('矩形形态：数字行中心与布局算术逐位一致', (tester) async {
    const contentSize = Size(320, 120);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: KeyedSubtree(
            key: const Key('content_box'),
            child: SizedBox.fromSize(
              size: contentSize,
              child: content(animationHeight: kBeatBarAnimationHeight),
            ),
          ),
        ),
      ),
    );

    expectCenterMatches(
      tester: tester,
      contentSize: contentSize,
      style: BeatAnimationStyle.bar,
      textScaler: TextScaler.noScaling,
      textScale: 1,
    );
  });

  testWidgets('系统字号放大：内容区竖向容量倍率与算术同判', (tester) async {
    const textScaler = TextScaler.linear(1.5);
    const contentSize = Size(320, 120 * 1.5);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: textScaler),
          child: Center(
            child: KeyedSubtree(
              key: const Key('content_box'),
              child: SizedBox.fromSize(
                size: contentSize,
                child: content(animationHeight: kBeatBarAnimationHeight),
              ),
            ),
          ),
        ),
      ),
    );

    expectCenterMatches(
      tester: tester,
      contentSize: contentSize,
      style: BeatAnimationStyle.bar,
      textScaler: textScaler,
      textScale: 1.5,
    );
  });

  testWidgets('摆锤形态：内容区被等比铺满，数字行中心与算术同判', (tester) async {
    // `_sizedContent` 的摆锤分支：内容区 = 框（320 × 218.18…），基准盒
    // 220×120 被 FittedBox 等比铺满。
    const contentSize = Size(320, 120 * 320 / 220);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: KeyedSubtree(
            key: const Key('content_box'),
            child: SizedBox.fromSize(
              size: contentSize,
              child: FittedBox(
                fit: BoxFit.fill,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: kPendulumBaseContentSize.width,
                  height: kPendulumBaseContentSize.height,
                  child: content(animationHeight: kBeatPendulumAnimationHeight),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expectCenterMatches(
      tester: tester,
      contentSize: contentSize,
      style: BeatAnimationStyle.pendulum,
      textScaler: TextScaler.noScaling,
      textScale: 1,
    );
  });
}
