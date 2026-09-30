/// 八份文档的版本链集中登记表。
///
/// 版本事实各自只在自己的文档里声明一处（`X.versionPolicy`），本表把它们
/// 集中列出，作为「哪些版本号曾被分发」的唯一可审计清单：发布门的覆盖检查
/// 与地板棘轮据此逐份核对，不必在各文档之间翻找。
library;

import 'video_index.dart';
import '../core/document_version_policy.dart';
import 'four_beat_bucket_store.dart';
import 'local_document.dart';
import 'marker_document.dart';
import 'material_manifest.dart';
import 'member_scheme_store.dart';
import 'practice_plan.dart';
import 'practice_stats.dart';

/// 文档键 → 版本链。键为稳定的文档标识（不是展示名）。
final Map<String, DocumentVersionPolicy> documentVersionPolicies = {
  'markers': MarkersDocument.versionPolicy,
  'local': LocalDocument.versionPolicy,
  'videoIndex': VideoIndex.versionPolicy,
  'practiceStats': PracticeStatsDocument.versionPolicy,
  'practicePlan': PracticePlanDocument.versionPolicy,
  'fourBeatBucket': FourBeatBucketShard.versionPolicy,
  'memberSchemes': MemberSchemesDocument.versionPolicy,
  'materialManifest': MaterialManifestDocument.versionPolicy,
};
