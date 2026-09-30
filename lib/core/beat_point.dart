/// 一个拍点：[t] 为秒（浮点），[down] 为强拍标记。
class BeatPoint {
  const BeatPoint({required this.t, required this.down});

  /// 拍时刻（秒）。
  final double t;

  /// 是否强拍（downbeat）。
  final bool down;

  @override
  bool operator ==(Object other) =>
      other is BeatPoint && other.t == t && other.down == down;

  @override
  int get hashCode => Object.hash(t, down);
}
