/// 打开播放时带的方案参数：详情页「打开续播」与
/// 首页卡片都不带参数，方案区的每一行各带自己那一份——点一行即以那份方案
/// 进入播放。播放器里不提供方案切换。
///
/// 本模块只回答「这次打开用哪一份组员方案」（null = 我的标注方案）；装载它
/// 时的只读门禁归标注编辑模块，落位与熟练度归打开恢复接线。首页卡片派生量
/// 恒取我的方案，不经本模块。
library;

import '../annotation/learning_segment_attributes.dart' show LearningMastery;
import '../persistence/member_scheme_store.dart';

/// 打开播放时携带的方案参数。
sealed class SchemeOpen {
  const SchemeOpen();
}

/// 不带方案参数：恒用我的标注方案，没有例外（——我的方案为空也不
/// 改用组员方案）。
class AutoSchemeOpen extends SchemeOpen {
  const AutoSchemeOpen();
}

/// 以我的标注方案打开（可写）。方案区「我的标注」那一行是它的入口。
class MySchemeOpen extends SchemeOpen {
  const MySchemeOpen();
}

/// 以某个组员方案打开（只读）。
class MemberSchemeOpen extends SchemeOpen {
  const MemberSchemeOpen(this.schemeId);

  /// 目标组员方案标识。
  final String schemeId;
}

/// 打开参数 → 这次打开用哪一份组员方案：null = 用我的标注方案。标识已不
/// 存在（那条方案被删）时同样回落我的。
MemberSchemeRecord? resolveOpenedMemberScheme({
  required SchemeOpen open,
  required List<MemberSchemeRecord> schemes,
}) => switch (open) {
  MySchemeOpen() => null,
  AutoSchemeOpen() => null,
  MemberSchemeOpen(:final schemeId) => _schemeById(schemes, schemeId),
};

MemberSchemeRecord? _schemeById(
  List<MemberSchemeRecord> schemes,
  String schemeId,
) {
  for (final scheme in schemes) {
    if (scheme.schemeId == schemeId) return scheme;
  }
  return null;
}

/// 组员方案熟练度快照 → 熟练度读面装载值：档位数值按枚举序映射，越界档丢弃
/// （宁丢不显示错档）；未随包（null）按空表装载、按未练显示——不装载会让
/// 上一支舞的档位残留到组员方案的段上，被误读成队友的进度。
Map<int, LearningMastery> masteryFromSnapshot(Map<int, int>? snapshot) {
  if (snapshot == null) return const {};
  return {
    for (final entry in snapshot.entries)
      if (entry.value >= 0 && entry.value < LearningMastery.values.length)
        entry.key: LearningMastery.values[entry.value],
  };
}
