import 'dart:io';

import 'package:dance_learning_app/help/help_documents.dart'
    show onboardingCopyAssetKey;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_help_asset_bundle.dart';
import '../helpers/first_run_harness.dart';
import '../helpers/guide_copy_fixture.dart';
import '../helpers/help_assets_fixture.dart';
import '../helpers/help_document_harness.dart';
import '../helpers/in_memory_private_json_storage.dart';

/// 帮助正文的图片全屏查看：三处宿主共用同一个渲染件，单击任何一张
/// 已被渲染的图弹出全屏查看器——黑底、图按原比例居中不裁切、可缩放拖动；点查看
/// 器里任意位置、点右上角关闭钮、按系统返回三路都关得掉；顶部显示 alt，没有 alt
/// 就不显示这一行；缺图照旧不出图、没有可点区域。
void main() {
  const directory = downloadVideoTutorialDirectory;
  const imageKey = '$directory/shot.png';

  Finder viewer() => find.byKey(const Key('help_image_viewer'));
  Finder viewerImage() => find.byKey(const Key('help_image_viewer_image'));

  testWidgets('文档页：单击正文里的图弹出全屏查看器，黑底、图按原比例居中不裁切', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文一段。\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    expect(viewer(), findsNothing, reason: '没点之前不出现查看器');

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(viewer(), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(viewer());
    expect(scaffold.backgroundColor, Colors.black, reason: '查看器黑底');
    final image = tester.widget<Image>(viewerImage());
    expect(image.fit, BoxFit.contain, reason: '按原比例完整显示，不裁切');
    expect(
      (image.image as AssetImage).assetName,
      imageKey,
      reason: '全屏看的就是正文里那张同目录资产',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：查看器可双指缩放与拖动', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);
    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    final before = tester.getRect(viewerImage()).width;
    final center = tester.getCenter(viewerImage());
    final first = await tester.startGesture(center - const Offset(40, 0));
    final second = await tester.startGesture(center + const Offset(40, 0));
    await first.moveTo(center - const Offset(200, 0));
    await second.moveTo(center + const Offset(200, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();

    expect(
      tester.getRect(viewerImage()).width,
      greaterThan(before),
      reason: '双指张开放大图',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：点查看器里任意位置都关掉——点图与点黑边一个样', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    await tester.tap(viewerImage());
    await tester.pumpAndSettle();
    expect(viewer(), findsNothing, reason: '点图关掉');

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    // 左下角是黑边（标题行在上、关闭钮在右上），点它同样关掉。
    final size = tester.getSize(viewer());
    await tester.tapAt(Offset(10, size.height - 10));
    await tester.pumpAndSettle();
    expect(viewer(), findsNothing, reason: '点黑边也关掉');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：右上角关闭钮关掉查看器，回到正文原处', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文一段。\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help_image_viewer_close')));
    await tester.pumpAndSettle();

    expect(viewer(), findsNothing);
    expect(find.text('正文一段。'), findsOneWidget, reason: '回到正文原处');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：按系统返回关掉查看器', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    expect(viewer(), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(viewer(), findsNothing);
    expect(find.text('下载视频'), findsOneWidget, reason: '回到文档页');
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：顶部显示该图的 alt 文字；没有 alt 时不显示标题行', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: viewer(),
        matching: find.byKey(const Key('help_image_viewer_title')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: viewer(), matching: find.text('步骤截图')),
      findsOneWidget,
      reason: '标题写这张图的 alt',
    );
  });

  testWidgets('文档页：图没有 alt 时查看器不显示标题行', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(viewer(), findsOneWidget);
    expect(
      find.byKey(const Key('help_image_viewer_title')),
      findsNothing,
      reason: '没有 alt 就没有标题行',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：缺图不渲染、没有可点区域，点了也不出查看器', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n正文一段。\n\n![缺图](missing.png)\n',
    );

    expect(find.byType(Image), findsNothing);
    await tester.tap(find.text('正文一段。'));
    await tester.pumpAndSettle();
    expect(viewer(), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：查看器里不常驻任何按钮、不显示「长按可保存」提示', (tester) async {
    await pumpHelpDocumentPage(
      tester,
      markdown: '# 下载视频\n\n![步骤截图](shot.png)\n',
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    // 除右上角关闭钮外没有任何可点控件。
    expect(
      find.descendant(of: viewer(), matching: find.byType(TextButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: viewer(), matching: find.byType(FilledButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: viewer(), matching: find.byType(IconButton)),
      findsOneWidget,
      reason: '只有那枚关闭钮',
    );
    expect(find.textContaining('长按'), findsNothing);
    expect(find.textContaining('保存'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('文档页：折叠块内的图展开后可点开；点任意位置与关闭钮都关掉回到正文', (tester) async {
    final imageKey = '$directory/reward.png';
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
      binary: {imageKey: onePixelPng},
    );
    await _settleImages(tester);

    await tester.tap(find.text('赞赏'));
    await tester.pumpAndSettle();
    await _settleImages(tester);

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();

    expect(viewer(), findsOneWidget);
    expect(
      find.descendant(of: viewer(), matching: find.text('赞赏码')),
      findsOneWidget,
      reason: '折叠块里的图也带 alt 标题',
    );

    await tester.tap(viewerImage());
    await tester.pumpAndSettle();
    expect(viewer(), findsNothing, reason: '点查看器里任意位置关掉');
    expect(find.text('开头一段。'), findsOneWidget, reason: '回到正文原处');

    await tester.tap(_imageWithAsset(imageKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help_image_viewer_close')));
    await tester.pumpAndSettle();
    expect(viewer(), findsNothing, reason: '关闭钮关掉');
    expect(find.text('开头一段。'), findsOneWidget, reason: '回到正文原处');
    expect(tester.takeException(), isNull);
  });

  testWidgets('一次性图文卡：卡里点图打开查看器盖在卡之上；关掉回到那张卡、卡未被消耗', (tester) async {
    const coverKey = '$directory/cover.png';
    final storage = InMemoryPrivateJsonStorage();
    await _pumpFirstRunCard(
      tester,
      storage: storage,
      tutorialMarkdown:
          '# 下载视频\n'
          '\n'
          '把视频存下来。\n'
          '\n'
          '## 方法一\n'
          '\n'
          '一段够长的说明，让卡撑到宽度上限。一段够长的说明，让卡撑到宽度上限。\n'
          '\n'
          '![步骤截图](cover.png)\n'
          '\n'
          '## 方法二\n'
          '\n'
          '后面的方法。\n',
      images: {coverKey: onePixelPng},
    );
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: _imageWithAsset(coverKey),
      ),
    );
    await tester.pumpAndSettle();

    // 查看器走根 Navigator 推入通路：卡随「当前表面」机制收起，查看器在屏上。
    expect(viewer(), findsOneWidget);
    expect(
      find.byKey(const Key('guide_one_shot')),
      findsNothing,
      reason: '查看器盖在卡之上，卡收起',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(viewer(), findsNothing);
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(find.text('等会儿再下载'), findsOneWidget);
    expect(find.text('已经存好了'), findsOneWidget);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['firstRun'],
      isNull,
      reason: '看图不消耗这一步，仍等那两个出口按钮',
    );

    // 再开一次：走关闭钮关掉，同样回到那张卡。
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('guide_one_shot')),
        matching: _imageWithAsset(coverKey),
      ),
    );
    await tester.pumpAndSettle();
    expect(viewer(), findsOneWidget);
    await tester.tap(find.byKey(const Key('help_image_viewer_close')));
    await tester.pumpAndSettle();

    expect(viewer(), findsNothing);
    expect(find.byKey(const Key('guide_one_shot')), findsOneWidget);
    expect(
      (storage.snapshot['onboarding'] as Map?)?['firstRun'],
      isNull,
      reason: '两次看图都不消耗这一步',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('从卡里点图打开查看器：卡里那张缩略图本身仍是铺满卡内宽度的图', (tester) async {
    const coverKey = '$directory/cover.png';
    await _pumpFirstRunCard(
      tester,
      storage: InMemoryPrivateJsonStorage(),
      tutorialMarkdown:
          '# 下载视频\n'
          '\n'
          '把视频存下来。\n'
          '\n'
          '## 方法一\n'
          '\n'
          '一段够长的说明，让卡撑到宽度上限。一段够长的说明，让卡撑到宽度上限。\n'
          '\n'
          '![步骤截图](cover.png)\n'
          '\n'
          '## 方法二\n'
          '\n'
          '后面的方法。\n',
      images: {coverKey: onePixelPng},
    );

    final image = find.descendant(
      of: find.byKey(const Key('guide_one_shot')),
      matching: _imageWithAsset(coverKey),
    );
    expect(tester.getSize(image).width, 320.0 - 40, reason: '缩略图照旧铺满卡内宽度');
    expect(tester.takeException(), isNull);
  });
}

/// 按资产 key 找正文里画出来的那张图。
Finder _imageWithAsset(String assetKey) => find.byWidgetPredicate(
  (widget) =>
      widget is Image && (widget.image as AssetImage).assetName == assetKey,
);

/// 走首启到「下载视频」一次性图文卡（与 `help_fold_block_test` 同一套装配）：
/// 教程正文换成 [tutorialMarkdown]，图片资产补进假资产包。
Future<void> _pumpFirstRunCard(
  WidgetTester tester, {
  required InMemoryPrivateJsonStorage storage,
  required String tutorialMarkdown,
  Map<String, Uint8List> images = const {},
}) async {
  await pumpFirstRunHost(
    tester,
    storage: storage,
    helpAssets: FakeHelpAssetBundle(
      {
        onboardingCopyAssetKey: File(onboardingCopyAssetKey).readAsStringSync(),
        '$downloadVideoTutorialDirectory/下载视频.md': tutorialMarkdown,
      },
      binary: {
        '$downloadVideoTutorialDirectory/reward.png': onePixelPng,
        ...images,
      },
    ),
  );
  resetFirstRunSession(tester);
  await tester.pump();

  await tester.tap(find.text(welcomeTourLabel));
  await tester.pumpAndSettle();
  await _settleImages(tester);
}

/// 图片解码是真实异步：放行真实事件循环再泵帧，图才真的按尺寸排进布局、
/// 点得着。
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
}
