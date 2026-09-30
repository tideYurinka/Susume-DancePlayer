/// 学习段属性（会话内存态）。
///
/// 学习段几何实时派生，不在此重复存储；属性按段序 `order` 索引。缺省值为
/// 「未练」且未置「重点」，因此稀疏 Map/Set 只保存用户显式设置过的段。
///
///  分层：[LearningMastery] 与熟练度 Map 属于本地私密侧
/// （落盘见 `persistence/local_document.dart`）；「重点」段序集合属于
/// 公开标记侧（落盘见 `persistence/marker_document.dart`）。激活状态另行建模。
library;

import '../core/learning_mastery.dart';
import 'annotation_timeline.dart';
import 'learning_segments.dart';

export '../core/learning_mastery.dart';

/// 档位显示名（五档）：播放器标注工具区与舞详情段行共用同一份文案。
String learningMasteryLabel(LearningMastery mastery) => switch (mastery) {
  LearningMastery.unlearned => '未练',
  LearningMastery.learning => '学习中',
  LearningMastery.keepingUp => '能跟上',
  LearningMastery.familiar => '较熟',
  LearningMastery.mastered => '掌握',
};

/// 读取持久化熟练度名（含旧三态别名）；未知或非法名返回 null。
///
/// 新五档名直接可读；旧三态本地文档值只在读取时映射，不迁移、不报错：
/// 未学 → 未练、已掌握 → 掌握（与第 0/4 档同名，按枚举名命中）、
/// 练习中 → 学习中（唯一换名的档位，见 [_legacyMasteryNames]）。写盘只写
/// [LearningMastery.name]，故本函数是单向读取面；返回 null 表示该段无有效
/// 值——读取面按稀疏缺省「未练」兜底，且不落进 Map。
LearningMastery? learningMasteryFromName(Object? name) {
  if (name is! String) return null;
  for (final mastery in LearningMastery.values) {
    if (mastery.name == name) return mastery;
  }
  return _legacyMasteryNames[name];
}

/// 旧三态文件值 → 五档枚举（只读，不参与写盘）：只声明真正换名的档位。
const Map<String, LearningMastery> _legacyMasteryNames = {
  'practicing': LearningMastery.learning,
};

void _checkOrder(int order) {
  if (order < 0) {
    throw RangeError.range(order, 0, null, 'order', '学习段段序不能为负');
  }
}

/// 读取段序熟练度；未显式设置时返回「未练」。
LearningMastery learningSegmentMastery(
  Map<int, LearningMastery> values,
  int order,
) {
  _checkOrder(order);
  return values[order] ?? LearningMastery.unlearned;
}

/// 返回设置某段熟练度后的新 Map；原 Map 不变。
Map<int, LearningMastery> withLearningSegmentMastery(
  Map<int, LearningMastery> values,
  int order,
  LearningMastery mastery,
) {
  _checkOrder(order);
  if (values[order] == mastery) return Map.unmodifiable(values);
  return Map.unmodifiable({...values, order: mastery});
}

/// 返回把全部给定段序设为同一档后的新 Map；原 Map 不变。
///
/// 批量写：熟练度一次作用在全部选中段上。[orders] 为空 → 原样
/// 返回；全部给定段已是该档 → 同一实例（EditNoop 判定据此成立）。
Map<int, LearningMastery> withLearningSegmentsMastery(
  Map<int, LearningMastery> values,
  Iterable<int> orders,
  LearningMastery mastery,
) {
  final targets = orders.toList()..sort();
  if (targets.isEmpty) return Map.unmodifiable(values);
  for (final order in targets) {
    _checkOrder(order);
  }
  if (targets.every((order) => values[order] == mastery)) {
    return Map.unmodifiable(values);
  }
  return Map.unmodifiable({
    ...values,
    for (final order in targets) order: mastery,
  });
}

/// 段内档显示名（×2 / ×½ / 原样）：工具槽读数用。
String segmentDensityLabel(double density) {
  if (density == 2) return '×2';
  if (density == 0.5) return '×½';
  return '原样';
}

