/// 音源注册表：音源 → 速度组 → 9 槽段的清单与纯策略（选段、选速、段表
/// 压平），以及「生效音源 id」注入点。
///
/// 依赖方向：本文件 import `metronome_sound.dart`（音源设置槽）、
/// `av_sync_session.dart`（校准会话）与 `../core/current_beat.dart`（八拍号
/// 回卷）；`metronome_sound.dart` 反向 import 本文件的段表查询——同域内
/// 音声设置与音源注册表互相可见。零 import 中枢。
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/beat_grid.dart' show kBeatsPerBar, kBeatsPerEightCount;
import 'av_sync_session.dart' show avSyncCalibrationSessionProvider;
import 'metronome_sound.dart' show metronomeSoundTypeProvider;

/// 段槽位：号 1..8 整拍 + 半拍，位置即号（下标 0..7 = 号 1..8，8 = 半拍）。
enum MetronomeSegmentSlot {
  count1,
  count2,
  count3,
  count4,
  count5,
  count6,
  count7,
  count8,
  half,
}

/// 选段口径：音效类（恒按拍号）/ 按号发音类（小节首按八拍号）。
enum MetronomeSlotMode { effect, numbered }

/// 速度组：一段语速的 9 槽段（下标 = 槽位，恒 9 项）+ 组身份——该组最长
/// 音频长度（毫秒，声明值）。同音源内身份互异 ⇒ 选速无并列、无第二判据。
/// 每组恒 9 槽（号 1..8 整拍 + 半拍；与 [MetronomeSegmentSlot] 值域一致，
/// 由不变量用例钉住）。
const int kMetronomeSlotCount = 9;

class MetronomeSpeedGroup {
  const MetronomeSpeedGroup({required this.standardMs, required this.slots})
    : assert(slots.length == kMetronomeSlotCount);

  /// 组内最长音频长度（毫秒，声明值；由「声明 == 实测」不变量用例兜住）。
  final int standardMs;

  /// 9 槽段规格，下标 = [MetronomeSegmentSlot] 槽位。
  final List<SegmentSpec> slots;
}

/// 段规格：段音频资产 + 段内拍点标记（听感拍点相对段首的毫秒偏移；
/// 「段首即拍点」的短敲击采样为 0，带音头的采样为音头偏移，实测写入）。
class SegmentSpec {
  const SegmentSpec({required this.asset, required this.markerMs});

  /// 段音频资产（WAV，随包内置）。
  final String asset;

  /// 段内拍点标记（毫秒）：听感拍点相对段首偏移；由制作/测量写入，
  /// 随注册表版本化。
  final int markerMs;
}

/// 音源注册表项：一个音源 = 若干速度组、每组 9 槽段。音源▾列表、置灰
/// 待支持沿用现有项形态（available:false → 「待支持」不可选）。
class MetronomeSourceEntry {
  const MetronomeSourceEntry({
    required this.id,
    required this.label,
    required this.available,
    required this.mode,
    required this.speedGroups,
  });

  /// 音源标识（`normal` / `vocal` / `geigi`，与设置槽 soundType 存值一致）。
  final String id;

  /// 面板「音源」下拉的中文标签。
  final String label;

  /// false → 待支持置灰不可选。
  final bool available;

  /// 选段口径（数据，不是调用点分支）。
  final MetronomeSlotMode mode;

  /// 速度组（恒非空：待支持音源为 9 个空资产槽的占位组 ⇒ 选速/选段无
  /// null 分支，静默由出口闸门承担）。
  final List<MetronomeSpeedGroup> speedGroups;
}

/// 「普通」音源 id（与设置槽 soundType 存值一致）。
const String kNormalSourceId = 'normal';

