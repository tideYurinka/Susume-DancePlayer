/// **投屏坐标换算**（纯件，零 Flutter、零 IO、零网络）：一档一份副本，于是
/// 「源片上的某一刻」与「这一档副本上的某一刻」之间的换算全收在这里。
///
/// ## 它回答什么
///
/// - 某一档副本的**时间轴原点**（[sourceStartOf]）：范围生效时副本 0 是**首线**、
///   否则是源片 0（复制档明确不收范围，原点也留在 0，见 `cast_range_gate.dart`）；
/// - 某一档副本的**总时长**（[copyDurationOf]）：范围 / 整片按该档倍率换算过来；
/// - **源坐标 → 副本坐标**（[copyPositionOf]）与反向（[sourcePositionOf]）：减
///   原点、按倍率缩放、再钳进目标时间轴；
/// - **换档的续播位置**（[resumePositionOf]）：先回源坐标、把位置钳进这次正在练
///   的学习段，再落到目标档的副本坐标。
///
/// ## 一切输入都在构造那一下给齐
///
/// 输入只有「各档渲染请求 + 本次学习段」；档位与位置是逐次调用的参数。容器、
/// 会话与递出通道一概不进——想验「0.5× 档 + 收窄范围时源第 10 秒是副本哪一秒」
/// 就构造一份请求、问一句，不必先起一条投屏。
///
/// ## 换档为什么要经源坐标
///
/// 两档副本的**原点**可能不同（只勾声音类时，1× 是复制档、不收范围；非 1× 档收
/// 了范围、副本 0 是首线）——按倍率在副本坐标之间直接换算会偏掉一个原点。经过源
/// 坐标这一步，原点差异自然被吸收。
///
/// ## 钳制
///
/// 结果一律钳进 `[0, 目标时长]`：接收端上报的位置可能略带过冲（电视那边的跳转
/// 精度不由我们决定），负读数同样收到零。某一档没有渲染请求时它没有可钳的副本
/// 时长——位置照算（原点按源片 0）。
///
/// ## 不属本件
///
/// 同原点之间的纯缩放（`cast_speed_tier.dart`）、副本原点与副本时长的请求级算术
/// （`cast_range_gate.dart`），以及「哪一档在播、哪些档还没渲好」的运行账
/// （`lib/player/cast_run.dart`）。
library;

import 'cast_range_gate.dart'
    show
        castCopyDurationOf,
        castCopySourceDurationOf,
        castCopySourceStartOf;
import 'cast_render_request.dart' show CastRenderRequest, CastSpeedTier;
import 'cast_speed_tier.dart' show castCopyPosition, castSourcePosition;

/// 一次投屏的坐标换算：各档渲染请求 + 起投那一刻正在练的学习段（源坐标）。
class CastCoordinates {
  const CastCoordinates({this.requests = const {}, this.practiceSpan});

  /// 这次投屏各档的渲染请求（缺哪一档 = 这一档没有副本时长可钳）。
  final Map<CastSpeedTier, CastRenderRequest> requests;

  /// 起投那一刻正在练的**学习段**（源坐标；null = 没在练段）。
  final ({Duration start, Duration end})? practiceSpan;

  /// 某一档的渲染请求；没备这一档时为空。
  CastRenderRequest? requestFor(CastSpeedTier tier) => requests[tier];

  /// 某一档副本的**时间轴原点**落在源坐标上的哪一刻：范围生效 = 首线，否则源片
  /// 0（复制档不收范围，故原点也留在 0）；没有这一档的请求同样是源片 0。
  Duration sourceStartOf(CastSpeedTier tier) {
    final request = requests[tier];
    if (request == null) return Duration.zero;
    return castCopySourceStartOf(request);
  }

  /// 某一档副本的**总时长**；没有这一档的请求、或算出来不是正数时为空（钳制不
  /// 做，位置照算）。
  Duration? copyDurationOf(CastSpeedTier tier) {
    final request = requests[tier];
    if (request == null) return null;
    final copy = castCopyDurationOf(request);
    return copy <= Duration.zero ? null : copy;
  }

  /// **源坐标 → 某一档副本坐标**：减去这一档副本的原点（范围生效时是首线）、按
  /// 倍率缩放、再钳进副本时长。
  Duration copyPositionOf(Duration sourcePosition, CastSpeedTier tier) =>
      castCopyPosition(
        sourcePosition - sourceStartOf(tier),
        tier,
        copyDuration: copyDurationOf(tier),
      );

  /// **某一档副本坐标 → 源坐标**：按倍率换回、加回副本原点。钳制在那一段的**长度**
  /// 上做（长度取自这一档覆盖的源跨度），于是结果不越过尾线。
  Duration sourcePositionOf(Duration copyPosition, CastSpeedTier tier) {
    final request = requests[tier];
    final within = castSourcePosition(
      copyPosition,
      tier,
      sourceDuration: request == null ? null : castCopySourceDurationOf(request),
    );
    return sourceStartOf(tier) + within;
  }

  /// **换档后要跳的位置**：先回到源坐标、把续播位置钳进这次正在练的学习段（段是
  /// 源坐标那一份），再落到目标档的副本坐标——起播等待与接收端的跳转精度都不由
  /// 我们决定，续播落在段外那次练习就白等了。
  Duration resumePositionOf({
    required Duration position,
    required CastSpeedTier from,
    required CastSpeedTier to,
  }) {
    var source = sourcePositionOf(position, from);
    final span = practiceSpan;
    if (span != null) {
      if (source < span.start) source = span.start;
      if (source > span.end) source = span.end;
    }
    return copyPositionOf(source, to);
  }
}
