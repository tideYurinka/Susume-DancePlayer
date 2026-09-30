import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart';
import 'speed_control.dart';
import 'speed_step.dart';
import 'speed_step_preset.dart';

/// 预设存储注入点（在私密 JSON 的 `speedStepPresets` 键下读写，后续
/// 全局私密配置并列扩键复用同一文件）。
final speedStepPresetStorageProvider = Provider<SpeedStepPresetStorage>((ref) {
  return SpeedStepPresetStore(ref.watch(privateJsonStorageProvider));
});

/// 是否在启动时自动恢复已持久化的预设（测试可关掉以隔离确定性初始态）。
final speedStepPresetAutoRestoreProvider = Provider<bool>((ref) => true);

/// 预设存储：预设列表 + 当前选中预设的「读 → 改 → 写」串行存取。
abstract interface class SpeedStepPresetStorage {
  /// 读取当前文档；缺失/损坏时兜底为出厂内置预设（[SpeedStepPresetDoc.fresh]）。
  Future<SpeedStepPresetDoc> load();

  /// 串行「读 → [mutate] → 写」。
  Future<SpeedStepPresetDoc> update(
    FutureOr<SpeedStepPresetDoc> Function(SpeedStepPresetDoc current) mutate,
  );
}

/// [SpeedStepPresetStorage] 的私密 JSON 实现。
class SpeedStepPresetStore implements SpeedStepPresetStorage {
  SpeedStepPresetStore(this._storage);

  static const _key = 'speedStepPresets';

  final PrivateJsonStorage _storage;

  @override
  Future<SpeedStepPresetDoc> load() async {
    final json = await _storage.read();
    final raw = json[_key];
    if (raw is! Map<String, dynamic>) return SpeedStepPresetDoc.fresh;
    // 损坏兜底：解析失败（含字段类型错误）/预设列表为空/选中项缺失 → 出厂。
    final SpeedStepPresetDoc doc;
    try {
      doc = SpeedStepPresetDoc.fromJson(raw);
    } on TypeError {
      return SpeedStepPresetDoc.fresh;
    }
    if (doc.presets.isEmpty ||
        doc.presets.every((p) => p.id != doc.selectedId)) {
      return SpeedStepPresetDoc.fresh;
    }
    return doc;
  }

  @override
  Future<SpeedStepPresetDoc> update(
    FutureOr<SpeedStepPresetDoc> Function(SpeedStepPresetDoc current) mutate,
  ) {
    // 串行读改写由私密 JSON 存储的 mutate 保证（同文件并发无 lost-update）；
    // 本层只做节映射（文档整体覆盖写入 `speedStepPresets` 键；同文件其它
    // 键——metronomeSettings / avSyncDelays 等——保留；原 clear+
    // addAll 会抹除后续并列扩键）。
    var result = SpeedStepPresetDoc.fresh;
    final run = _storage.mutate((json, {required bool present}) async {
      final next = await mutate(await load());
      result = next;
      json[_key] = next.toJson();
    });
    return run.then((_) => result);
  }
}

/// 步进预设模型。
///
/// 职责：
/// - 选中：应用选中预设参数到步进控制（[speedControlProvider]）；
/// - 编辑即存：编辑任意预设（名称 + 参数，[updatePreset]；内置可覆盖）；
/// - 新建/删除预设（内置与自定义均可删）、内置一键恢复默认；
/// - 跨会话持久化：内容与选中态经 [speedStepPresetStorageProvider] 落
///   设备级私密 JSON；步进启用等会话内态不归本模型持有、不落盘（本模型只在
///   选中或删除预设时驱动 [speedControlProvider] 应用参数 / 停用步进）。
class SpeedStepPresetModel extends Notifier<SpeedStepPresetDoc> {
  @override
  SpeedStepPresetDoc build() {
    restoreDone = ref.read(speedStepPresetAutoRestoreProvider)
        ? _restore()
        : Future<void>.value();
    return SpeedStepPresetDoc.fresh;
  }

  /// 启动恢复是否完成（测试等价「重启后读态」的同步点）。
  late Future<void> restoreDone;

  bool _mutated = false;

  Future<void> _restore() async {
    var disposed = false;
    ref.onDispose(() => disposed = true);
    final doc = await ref.read(speedStepPresetStorageProvider).load();
    // 恢复前用户已发生变更（启动恢复与首操作的竞态）：以用户态为准，丢弃
    // 恢复结果——用户变更随后会以完整状态落盘。
    if (disposed || _mutated) return;
    state = doc;
    // 选中预设的参数应用到步进控制（重启等价：内容与选中态一起回来）。
    await _applyToStepControl(doc);
  }

