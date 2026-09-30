/// 节拍动画：连续游标相位 + 矩形进度条/机械摆锤两形态。
///
/// - **连续相位派生**（纯函数 seam）：
///   [deriveBeatPhase] 把播放位置解析为八拍大周期内的连续相位
///   [BeatAnimationPhase.cyclePhase]（0–1，含拍内细分，跨拍/跨格不重置——
///   全域位置推进），并给出小节首/八拍首强拍标记。
/// - **相位单一事实源**：动画的**八拍窗口首拍**（游标格所在的一格）、
///   **八拍首**与**强拍格**统一读 core 相位源 [BeatPhase]（网格 + 八拍
///   锚点）——半八拍与锚点重定相下，动画分组与轨上八拍大线同判。无锚点
///   调用点显式构造无锚点相位。
/// - **两形态**（用户可选，[BeatAnimationStyle]）：[MetronomeBeatAnimation]
///   在矩形大方块格（一栏 = 一个八拍，8 个分隔大方块、块内弱显拍号、格描
///   边逐格一致、强拍边界竖线、当前格整块亮青、格内只画用户半拍线、拖尾 +
///   游标线连续推进）与机械摆锤（一摆一拍、强拍摆幅略大，[pendulumSwing]，
///   不画半拍线）间切换。
/// - **发布值驱动**：widget 只读节拍呈现对象的发布值
///   [BeatPresentationValue]；[deriveBeatPhase] 与
///   [projectUserHalfBeatLines] 的求值点在对象侧（`beat_presentation.dart`），
///   纯函数 seam 本身保留在此供对象与测试复用。
/// - **节拍器声**：发声决策/排程在 `beat_schedule.dart`（排程消费 seam）；
///   音声设置槽/seek 复位信号/共享音声词表住中立音声文件
///   `metronome_sound.dart`。
library;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/beat_grid.dart';
import '../core/eight_beat_phase.dart';
import 'metronome_settings_store.dart';
import 'beat_prompt_memory.dart';
import '../core/current_beat.dart'
    show BeatCountDisplay, LeadingBeatCount, PracticeBeatCount;
import '../core/current_beat.dart' show CurrentBeat;
import 'visual_tokens.dart';

/// 节拍动画形态（用户可选）。
enum BeatAnimationStyle {
  /// 矩形进度条：一栏 = 一个八拍。
  bar,

  /// 机械摆锤：一摆一拍。
  pendulum,
}

/// 动画形态解码/编码（设备级默认层与记忆字段共用；词表 = 枚举名）。
BeatAnimationStyle? decodeBeatAnimationStyle(Object? raw) =>
    switch (raw) {
      'bar' => BeatAnimationStyle.bar,
      'pendulum' => BeatAnimationStyle.pendulum,
      _ => null,
    };

Object? encodeBeatAnimationStyle(BeatAnimationStyle style) => switch (style) {
      BeatAnimationStyle.pendulum => 'pendulum',
      BeatAnimationStyle.bar => 'bar',
    };

/// 动画形态设备级「新舞默认」槽（global_private.json
/// `metronomeSettings.animationStyle`；语义 = 新舞默认——这支舞
/// 还没有意见时用的值）。
final beatAnimationStyleDefaultProvider =
    NotifierProvider<BeatAnimationStyleDefaultModel, BeatAnimationStyle>(
      BeatAnimationStyleDefaultModel.new,
    );

class BeatAnimationStyleDefaultModel
    extends PersistedSettingModel<BeatAnimationStyle> {
  @override
  String get settingField => 'animationStyle';

  @override
  BeatAnimationStyle? Function(Object? raw) get decode =>
      decodeBeatAnimationStyle;

  @override
  Object? Function(BeatAnimationStyle value) get encode =>
      encodeBeatAnimationStyle;

  @override
  BeatAnimationStyle get defaultValue => BeatAnimationStyle.bar;
}

/// 动画形态生效值设置槽：记忆有值用记忆值，缺席回落设备级「新舞
/// 默认」；用户选择双写记忆与设备级字段。
final beatAnimationStyleProvider =
    NotifierProvider<BeatAnimationStyleModel, BeatAnimationStyle>(
      BeatAnimationStyleModel.new,
    );

