import 'package:dance_learning_app/persistence/member_scheme_store.dart';

/// 内存组员方案存取（widget/编排测试注入，不触真实文件 IO）。
class InMemoryMemberSchemeStorage implements MemberSchemeStorage {
  InMemoryMemberSchemeStorage([Map<String, dynamic>? initial])
    : _json = initial ?? {};

  Map<String, dynamic> _json;
  int saveCalls = 0;
  int deleteCalls = 0;

  /// 当前整份 JSON（断言落盘内容用）。
  Map<String, dynamic> get json => _json;

  @override
  Future<Map<String, dynamic>> load() async => _json;

  @override
  Future<void> save(Map<String, dynamic> json) async {
    saveCalls++;
    _json = json;
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
    _json = {};
  }
}
