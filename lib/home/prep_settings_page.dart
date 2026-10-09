import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_render_cache.dart' show castRenderCacheProvider;
import '../persistence/prep_beats_store.dart';

/// 「详细设置」页：首页「⋯」进入，设备级设置统一入口。
/// 现含「预备拍数」一组三行（延迟播放 / 录制准备 / 循环前导），分段档位
/// 点选即落盘（`prepBeats` 键），下次触发延迟 / 按录制 / 段循环即按新值走；
/// 末尾一行「投屏缓存」显示这块缓存区的真实占用，并给一枚**要确认**的清空
/// （ADR-0005：清空入口放这里，因为这里已经是设备级设置的统一入口）。
class PrepSettingsPage extends ConsumerWidget {
  const PrepSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prep = ref.watch(prepBeatsProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('详细设置')),
      body: ListView(
        key: const Key('prep_settings_list'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Padding(
            key: const Key('prep_beats_group_header'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('预备拍数', style: theme.textTheme.titleSmall),
          ),
          _PrepTierRow(
            rowKey: 'prep_delayed_play',
            label: '延迟播放',
            tiers: kPrepBeatsTiers,
            value: prep.delayedPlay,
            onChanged: (value) =>
                ref.read(prepBeatsProvider.notifier).setDelayedPlay(value),
          ),
          _PrepTierRow(
            rowKey: 'prep_recording',
            label: '录制准备',
            tiers: kPrepBeatsTiers,
            value: prep.recording,
            onChanged: (value) =>
                ref.read(prepBeatsProvider.notifier).setRecording(value),
          ),
          _PrepTierRow(
            rowKey: 'prep_loop_lead',
            label: '循环前导',
            tiers: kLoopLeadPrepBeatsTiers,
            value: prep.loopLead,
            onChanged: (value) =>
                ref.read(prepBeatsProvider.notifier).setLoopLead(value),
          ),
          const Divider(height: 32),
          const _CastCacheRow(),
        ],
      ),
    );
  }
}

/// 清空投屏缓存的二次确认：确认返回 true；取消或点外面关掉返回 false。
/// 与删除一支舞同款「默认不删」——缓存虽可再生，删的却是用户等过的那几分钟。
Future<bool> confirmCastCacheClear(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('cast_cache_clear_dialog'),
      content: const Text('投屏副本会全部删掉；标注与设置不受影响。下次投屏要重新渲染一遍'),
      actions: [
        TextButton(
          key: const Key('cast_cache_clear_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('cast_cache_clear_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('清空'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 「投屏缓存」那一行：当前占用（真实字节）+ 一枚清空。
///
/// 占用是**问出来的**（`usageBytes`），不是页面的记忆：清空、渲染、淘汰都会
/// 改它，所以每次进页面与清空之后各问一次，显示的就是盘上此刻的样子。
class _CastCacheRow extends ConsumerStatefulWidget {
  const _CastCacheRow();

  @override
  ConsumerState<_CastCacheRow> createState() => _CastCacheRowState();
}

class _CastCacheRowState extends ConsumerState<_CastCacheRow> {
  /// 当前占用；还没问出来时是 null（显示「…」而不是一个假数）。
  int? _bytes;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    int bytes;
    try {
      bytes = await ref.read(castRenderCacheProvider).usageBytes();
    } on Object {
      // 缓存区解析不出来（比如平台目录不在）：按零占用显示，不把设置页拦下。
      bytes = 0;
    }
    if (mounted) setState(() => _bytes = bytes);
  }

  Future<void> _clear() async {
    if (!await confirmCastCacheClear(context)) return;
    try {
      await ref.read(castRenderCacheProvider).clear();
    } on Object {
      // 清空失败不弹新窗：下面重新问一次占用，那一行如实显示还剩多少。
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bytes = _bytes;
    return Padding(
      key: const Key('cast_cache_row'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('投屏缓存'),
                Text(
                  bytes == null ? '当前占用 …' : '当前占用 ${_formatSize(bytes)}',
                  key: const Key('cast_cache_usage'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('cast_cache_clear'),
            onPressed: () => unawaited(_clear()),
            child: const Text('清空'),
          ),
        ],
      ),
    );
  }
}

/// 占用显示串：字节按 1024 进制换 B / KB / MB / GB（与分享面板的包体估算
/// 同一口径）。缓存可能很小，所以 B 与 KB 也要给，不能只有 MB。
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// 一行设置：标签 + 分段档位选择（循环前导含「不前导」档）。
class _PrepTierRow extends StatelessWidget {
  const _PrepTierRow({
    required this.rowKey,
    required this.label,
    required this.tiers,
    required this.value,
    required this.onChanged,
  });

  final String rowKey;
  final String label;
  final List<int> tiers;
  final int value;
  final ValueChanged<int> onChanged;

  String _segmentLabel(int tier) => tier == 0 ? '不前导' : '$tier';

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('prep_row_$rowKey'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SegmentedButton<int>(
            key: Key('prep_segments_$rowKey'),
            segments: [
              for (final tier in tiers)
                ButtonSegment(
                  value: tier,
                  label: Text(
                    _segmentLabel(tier),
                    key: Key('prep_segment_${rowKey}_$tier'),
                  ),
                ),
            ],
            selected: {value},
            onSelectionChanged: (selection) => onChanged(selection.first),
            showSelectedIcon: false,
          ),
        ],
      ),
    );
  }
}
