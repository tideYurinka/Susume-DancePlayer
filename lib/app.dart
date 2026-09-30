import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dance_learning_app/core/app_identity.dart';
import 'package:dance_learning_app/player/system_ui.dart';

import 'app_shell.dart';
import 'help/guide_host.dart';

/// App 根组件（宿主）。
///
/// Riverpod [ProviderScope] 由 main() 提供；本组件负责 Material 主题、
/// 引导演出层宿主（`builder`，唯一渲染引导的地方，包住整个 App）、两 Tab
/// 根壳，以及启动瞬间的**全局竖屏锁**——播放器以外页面的屏幕朝向由 App
/// 自己请求，系统「自动旋转」开关开着或关掉都一样。
class DanceLearningApp extends ConsumerStatefulWidget {
  const DanceLearningApp({super.key});

  @override
  ConsumerState<DanceLearningApp> createState() => _DanceLearningAppState();
}

class _DanceLearningAppState extends ConsumerState<DanceLearningApp> {
  @override
  void initState() {
    super.initState();
    // 启动即请求竖屏：在根组件首帧的构建期发出，先于任何非播放器页面渲染；
    // 平台启动窗口（引擎挂载前）不归 App 的请求管。
    unawaited(ref.read(systemUiControllerProvider).lockPortrait());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appDisplayName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      builder: (context, child) => GuideHost(child: child!),
      home: const AppShell(),
    );
  }
}
