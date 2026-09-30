import 'package:dance_learning_app/app.dart';
import 'package:dance_learning_app/player/system_ui.dart'
    show systemUiControllerProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_system_ui.dart';

void main() {
  testWidgets('App 骨架可构建运行（首页导入入口）', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: DanceLearningApp()));
    await tester.pumpAndSettle();

    expect(find.text('Susume'), findsOneWidget);
    expect(find.byKey(const Key('import_video_button')), findsOneWidget);
    expect(find.text('导入视频'), findsOneWidget);
  });

  testWidgets('App 根启动即请求全局竖屏锁（启动瞬间竖屏，不随系统旋转开关）', (tester) async {
    final systemUi = FakeSystemUi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [systemUiControllerProvider.overrideWithValue(systemUi)],
        child: const DanceLearningApp(),
      ),
    );
    await tester.pump();

    expect(
      systemUi.lockPortraitCount,
      1,
      reason: 'App 起来的那一刻就由 App 自己请求竖屏',
    );
    expect(systemUi.enterCount, 0, reason: '启动不进入播放器模式');
  });
}
