/// 节拍提示气泡内容（三段并排横屏重排）。
///
/// - **容器**：倍速同款锚定气泡（[SpeedBubbleMode.beat]，与倍速设置/倍速
///   步进共享 [speedBubbleSessionProvider] 单值互斥会话）。两处入口——
///   编辑态顶栏「节拍提示」工具（锚在按钮下方）与观看态数拍浮层选中态
///   左下角工具（锚在工具上方）——同一组件。
/// - **形态**：横屏窄高三段并排（节拍动画｜声音反馈｜节拍矫正），
///   列间细竖分隔线、各列组名在顶。任何开关态下内容一次全显、不依赖外层
///   纵向滚动兜底（内容高按横屏窄高收紧，目标 ≤~170px 量级）。
/// - **收起占宽**：节拍动画、声音反馈两组的总开关关闭即收起本组子行，
///   但只变高度、各列宽与气泡总宽不变。实现为
///   **固定保留列宽**（[animColWidth]/[soundColWidth]/[correctionColWidth]）：
///   收起子行从布局移除、宽度仍由该固定列宽保留——列宽与气泡总宽在任何
///   开关态都恒定（「零高保留宽」的可测等价）。
/// - **关闭弃预览**：气泡关闭（含切到其它气泡、含切到节拍对齐气泡）即清空
///   节拍对齐预览偏移，不自动应用（会话侧 [SpeedBubbleSession] 统一处理）。
/// - **节拍动画＝总开关**（[beatPromptEnabledProvider]）：数拍数字与
///   矩形/摆锤动画同显同隐。会话级，默认关；节拍识别成功后自动置开一次。
/// - **声音反馈**（[MetronomeSoundEnabledModel]，会话级默认关）+
///   音源（设备级 `soundType`，「音源 ▾」锚定列表，人声/歌姬无采样置灰
///   不可选）+ 半拍声 + 节拍音量滑条；声音总开关关闭即整组收起
///   （音源/半拍/音量一并隐藏）。
/// - **三段堆叠**：气泡族统一规则
///   「容不下并排即纵向堆叠」的第二消费者——横屏可用宽放得下三段并排即
///   并排（既有形态），竖屏放不下即三段上下堆叠、每段完整可见；各段内部
///   形态与定列宽不变（组总开关收起仍只变高度），判定走共用纯件
///   [bubbleReflowFor]（[beatPromptBubbleLayout]）。
/// - **节拍矫正＝菜单列**：第三列 = 标题
///   「节拍矫正」+ 一行小字说明 + 竖排三个按钮（各带一行使用提示小字），
///   **只放入口、不含控件本体**——「节拍对齐」点开控件本体所在的独立
///   锚定气泡（[SpeedBubbleMode.beatAlign]）；「八拍矫正」按下即关本气泡
///   + 落一个进入待命态的待办（宿主编排后经唯一提交入口提交）。
/// - **生效值与记忆**：面板读写的五个值都是
///   生效值——记忆有值用记忆值，缺席按字段默认（两个总开关恒关；形态/
///   音源/半拍回落设备级「新舞默认」，归 `metronome_settings_store.dart`
///   并在用户设置时双写）；总开关只写这支舞的记忆。
/// - **随舞落盘与恢复**：由设置持久化接线。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'beat_animation.dart';
import 'beat_bubble_theme.dart';
import 'beat_density_panel.dart'
    show
        beatDensityAvailableProvider,
        kBeatGridErrorHint,
        kBeatGridPlaceholderHint;
import 'beat_prompt_memory.dart';
import 'bubble_reflow.dart';
import 'metronome_sound.dart';
import '../player_session/player_session.dart'
    show PlayerSessionMode, playerSessionProvider;