class BeatAnimationStyleModel
    extends BeatPromptEffectiveModel<BeatAnimationStyle> {
  @override
  BeatAnimationStyle? memoryValueOf(memory) {
    final raw = memory?.animationStyle;
    return raw == null ? null : decodeBeatAnimationStyle(raw);
  }

  @override
  BeatAnimationStyle watchDeviceDefault() =>
      ref.watch(beatAnimationStyleDefaultProvider);

  @override
  void persistDeviceDefault(BeatAnimationStyle value) =>
      ref.read(beatAnimationStyleDefaultProvider.notifier).set(value);

  @override
  void writeMemoryField(BeatAnimationStyle value) =>
      ref.read(beatPromptMemoryProvider.notifier).setAnimationStyle(value.name);
}

/// 动画侧连续游标相位（含强拍标记）。
///
/// 命名消歧：**本类型是动画的派生显示相位**，与 core 的相位
/// 事实源 [BeatPhase]（网格 + 八拍锚点，决定哪些拍是八拍点）不是一个东西
/// ——后者是入参，本类型是它的派生面（拍内细分相位 + 窗口内偏移）。
class BeatAnimationPhase {
  const BeatAnimationPhase({
    required this.beatInCycle,
    required this.beatFraction,
    required this.cyclePhase,
    required this.isEightStart,
    required this.isBarStart,
    required this.beatIndex,
  });

  /// 八拍窗口内第几拍（0–7）= 当前位置距**八拍窗口首拍**（相位源给出的
  /// 最近八拍点）的拍数。
  final int beatInCycle;

  /// 拍内连续相位（0–1）。
  final double beatFraction;

  /// 八拍大周期内的全域连续相位（0–1）= (beatInCycle + beatFraction)/8；
  /// 跨拍、跨格连续推进（不按块重置）。
  final double cyclePhase;

  /// 八拍首（强拍中最醒目一级；相位源判定）。
  final bool isEightStart;

  /// 小节首（非八拍首的 downbeat，强拍）。
  final bool isBarStart;

  /// 网格内绝对拍序号（早于首拍钳制为 firstDownbeatIndex）。
  final int beatIndex;

  /// 八拍窗口首拍（当前 8 格栏的起始拍）= beatIndex − beatInCycle；
  /// 相位源判定（锚点重定相后随锚点移动）。
  int get windowFirstBeatIndex => beatIndex - beatInCycle;

  /// 强拍（八拍首或小节首）。
  bool get isStrong => isEightStart || isBarStart;

  @override
  bool operator ==(Object other) =>
      other is BeatAnimationPhase &&
      other.beatInCycle == beatInCycle &&
      other.beatFraction == beatFraction &&
      other.cyclePhase == cyclePhase &&
      other.isEightStart == isEightStart &&
      other.isBarStart == isBarStart &&
      other.beatIndex == beatIndex;

  @override
  int get hashCode => Object.hash(
    beatInCycle,
    beatFraction,
    cyclePhase,
    isEightStart,
    isBarStart,
    beatIndex,
  );
}

int _euclidMod(int a, int b) => ((a % b) + b) % b;

