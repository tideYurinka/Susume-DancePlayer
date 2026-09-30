import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import 'annotation_editor.dart' show layoutLockedProvider;
import 'load_gate.dart' show loadGateActiveProvider, loadGateBlocksWrite;
import 'preview_snap.dart' show previewSnapEnabledProvider;
import 'tool_slots.dart' show PageWriteEntryId;
import 'track_band_session.dart';
import 'track_geometry.dart';
import 'track_time.dart';
import 'visual_tokens.dart';

/// 设置簇：由控制层承载、置于**轨道带外**
/// （轨道带上方外侧）右对齐一行的成组设置，不占轨道带内内容区——带内
/// 不再渲染 dock，轨道手柄带行恢复纯粹。
///
/// 组序固定 [预览线吸附开关｜锁定分段｜放大镜 + 缩放滑条]：前导选择器的
/// [delayedLoopProvider] 字段、合法取值与默认 4 拍不变；滑条左侧一枚
/// 纯装饰放大镜图标。
///
/// 缩放滑条仍以播放头为锚、经共享的 [TrackBandSession] 与轨道带/空白捏合层
/// 共用同一可视窗口（行为与带内时期不变，仅位置迁移）；无时间线（引擎时长
/// 未知/非正）时整簇隐藏。
///
/// 键名沿用带内时期的 `track_*` 前缀（同一组控件迁位，既有测试/接线锚点
/// 不变）。
class SettingsCluster extends ConsumerStatefulWidget {
  const SettingsCluster({super.key, required this.session});

  /// 轨道带会话域：与轨道带/控制层空白捏合
  /// 共享同一可视窗口——本簇只经它读窗口、写窗口，不持控制器。
  final TrackBandSession session;

  @override
  ConsumerState<SettingsCluster> createState() => _SettingsClusterState();
}