/// 返回把全部给定段序的段内档**赋值**为 [density] 后的新 Map；原 Map 不变。
///
/// 赋值语义：三枚赋值钮都是设值不是步进——
/// 连按不叠乘；多段档位不一时按一下即整片统一为同一档。[density] == 1
/// （回到原样）即删键（稀疏约定：原样不入 Map）。[orders] 为空 → 原样返回；
/// 全部给定段已是该档 → 同一实例（EditNoop 判定据此成立，按钮保持可点、
/// 按下无变化）。非法档值抛 [ArgumentError]。
Map<int, double> withLearningSegmentsDensity(
  Map<int, double> values,
  Iterable<int> orders,
  double density,
) {
  if (density != 0.5 && density != 1 && density != 2) {
    throw ArgumentError.value(density, 'density', '段内档只有 ×½ / 1 / ×2');
  }
  final targets = orders.toList()..sort();
  if (targets.isEmpty) return Map.unmodifiable(values);
  for (final order in targets) {
    _checkOrder(order);
  }
  if (targets.every((order) => (values[order] ?? 1) == density)) {
    return Map.unmodifiable(values);
  }
  final next = {...values};
  for (final order in targets) {
    if (density == 1) {
      next.remove(order);
    } else {
      next[order] = density;
    }
  }
  return Map.unmodifiable(next);
}

/// 返回切换某段「重点」后的新集合；原集合不变。
Set<int> toggleLearningSegmentEmphasis(Set<int> orders, int order) {
  _checkOrder(order);
  return Set.unmodifiable(
    orders.contains(order)
        ? orders.where((value) => value != order)
        : {...orders, order},
  );
}

/// 切换全部给定段序的「重点」：全有星则全部取消、否则全部点亮。
///
/// 批量写：重点一次作用在全部选中段上。原集合不变；[orders]
/// 为空 → 原样返回。
Set<int> toggleLearningSegmentsEmphasis(
  Set<int> orders,
  Iterable<int> selectedOrders,
) {
  final targets = selectedOrders.toSet();
  if (targets.isEmpty) return Set.unmodifiable(orders);
  for (final order in targets) {
    _checkOrder(order);
  }
  final allEmphasized = targets.every(orders.contains);
  return Set.unmodifiable(
    allEmphasized
        ? orders.where((order) => !targets.contains(order))
        : {...orders, ...targets},
  );
}

/// 新学习段插入 [at] 后的旧段序 → 新段序映射（未出现的新段为默认值）。
Map<int, int> insertedLearningSegmentOrderMapping(int oldCount, int at) {
  if (oldCount < 0) {
    throw RangeError.range(oldCount, 0, null, 'oldCount', '学习段数量不能为负');
  }
  if (at < 0 || at > oldCount) {
    throw RangeError.range(at, 0, oldCount, 'at');
  }
  return {for (var i = 0; i < oldCount; i++) i: i < at ? i : i + 1};
}

/// 首/尾区间变化后的旧段序 → 新段序映射；被裁掉的段不出现。
///
/// 区间扩张只在首/尾追加默认段；区间收缩按被裁掉的 Prefix/Suffix 段平移，
/// 避免练习进度误贴到另一段。内部拖动不改变段数，映射为恒等。
Map<int, int> rangeChangedLearningSegmentOrderMapping(
  AnnotationTimeline oldTimeline,
  AnnotationTimeline newTimeline,
) {
  final oldCount = oldTimeline.segmentLines.isEmpty
      ? 0
      : oldTimeline.segmentLines.length + 1;
  if (oldCount == 0 || newTimeline.segmentLines.isEmpty) return const {};
  final removedPrefixLines = oldTimeline.segmentLines
      .where((line) => line.position < newTimeline.rangeStart)
      .length;
  final removedSuffixLines = oldTimeline.segmentLines
      .where((line) => line.position >= newTimeline.rangeEnd)
      .length;
  final removedPrefix = removedPrefixLines;
  final removedSuffix = removedSuffixLines;
  return {
    for (var i = removedPrefix; i < oldCount - removedSuffix; i++)
      i: i - removedPrefix,
  };
}

/// 按段序映射重排 Map；映射外的旧值丢弃，新段保持缺省。
Map<int, V> remapLearningSegmentOrders<V>(
  Map<int, V> values,
  Map<int, int> orderMapping,
) {
  final remapped = <int, V>{};
  for (final entry in orderMapping.entries) {
    final value = values[entry.key];
    if (value != null) remapped[entry.value] = value;
  }
  return Map.unmodifiable(remapped);
}

/// 按段序映射重排重点集合。
Set<int> remapLearningSegmentEmphasis(
  Set<int> orders,
  Map<int, int> orderMapping,
) {
  return Set.unmodifiable({
    for (final entry in orderMapping.entries)
      if (orders.contains(entry.key)) entry.value,
  });
}

/// 分区重写结果：重写后的熟练度全表与重点集合。
typedef RebakedLearningSegmentAttributes = ({
  Map<int, LearningMastery> mastery,
  Set<int> emphasis,
});

