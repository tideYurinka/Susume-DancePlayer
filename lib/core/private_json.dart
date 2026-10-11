import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'atomic_json_file.dart';

/// 设备级全局私密 JSON 存取 seam（供全局私密配置复用）。
///
/// 语义定位（`lib/stats/GLOSSARY.md`「练舞统计」与 `lib/persistence/GLOSSARY.md`「本地文档」先例、字段归属）：
/// 全局、单文件、**非按视频**——与镜像的按视频索引（`persistence/video_index.dart`）
/// 与按视频标记文件相区别；内容不随任何分享/导出流出。
///
/// 接口与 `VideoIndexStorage` 同风格，方法名与 [AtomicJsonFile] 的读写面
/// 一致：读取失败（缺失/损坏）由实现兜底为空 JSON，不抛错；写入先落临时文件
/// 再原子重命名，避免读侧读到半截 JSON。
abstract interface class PrivateJsonStorage {
  /// 读取整份 JSON；文件缺失/损坏时返回空 Map（首次启动/升级兜底）。
  Future<Map<String, dynamic>> read();

  /// 整份覆盖写入。
  Future<void> write(Map<String, dynamic> json);

  /// 原子读改写（同文件并发安全）：读 → [mutate] → 写并入同一条写链
  /// 串行执行，并发调用无 lost-update。[mutate] 额外收到盘上「是否存在
  /// 且可解析」的存在位（`false` = 文件不在/损坏/顶层非对象），不被
  /// 塌缩成空对象。
  Future<void> mutate(
    FutureOr<void> Function(Map<String, dynamic> json, {required bool present})
    mutate,
  );
}

/// 设备级全局私密 JSON 的目标文件（生产：应用支持目录 `global_private.json`；
/// 测试经 [privateJsonStorageProvider] 注入内存实现，不触真实路径）。
final privateJsonFileProvider = Provider<FutureOr<File>>((ref) {
  return getApplicationSupportDirectory().then(
    (dir) => File('${dir.path}/global_private.json'),
  );
});

/// 设备级私密 JSON 存取注入点：与 [PrivateJsonStorage] 同住
/// 共享内核，播放器各域、打包侧与偏好编排共用同一注入点。
final privateJsonStorageProvider = Provider<PrivateJsonStorage>((ref) {
  return AtomicJsonFile(ref.watch(privateJsonFileProvider));
});