class _SettingsClusterState extends ConsumerState<SettingsCluster> {
  /// 缩放滑条（以播放头为锚，指数插值 1..maxZoomFactor）：滑到目标倍率
  /// [wantFactor]，相对当前倍率 [curFactor] 缩放一次（与轨道带内时期同一
  /// 数学，语义迁出；未缩放时窗口为 null → 以全宽窗口
  /// [TimelineWindow.full] 为基准起缩，同原 _effectiveWindow 回退）。
  void _onZoomSlider(double value) {
    final engine = ref.read(playbackEngineProvider);
    // 起缩窗口问轨道带几何模块的单一读取（null = 总时长未知 → 不动窗口）。
    final win = TrackBandGeometry.eval(
      total: engine.duration,
      window: widget.session.window,
      width: 0,
      // 只读窗口（缩放以播放头为锚，不映射像素）。
      prefixWidth: 0,
    ).effectiveWindowOrNull;
    if (win == null) return;
    final wantFactor = zoomFactorForSliderValue(
      win.total,
      sanitizeZoomSliderValue(value),
    );
    final curFactor = win.zoomFactor;
    if ((wantFactor - curFactor).abs() < 1e-6) return;
    widget.session.updateWindow(
      win.zoomed(anchor: engine.position, factor: wantFactor / curFactor),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = ref.watch(playbackEngineProvider).duration;
    if (!settingsStripVisibleFor(total)) return const SizedBox.shrink();
    // 此后 total 非空（可见性判定的另一半）。
    final timeline = total!;
    return Align(
      key: const Key('settings_cluster'),
      alignment: Alignment.centerRight,
      // 固定右缘（右缘只留固定边距），不随尾线手柄槽让位。
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        // 大字号不溢出：开关标签与读数随系统
        // 字号放大，放不下时整组等比缩小（与控制层工具行同口径）。
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 预览线吸附开关（点击切换，默认开；吸附网格设置左侧）。
              const _PreviewSnapToggle(),
              const SizedBox(width: 8),
              // 锁定分段开关（范围收窄）：会话内默认关；
              // 开启后阻止分段线的建/删/移/步进与 flag 切换、自动分段与
              // 清空分段、视频首/尾边界调整。
              const _LayoutLockToggle(),
              const SizedBox(width: 8),
              AnimatedBuilder(
                animation: widget.session.windowChanges,
                builder: (context, _) {
                  final window = widget.session.window;
                  return _ZoomDock(
                    // 进 Slider 的取值先过 NaN 过滤（静默钳制）。
                    value: window == null
                        ? 0
                        : sanitizeZoomSliderValue(zoomSliderValueFor(window)),
                    enabled: maxZoomFactorFor(timeline) > 1,
                    onChanged: _onZoomSlider,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 设置条（簇）可见性（单一出处）：无时间线
/// （时长未知/非正）时整簇隐藏、承载它的行随之整体让位。簇内 build 与
/// 控制层设置条行（_buildSettingsStrip）都读本一判定，不各写一份。
bool settingsStripVisibleFor(Duration? total) =>
    total != null && total > Duration.zero;

/// 设置开关状态文字色（开 = 白 90%，关闭/装载置灰 = 达标灰
/// token——两枚开关共用同一条取值，不各写一份三元式）。
Color settingsToggleTextColor({required bool on}) =>
    on ? Colors.white.withValues(alpha: 0.9) : kSettingsToggleOffTextColor;

/// 开关胶囊：命中盒撑到 [kHitTargetMinSize]——
/// 视觉胶囊（scrim + 状态文字）保持既有紧凑尺寸居中其内，外圈为透明
/// 命中区；点按语义与装载门控不变。
class _ToggleCapsule extends StatelessWidget {
  const _ToggleCapsule({
    required this.hitKey,
    required this.label,
    required this.on,
    required this.onToggle,
  });

  final Key hitKey;
  final String label;
  final bool on;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: hitKey,
      height: kHitTargetMinSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggle,
          child: Center(
            child: Material(
              color: kSettingsToggleScrimColor,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Text(
                  label,
                  style: TextStyle(
                    color: settingsToggleTextColor(on: on),
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 预览线吸附开关（随设置簇迁至带外，行为不变）。
class _PreviewSnapToggle extends ConsumerWidget {
  const _PreviewSnapToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(previewSnapEnabledProvider);
    // 设置开关是会写盘的入口（写 local prefs）：装载未完成时被同一道门
    // 挡下——置灰、可点、弹「正在装载」，值一位不动。
    final loading = ref.watch(loadGateActiveProvider);
    return _ToggleCapsule(
      hitKey: const Key('track_preview_snap_slot'),
      label: enabled ? '预览吸附·开' : '预览吸附·关',
      on: enabled && !loading,
      onToggle: () {
        if (loadGateBlocksWrite(ref, PageWriteEntryId.settingsToggle)) return;
        ref.read(previewSnapEnabledProvider.notifier).toggle();
      },
    );
  }
}

/// 锁定分段开关（范围收窄）：置于轨道
/// 设置条内，会话内随时开关（默认关）。开启后阻止分段结构族
/// ——分段线的建/删/移/步进与 flag 切换、自动分段三档与清空分段、视频
/// 首/尾边界调整——并弹短暂提示；节拍域与画面/各片段轨不受锁。
class _LayoutLockToggle extends ConsumerWidget {
  const _LayoutLockToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(layoutLockedProvider);
    // 设置开关会写盘（local prefs）：装载未完成时被同一道门挡下。
    final loading = ref.watch(loadGateActiveProvider);
    // 状态文字常显，开/关均带状态后缀并即时切换。
    return _ToggleCapsule(
      hitKey: const Key('layout_lock_toggle'),
      label: locked ? '锁定分段·开' : '锁定分段·关',
      on: locked && !loading,
      onToggle: () {
        if (loadGateBlocksWrite(ref, PageWriteEntryId.settingsToggle)) return;
        ref.read(layoutLockedProvider.notifier).toggle();
      },
    );
  }
}

/// 缩放滑条轨道形状（视觉件与透明命中件共用一份，只覆写颜色）。
const SliderThemeData _zoomSliderShapeTheme = SliderThemeData(
  trackHeight: 2,
  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
  overlayShape: RoundSliderOverlayShape(overlayRadius: 10),
);

/// 缩放滑条 dock（位于轨道带外）：紧凑滑条（0 = 全宽、
/// 1 = 最细可视）；[enabled] 为 false（视频过短无可缩放空间）时禁用置灰。
/// 左侧一枚纯装饰放大镜图标：不承载点击、无手势包裹。
class _ZoomDock extends StatelessWidget {
  const _ZoomDock({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    // 命中盒 = 外层 48 高盒；视觉 dock（黑色
    // 衬底 154×28 = 内容 142×24 + 衬边 6/2，与迁位前逐位同尺寸）居中其内。
    // 上层叠一枚全透明滑条承接拖动（RenderSlider 命中即整盒），视觉件因此
    // 不承接指针、不进语义树——外观与拖动行为都与迁位前一致。
    return SizedBox(
      key: const Key('track_zoom_dock'),
      width: 154,
      height: kHitTargetMinSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 放大镜与衬底保持「点了没反应」（语义）：吃掉落点的手势，
          // 不冒泡到外层的空白单击收起。
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: Material(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: SizedBox(
                  // 图标 14 + 间距 2 + 滑条（Expanded ≈120）：dock 加宽只为
                  // 容纳放大镜，滑条区与迁移前等宽档。
                  width: 142,
                  height: 24,
                  child: Row(
                    children: [
                      // 纯装饰放大镜：贴紧滑条左侧，无点击语义。
                      const Icon(Icons.search, color: Colors.white70, size: 14),
                      const SizedBox(width: 2),
                      Expanded(
                        child: SliderTheme(
                          data: _zoomSliderShapeTheme.copyWith(
                            activeTrackColor: Colors.white70,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                          ),
                          child: ExcludeSemantics(
                            child: Slider(value: value, onChanged: null),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 透明滑条只盖视觉滑条区（衬边 6 + 放大镜 14 + 间距 2 = 22；右侧
          // 同衬边 6），放大镜保持纯装饰、点它不产生任何状态变化。
          Positioned(
            left: 22,
            right: 6,
            top: 0,
            bottom: 0,
            child: SliderTheme(
              data: _zoomSliderShapeTheme.copyWith(
                activeTrackColor: Colors.transparent,
                inactiveTrackColor: Colors.transparent,
                thumbColor: Colors.transparent,
                overlayColor: Colors.transparent,
              ),
              child: Slider(
                key: const Key('track_zoom_slider'),
                value: value,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
