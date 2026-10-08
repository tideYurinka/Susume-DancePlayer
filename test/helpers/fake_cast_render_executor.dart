import 'dart:async';
import 'dart:io';

import 'package:dance_learning_app/cast/cast_render_executor.dart';

/// 脚本化的假渲染执行器：记录跑过的命令、可逐步报进度、可挂着不放、可注入
/// 失败或取消——渲染编排（命中不重渲、进度、可取消、不留半成品）全部经它测，
/// 不跑进程。照 `fake_cast_session.dart` / `fake_update_gateway.dart` 的既有
/// 范式。
///
/// 它还**真写产物文件**（默认写 [outputPath]）：编排器的「落定 / 清半成品」
/// 要真的在文件系统上看得出来，产物内容不重要（写一行字节）。
class FakeCastRenderExecutor implements CastRenderExecutor {
  /// 跑过的命令参数表，按顺序。
  final List<List<String>> runs = [];

  /// 每次 [run] 给的进度分母（与 [runs] 同序）。
  final List<Duration> totals = [];

  /// [run] 开始即完成的信号（编排器测试等它，避免与异步赛跑）。
  final List<Completer<void>> started = [];

  /// [run] 的结局；默认成功。
  CastRenderVerdict verdict = CastRenderVerdict.succeeded;

  /// 非 null 时 [run] 抛出它（执行器自身报错用例）。
  Object? runError;

  /// 非 null 时 [run] 挂在它上面，直到测试放行（在飞用例）。
  Completer<void>? runGate;

  /// 非 null 时 [run] 在开始处回调它（测试用来报进度或写产物）。
  void Function(CastRenderJob job, int index)? onRun;

  /// 这条脚本里的进度会在 [run] 开始后逐条报出去（分母取命令的总时长）。
  List<Duration> progressScript = const [];

  /// [cancel] 的调用次数。
  int cancelCalls = 0;

  /// 在飞时被取消：放行 [runGate] 并按 [verdictOnCancel] 收场。
  CastRenderVerdict verdictOnCancel = CastRenderVerdict.cancelled;

  /// 成功时真写一份产物到命令里的输出路径（默认写；「没写产物」用例可关掉）。
  bool writesArtifact = true;

  bool get ran => runs.isNotEmpty;

  /// 最近一条命令的参数表。
  List<String> get lastArguments => runs.last;

  /// 最近一条命令要写的产物路径（参数表最后一项）。
  String get lastOutputPath => runs.last.last;

  @override
  Future<CastRenderVerdict> run(
    CastRenderJob job, {
    void Function(CastRenderProgress progress)? onProgress,
  }) async {
    final index = runs.length;
    runs.add(job.arguments);
    totals.add(job.total);
    started.add(Completer<void>()..complete());
    onRun?.call(job, index);
    for (final rendered in progressScript) {
      onProgress?.call(
        CastRenderProgress(rendered: rendered, total: job.total),
      );
    }

    final gate = runGate;
    if (gate != null) {
      await gate.future;
    }
    final error = runError;
    if (error != null) throw error;
    if (verdict == CastRenderVerdict.succeeded && writesArtifact) {
      writeArtifact(job.arguments.last);
    }
    return verdict;
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final gate = runGate;
    if (gate != null && !gate.isCompleted) {
      verdict = verdictOnCancel;
      gate.complete();
    }
  }

  /// 假执行器真写产物：给编排器的落定/清半成品路径一个真实文件。
  static void writeArtifact(String path, {String content = 'rendered'}) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// 目录（含子目录）里的文件名（判「半成品还在不在 / 盘上还剩什么」用）。
  static List<String> fileNamesIn(String directoryPath) {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) return const [];
    return directory
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toList()
      ..sort();
  }
}