/// 自动分段整体替换分区后，按旧新分段的**时间重叠**重写段序键属性。
///
/// 规则（见词条「自动分段」，本函数是唯一事实源）：新段的熟练度取与之相交
/// （半开区间 `[start, end)`，相交非空）的全部旧段中的**最高档**；重点为
/// 「任一相交旧段为重点」。一个旧段被切成多个新段时各新段都继承；多个旧段
/// 并进一个新段时取最高／取并集。旧分区里不存在对应新段的段序丢弃；输出
/// 沿用稀疏约定（「未练」不入 Map）。无旧分区或无新分区时结果为空——不抛
/// 异常、不特判。
RebakedLearningSegmentAttributes rebakeLearningSegmentAttributes({
  required AnnotationTimeline oldTimeline,
  required AnnotationTimeline newTimeline,
  required Map<int, LearningMastery> mastery,
  required Set<int> emphasis,
}) {
  final oldSegments = deriveLearningSegments(oldTimeline);
  final newSegments = deriveLearningSegments(newTimeline);
  if (oldSegments.isEmpty || newSegments.isEmpty) {
    return (mastery: const {}, emphasis: const {});
  }
  final rebakedMastery = <int, LearningMastery>{};
  final rebakedEmphasis = <int>{};
  for (final newSegment in newSegments) {
    LearningMastery? best;
    var emphasized = false;
    for (final oldSegment in oldSegments) {
      if (!_segmentsOverlap(oldSegment, newSegment)) continue;
      final value = mastery[oldSegment.order];
      if (value != null && (best == null || value.index > best.index)) {
        best = value;
      }
      if (emphasis.contains(oldSegment.order)) emphasized = true;
    }
    if (best != null && best != LearningMastery.unlearned) {
      rebakedMastery[newSegment.order] = best;
    }
    if (emphasized) rebakedEmphasis.add(newSegment.order);
  }
  return (
    mastery: Map.unmodifiable(rebakedMastery),
    emphasis: Set.unmodifiable(rebakedEmphasis),
  );
}

/// 半开区间相交判定：触界（一段终点 = 另一段起点）不算相交。
bool _segmentsOverlap(LearningSegment a, LearningSegment b) =>
    a.start < b.end && b.start < a.end;

/// 新建分段线切割学习段：前后两新段均复制原段熟练度，后续段序后移。
///
/// 仅适用于**段内切割**（「分段」入口保证新线严格位于开区间内、右侧必有
/// 原学习段）：[insertedLineIndex] 为新分段线的索引；其右侧原学习段（段序 =
/// [insertedLineIndex]）被切成新段序 [insertedLineIndex] 与
/// [insertedLineIndex] + 1 两段，两段熟练度均等于原段（不取「仅一侧继承」
/// 或「取较高者」）；切割点左侧原段段序不变，右侧其余段序 +1。与删除融合
/// 一致保持稀疏存储：显式「未练」不入结果 Map。
Map<int, LearningMastery> splitLearningMasteryOnSegmentLineAdded(
  Map<int, LearningMastery> values,
  int insertedLineIndex,
) {
  _checkNonNegativeLineIndex(insertedLineIndex, 'insertedLineIndex');
  final split = <int, LearningMastery>{};
  for (final MapEntry(key: order, value: mastery) in values.entries) {
    if (order <= insertedLineIndex) {
      split[order] = mastery;
      if (order == insertedLineIndex) split[order + 1] = mastery;
    } else {
      split[order + 1] = mastery;
    }
  }
  split.removeWhere((_, mastery) => mastery == LearningMastery.unlearned);
  return Map.unmodifiable(split);
}

/// 新建分段线切割学习段：前后两新段均继承原段逐段档（见词条「段内倍频」），
/// 后续段序后移。
///
/// 仅适用于**段内切割**，段序语义同 [splitLearningMasteryOnSegmentLineAdded]；
/// 存储同为稀疏约定（无档不入 Map）。
Map<int, double> splitSegmentDensitiesOnSegmentLineAdded(
  Map<int, double> values,
  int insertedLineIndex,
) {
  _checkNonNegativeLineIndex(insertedLineIndex, 'insertedLineIndex');
  final split = <int, double>{};
  for (final MapEntry(key: order, value: density) in values.entries) {
    if (order <= insertedLineIndex) {
      split[order] = density;
      if (order == insertedLineIndex) split[order + 1] = density;
    } else {
      split[order + 1] = density;
    }
  }
  return Map.unmodifiable(split);
}

