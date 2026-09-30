import 'package:dance_learning_app/about/about_page.dart';
import 'package:dance_learning_app/about/contributor_intro_page.dart';
import 'package:dance_learning_app/about/contributors_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/contributor_assets_fixture.dart';
import '../helpers/contributor_pages_harness.dart';

/// 关于页那两行导航里「贡献者名单」这一行的落点，以及这一票交付后从头走通的
/// 那条路：关于页 →「贡献者名单」→ 名单页 → 点一位 → 个人介绍页。断言只落在
/// 屏幕上发生的事上。
void main() {
  testWidgets('按下「贡献者名单」行推入贡献者名单页', (tester) async {
    await pumpContributorSurface(
      tester,
      home: const AboutPage(),
      bundle: contributorBundle(),
    );

    await tester.tap(find.byKey(const Key('about_contributors_row')));
    await tester.pumpAndSettle();

    expect(find.byType(ContributorsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('从头走通：关于页 →「贡献者名单」→ 名单页 → 点一位 → 个人介绍页', (tester) async {
    final id = sampleContributor.id;
    await pumpContributorSurface(
      tester,
      home: const AboutPage(),
      bundle: contributorBundle(
        intros: {id: '# ${sampleContributor.displayName}\n\n他自己的介绍正文。\n'},
      ),
    );

    await tester.tap(find.byKey(const Key('about_contributors_row')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('contributor_row_$id')));
    await tester.pumpAndSettle();

    expect(find.byType(ContributorIntroPage), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('contributor_profile_header')),
        matching: find.text(sampleContributor.displayName),
      ),
      findsOneWidget,
      reason: '档案头写他的显示名',
    );
    expect(find.text('他自己的介绍正文。'), findsOneWidget, reason: '正文在他的介绍页上');
    expect(tester.takeException(), isNull);
  });
}
