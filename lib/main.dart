import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'dance/dance_library_providers.dart'
    show danceLibraryRenameObserversProvider;
import 'feedback/issue_log_sink.dart';
import 'persistence/practice_plan_providers.dart';
import 'plan/system_push_provider.dart';
import 'player/segment_density_grid_wiring.dart'
    show beatGridSegmentContextWiring;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 播放内核初始化（幂等）：加载 libmpv 原生库（ADR-0001）。
  MediaKit.ensureInitialized();
  // 问题日志落盘件：在 runApp 之前接管 debugPrint
  // 单一出口，把每一行写进应用支持目录的 `logs/`，同时保留既有控制台输出。
  final issueLogSink = IssueLogSink(directory: await issueLogDirectory());
  await issueLogSink.install();
  // 崩溃与未捕获异常两处也汇入同一出口，写完即落地。
  issueLogSink.installErrorHandlers();
  runApp(
    ProviderScope(
      overrides: [
        // 计划文档每次写盘成功后同步系统推送排程：装配处把
        // 推送同步注册为 store 观察者，持久层不反向依赖功能层。
        practicePlanStoreObserversProvider.overrideWith(
          (ref) => [ref.watch(planPushSyncProvider)],
        ),
        // 改名成功后补一次推送同步：署名写路径不反向依赖
        // 功能层，装配处把它注册为舞库改名观察者。
        danceLibraryRenameObserversProvider.overrideWith(
          (ref) => [ref.watch(planPushSyncProvider)],
        ),
        issueLogSinkProvider.overrideWithValue(issueLogSink),
        // 段内倍频读面装配：逐段档与分段几何
        // 注入节拍轨展示读面端口。
        beatGridSegmentContextWiring,
      ],
      child: const DanceLearningApp(),
    ),
  );
}
