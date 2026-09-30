import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'av_sync.dart';
import '../core/beat_grid.dart';
import 'av_sync_session.dart';
import 'calibration_session_grid.dart'
    show CalibrationSessionBpmTier, CalibrationSessionGrid;
import '../beat_track_state/beat_track_state.dart' show beatGridProvider;
import 'speed_bubble.dart' show SpeedBubbleMode, speedBubbleSessionProvider;
import 'visual_tokens.dart';
import '../help/content_registry.dart'
    show avSyncDelayColumnAnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor;

/// 音画同步锚定气泡内容：挂在共享锚定气泡互斥会话
/// （[SpeedBubbleMode.avSync]）下——挂载即进入**校准会话**
/// （[AvSyncCalibrationSessionModel]：进入暂停播放、卸载即取消还原）。
/// 内容纵向顺序 = 当前输出设备名（+ 设备切换提示）+ **8 格拍点刻度带**
/// （闪亮钉在会话网格、重音每 4 拍）+ BPM 快选（歌曲节拍 / 120 / 160，
/// 无已对齐网格歌曲档禁用、默认 120）+ 延迟滑条（±1000 线性、10ms 档）
/// + −/＋ 细调 + 带符号读数 + 重置（0）+ 应用/取消（滑条下方提交门）。
///
/// 刻度带闪亮与滴答同拍（会话模块每次会话拍决策一处点火视觉脉冲、经
/// 渲染器 seam 下发滴答）：看+听同台；滑条/细调只改会话试听值
/// （零写盘、自下一拍被听到）；「应用」才写当前设备键并收泡，取消同。
class AvSyncBubbleContent extends ConsumerStatefulWidget {
  const AvSyncBubbleContent({super.key});

  @override
  ConsumerState<AvSyncBubbleContent> createState() =>
      _AvSyncBubbleContentState();
}

class _AvSyncBubbleContentState extends ConsumerState<AvSyncBubbleContent> {
  AvSyncCalibrationSessionModel? _session;

  /// 只进入一次：后续 inherited 依赖变化（didChangeDependencies 重入）
  /// 不再重新 enter（避免应用/取消退出后被误拉回会话）。
  bool _enterRequested = false;

