import 'package:dance_learning_app/core/private_json.dart';
import 'package:dance_learning_app/help/content_registry.dart'
    show homeHelpEntryAnchorKey, importVideoAnchorKey;
import 'package:dance_learning_app/help/guide_anchor.dart' show GuideAnchor;
import 'package:dance_learning_app/help/guide_host.dart' show GuideHost;
import 'package:dance_learning_app/help/guide_state.dart'
    show
        OnboardingStore,
        guideSessionProvider,
        onboardingStorageProvider;
import 'package:dance_learning_app/help/help_documents.dart' show helpAssetBundleProvider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// 首启引导 widget 测试共用的装配（`first_run_flow_test` 与
/// `help_fold_block_test`）：引导演出层包住整个 App（同生产装配），首页放首启
/// 两个锚点。传入 [helpAssets] 时用它替换随包资产（喂假内容）；[overrides]
/// 追加平台动作端口之类的替身覆写。
Future<void> pumpFirstRunHost(
  WidgetTester tester, {
  required PrivateJsonStorage storage,
  AssetBundle? helpAssets,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = const Size(1000, 1600); // 合成档 1000×1600dp，非设备档。
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        privateJsonStorageProvider.overrideWithValue(storage),
        onboardingStorageProvider.overrideWithValue(OnboardingStore(storage)),
        if (helpAssets != null)
          helpAssetBundleProvider.overrideWithValue(helpAssets),
        ...overrides,
      ],
      child: MaterialApp(
        builder: (_, child) => GuideHost(child: child!),
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                left: 40,
                top: 40,
                child: GuideAnchor(
                  anchorKey: homeHelpEntryAnchorKey,
                  child: const SizedBox(
                    key: Key('home_help_entry'),
                    width: 48,
                    height: 48,
                  ),
                ),
              ),
              Positioned(
                left: 40,
                top: 600,
                child: GuideAnchor(
                  anchorKey: importVideoAnchorKey,
                  child: const SizedBox(
                    key: Key('import_video_button'),
                    width: 120,
                    height: 48,
                  ),
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

/// 清掉首启的本会话进度（riverpod 3 的会话 provider 状态随测试进程存活、
/// 跨用例不随 ProviderScope 重建）。
void resetFirstRunSession(WidgetTester tester) {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(GuideHost)),
  );
  container.read(guideSessionProvider.notifier).clearUnit('first_run');
}
