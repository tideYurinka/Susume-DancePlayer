/// 问题日志落盘件：接管 Flutter 的
/// [debugPrint] 单一出口，把每一行写进应用支持目录下的 `logs/`，同时保留
/// 既有控制台输出（真机 logcat 照旧）。既有诊断站点一处不改，也不新开
/// 第二套日志机制。
///
/// 行格式 = 本地时间前缀 `yyyy-MM-dd HH:mm:ss.SSS` + 原消息（tag 是原消息
/// 的一部分，原样保留）。滚动 = `log.txt` 是当前、`log.1.txt` 是上一份，
/// 单文件满 [kIssueLogMaxBytes] 即把当前改名覆盖上一份、只保留两份。
/// 写入先在内存里缓冲、批量 flush；异常路径写完强制 flush——崩溃前的
/// 最后一段必须落地（[IssueLogSink.installErrorHandlers]）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 日志目录名（应用支持目录下）。
const String kIssueLogDirectoryName = 'logs';

const String kIssueLogCurrentFileName = 'log.txt';

const String kIssueLogPreviousFileName = 'log.1.txt';

/// 单文件上限：1 MB。写满即滚动。
const int kIssueLogMaxBytes = 1024 * 1024;

/// 缓冲达到该字节数即自动 flush（批量落盘摊平每条输出的开销）。
const int kIssueLogFlushThresholdBytes = 8 * 1024;

/// 两位补零（时间戳与包名的时间戳共用一处口径）。
String twoDigit(int value) => value.toString().padLeft(2, '0');

/// 本地时间前缀 `yyyy-MM-dd HH:mm:ss.SSS`。
String formatIssueLogTimestamp(DateTime time) {
  final millis = time.millisecond.toString().padLeft(3, '0');
  return '${time.year.toString().padLeft(4, '0')}-${twoDigit(time.month)}-'
      '${twoDigit(time.day)} ${twoDigit(time.hour)}:${twoDigit(time.minute)}:'
      '${twoDigit(time.second)}.$millis';
}

/// 问题日志落盘件。装配：`await install()` 接管 [debugPrint]；退出前
/// `await flush()` 保证缓冲落地。
class IssueLogSink {
  IssueLogSink({
    required this.directory,
    this.maxBytes = kIssueLogMaxBytes,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// 日志目录（应用支持目录下的 `logs/`）。
  final Directory directory;

  /// 单文件上限（测试注入小值以免写满 1 MB）。
  final int maxBytes;

  final DateTime Function() _clock;
  final List<String> _pending = [];
  int _pendingBytes = 0;
  int _currentBytes = 0;
  bool _installed = false;
  bool _errorHandlersInstalled = false;
  Future<void> _writes = Future<void>.value();

  File get currentFile =>
      File(p.join(directory.path, kIssueLogCurrentFileName));

  File get previousFile =>
      File(p.join(directory.path, kIssueLogPreviousFileName));

  /// 已排入的写盘全部落地的信号。崩溃与未捕获异常路径写完即强制落地，
  /// 调用方（含测试）等它即可确认最后一段已经落盘，不必再补一次 [flush]。
  Future<void> get writesSettled => _writes;

  /// 接管 [debugPrint]：既有输出经 [debugPrint] 原实现照旧（logcat 不变），
  /// 同时把这一行排进缓冲。
  Future<void> install() async {
    if (_installed) return;
    await directory.create(recursive: true);
    _currentBytes = await currentFile.exists() ? await currentFile.length() : 0;
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      _record(message);
    };
    _installed = true;
  }

  /// 把 [FlutterError.onError] 与 [PlatformDispatcher.instance.onError] 两处
  /// 汇入本落盘件，写完强制 [flush]——崩溃前的最后一段必须落地，不等缓冲的
  /// 批量阈值。两处各自转发已经装着的处理器，不静默丢掉别人接的线；重复调用
  /// 是空操作（与 [install] 同一口径）。
  ///
  /// 提示的正文仍由既有呈现站经 [debugPrint] 单一出口产生，这里是加一层
  /// 「转发 + 强制落地」；[PlatformDispatcher] 一侧没有默认呈现站，故把异常
  /// 与堆栈交给同一出口。只覆盖 Dart 层，原生崩溃的 tombstone 不在应用可及
  /// 范围。
  ///
  /// 需先 [install]：转发依赖 [debugPrint] 已被接管。
  void installErrorHandlers() {
    if (_errorHandlersInstalled) return;
    _errorHandlersInstalled = true;
    final previousOnError = FlutterError.onError;
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    FlutterError.onError = (details) {
      try {
        if (previousOnError != null) {
          previousOnError(details);
        } else {
          debugPrint(details.exceptionAsString());
        }
      } finally {
        unawaited(flush());
      }
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('$error');
      debugPrint('$stack');
      unawaited(flush());
      return previousPlatformOnError?.call(error, stack) ?? true;
    };
  }

  /// 把一行加本地时间前缀后排进缓冲，缓冲满即自动落地。消息自带换行时逐行
  /// 前缀——每条落盘行都以时间前缀开头，不出现无前缀的续行。
  void _record(String? message) {
    final lines = const LineSplitter().convert(message ?? '');
    for (final text in lines.isEmpty ? const [''] : lines) {
      final line = '${formatIssueLogTimestamp(_clock())} $text';
      _pending.add(line);
      _pendingBytes += utf8.encode('$line\n').length;
    }
    if (_pendingBytes >= kIssueLogFlushThresholdBytes) {
      unawaited(flush());
    }
  }

  /// 把缓冲里的行落到盘上；写满上限即滚动。串行化，并发调用不交叉写。
  Future<void> flush() {
    final next = _writes.then((_) => _flushPending());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _flushPending() async {
    if (_pending.isEmpty) return;
    final lines = List<String>.of(_pending);
    _pending.clear();
    _pendingBytes = 0;

    final buffer = StringBuffer();
    Future<void> drain() async {
      if (buffer.isEmpty) return;
      await currentFile.writeAsString(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
      buffer.clear();
    }

    for (final line in lines) {
      final bytes = utf8.encode('$line\n');
      if (_currentBytes > 0 && _currentBytes + bytes.length > maxBytes) {
        await drain();
        await _rotate();
      }
      buffer.write('$line\n');
      _currentBytes += bytes.length;
    }
    await drain();
  }

  Future<void> _rotate() async {
    if (await previousFile.exists()) await previousFile.delete();
    if (await currentFile.exists()) await currentFile.rename(previousFile.path);
    _currentBytes = 0;
  }
}

/// 日志目录（应用支持目录下 `logs/`）。装配落盘件与读日志目录的调用方
/// 共用一处，不各拼一份路径。
Future<Directory> issueLogDirectory() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, kIssueLogDirectoryName));
}

/// 落盘件注入点：真实装配在 `main()` 启动时创建并 `install()`，测试覆写
/// 注入临时目录的落盘件。
final issueLogSinkProvider = Provider<IssueLogSink>(
  (ref) => throw UnimplementedError('问题日志落盘件由 main() 在 runApp 前装配'),
);
