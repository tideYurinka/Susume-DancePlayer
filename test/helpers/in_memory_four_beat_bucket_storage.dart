import 'package:dance_learning_app/persistence/four_beat_bucket_store.dart';

/// [FourBeatBucketStorage] 内存实现（每舞一份分片；真实文件 IO 在 fake
/// async 时钟下不可完成，测试注入本 fake——沿 in_memory_practice_stats_storage
/// 先例）。
class InMemoryFourBeatBucketStorage implements FourBeatBucketStorage {
  final Map<String, Map<String, dynamic>> _files = {};

  /// 预置某舞的原始 JSON（注入损坏内容等用例）。
  void setRaw(String videoId, Map<String, dynamic>? json) {
    if (json == null) {
      _files.remove(videoId);
    } else {
      _files[videoId] = Map<String, dynamic>.of(json);
    }
  }

  /// 某舞最近一次保存的整份 JSON（null = 尚未保存过）。
  Map<String, dynamic>? savedJsonFor(String videoId) {
    final json = _files[videoId];
    return json == null ? null : Map<String, dynamic>.of(json);
  }

  /// 保存次数（断言无变化不写盘等时机用例）。
  int saveCount = 0;

  @override
  Future<Map<String, dynamic>?> loadOrNull(String videoId) async {
    final json = _files[videoId];
    return json == null ? null : Map<String, dynamic>.of(json);
  }

  @override
  Future<void> save(String videoId, Map<String, dynamic> json) async {
    _files[videoId] = Map<String, dynamic>.of(json);
    saveCount++;
  }

  @override
  Future<void> delete(String videoId) async {
    _files.remove(videoId);
  }
}
