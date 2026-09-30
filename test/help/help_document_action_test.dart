import 'package:dance_learning_app/feedback/issue_report_page.dart';
import 'package:dance_learning_app/help/content_registry.dart';
import 'package:dance_learning_app/help/help_documents.dart';
import 'package:dance_learning_app/help/help_document_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/help_assets_fixture.dart';

/// 文档页动作区接缝（接缝三，既有帮助文档渲染面）：
/// 只有「问题反馈」这一条教程声明动作、动作区只出现在它上面。
void main() {
  Future<void> pumpDocument(WidgetTester tester, String documentId) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpAssetBundleProvider.overrideWithValue(
            FakeHelpAssetBundle(const {
              '$feedbackTutorialDirectory/问题反馈.md':
                  '# 问题反馈\n\n这是问题反馈\n',
              '$downloadVideoTutorialDirectory/下载视频.md':
                  '# 下载视频\n\n下载正文\n',
            }),
          ),
        ],
        child: MaterialApp(home: HelpDocumentPage(documentId: documentId)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('「问题反馈」教程页正文下方出现动作区，按下进「发送问题日志」表单页', (tester) async {
    // 条目 id 按真实目录名用与装载同一处推导函数现算：常量一旦与目录名漂移，
    // 这里就落不到动作、当场失败。
    final documentId = helpDocumentIdOfDirectory(feedbackTutorialDirectory);
    expect(
      feedbackTutorialId,
      documentId,
      reason: '条目 id 常量必须等于真实目录名去掉数字前缀的结果',
    );
    await pumpDocument(tester, documentId);

    expect(find.byKey(const Key('help_document_action_area')), findsOneWidget);
    expect(find.text(issueReportTitle), findsOneWidget);

    await tester.tap(find.text(issueReportTitle));
    await tester.pumpAndSettle();
    expect(find.byType(IssueReportPage), findsOneWidget);
    // 钮文案与表单页标题同源（都取 [issueReportTitle]）。
    expect(find.widgetWithText(AppBar, issueReportTitle), findsOneWidget);
  });

  testWidgets('别的文档条目页没有动作区', (tester) async {
    await pumpDocument(tester, downloadVideoTutorialId);

    expect(find.byKey(const Key('help_document_action_area')), findsNothing);
    expect(find.text(issueReportTitle), findsNothing);
  });
}
