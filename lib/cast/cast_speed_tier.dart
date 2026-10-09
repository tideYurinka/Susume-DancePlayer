/// **投屏倍速档**的纯件（零 Flutter、零 IO、零网络）：选哪几档、先渲哪一档，
/// 以及**跨档坐标换算**——三档各是一份独立副本，位置与学习段都得按比例
/// 搬过去。
///
/// ## 一档一份副本 ⇒ 一切都是坐标换算
///
/// 倍速不靠接收端（DLNA 没有这门能力），靠**换文件**：0.5 / 0.75 / 1 各渲一份，
/// 切换就是让接收端换一个文件播。于是「换成别的档」有两件事必须算对：
///
/// - **位置**：某个时刻在旧档副本上是第几秒、在新档副本上又是第几秒。
///   装配侧用 `setpts=PTS/rate`（0.5× 档时长翻倍），故
///   `副本位置 = 源位置 ÷ 该档倍率`，反过来 `源位置 = 副本位置 × 该档倍率`，
///   档间是 `新位置 = 旧位置 × 旧率 ÷ 新率`；
/// - **学习段**：段是两端都算一次的两个位置（[castSwitchedSpan]），两端各自
///   钳、起点不越终点——换档不该把一个区间换算成反的。
///
/// ## 边界钳制
///
/// 换算结果一律钳进 `[0, 目标副本时长]`：接收端上报的位置可能略带过冲
/// （电视那边的跳转精度不由我们决定），越界的位置推给接收端会被它回绝。
/// 负位置（坏读数）同样钳到零——**不造出负数时长**。
///
/// ## 副本原点可能是**首线**（`#37`）
///
/// 上面那条 `副本位置 = 源位置 ÷ 该档倍率` 是**副本原点在源片 0** 时的写法。
/// 范围生效时（这支舞设了首尾线，且这一档的视频被重编码）副本自己的时间轴从
/// **首线**起：`副本位置 = (源位置 − 首线) ÷ 该档倍率`，`源位置 = 首线 +
/// 副本位置 × 该档倍率`。坐标换算纯件（`lib/cast/cast_coordinates.dart`）按这个
/// 口径换算，且**跨原点时先经源坐标**；本件这些纯换算与件内其它算术一样都是
/// **同原点**之间的换算——档间换算（[castSwitchedPosition]）因此与原点无关，
/// 前提是两端同原点（不同原点时先回源坐标）。副本原点与副本时长那一份算术在
/// `cast_range_gate.dart` 的 `castCopySourceStartOf` / `castCopyDurationOf`。
///
/// ## 都不勾渲染档 = 只有原片这一档
///
/// 「都不勾 = 直接推原片、零等待」时没有任何副本可换，因此
/// [castSpeedTierPlanFor] 在 `renders == false` 时一律给**单档 1×** 计划：
/// 原片就是那一档，勾别档没有意义（收到别的档却推原片，是要命的谎）。
///
/// ## 不属本件
///
/// 命令装配在 `cast_render_plan.dart`（那里的 `setpts` / `atempo` 与本件的
/// 倍率是同一套算术的两头）；渲染编排在 `cast_render_orchestrator.dart`；
/// 「哪一档在播、哪些档还没渲好」的运行账在 `lib/player/cast_run.dart`。
library;

import 'cast_render_request.dart' show CastSpeedTier;

/// 候选三档（声明次序即界面次序：从慢到快）。
const List<CastSpeedTier> kCastSpeedTierCandidates = CastSpeedTier.values;

/// 档位文案（下拉与按钮上那三个记号）。逐档唯一。
String castSpeedTierLabel(CastSpeedTier tier) => '${tier.token}×';

/// 与 [rate] 最接近的一档；**平局取较慢那一档**（宁可慢一点，抠动作更稳），
/// 非有限读数兜到 1×。
CastSpeedTier nearestCastSpeedTier(double rate) {
  if (!rate.isFinite) return CastSpeedTier.full;
  return _nearestAmong(rate, kCastSpeedTierCandidates);
}

/// 默认勾选：只勾最接近的那一档（面板打开时的初值）。
Set<CastSpeedTier> defaultCastSpeedTiersFor(double rate) => {
  nearestCastSpeedTier(rate),
};

/// 这一次投屏的**档计划**：要备哪几档、先渲哪一档。
class CastSpeedTierPlan {
  const CastSpeedTierPlan({required this.tiers, required this.startTier});

  /// 单档计划（原片那条路与老调用方的取值形状：只有一档，起投就是它）。
  CastSpeedTierPlan.single(CastSpeedTier tier)
    : this(tiers: [tier], startTier: tier);

  /// 要备的档（声明次序、至少一档）。
  final List<CastSpeedTier> tiers;

  /// 先渲的那一档 = **起投档**（它渲好即开投，其余档在后台接着渲）。
  final CastSpeedTier startTier;

  /// 起投档之外、还要后台渲的档（声明次序）。
  List<CastSpeedTier> get pending => [
    for (final tier in tiers)
      if (tier != startTier) tier,
  ];

