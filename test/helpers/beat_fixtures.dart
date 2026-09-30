/// 节拍规整测试共用的拍点夹具。
library;

/// 真实相位跳变夹具：稳态 [uniform]（400 拍）+ idx≈100 吞拍 + idx≈339 起
/// 整体后移 0.62s（「染上你的颜色」1:46 型）。
List<Duration> jumpTimes(List<Duration> uniform) {
  final swallowed = <Duration>[
    ...uniform.sublist(0, 100),
    ...uniform.sublist(101),
  ];
  return [
    for (final (i, t) in swallowed.indexed)
      i >= 339 ? t + const Duration(milliseconds: 620) : t,
  ];
}