import '../beat_track_state/beat_track_state.dart' show beatGridProvider;
import '../core/beat_grid.dart' show BeatGridReads;
import 'beat_correction.dart' show beatCorrectionAvailableProvider;
import 'song_loudness.dart';
import 'speed_bubble.dart' show SpeedBubbleMode, speedBubbleSessionProvider;
import 'visual_tokens.dart' show kHitTargetMinSize;
import '../help/content_registry.dart'
    show
        beatAnimationColumnAnchorKey,
        beatCorrectColumnAnchorKey,
        beatSoundColumnAnchorKey;
import '../help/guide_anchor.dart' show GuideAnchor;

/// 节拍气泡内容暗色主题见 `beat_bubble_theme.dart`（节拍提示气泡与节拍
/// 对齐独立气泡共用）。

/// 控件行高：行盒即命中盒，统一撑到命中下限
/// [kHitTargetMinSize]——文字与开关等视觉件不变、行内居中，多出的部分是
/// 透明命中区。
const double _beatCompactRowHeight = kHitTargetMinSize;

/// 分段钮紧凑行高（40 → ~32）。
const double _beatCompactSegmentHeight = 32;

/// 开关视觉盒高（命中经透明条带外扩到 [kHitTargetMinSize]，视觉不变）。
const double _beatCompactSwitchHeight = 36;

/// 节拍提示面板的列头、子行标签与提示小字承载语义，属语义档（随系统字号）：
/// 无覆写即吃环境缩放，量测与渲染吃同一个缩放值。
///
/// 组名列头文案样式（三段并排；深底白 87%、紧凑）。
const TextStyle _beatColHeaderStyle = TextStyle(
  color: Colors.white,
  fontSize: 13,
  fontWeight: FontWeight.w600,
);

/// 组内子行左标签样式（音源/音量 等）。
const TextStyle _beatColLabelStyle = TextStyle(
  color: Colors.white70,
  fontSize: 12,
);

/// 节拍矫正菜单列小字样式（列说明与各按钮的一行使用提示）。
const TextStyle _beatColHintStyle = TextStyle(
  color: Colors.white54,
  fontSize: 11,
);

/// 待支持占位标记小字样式（既有音源「待支持」项共用一套占位外观：
/// 置灰 + 白 38% 小字）。
const TextStyle _beatPendingLabelStyle = TextStyle(
  color: Colors.white38,
  fontSize: 11,
);

/// 节拍矫正菜单列入口按钮行高：与分段钮紧凑档同档
/// （[_beatCompactSegmentHeight]）：视觉仍 32，
/// 命中经 `MaterialTapTargetSize.padded` 透明外扩到下限（[kHitTargetMinSize]）。
const double _beatCorrectionButtonHeight = _beatCompactSegmentHeight;

/// 节拍矫正菜单列按钮样式（紧凑横向边距、行高钉
/// [_beatCorrectionButtonHeight]；padded 触控目标撑命中盒）。
const ButtonStyle _beatCorrectionButtonStyle = ButtonStyle(
  visualDensity: VisualDensity(horizontal: -2),
  padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
  minimumSize: WidgetStatePropertyAll(Size(0, _beatCorrectionButtonHeight)),
  tapTargetSize: MaterialTapTargetSize.padded,
  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 13)),
);

/// 组内容行横向内边距。
const EdgeInsets _beatColPad = EdgeInsets.only(left: 10, right: 8);

/// 节拍动画总开关生效值设置槽：数拍数字 + 矩形/摆锤动画的显隐（同显同隐），
/// 随舞记忆、无设备级对应值——记忆缺席一律关（识别
/// 成功后由分析运行器自动置开一次并写进记忆），用户选择只写这支舞的记忆。
final beatPromptEnabledProvider =
    NotifierProvider<BeatPromptEnabledModel, bool>(BeatPromptEnabledModel.new);

class BeatPromptEnabledModel extends Notifier<bool> {
  @override
  bool build() => ref.watch(beatPromptMemoryProvider)?.animation ?? false;

  void set(bool enabled) {
    if (!ref.mounted || enabled == state) return;
    ref.read(beatPromptMemoryProvider.notifier).setAnimation(enabled);
  }
}

