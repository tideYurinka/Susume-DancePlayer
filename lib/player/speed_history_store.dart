import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart';

/// 历史倍速上限（产品需求：上限由开发方按面板实际空间决定）。
const int speedHistoryCap = 8;

/// 倍速历史（设备级，`global_private.json` 的 `speedHistory` 键）存取 seam。
///
/// 归属：跨视频通用习惯，不入 markers/
/// local；去重、最近使用在前、上限 [speedHistoryCap] 由倍速模型保证，本层
/// 只做透明的读写与损坏兜底（非 List 或元素非法 → 出厂空态，不抛错）。
abstract interface class SpeedHistoryStorage {
  /// 读取历史倍速；缺失/损坏兜底空列表。
  Future<List<double>> load();

  /// 覆盖写入历史倍速（保留同文件其它键）。
  Future<void> save(List<double> history);
}

/// [SpeedHistoryStorage] 的私密 JSON 实现。
class SpeedHistoryStore implements SpeedHistoryStorage {
  SpeedHistoryStore(this._storage);

  static const _key = 'speedHistory';

  final PrivateJsonStorage _storage;

  @override
  Future<List<double>> load() async {
    final raw = await _storage.read();
    return sanitizeSpeedHistory(raw[_key]);
  }

  @override
  Future<void> save(List<double> history) {
    return _storage.mutate((json, {required bool present}) {
      json[_key] = [...history];
    });
  }
}

/// 历史倍速净化：过滤非数值元素、转为 double、去重（保留最近在前）、
/// 截断到 [cap]。整体不是 List 时返回空列表（出厂态）。
List<double> sanitizeSpeedHistory(Object? raw, {int cap = speedHistoryCap}) {
  if (raw is! List) return const [];
  final sanitized = <double>[];
  for (final item in raw) {
    if (item is! num) continue;
    final rate = item.toDouble();
    if (sanitized.contains(rate)) continue;
    sanitized.add(rate);
    if (sanitized.length == cap) break;
  }
  return List.unmodifiable(sanitized);
}

/// 倍速历史存取注入点（测试经内存私密 JSON 覆盖）。
final speedHistoryStorageProvider = Provider<SpeedHistoryStorage>((ref) {
  return SpeedHistoryStore(ref.watch(privateJsonStorageProvider));
});

/// 是否在启动时自动恢复持久化的倍速历史（测试可关掉以隔离确定性初始态）。
final speedHistoryAutoRestoreProvider = Provider<bool>((ref) => true);
