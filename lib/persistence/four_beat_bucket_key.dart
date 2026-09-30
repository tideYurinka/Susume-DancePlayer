/// 四拍桶键的存储形状：倍频身份 + 桶序号，及其落盘字符串编解码。
///
/// 原样档（density = 1）即全部历史已有的**裸整数**键（零迁移）；其余档
/// 落盘为「倍频值 + `:` 分隔符 + 桶序号」（如 `2:17`、`0.25:0`）。
library;

import 'marker_document.dart' show BeatDensity;

/// 桶键＝记录时的倍频身份 + 桶序号。
class FourBeatBucketKey {
  const FourBeatBucketKey(this.density, this.index);

  /// 记录时的节拍倍频（派生拍数 ÷ 落盘拍数；1 = 原样）。
  final double density;

  /// 桶序号（该倍频档派生网格上的绝对四拍线序号）。
  final int index;

  bool get isBare => density == 1;

  @override
  bool operator ==(Object other) =>
      other is FourBeatBucketKey &&
      other.density == density &&
      other.index == index;

  @override
  int get hashCode => Object.hash(density, index);

  @override
  String toString() => encodeFourBeatBucketKey(this);
}

/// 桶键 → 落盘字符串（裸整数 / 「倍频值 + 分隔符 + 桶序号」）。
String encodeFourBeatBucketKey(FourBeatBucketKey key) {
  if (key.isBare) return key.index.toString();
  final density = key.density == key.density.roundToDouble()
      ? key.density.round().toString()
      : key.density.toString();
  return '$density:${key.index}';
}

/// 落盘字符串 → 桶键；非桶键（非数、负序号、不在五档内的倍频值）返回
/// null——由存储层收进陌生键保底区。
FourBeatBucketKey? parseFourBeatBucketKey(String raw) {
  final bare = int.tryParse(raw);
  if (bare != null) {
    return bare < 0 ? null : FourBeatBucketKey(1, bare);
  }
  final parts = raw.split(':');
  if (parts.length != 2) return null;
  final density = double.tryParse(parts[0]);
  final index = int.tryParse(parts[1]);
  if (density == null ||
      index == null ||
      index < 0 ||
      density == 1 ||
      BeatDensity.fromValue(density).value != density) {
    return null;
  }
  return FourBeatBucketKey(density, index);
}
