import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/guide_anchor.dart';
import 'package:dance_learning_app/help/guide_host.dart';
import 'package:dance_learning_app/help/guide_state.dart'
    show OnboardingStore, onboardingStorageProvider;
import 'package:dance_learning_app/help/guide_units_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 新手引导页两套件（清点 / 重置、逐条重看）共用的装配：拉高视口让整张表
/// 都在树里（默认 800×600 下 ListView 只建可见行），引导演出层包住整个 App
/// （同生产装配），首页放首启两个锚点与一个进页按钮。
Future<void> pumpGuideUnitsHarness(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
}) async {
  tester.view.physicalSize = const Size(1000, 3000); // 合成档 1000×3000dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
      ],
      child: MaterialApp(
        builder: (_, child) => GuideHost(child: child!),
        home: Scaffold(
          body: Column(
            children: [
              GuideAnchor(
                anchorKey: importVideoAnchorKey,
                child: Container(
                  key: const Key('import_video_button'),
                  width: 40,
                  height: 40,
                  color: Colors.blue,
                ),
              ),
              GuideAnchor(
                anchorKey: homeHelpEntryAnchorKey,
                child: Container(
                  key: const Key('home_help_entry'),
                  width: 40,
                  height: 40,
                  color: Colors.blue,
                ),
              ),
              GuideAnchor(
                anchorKey: segmentLineAnchorKeyBase,
                child: Container(
                  key: const Key('segment_line'),
                  width: 40,
                  height: 40,
                  color: Colors.blue,
                ),
              ),
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => _pushGuideUnitsPage(context),
                  child: const Text('units'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// 直推新手引导页（不过首页按钮）：首页上可能正演着首启引导，全屏压暗层会
/// 吞掉点击；页面的真实进入路径由帮助中心 / 播放页套件断言。
Future<void> openGuideUnitsPage(WidgetTester tester) async {
  tester
      .state<NavigatorState>(find.byType(Navigator))
      .push(MaterialPageRoute<void>(builder: (_) => const GuideUnitsPage()));
  await tester.pumpAndSettle();
}

/// 从新手引导页回到上一层表面。
Future<void> backFromGuideUnitsPage(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator)).pop();
  await tester.pumpAndSettle();
}

void _pushGuideUnitsPage(BuildContext context) {
  Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => const GuideUnitsPage()));
}
