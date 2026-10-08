/// **数拍层的值对象**（纯件，零 Flutter、零 IO；`#30`）：投屏副本里那一行
/// **逐拍静态数字**的时间窗、文字与归一化落位。
///
/// ## 只烤静态数字
///
/// 规格把「呈现类」定成「只烤逐拍静态数字（单输入的时间窗文本），不做摆锤
/// 动画」——烤死的动画与遥控跳段后的重锚定会互相打脸。因此这一层里没有
/// 动画条、没有摆锤、没有游标：一格就是一行数字（[CastBeatCountRow.text]）
/// 加它在**源时间轴**上的半开窗，`text == null` 的格是「这一段不显示」
/// （前导区之前、末拍之后，以及网格异常的那些段）。
///
/// ## 拍号取值与手机同源
///
/// 文字（八拍号 / 组上标 / 拍号）由**播放页**按上屏同一处派生
/// （`player/metronome_overlay.dart` 的 `beatCountTextOf`，逐拍求值走节拍呈现
/// 的同一条 `evaluatePresentationValue`）后带过来；投屏域不 import 播放页，
/// 也不自己数拍。这就是「数值与手机在同一时刻一致」的落实方式，也是
/// 「数字冻结在渲染那一刻」的来源：烤进去的就是渲染当时算出来的那几个字，
/// 投屏期间手机上重新锚定学习段，副本里那份不会跟着变（ADR-0004 已记录的
/// 已知偏差）。
library;

import 'dart:typed_data';

/// 一格的文字（八拍号 / 组上标 / 拍号）——与上屏那份 span 同源。
class CastBeatCountText {
  const CastBeatCountText({
    required this.eightCount,
    required this.beatCount,
    this.group,
  });

  /// 八拍号（前导区恒 `0`；练习区按「数四个八拍重新数」循环）。
  final String eightCount;

  /// 拍号（练习区 1–8；前导区按时间顺数）。
  final String beatCount;

  /// 组上标（相对八拍 > 4 才有；null = 不显示）。
  final String? group;

  @override
  bool operator ==(Object other) =>
      other is CastBeatCountText &&
      other.eightCount == eightCount &&
      other.beatCount == beatCount &&
      other.group == group;

  @override
  int get hashCode => Object.hash(eightCount, beatCount, group);

  @override
  String toString() =>
      'CastBeatCountText(${group == null ? '' : '$group '}$eightCount｜'
      '$beatCount)';
}

/// 数拍层的一格：**源时间轴**上的半开窗 `[startMs, endMs)` + 这一刻画什么。
///
/// [text] 为 null 的格仍进时间轴（序列要连续覆盖整片，见
/// `cast_beat_gate.dart` 的清单装配），只是画一张全透明的画布。
class CastBeatCountRow {
  const CastBeatCountRow({required this.startMs, required this.endMs, this.text});

  /// 这一格的起点（毫秒，含）。
  final int startMs;

  /// 这一格的终点（毫秒，不含——半开区间）。
  final int endMs;

  /// 这一刻要画的数字（null = 这一段不显示数拍）。
  final CastBeatCountText? text;

  /// 这一格多长（毫秒）。
  int get durationMs => endMs - startMs;

  /// 这一格要不要画数字。
  bool get visible => text != null && durationMs > 0;

  /// 进 `-f concat` 清单的时长字面量（秒；毫秒级精度足够，拍点本就同精度）。
  String get durationLiteral => (durationMs / 1000).toStringAsFixed(3);

  @override
  String toString() => 'CastBeatCountRow($startMs–$endMs, ${text ?? '（不显示）'})';
}

/// **整条数拍层**：逐格时间窗 + 归一化落位 + 每格 PNG 的惰性字节口。
///
/// 落位由播放页的 `cast_beat_placement.dart` 换算（视口 → 画面区域），
/// 此处只携带**画面区域归一化**的那四个数（投屏域不 import 播放页）。
/// 各格画布尺寸必须固定（图像序列是**一条流**）：播放页按全部行里最大的那一
/// 份底衬建画布，逐格居中画进去（见 `player/cast_beat_sheet.dart`）。
class CastBeatCountOverlay {
  const CastBeatCountOverlay({
    required this.rows,
    required this.centerX,
    required this.centerY,
    required this.widthFraction,
    required this.heightFraction,
    required this.imageBytesOf,
  });

  /// 逐格时间窗（升序、首尾相接、覆盖整片；见 `castBeatRowsOf`）。
  final List<CastBeatCountRow> rows;

  /// 落位中心横坐标（画面区域归一化）。
  final double centerX;

  /// 落位中心纵坐标。
  final double centerY;

  /// 落位宽占画面区域的比例。
  final double widthFraction;

  /// 落位高占画面区域的比例。
  final double heightFraction;

  /// 第 [index] 格画布的 PNG 字节（惰性：渲染编排落盘时现取）。
  final Future<Uint8List> Function(int index) imageBytesOf;

  /// 有没有可画的格（时间窗非空且至少一格真的要画数字）。
  bool get hasVisibleRow => rows.any((row) => row.visible);

  @override
  String toString() =>
      'CastBeatCountOverlay(${rows.length} 格, $centerX/$centerY, '
      '$widthFraction×$heightFraction)';
}