/// 「普通」音源 9 槽映射：小节首号（每 [kBeatsPerBar] 拍）
/// 槽 → 重音资产、其余整拍槽 → 整拍资产、半拍槽 → 半拍资产；复用现有三段
/// 资产，不新录。重音周期与重音判定（[CalibrationSessionGrid.isAccent]）、
/// 派生网格 downbeat 周期同读 [kBeatsPerBar] 一处。
final List<SegmentSpec> _normalSlots = [
  for (var i = 0; i < kBeatsPerEightCount; i++)
    SegmentSpec(
      asset: i % kBeatsPerBar == 0
          ? 'assets/sounds/metronome_strong.wav'
          : 'assets/sounds/metronome_beat.wav',
      markerMs: 0,
    ),
  SegmentSpec(asset: 'assets/sounds/metronome_half.wav', markerMs: 0),
];

/// 待支持音源占位速度组：9 个空资产槽，standardMs 0（无实际资产）。
final List<MetronomeSpeedGroup> _placeholderSpeedGroups = [
  MetronomeSpeedGroup(
    standardMs: 0,
    slots: List.filled(
      kMetronomeSlotCount,
      const SegmentSpec(asset: '', markerMs: 0),
    ),
  ),
];

/// 音源段注册表：加音源 = 加一项（首版只铺「普通」，人声/歌姬为
/// available:false 占位）。
final List<MetronomeSourceEntry> metronomeSourceRegistry = [
  MetronomeSourceEntry(
    id: kNormalSourceId,
    label: '普通',
    available: true,
    mode: MetronomeSlotMode.effect,
    speedGroups: [MetronomeSpeedGroup(standardMs: 70, slots: _normalSlots)],
  ),
  MetronomeSourceEntry(
    id: 'vocal',
    label: '人声',
    available: false,
    mode: MetronomeSlotMode.numbered,
    speedGroups: _placeholderSpeedGroups,
  ),
  MetronomeSourceEntry(
    id: 'geigi',
    label: '歌姬',
    available: false,
    mode: MetronomeSlotMode.numbered,
    speedGroups: _placeholderSpeedGroups,
  ),
];

/// 按 id 取注册表项；未知 id（旧数据/非法存值）兜底回「普通」。
MetronomeSourceEntry metronomeSourceEntryOfId(String id) {
  return metronomeSourceRegistry.firstWhere(
    (entry) => entry.id == id,
    orElse: () => metronomeSourceRegistry.first,
  );
}

/// 节拍生效音源 id：校准会话活跃
/// 且当前音源为待支持项时，节拍发声回落「普通」；只影响会话期间发声，
/// 设置槽不写盘、退出即还原。普通音源下会话进出不触发重建（select 只订
/// 生效 id）。消费方 = 渲染器 entry（播放节拍与会话滴答同一音源 seam）。
final effectiveMetronomeSourceIdProvider = Provider<String>((ref) {
  final sourceId = ref.watch(metronomeSoundTypeProvider).name;
  final sessionActive = ref.watch(
    avSyncCalibrationSessionProvider.select((s) => s.active),
  );
  if (sessionActive && !metronomeSourceEntryOfId(sourceId).available) {
    return kNormalSourceId;
  }
  return sourceId;
});

/// 全部注册表段资产（资产清单，供宿主一次性预载；available:false 的
/// 占位段无资产，不入清单）。直接取各可用音源段表的装载清单——去重与
/// 定序（资产 + 段内拍点标记、首次出现）与段表结构性同一口径。
final List<SegmentSpec> metronomeSourceRegistryAssets = [
  for (final entry in metronomeSourceRegistry)
    if (entry.available) ...MetronomeSegmentTable.of(entry).loads,
];

/// 段表：把一个音源「速度组 × 9 槽」按（资产 + 段内拍点标记）去重压平成
/// 装载清单 + 「组序、槽 → 段 id」查表；键按首次出现定序。「普通」因此
/// 压平成三段：重音资产段、整拍段、半拍段。
class MetronomeSegmentTable {
  factory MetronomeSegmentTable.of(MetronomeSourceEntry entry) {
    final loads = <SegmentSpec>[];
    final seen = <(String, int), int>{};
    final ids = <(int, MetronomeSegmentSlot), int>{};
    for (var g = 0; g < entry.speedGroups.length; g++) {
      final slots = entry.speedGroups[g].slots;
      for (var s = 0; s < slots.length; s++) {
        final spec = slots[s];
        final id = seen.putIfAbsent((spec.asset, spec.markerMs), () {
          loads.add(spec);
          return loads.length - 1;
        });
        ids[(g, MetronomeSegmentSlot.values[s])] = id;
      }
    }
    return MetronomeSegmentTable._(loads, ids);
  }