  Future<void> _applyToStepControl(SpeedStepPresetDoc doc) async {
    final selected = presetById(doc, doc.selectedId);
    if (selected == null) return;
    await ref
        .read(speedControlProvider.notifier)
        .updateStepParams(selected.params);
  }

  SpeedStepPresetStorage get _storage =>
      ref.read(speedStepPresetStorageProvider);

  /// 提交新文档：更新状态、应用选中参数到步进控制、落盘（[apply] = 是否
  /// 需要应用参数——选中预设未变时为 false 避免重复切档）。
  Future<void> _commit(SpeedStepPresetDoc next, {bool apply = true}) async {
    _mutated = true;
    state = next;
    await Future.wait([
      if (apply) _applyToStepControl(next),
      _storage.update((_) => next),
    ]);
  }

  /// 选中预设：参数应用到步进控制并持久化选中态。
  Future<void> select(String id) async {
    if (state.presets.every((p) => p.id != id)) return;
    await _commit(
      SpeedStepPresetDoc(presets: state.presets, selectedId: id),
    );
  }

  /// 编辑任意预设：就地编辑/新增后保存即存——
  /// 更新 [id] 预设的名称（[name]，非空才改）与参数（[params]，恒合法）
  /// 并落盘；选中预设未变时不改选中。内置/自定义都可编辑；内置恢复出厂由
  /// [restoreBuiltinDefault]。非法参数忽略。
  Future<void> updatePreset({
    required String id,
    String? name,
    SpeedStepParams? params,
  }) async {
    final target = presetById(state, id);
    if (target == null) return;
    final nextName = name == null || name.trim().isEmpty ? target.name : name.trim();
    final effectiveParams = params ?? target.params;
    if (!effectiveParams.isValid) return;
    await _commit(
      state.copyWith(
        presets: [
          for (final p in state.presets)
            if (p.id == id) p.copyWith(name: nextName, params: effectiveParams)
            else p,
        ],
      ),
      apply: state.selectedId == id,
    );
  }

  /// 内置预设一键恢复出厂参数；非内置 id no-op。
  Future<void> restoreBuiltinDefault(String id) async {
    final SpeedStepPreset fresh;
    try {
      fresh = builtinDefault(id);
    } on ArgumentError {
      return; // 非内置预设：不恢复。
    }
    await _commit(
      state.copyWith(
        presets: [
          for (final p in state.presets)
            if (p.id == id) p.copyWith(params: fresh.params) else p,
        ],
      ),
      apply: state.selectedId == id,
    );
  }

  /// 新建自定义预设：以当前选中预设参数为初值（或 [params]）、自动选中并
  /// 落盘。空名（留空/纯空白）兜底默认名「自定义 N」（N 避开既有同名）。
  /// [params] 供新建编辑器直接传入所选参数（省略时以当前选中预设参数为
  /// 初值）。
  Future<void> createCustom(String name, {SpeedStepParams? params}) async {
    final current = presetById(state, state.selectedId);
    final trimmed = name.trim();
    final effectiveName = trimmed.isNotEmpty
        ? trimmed
        : defaultCustomPresetName([for (final p in state.presets) p.name]);
    final effectiveParams = params?.isValid == true
        ? params!
        : (current?.params ?? const SpeedStepParams());
    final now = DateTime.now();
    var id = newCustomPresetId(now);
    for (var i = 1; state.presets.any((p) => p.id == id); i++) {
      id = '${newCustomPresetId(now)}_$i';
    }
    final preset = SpeedStepPreset(
      id: id,
      name: effectiveName,
      builtin: false,
      params: effectiveParams,
    );
    await _commit(
      SpeedStepPresetDoc(presets: [...state.presets, preset], selectedId: id),
    );
  }

  /// 删除预设（内置与自定义一律可删）；保留
  /// 「至少一个」不变量（剩余为空时拒绝）。删除选中的预设时回退选中列表首个
  /// 并应用其参数；删除正在生效（已启用）的预设时一并停用步进——不留一条
  /// 已不存在的参数继续在跑。
  Future<void> delete(String id) async {
    final target = presetById(state, id);
    if (target == null) return;
    final remaining = state.presets.where((p) => p.id != id).toList();
    if (remaining.isEmpty) return;
    final wasSelected = state.selectedId == id;
    if (wasSelected && ref.read(speedControlProvider).stepEnabled) {
      await ref.read(speedControlProvider.notifier).setStepEnabled(false);
    }
    await _commit(
      SpeedStepPresetDoc(
        presets: remaining,
        selectedId: wasSelected ? remaining.first.id : state.selectedId,
      ),
      apply: wasSelected,
    );
  }
}

/// 步进预设注入点。
final speedStepPresetProvider =
    NotifierProvider<SpeedStepPresetModel, SpeedStepPresetDoc>(
      SpeedStepPresetModel.new,
    );