/// 连续游标相位派生（纯函数 seam）。
///
/// 拍序号经 [BeatGrid.beatIndexAt] 定位、拍内相位由相邻拍时刻内插；
/// **八拍窗口首拍 / 八拍首 / 强拍**统一取自 core 相位源 [phase]（网格 +
/// 八拍锚点，**必填**——漏传即编译错误，无锚点调用点显式构造无锚点相位）。
///
/// 窗口首拍 = 不晚于当前拍的最近八拍点（[BeatPhase.eightBeatPointIndexAtOrBefore]）；
/// 弱起区（早于该段首个八拍点，定位为 -1 的时间钳到首拍）与八拍点间距
/// 超过 8 拍的稀疏网格退回索引算术窗口（8 格栏容纳不下该区间，仅游标格
/// 位置回退，强拍格仍按相位源判定）。早于首拍的时间钳制到首拍相位 0
/// （前导区游标停在起点，与数拍数字的倒数语义并行）。
BeatAnimationPhase deriveBeatPhase({
  required BeatGrid grid,
  required Duration position,
  required BeatPhase phase,
}) {
  // 拍边界走网格 seam 的唯一求值（与求值层同一份
  // 守卫）：早于首拍钳到首拍，有界网格末拍拍末钳回拍首（拍内相位 0，
  // 无激活段常态播放可达网格末拍，直接取 beatTime(index+1) 会越界）。
  final boundary = grid.beatBoundaryAt(position);
  final index = boundary.index;
  final beatStart = boundary.beatStart;
  final beatEnd = boundary.beatEnd;
  var fraction = 0.0;
  if (!boundary.beforeFirst && beatEnd > beatStart) {
    fraction =
        (position - beatStart).inMicroseconds /
        (beatEnd - beatStart).inMicroseconds;
    fraction = fraction.clamp(0.0, 1.0);
  }
  final cycleBeats = kBeatsPerEightCount;
  final pointIndex = phase.eightBeatPointIndexAtOrBefore(index);
  final windowFirst = (pointIndex != null && index - pointIndex < cycleBeats)
      ? pointIndex
      : index - _euclidMod(index - grid.firstDownbeatIndex, cycleBeats);
  final beatInCycle = index - windowFirst;
  // 八拍首 / 小节首判定经 core 相位源：八拍首 = 相位源八拍点
  //（自相位原点起 downbeat 全局序数奇偶），小节首 = 其余强拍
  //（[BeatPhase.isStrongBeat]，与 [_BeatBar._isStrongCell] 同一判定；弱起拍
  // 不按 `rel % beatsPerBar` 的索引算术误判）。
  final isEightStart = phase.isEightBeatPoint(index);
  final isBarStart = phase.isStrongBeat(index) && !isEightStart;
  return BeatAnimationPhase(
    beatInCycle: beatInCycle,
    beatFraction: fraction,
    cyclePhase: (beatInCycle + fraction) / cycleBeats,
    isEightStart: isEightStart,
    isBarStart: isBarStart,
    beatIndex: index,
  );
}

/// 用户半拍线在八拍格内的投影（纯函数 seam）。
class UserHalfBeatProjection {
  const UserHalfBeatProjection({
    required this.beatOffset,
    required this.beatFraction,
  });

  /// 所属拍在当前八拍窗口内的偏移（0–7）。
  final int beatOffset;

  /// 标记相对所属拍的时间相位（0–1）。
  final double beatFraction;

  @override
  bool operator ==(Object other) =>
      other is UserHalfBeatProjection &&
      other.beatOffset == beatOffset &&
      other.beatFraction == beatFraction;

  @override
  int get hashCode => Object.hash(beatOffset, beatFraction);
}

/// 把用户插入的半拍线标记投影到当前八拍窗口：
///
/// 仅保留落在窗口 `[windowFirstBeatIndex, windowFirstBeatIndex + 8)` 内的
/// 标记；每条按其相对所属拍的时间相位给出格内位置；同拍多条都保留。
/// 真实有界网格早于首拍返回 -1，不投影（占位均匀网格把负值钳到 0，生产
/// 上首拍之前也无从落标记）。无自动半拍刻度——数据源只有用户标记。
List<UserHalfBeatProjection> projectUserHalfBeatLines({
  required BeatGrid grid,
  required int windowFirstBeatIndex,
  required Iterable<Duration> halfBeatLines,
}) {
  final windowEnd = windowFirstBeatIndex + kBeatsPerEightCount;
  final projections = <UserHalfBeatProjection>[];
  for (final line in halfBeatLines) {
    final index = grid.beatIndexAt(line);
    if (index < windowFirstBeatIndex || index >= windowEnd) continue;
    // 拍边界走网格 seam 的唯一求值：有界网格末拍
    // 拍末钳回拍首（格内相位 0），不外推越界索引。
    final boundary = grid.beatBoundaryAt(line);
    final beatStart = boundary.beatStart;
    final beatEnd = boundary.beatEnd;
    var fraction = 0.0;
    if (beatEnd > beatStart) {
      fraction =
          (line - beatStart).inMicroseconds /
          (beatEnd - beatStart).inMicroseconds;
      fraction = fraction.clamp(0.0, 1.0);
    }
    projections.add(
      UserHalfBeatProjection(
        beatOffset: index - windowFirstBeatIndex,
        beatFraction: fraction,
      ),
    );
  }
  projections.sort((a, b) {
    final byOffset = a.beatOffset.compareTo(b.beatOffset);
    return byOffset != 0 ? byOffset : a.beatFraction.compareTo(b.beatFraction);
  });
  return projections;
}

