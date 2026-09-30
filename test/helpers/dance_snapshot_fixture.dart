import 'package:dance_learning_app/core/cover_frame.dart'
    show kCoverPlaceholderAspectRatio;
import 'package:dance_learning_app/dance/dance_library.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';

/// 表单页测试共用的一份公开标记文件原文（节拍网格等结构此处不关心，只要
/// 有确定内容即可断言内联）。
const Map<String, dynamic> testDanceMarkers = {
  'version': 8,
  'meta': <String, dynamic>{'mirrored': true},
};

/// 表单页测试用的一支舞读面快照：只关心列表要用的三样——标题（署名优先、
/// 显示名兜底）、视频标识与最近打开时间；其余读面量按空态兜底。
DanceSnapshot danceSnapshotFixture({
  required String videoId,
  required String displayName,
  SongSignature? signature,
  required DateTime lastOpenedAt,
  int importOrder = 0,
}) => DanceSnapshot(
  entry: VideoIndexEntry(
    videoId: videoId,
    displayName: displayName,
    filePath: '/videos/$videoId.mp4',
    sizeBytes: 1,
    fastKey: 'fast-$videoId',
    mirrored: false,
    lastOpenedAt: lastOpenedAt,
  ),
  importOrder: importOrder,
  signature: signature,
  masteryPercent: null,
  fullyMastered: false,
  practiceTotal: Duration.zero,
  lastPracticedAt: null,
  averagePracticeCount: null,
  segments: const [],
  coverPosition: Duration.zero,
  coverReady: false,
  coverAspectRatio: kCoverPlaceholderAspectRatio,
  urgency: null,
);