/// 删除分段线后融合相邻学习段：取两段中**绝对值最大**的逐段档（与自动
/// 分段的时间重叠重烘焙同一比较口径，不新增第四条规则），后续段序前移。
Map<int, double> mergeSegmentDensitiesOnSegmentLineRemoved(
  Map<int, double> values,
  int removedLineIndex,
) {
  _checkRemovedLineIndex(removedLineIndex);
  final merged = <int, double>{};
  for (final entry in values.entries) {
    final order = entry.key;
    final density = entry.value;
    if (order < removedLineIndex) {
      merged[order] = density;
    } else if (order == removedLineIndex || order == removedLineIndex + 1) {
      final current = merged[removedLineIndex];
      if (current == null || _fasterDensity(density, current)) {
        merged[removedLineIndex] = density;
      }
    } else {
      merged[order - 1] = density;
    }
  }
  return Map.unmodifiable(merged);
}

/// 方向并列取更快的一档：绝对值大者胜；绝对值相等时取数值大者（×2 比
/// ×½ 快）。
bool _fasterDensity(double a, double b) =>
    a.abs() > b.abs() || (a.abs() == b.abs() && a > b);

/// 自动分段整体替换分区后，按旧新分段的**时间重叠**重写逐段档表
/// （规则唯一事实源，与
/// [rebakeLearningSegmentAttributes] 同一条先例）：新段的段内档取与之
/// 相交（半开区间，相交非空）的全部旧段中**绝对值最大**的档、方向并列取
/// 更快的一档；不相交的旧段档丢弃；一个旧段被切成多个新段时各新段都
/// 继承。无旧分区或无新分区时结果为空——不抛异常、不特判。
Map<int, double> rebakeSegmentDensities({
  required AnnotationTimeline oldTimeline,
  required AnnotationTimeline newTimeline,
  required Map<int, double> densities,
}) {
  final oldSegments = deriveLearningSegments(oldTimeline);
  final newSegments = deriveLearningSegments(newTimeline);
  if (oldSegments.isEmpty || newSegments.isEmpty) return const {};
  final rebaked = <int, double>{};
  for (final newSegment in newSegments) {
    double? best;
    for (final oldSegment in oldSegments) {
      if (!_segmentsOverlap(oldSegment, newSegment)) continue;
      final value = densities[oldSegment.order];
      if (value != null && (best == null || _fasterDensity(value, best))) {
        best = value;
      }
    }
    if (best != null) rebaked[newSegment.order] = best;
  }
  return Map.unmodifiable(rebaked);
}

/// 新建分段线切割学习段：前后两新段均复制原段重点，后续段序后移。
///
/// 仅适用于**段内切割**，语义同 [splitLearningMasteryOnSegmentLineAdded]。
Set<int> splitLearningEmphasisOnSegmentLineAdded(
  Set<int> orders,
  int insertedLineIndex,
) {
  _checkNonNegativeLineIndex(insertedLineIndex, 'insertedLineIndex');
  return Set.unmodifiable({
    for (final order in orders)
      if (order < insertedLineIndex)
        order
      else if (order == insertedLineIndex) ...[order, order + 1]
      else
        order + 1,
  });
}

/// 删除分段线后融合相邻学习段：熟练度取两段中较高者，后续段序前移。
Map<int, LearningMastery> mergeLearningMasteryOnSegmentLineRemoved(
  Map<int, LearningMastery> values,
  int removedLineIndex,
) {
  _checkRemovedLineIndex(removedLineIndex);
  final merged = <int, LearningMastery>{};
  for (final entry in values.entries) {
    final order = entry.key;
    final mastery = entry.value;
    if (order < removedLineIndex) {
      merged[order] = mastery;
    } else if (order == removedLineIndex || order == removedLineIndex + 1) {
      final current = merged[removedLineIndex];
      if (current == null || mastery.index > current.index) {
        merged[removedLineIndex] = mastery;
      }
    } else {
      merged[order - 1] = mastery;
    }
  }
  merged.removeWhere((_, mastery) => mastery == LearningMastery.unlearned);
  return Map.unmodifiable(merged);
}

/// 删除分段线后融合相邻学习段：任一段为重点则保留，后续段序前移。
Set<int> mergeLearningEmphasisOnSegmentLineRemoved(
  Set<int> orders,
  int removedLineIndex,
) {
  _checkRemovedLineIndex(removedLineIndex);
  return Set.unmodifiable({
    for (final order in orders)
      if (order < removedLineIndex)
        order
      else if (order == removedLineIndex || order == removedLineIndex + 1)
        removedLineIndex
      else
        order - 1,
  });
}

void _checkRemovedLineIndex(int index) =>
    _checkNonNegativeLineIndex(index, 'removedLineIndex');

void _checkNonNegativeLineIndex(int index, String name) {
  if (index < 0) {
    throw RangeError.range(index, 0, null, name, '分段线索引不能为负');
  }
}