/// 节拍提示气泡内容（三段并排；竖屏三段堆叠）。锚定与开关由
/// [SpeedBubbleHost] 接线；本组件只负责内容三段布局。
///
/// [stacked]由宿主按 [beatPromptBubbleLayout] 判定后传入：
/// false = 三段并排（横屏既有形态），true = 三段上下堆叠（竖屏放不下并排）。
class BeatPromptBubbleContent extends ConsumerWidget {
  const BeatPromptBubbleContent({super.key, this.stacked = false});

  /// 是否上下堆叠（唯一来源 = 宿主按共用重排规则 [bubbleReflowFor] 的判定）。
  final bool stacked;

  /// 分隔线宽（并排竖线 / 堆叠横线同为 1px）。
  static const double colGapWidth = 1;

  /// 分隔线两侧各留的间距（线两侧各 8px；堆叠时横线上下各留同值）。
  static const double colGapSide = 8;

  /// 段距（8 + 1 + 8 = 17px 口径）——并排列间距与堆叠行间距同值。
  static const double colGap = colGapSide + colGapWidth + colGapSide;

  /// 各段**保留宽**——收起子行后仍占的列宽：开关切换只变高度、列宽与气泡
  /// 总宽不变；全展开 + 最长读数（音量 100%、音源项最宽）在 host widget
  /// 量测得来，按同口径重校并预留 textScale 1.3 大字宽（量测
  /// anim 156.6 / sound 201.7），气泡总宽 824 → 760。并排与堆叠的唯一判据
  /// 是**可用宽是否放得下三段**，竖屏放不下即堆叠回落。
  ///
  /// [correctionColWidth]：第三列「节拍矫正」菜单列按**菜单列自身内容
  /// 实测**钉定宽——口径沿用「最长单行文案在 textScale 1.3 下不换行」
  /// （按钮 + 右侧使用提示小字一行是本列最宽行）。气泡总宽与两条分隔线位置
  /// 随 [_colWidths] 单源派生。
  static const double animColWidth = 158;
  static const double soundColWidth = 204;
  static const double correctionColWidth = 312;

  /// 三段列宽（按展示序：节拍动画｜声音反馈｜节拍矫正），供内容宽与分隔线
  /// 位置派生——单一来源，改列宽不散改 [contentWidth]/分隔线。
  static const List<double> _colWidths = [
    animColWidth,
    soundColWidth,
    correctionColWidth,
  ];

  /// 三段堆叠时的内容宽：最宽段（节拍矫正菜单列）的定宽——
  /// 每段完整可见所需的最小内容宽，气泡总宽随之恒定。
  static final double stackedContentWidth = _colWidths.reduce(
    (a, b) => a > b ? a : b,
  );

  /// 三段内容宽（含两处列间距），供 [SpeedBubble] 侧内容 maxWidth 兜底
  /// 对齐（速/步/avSync 仍用共享 [speedBubbleMaxWidth]）。与
  /// [columnSeparatorXs] 同由 [columnLayout] 单源累计派生。
  static double get contentWidth => columnLayout().width;

  /// 列布局单源累计（[contentWidth] 与各分隔线 x 只此一处手写累加，
  /// 避免改列宽/间距时两处漂移）：列间填 线前 [colGapSide] + 1px 线 + 线后
  /// [colGapSide]，返回各分隔线线中心 x 与三段内容总宽。
  static ({List<double> separatorXs, double width}) columnLayout() {
    final xs = <double>[];
    var x = 0.0;
    for (var i = 0; i < _colWidths.length; i++) {
      if (i > 0) {
        x += colGapSide;
        xs.add(x);
        x += colGapWidth + colGapSide;
      }
      x += _colWidths[i];
    }
    return (separatorXs: xs, width: x);
  }

