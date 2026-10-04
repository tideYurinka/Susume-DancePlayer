import 'dart:io';

import 'package:flutter/material.dart';

import '../dance/dance_library.dart';
import '../player/player_page.dart';
import '../player/scheme_open.dart';
import 'dance_recovery_page.dart';

/// 打开一支舞的唯一入口：先读舞库读面带出的**副本丢失**事实。
///
/// 副本在场 → 播放页（续播位置、镜像、方案参数照旧由播放器侧接手）；
/// 副本丢失 → 找回面——今天它一路进播放页、最后报一句「视频打开失败」，那是
/// 播放页在替读面判断丢失，不是它该管的事。
///
/// 首页卡片与舞详情页都经这一条路进入，判定因此只有一处：读面在清单装入时
/// 按条目路径问一次存在性（见 `dance/video_copy_presence.dart`），页面不自己
/// 再看文件、不各判一套。
Future<void> openDance(
  BuildContext context,
  DanceSnapshot dance, {
  SchemeOpen scheme = const AutoSchemeOpen(),
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => dance.copyMissing
          ? DanceRecoveryPage(dance: dance)
          : PlayerPage(source: File(dance.entry.filePath).uri, scheme: scheme),
    ),
  );
}
