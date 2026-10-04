/// 基准键：设备事实的落点——两项平台基准合成的
/// **基准键**住设备级私密文件（`global_private.json` 顶层布尔键，与既有设备级
/// 镜像默认键 `practiceMirrorDefault` 同文件同形状），供画面方向表读取。
///
/// - **不可随舞覆盖**：随舞覆盖只作用于练习镜像（`practice_mirror.dart` 的
///   local `prefs.practiceMirror`）；本键住设备级文件，与任何一支舞的 local
///   私密文件无关。
/// - **判断链与兜底**：键读得到就用它（真机判据 / 人工覆盖优先于推导）；键
///   读不到（缺失/损坏）则**判定一次并记住**——直接读相机引擎的 producer 标志，
///   读不到按机型规则推导，判不出兜底为**镜像**，判定结果落进本键。
/// - **不阻塞启动**：存储读取/写入失败都不抛给调用方——读失败 = 尚未落定
///   （取值落回判定链），写失败 = 会话态已生效、仅未落盘。
/// - **人工覆盖**：没有设置界面——覆盖按
///   `docs/basis-key-manual-override.md` 的说明直接改设备级文件后重启应用，
///   或由将来的设置界面调用 [SurfaceBasisKeyModel.set]；两条路径写同一个键。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera_capture/platform_preview_basis.dart' show platformSaveBasis;
import '../camera_capture/platform_preview_basis_providers.dart'
    show platformPreviewBasisAdapterProvider;
import '../core/private_json.dart';
import '../surface_direction/surface_direction.dart';

/// 设备级全局私密文件里「基准键」的顶层键（与既有设备级镜像默认键
/// `practiceMirrorDefault` 同文件同形状的并列扩键）。
const String kSurfaceBasisKeyKey = 'surfaceBasisKey';

/// 基准键的设备级私密键存取。
///
/// 形状与既有设备级镜像默认键一致：顶层**布尔**键，`true` = 镜像、
/// `false` = 原相。键缺失、文件缺失或键值类型损坏（非 bool）都算**读不到**
/// （null）——不抛错，由画面方向表落回平台事实判定链。
class SurfaceBasisKeyStore {
  SurfaceBasisKeyStore(this._storage);

  final PrivateJsonStorage _storage;

  /// 读取基准键；读不到返回 null。
  Future<FaceDirection?> load() async {
    final json = await _storage.read();
    return _decode(json[kSurfaceBasisKeyKey]);
  }

  /// 写入基准键（null = 清除，恢复默认）；同文件其它键保留。
  Future<void> save(FaceDirection? value) =>
      _storage.mutate((json, {required bool present}) {
        if (value == null) {
          json.remove(kSurfaceBasisKeyKey);
        } else {
          json[kSurfaceBasisKeyKey] = value.isMirrored;
        }
      });
}

/// 顶层布尔键的取值口径：true = 镜像、false = 原相；其余（含缺失）= 读不到。
FaceDirection? _decode(Object? raw) => switch (raw) {
  true => FaceDirection.mirrored,
  false => FaceDirection.original,
  _ => null,
};

/// 基准键存取注入点（设备级私密文件，与设备级镜像默认键同源）。
final surfaceBasisKeyStoreProvider = Provider<SurfaceBasisKeyStore>(
  (ref) => SurfaceBasisKeyStore(ref.watch(privateJsonStorageProvider)),
);

/// 基准键的会话态与落盘：启动恢复（键读得到就用它）+ **判定一次并记住**
/// （键读不到时按判定链判定并写入设备级键）+ 变更即写入。
///
/// 会话态初值 = null（尚未落定）——恢复、判定与写入都不阻塞启动/交互。
class SurfaceBasisKeyModel extends Notifier<FaceDirection?> {
  bool _disposed = false;
  bool _mutated = false;
  Future<void> _flush = Future<void>.value();
  Future<void> _restoreDone = Future<void>.value();

  /// 启动恢复完成（含「键读不到 ⇒ 判定一次并写入」那一步；测试同步点）。
  Future<void> get restoreDone => _restoreDone;

  @override
  FaceDirection? build() {
    _disposed = false;
    _mutated = false;
    ref.onDispose(() => _disposed = true);
    _restoreDone = _restore();
    return null;
  }

  Future<void> _restore() async {
    final FaceDirection? stored;
    try {
      stored = await ref.read(surfaceBasisKeyStoreProvider).load();
    } on Object {
      // 存储不可读：维持「尚未落定」，取值落回平台事实判定链。
      return;
    }
    // 恢复前用户已改动（竞态）：以用户态为准，不拿存储盖回。
    if (_disposed || _mutated) return;
    if (stored != null) {
      state = stored;
      return;
    }
    // 键读不到（缺失/损坏）：**判定一次并记住**——判定链与画面方向表同一处
    // （producer 标志 → 机型规则 → 兜底镜像），结果落进设备级键，下次启动直接
    // 读它（推导值只作新机型初值）。
    final determined = SurfaceBaselines(
      platformPreviewBasis: ref
          .read(platformPreviewBasisAdapterProvider)
          .resolve(),
      platformSaveBasis: platformSaveBasis,
    ).basisKey;
    if (_disposed || _mutated) return;
    state = determined;
    await _persist(determined);
  }

  /// 写入基准键（**人工覆盖入口**——最坏情况下的救回手段）或清除（null =
  /// 恢复默认）。先落会话态（当场生效）再落盘；写失败不回滚会话态、不抛出。
  Future<void> set(FaceDirection? value) async {
    _mutated = true;
    state = value;
    await _persist(value);
  }

  /// 串行落盘（同一次会话内的多次写入按序；写失败不阻塞、不抛出）。
  Future<void> _persist(FaceDirection? value) {
    _flush = _flush.then((_) async {
      try {
        await ref.read(surfaceBasisKeyStoreProvider).save(value);
      } on Object {
        // 写失败不阻塞：会话态已生效，仅未落盘。
      }
    });
    return _flush;
  }
}

/// 基准键注入点。
final surfaceBasisKeyProvider =
    NotifierProvider<SurfaceBasisKeyModel, FaceDirection?>(
      SurfaceBasisKeyModel.new,
    );

/// 设备事实的**当前取值**（画面方向基线项）：设备级基准键读得到就按它落定
/// 两项平台事实（已落定的真机判据 / 人工覆盖优先于推导）；读不到（键缺失或
/// 损坏）按平台事实判定链——producer 标志 → 机型规则 → 兜底镜像。
final liveSurfaceBaselinesProvider = Provider<SurfaceBaselines>(
  (ref) => SurfaceBaselines(
    platformPreviewBasis: ref
        .watch(platformPreviewBasisAdapterProvider)
        .resolve(deviceBasisKey: ref.watch(surfaceBasisKeyProvider)),
    platformSaveBasis: platformSaveBasis,
  ),
);
