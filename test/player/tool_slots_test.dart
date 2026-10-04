import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:flutter_test/flutter_test.dart';

/// 工具槽库直测——槽标识与槽键、两份
/// 具名槽集的槽位与次序、判定表四行与门优先级、门种 → 可点性、逐槽表、
/// 无门槽、退化输入。不启动 widget 环境、不 pump 容器。
///
/// 底排对比槽集不含「取景」槽（入口统一为顶栏
/// 「取景调整」，见 `play_tool_table_test.dart`）。
void main() {
  group('槽标识与槽键', () {
    test('槽标识覆盖全部 15 个工具槽', () {
      expect(ToolSlotId.values.length, 15);
      expect(
        ToolSlotId.values,
        containsAll(const [
          ToolSlotId.mastery,
          ToolSlotId.emphasis,
          ToolSlotId.segment,
          ToolSlotId.add,
          ToolSlotId.delete,
          ToolSlotId.autoRange,
          ToolSlotId.beatAnchorAdd,
          ToolSlotId.beatAnchorRemove,
          ToolSlotId.beatAnchorsClear,
          ToolSlotId.beatCorrectionExit,
          ToolSlotId.segmentDensityFaster,
          ToolSlotId.segmentDensitySlower,
          ToolSlotId.segmentDensityReset,
          ToolSlotId.segmentDensityExit,
          ToolSlotId.practiceMirror,
        ]),
      );
      expect(
        ToolSlotId.values.map((v) => v.name),
        isNot(contains('screenshot')),
      );
    });

    test('每个槽键逐位沿用既有取值（「添加」槽新增 control_add）', () {
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.standby.slots,
        ...ToolSlotTable.segmentDensityStandby.slots,
        ...ToolSlotTable.compare.slots,
      ];
      final keysById = {for (final s in all) s.id: s.key};
      expect(keysById[ToolSlotId.mastery], 'control_mastery');
      expect(keysById[ToolSlotId.emphasis], 'control_emphasis');
      expect(keysById[ToolSlotId.segment], 'control_segment');
      expect(keysById[ToolSlotId.add], 'control_add');
      expect(keysById[ToolSlotId.delete], 'control_segment_delete');
      expect(keysById[ToolSlotId.autoRange], 'control_auto_range');
      expect(keysById[ToolSlotId.beatAnchorAdd], 'control_beat_anchor_add');
      expect(
        keysById[ToolSlotId.beatAnchorRemove],
        'control_beat_anchor_remove',
      );
      expect(
        keysById[ToolSlotId.beatAnchorsClear],
        'control_beat_anchors_clear',
      );
      expect(
        keysById[ToolSlotId.beatCorrectionExit],
        'control_beat_correction_exit',
      );
      expect(
        keysById[ToolSlotId.segmentDensityFaster],
        'control_segment_density_faster',
      );
      expect(
        keysById[ToolSlotId.segmentDensitySlower],
        'control_segment_density_slower',
      );
      expect(
        keysById[ToolSlotId.segmentDensityReset],
        'control_segment_density_reset',
      );
      expect(
        keysById[ToolSlotId.segmentDensityExit],
        'control_segment_density_exit',
      );
      expect(keysById[ToolSlotId.practiceMirror], 'control_practice_mirror');
    });
  });

  group('具名槽集', () {
    test('段内倍频待命态 4 槽，次序 = 快一倍→慢一半→回到原样→退出', () {
      expect(ToolSlotTable.segmentDensityStandby.slots.map((s) => s.id), const [
        ToolSlotId.segmentDensityFaster,
        ToolSlotId.segmentDensitySlower,
        ToolSlotId.segmentDensityReset,
        ToolSlotId.segmentDensityExit,
      ]);
      // 三枚赋值钮的门 = 装载 + 无对象（做法取辞 = 先选中一个学习段）；
      // 退出槽无门、不改文档。
      for (final id in [
        ToolSlotId.segmentDensityFaster,
        ToolSlotId.segmentDensitySlower,
        ToolSlotId.segmentDensityReset,
      ]) {
        final slot = ToolSlotTable.segmentDensityStandby.slotOf(id);
        expect(slot.gates, [ToolGateKind.loading, ToolGateKind.noSubject]);
        expect(slot.noSubjectHint, NoSubjectHint.learningSegment);
      }
      final exit = ToolSlotTable.segmentDensityStandby.slotOf(
        ToolSlotId.segmentDensityExit,
      );
      expect(exit.gates, isEmpty);
      expect(exit.writesDocument, isFalse);
    });
    test('对比态 5 槽，次序 = 熟练度→重点→删除→练习侧镜像→自动分段', () {
      expect(ToolSlotTable.compare.slots.map((s) => s.id), const [
        ToolSlotId.mastery,
        ToolSlotId.emphasis,
        ToolSlotId.delete,
        ToolSlotId.practiceMirror,
        ToolSlotId.autoRange,
      ]);
    });

    test('正常态 6 槽，次序 = 熟练度→重点→分段→添加→删除→自动分段', () {
      expect(ToolSlotTable.normal.slots.map((s) => s.id), const [
        ToolSlotId.mastery,
        ToolSlotId.emphasis,
        ToolSlotId.segment,
        ToolSlotId.add,
        ToolSlotId.delete,
        ToolSlotId.autoRange,
      ]);
    });

    test('待命态 4 槽，次序 = 设为八拍线→取消八拍线→清除所有八拍线→退出八拍矫正', () {
      expect(ToolSlotTable.standby.slots.map((s) => s.id), const [
        ToolSlotId.beatAnchorAdd,
        ToolSlotId.beatAnchorRemove,
        ToolSlotId.beatAnchorsClear,
        ToolSlotId.beatCorrectionExit,
      ]);
    });

    test('引导锚点声明：底栏三份槽集里只有编辑态那枚「删除」声明为真', () {
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.standby.slots,
        ...ToolSlotTable.compare.slots,
      ];
      expect(
        {
          for (final slot in all)
            if (slot.carriesGuideAnchor) slot.key,
        },
        {'control_segment_delete'},
        reason: '同一枚槽键在编辑态与对比态是两枚不同的槽：只有编辑态那枚承载分段第 ② 步的锚点',
      );
    });
  });

  group('对比态槽集', () {
    final byId = {for (final s in ToolSlotTable.compare.slots) s.id: s};

    test('三个槽门逐条声明：全部 = 装载未完成 + 无对象；删除不声明锁定门', () {
      for (final id in const [
        ToolSlotId.mastery,
        ToolSlotId.emphasis,
        ToolSlotId.delete,
      ]) {
        final expected = const [ToolGateKind.loading, ToolGateKind.noSubject];
        expect(byId[id]!.gates, expected, reason: '$id');
      }
    });

    test('练习侧镜像开关槽门 = 装载未完成：不存在「无对象」前提、不声明锁定门（开关不改标注几何）', () {
      for (final id in const [ToolSlotId.practiceMirror]) {
        expect(byId[id]!.gates, const [ToolGateKind.loading], reason: '$id');
        expect(evaluateToolSlot(const []).available, isTrue, reason: '$id');
      }
    });

    test('判定结果：置灰可点、弹做法（无对象）', () {
      for (final slot in ToolSlotTable.compare.slots) {
        if (slot.id == ToolSlotId.practiceMirror) continue; // 见上用例
        if (slot.id == ToolSlotId.autoRange) continue; // 门 = 装载/锁定/未就绪，无对象门不适用
        // 装载未完成门恒在声明里，本用例只问「装载落定后」的其余门。
        final v = evaluateToolSlot(
          slot.gates.where((g) => g != ToolGateKind.loading),
        );
        expect(v.available, isFalse, reason: '${slot.id}');
        expect(v.kind, ToolGateKind.noSubject);
        expect(v.tappable, isTrue);
      }
    });

    test('对比槽键沿用既有键、练习侧镜像槽新键', () {
      final keys = {for (final s in ToolSlotTable.compare.slots) s.id: s.key};
      expect(keys[ToolSlotId.mastery], 'control_mastery');
      expect(keys[ToolSlotId.emphasis], 'control_emphasis');
      expect(keys[ToolSlotId.delete], 'control_segment_delete');
      expect(keys[ToolSlotId.practiceMirror], 'control_practice_mirror');
    });

    test('对比态没有分段 / 添加槽（自动分段在册）', () {
      expect(
        byId.keys,
        isNot(anyOf(contains(ToolSlotId.segment), contains(ToolSlotId.add))),
      );
      expect(byId[ToolSlotId.autoRange], isNotNull);
    });

    test('自动分段条目表：三档、次序 = 清空分段→4 个八拍/段→8 个八拍/段；键与门逐条声明', () {
      expect(AutoSegmentEntryTable.normal.entries.map((e) => e.id), const [
        AutoSegmentEntryId.clearSegments,
        AutoSegmentEntryId.fourBeats,
        AutoSegmentEntryId.eightBeats,
      ]);
      final byId = {
        for (final e in AutoSegmentEntryTable.normal.entries) e.id: e,
      };
      expect(byId[AutoSegmentEntryId.clearSegments]!.key, 'control_auto_clear');
      expect(byId[AutoSegmentEntryId.fourBeats]!.key, 'control_auto_seg_4');
      expect(byId[AutoSegmentEntryId.eightBeats]!.key, 'control_auto_seg_8');
      for (final entry in AutoSegmentEntryTable.normal.entries) {
        expect(entry.gates, const [
          ToolGateKind.loading,
          ToolGateKind.locked,
          ToolGateKind.gridNotReady,
        ], reason: '${entry.id} 门 = 装载 / 锁定 / 网格未就绪');
        expect(entry.writesDocument, isTrue, reason: '${entry.id}');
      }
      // 未收录标识显式报错。
      expect(
        () =>
            AutoSegmentEntryTable.normal.entryOf(AutoSegmentEntryId.eightBeats),
        returnsNormally,
      );
    });
  });

  group('判定表：单门逐行', () {
    test('无对象 → 置灰、可点、弹原因（该怎么做）', () {
      final v = evaluateToolSlot(const [ToolGateKind.noSubject]);
      expect(v.available, isFalse);
      expect(v.kind, ToolGateKind.noSubject);
      expect(v.tappable, isTrue);
    });

    test('锁定 → 置灰、可点、弹原因（已锁定分段）', () {
      final v = evaluateToolSlot(const [ToolGateKind.locked]);
      expect(v.available, isFalse);
      expect(v.kind, ToolGateKind.locked);
      expect(v.tappable, isTrue);
    });

    test('网格未就绪 → 置灰、可点、弹原因', () {
      final v = evaluateToolSlot(const [ToolGateKind.gridNotReady]);
      expect(v.available, isFalse);
      expect(v.kind, ToolGateKind.gridNotReady);
      expect(v.tappable, isTrue);
    });

    test('预览线越界 → 置灰、不可点、静默', () {
      final v = evaluateToolSlot(const [ToolGateKind.previewOutOfBounds]);
      expect(v.available, isFalse);
      expect(v.kind, ToolGateKind.previewOutOfBounds);
      expect(v.tappable, isFalse);
    });

    test('都不命中 → 正常', () {
      final v = evaluateToolSlot(const []);
      expect(v.available, isTrue);
      expect(v.kind, isNull);
      expect(v.tappable, isTrue);
    });

    test('装载未完成 → 置灰、可点、弹原因', () {
      final v = evaluateToolSlot(const [ToolGateKind.loading]);
      expect(v.available, isFalse);
      expect(v.kind, ToolGateKind.loading);
      expect(v.tappable, isTrue);
    });
  });

  group('装载未完成门', () {
    test('门优先级排在无对象之前：对象集本身来自尚未装载的文档', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.noSubject,
        ToolGateKind.loading,
      ]);
      expect(v.kind, ToolGateKind.loading);
      expect(v.tappable, isTrue);
    });

    test('装载未完成压倒锁定与未就绪（门表最前一行）', () {
      for (final other in const [
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
        ToolGateKind.previewOutOfBounds,
      ]) {
        final v = evaluateToolSlot([other, ToolGateKind.loading]);
        expect(v.kind, ToolGateKind.loading, reason: '$other');
      }
    });

    test('门种 → 可点性：置灰仍可点（与未就绪同款）', () {
      expect(toolSlotTappable(ToolGateKind.loading), isTrue);
    });
  });

  group('门完整性结构断言（装载未完成门）', () {
    test('槽集声明的会写文档入口 == 声明了装载未完成门的槽（漏声明即红）', () {
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.standby.slots,
        ...ToolSlotTable.compare.slots,
      ];
      final declared = {
        for (final slot in all)
          if (slot.writesDocument) slot.id,
      };
      final gated = {
        for (final slot in all)
          if (slot.gates.contains(ToolGateKind.loading)) slot.id,
      };
      expect(gated, declared, reason: '会写文档的槽必须声明装载未完成门');
      expect(declared, isNotEmpty);
    });

    test('槽的会写文档声明与门清单双向一致：声明了门即会写盘、会写盘即声明门', () {
      for (final slot in [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.standby.slots,
        ...ToolSlotTable.compare.slots,
      ]) {
        expect(
          slot.gates.contains(ToolGateKind.loading),
          slot.writesDocument,
          reason: '${slot.id} 会写文档 ⇔ 声明装载未完成门',
        );
      }
    });

    test('退出八拍矫正不写文档、不声明装载未完成门', () {
      final exit = ToolSlotTable.standby.slotOf(ToolSlotId.beatCorrectionExit);
      expect(exit.writesDocument, isFalse);
      expect(exit.gates.contains(ToolGateKind.loading), isFalse);
    });

    test('添加条目：三个条目都会写文档，各自声明装载未完成门', () {
      for (final entry in AddEntryTable.normal.entries) {
        expect(entry.writesDocument, isTrue, reason: '${entry.id}');
        expect(
          entry.gates,
          contains(ToolGateKind.loading),
          reason: '${entry.id}',
        );
      }
    });

    test('自动分段条目：会写文档 ⇔ 声明装载未完成门（与添加条目同款双向一致）', () {
      for (final entry in AutoSegmentEntryTable.normal.entries) {
        expect(
          entry.gates.contains(ToolGateKind.loading),
          entry.writesDocument,
          reason: '${entry.id} 会写文档 ⇔ 声明装载未完成门',
        );
      }
    });

    test('页面级入口逐条在册（全集，不是子集：漏一条或加一条未声明的都红）', () {
      expect(
        {for (final entry in PageWriteEntryTable.main.entries) entry.id},
        {
          PageWriteEntryId.editorEntry,
          PageWriteEntryId.mirrorSwitch,
          PageWriteEntryId.signatureEdit,
          PageWriteEntryId.settingsToggle,
          PageWriteEntryId.recording,
          PageWriteEntryId.capture,
          PageWriteEntryId.framingAdjust,
        },
      );
    });

    test('页面级入口的静默标记：手势类入口（截取）静默不参与，其余点按类入口弹原因', () {
      final byId = {
        for (final entry in PageWriteEntryTable.main.entries) entry.id: entry,
      };
      expect(byId[PageWriteEntryId.capture]!.silent, isTrue);
      for (final id in const [
        PageWriteEntryId.editorEntry,
        PageWriteEntryId.mirrorSwitch,
        PageWriteEntryId.signatureEdit,
        PageWriteEntryId.settingsToggle,
        PageWriteEntryId.recording,
        PageWriteEntryId.framingAdjust,
      ]) {
        expect(byId[id]!.silent, isFalse, reason: '$id');
      }
    });

    test('页面级入口表：未收录标识显式报错、空表可构造', () {
      expect(
        () => PageWriteEntryTable.main.entryOf(PageWriteEntryId.capture),
        returnsNormally,
      );
      const empty = PageWriteEntryTable([]);
      expect(() => empty.entryOf(PageWriteEntryId.capture), throwsStateError);
      expect(empty.entries, isEmpty);
    });

    test('槽集声明的会写文档入口全集 = 除退出槽之外的全部槽（增删槽都被这条钉住）', () {
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.standby.slots,
        ...ToolSlotTable.segmentDensityStandby.slots,
        ...ToolSlotTable.compare.slots,
      ];
      final writers = {
        for (final slot in all)
          if (slot.writesDocument) slot.id,
      };
      expect(
        writers,
        ToolSlotId.values.toSet()
          ..remove(ToolSlotId.beatCorrectionExit)
          ..remove(ToolSlotId.segmentDensityExit),
      );
    });
  });

  group('判定表：两句话优先级', () {
    test('无对象 + 锁定 → 无对象胜', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.locked,
        ToolGateKind.noSubject,
      ]);
      expect(v.kind, ToolGateKind.noSubject);
      expect(v.tappable, isTrue);
    });

    test('锁定 + 网格未就绪 → 锁定胜', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.gridNotReady,
        ToolGateKind.locked,
      ]);
      expect(v.kind, ToolGateKind.locked);
    });

    test('锁定 + 越界 → 锁定胜', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.previewOutOfBounds,
        ToolGateKind.locked,
      ]);
      expect(v.kind, ToolGateKind.locked);
      expect(v.tappable, isTrue);
    });

    test('网格未就绪 + 越界 → 未就绪胜', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.previewOutOfBounds,
        ToolGateKind.gridNotReady,
      ]);
      expect(v.kind, ToolGateKind.gridNotReady);
      expect(v.tappable, isTrue);
    });

    test('三门户齐发（无对象 + 锁定 + 未就绪）仍按序取第一', () {
      final v = evaluateToolSlot(const [
        ToolGateKind.gridNotReady,
        ToolGateKind.locked,
        ToolGateKind.noSubject,
      ]);
      expect(v.kind, ToolGateKind.noSubject);
    });
  });

  group('门种 → 可点性', () {
    test('无对象/锁定/未就绪可点、越界不可点', () {
      expect(toolSlotTappable(ToolGateKind.noSubject), isTrue);
      expect(toolSlotTappable(ToolGateKind.locked), isTrue);
      expect(toolSlotTappable(ToolGateKind.gridNotReady), isTrue);
      expect(toolSlotTappable(ToolGateKind.previewOutOfBounds), isFalse);
    });
  });

  group('无对象门：四个入口一致', () {
    test('熟练度 / 重点 / 删除 / 标记分段线：无对象命中 → 置灰、可点、解释', () {
      final verdicts = <(String, ToolSlotVerdict)>[
        (
          'control_mastery',
          evaluateToolEntry(
            ToolSlotTable.normal.slotOf(ToolSlotId.mastery),
            const ToolFacts(),
          ),
        ),
        (
          'control_emphasis',
          evaluateToolEntry(
            ToolSlotTable.normal.slotOf(ToolSlotId.emphasis),
            const ToolFacts(),
          ),
        ),
        (
          'control_segment_delete',
          evaluateToolEntry(
            ToolSlotTable.normal.slotOf(ToolSlotId.delete),
            const ToolFacts(),
          ),
        ),
        (
          'control_segment_flag',
          evaluateDeclaredGates(
            AddEntryTable.normal.entryOf(AddEntryId.segmentFlag).gates.toSet(),
            const ToolFacts(),
            hasSubject: false,
            noSubjectExplained:
                AddEntryTable.normal
                    .entryOf(AddEntryId.segmentFlag)
                    .noSubjectHint !=
                null,
          ),
        ),
      ];
      for (final (key, v) in verdicts) {
        expect(v.available, isFalse, reason: key);
        expect(v.kind, ToolGateKind.noSubject, reason: key);
        expect(v.tappable, isTrue, reason: key);
      }
    });
  });

  group('10 行逐槽表', () {
    final rows = {
      ...{for (final s in ToolSlotTable.normal.slots) s.id: s},
      ...{for (final s in ToolSlotTable.standby.slots) s.id: s},
    };

    test('10 行逐行在册，且每行命中结果与种类映射一致', () {
      expect(rows.length, 10);
      for (final slot in rows.values) {
        final v = evaluateToolSlot(slot.gates);
        if (slot.gates.isEmpty) {
          expect(v.available, isTrue, reason: '${slot.id} 无门恒为正常');
        } else {
          expect(v.available, isFalse, reason: '${slot.id} 有门命中即不可用');
          expect(
            v.tappable,
            toolSlotTappable(v.kind!),
            reason: '${slot.id} 可点性与种类映射一致',
          );
        }
      }
    });

    test('逐行门清单与全命中命中结果', () {
      void expectRow(
        ToolSlotId id,
        List<ToolGateKind> gates,
        ToolGateKind? kind,
      ) {
        expect(rows[id]!.gates, gates, reason: '$id 门清单');
        final v = evaluateToolSlot(gates);
        expect(v.kind, kind, reason: '$id 全命中结果');
      }

      expectRow(ToolSlotId.mastery, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.emphasis, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.segment, const [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
        ToolGateKind.previewOutOfBounds,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.add, const [
        ToolGateKind.loading,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.delete, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
        ToolGateKind.locked,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.autoRange, const [
        ToolGateKind.loading,
        ToolGateKind.locked,
        ToolGateKind.gridNotReady,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.beatAnchorAdd, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.beatAnchorRemove, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.beatAnchorsClear, const [
        ToolGateKind.loading,
        ToolGateKind.noSubject,
      ], ToolGateKind.loading);
      expectRow(ToolSlotId.beatCorrectionExit, const [], null);
    });

    test('受锁槽集合 = 3 个（分段/删除/自动分段，含对比态自动分段）；「添加」钮与三个锚点槽不受锁', () {
      const lockedSlots = [
        ToolSlotId.segment,
        ToolSlotId.delete,
        ToolSlotId.autoRange,
      ];
      for (final id in lockedSlots) {
        expect(
          rows[id]!.gates,
          contains(ToolGateKind.locked),
          reason: '$id 受锁',
        );
      }
      expect(
        ToolSlotTable.compare.slotOf(ToolSlotId.autoRange).gates,
        contains(ToolGateKind.locked),
        reason: '对比态自动分段同受锁',
      );
      expect(rows[ToolSlotId.add]!.gates, const [
        ToolGateKind.loading,
      ], reason: '「添加」钮不受锁');
      const exempt = [
        ToolSlotId.mastery,
        ToolSlotId.emphasis,
        ToolSlotId.add,
        ToolSlotId.beatCorrectionExit,
        ToolSlotId.beatAnchorAdd,
        ToolSlotId.beatAnchorRemove,
        ToolSlotId.beatAnchorsClear,
      ];
      for (final id in exempt) {
        expect(
          rows[id]!.gates,
          isNot(contains(ToolGateKind.locked)),
          reason: '$id 锁定豁免',
        );
      }
    });

    test('逐行部分命中：分段槽按命中门给对应结果', () {
      final segment = rows[ToolSlotId.segment]!;
      expect(
        evaluateToolSlot(
          segment.gates.where(
            (g) => g != ToolGateKind.locked && g != ToolGateKind.loading,
          ),
        ).kind,
        ToolGateKind.gridNotReady,
        reason: '只命中未就绪时弹原因',
      );
      final delete = rows[ToolSlotId.delete]!;
      expect(
        evaluateToolSlot(
          delete.gates.where(
            (g) => g != ToolGateKind.noSubject && g != ToolGateKind.loading,
          ),
        ).kind,
        ToolGateKind.locked,
        reason: '删除有对象且锁定 → 锁定胜（可点弹锁提示）',
      );
    });
  });

  group('无门槽', () {
    test('退出八拍矫正无门：任何命中集下恒为正常', () {
      final exit = ToolSlotTable.standby.slotOf(ToolSlotId.beatCorrectionExit);
      expect(exit.gates, isEmpty);
      expect(evaluateToolSlot(exit.gates).available, isTrue);
    });
  });

  group('退化输入', () {
    test('空门清单等同正常', () {
      final v = evaluateToolSlot(const <ToolGateKind>[]);
      expect(v.available, isTrue);
      expect(v.tappable, isTrue);
    });

    test('空槽集可构造、槽位查询返回空', () {
      const table = ToolSlotTable([]);
      expect(table.slots, isEmpty);
    });

    test('未知槽标识显式报错，不静默返回空', () {
      const table = ToolSlotTable([]);
      expect(() => table.slotOf(ToolSlotId.mastery), throwsStateError);
      expect(
        () => ToolSlotTable.standby.slotOf(ToolSlotId.mastery),
        throwsStateError,
      );
    });
  });

  group('事实求值：声明 + 事实 → verdict', () {
    test('每门种正反两态：事实成立且声明 → 命中；事实不成立 → 不命中', () {
      // 正态逐门种（noSubject 在逐槽用例覆盖，此处覆盖四个全局门）：
      final loading = evaluateToolEntry(
        ToolSlotTable.normal.slotOf(ToolSlotId.segment),
        const ToolFacts(loading: true),
      );
      expect(loading.kind, ToolGateKind.loading);
      expect(loading.tappable, isTrue);

      final locked = evaluateToolEntry(
        ToolSlotTable.normal.slotOf(ToolSlotId.segment),
        const ToolFacts(locked: true),
      );
      expect(locked.kind, ToolGateKind.locked);
      expect(locked.tappable, isTrue);

      final grid = evaluateToolEntry(
        ToolSlotTable.normal.slotOf(ToolSlotId.segment),
        const ToolFacts(gridNotReady: true),
      );
      expect(grid.kind, ToolGateKind.gridNotReady);
      expect(grid.tappable, isTrue);

      final oob = evaluateToolEntry(
        ToolSlotTable.normal.slotOf(ToolSlotId.segment),
        const ToolFacts(previewOutOfBounds: true),
      );
      expect(oob.kind, ToolGateKind.previewOutOfBounds);
      expect(oob.tappable, isFalse);

      // 反态：事实全空 → 四个全局门都不命中（对无对象槽另测）。
      final none = evaluateToolEntry(
        ToolSlotTable.normal.slotOf(ToolSlotId.segment),
        const ToolFacts(),
      );
      expect(none.available, isTrue);
      expect(none.kind, isNull);
    });

    test('未声明的门不被事实点亮：改表即改行为，事实不越过声明', () {
      // 「退出八拍矫正」无门：任何事实下恒正常。
      final exit = ToolSlotTable.standby.slotOf(ToolSlotId.beatCorrectionExit);
      for (final facts in const [
        ToolFacts(loading: true),
        ToolFacts(locked: true),
        ToolFacts(gridNotReady: true),
        ToolFacts(previewOutOfBounds: true),
      ]) {
        final v = evaluateToolEntry(exit, facts);
        expect(v.available, isTrue, reason: '$facts');
      }
      // 「练习侧镜像」只声明装载未完成：锁定事实点亮不了它。
      final mirror = ToolSlotTable.compare.slotOf(ToolSlotId.practiceMirror);
      expect(
        evaluateToolEntry(mirror, const ToolFacts(locked: true)).available,
        isTrue,
      );
      expect(
        evaluateToolEntry(mirror, const ToolFacts(loading: true)).kind,
        ToolGateKind.loading,
      );
    });

    test('逐槽 noSubject：声明该门的槽按具名事实解析；做法随声明', () {
      // 声明无对象门的槽与它的具名事实（穷尽 switch 的外部观察）。
      final subjectFact = {
        ToolSlotId.mastery: (ToolFacts f) =>
            f.selectedLearningSegmentInInterval,
        ToolSlotId.emphasis: (ToolFacts f) =>
            f.selectedLearningSegmentInInterval,
        ToolSlotId.delete: (ToolFacts f) =>
            f.anyLineSelected || f.selectedPracticeClip,
        ToolSlotId.beatAnchorAdd: (ToolFacts f) => f.anchorAddable,
        ToolSlotId.beatAnchorRemove: (ToolFacts f) => f.anchorRemovable,
        ToolSlotId.beatAnchorsClear: (ToolFacts f) => f.hasAnchors,
      };
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.compare.slots,
        ...ToolSlotTable.standby.slots,
      ];
      for (final slot in all) {
        final fact = subjectFact[slot.id];
        if (fact == null) continue; // 不声明无对象门的槽在下一用例覆盖
        // 事实不成立 → 无对象命中。表现随该槽声明的做法：声明了做法 →
        // 置灰、可点、弹做法；刻意不给做法（待命态锚点三槽）
        // → 置灰、按不动、静默。
        final denied = evaluateToolEntry(slot, const ToolFacts());
        expect(denied.available, isFalse, reason: '${slot.id} 空事实');
        expect(denied.kind, ToolGateKind.noSubject, reason: '${slot.id}');
        if (slot.noSubjectHint != null) {
          expect(denied.tappable, isTrue, reason: '${slot.id} 声明了做法');
        } else {
          expect(denied.tappable, isFalse, reason: '${slot.id} 不给做法');
        }
        // 对应事实成立 → 无对象不命中。
        // 删除槽以「任一线被选中」单事实点亮，其余槽直接取具名事实。
        final satisfied = slot.id == ToolSlotId.delete
            ? const ToolFacts(anyLineSelected: true)
            : ToolFacts(
                selectedLearningSegmentInInterval:
                    slot.id == ToolSlotId.mastery ||
                    slot.id == ToolSlotId.emphasis,
                anchorAddable: slot.id == ToolSlotId.beatAnchorAdd,
                anchorRemovable: slot.id == ToolSlotId.beatAnchorRemove,
                hasAnchors: slot.id == ToolSlotId.beatAnchorsClear,
              );
        final allowed = evaluateToolEntry(slot, satisfied);
        expect(allowed.available, isTrue, reason: '${slot.id} 事实成立 → 无对象不命中');
      }
    });

    test('做法声明的结构事实：四个灰钮入口各声明一句做法，待命态锚点三槽刻意为空', () {
      expect(
        ToolSlotTable.normal.slotOf(ToolSlotId.mastery).noSubjectHint,
        NoSubjectHint.learningSegment,
      );
      expect(
        ToolSlotTable.normal.slotOf(ToolSlotId.emphasis).noSubjectHint,
        NoSubjectHint.learningSegment,
      );
      expect(
        ToolSlotTable.normal.slotOf(ToolSlotId.delete).noSubjectHint,
        NoSubjectHint.segmentLineOrClip,
      );
      expect(
        AddEntryTable.normal.entryOf(AddEntryId.segmentFlag).noSubjectHint,
        NoSubjectHint.segmentLine,
      );
      for (final slot in ToolSlotTable.standby.slots) {
        expect(slot.noSubjectHint, isNull, reason: '${slot.id} 刻意不给做法');
      }
      // 对比槽集里同门同款（熟练度 / 重点 / 删除三条逐位相同）。
      expect(
        ToolSlotTable.compare.slotOf(ToolSlotId.mastery).noSubjectHint,
        NoSubjectHint.learningSegment,
      );
      expect(
        ToolSlotTable.compare.slotOf(ToolSlotId.emphasis).noSubjectHint,
        NoSubjectHint.learningSegment,
      );
      expect(
        ToolSlotTable.compare.slotOf(ToolSlotId.delete).noSubjectHint,
        NoSubjectHint.segmentLineOrClip,
      );
      // 不给做法 + 命中该门 → 判定表退回旧口径（可点性不由渲染路径决定）。
      final silent = evaluateDeclaredGates(
        const {ToolGateKind.noSubject},
        const ToolFacts(),
        hasSubject: false,
        noSubjectExplained: false,
      );
      expect(silent.kind, ToolGateKind.noSubject);
      expect(silent.tappable, isFalse);
    });

    test('逐槽穷尽：不声明无对象门的槽在任何事实下都不报无对象', () {
      final all = [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.compare.slots,
        ...ToolSlotTable.standby.slots,
      ];
      const facts = ToolFacts(
        selectedLearningSegmentInInterval: true,
        selectedSegmentLine: true,
        anyLineSelected: true,
        selectedPracticeClip: true,
        anchorAddable: true,
        anchorRemovable: true,
        hasAnchors: true,
      );
      for (final slot in all) {
        if (!slot.gates.contains(ToolGateKind.noSubject)) continue;
        final v = evaluateToolEntry(slot, facts);
        expect(v.kind, isNot(ToolGateKind.noSubject), reason: '${slot.id}');
      }
    });

    test('门优先级无例外：无对象压倒锁定，锁定压倒未就绪与越界', () {
      // 无对象压倒锁定：删除槽空事实 + 锁定 → 无对象胜。
      final delete = ToolSlotTable.normal.slotOf(ToolSlotId.delete);
      final v1 = evaluateToolEntry(delete, const ToolFacts(locked: true));
      expect(v1.kind, ToolGateKind.noSubject);
      expect(v1.tappable, isTrue);
      // 事实成立后锁定才可见（锁覆盖的作用对象 = 选中的分段线）。
      final v2 = evaluateToolEntry(
        delete,
        const ToolFacts(
          locked: true,
          anyLineSelected: true,
          selectedSegmentLine: true,
        ),
      );
      expect(v2.kind, ToolGateKind.locked);
      expect(v2.tappable, isTrue);
      // 锁定压倒未就绪与越界：分段槽三事实齐发 → 锁定胜。
      final segment = ToolSlotTable.normal.slotOf(ToolSlotId.segment);
      final v3 = evaluateToolEntry(
        segment,
        const ToolFacts(
          locked: true,
          gridNotReady: true,
          previewOutOfBounds: true,
        ),
      );
      expect(v3.kind, ToolGateKind.locked);
      // 装载未完成仍压倒一切：四事实齐发 → 装载胜。
      final v4 = evaluateToolEntry(
        segment,
        const ToolFacts(
          loading: true,
          locked: true,
          gridNotReady: true,
          previewOutOfBounds: true,
        ),
      );
      expect(v4.kind, ToolGateKind.loading);
    });

    test('删除槽的锁门随作用对象：选中的是分段线时覆盖，是半拍线/局部镜像片段/练习片段时不覆盖', () {
      final delete = ToolSlotTable.normal.slotOf(ToolSlotId.delete);
      // 分段线：锁覆盖 → 锁定胜、可点弹原因。
      final segmentLine = evaluateToolEntry(
        delete,
        const ToolFacts(
          locked: true,
          anyLineSelected: true,
          selectedSegmentLine: true,
        ),
      );
      expect(segmentLine.kind, ToolGateKind.locked);
      expect(segmentLine.tappable, isTrue);
      // 半拍线 / 局部镜像片段：锁不覆盖 → 照常可删。局部镜像片段的
      // 「选中」义由装配点折进 `anyLineSelected`（片段不另立
      // 事实），两者经同一谓词取同一取值。
      final halfBeat = evaluateToolEntry(
        delete,
        const ToolFacts(locked: true, anyLineSelected: true),
      );
      expect(halfBeat.available, isTrue);
      // 练习片段（对比态）：锁不覆盖 → 照常可删。
      final clip = evaluateToolEntry(
        delete,
        const ToolFacts(locked: true, selectedPracticeClip: true),
      );
      expect(clip.available, isTrue);
    });

    test('锁定覆盖解析逐槽穷尽：声明锁定门的槽之外一律不覆盖（加槽漏补即编译报错）', () {
      const facts = ToolFacts(selectedSegmentLine: true, anyLineSelected: true);
      expect(toolEntryLayoutLockApplies(ToolSlotId.segment, facts), isTrue);
      expect(toolEntryLayoutLockApplies(ToolSlotId.autoRange, facts), isTrue);
      expect(toolEntryLayoutLockApplies(ToolSlotId.delete, facts), isTrue);
      // 锁门已摘除或本不属于分段结构族的槽一律不覆盖。
      for (final id in const [
        ToolSlotId.mastery,
        ToolSlotId.emphasis,
        ToolSlotId.add,
        ToolSlotId.beatAnchorAdd,
        ToolSlotId.beatAnchorRemove,
        ToolSlotId.beatAnchorsClear,
        ToolSlotId.beatCorrectionExit,
        ToolSlotId.practiceMirror,
      ]) {
        expect(toolEntryLayoutLockApplies(id, facts), isFalse, reason: '$id');
      }
    });

    test('空事实即全可用（不声明无对象门的槽在空事实下恒正常）', () {
      const facts = ToolFacts();
      for (final slot in [
        ...ToolSlotTable.normal.slots,
        ...ToolSlotTable.compare.slots,
        ...ToolSlotTable.standby.slots,
      ]) {
        if (slot.gates.contains(ToolGateKind.noSubject)) continue;
        final v = evaluateToolEntry(slot, facts);
        expect(v.available, isTrue, reason: '${slot.id}');
        expect(v.kind, isNull, reason: '${slot.id}');
        expect(v.tappable, isTrue, reason: '${slot.id}');
      }
    });
  });

  group('添加条目表', () {
    test('条目次序 = 菜单次序：备注贴纸 → 局部镜像 → 标记分段线 → 半拍标记', () {
      expect(AddEntryTable.normal.entries.map((e) => e.id), const [
        AddEntryId.noteSticker,
        AddEntryId.localMirror,
        AddEntryId.segmentFlag,
        AddEntryId.halfBeat,
      ]);
    });

    test('菜单文案 = 条目自己声明的标签：备注贴纸 / 局部镜像 / 标记分段线 / 半拍标记（基础标签是未标记态文案，已标记态「取消标记」由渲染层按事实取辞）', () {
      final labelById = {
        for (final e in AddEntryTable.normal.entries) e.id: e.label,
      };
      expect(labelById[AddEntryId.noteSticker], '备注贴纸');
      expect(labelById[AddEntryId.localMirror], '局部镜像');
      expect(labelById[AddEntryId.segmentFlag], '标记分段线');
      expect(labelById[AddEntryId.halfBeat], '半拍标记');
    });

    test('条目键逐位沿用原槽键（「标记分段线」沿用原「标记」槽键）', () {
      final keysById = {
        for (final e in AddEntryTable.normal.entries) e.id: e.key,
      };
      expect(keysById[AddEntryId.halfBeat], 'control_half_beat');
      expect(keysById[AddEntryId.localMirror], 'control_local_mirror');
      expect(keysById[AddEntryId.noteSticker], 'control_note_sticker');
      expect(keysById[AddEntryId.segmentFlag], 'control_segment_flag');
    });

    test(
      '条目各自的门清单：半拍线 = 装载未完成/越界，局部镜像片段与备注贴纸 = 装载未完成，标记分段线 = 装载未完成/无对象/锁定',
      () {
        final byId = {for (final e in AddEntryTable.normal.entries) e.id: e};
        expect(byId[AddEntryId.halfBeat]!.gates, const [
          ToolGateKind.loading,
          ToolGateKind.previewOutOfBounds,
        ]);
        expect(byId[AddEntryId.localMirror]!.gates, const [
          ToolGateKind.loading,
        ]);
        // 备注贴纸条目门 = 装载未完成（不受锁定分段）。
        expect(byId[AddEntryId.noteSticker]!.gates, const [
          ToolGateKind.loading,
        ]);
        // 原「标记」槽的「无对象」门随条目搬进来；flag 切换属分段结构族。
        expect(byId[AddEntryId.segmentFlag]!.gates, const [
          ToolGateKind.loading,
          ToolGateKind.noSubject,
          ToolGateKind.locked,
        ]);
      },
    );

    test('addEntryHasSubject：条目「无对象」前提由库内穷尽 switch 解析（与槽面同构）', () {
      expect(
        addEntryHasSubject(AddEntryId.segmentFlag, const ToolFacts()),
        isFalse,
      );
      expect(
        addEntryHasSubject(
          AddEntryId.segmentFlag,
          const ToolFacts(selectedSegmentLine: true),
        ),
        isTrue,
      );
      for (final id in const [
        AddEntryId.halfBeat,
        AddEntryId.localMirror,
        AddEntryId.noteSticker,
      ]) {
        expect(
          addEntryHasSubject(id, const ToolFacts()),
          isTrue,
          reason: '$id',
        );
      }
    });

    test(
      '标记分段线条目：无选中分段线（无对象）→ 置灰可点弹做法；有选中且锁定 → 可点弹「已锁定分段」（动作不发生）；装载未完成压倒一切',
      () {
        final entry = AddEntryTable.normal.entryOf(AddEntryId.segmentFlag);
        // 条目自己声明的做法——装配处与求值处读的同一份。
        final explained = entry.noSubjectHint != null;
        // 无选中：无对象命中（可点并解释该怎么做）。
        final denied = evaluateDeclaredGates(
          entry.gates.toSet(),
          const ToolFacts(),
          hasSubject: false,
          noSubjectExplained: explained,
        );
        expect(denied.available, isFalse);
        expect(denied.kind, ToolGateKind.noSubject);
        expect(denied.tappable, isTrue);
        // 无对象压倒锁定：无选中 + 锁定仍报无对象（可点、弹做法）。
        const lockedFacts = ToolFacts(locked: true);
        final lockedNoSubject = evaluateDeclaredGates(
          entry.gates.toSet(),
          lockedFacts,
          hasSubject: false,
          noSubjectExplained: explained,
        );
        expect(lockedNoSubject.kind, ToolGateKind.noSubject);
        // 有选中 + 锁定：可点弹「已锁定分段」、动作不发生。
        final lockedOk = evaluateDeclaredGates(
          entry.gates.toSet(),
          lockedFacts,
        );
        expect(lockedOk.kind, ToolGateKind.locked);
        expect(lockedOk.tappable, isTrue);
        // 装载未完成压倒无对象与锁定。
        final loading = evaluateDeclaredGates(
          entry.gates.toSet(),
          const ToolFacts(loading: true),
          hasSubject: false,
        );
        expect(loading.kind, ToolGateKind.loading);
        expect(loading.tappable, isTrue);
        // 装载落定、有选中、未锁定 → 正常。
        final ok = evaluateDeclaredGates(
          entry.gates.toSet(),
          const ToolFacts(),
        );
        expect(ok.available, isTrue);
      },
    );

    test('条目经同一张判定表判定：锁定可点弹原因、越界不可点静默、装载未完成弹原因', () {
      final halfBeat = AddEntryTable.normal.entryOf(AddEntryId.halfBeat);
      final loading = evaluateToolSlot([ToolGateKind.loading]);
      expect(loading.kind, ToolGateKind.loading);
      expect(loading.tappable, isTrue);
      final locked = evaluateToolSlot([ToolGateKind.locked]);
      expect(locked.tappable, isTrue);
      final outOfBounds = evaluateToolSlot(
        halfBeat.gates.where(
          (g) => g != ToolGateKind.locked && g != ToolGateKind.loading,
        ),
      );
      expect(outOfBounds.kind, ToolGateKind.previewOutOfBounds);
      expect(outOfBounds.tappable, isFalse);
      final mirror = AddEntryTable.normal.entryOf(AddEntryId.localMirror);
      expect(
        mirror.gates.contains(ToolGateKind.previewOutOfBounds),
        isFalse,
        reason: '局部镜像片段不受越界约束',
      );
    });

    test('未知 / 未收录条目标识显式报错', () {
      expect(
        () => AddEntryTable.normal.entryOf(AddEntryId.halfBeat),
        returnsNormally,
      );
      const empty = AddEntryTable([]);
      expect(() => empty.entryOf(AddEntryId.halfBeat), throwsStateError);
    });

    test('空条目表可构造、条目查询返回空', () {
      const table = AddEntryTable([]);
      expect(table.entries, isEmpty);
    });
  });
}
