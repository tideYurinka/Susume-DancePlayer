import 'dart:convert';

import 'package:dance_learning_app/persistence/practice_stats.dart';

/// [PracticeStatsStorage] 内存实现：真实文件 IO 在 fake async 时钟下不可
/// 完成，测试注入本 fake（沿 in_memory_video_index_storage 先例）。
class InMemoryPracticeStatsStorage implements PracticeStatsStorage {
  Map<String, dynamic>? _json;

  /// 预置原始 JSON（直接注入损坏内容等用例）；null = 无文件。
  set rawJson(Map<String, dynamic>? value) => _json = value;

  /// 最近一次保存的整份 JSON（null = 尚未保存过）。
  Map<String, dynamic>? get savedJson => _json == null
      ? null
      : Map<String, dynamic>.of(_json!);

  /// 保存次数（断言 settle 无变化不写盘等时机用例）。
  int saveCount = 0;

  /// 置为写失败：下一次 save 抛 [saveError]。
  Object? saveError;

  @override
  Future<Map<String, dynamic>?> loadOrNull() async => _json == null
      ? null
      : Map<String, dynamic>.of(_json!);

  @override
  Future<void> save(Map<String, dynamic> json) async {
    final error = saveError;
    if (error != null) throw error;
    _json = Map<String, dynamic>.of(json);
    saveCount++;
  }

  /// 测试断言便利：按 store 的文档编码反解当前内容。
  PracticeStatsDocument get document =>
      PracticeStatsDocument.fromJson(_json ?? const {});
}

/// 与生产实现同构的 JSON 文本往返（断言编码格式用例）。
Map<String, dynamic> decodeJsonText(String text) =>
    Map<String, dynamic>.of(jsonDecode(text) as Map<String, dynamic>);
