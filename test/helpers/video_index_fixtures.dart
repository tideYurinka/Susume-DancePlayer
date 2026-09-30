import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';

/// 构造「已按历史应用镜像」场景的索引种子条目：文件路径与播放器
/// source 匹配、[mirrorAsked] = true（已询问过，打开时按历史应用而非
/// 弹询问）。
///
/// 供既有 player 测试（PlayerPage 镜像接线后需要读索引）与镜像 widget
/// 测试的「再次打开」场景共用，避免各处内联重复条目。
VideoIndexEntry historyEntry({
  required String filePath,
  required bool mirrored,
  String videoId = 'seeded',
  String displayName = 'a.mp4',
  int sizeBytes = 1,
  DateTime? lastOpenedAt,
}) {
  return VideoIndexEntry(
    videoId: videoId,
    displayName: displayName,
    filePath: filePath,
    sizeBytes: sizeBytes,
    fastKey: fastKeyFor(name: displayName, sizeBytes: sizeBytes),
    mirrored: mirrored,
    mirrorAsked: true,
    lastOpenedAt: lastOpenedAt ?? DateTime(2026, 9, 1),
  );
}
