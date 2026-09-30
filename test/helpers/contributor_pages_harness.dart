import 'package:dance_learning_app/about/about_page.dart'
    show aboutAppVersionProvider;
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/update/update_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'contributor_assets_fixture.dart';
import 'fake_help_asset_bundle.dart';
import 'help_assets_fixture.dart';

/// 一份关于页内容的假资产包：名单按 [records] 逐条写出，每位贡献者的个人介绍
/// 取 [intros] 里他那份（缺省给一段带一级标题的确定正文）；[assets] 追加帮助
/// 条目之类的其余文本资产（个人介绍里的**条目链接**要解析得到目标条目）。
FakeHelpAssetBundle contributorBundle({
  List<ContributorFixture> records = const [sampleContributor],
  Map<String, String> intros = const {},
  Map<String, String> assets = const {},
  Map<String, Uint8List> binary = const {},
}) {
  return FakeHelpAssetBundle({
    // 引导文案：正文里的**条目链接**解析要读帮助内容，给一副合法文案，装载
    // 就不走「文案解析失败」的降级分支。
    onboardingCopyAssetKey: helpOnboardingStub,
    contributorRosterAsset: contributorRosterYaml(records),
    for (final record in records)
      contributorIntroAsset(record.id):
          intros[record.id] ??
          '# ${record.displayName}\n\n${record.displayName}的自述。\n',
    ...assets,
  }, binary: binary);
}

/// 关于页 / 贡献者名单页 / 个人介绍页 widget 测试共用的装配：版本号与本机构建
/// 号给确定值、资产包喂假件，[overrides] 追加平台动作端口之类的替身覆写。
Future<void> pumpContributorSurface(
  WidgetTester tester, {
  required Widget home,
  required AssetBundle bundle,
  Size viewport = const Size(1000, 2000),
  List<Override> overrides = const [],
}) async {
  // 合成档视口（入参 viewport，默认 1000×2000dp；dpr 1.0），非设备档。
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        helpAssetBundleProvider.overrideWithValue(bundle),
        aboutAppVersionProvider.overrideWith((ref) => '0.1.0'),
        localBuildNumberProvider.overrideWith((ref) => 1),
        ...overrides,
      ],
      child: MaterialApp(home: home),
    ),
  );
  await tester.pumpAndSettle();
}