  /// 列间分隔线 x 坐标（线中心，相对内容左缘）——三段两处（只在列
  /// **之间**，末列后无线）。供 [_ColumnVsepPainter] 满高竖线绘制。
  static List<double> columnSeparatorXs() => columnLayout().separatorXs;

  /// 紧凑钉行高行：[_beatCompactRowHeight] 档 + min Row，组名行/
  /// 半拍声行/音量行共用，行高档变更只改此处。
  Widget _compactRow({required List<Widget> children, Key? rowKey}) {
    return Padding(
      padding: _beatColPad,
      child: SizedBox(
        height: _beatCompactRowHeight,
        child: Row(
          key: rowKey,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }

  /// 行内控件上下的透明命中条：贴视觉件上/下
  /// 边、把点按按 x 转发给 [onTapAt]（dx = 点位横向位置、width = 行宽）。
  /// 视觉件保持既有紧凑档不变，命中盒由行盒（[kHitTargetMinSize]）+ 条带
  /// 补齐到下限。
  Widget _hitStrips({
    required double visualHeight,
    required void Function(double dx, double width) onTapAt,
    Widget? child,
    Key? hitKey,
  }) {
    final strip = (kHitTargetMinSize - visualHeight) / 2;

    // 上/下两条命中条共用同一构造（贴视觉件边、点按按 x 转发）。
    Widget edge({required bool top}) => Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      height: strip,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) =>
              onTapAt(details.localPosition.dx, constraints.maxWidth),
        ),
      ),
    );

