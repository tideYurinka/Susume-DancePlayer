import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'four_beat_bucket_store.dart';

/// 每舞桶分片文件解析器（生产：应用文档目录
/// `four_beat_buckets_<videoId>.json`，与 `index.json` / `practice_stats.json`
/// 平级）。
///
/// 返回解析闭包而非 Future 本身：文件解析只在真正读写时发生，容器不持有
/// 可能失败的 Future（测试环境无 path_provider 插件时失败由存储读写的
/// 调用链静默承接，与练舞统计同款）。
final fourBeatBucketFileProvider =
    Provider<Future<File> Function(String videoId)>((ref) {
      return (videoId) async {
        final base = await getApplicationDocumentsDirectory();
        return File('${base.path}/four_beat_buckets_$videoId.json');
      };
    });

/// 每舞桶分片存取注入点（完全私密，ADR-0002：不进任何分享包、只随整机
/// 备份走）。
final fourBeatBucketStorageProvider = Provider<FourBeatBucketStorage>((ref) {
  return AtomicFourBeatBucketStorage(ref.watch(fourBeatBucketFileProvider));
});

/// 每舞桶分片 store 注入点（分片的唯一读写入口；记录器落桶、改名
/// write-through 与删舞清理共用同一实例）。
final fourBeatBucketStoreProvider = Provider<FourBeatBucketStore>((ref) {
  return FourBeatBucketStore(ref.watch(fourBeatBucketStorageProvider));
});
