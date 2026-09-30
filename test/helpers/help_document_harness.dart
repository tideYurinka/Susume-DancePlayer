import 'package:dance_learning_app/help/content_registry.dart'
    show downloadVideoTutorialId;
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_help_asset_bundle.dart';
import 'help_assets_fixture.dart';

/// 文档页 widget 测试共用的装配（`help_document_page_test` 与
/// `help_fold_block_test`）：假资产包喂「下载视频」这一条的 Markdown，直开
/// 文档页；视口默认够高，整篇都在树里。[overrides] 追加平台动作端口之类的
/// 替身覆写（假资产包的覆写恒在首位）。
Future<void> pumpHelpDocumentPage(
  WidgetTester tester, {
  required String markdown,
  Map<String, Uint8List> binary = const {},
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
        helpAssetBundleProvider.overrideWithValue(
          FakeHelpAssetBundle({
            '$downloadVideoTutorialDirectory/下载视频.md': markdown,
          }, binary: binary),
        ),
        ...overrides,
      ],
      child: const MaterialApp(
        home: HelpDocumentPage(documentId: downloadVideoTutorialId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