/// 机械摆锤相位（纯函数）：返回 -1–1，一摆一拍——偶数拍从 -1 摆到 +1、
/// 奇数拍回摆；三角形波（拍首/拍末在端点、拍中过中线）。强拍摆幅 1.0、
/// 普通拍略小（视觉主次）。
double pendulumSwing(BeatAnimationPhase phase) {
  const strongAmplitude = 1.0;
  const normalAmplitude = 0.85;
  final amplitude = phase.isStrong ? strongAmplitude : normalAmplitude;
  final travel = phase.beatFraction * 2 - 1;
  final swing = phase.beatInCycle.isEven ? travel : -travel;
  return swing * amplitude;
}

/// 发布值：当前拍（自足的值）+ 动画状态。屏幕
/// 消费方只读本值一个来源，不读网格 / 相位 / 半拍线 / 位置 / 锚。求值点
/// 在节拍呈现对象（`beat_presentation.dart` 的 `evaluatePresentationValue`）。
class BeatPresentationValue {
  const BeatPresentationValue({
    required this.beat,
    required this.animation,
    required this.strongBoundaryOffsets,
    required this.halfBeatProjections,
  });

  /// 当前拍（core 纯求值的输出）。
  final CurrentBeat beat;

  /// 动画游标相位（八拍窗口内偏移 + 拍内连续相位 + 强拍标记）。
  final BeatAnimationPhase animation;

  /// 当前八拍窗口内画强拍边界竖线的格偏移（1–7，画在第 i 格左边界）。
  final List<int> strongBoundaryOffsets;

  /// 用户半拍线在当前八拍窗口内的投影。
  final List<UserHalfBeatProjection> halfBeatProjections;

  /// 数拍数字显示（八拍号 0 = 前导区 `0｜x`，否则练习区两数、组上标由
  /// [BeatCountNumbers] 派生）。
  BeatCountDisplay get display => beat.eightCount == 0
      ? LeadingBeatCount(beatCount: beat.beatCount)
      : PracticeBeatCount(
          eightCount: beat.eightCount,
          beatCount: beat.beatCount,
        );

  @override
  bool operator ==(Object other) =>
      other is BeatPresentationValue &&
      other.beat == beat &&
      other.animation == animation &&
      listEquals(other.strongBoundaryOffsets, strongBoundaryOffsets) &&
      listEquals(other.halfBeatProjections, halfBeatProjections);

  @override
  int get hashCode => Object.hash(
    beat,
    animation,
    Object.hashAll(strongBoundaryOffsets),
    Object.hashAll(halfBeatProjections),
  );
}

/// 节拍动画内容（浮层内承载）：随浮层位置/缩放联动（宿主把
/// 本组件放入 [MetronomeOverlay] 内容位）。
///
/// widget 只读发布值 [BeatPresentationValue]——
/// 八拍窗口相位、强拍边界、用户半拍线投影与游标推进全部由节拍呈现对象
/// 按同一份上下文求值后发布，widget 不再依赖网格 / 相位 / 半拍线 / 位置 /
/// 锚（同源是结构而不是装配纪律）。
class MetronomeBeatAnimation extends StatelessWidget {
  const MetronomeBeatAnimation({
    super.key,
    required this.style,
    required this.value,
  });

  final BeatAnimationStyle style;

  /// 节拍呈现发布值（null = 无可数拍，渲染空占位——浮层此时不挂载）。
  final BeatPresentationValue? value;

  @override
  Widget build(BuildContext context) {
    final value = this.value;
    if (value == null) return const SizedBox.shrink();
    return switch (style) {
      BeatAnimationStyle.bar => _BeatBar(
        phase: value.animation,
        strongBoundaryOffsets: value.strongBoundaryOffsets,
        halfBeatProjections: value.halfBeatProjections,
      ),
      BeatAnimationStyle.pendulum => _BeatPendulum(phase: value.animation),
    };
  }
}

/// 半拍细分色（与插入半拍线同一冷灰蓝 token，两层
/// 半拍概念同用冷灰蓝视觉统一）。
const Color kBeatHalfSubdivisionColor = kHalfBeatLineColor;

/// 当前格亮青时格内半拍线的加深色（深墨青，取自当前格
/// 数字墨色 `#06272A`）。
const Color kBeatHalfLineDeepenedColor = Color(0xFF06272A);

/// 大方块格暗底色（`.sq` 底 `#1B202B`）。
const Color _kBeatBlockColor = Color(0xFF1B202B);

