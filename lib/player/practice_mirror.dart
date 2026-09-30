import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart' show privateJsonStorageProvider;

/// 练习侧镜像：两层开关
/// ——设备级默认开（照镜子）+ 随该支舞覆盖记忆；显示层生效值 = 覆盖 ??
/// 设备级默认。作用于**练习半区当前显示的那一路画面**（显示层翻转）——
/// 该路画面的方向与施加的缩放两路都读画面方向库（装配点见
/// `player_page.dart` 的 `_practiceFaceDirection`），本文件只余**真值**：
/// 练习镜像是练习侧唯一的用户自由选择，两条练习路径共用这一个值，方向换算
/// 不再有第二处。**录像文件本身不改写**，镜像只是显示层。
///
/// 设备级值并列扩键进既有的设备级全局私密文件（`global_private.json` 顶层
/// `practiceMirrorDefault` 键，实施决定）；损坏/缺失兜底默认
/// 开。随舞覆盖的真值在 local 私密文件 `prefs` 段 `practiceMirror`（null =
/// 未覆盖），由 `VideoSettingsPersistence` 恢复与落盘，本层只持会话态。

/// 设备级全局私密文件里「练习侧镜像默认开」的顶层键。
const String kPracticeMirrorDefaultKey = 'practiceMirrorDefault';

/// 设备级默认开（`global_private.json` 并列扩键）：启动恢复 + 缺失/损坏
/// 兜底默认开（先例 = metronome_settings_store.dart 的「启动恢复 +
/// 变更即落盘」骨架；无写 UI 入口，只读）。
class PracticeMirrorDefaultModel extends Notifier<bool> {
  bool _disposed = false;
  Future<void> _restoreDone = Future<void>.value();

  /// 启动恢复完成（测试同步点）。
  Future<void> get restoreDone => _restoreDone;

  @override
  bool build() {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    _restoreDone = () async {
      try {
        final json = await ref.read(privateJsonStorageProvider).read();
        final raw = json[kPracticeMirrorDefaultKey];
        if (_disposed || raw is! bool) return;
        state = raw;
      } on Object {
        // 存储不可读：维持默认会话态（默认开）。
      }
    }();
    return true;
  }
}

/// 设备级默认注入点。
final practiceMirrorDeviceDefaultProvider =
    NotifierProvider<PracticeMirrorDefaultModel, bool>(
      PracticeMirrorDefaultModel.new,
    );

/// 随舞覆盖（会话态）：null = 该舞未覆盖（生效值用设备级默认）。真值在
/// local `prefs` 段，恢复与落盘归 `VideoSettingsPersistence`。
class PracticeMirrorOverrideModel extends Notifier<bool?> {
  @override
  bool? build() => null;

  /// 设置/清除覆盖（null 清除）。
  void set(bool? value) => state = value;
}

/// 随舞覆盖注入点。
final practiceMirrorOverrideProvider =
    NotifierProvider<PracticeMirrorOverrideModel, bool?>(
      PracticeMirrorOverrideModel.new,
    );

/// 显示层生效值（唯一读取口）：覆盖缺省即用设备级值。
final effectivePracticeMirrorProvider = Provider<bool>((ref) {
  final override = ref.watch(practiceMirrorOverrideProvider);
  return override ?? ref.watch(practiceMirrorDeviceDefaultProvider);
});
