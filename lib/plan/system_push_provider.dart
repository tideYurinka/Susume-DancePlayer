import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/learning_segment_attributes.dart';
import '../core/device_clock.dart';
import '../import/import_providers.dart' show videoIndexStoreProvider;
import '../persistence/practice_plan_providers.dart';
import '../persistence/song_signature.dart'
    show signatureDisplayText, songFallbackName;
import 'system_push.dart';
import 'system_push_local.dart';

/// 系统推送的 provider 接线：端口注入点（真机实现；测试用内存
/// 替身 override）、排程协调器与写后同步闭包。
final systemPushPortProvider = Provider<SystemPushPort>((ref) {
  return LocalNotificationPushPort();
});

final planPushPlannerProvider = Provider<SystemPushPlanner>((ref) {
  return SystemPushPlanner(ref.watch(systemPushPortProvider));
});

/// 完全掌握舞集合的读入口（自动规则「非完全掌握」的判定输入）：对有活跃
/// DDL 的条目逐支解析段档位——段集非空且全段最高档才算。
final planPushFullyMasteredIdsProvider =
    Provider<Future<Set<String>> Function()>((ref) {
      final store = ref.watch(practicePlanStoreProvider);
      final masteryOf = ref.watch(practicePlanMasteryResolverProvider);
      return () async {
        final entries = await store.entries();
        final mastered = <String>{};
        for (final entry in entries) {
          final ddl = entry.ddl;
          if (ddl == null || ddl.settlement != null) continue;
          try {
            final masteries = await masteryOf(entry.videoId);
            if (masteries == null) continue;
            if (masteries.isNotEmpty &&
                masteries.every(
                  (mastery) => mastery == LearningMastery.mastered,
                )) {
              mastered.add(entry.videoId);
            }
          } on Object {
            continue;
          }
        }
        return mastered;
      };
    });

/// 计划文档每次写盘成功后的推送同步（store 的 onChanged 钩子）：期望排程
/// 全集对上次同步做差分，目标清除 / 改期 / 删除与开关翻转后的取消与重排
/// 都经这一处。同步失败静默承接，不阻塞计划写入。
///
/// 显示名表在同步接线处一次读出：只读视频索引一份，用与卡片标题同一处
/// 渲染口径 `signatureDisplayText` 取署名缓存（未署名回退「文件名回落名」，
/// 即经 `songFallbackName` 去扩展名的文件名）——名字来源即索引署名缓存，
/// 故不逐支读 markers 真值、更不读整份舞库读面快照。
final Provider<Future<void> Function()> planPushSyncProvider =
    Provider<Future<void> Function()>((ref) {
      return () async {
        try {
          final store = ref.read(practicePlanStoreProvider);
          final planner = ref.read(planPushPlannerProvider);
          final index = await ref.read(videoIndexStoreProvider).load();
          await planner.sync(
            entries: await store.entries(),
            events: await store.events(),
            fullyMasteredIds: await ref.read(
              planPushFullyMasteredIdsProvider,
            )(),
            displayNames: {
              for (final entry in index.entries)
                entry.videoId: signatureDisplayText(
                  entry.signatureCache,
                  songFallbackName(entry.displayName),
                ),
            },
            now: ref.read(deviceClockProvider)(),
          );
        } on Object {
          // 排程降级为不投递，不影响计划数据。
        }
      };
    });