/// 普通格描边色（`.sq` 描边 `#2A313D`）。
const Color _kBeatBlockStrokeColor = Color(0xFF2A313D);

/// 格描边（四边共用一份：任何一格四边同宽同色）。
const BorderSide _kBeatBlockSide = BorderSide(
  color: _kBeatBlockStrokeColor,
  width: 1.0,
);

/// 强拍边界竖线色（`.sq.down` 描边 `#4A5A6B`）：与格描边
/// 相比明显更亮更粗。
const Color _kStrongBeatLineColor = Color(0xFF4A5A6B);

/// 强拍边界竖线宽（2px）。
const double _kStrongBeatLineWidth = 2.0;

/// 矩形节拍动画：一栏 = 一个八拍，8 格无缝等分
/// 整条（每格 = 一个拍间隔、格间只靠描边分隔、无行尾悬空，块内弱显拍号
/// 1–8、格描边逐格一致），当前格整块亮青；游标（白 + 青描边 + 顶部三角）
/// 按全域相位跨块连续推进，已过区间带青拖尾。强拍由一条独立竖线标出
/// （见 [_isStrongCell] 与 build 内注释）。格内半拍线只画**用户
/// 插入的半拍线**（[projectUserHalfBeatLines] 投影；无自动半拍刻度）：相邻
/// 拍中点 = 所属格几何正中；当前格亮青时格内半拍线加深
/// （[kBeatHalfLineDeepenedColor]、略加粗），其余格保持冷灰蓝。
class _BeatBar extends StatelessWidget {
  const _BeatBar({
    required this.phase,
    required this.strongBoundaryOffsets,
    required this.halfBeatProjections,
  });

  /// 动画游标相位（拍内细分 + 窗口内偏移）。
  final BeatAnimationPhase phase;

  /// 强拍边界竖线的格偏移（发布值给出，1–7）。
  final List<int> strongBoundaryOffsets;

  final List<UserHalfBeatProjection> halfBeatProjections;

  static const double _height = 28;

  /// 头尾格圆角。
  static const double _endRadius = 8;

  /// 强拍边界竖线画不画（偏移清单由发布值给出：窗口内部边界、越界不画，
  /// 强拍判定单一来源在节拍呈现对象侧）。
  bool _isStrongBoundary(int boundaryOffset) =>
      strongBoundaryOffsets.contains(boundaryOffset);

