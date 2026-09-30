/// 练习片段表代数纯件：撤销/重做共用的逐 id
/// 三方合并、本次编辑碰过的 id 集合、表规范化（源起点升序 + 两两不重叠）。
/// 与 [PracticeClip] 模型同侧的零框架纯件——不引 Flutter、不读状态容器、
/// 不持 IO，可在不启动 widget 环境的情况下直测。
library;

import 'compare_materials.dart';
import 'interval_fragment_row.dart';

/// 逐 id 三方合并的结果：回放后的表 + 被跳过的 id（当前值与 `after` 不符、
/// 视为外部写过的 id），供上游判断；本纯件不弹提示。
class PracticeClipTableMergeResult {
  const PracticeClipTableMergeResult({
    required this.clips,
    required this.skippedIds,
  });

  /// 回放后的片段表。
  final List<PracticeClip> clips;

  /// 因外部写过而被跳过（未回放）的片段 id——仅指当前表里有该 id、值与
  /// `after` 不符的主循环冲突；复活分支的冲突（`after` 仍有、当前表已无）
  /// 不计入——当前表本就没有该 id 可跳。
  final Set<String> skippedIds;
}

/// 撤销/重做共用的唯一回放语义：以历史条目的快照对（`before` / `after`）
/// 为变更、以当前表为目标——仅当 `当前[id] == after[id]` 时写 `before[id]`
/// （`before` 无该 id = 移除）；`当前[id] != after[id]` 视为外部写过 →
/// 跳过该 id。未碰过的 id 原样保留；复活（当前表与 `after` 都没有、
/// `before` 有的 id）追加在表尾。相等语义按 [PracticeClip] 既有相等。
PracticeClipTableMergeResult replayClipTableBySnapshotPair({
  required List<PracticeClip> before,
  required List<PracticeClip> after,
  required List<PracticeClip> current,
}) {
  final beforeById = _byId(before);
  final afterById = _byId(after);
  final currentById = _byId(current);

  final result = <PracticeClip>[];
  final skipped = <String>{};
  for (final clip in current) {
    if (!beforeById.containsKey(clip.id) && !afterById.containsKey(clip.id)) {
      result.add(clip);
      continue;
    }
    if (beforeById[clip.id] == afterById[clip.id]) {
      result.add(clip);
      continue;
    }
    if (clip != afterById[clip.id]) {
      skipped.add(clip.id);
      result.add(clip);
      continue;
    }
    final restored = beforeById[clip.id];
    if (restored != null) result.add(restored);
  }

  // 复活：当前表与 `after` 一致地没有该 id（缺席相等）、`before` 有的
  // 碰过 id。`after` 仍有的 id 而当前表没有 = 该 id 被外部写过（删）→
  // 冲突跳过，不复活。
  for (final clip in before) {
    if (!currentById.containsKey(clip.id) &&
        !afterById.containsKey(clip.id) &&
        beforeById[clip.id] != afterById[clip.id]) {
      result.add(clip);
    }
  }

  return PracticeClipTableMergeResult(
    clips: result,
    skippedIds: Set.unmodifiable(skipped),
  );
}

/// 本次编辑碰过的 id = `before` 与 `after` 有差异的 id（含出现/缺席的
/// 差异；相等语义按 [PracticeClip] 既有相等）。
Set<String> clipIdsTouchedByEdit({
  required List<PracticeClip> before,
  required List<PracticeClip> after,
}) {
  final beforeById = _byId(before);
  final afterById = _byId(after);
  return {
    for (final id in {...beforeById.keys, ...afterById.keys})
      if (beforeById[id] != afterById[id]) id,
  };
}

/// 表规范化：按源起点升序；两两不重叠——重叠口径沿用入轨同一套纯函数
/// [pruneClipOverlappedBy]（被完全覆盖的删、部分重叠的裁到不重叠、裁后
/// 无单一不重叠区间的删），升序遍历逐条入轨、后条对已收条目裁让，不新造
/// 判据。返回新表（不改传入对象）。
List<PracticeClip> normalizePracticeClipTable(List<PracticeClip> clips) {
  final sorted = [...clips]
    ..sort((a, b) => a.sourceStartMs.compareTo(b.sourceStartMs));
  final result = <PracticeClip>[];
  for (final clip in sorted) {
    var candidate = clip;
    var covered = false;
    for (final kept in result) {
      final pruned = pruneClipOverlappedBy(
        candidate,
        IntervalSpan(startMs: kept.sourceStartMs, endMs: kept.sourceEndMs),
      );
      if (pruned == null) {
        covered = true;
        break;
      }
      candidate = pruned;
    }
    if (!covered) result.add(candidate);
  }
  return result;
}

Map<String, PracticeClip> _byId(List<PracticeClip> clips) => {
      for (final clip in clips) clip.id: clip,
    };
