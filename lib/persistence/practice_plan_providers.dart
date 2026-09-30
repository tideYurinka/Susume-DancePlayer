import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../annotation/learning_segment_attributes.dart';
import '../annotation/learning_segments.dart' show learningSegmentsOf;
import '../persistence/marker_document.dart';
import '../persistence/video_document_providers.dart'
    show videoDocumentStorageFactoryProvider;
import 'local_document.dart';
import 'practice_plan.dart';

/// 计划文档文件解析闭包（设备级全局私密 `practice_plan.json`）。返回解析
/// 闭包而非 Future 本身：目录解析只在真正读写时发生（与练舞统计同款，
/// 容器构建不触发 path_provider）。
final practicePlanFileProvider = Provider<Future<File> Function()>((ref) {
  return () async {
    final base = await getApplicationDocumentsDirectory();
    return File('${base.path}/practice_plan.json');
  };
});

/// 计划存取注入点（设备级全局私密文件，不进公开标记文件、不进分享包）。
final practicePlanStorageProvider = Provider<PracticePlanStorage>((ref) {
  return AtomicPracticePlanStorage(ref.watch(practicePlanFileProvider));
});

/// 到期落档补判的段档位读入口：给定 videoId，读该舞的公开标记
/// 文件与本地文档，返回全部学习段的档位集合（零段舞 = 空集，判逾期）。
/// 读不到文档 / 读失败返回 null——该舞留待下次装载，不猜。
final practicePlanMasteryResolverProvider =
    Provider<Future<Set<LearningMastery>?> Function(String videoId)>((ref) {
      final storageFor = ref.watch(videoDocumentStorageFactoryProvider);
      return (videoId) async {
        try {
          final storage = storageFor(videoId);
          final markersJson = await storage.loadMarkersOrNull();
          final markers = markersJson == null
              ? const MarkersDocument.empty()
              : MarkersDocument.fromJson(markersJson);
          final local = LocalDocument.fromJson(await storage.loadLocal());
          return {
            for (final segment in learningSegmentsOf(
              rangeStartMs: markers.rangeStartMs,
              rangeEndMs: markers.rangeEndMs,
              segmentLines: markers.segmentLines,
            ))
              learningSegmentMastery(local.mastery, segment.order),
          };
        } on Object {
          return null;
        }
      };
    });

/// 计划 store 写盘成功后的观察者（系统推送排程的取消 / 重排
/// 在装配处〔main 的 ProviderScope〕经 `planPushSyncProvider` 注册；持久
/// 层不反向依赖功能层）。
final practicePlanStoreObserversProvider =
    Provider<List<Future<void> Function()>?>((ref) => null);

/// 计划全局 store 注入点（`practice_plan.json` 的唯一读写入口）。
final Provider<PracticePlanStore> practicePlanStoreProvider =
    Provider<PracticePlanStore>((ref) {
      final observers = ref.watch(practicePlanStoreObserversProvider);
      return PracticePlanStore(
        ref.watch(practicePlanStorageProvider),
        masteryOf: ref.watch(practicePlanMasteryResolverProvider),
        onChanged: observers == null
            ? null
            : () {
                for (final observer in observers) {
                  observer();
                }
              },
      );
    });

/// 单舞 DDL 读面：写面动作完成后作废本 provider，计划区随之重读。
final dancePlanDdlProvider = FutureProvider.autoDispose
    .family<DanceDdl?, String>((ref, videoId) {
      return ref.watch(practicePlanStoreProvider).ddlOf(videoId);
    });

/// 计划文档全部条目读面（计划页）：进入计划 Tab 时由壳作废重读。
final practicePlanEntriesProvider =
    FutureProvider.autoDispose<List<DancePlanEntry>>((ref) {
      return ref.watch(practicePlanStoreProvider).entries();
    });

/// 计划事件读面：写面动作完成后作废重读。
final practicePlanEventsProvider = FutureProvider.autoDispose<List<PlanEvent>>((
  ref,
) {
  return ref.watch(practicePlanStoreProvider).events();
});

/// 单舞随舞曲库开关读面（无条目 = 开）。写面动作完成后作废重读。
final dancePlanSocialLibraryProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, videoId) {
      return ref
          .watch(practicePlanStoreProvider)
          .socialLibraryEnabledOf(videoId);
    });

/// 单舞复习提醒开关读面（无条目 = 开）。写面动作完成后作废重读。
final dancePlanReviewRemindersProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, videoId) {
      return ref
          .watch(practicePlanStoreProvider)
          .reviewRemindersEnabledOf(videoId);
    });
