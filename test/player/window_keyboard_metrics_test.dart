import 'package:dance_learning_app/player/window_keyboard_metrics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late double latestInset;
  late Size latestSize;
  var builds = 0;

  // FakeViewPadding 为物理像素（测试面 dpr = 3.0）：900 物理 = 300 逻辑。
  Widget probe() => Directionality(
    textDirection: TextDirection.ltr,
    child: WindowMetricsWatcher(
      builder: (context, viewData) {
        builds++;
        latestInset = viewData.viewInsets.bottom;
        latestSize = viewData.size;
        return const SizedBox.shrink();
      },
    ),
  );

  setUp(() {
    builds = 0;
  });

  testWidgets('取值正确：builder 收到窗口真实键盘下沿 inset 与视口尺寸', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    tester.view.physicalSize = const Size(
      1170,
      1800,
    ); // 合成档 390.0×600.0dp（dpr 3），非设备基准。
    await tester.pumpWidget(probe());

    expect(latestInset, 300);
    expect(latestSize, const Size(390, 600));
  });

  testWidgets('窗口 metrics 变化驱动消费方重建', (tester) async {
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpWidget(probe());
    expect(builds, 1);
    expect(latestInset, 0);

    // 键盘弹出：metrics 变化应触发重建并给出新的 inset。
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pump();
    expect(builds, 2);
    expect(latestInset, 300);

    // 键盘收起：再次重建，inset 回零。
    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(builds, 3);
    expect(latestInset, 0);
  });
}
