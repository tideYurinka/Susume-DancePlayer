import 'package:dance_learning_app/about/about_page.dart';
import 'package:dance_learning_app/about/contributor_intro_page.dart';
import 'package:dance_learning_app/about/contributors_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/contributor_assets_fixture.dart';
import '../helpers/contributor_pages_harness.dart';
import '../helpers/fake_help_asset_bundle.dart';

/// **贡献者名单**页的头与线：开头是与**关于页**逐位相同的**应用信息头**，其下
/// 一条横线把只读头部与名单分开——关于页没有这条线。
void main() {
  testWidgets('名单页的头部与关于页的头部逐位相同', (tester) async {
    final bundle = contributorBundle();
    await pumpContributorSurface(
      tester,
      home: const AboutPage(),
      bundle: bundle,
    );
    final aboutHeader = _headerRects(tester);

    await pumpContributorSurface(
      tester,
      home: const ContributorsPage(),
      bundle: bundle,
    );

    expect(
      _headerRects(tester),
      aboutHeader,
      reason: '同一个应用信息头，落在同一处',
    );
  });

  testWidgets('横线只出现在名单页：关于页没有这条线', (tester) async {
    final divider = find.byKey(const Key('contributors_header_divider'));
    await pumpContributorSurface(
      tester,
      home: const AboutPage(),
      bundle: contributorBundle(),
    );
    expect(divider, findsNothing, reason: '关于页不画这条横线');

    await pumpContributorSurface(
      tester,
      home: const ContributorsPage(),
      bundle: contributorBundle(),
    );
    expect(divider, findsOneWidget, reason: '名单页用它分开只读头部与名单');

    final headerBottom = tester
        .getBottomLeft(find.byKey(const Key('about_app_info_header')))
        .dy;
    final dividerTop = tester.getTopLeft(divider).dy;
    expect(
      dividerTop,
      greaterThanOrEqualTo(headerBottom),
      reason: '横线在头部之下',
    );
  });

  testWidgets('横线之下是组名「贡献者」与逐位名单：头像或占位、显示名与角色', (tester) async {
    final bundle = contributorBundle(
      records: [
        ContributorFixture('alpha', '首位', '项目发起者', avatar: 'me.webp'),
        ContributorFixture('zeta', '末位', '插画'),
      ],
      binary: {contributorAvatarAsset('alpha', 'me.webp'): onePixelPng},
    );
    await pumpContributorSurface(
      tester,
      home: const ContributorsPage(),
      bundle: bundle,
    );

    final dividerTop = tester
        .getTopLeft(find.byKey(const Key('contributors_header_divider')))
        .dy;
    expect(find.text('贡献者'), findsOneWidget, reason: '名单的组名');
    expect(
      tester.getTopLeft(find.text('贡献者')).dy,
      greaterThan(dividerTop),
      reason: '组名在横线之下',
    );

    // 逐位：显示名与角色都在，且按名单顺序排列。
    final alphaRow = find.byKey(const Key('contributor_row_alpha'));
    final zetaRow = find.byKey(const Key('contributor_row_zeta'));
    expect(find.text('首位'), findsOneWidget);
    expect(find.text('项目发起者'), findsOneWidget);
    expect(find.text('末位'), findsOneWidget);
    expect(find.text('插画'), findsOneWidget);
    expect(
      tester.getTopLeft(alphaRow).dy,
      lessThan(tester.getTopLeft(zetaRow).dy),
      reason: '按名单里的顺序排',
    );

    // 头像：盘上有那张图就画它。
    final avatar = find.descendant(
      of: alphaRow,
      matching: find.byType(Image),
    );
    expect(avatar, findsOneWidget);
    expect(
      (tester.widget<Image>(avatar).image as AssetImage).assetName,
      contributorAvatarAsset('alpha', 'me.webp'),
    );

    // 没提供头像的那位看到规整的占位件，不是空白也不是坏图。
    expect(
      find.descendant(
        of: zetaRow,
        matching: find.byKey(const Key('contributor_avatar_placeholder_zeta')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zetaRow, matching: find.byType(Image)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点名单里的一位进他的个人介绍页：顶端是他的档案头', (tester) async {
    final bundle = contributorBundle(
      records: [
        ContributorFixture('alpha', '首位', '项目发起者', avatar: 'me.webp'),
        ContributorFixture('zeta', '末位', '插画'),
      ],
      binary: {contributorAvatarAsset('alpha', 'me.webp'): onePixelPng},
    );
    await pumpContributorSurface(
      tester,
      home: const ContributorsPage(),
      bundle: bundle,
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('contributor_row_alpha')),
        matching: find.byIcon(Icons.chevron_right),
      ),
      findsOneWidget,
      reason: '每位一行，右端有进入箭头',
    );

    await tester.tap(find.byKey(const Key('contributor_row_alpha')));
    await tester.pumpAndSettle();

    expect(find.byType(ContributorIntroPage), findsOneWidget);
    final header = find.byKey(const Key('contributor_profile_header'));
    expect(header, findsOneWidget, reason: '顶端是这位贡献者的档案头');
    expect(
      find.descendant(of: header, matching: find.text('首位')),
      findsOneWidget,
      reason: '档案头写他的显示名',
    );
    expect(
      find.descendant(of: header, matching: find.text('项目发起者')),
      findsOneWidget,
      reason: '档案头写他的角色',
    );
    final avatar = find.descendant(of: header, matching: find.byType(Image));
    expect(
      (tester.widget<Image>(avatar).image as AssetImage).assetName,
      contributorAvatarAsset('alpha', 'me.webp'),
      reason: '档案头画的是他的头像',
    );
  });

  testWidgets('点没有头像的那位：档案头也画占位件，不留空白', (tester) async {
    await pumpContributorSurface(
      tester,
      home: const ContributorsPage(),
      bundle: contributorBundle(),
    );

    await tester.tap(
      find.byKey(Key('contributor_row_${sampleContributor.id}')),
    );
    await tester.pumpAndSettle();

    final header = find.byKey(const Key('contributor_profile_header'));
    expect(
      find.descendant(
        of: header,
        matching: find.byKey(
          Key('contributor_avatar_placeholder_${sampleContributor.id}'),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

/// 应用信息头上每一件的矩形：图标、应用名与一句话简介、以及整个头部。
List<double> _headerRects(WidgetTester tester) => [
  ..._rect(tester, find.byKey(const Key('about_app_info_header'))),
  ..._rect(tester, find.byKey(const Key('about_app_icon'))),
  ..._rect(tester, find.byKey(const Key('about_app_name'))),
  ..._rect(tester, find.byKey(const Key('about_app_tagline'))),
];

List<double> _rect(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  return [rect.left, rect.top, rect.right, rect.bottom];
}