  /// 单条用户半拍线：按相对所属拍相位投影到格内 x；无缝等分下拍中
  /// （beatFraction 0.5）恰好落在所属格几何正中。当前格亮青 → 加深略粗，
  /// 其余格冷灰蓝。
  Widget _userHalfBeatLine({
    required UserHalfBeatProjection projection,
    required int index,
    required int cycleBeats,
    required double width,
  }) {
    final deepened = projection.beatOffset == phase.beatInCycle;
    final lineW = deepened ? 2.0 : 1.0;
    final x =
        (projection.beatOffset + projection.beatFraction) / cycleBeats * width;
    return Positioned(
      key: Key('beat_anim_user_half_$index'),
      left: x - lineW / 2,
      top: 2,
      bottom: 2,
      width: lineW,
      child: ColoredBox(
        color: deepened
            ? kBeatHalfLineDeepenedColor
            : kBeatHalfSubdivisionColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 八拍窗口 = 当前格所在八拍（首拍 = 相位源给出的最近八拍点）；每格 =
    // 一个拍间隔（左缘 = 拍 k、右缘 = 拍 k+1），8 格无缝等分整条；
    // 坐标统一单一基准 x = 拍相位 × 格宽。
    final cycleBeats = kBeatsPerEightCount;
    final projections = halfBeatProjections;
    return SizedBox(
      key: const Key('beat_anim_bar'),
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final slot = width / cycleBeats;
          final cursorX = phase.cyclePhase * width;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 8 格无缝等分整条：格间分隔 = 1px 描边（任何一格四边同宽同色，
              // 强拍由独立竖线标出）；头尾格圆角；当前格整块亮青。
              for (var i = 0; i < cycleBeats; i++)
                Positioned(
                  key: Key('beat_anim_block_$i'),
                  left: i * slot,
                  top: 0,
                  bottom: 0,
                  width: slot,
                  child: Container(
                    decoration: BoxDecoration(
                      color: i == phase.beatInCycle
                          ? kCyanAccentColor
                          : _kBeatBlockColor,
                      border: Border(
                        // 非头格省去左描边：相邻格共享分隔线，无缝拼接。
                        left: i == 0 ? _kBeatBlockSide : BorderSide.none,
                        top: _kBeatBlockSide,
                        right: _kBeatBlockSide,
                        bottom: _kBeatBlockSide,
                      ),
                      borderRadius: BorderRadius.horizontal(
                        left: i == 0
                            ? Radius.circular(_endRadius)
                            : Radius.zero,
                        right: i == cycleBeats - 1
                            ? Radius.circular(_endRadius)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              // 强拍边界竖线：画在强拍格**左边界**上、2px、中心压在边界正
              // 中间（线的中心 = 那个拍点的时刻）。窗口左端（第一格左边界）
              // 不画——起点由端帽表达；越过末拍的边界无拍可派生、不画。
              // 画在格层之上、拖尾之下（拖尾半透明，竖线作为分隔线仍可读）。
              for (var i = 1; i < cycleBeats; i++)
                if (_isStrongBoundary(i))
                  Positioned(
                    key: Key('beat_anim_strong_line_$i'),
                    left: i * slot - _kStrongBeatLineWidth / 2,
                    top: 0,
                    bottom: 0,
                    width: _kStrongBeatLineWidth,
                    child: const ColoredBox(color: _kStrongBeatLineColor),
                  ),
              // 拖尾（已过区间，适度可见）。
              Positioned(
                key: const Key('beat_anim_fill'),
                left: 0,
                top: 0,
                bottom: 0,
                width: cursorX,
                child: ColoredBox(
                  color: kCyanAccentColor.withValues(alpha: 0.22),
                ),
              ),
              // 格内弱显拍号 1–8（16px、白 35%，当前格深色）。
              for (var i = 0; i < cycleBeats; i++)
                Positioned(
                  left: i * slot,
                  top: 0,
                  bottom: 0,
                  width: slot,
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      key: Key('beat_anim_beat_number_$i'),
                      style: TextStyle(
                        color: i == phase.beatInCycle
                            ? kBeatHalfLineDeepenedColor
                            : Colors.white.withValues(alpha: 0.35),
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              // 用户半拍线（当前格亮青 → 加深略粗；其余格冷灰蓝）。
              for (var j = 0; j < projections.length; j++)
                _userHalfBeatLine(
                  projection: projections[j],
                  index: j,
                  cycleBeats: cycleBeats,
                  width: width,
                ),
              // 游标线：白 + 青描边 + 顶部三角标记（跨块连续推进）。
              Positioned(
                key: const Key('beat_anim_cursor'),
                left: cursorX - 1.5,
                top: 0,
                bottom: 0,
                width: 3,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(
                      color: kCyanAccentColor,
                      width: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: cursorX - 4,
                top: -5,
                child: _CursorTriangle(color: kCyanAccentColor),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 游标顶部三角标记。
class _CursorTriangle extends StatelessWidget {
  const _CursorTriangle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(8, 5),
      painter: _TrianglePainter(color: color),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 机械摆锤：一摆一拍（[pendulumSwing]），摆锤点 + 中轴；强拍摆幅略大。
class _BeatPendulum extends StatelessWidget {
  const _BeatPendulum({required this.phase});

  final BeatAnimationPhase phase;

  /// 显式高度：宿主 Column 对非弹性子级给无限高，无显式高度会让内部
  /// Stack shrink-wrap 成 0 高（真机整棵不可见）；与矩形行视觉
  /// 高度协调取 32。
  static const double _height = 32;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('beat_anim_pendulum'),
      height: _height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final swing = pendulumSwing(phase);
          final width = constraints.maxWidth;
          final knobX = (width / 2) + swing * (width * 0.4);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 中轴：全高 1px 定位列（Center 链在无子级时恒 0 高，
              // 中轴从未真正绘制）。
              Positioned(
                key: const Key('beat_anim_pendulum_axis'),
                left: width / 2 - 0.5,
                top: 0,
                bottom: 0,
                width: 1,
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.3)),
              ),
              // 摆臂 + 摆锤。
              Positioned(
                left: knobX - 7,
                top: 0,
                bottom: 0,
                width: 14,
                child: Center(
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: phase.isStrong
                          ? kCyanAccentColor
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