  @override
  String toString() =>
      'CastSpeedTierPlan(tiers: ${tiers.map((t) => t.token).join(',')}, '
      'start: ${startTier.token})';
}

/// 由「勾了哪几档」算出档计划。
///
/// - [renders] 为假（都不勾渲染档）= 只有原片这一档，勾了什么一律不算；
/// - [selected] 为空 = 退回「与 [manualRate] 最接近的那一档」，投屏总有一份
///   可播；
/// - [startTier] 只在**选中的档**里挑最接近 [manualRate] 的那一档——手动倍率
///   1× 而只勾了 0.5× 时，起投档就是 0.5×（当前手动倍率落在没勾的档上，
///   没有意义）。
CastSpeedTierPlan castSpeedTierPlanFor({
  required bool renders,
  required double manualRate,
  Set<CastSpeedTier> selected = const {},
}) {
  if (!renders) return CastSpeedTierPlan.single(CastSpeedTier.full);
  final chosen = selected.isEmpty
      ? defaultCastSpeedTiersFor(manualRate)
      : selected;
  final tiers = [
    for (final tier in kCastSpeedTierCandidates)
      if (chosen.contains(tier)) tier,
  ];
  return CastSpeedTierPlan(
    tiers: tiers,
    startTier: _nearestAmong(manualRate, tiers),
  );
}

/// 该档副本的时长：`setpts=PTS/rate` 的直接后果（0.5× 档时长翻倍）。
Duration castCopyDuration(Duration sourceDuration, CastSpeedTier tier) =>
    _scale(sourceDuration, 1 / tier.rate);

/// **源坐标 → 该档副本坐标**（[copyDuration] 非空时钳进该档副本时长）。
Duration castCopyPosition(
  Duration sourcePosition,
  CastSpeedTier tier, {
  Duration? copyDuration,
}) => castSwitchedPosition(
  position: sourcePosition,
  from: CastSpeedTier.full,
  to: tier,
  newCopyDuration: copyDuration,
);

/// **该档副本坐标 → 源坐标**（[sourceDuration] 非空时钳进源时长）。
Duration castSourcePosition(
  Duration copyPosition,
  CastSpeedTier tier, {
  Duration? sourceDuration,
}) => castSwitchedPosition(
  position: copyPosition,
  from: tier,
  to: CastSpeedTier.full,
  newCopyDuration: sourceDuration,
);

/// **档间换算**：`新位置 = 旧位置 × 旧率 ÷ 新率`，再钳进 `[0, 新档副本时长]`
/// （[newCopyDuration] 非空时）。
Duration castSwitchedPosition({
  required Duration position,
  required CastSpeedTier from,
  required CastSpeedTier to,
  Duration? newCopyDuration,
}) => _clamp(_scale(position, from.rate / to.rate), newCopyDuration);

/// **学习段随档换算**：两端各按位置换算，起点不越终点（两端都越界时退化成一个
/// 点，不造出反向区间）。返回的是闭区间两端的取值。
({Duration start, Duration end}) castSwitchedSpan({
  required Duration start,
  required Duration end,
  required CastSpeedTier from,
  required CastSpeedTier to,
  Duration? newCopyDuration,
}) {
  final head = castSwitchedPosition(
    position: start,
    from: from,
    to: to,
    newCopyDuration: newCopyDuration,
  );
  final tail = castSwitchedPosition(
    position: end,
    from: from,
    to: to,
    newCopyDuration: newCopyDuration,
  );
  return head <= tail ? (start: head, end: tail) : (start: tail, end: tail);
}

/// 在给定的一组档里挑最接近 [rate] 的一档：按传入次序比较，**距离相等保留
/// 先遇到的那个**（调用方按声明次序传 = 平局取较慢）。非有限读数取该组里
/// 最后（最快）那一档。
CastSpeedTier _nearestAmong(double rate, List<CastSpeedTier> tiers) {
  if (!rate.isFinite) return tiers.last;
  var best = tiers.first;
  var bestDistance = (best.rate - rate).abs();
  for (final tier in tiers.skip(1)) {
    final distance = (tier.rate - rate).abs();
    if (distance < bestDistance) {
      best = tier;
      bestDistance = distance;
    }
  }
  return best;
}

/// 按倍率缩放一个时长；负值与零一律给零（坏输入不造出负数时长）。
Duration _scale(Duration value, double factor) {
  if (value <= Duration.zero) return Duration.zero;
  final micros = value.inMicroseconds * factor;
  if (!micros.isFinite || micros <= 0) return Duration.zero;
  return Duration(microseconds: micros.round());
}

/// 钳进 `[0, limit]`（[limit] 为空只钳下界；limit 本身不是正数时给零）。
Duration _clamp(Duration value, Duration? limit) {
  var result = value < Duration.zero ? Duration.zero : value;
  if (limit != null && result > limit) {
    result = limit < Duration.zero ? Duration.zero : limit;
  }
  return result;
}
