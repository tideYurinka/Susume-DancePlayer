import 'dart:io';

import 'package:dance_learning_app/feedback/issue_log_sink.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 日志落盘件接缝（接缝二）：装到临时目录，直接调
/// [debugPrint]，只断言落盘文本与滚动结果——不测内部缓冲结构、不钉字节
/// 时间戳。
void main() {
  late Directory tempDir;
  late DebugPrintCallback original;
  late FlutterExceptionHandler? originalOnError;
  late bool Function(Object, StackTrace)? originalPlatformOnError;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('issue_log_sink_test');
    original = debugPrint;
    originalOnError = FlutterError.onError;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
  });

  tearDown(() async {
    debugPrint = original;
    FlutterError.onError = originalOnError;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  IssueLogSink sink({int maxBytes = kIssueLogMaxBytes}) => IssueLogSink(
        directory: Directory('${tempDir.path}/logs'),
        maxBytes: maxBytes,
      );

  test('接管 debugPrint：一行一条、以本地时间前缀开头、原消息（含 tag）原样保留', () async {
    final log = sink();
    await log.install();

    debugPrint('[节拍] 第 3 拍');
    await log.flush();

    final lines =
        File('${tempDir.path}/logs/log.txt').readAsLinesSync();
    expect(lines, hasLength(1));
    expect(
      lines.single,
      matches(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} \[节拍\] 第 3 拍$'),
      ),
      reason: '本地时间前缀 + 原消息；tag 是原消息的一部分，不另存字段',
    );
  });

  test('写满 1MB 上限即滚动为两份且只保留两份：log.txt 当前、log.1.txt 上一份', () async {
    // 每行字节数固定的短上限：两行装得下、第三行触发滚动。
    final log = sink(maxBytes: 80);
    await log.install();

    for (var i = 0; i < 12; i++) {
      debugPrint('第 ${i.toString().padLeft(2, '0')} 行');
    }
    await log.flush();

    final files = (Directory('${tempDir.path}/logs')
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .toList())
      ..sort();
    expect(files, ['log.1.txt', 'log.txt'], reason: '只留两份，不多不少');

    final previous = File('${tempDir.path}/logs/log.1.txt').readAsStringSync();
    final current = File('${tempDir.path}/logs/log.txt').readAsStringSync();
    expect(current, contains('第 11 行'), reason: '当前份接着写');
    expect(previous, isNot(contains('第 00 行')), reason: '更早的被覆盖，只有两份');
    expect(previous, contains('第 08 行'));
  });

  test('消息自带换行时逐行前缀：续行也以本地时间前缀开头', () async {
    final log = sink();
    await log.install();

    debugPrint('第一行\n第二行');
    await log.flush();

    final lines = File('${tempDir.path}/logs/log.txt').readAsLinesSync();
    expect(lines, hasLength(2));
    final prefix = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ');
    expect(lines[0], matches(prefix));
    expect(lines[0], endsWith('第一行'));
    expect(lines[1], matches(prefix), reason: '续行也有前缀，不留无前缀行');
    expect(lines[1], endsWith('第二行'));
  });

  test('flush 后盘上内容与写入一致', () async {
    final log = sink();
    await log.install();

    debugPrint('第一行');

    await log.flush();
    expect(
      File('${tempDir.path}/logs/log.txt').readAsStringSync(),
      contains('第一行'),
    );
  });

  test('FlutterError.onError 汇入落盘件：写完立即落地，不等批量 flush', () async {
    final log = sink();
    await log.install();
    final forwarded = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      forwarded.add(details);
      previous?.call(details);
    };
    FlutterError.resetErrorCount();

    log.installErrorHandlers();
    FlutterError.onError!(FlutterErrorDetails(exception: '闪退标记-01'));

    // 只等异常路径自己排的落地，不再手动 flush：缓冲里的普通行不算落地。
    await log.writesSettled;

    expect(forwarded, hasLength(1), reason: '既有呈现站照旧收到');
    final lines = File('${tempDir.path}/logs/log.txt').readAsLinesSync();
    expect(
      lines,
      anyElement(contains('闪退标记-01')),
      reason: '异常经既有 debugPrint 单一出口落盘',
    );
    final prefix = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ');
    expect(lines.every(prefix.hasMatch), isTrue, reason: '格式与普通日志行一致');
  });

  test('PlatformDispatcher.onError 汇入落盘件：写完立即落地并转发既有处理器', () async {
    final log = sink();
    await log.install();
    final forwarded = <Object>[];
    PlatformDispatcher.instance.onError = (error, stack) {
      forwarded.add(error);
      return true;
    };

    log.installErrorHandlers();
    final handled = PlatformDispatcher.instance.onError!(
      '未捕获异常-02',
      StackTrace.current,
    );

    await log.writesSettled;

    expect(handled, isTrue, reason: '异常已汇入落盘件，视为已处理');
    expect(forwarded, ['未捕获异常-02'], reason: '既有处理器照旧收到');
    final lines = File('${tempDir.path}/logs/log.txt').readAsLinesSync();
    expect(lines, anyElement(contains('未捕获异常-02')), reason: '原文进盘');
    expect(lines, anyElement(contains('#0')), reason: '堆栈也进盘');
    final prefix = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ');
    expect(lines.every(prefix.hasMatch), isTrue, reason: '格式与普通日志行一致');
  });
}
