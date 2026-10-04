import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../persistence/prep_beats_store.dart';

/// 「详细设置」页：首页「⋯」进入，设备级设置统一入口。
/// 现含「预备拍数」一组三行（延迟播放 / 录制准备 / 循环前导），分段档位
/// 点选即落盘（`prepBeats` 键），下次触发延迟 / 按录制 / 段循环即按新值走。
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
        ],
      ),
    );
  }
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
