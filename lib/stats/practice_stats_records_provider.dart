import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/practice_stats.dart';
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;

/// 统计页读面：装入全部会话记录（一次装入；「进页面重算」= 作废本
/// provider，不新增缓存）。存储取自持久化层的练舞统计 store。
final practiceStatsRecordsProvider =
    FutureProvider.autoDispose<List<PracticeSessionRecord>>((ref) {
  return ref.watch(practiceStatsStoreProvider).records();
});