  /// 设备切换短暂提示（显示数秒后自动隐去；展示态 UI 本地，模型不管）。
  static const _noticeDuration = Duration(seconds: 3);
  Timer? _noticeTimer;
  String? _visibleNotice;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enterRequested) return;
    _enterRequested = true;
    _session ??= ref.read(avSyncCalibrationSessionProvider.notifier);
    final session = _session;
    if (session != null) {
      unawaited(session.enter());
    }
  }

  @override
  void dispose() {
    // 卸载（关闭气泡 / 互斥切其它工具）= 取消：丢弃试听值并还原播放。
    _noticeTimer?.cancel();
    unawaited(_session?.cancel());
    _session = null;
    super.dispose();
  }

  /// 应用：写当前设备键并退出会话，随后收泡（气泡壳互斥会话关闭）。
  void _applyAndClose() {
    unawaited(ref.read(avSyncCalibrationSessionProvider.notifier).apply());
    ref.read(speedBubbleSessionProvider.notifier).close();
  }

  /// 取消：丢弃试听值退出会话，随后收泡。
  void _cancelAndClose() {
    unawaited(ref.read(avSyncCalibrationSessionProvider.notifier).cancel());
    ref.read(speedBubbleSessionProvider.notifier).close();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(avSyncCalibrationSessionProvider);
    final deviceLabel = ref.watch(
      avSyncProvider.select((state) => state.deviceLabel),
    );
    ref.listen(
      avSyncCalibrationSessionProvider.select((state) => state.notice),
      (previous, next) {
        if (next == null) return;
        _noticeTimer?.cancel();
        setState(() => _visibleNotice = next);
        _noticeTimer = Timer(_noticeDuration, () {
          if (mounted) setState(() => _visibleNotice = null);
        });
      },
    );
    return Column(
      key: const Key('av_sync_bubble'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 当前输出设备名（类型·产品名 /「其它设备」），白 70 小字。
        Text(
          deviceLabel,
          key: const Key('av_sync_device'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
        // 设备切换短暂提示。
        if (_visibleNotice != null)
          Text(
            _visibleNotice!,
            key: const Key('av_sync_device_notice'),
            style: TextStyle(color: kHighlightAmber, fontSize: 10),
          ),
        // 8 格拍点刻度带 + BPM 快选：会话脉冲（闪亮与滴答同一时刻表）。
        const _AvSyncSessionPulse(),
        // 延迟滑条：±1000 线性、10ms 步进档位（与细调单步一致）；
        // 只改会话试听值（不写盘、不应用引擎）。
        Slider(
          key: const Key('av_sync_slider'),
          value: session.trialMs.toDouble(),
          min: kAvSyncMinMs.toDouble(),
          max: kAvSyncMaxMs.toDouble(),
          divisions: (kAvSyncMaxMs - kAvSyncMinMs) ~/ kAvSyncStepMs,
          onChanged: (value) => ref
              .read(avSyncCalibrationSessionProvider.notifier)
              .setTrialMs(value.round()),
        ),
        // 含 ＋/－ 的那一行（次序：− 读数 ＋ … 重置）：本单元唯一一步的
        // 引导锚点包住整行（＋ 与 − 中间夹着读数）。
        GuideAnchor(
          anchorKey: avSyncDelayColumnAnchorKey,
          child: Row(
            key: const Key('av_sync_readout_row'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _AvSyncStepButton(
                buttonKey: const Key('av_sync_minus'),
                icon: Icons.remove,
                label: '音画同步减一档',
                onStep: () => ref
                    .read(avSyncCalibrationSessionProvider.notifier)
                    .stepBy(-kAvSyncStepMs),
              ),
              // 读数（带符号 ms）。
              Text(
                _signedMsLabel(session.trialMs),
                key: const Key('av_sync_readout'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              _AvSyncStepButton(
                buttonKey: const Key('av_sync_plus'),
                icon: Icons.add,
                label: '音画同步加一档',
                onStep: () => ref
                    .read(avSyncCalibrationSessionProvider.notifier)
                    .stepBy(kAvSyncStepMs),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: const Key('av_sync_reset'),
                onPressed: () => ref
                    .read(avSyncCalibrationSessionProvider.notifier)
                    .reset(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: const Text('重置', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 应用/取消（提交门）。
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              key: const Key('av_sync_apply'),
              onPressed: _applyAndClose,
              child: const Text('应用'),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('av_sync_cancel'),
              onPressed: _cancelAndClose,
              child: const Text('取消'),
            ),
          ],
        ),
      ],
    );
  }
}

/// 带符号读数：正 = 「+N ms」（声音晚到补偿）、0 = 「0 ms」。
String _signedMsLabel(int ms) => ms > 0 ? '+$ms ms' : '$ms ms';

/// 会话脉冲区：8 格拍点刻度带 + BPM 快选（纯渲染视图，气泡瘦身）。
///
/// 不自持会话逻辑：刻度带订阅会话模块的视觉脉冲出口（节拍音频深模块
/// 每产出一条会话拍指令经页面接线点火一次，与发声同一拍点时刻表、同一
/// 拍序）推进闪亮（重音每 4 拍，不随补偿值滑移）；重启记号
/// （进入 / 设备切换）变化即高亮归零。BPM 快选读/写会话状态档位（深
/// 模块会话拍序按当拍读取档间隔，变更自下一拍生效）；歌曲档可用性实时
/// 读既有网格纯函数。
class _AvSyncSessionPulse extends ConsumerStatefulWidget {
  const _AvSyncSessionPulse();

  @override
  ConsumerState<_AvSyncSessionPulse> createState() =>
      _AvSyncSessionPulseState();
}

class _AvSyncSessionPulseState extends ConsumerState<_AvSyncSessionPulse> {
  /// 自（重）启起已收到的会话拍脉冲数（高亮 = %8）。
  int _beats = 0;
  bool _started = false;
  StreamSubscription<void>? _pulseSubscription;

  /// 会话模块（哑适配器转发目标 / 视觉脉冲出口源 / 档位意图口）。
  AvSyncCalibrationSessionModel get _session =>
      ref.read(avSyncCalibrationSessionProvider.notifier);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _pulseSubscription = _session.beatPulse.listen((_) {
      if (!mounted) return;
      setState(() => _beats++);
    });
    _restart();
  }

  @override
  void dispose() {
    unawaited(_pulseSubscription?.cancel());
    _pulseSubscription = null;
    super.dispose();
  }

  /// 整体重启（会话进入 / 设备切换）：刻度带高亮归零——会话逻辑零参与。
  void _restart() {
    setState(() => _beats = 0);
  }

  void _selectTier(CalibrationSessionBpmTier tier) {
    _session.setTier(tier);
    // 不重启：深模块会话拍序按当拍读取档位，变更自下一拍生效。
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      avSyncCalibrationSessionProvider.select((state) => state.restartToken),
      (previous, next) => _restart(),
    );
    // 节拍轨三态变化（已对齐网格就绪/失效）即重建可用性（歌曲档禁用/
    // 启用）；已启动的节拍表不重启。可用性读派生格谓词（watch 网格即随
    // 三态重建）。
    final grid = ref.watch(beatGridProvider);
    final tier = ref.watch(avSyncCalibrationSessionProvider.select(
      (state) => state.tier,
    ));
    // 歌曲档可用性：视图实时读既有会话网格纯函数（真实拍点不可用置灰，
    // 严格读法与 [av_sync_session.dart] `_songGrid` 同一谓词）。
    final songAvailable = CalibrationSessionGrid.isTierAvailable(
      CalibrationSessionBpmTier.song,
      grid.hasRealBeats ? grid : null,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 窄屏取舍：以压缩格距/格宽
        // 适配（等比下缩几何，仅刻度带；字号与控件不缩放）。
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _AvSyncBeatBand(beats: _beats),
        ),
        const SizedBox(height: 4),
        Row(
          key: const Key('av_sync_bpm'),
          mainAxisSize: MainAxisSize.min,
          children: [
            _AvSyncTierButton(
              buttonKey: const Key('av_sync_bpm_song'),
              label: '歌曲节拍',
              selected: tier == CalibrationSessionBpmTier.song,
              enabled: songAvailable,
              onPressed: () => _selectTier(CalibrationSessionBpmTier.song),
            ),
            _AvSyncTierButton(
              buttonKey: const Key('av_sync_bpm_120'),
              label: '120',
              selected: tier == CalibrationSessionBpmTier.bpm120,
              onPressed: () => _selectTier(CalibrationSessionBpmTier.bpm120),
            ),
            _AvSyncTierButton(
              buttonKey: const Key('av_sync_bpm_160'),
              label: '160',
              selected: tier == CalibrationSessionBpmTier.bpm160,
              onPressed: () => _selectTier(CalibrationSessionBpmTier.bpm160),
            ),
          ],
        ),
      ],
    );
  }
}

/// 8 格拍点刻度带：[beats] = 自会话（重）启已产出拍数（0 = 首拍尚未
/// 到点、无格亮）；当前格高亮（琥珀），重音格（每 4 拍）格身更宽。
class _AvSyncBeatBand extends StatelessWidget {
  const _AvSyncBeatBand({required this.beats});

  final int beats;

  @override
  Widget build(BuildContext context) {
    final litIndex = beats > 0 ? (beats - 1) % 8 : -1;
    return Row(
      key: const Key('av_sync_band'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 8; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          _AvSyncBeatCell(index: i, lit: i == litIndex),
        ],
      ],
    );
  }
}

class _AvSyncBeatCell extends StatelessWidget {
  const _AvSyncBeatCell({required this.index, required this.lit});

  final int index;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final accent = CalibrationSessionGrid.isAccent(index);
    return Container(
      key: Key('av_sync_band_cell_$index'),
      width: accent ? 26.0 : 18.0,
      height: accent ? 8.0 : 5.0,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: accent ? 0.30 : 0.16),
        borderRadius: BorderRadius.circular(2),
      ),
      child: lit
          ? Container(
              key: Key('av_sync_band_cell_${index}_on'),
              width: accent ? 22.0 : 14.0,
              height: accent ? 6.0 : 3.0,
              decoration: BoxDecoration(
                color: kHighlightAmber,
                borderRadius: BorderRadius.circular(2),
              ),
            )
          : null,
    );
  }
}

