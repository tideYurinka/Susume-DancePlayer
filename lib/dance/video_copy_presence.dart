/// 视频副本存在性判定：**副本丢失**这个事实的唯一来源。
///
/// 输入一支舞的**视频副本**路径、输出它是否还在盘上——只问存在性，不看
/// 大小、不读内容（内容那头归**视频标识**）。舞库读面在清单装入时按条目
/// 记录的路径问一次，卡片标记、详情状态与打开入口都读那一处算出的结果，
/// 不各判一套。
///
/// 生产实现就是一次同步存在性查询：不做后台巡检、不加轮询；测试覆盖为
/// 内存替身（`test/helpers/fake_video_copy_presence.dart`），不碰真实文件
/// 系统。
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 副本存在性查询口（输入路径、输出是否存在）。
abstract interface class VideoCopyPresence {
  /// [path] 处的视频副本是否在场。
  bool exists(String path);
}

/// 生产实现：一次同步存在性查询。同步是刻意的——问这一句的都在构建路径上
/// （读面装配与打开入口），且 widget 测试的 fake async 时钟下异步文件 IO
/// 不可完成（与素材库删除同款先例）。
class FileVideoCopyPresence implements VideoCopyPresence {
  const FileVideoCopyPresence();

  @override
  bool exists(String path) => File(path).existsSync();
}

/// 存在性判定注入点：舞库读面与删除动作共用。
final videoCopyPresenceProvider = Provider<VideoCopyPresence>(
  (ref) => const FileVideoCopyPresence(),
);