  MetronomeSegmentTable._(this.loads, this._ids);

  /// 去重后的装载清单（按首次出现定序）。
  final List<SegmentSpec> loads;

  /// (组序, 槽位) → 段 id（[loads] 下标）。
  final Map<(int, MetronomeSegmentSlot), int> _ids;

  int idOf(int groupIndex, MetronomeSegmentSlot slot) =>
      _ids[(groupIndex, slot)]!;
}

/// 选段（唯一一份规则）：八拍号 0（前导区）按拍号；
/// 音效类恒按拍号；按号发音类在拍号 1 时按八拍号（回卷 1..8）、其余按拍
/// 号。半拍不经选段（半拍事件直接取 [MetronomeSegmentSlot.half]），回卷
/// 朝整拍，绝不落半拍槽。
MetronomeSegmentSlot selectMetronomeSlot({
  required int eightCount,
  required int beatCount,
  required MetronomeSlotMode mode,
}) {
  var number = beatCount;
  if (eightCount > 0 && mode == MetronomeSlotMode.numbered && beatCount == 1) {
    number = (eightCount - 1) % kBeatsPerEightCount + 1;
  }
  return MetronomeSegmentSlot.values[number - 1];
}

/// 选速：`standardMs ≤ 间隔` 的组里取最快一组（最小声明长度），全超则取
/// 最慢一组（最大声明长度）。间隔由调用方给（播放轴 = 网格名义一拍，会话
/// 轴 = 会话档间隔）；倍速、位置、播放态都不进这条算术。返回组序（配合
/// [MetronomeSegmentTable.idOf]）。同源内声明长度互异，无并列。
int selectMetronomeSpeedGroupIndex(
  List<MetronomeSpeedGroup> groups,
  int intervalMs,
) {
  int? best;
  for (var i = 0; i < groups.length; i++) {
    if (groups[i].standardMs > intervalMs) continue;
    if (best == null || groups[i].standardMs < groups[best].standardMs) {
      best = i;
    }
  }
  if (best != null) return best;
  var slowest = 0;
  for (var i = 1; i < groups.length; i++) {
    if (groups[i].standardMs > groups[slowest].standardMs) slowest = i;
  }
  return slowest;
}

final Map<String, MetronomeSegmentTable> _segmentTablesOfSource = {};

/// 音源的段表（按音源 id 缓存：注册表项同 id 同口径，会话拍序逐拍查表
/// 不重复压平）。
MetronomeSegmentTable _metronomeSegmentTableOf(MetronomeSourceEntry entry) =>
    _segmentTablesOfSource.putIfAbsent(
      entry.id,
      () => MetronomeSegmentTable.of(entry),
    );

/// 「音源 × 速度组 × 槽位」→ 哑段 id：会话拍序的槽位与组选择都来自同一
/// 套选段 / 选速纯策略，id 查表收在这一处。
int metronomeSegmentIdOf(
  MetronomeSourceEntry entry,
  int groupIndex,
  MetronomeSegmentSlot slot,
) => _metronomeSegmentTableOf(entry).idOf(groupIndex, slot);

/// 原生段槽容量：注册表全量音源里最坏所需段数（单份事实源——原生槽表按
/// 此容量校验，经 sink 创建参数下传，Dart 与原生不各写一份魔数；容量不足
/// 只会在 CI 的不变量用例失败，不在真机静默）。
final int kMetronomeNativeSegmentCapacity = metronomeSourceRegistry.fold(
  0,
  (worst, entry) =>
      math.max(worst, MetronomeSegmentTable.of(entry).loads.length),
);
