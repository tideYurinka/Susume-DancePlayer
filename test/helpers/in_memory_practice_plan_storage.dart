import 'package:dance_learning_app/persistence/practice_plan.dart';

/// [PracticePlanStorage] 内存实现（与 in_memory_practice_stats_storage 同
/// 款）：真实文件 IO 在测试环境不可完成，注入本 fake 与真实实现双跑。
class InMemoryPracticePlanStorage implements PracticePlanStorage {
  Map<String, dynamic>? _json;

  /// 预置原始 JSON（直接注入缺字段 / 未知键 / 错版本内容等用例）；null =
  /// 无文件。
  set rawJson(Map<String, dynamic>? value) => _json = value;

  /// 最近一次保存的整份 JSON（null = 尚未保存过）。
  Map<String, dynamic>? get savedJson =>
      _json == null ? null : Map<String, dynamic>.of(_json!);

  /// 保存次数（断言无变化不写盘等时机用例）。
  int saveCount = 0;

  /// 置为写失败：下一次 save 抛 [saveError]。
  Object? saveError;

  @override
  Future<Map<String, dynamic>?> loadOrNull() async =>
      _json == null ? null : Map<String, dynamic>.of(_json!);

  @override
  Future<void> save(Map<String, dynamic> json) async {
    final error = saveError;
    if (error != null) throw error;
    _json = Map<String, dynamic>.of(json);
    saveCount++;
  }
}
