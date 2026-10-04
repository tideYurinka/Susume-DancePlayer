import 'dart:io';

import 'package:dance_learning_app/dance/video_copy_presence.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 视频副本存在性判定直测：输入副本路径、输出是否在场。生产实现只是一次
/// 同步存在性查询——不看大小、不读内容（内容那头归视频标识）。
void main() {
  test('副本在盘上：判为在场', () {
    final directory = Directory.systemTemp.createTempSync('copy_presence');
    addTearDown(() => directory.deleteSync(recursive: true));
    final copy = File(p.join(directory.path, 'v1.mp4'))
      ..writeAsStringSync('video-bytes');

    expect(const FileVideoCopyPresence().exists(copy.path), isTrue);
  });

  test('副本不在（恢复了一份不带媒体的整机备份）：判为丢失', () {
    final directory = Directory.systemTemp.createTempSync('copy_presence');
    addTearDown(() => directory.deleteSync(recursive: true));

    expect(
      const FileVideoCopyPresence().exists(p.join(directory.path, 'gone.mp4')),
      isFalse,
    );
  });
}