    // 行内 Row 交叉轴对子项是松约束：显式钉行盒高，命中盒才是整个 48 高。
    return SizedBox(
      key: hitKey,
      height: kHitTargetMinSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ?child,
          if (strip > 0) ...[edge(top: true), edge(top: false)],
        ],
      ),
    );
  }

  /// 组名列头（节拍动画/声音反馈）右侧总开关；本组子行由开关收起/展开。
  Widget _masterRow({
    required String title,
    required Key switchKey,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    // 行高钉在 [_beatCompactRowHeight]（即命中下限档）。Switch 视觉
    // 保持主题紧凑档（36 高），上下透明命中条补齐到下限。
    return _compactRow(
      children: [
        // 组名随系统字号放大（语义档（随系统字号））；定列宽放不下时等比微缩保完整可读，
        // 不溢出不裁字（1.6× 档起才触发，≤1.3× 为原大）。
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(title, style: _beatColHeaderStyle),
          ),
        ),
        const SizedBox(width: 10),
        _hitStrips(
          visualHeight: _beatCompactSwitchHeight,
          onTapAt: (_, _) => onChanged(!value),
          hitKey: switchKey,
          child: SizedBox(
            // 定宽 52（M3 开关视觉盒）：大字号下组名 + 开关仍放进定列宽。
            width: 52,
            height: _beatCompactSwitchHeight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
      ],
    );
  }

  /// 一个开关组列骨架：定宽列 + 顶对齐 Column（组名开关行 + 可选子行）。
  /// 动画/声音两列共用，消除重复的列外框/间距脚手架（列宽来自
  /// [_colWidths] 单源）。
  Widget _toggleColumn({
    required Key columnKey,
    required double width,
    required String title,
    required Key switchKey,
    required bool value,
    required ValueChanged<bool> onChanged,
    required List<Widget> body,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        key: columnKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _masterRow(
            title: title,
            switchKey: switchKey,
            value: value,
            onChanged: onChanged,
          ),
          ...body,
        ],
      ),
    );
  }

  /// 声音组内三个子行（音源/半拍/音量；声音总开关关则整组收起）。
  /// 音源下拉项：标签/置灰读注册表项，待支持项不可选。
  DropdownMenuItem<MetronomeSoundType> _sourceDropdownItem(
    MetronomeSoundType type,
  ) {
    final entry = type.sourceEntry;
    return DropdownMenuItem<MetronomeSoundType>(
      key: Key('beat_panel_sound_source_option_${type.name}'),
      value: type,
      enabled: entry.available,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.label,
            style: TextStyle(
              color: entry.available ? Colors.white : Colors.white38,
            ),
          ),
          if (!entry.available) ...[
            const SizedBox(width: 6),
            const Text('待支持', style: _beatPendingLabelStyle),
          ],
        ],
      ),
    );
  }

  Widget _soundBody(BuildContext context, WidgetRef ref) {
    final soundType = ref.watch(metronomeSoundTypeProvider);
    final halfBeat = ref.watch(metronomeHalfBeatEnabledProvider);
    final volume = ref.watch(metronomeVolumeProvider);
    final accent = Theme.of(context).colorScheme.secondary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 音源行：「音源 ▾」锚定列表。
        // 行内可见标签与下拉合并同一语义节点，
        // 读屏报得出「音源」。
        Padding(
          padding: _beatColPad,
          child: MergeSemantics(
            child: Row(
              key: const Key('beat_panel_sound_source_row'),
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('音源', style: _beatColLabelStyle),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<MetronomeSoundType>(
                    key: const Key('beat_panel_sound_source_select'),
                    value: soundType,
                    isDense: true,
                    dropdownColor: Colors.black87,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    iconEnabledColor: Colors.white70,
                    items: [
                      for (final type in MetronomeSoundType.values)
                        _sourceDropdownItem(type),
                    ],
                    onChanged: (selection) {
                      if (selection == null) return;
                      ref
                          .read(metronomeSoundTypeProvider.notifier)
                          .set(selection);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        // 半拍声行（行盒 = 命中下限档；Switch 视觉紧凑档，透明命中条补齐）。
        _compactRow(
          children: [
            const Text('半拍声', style: _beatColLabelStyle),
            const SizedBox(width: 10),
            _hitStrips(
              visualHeight: _beatCompactSwitchHeight,
              onTapAt: (_, _) => ref
                  .read(metronomeHalfBeatEnabledProvider.notifier)
                  .set(!halfBeat),
              hitKey: const Key('beat_panel_half_beat_switch'),
              child: SizedBox(
                height: _beatCompactSwitchHeight,
                child: Switch(
                  value: halfBeat,
                  activeThumbColor: accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => ref
                      .read(metronomeHalfBeatEnabledProvider.notifier)
                      .set(value),
                ),
              ),
            ),
          ],
        ),
        // 音量行：文字标注「音量」+ 滑条(0–100) + 百分比。
        // 行盒 = 命中下限档。可见标签与滑条合并同一语义节点，
        // 读屏报得出「音量」；读数盒随系统字号放大（语义档（随系统字号），
        // 1.6× 不裁）；滑条在挤宽时让出空间（Flexible，1.6× 不横向溢出）。
        MergeSemantics(
          child: _compactRow(
            rowKey: const Key('beat_panel_volume_row'),
            children: [
              const Text('音量', style: _beatColLabelStyle),
              const SizedBox(width: 10),
              Flexible(
                child: SizedBox(
                  width: 108,
                  height: _beatCompactRowHeight,
                  child: Slider(
                    key: const Key('beat_panel_volume_slider'),
                    value: volume.toDouble(),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    label: '$volume%',
                    onChanged: (value) => ref
                        .read(metronomeVolumeProvider.notifier)
                        .set(value.round()),
                  ),
                ),
              ),
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(34),
                child: Text(
                  '$volume%',
                  textAlign: TextAlign.right,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 节拍矫正菜单列的一个入口行：按钮 + 右侧一行使用提示小字。
  ///
  /// - [onPressed] 为 null = 置灰；待支持项另带 [pendingKey] 的「待支持」
  ///   小字标记（沿用既有待支持音源项的占位惯例：置灰 + 「待支持」）。
  /// - 提示小字单行不换行：超出（大字号）时省略号收尾，不换行不溢出。
  Widget _correctionEntry({
    required Key buttonKey,
    required String label,
    required Key hintKey,
    required String hint,
    required VoidCallback? onPressed,
    Key? pendingKey,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 8, top: 4),
      child: Row(
        children: [
          OutlinedButton(
            key: buttonKey,
            onPressed: onPressed,
            style: _beatCorrectionButtonStyle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (pendingKey != null) ...[
                  const SizedBox(width: 6),
                  Text('待支持', key: pendingKey, style: _beatPendingLabelStyle),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hint,
              key: hintKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _beatColHintStyle,
            ),
          ),
        ],
      ),
    );
  }

  /// 第三列「节拍矫正」菜单列（三个条目）：标题 + 一行小字说明 + 竖排三个
  /// 按钮（各带一行使用
  /// 提示）。本列**只放入口、不含控件本体**：
  ///
  /// - 「节拍对齐」→ 打开控件本体所在的独立锚定气泡
  ///   （[SpeedBubbleMode.beatAlign]，本气泡随之消失——会话单值互斥）；
  /// - 「八拍矫正」→ 关本气泡 + 进控制层待命态。**仅真实网格
  ///   就绪时可用**（占位/异常置灰）；观看态同一角标打开本气泡，
  ///   本按钮**不置灰不隐藏**（是否可用只由网格就绪决定、不按
  ///   入口态区分），按下同样自动进控制层。
  /// - 「节拍倍频」→ 打开倍频独立气泡（[SpeedBubbleMode.beatDensity]）。
  Widget _correctionColumn(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: correctionColWidth,
      child: Column(
        key: const Key('beat_correction_column'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _beatColPad,
            child: Text('节拍矫正', style: _beatColHeaderStyle),
          ),
          const Padding(
            padding: _beatColPad,
            child: Text(
              '修正整曲或局部的节拍错位',
              key: Key('beat_correction_column_hint'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _beatColHintStyle,
            ),
          ),
          _correctionEntry(
            buttonKey: const Key('beat_correction_align_button'),
            label: '节拍对齐',
            hintKey: const Key('beat_correction_align_hint'),
            hint: '整首偏移时用',
            // 打开独立对齐气泡（控件本体在彼处）：会话单值 → 本气泡随之
            // 关闭；关闭/切走即弃未应用预览（会话侧统一处理）。
            onPressed: () => ref
                .read(speedBubbleSessionProvider.notifier)
                .open(SpeedBubbleMode.beatAlign),
          ),
          _correctionEntry(
            buttonKey: const Key('beat_correction_eight_beat_button'),
            label: '八拍矫正',
            hintKey: const Key('beat_correction_eight_beat_hint'),
            hint: '八拍点错位 / 半八拍时用',
            // 真实网格就绪即可用（占位/异常置灰）；按下即关气泡
            // + **落一个进入待命态的待办**（观看态入口同一路径）。进入编排
            // （画布兜底、浮层退选中）不在发起方——宿主（播放页）听待办槽，
            // 完成后经唯一提交入口提交、不成立则取消（模式值一位不动）。
            // 发起路径可多、提交点唯一。
            onPressed: ref.watch(beatCorrectionAvailableProvider)
                ? () {
                    ref.read(speedBubbleSessionProvider.notifier).close();
                    ref
                        .read(playerSessionProvider.notifier)
                        .requestEntry(PlayerSessionMode.beatCorrectionStandby);
                  }
                : null,
          ),
          _correctionEntry(
            buttonKey: const Key('beat_correction_density_button'),
            label: '节拍倍频',
            hintKey: const Key('beat_correction_density_hint'),
            // 使用提示按就绪态切换：
            // 就绪读词条句式；占位（分析中/未开始）与异常各说明原因。状态
            // 判读走共享内核两个可用性谓词，不做三态裸直判。
            hint: () {
              final reads = ref.watch(beatGridProvider);
              if (reads.hasRealBeats) return '识别快/慢一倍时用';
              return reads.isSecondsFallback
                  ? kBeatGridErrorHint
                  : kBeatGridPlaceholderHint;
            }(),
            // 打开倍频控件本体所在的独立锚定气泡
            // （[SpeedBubbleMode.beatDensity]，会话单值互斥）。置灰门 =
            // 真实拍点可用（占位/异常置灰），与八拍矫正
            // 同族——不按入口态区分。
            onPressed: ref.watch(beatDensityAvailableProvider)
                ? () => ref
                      .read(speedBubbleSessionProvider.notifier)
                      .open(SpeedBubbleMode.beatDensity)
                : null,
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promptOn = ref.watch(beatPromptEnabledProvider);
    final soundOn = ref.watch(metronomeSoundEnabledProvider);
    final animationStyle = ref.watch(beatAnimationStyleProvider);
    // 三列各自包引导锚点（逐栏走查）：并排与堆叠用的是同一组列
    // widget，锚点与文案在横竖屏重排下都无需分支。
    // 列1 节拍动画：组总开关 +（开时）形态分段。
    final animColumn = GuideAnchor(
      anchorKey: beatAnimationColumnAnchorKey,
      child: _toggleColumn(
        columnKey: const Key('beat_anim_column'),
        width: animColWidth,
        title: '节拍动画',
        switchKey: const Key('beat_panel_prompt_switch'),
        value: promptOn,
        onChanged: (v) => ref.read(beatPromptEnabledProvider.notifier).set(v),
        body: [
          if (promptOn)
            Padding(
              padding: _beatColPad,
              // 分段钮（视觉紧凑档不变）：透明
              // 命中条把行盒补齐到下限，点按按 x 折半转发给对应分段——命中盒
              // ≥ 下限而分段钮视觉行高不变。
              child: _hitStrips(
                visualHeight: _beatCompactSegmentHeight,
                hitKey: const Key('beat_panel_style_seg_hit'),
                // 命中条按 x 折算分段序（与视觉分段同序同宽：本钮两段等宽）。
                onTapAt: (dx, width) => ref
                    .read(beatAnimationStyleProvider.notifier)
                    .set(
                      dx < width / 2
                          ? BeatAnimationStyle.bar
                          : BeatAnimationStyle.pendulum,
                    ),
                child: SizedBox(
                  height: _beatCompactSegmentHeight,
                  child: SegmentedButton<BeatAnimationStyle>(
                    segments: const [
                      ButtonSegment(
                        value: BeatAnimationStyle.bar,
                        label: Text('矩形'),
                      ),
                      ButtonSegment(
                        value: BeatAnimationStyle.pendulum,
                        label: Text('摆锤'),
                      ),
                    ],
                    selected: {animationStyle},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity(
                        horizontal: -4,
                        vertical: -4,
                      ),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 8),
                      ),
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 12),
                      ),
                    ),
                    onSelectionChanged: (selection) => ref
                        .read(beatAnimationStyleProvider.notifier)
                        .set(selection.first),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    // 列2 声音反馈：组总开关 +（开时）音源/半拍/音量 整组。
    final soundColumn = GuideAnchor(
      anchorKey: beatSoundColumnAnchorKey,
      child: _toggleColumn(
        columnKey: const Key('beat_sound_column'),
        width: soundColWidth,
        title: '声音反馈',
        switchKey: const Key('beat_panel_sound_switch'),
        value: soundOn,
        onChanged: (v) =>
            ref.read(metronomeSoundEnabledProvider.notifier).set(v),
        body: [if (soundOn) _soundBody(context, ref)],
      ),
    );
    // 列3 节拍矫正：菜单列（标题 + 说明小字 + 竖排三个入口按钮）
    // ——只放入口，控件本体各在独立气泡/待命态。
    final correctionColumn = GuideAnchor(
      anchorKey: beatCorrectColumnAnchorKey,
      child: _correctionColumn(context, ref),
    );
    return Theme(
      data: beatBubbleContentTheme,
      // 并排（横屏）：三段顶对齐、各列自然高（组收/展只变本列高），列间细竖
      // 分隔线由 [_ColumnVsepPainter] 按列宽界线在整个内容高上绘制——各列高
      // 度不必等高，分隔线也能满高（真机窄高看版）。堆叠（竖屏）：
      // 三段上下、段间横分隔线；内容宽收为最宽段，各段完整可见。
      child: stacked
          ? SizedBox(
              key: const Key('beat_prompt_panel'),
              width: stackedContentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  animColumn,
                  const _StackedColumnSeparator(),
                  soundColumn,
                  const _StackedColumnSeparator(),
                  correctionColumn,
                ],
              ),
            )
          : CustomPaint(
              painter: _ColumnVsepPainter(separatorsAt: columnSeparatorXs()),
              child: Row(
                key: const Key('beat_prompt_panel'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  animColumn,
                  // 列间距（分隔线两侧各 8px + 1px 线，与
                  // [contentWidth] 计入的 colGap 对应；线由
                  // [_ColumnVsepPainter] 在间隙中央绘制）。
                  const SizedBox(width: BeatPromptBubbleContent.colGap),
                  soundColumn,
                  const SizedBox(width: BeatPromptBubbleContent.colGap),
                  correctionColumn,
                ],
              ),
            ),
    );
  }
}

/// 堆叠时的段间横分隔线：占满内容宽的 1px 白 24% 线，居中于
/// [BeatPromptBubbleContent.colGap] 的段距（与并排竖分隔线同一间隙口径）。
class _StackedColumnSeparator extends StatelessWidget {
  const _StackedColumnSeparator();

  @override
  Widget build(BuildContext context) {
    final width = BeatPromptBubbleContent.stackedContentWidth;
    return SizedBox(
      key: const Key('beat_stacked_separator'),
      width: width,
      height: BeatPromptBubbleContent.colGap,
      child: Center(
        child: SizedBox(
          width: width,
          height: BeatPromptBubbleContent.colGapWidth,
          child: const ColoredBox(color: Colors.white24),
        ),
      ),
    );
  }
}

/// 节拍提示气泡布局（纯件 seam）：三段并排还是上下堆叠 + 内容宽。
typedef BeatPromptBubbleLayout = ({bool stacked, double contentWidth});

/// 节拍提示气泡布局判定：**复用气泡族共用重排规则**
/// [bubbleReflowFor]——可用宽放得下三段并排（[sideBySideBubbleWidth] 已含
/// 气泡盒边距）即并排、内容宽 [BeatPromptBubbleContent.contentWidth]；否则
/// 三段上下堆叠、内容宽收为最宽段
/// [BeatPromptBubbleContent.stackedContentWidth]。判定只吃宽度、与设备方向
/// 无关（横竖屏切换经可用宽变化自然重排）。
BeatPromptBubbleLayout beatPromptBubbleLayout({
  required double availableWidth,
  required double sideBySideBubbleWidth,
}) {
  final stacked =
      bubbleReflowFor(
        availableWidth: availableWidth,
        sideBySideWidth: sideBySideBubbleWidth,
      ) ==
      BubbleReflow.stacked;
  return (
    stacked: stacked,
    contentWidth: stacked
        ? BeatPromptBubbleContent.stackedContentWidth
        : BeatPromptBubbleContent.contentWidth,
  );
}

/// 三段并排的列间细竖分隔线：按各列宽界线在整段内容高上绘制
/// 1px 竖线。用 CustomPaint 前景绘制即可满高——列不必等高，视觉分列清晰。
class _ColumnVsepPainter extends CustomPainter {
  const _ColumnVsepPainter({required this.separatorsAt});

  /// 各分隔线的 x 坐标（相对列宽累加 + 分隔间隙）。
  final List<double> separatorsAt;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white24
      ..strokeWidth = 1;
    for (final x in separatorsAt) {
      canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_ColumnVsepPainter oldDelegate) =>
      !listEquals(oldDelegate.separatorsAt, separatorsAt);
}