/// BPM 快选档钮（歌曲节拍 / 120 / 160）。
class _AvSyncTierButton extends StatelessWidget {
  const _AvSyncTierButton({
    required this.buttonKey,
    required this.label,
    required this.selected,
    this.enabled = true,
    required this.onPressed,
  });

  final Key buttonKey;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: TextButton(
        key: buttonKey,
        onPressed: enabled ? onPressed : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 32),
          foregroundColor: selected ? kHighlightAmber : Colors.white70,
          // 禁用态不落回主题 onSurface 38%（近黑压黑 94% 气泡底
          // 不可辨），显式给禁用灰 token。
          disabledForegroundColor: kAvSyncTierDisabledTextColor,
          textStyle: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// −/＋ 步进钮：单步单击、按住连续（重复间隔与节拍对齐 ± 同量级；
/// 自绘 Listener 挂指针级长按重复，语义同控制层帧步进钮）。
class _AvSyncStepButton extends StatefulWidget {
  const _AvSyncStepButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onStep,
  });

  final Key buttonKey;
  final IconData icon;

  /// 无障碍名字（主动语态、说清动作与对象）。
  final String label;
  final VoidCallback onStep;

  @override
  State<_AvSyncStepButton> createState() => _AvSyncStepButtonState();
}

class _AvSyncStepButtonState extends State<_AvSyncStepButton> {
  /// 长按启动阈值与重复间隔（固定间隔；补偿调节无需渐快）。
  static const _holdDelay = Duration(milliseconds: 400);
  static const _repeatInterval = Duration(milliseconds: 100);

  Timer? _holdTimer;
  Timer? _repeatTimer;

  void _onDown() {
    widget.onStep();
    _holdTimer = Timer(_holdDelay, () {
      _repeatTimer = Timer.periodic(_repeatInterval, (_) => widget.onStep());
    });
  }

  void _stop() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '按住连续调节',
      // 指针长按走 [Listener]；读屏双击走这里的 `onTap`，两者都落到 onStep。
      child: Semantics(
        key: widget.buttonKey,
        button: true,
        label: widget.label,
        onTap: widget.onStep,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _onDown(),
          onPointerUp: (_) => _stop(),
          onPointerCancel: (_) => _stop(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(widget.icon, color: kHighlightAmber, size: 20),
          ),
        ),
      ),
    );
  }
}
