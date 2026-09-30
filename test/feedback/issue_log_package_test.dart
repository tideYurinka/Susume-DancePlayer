import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/feedback/issue_log_package.dart';
import 'package:dance_learning_app/feedback/issue_log_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/device_snapshot_fixture.dart';
import '../helpers/issue_log_zip.dart';

/// 问题日志包组装接缝（接缝一，纯面）：把四组输入
/// 喂给组装件，断言产出的 zip 条目与内容——不跑真机、不碰 widget。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('issue_log_package_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('包内必有 issue.txt、device.json、logs/log.txt；文件名带本地时间戳', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);
    File('${logDirectory.path}/log.txt')
        .writeAsStringSync('2026-09-24 15:20:27.000 [节拍] 第一行\n');
    File('${logDirectory.path}/log.1.txt')
        .writeAsStringSync('2026-09-24 15:19:00.000 [节拍] 旧行\n');

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '视频加载不出来',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    expect(output.path, endsWith('susume-logs-20260924-152027.zip'));
    final entries = readZipEntries(output.path);
    expect(
      entries.keys,
      containsAll(<String>['issue.txt', 'device.json', 'logs/log.txt']),
    );
    // 问题描述原文在 issue.txt 里。
    expect(utf8.decode(entries['issue.txt']!), contains('视频加载不出来'));
    // device.json 五项齐全。
    final decoded = jsonDecode(utf8.decode(entries['device.json']!));
    expect(decoded, testDeviceSnapshot.toJson());
    expect((decoded as Map).keys, hasLength(5));
    // 日志按目录原文进包，上一份存在才放。
    expect(
      utf8.decode(entries['logs/log.txt']!),
      contains('[节拍] 第一行'),
    );
    expect(
      utf8.decode(entries['logs/log.1.txt']!),
      contains('旧行'),
    );
  });

  test('只填问题描述时 issue.txt 的产出逐字相同', () async {
    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '视频加载不出来',
      device: testDeviceSnapshot,
      logDirectory: Directory('${tempDir.path}/logs')
        ..createSync(recursive: true),
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    final text = utf8.decode(readZipEntries(output.path)['issue.txt']!);
    expect(text, '## 问题描述\n视频加载不出来');
  });

  test('填了的补充回答各占一节，留空的不出现', () async {
    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '视频加载不出来',
      reproduce: '打开应用就白屏',
      device: testDeviceSnapshot,
      logDirectory: Directory('${tempDir.path}/logs')
        ..createSync(recursive: true),
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    final text = utf8.decode(readZipEntries(output.path)['issue.txt']!);
    expect(text, '## 问题描述\n视频加载不出来\n\n## 如何复现\n打开应用就白屏');
    expect(text, isNot(contains('## 实际表现')));
    expect(text, isNot(contains('## 期望表现')));
    expect(text, isNot(contains('## 出现频率')));
    expect(text, isNot(contains('\n\n\n')), reason: '留空项不留占位空行');
  });

  test('四项都填：issue.txt 按序各占一节，出现频率正文是选中的一档', () async {
    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '视频加载不出来',
      reproduce: '打开应用就白屏',
      actual: '一直转圈',
      expected: '进首页',
      frequency: '偶尔出现',
      device: testDeviceSnapshot,
      logDirectory: Directory('${tempDir.path}/logs')
        ..createSync(recursive: true),
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    final text = utf8.decode(readZipEntries(output.path)['issue.txt']!);
    expect(
      text,
      '## 问题描述\n视频加载不出来\n\n'
      '## 如何复现\n打开应用就白屏\n\n'
      '## 实际表现\n一直转圈\n\n'
      '## 期望表现\n进首页\n\n'
      '## 出现频率\n偶尔出现',
    );
  });

  test('未勾任何舞：包内没有 dances.json，issue.txt 也不写「附带的数据」节', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '偶发闪退',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    final entries = readZipEntries(output.path);
    expect(entries.containsKey(kIssueDancesEntry), isFalse);
    expect(
      utf8.decode(entries['issue.txt']!),
      isNot(contains('附带的数据')),
    );
  });

  test('勾了舞且不附标记文件：dances.json 逐项含标题与视频标识，issue.txt 末节列出两者', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '节拍不对',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
      dances: const [
        IssueDanceAttachment(title: '「如」真值名', videoId: 'v1'),
        IssueDanceAttachment(title: '第二支', videoId: 'v2'),
      ],
    );

    final entries = readZipEntries(output.path);
    final decoded = jsonDecode(utf8.decode(entries[kIssueDancesEntry]!));
    expect(decoded, [
      {'title': '「如」真值名', 'videoId': 'v1'},
      {'title': '第二支', 'videoId': 'v2'},
    ]);

    final issue = utf8.decode(entries['issue.txt']!);
    expect(issue, contains('附带的数据'));
    expect(issue, contains('「如」真值名'));
    expect(issue, contains('v1'));
    expect(issue, contains('第二支'));
    expect(issue, contains('v2'));
  });

  test('内联公开标记文件原文；每份数据对回自己的标题与标识', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '分段不对',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
      dances: const [
        IssueDanceAttachment(
          title: 'A',
          videoId: 'v1',
          markers: {
            'version': 8,
            'meta': {'mirrored': true, 'signature': {'song': '真值名'}},
          },
        ),
        // 没有公开标记文件的舞：不内联空壳。
        IssueDanceAttachment(title: 'B', videoId: 'v2'),
      ],
    );

    final decoded =
        jsonDecode(utf8.decode(readZipEntries(output.path)[kIssueDancesEntry]!))
            as List;
    expect(decoded, hasLength(2));
    expect((decoded[0] as Map)['title'], 'A');
    expect((decoded[0] as Map)['videoId'], 'v1');
    expect((decoded[0] as Map)['markers'], {
      'version': 8,
      'meta': {'mirrored': true, 'signature': {'song': '真值名'}},
    });
    expect((decoded[1] as Map)['title'], 'B');
    expect((decoded[1] as Map)['videoId'], 'v2');
    expect((decoded[1] as Map).containsKey('markers'), isFalse);
  });

  test('公开标记文件为空：不带 markers 键，不内联空壳', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '节拍不对',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
      dances: const [
        IssueDanceAttachment(title: 'A', videoId: 'v1', markers: {}),
      ],
    );

    final decoded =
        jsonDecode(utf8.decode(readZipEntries(output.path)[kIssueDancesEntry]!))
            as List;
    expect((decoded.single as Map).containsKey('markers'), isFalse);
  });

  test('没有任何日志行时 logs/ 为空、包照常产出', () async {
    final logDirectory = Directory('${tempDir.path}/logs')
      ..createSync(recursive: true);

    final output = await assembleIssueLogPackage(
      outputDir: Directory('${tempDir.path}/out'),
      description: '偶发闪退',
      device: testDeviceSnapshot,
      logDirectory: logDirectory,
      now: DateTime(2026, 9, 24, 15, 20, 27),
    );

    final entries = readZipEntries(output.path);
    expect(
      entries.keys.where((name) => name.startsWith(kIssueLogsEntryPrefix)),
      isEmpty,
      reason: '没有日志行时 logs/ 为空，不留空条目',
    );
    expect(entries.keys, containsAll(<String>['issue.txt', 'device.json']));
  });

  test('Dart 层未捕获异常经落盘件进包：logs/log.txt 里有痕迹', () async {
    final logDirectory = Directory('${tempDir.path}/logs');
    final sink = IssueLogSink(directory: logDirectory);
    final originalDebugPrint = debugPrint;
    final originalOnFlutterError = FlutterError.onError;
    final originalOnError = PlatformDispatcher.instance.onError;
    try {
      await sink.install();
      sink.installErrorHandlers();
      PlatformDispatcher.instance.onError!('偶发闪退-03', StackTrace.current);
      await sink.writesSettled;

      final output = await assembleIssueLogPackage(
        outputDir: Directory('${tempDir.path}/out'),
        description: '偶发闪退',
        device: testDeviceSnapshot,
        logDirectory: logDirectory,
        now: DateTime(2026, 9, 24, 15, 20, 27),
      );

      final entries = readZipEntries(output.path);
      expect(
        utf8.decode(entries['logs/log.txt']!),
        contains('偶发闪退-03'),
        reason: '用户报「闪退」时，包里 logs/ 看得到痕迹',
      );
    } finally {
      debugPrint = originalDebugPrint;
      FlutterError.onError = originalOnFlutterError;
      PlatformDispatcher.instance.onError = originalOnError;
    }
  });
}
