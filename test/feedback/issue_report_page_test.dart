import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/dance/dance_library_providers.dart';
import 'package:dance_learning_app/feedback/device_snapshot.dart';
import 'package:dance_learning_app/feedback/issue_log_package.dart';
import 'package:dance_learning_app/feedback/issue_log_sink.dart';
import 'package:dance_learning_app/feedback/issue_report_page.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/persistence/video_document_providers.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/share_channel/share_channel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/dance_snapshot_fixture.dart';
import '../helpers/device_snapshot_fixture.dart';
import '../helpers/fake_share_channel.dart';
import '../helpers/in_memory_video_document_storage.dart';
import '../helpers/issue_log_zip.dart';
import '../helpers/poll.dart';

/// 表单页接缝（接缝四，既有出站递出接口）：以 fake
/// 出站递出件断言——描述为空出提示且未递出；填了描述收到一个存在且可解压的
/// 包；递出失败只出一次失败提示。
void main() {
  late Directory tempDir;
  late FakeShareChannel channel;
  late Directory logDirectory;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('issue_report_page_test');
    channel = FakeShareChannel();
    logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);
    File('${logDirectory.path}/log.txt')
        .writeAsStringSync('2026-09-24 15:20:27.000 [节拍] 第一行\n');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    List<DanceSnapshot> dances = const [],
    Map<String, InMemoryVideoDocumentStorage> danceDocuments = const {},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          issueLogSinkProvider.overrideWithValue(
            IssueLogSink(directory: logDirectory),
          ),
          deviceSnapshotProvider.overrideWith(
            (ref) async => testDeviceSnapshot,
          ),
          shareChannelProvider.overrideWithValue(channel),
          susumeShareDirectoryProvider.overrideWith(
            (ref) async => Directory('${tempDir.path}/out'),
          ),
          danceLibrarySnapshotProvider.overrideWith(
            (ref) async => DanceLibrarySnapshot(dances: dances),
          ),
          videoDocumentStorageFactoryProvider.overrideWithValue(
            (videoId) =>
                danceDocuments[videoId] ?? InMemoryVideoDocumentStorage(),
          ),
        ],
        child: const MaterialApp(home: IssueReportPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 页面比测试视口高（问题描述与四项回答占去上半屏），先滚到目标再点，
  /// 否则 tap 会脱靶而空击。
  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(Key(key));
    await tester.pumpAndSettle();
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  Future<void> tapSend(WidgetTester tester) =>
      tapKey(tester, 'issue_report_send');

  testWidgets('问题描述为空：发送钮置灰但按得动，按下弹「先说说遇到了什么问题」且不递出', (tester) async {
    await pumpPage(tester);

    final send = tester.widget<FilledButton>(
      find.byKey(const Key('issue_report_send')),
    );
    expect(send.onPressed, isNotNull, reason: '灰着的入口按得动');

    await tapSend(tester);
    await tester.pump();

    expect(find.text('先说说遇到了什么问题'), findsOneWidget);
    expect(channel.sharedFiles, isEmpty, reason: '不满足必答就不发生递出');
    expect(channel.shareCalls, 0);
  });

  testWidgets('页面标题与帮助文档动作区的钮文案一致（同一处字面量）', (tester) async {
    await pumpPage(tester);

    expect(find.widgetWithText(AppBar, issueReportTitle), findsOneWidget);
  });

  testWidgets('四个框：标题带（必填）/（可选）在框上方，灰字引导在框里，必答那项另有红星', (tester) async {
    await pumpPage(tester);

    expect(find.text('$kIssueSectionDescription（必填）'), findsOneWidget);
    expect(find.text('$kIssueSectionReproduce（可选）'), findsOneWidget);
    expect(find.text('$kIssueSectionActual（可选）'), findsOneWidget);
    expect(find.text('$kIssueSectionExpected（可选）'), findsOneWidget);

    expect(find.text(kIssueDescriptionHint), findsOneWidget);
    expect(find.text(kIssueReproduceHint), findsOneWidget);
    expect(find.text(kIssueActualHint), findsOneWidget);
    expect(find.text(kIssueExpectedHint), findsOneWidget);
    expect(find.textContaining('可留空'), findsNothing, reason: '选填与否写在标题上，不写进灰字');

    final star = find.text('*');
    expect(star, findsOneWidget, reason: '必答标记只挂在问题描述那一项上');
    expect(
      tester.widget<Text>(star).style?.color,
      Theme.of(tester.element(star)).colorScheme.error,
      reason: '红星取主题的错误色',
    );
  });

  testWidgets('填好描述点发送：递出一个存在且可解压的问题日志包，含 issue.txt、device.json 与日志', (
    tester,
  ) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '视频加载不出来',
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '确认发送后应出包',
      );
    });
    await tester.pumpAndSettle();

    expect(channel.sharedFiles, hasLength(1));
    expect(channel.shareCalls, 1);
    final shared = channel.sharedFiles.single;
    expect(shared.existsSync(), isTrue);
    expect(shared.path, endsWith('.zip'));

    final entries = readZipEntries(shared.path);
    expect(
      entries.keys,
      containsAll(<String>['issue.txt', 'device.json', 'logs/log.txt']),
    );
    expect(utf8.decode(entries['issue.txt']!), contains('视频加载不出来'));
    expect(
      jsonDecode(utf8.decode(entries['device.json']!)),
      testDeviceSnapshot.toJson(),
    );
    expect(utf8.decode(entries['logs/log.txt']!), contains('第一行'));
  });

  testWidgets('补充回答全部留空：照常递出，issue.txt 只有问题描述一节', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '视频加载不出来',
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '四项都留空时照常出包',
      );
    });
    await tester.pumpAndSettle();

    expect(channel.sharedFiles, hasLength(1));
    final text = utf8.decode(
      readZipEntries(channel.sharedFiles.single.path)['issue.txt']!,
    );
    expect(text, '## 问题描述\n视频加载不出来');
    expect(text, isNot(contains('## 出现频率')), reason: '出现频率默认不选，不进包');
  });

  testWidgets('填了四项：issue.txt 各占一节，出现频率正文是选中的一档', (tester) async {
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '视频加载不出来',
    );
    await tester.enterText(
      find.byKey(const Key('issue_report_reproduce')),
      '打开应用就白屏',
    );
    await tester.enterText(
      find.byKey(const Key('issue_report_actual')),
      '一直转圈',
    );
    await tester.enterText(
      find.byKey(const Key('issue_report_expected')),
      '进首页',
    );
    await tester.pump();

    // 三档都在、默认不选。
    for (final label in ['每次都出现', '偶尔出现', '只出现过一次']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester
          .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
          .groupValue,
      isNull,
      reason: '出现频率默认不选',
    );

    final frequency = find.byKey(const Key('issue_report_frequency_sometimes'));
    await tester.ensureVisible(frequency);
    await tester.pump();
    await tester.tap(frequency);
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '填了四项应出包',
      );
    });
    await tester.pumpAndSettle();

    final text = utf8.decode(
      readZipEntries(channel.sharedFiles.single.path)['issue.txt']!,
    );
    expect(
      text,
      '## 问题描述\n视频加载不出来\n\n'
      '## 如何复现\n打开应用就白屏\n\n'
      '## 实际表现\n一直转圈\n\n'
      '## 期望表现\n进首页\n\n'
      '## 出现频率\n偶尔出现',
    );
  });

  testWidgets('递出失败：只出一句「日志包未递出」，不重试、不二次弹分享面板', (tester) async {
    channel.throwOnShare = Exception('no chooser');
    await pumpPage(tester);

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '视频加载不出来',
    );
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        onTick: tester.pump,
        reason: '递出失败应出声',
      );
    });
    await tester.pumpAndSettle();

    expect(find.text('日志包未递出'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget, reason: '只出一句，不二次弹面板');
    expect(channel.sharedFiles, isEmpty);
    expect(channel.shareCalls, 1, reason: '只递出一次：不重试、不二次弹分享面板');
  });

  testWidgets('舞列表覆盖全部舞、按最近打开倒序、标题署名优先显示名兜底', (tester) async {
    await pumpPage(
      tester,
      dances: [
        danceSnapshotFixture(
          videoId: 'old',
          displayName: '旧片.mp4',
          lastOpenedAt: DateTime(2026, 9, 1),
        ),
        danceSnapshotFixture(
          videoId: 'new',
          displayName: '新片.mp4',
          signature: const SongSignature(dancer: '如', song: '真值名'),
          lastOpenedAt: DateTime(2026, 9, 20),
        ),
      ],
    );

    // 署名优先：有署名取署名显示串，没有则回退显示名。
    expect(find.text('「如」真值名'), findsOneWidget);
    expect(find.text('旧片.mp4'), findsOneWidget);
    // 最近打开的排在上面。
    expect(
      tester.getTopLeft(find.byKey(const Key('issue_dance_new'))).dy,
      lessThan(tester.getTopLeft(find.byKey(const Key('issue_dance_old'))).dy),
    );
  });

  testWidgets('多选，以及顶部的「全选」与「清除」', (tester) async {
    await pumpPage(
      tester,
      dances: [
        danceSnapshotFixture(
          videoId: 'v1',
          displayName: 'a.mp4',
          lastOpenedAt: DateTime(2026, 9, 20),
        ),
        danceSnapshotFixture(
          videoId: 'v2',
          displayName: 'b.mp4',
          lastOpenedAt: DateTime(2026, 9, 10),
        ),
      ],
    );

    bool checked(String videoId) => tester
        .widget<CheckboxListTile>(find.byKey(Key('issue_dance_$videoId')))
        .value!;

    // 初始都没勾。
    expect(checked('v1'), isFalse);
    expect(checked('v2'), isFalse);

    await tapKey(tester, 'issue_dance_v1');
    await tester.pump();
    expect(checked('v1'), isTrue, reason: '点一下即勾上一支');
    expect(checked('v2'), isFalse, reason: '多选互不影响');

    await tapKey(tester, 'issue_dance_select_all');
    await tester.pump();
    expect(checked('v1'), isTrue);
    expect(checked('v2'), isTrue);

    await tapKey(tester, 'issue_dance_clear');
    await tester.pump();
    expect(checked('v1'), isFalse);
    expect(checked('v2'), isFalse);
  });

  testWidgets('舞库为空：列表区显示「舞库里还没有舞」，其余照常可发送', (tester) async {
    await pumpPage(tester);

    expect(find.text('舞库里还没有舞'), findsOneWidget);

    // 描述填好照常发送成功。
    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '没有舞的问题',
    );
    await tester.pump();
    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '舞库为空也应能出包',
      );
    });
    await tester.pumpAndSettle();
    expect(channel.sharedFiles, hasLength(1));
  });

  testWidgets('勾了舞发送：包内 dances.json 逐项对回它自己的标题与标识，没有公开标记文件的不内联空壳', (
    tester,
  ) async {
    await pumpPage(
      tester,
      dances: [
        danceSnapshotFixture(
          videoId: 'v1',
          displayName: 'a.mp4',
          lastOpenedAt: DateTime(2026, 9, 20),
        ),
        danceSnapshotFixture(
          videoId: 'v2',
          displayName: 'b.mp4',
          lastOpenedAt: DateTime(2026, 9, 10),
        ),
      ],
      danceDocuments: {
        'v1': InMemoryVideoDocumentStorage(markers: testDanceMarkers),
      },
    );

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '节拍不对',
    );
    await tapKey(tester, 'issue_dance_v2');
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '勾了舞应出包',
      );
    });
    await tester.pumpAndSettle();

    final entries = readZipEntries(channel.sharedFiles.single.path);
    final decoded =
        jsonDecode(utf8.decode(entries[kIssueDancesEntry]!)) as List;
    expect(decoded, [
      {'title': 'b.mp4', 'videoId': 'v2'},
    ]);
    expect(
      utf8.decode(entries['issue.txt']!),
      contains('b.mp4'),
      reason: 'issue.txt 末节列出附带的数据',
    );
  });

  testWidgets('勾了舞：包内该舞带公开标记文件原文', (tester) async {
    await pumpPage(
      tester,
      dances: [
        danceSnapshotFixture(
          videoId: 'v1',
          displayName: 'a.mp4',
          lastOpenedAt: DateTime(2026, 9, 20),
        ),
      ],
      danceDocuments: {
        'v1': InMemoryVideoDocumentStorage(markers: testDanceMarkers),
      },
    );

    await tester.enterText(
      find.byKey(const Key('issue_report_description')),
      '分段不对',
    );
    await tapKey(tester, 'issue_dance_v1');
    await tester.pump();

    await tester.runAsync(() async {
      await tapSend(tester);
      await pollUntil(
        () => channel.sharedFiles.isNotEmpty,
        onTick: tester.pump,
        reason: '勾了舞应出包',
      );
    });
    await tester.pumpAndSettle();

    final decoded = jsonDecode(
      utf8.decode(
        readZipEntries(channel.sharedFiles.single.path)[kIssueDancesEntry]!,
      ),
    ) as List;
    expect((decoded.single as Map)['markers'], testDanceMarkers);
  });
}
