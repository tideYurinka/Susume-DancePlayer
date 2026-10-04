import 'dart:io';

import 'package:dance_learning_app/help/help_documents.dart'
    show onboardingCopyAssetKey;
import 'package:dance_learning_app/help/help_platform_actions.dart';
import 'package:dance_learning_app/help/platform_help_actions.dart'
    show helpImageSaverProvider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/fake_help_platform_actions.dart';
import '../helpers/first_run_harness.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/help_document_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 帮助正文的图片保存：长按正文缩略图与全屏大图都把那张图的字节
/// 与文件名交给保存件——两处行为一致、长按直接保存不弹菜单；成功提示「已保存
/// 到相册」，权限被拒提示「需要相册权限才能保存」，其它失败提示「保存失败」。
/// 文档页与一次性图文卡两处宿主、以及折叠块内的图一致适用。保存件是端口替身，
/// 不碰真相册。
void main() {
  const directory = downloadVideoTutorialDirectory;
  const imageKey = '$directory/shot.png';

  Finder viewer() => find.byKey(const Key('help_image_viewer'));
  Finder viewerImage() => find.byKey(const Key('help_image_viewer_image'));

  /// 文档页 + 保存件替身：正文一段 + 一张 `shot.png`。
  Future<FakeHelpImageSaver> pumpDocument(
    WidgetTester tester, {
    HelpImageSaveException? failure,
  }) async {
    final saver = FakeHelpImageSaver(failure: failure);
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文一段。\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
      overrides: [helpImageSaverProvider.overrideWithValue(saver)],
    );
    await _settleImages(tester);
    return saver;
  }

  testWidgets('文档页：长按正文缩略图，把那张资产的字节与文件名交给保存件并提示「已保存到相册」', (tester) async {
    final saver = await pumpDocument(tester);

    await tester.longPress(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(saver.names, ['shot.png'], reason: '文件名取资产文件名');
    expect(saver.bytes, [onePixelPng], reason: '字节是这张图从资产包读出的');
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(
      find.byType(PopupMenuItem<Object>),
      findsNothing,
      reason: '长按直接保存，不弹菜单',
    );
    expect(viewer(), findsNothing, reason: '长按缩略图只保存，不顺便打开查看器');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：点开查看器后长按大图，交出的字节与文件名与长按缩略图一致', (tester) async {
    final saver = await pumpDocument(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    expect(viewer(), findsOneWidget);

    await tester.longPress(viewerImage());
    await tester.pumpAndSettle();

    expect(saver.names, ['shot.png']);
    expect(saver.bytes, [onePixelPng]);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(viewer(), findsOneWidget, reason: '长按保存不关查看器');
    expect(tester.takeException(), isNull);
  });

  testWidgets('权限被拒：提示「需要相册权限才能保存」', (tester) async {
    await pumpDocument(tester, failure: const HelpImageSavePermissionDenied());

    await tester.longPress(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(find.text('需要相册权限才能保存'), findsOneWidget);
    expect(find.text('已保存到相册'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('其它失败（空间不足、格式不支持、意外）：提示「保存失败」', (tester) async {
    await pumpDocument(tester, failure: const HelpImageSaveFailed());

    await tester.longPress(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(find.text('保存失败'), findsOneWidget);
    expect(find.text('需要相册权限才能保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：折叠块内的图展开后长按也能存下，交出它自己的字节与文件名', (tester) async {
    final rewardKey = '$directory/reward.png';
    final saver = FakeHelpImageSaver();
    await pumpHelpDocumentPage(
      tester,
      markdown:
          '# 下载视频\n'
          '\n'
          '开头一段。\n'
          '\n'
          '<details>\n'
          '<summary>赞赏</summary>\n'
          '![赞赏码](reward.png)\n'
          '</details>\n',
      binary: {rewardKey: onePixelPng},
      overrides: [helpImageSaverProvider.overrideWithValue(saver)],
    );
    await _settleImages(tester);

    await tester.tap(find.text('赞赏'));
    await tester.pumpAndSettle();
    await _settleImages(tester);

    await tester.longPress(_imageWithAsset(rewardKey));
    await tester.pumpAndSettle();

    expect(saver.names, ['reward.png']);
    expect(saver.bytes, [onePixelPng]);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('一次性图文卡：卡里的缩略图长按也能存下', (tester) async {
    const coverKey = '$directory/cover.png';
    final saver = FakeHelpImageSaver();
    await pumpFirstRunHost(
      tester,
      storage: InMemoryPrivateJsonStorage(),
      helpAssets: FakeHelpAssetBundle(
        {
          onboardingCopyAssetKey: File(onboardingCopyAssetKey)
              .readAsStringSync(),
          '$directory/下载视频.md':
              '# 下载视频\n'
              '\n'
              '## 方法一\n'
              '\n'
              '把视频存下来。\n'
              '\n'
              '![步骤截图](cover.png)\n',
        },
        binary: {coverKey: onePixelPng},
      ),
      overrides: [helpImageSaverProvider.overrideWithValue(saver)],
    );
    resetFirstRunSession(tester);
    await tester.pump();

    await tester.tap(find.text(welcomeTourLabel));
    await tester.pumpAndSettle();
    await _settleImages(tester);

    await tester.longPress(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: _imageWithAsset(coverKey),
      ),
    );
    await tester.pumpAndSettle();

    expect(saver.names, ['cover.png']);
    expect(saver.bytes, [onePixelPng]);
    expect(find.text('已保存到相册'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 按资产 key 找正文里画出来的那张图。
Finder _imageWithAsset(String assetKey) => find.byWidgetPredicate(
  (widget) =>
      widget is Image && (widget.image as AssetImage).assetName == assetKey,
);

/// 图片解码是真实异步：放行真实事件循环再泵帧，图才真的按尺寸排进布局、
/// 点得着（与 `help_image_viewer_test` 同一套）。
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
