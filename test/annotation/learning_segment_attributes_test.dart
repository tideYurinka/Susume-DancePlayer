import 'package:dance_learning_app/annotation/annotation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('熟练度五档：声明次序即高低，数值口径 0–4 由枚举直接给出', () {
    expect(LearningMastery.values, const [
      LearningMastery.unlearned,
      LearningMastery.learning,
      LearningMastery.keepingUp,
      LearningMastery.familiar,
      LearningMastery.mastered,
    ]);
    expect(
      LearningMastery.values.map((mastery) => mastery.index).toList(),
      const [0, 1, 2, 3, 4],
      reason: '百分比 = 段档位值均值 × 25，档位值即枚举数值',
    );
  });

  test('旧三态名读取映射为五档；未知或非法名按未练兜底且不落 Map', () {
    // 旧本地文档三态值（未学 / 练习中 / 已掌握）只在读取时映射。
    expect(learningMasteryFromName('unlearned'), LearningMastery.unlearned);
    expect(learningMasteryFromName('practicing'), LearningMastery.learning);
    expect(learningMasteryFromName('mastered'), LearningMastery.mastered);
    // 新枚举名直接可读（写盘只写新名）。
    expect(learningMasteryFromName('learning'), LearningMastery.learning);
    expect(learningMasteryFromName('keepingUp'), LearningMastery.keepingUp);
    expect(learningMasteryFromName('familiar'), LearningMastery.familiar);
    // 未知/非法值：不落 Map，段读取按稀疏缺省「未练」。
    expect(learningMasteryFromName('unknown-value'), isNull);
    expect(learningMasteryFromName(2), isNull);
    expect(learningMasteryFromName(null), isNull);
    expect(learningSegmentMastery(const {}, 0), LearningMastery.unlearned);
  });

  test('熟练度按段序存储；缺省为未练，重复设置替换旧值', () {
    var mastery = const <int, LearningMastery>{};
    expect(learningSegmentMastery(mastery, 0), LearningMastery.unlearned);

    mastery = withLearningSegmentMastery(mastery, 0, LearningMastery.learning);
    mastery = withLearningSegmentMastery(mastery, 1, LearningMastery.mastered);
    mastery = withLearningSegmentMastery(mastery, 0, LearningMastery.mastered);

    expect(learningSegmentMastery(mastery, 0), LearningMastery.mastered);
    expect(learningSegmentMastery(mastery, 1), LearningMastery.mastered);
    expect(learningSegmentMastery(mastery, 2), LearningMastery.unlearned);
  });

  test('段序为负时属性操作被拒', () {
    expect(
      () => withLearningSegmentMastery(const {}, -1, LearningMastery.learning),
      throwsRangeError,
    );
    expect(
      () => toggleLearningSegmentEmphasis(const <int>{}, -1),
      throwsRangeError,
    );
  });

  test('首/尾区间变化时保留段按裁掉的边界线平移', () {
    var oldTimeline = AnnotationTimeline.wholeVideo(const Duration(minutes: 3));
    oldTimeline = addSegmentLine(oldTimeline, const Duration(seconds: 10));
    oldTimeline = addSegmentLine(oldTimeline, const Duration(seconds: 20));

    final startMovedIntoMiddle = setVideoRangeStart(
      oldTimeline,
      const Duration(seconds: 15),
    );
    expect(
      rangeChangedLearningSegmentOrderMapping(
        oldTimeline,
        startMovedIntoMiddle,
      ),
      {1: 0, 2: 1},
    );

    final endMovedIntoMiddle = setVideoRangeEnd(
      oldTimeline,
      const Duration(seconds: 15),
    );
    expect(
      rangeChangedLearningSegmentOrderMapping(oldTimeline, endMovedIntoMiddle),
      {0: 0, 1: 1},
    );

    var expandedBase = AnnotationTimeline.wholeVideo(
      const Duration(minutes: 3),
    );
    expandedBase = setVideoRangeStart(
      expandedBase,
      const Duration(seconds: 10),
    );
    expandedBase = addSegmentLine(expandedBase, const Duration(seconds: 20));
    expandedBase = addSegmentLine(expandedBase, const Duration(seconds: 40));
    final startExpanded = setVideoRangeStart(expandedBase, Duration.zero);
    expect(
      rangeChangedLearningSegmentOrderMapping(expandedBase, startExpanded),
      {0: 0, 1: 1, 2: 2},
      reason: '首界左扩只是延伸原第一段，不新增段序',
    );
  });

  group('新建分段线切割学习段的双新段继承', () {
    test('熟练度：被切割段的前后两新段均复制原段（五档逐位保留），后续段序后移', () {
      const mastery = <int, LearningMastery>{
        0: LearningMastery.keepingUp,
        1: LearningMastery.familiar,
      };

      // 在 1 号分段线处插线：原学习段 1 被切成新 1/2 两段。
      final split = splitLearningMasteryOnSegmentLineAdded(mastery, 1);

      expect(split, const {
        0: LearningMastery.keepingUp, // 切割点左侧原段不动。
        1: LearningMastery.familiar, // 前半段继承原段。
        2: LearningMastery.familiar, // 后半段继承原段。
        // 原段 2 后移为新 3；未显式设置，缺省「未练」不入 Map（稀疏不变式）。
      });
      expect(learningSegmentMastery(split, 3), LearningMastery.unlearned);
      // 原 Map 不变。
      expect(mastery, const {
        0: LearningMastery.keepingUp,
        1: LearningMastery.familiar,
      });
    });

    test('熟练度：原段未显式设置（未练）时切割后两新段均为未练（缺省）', () {
      const mastery = <int, LearningMastery>{0: LearningMastery.mastered};

      final split = splitLearningMasteryOnSegmentLineAdded(mastery, 0);

      // 原段 0（掌握）切成新 0/1，两段均继承掌握。
      expect(split, const {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
      });
      expect(learningSegmentMastery(split, 2), LearningMastery.unlearned);
    });

    test('熟练度：显式「未练」不被切割复制（稀疏不变式保持不变）', () {
      const mastery = <int, LearningMastery>{1: LearningMastery.unlearned};

      expect(splitLearningMasteryOnSegmentLineAdded(mastery, 1), isEmpty);
    });

    test('重点：被切割段为重点则前后两新段均保留重点，后续段序后移', () {
      const emphasized = {0, 1, 3};

      final split = splitLearningEmphasisOnSegmentLineAdded(emphasized, 1);

      // 原重点段 1 切成新 1/2，均保留；原段 3 后移为新 4。
      expect(split, const {0, 1, 2, 4});
    });

    test('重点：原段无重点时切割后两新段均无重点', () {
      const emphasized = <int>{};

      final split = splitLearningEmphasisOnSegmentLineAdded(emphasized, 0);

      expect(split, isEmpty);
    });

    test('切割线索引为负时被拒', () {
      expect(
        () => splitLearningMasteryOnSegmentLineAdded(const {}, -1),
        throwsRangeError,
      );
      expect(
        () => splitLearningEmphasisOnSegmentLineAdded(const <int>{}, -1),
        throwsRangeError,
      );
    });
  });

  group('删除分段线后的学习段属性融合', () {
    test('熟练度取相邻两段较高者（五档全序），后续段序前移', () {
      const mastery = <int, LearningMastery>{
        1: LearningMastery.learning,
        3: LearningMastery.familiar,
      };

      final merged = mergeLearningMasteryOnSegmentLineRemoved(mastery, 1);

      expect(merged, const {
        // 删除 1 号分段线：原学习段 1/2 融合为新 1；学习中 > 未练。
        1: LearningMastery.learning,
        // 原学习段 3 前移为新 2。
        2: LearningMastery.familiar,
      });
    });

    test('熟练度融合取较高者：较低的相邻段不覆盖较高者', () {
      const mastery = <int, LearningMastery>{
        0: LearningMastery.keepingUp,
        1: LearningMastery.familiar,
        2: LearningMastery.learning,
      };

      final merged = mergeLearningMasteryOnSegmentLineRemoved(mastery, 0);

      expect(merged, const {
        // 段 0/1 融合：较熟（3）> 能跟上（2），取较熟。
        0: LearningMastery.familiar,
        // 原段 2 前移为新 1，不受融合影响。
        1: LearningMastery.learning,
      });
    });

    test('熟练度融合：显式「未练」参与后仍不入 Map（稀疏不变式保持不变）', () {
      const mastery = <int, LearningMastery>{0: LearningMastery.unlearned};

      expect(mergeLearningMasteryOnSegmentLineRemoved(mastery, 0), isEmpty);
    });

    test('任一相邻段为重点则融合段保留重点，后续段序前移', () {
      const emphasized = {0, 2, 3};

      final merged = mergeLearningEmphasisOnSegmentLineRemoved(emphasized, 1);

      expect(merged, const {0, 1, 2});
    });
  });

  group('逐段档随几何变动的重烘焙', () {
    test('插线切割：被切段的快慢两新段均继承原档，后续段序后移', () {
      const densities = <int, double>{0: 0.5, 1: 2.0};

      final split = splitSegmentDensitiesOnSegmentLineAdded(densities, 1);

      // 在 1 号分段线处插线：原段 0 不受影响；原段 1（×2）切成新 1/2
      // 两段，均继承 ×2。
      expect(split, const {0: 0.5, 1: 2.0, 2: 2.0});
      expect(densities, const <int, double>{0: 0.5, 1: 2.0}, reason: '原表不变');
    });

    test('插线：原段无逐段档时切割不产生键（稀疏不变式）；负线索引被拒', () {
      expect(splitSegmentDensitiesOnSegmentLineAdded(const {}, 0), isEmpty);
      expect(
        () => splitSegmentDensitiesOnSegmentLineAdded(const {}, -1),
        throwsRangeError,
      );
    });

    test('删线融合：相邻两段取绝对值最大的一档，后续段序前移', () {
      const densities = <int, double>{0: 2.0, 1: 0.5, 2: 0.5};

      final merged = mergeSegmentDensitiesOnSegmentLineRemoved(densities, 0);

      // 段 0（×2）与段 1（×½）融合：×2 绝对值大 → 融合段 ×2；原段 2 前移。
      expect(merged, const {0: 2.0, 1: 0.5});
    });

    test('删线融合：一侧无档时融合段继承另一侧的档；两侧同档不变', () {
      expect(
        mergeSegmentDensitiesOnSegmentLineRemoved(const {1: 0.5}, 0),
        const {0: 0.5},
      );
      expect(
        mergeSegmentDensitiesOnSegmentLineRemoved(const {0: 2.0}, 0),
        const {0: 2.0},
      );
      expect(
        mergeSegmentDensitiesOnSegmentLineRemoved(const {0: 0.5, 1: 0.5}, 0),
        const {0: 0.5},
      );
    });

    /// 构造 [0, 64s) 上以 [cuts] 切分的分区；无切割线 = 无学习段。
    AnnotationTimeline partition(List<Duration> cuts) =>
        AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 64),
          rangeStart: Duration.zero,
          rangeEnd: const Duration(seconds: 64),
          segmentLines: [for (final cut in cuts) SegmentLine(position: cut)],
        );

    const s16 = Duration(seconds: 16);
    const s32 = Duration(seconds: 32);
    const s40 = Duration(seconds: 40);
    const s48 = Duration(seconds: 48);
    const s56 = Duration(seconds: 56);

    test('自动分段一对一：同位段保留原档', () {
      final result = rebakeSegmentDensities(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s16, s32, s48]),
        densities: const {0: 0.5, 2: 2.0},
      );
      expect(result, const {0: 0.5, 2: 2.0});
    });

    test('自动分段多段相交：取绝对值最大的档，方向并列取更快的一档', () {
      // 新段 [0,32) 与旧段 0（×½）、旧段 1（×2）都相交 → 取 ×2。
      final absMax = rebakeSegmentDensities(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s32]),
        densities: const {0: 0.5, 1: 2.0},
      );
      expect(absMax, const {0: 2.0});

      // 方向并列（相等值）取更快：同值即同档，仍落该档。
      final tie = rebakeSegmentDensities(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s32]),
        densities: const {0: 2.0, 1: 2.0},
      );
      expect(tie, const {0: 2.0});
    });

    test('自动分段无档/越界的段序不残留；一段切两段各继承该档', () {
      // 旧段 0（×½）[0,16)、旧段 1（无档）、旧段 2（×2）[32,48)；新分区
      // [0,16)/[16,32)/[32,40)/[40,48)/[48,64)。
      final result = rebakeSegmentDensities(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s16, s32, s40, s48, s56]),
        densities: const {0: 0.5, 2: 2.0},
      );
      // 新段 0 → ×½；新段 1 无相交旧段带档 → 不落键；新段 2/3 → ×2；
      // 新段 4 落在无档旧段 3 [48,64) 内 → 不落键。
      expect(result, const {0: 0.5, 2: 2.0, 3: 2.0});
    });

    test('触界不算相交（半开区间）；旧/新分区为空时结果为空', () {
      expect(
        rebakeSegmentDensities(
          oldTimeline: partition(const [s32, s48]),
          newTimeline: partition(const [s32]),
          densities: const {0: 0.5, 1: 2.0},
        ),
        const {0: 0.5, 1: 2.0},
        reason:
            '新段 0 [0,32) 与旧段 1 [32,48) 触界不相交 → 只继承旧段 0；'
            '新段 1 [32,64) 与旧段 1 相交 → ×2',
      );
      expect(
        rebakeSegmentDensities(
          oldTimeline: partition(const []),
          newTimeline: partition(const [s32]),
          densities: const {0: 2.0},
        ),
        isEmpty,
      );
      expect(
        rebakeSegmentDensities(
          oldTimeline: partition(const [s32]),
          newTimeline: partition(const []),
          densities: const {0: 2.0},
        ),
        isEmpty,
      );
    });
  });

  group('自动分段整体替换分区后的段序键属性重写', () {
    /// 构造 [0, 64s) 上以 [cuts] 切分的分区；无切割线 = 无学习段。
    AnnotationTimeline partition(List<Duration> cuts) =>
        AnnotationTimeline.normalized(
          videoDuration: const Duration(seconds: 64),
          rangeStart: Duration.zero,
          rangeEnd: const Duration(seconds: 64),
          segmentLines: [for (final cut in cuts) SegmentLine(position: cut)],
        );

    const s8 = Duration(seconds: 8);
    const s16 = Duration(seconds: 16);
    const s20 = Duration(seconds: 20);
    const s24 = Duration(seconds: 24);
    const s30 = Duration(seconds: 30);
    const s32 = Duration(seconds: 32);
    const s40 = Duration(seconds: 40);
    const s48 = Duration(seconds: 48);
    const s56 = Duration(seconds: 56);

    test('一对一：新段与旧段完全同位时逐段保留熟练度与重点', () {
      final oldTimeline = partition(const [s16, s32, s48]);
      final newTimeline = partition(const [s16, s32, s48]);

      final result = rebakeLearningSegmentAttributes(
        oldTimeline: oldTimeline,
        newTimeline: newTimeline,
        mastery: const {
          0: LearningMastery.keepingUp,
          2: LearningMastery.mastered,
        },
        emphasis: const {1, 3},
      );

      expect(result.mastery, const {
        0: LearningMastery.keepingUp,
        2: LearningMastery.mastered,
      });
      expect(result.emphasis, const {1, 3});
    });

    test('一拆多：旧段被切成多个新段时各新段都继承熟练度与重点', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s32]),
        newTimeline: partition(const [s8, s16, s24, s32, s40, s48, s56]),
        mastery: const {0: LearningMastery.mastered},
        emphasis: const {0},
      );

      // 新段 0–3 落在旧段 0 [0,32) 内、新段 4–7 落在旧段 1 [32,64) 内。
      expect(result.mastery, const {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
        2: LearningMastery.mastered,
        3: LearningMastery.mastered,
      });
      expect(result.emphasis, const {0, 1, 2, 3});
    });

    test('多并一：熟练度取相交旧段的最高档，重点取任一为重点', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s32]),
        mastery: const {
          0: LearningMastery.learning,
          1: LearningMastery.familiar,
        },
        emphasis: const {0, 2},
      );

      // 新段 0 = 旧段 0/1 合并 → 取较高者；新段 1 = 旧段 2/3 合并。
      expect(result.mastery, const {0: LearningMastery.familiar});
      expect(result.emphasis, const {0, 1});
    });

    test('部分重叠：只要相交非空就归入，不要求包含关系', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s20]),
        newTimeline: partition(const [Duration(seconds: 10), s30]),
        mastery: const {0: LearningMastery.mastered},
        emphasis: const {1},
      );

      // 新段 1 [10,30) 横跨旧段边界，与旧段 0、旧段 1 都相交。
      expect(result.mastery, const {
        0: LearningMastery.mastered,
        1: LearningMastery.mastered,
      });
      expect(result.emphasis, const {1, 2});
    });

    test('触界不算相交：旧段终点等于新段起点时不继承', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s20, s40]),
        newTimeline: partition(const [s20]),
        mastery: const {
          0: LearningMastery.learning,
          1: LearningMastery.mastered,
        },
        emphasis: const {},
      );

      // 旧段 1 [20,40) 的起点 = 新段 0 [0,20) 的终点 → 不算相交。
      expect(result.mastery, const {
        0: LearningMastery.learning,
        1: LearningMastery.mastered,
      });
    });

    test('旧分区里不存在对应段的段序丢弃（越界键不残留）', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s16, s32, s48]),
        newTimeline: partition(const [s16, s32, s48]),
        mastery: const {
          0: LearningMastery.mastered,
          9: LearningMastery.familiar,
        },
        emphasis: const {9},
      );

      expect(result.mastery, const {0: LearningMastery.mastered});
      expect(result.emphasis, isEmpty);
    });

    test('旧分区为空或新分区为空时都返回空（无异常、无特判）', () {
      final withSegments = partition(const [s16, s32]);

      final emptyOld = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const []),
        newTimeline: withSegments,
        mastery: const {0: LearningMastery.mastered},
        emphasis: const {0},
      );
      expect(emptyOld.mastery, isEmpty);
      expect(emptyOld.emphasis, isEmpty);

      final emptyNew = rebakeLearningSegmentAttributes(
        oldTimeline: withSegments,
        newTimeline: partition(const []),
        mastery: const {0: LearningMastery.mastered},
        emphasis: const {0},
      );
      expect(emptyNew.mastery, isEmpty);
      expect(emptyNew.emphasis, isEmpty);

      final bothEmpty = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const []),
        newTimeline: partition(const []),
        mastery: const {0: LearningMastery.mastered},
        emphasis: const {0},
      );
      expect(bothEmpty.mastery, isEmpty);
      expect(bothEmpty.emphasis, isEmpty);
    });

    test('输出按稀疏约定：显式「未练」不入 Map，重点不会凭空产生', () {
      final result = rebakeLearningSegmentAttributes(
        oldTimeline: partition(const [s16, s32]),
        newTimeline: partition(const [s16, s32]),
        mastery: const {0: LearningMastery.unlearned},
        emphasis: const {},
      );

      expect(result.mastery, isEmpty);
      expect(result.emphasis, isEmpty);
    });
  });
}
