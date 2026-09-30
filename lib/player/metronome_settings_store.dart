import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart';

/// 节拍器设备级设置（`global_private.json` 的 `metronomeSettings`
/// 键）存取 seam。
///
/// 归属：节拍器动画类型 / 声音类型 / 半拍开关为
/// 设备级（跨视频通用），与倍速历史/步进预设同文件并列扩键；字段值由消费方
/// （各设置槽模型）编解码，本层只做透明读写与损坏兜底。前导拍数为 per-video
/// （local），不归本层。
///
/// 损坏兜底（先例 = [SpeedHistoryStore]/倍速历史）：`metronomeSettings` 整体
/// 不是 Map 时兜底空设置（出厂态），不抛错。
abstract interface class MetronomeSettingsStorage {
  /// 读取节拍器设置；缺失/损坏兜底空 Map（出厂态）。
  Future<Map<String, dynamic>> load();

  /// 原子「读 → [mutate] → 写」节拍器设置（保留同文件其它键）。
  Future<void> update(
    FutureOr<void> Function(Map<String, dynamic> settings) mutate,
  );
}

/// [MetronomeSettingsStorage] 的私密 JSON 实现。
class MetronomeSettingsStore implements MetronomeSettingsStorage {
  MetronomeSettingsStore(this._storage);

  static const _key = 'metronomeSettings';

  final PrivateJsonStorage _storage;

  @override
  Future<Map<String, dynamic>> load() async =>
      sanitizeMetronomeSettings((await _storage.read())[_key]);

  @override
  Future<void> update(
    FutureOr<void> Function(Map<String, dynamic> settings) mutate,
  ) {
    return _storage.mutate((json, {required bool present}) async {
      final settings = Map<String, dynamic>.of(
        sanitizeMetronomeSettings(json[_key]),
      );
      await mutate(settings);
      json[_key] = settings;
    });
  }
}

/// 节拍器设置净化：整体不是 Map → 出厂空态；是 Map → 浅拷贝（字段级非法值
/// 由各消费方的解码函数兜底默认）。
Map<String, dynamic> sanitizeMetronomeSettings(Object? raw) {
  if (raw is! Map) return const {};
  return Map<String, dynamic>.from(raw);
}

/// 节拍器设置存取注入点（测试经内存私密 JSON 覆盖）。
final metronomeSettingsStorageProvider = Provider<MetronomeSettingsStorage>((
  ref,
) {
  return MetronomeSettingsStore(ref.watch(privateJsonStorageProvider));
});

/// 是否在模型构建时自动恢复持久化的节拍器设置（测试可关掉以隔离确定性
/// 初始态）。
final metronomeSettingsAutoRestoreProvider = Provider<bool>((ref) => true);

/// 设备级节拍器设置槽基类：「启动恢复 + 变更即落盘」的
/// 通用 Notifier 骨架；子类只给出 字段名 / 编解码 / 默认值。
abstract class PersistedSettingModel<T> extends Notifier<T> {
  late final MetronomeSettingSync<T> _sync = MetronomeSettingSync<T>(
    ref,
    field: settingField,
    decode: decode,
    encode: encode,
  );

  /// `metronomeSettings` 下的字段名。
  String get settingField;

  /// 字段解码：缺失/非法返回 null（恢复时以会话默认为准）。
  T? Function(Object? raw) get decode;

  Object? Function(T value) get encode;

  /// 出厂默认值。
  T get defaultValue;

  @override
  T build() {
    _sync.restore((value) {
      if (!ref.mounted) return;
      state = value;
    });
    return defaultValue;
  }

  /// 启动恢复完成（测试「重启后读态」的同步点）。
  Future<void> get restoreDone => _sync.restoreDone;

  /// 最近一次落盘写入完成（测试同步点）。
  Future<void> get flushDone => _sync.flushDone;

  void set(T value) {
    if (!ref.mounted || value == state) return;
    state = value;
    _sync.persist(value);
  }
}

/// 单字段设备级设置的「启动恢复 + 变更即落盘」同步（先例 = 倍速历史
/// `SpeedControlModel._restoreHistory/_persistHistory`；字段编解码由使用方
/// 给出，本类不认识具体枚举）。
class MetronomeSettingSync<T> {
  MetronomeSettingSync(
    this._ref, {
    required this.field,
    required this.decode,
    required this.encode,
  });

  final Ref _ref;

  /// `metronomeSettings` 下的字段名。
  final String field;

  final T? Function(Object? raw) decode;
  final Object? Function(T value) encode;

  bool _mutated = false;
  Future<void> _flush = Future<void>.value();
  Future<void> _restoreDone = Future<void>.value();

  /// 启动恢复是否完成（测试「重启后读态」的同步点）。
  Future<void> get restoreDone => _restoreDone;

  /// 最近一次落盘写入完成（测试同步点）。
  Future<void> get flushDone => _flush;

  /// 启动恢复：读设备级设置并经 [apply] 写回会话态；恢复前用户已改动
  /// （竞态）或字段缺失/非法时以会话态为准；存储不可用维持默认会话态。
  void restore(void Function(T value) apply) {
    if (!_ref.read(metronomeSettingsAutoRestoreProvider)) return;
    var disposed = false;
    _ref.onDispose(() => disposed = true);
    _restoreDone = () async {
      try {
        final settings = await _ref
            .read(metronomeSettingsStorageProvider)
            .load();
        final value = decode(settings[field]);
        if (disposed || _mutated || value == null) return;
        apply(value);
      } on Object {
        // 存储不可读：维持默认会话态。
      }
    }();
  }

  /// 变更落盘（写失败不抛到 UI：设置留在会话内）。
  void persist(T value) {
    _mutated = true;
    _flush = _flush.then((_) async {
      try {
        await _ref
            .read(metronomeSettingsStorageProvider)
            .update((settings) {
              settings[field] = encode(value);
            });
      } on Object {
        // 写失败不抛到 UI。
      }
    });
  }
}
