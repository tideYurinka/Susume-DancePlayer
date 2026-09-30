/// 练舞统计存取与全局 store 的注入点：设备全局私密文件
/// `practice_stats.json` 的目标文件解析与唯一读写入口——舞库、统计页与
/// 打包三条线各自向下依赖本层。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'practice_stats.dart';

/// 练舞统计存取注入点（设备全局私密文件，永不进 markers/local）。
///
/// 目标文件解析（原 `practiceStatsFileProvider`；零外部消费者，内联进唯一
/// 读处）：生产 = 应用文档目录 `practice_stats.json`，与 `index.json` 平级；
/// 测试覆盖为临时文件。解析闭包而非 Future 本身：文件解析只在真正读写时
/// 发生，容器不持有可能失败的 Future（测试环境无 path_provider 插件时失败
/// 由存储读写的调用链静默承接，不以 unhandled async error 冒泡）。
final practiceStatsStorageProvider = Provider<PracticeStatsStorage>((ref) {
  return AtomicPracticeStatsStorage(() async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/practice_stats.json');
  });
});

/// 练舞统计全局 store 注入点（`practice_stats.json` 的唯一读写入口；
/// 打开统计页与改名写-through 共用同一实例）。
final practiceStatsStoreProvider = Provider<PracticeStatsStore>((ref) {
  return PracticeStatsStore(ref.watch(practiceStatsStorageProvider));
});
