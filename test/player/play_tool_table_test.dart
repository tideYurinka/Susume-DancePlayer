import 'package:dance_learning_app/player/play_tool_table.dart';
import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// 看片工具槽表直测：六份具名行集的成员与次序、
/// 十四条槽的声明字段、共享声明的同一性、门谓词两态与软门可点性、
/// 可点性派生规则、「模式 → 顶栏行集」唯一映射。
/// 不启动 widget 环境、不注容器。
///
/// 新增「取景调整」槽（tool_framing_adjust）进横屏
/// 顶栏与竖屏视频工具栏，均在「音画同步」右侧。竖屏视频工具栏拆
/// 两行——上排两枚（全局镜像、局部镜像）、下排五枚（音画同步、取景调整、
/// 节拍提示、倍速设置、对比练习），两行各一份具名行集。
///
/// 新增「投屏」槽（tool_cast，编辑面顶栏入口）、「断开投屏」槽
/// （tool_cast_disconnect）与「系统镜像」槽（tool_system_mirror，只在投屏态
/// 顶栏行集里）：投屏态两值用自己那份三枚行集（断开投屏 → 系统镜像 →
/// 查看引导，查看引导恒在末位），不占编辑态的位置预算。「系统镜像」是唯一
/// 带提示文案的槽——一句说清两条路代价差的文案随槽一起进表。
void main() {
  /// 竖屏视频播放工具栏的两行：上排两枚 +
  /// 下排五枚；同属一个落点，结构断言按两行合计。
  const portraitVideoToolbarRows = [
    kPlayToolRowPortraitVideoToolbarTop,
    kPlayToolRowPortraitVideoToolbarBottom,
  ];

  group('三份具名行集：成员与次序', () {
    test('横屏顶栏十三位 = 十一条工具加两条分隔线（投屏在「对比练习」右侧、「查看引导」之前）', () {
      final items = kPlayToolRowLandscapeTopBar.items;
      expect(items.length, 13);
      expect(items[0].slot, same(kPlayToolUndo));
      expect(items[1].slot, same(kPlayToolRedo));
      expect(items[2].isSeparator, isTrue, reason: '撤销/重做与音画同步之间');
      expect(items[3].slot, same(kPlayToolAvSync));
      expect(items[4].slot, same(kPlayToolFramingAdjust));
      expect(items[5].slot, same(kPlayToolBeatPrompt));
      expect(items[6].slot, same(kPlayToolMirror));
      expect(items[7].slot, same(kPlayToolLocalMirror));
      expect(items[8].slot, same(kPlayToolSpeedSettings));
      expect(items[9].isSeparator, isTrue, reason: '倍速设置与对比练习之间');
      expect(items[10].slot, same(kPlayToolCompare));
      expect(items[11].slot, same(kPlayToolCast));
      expect(items[12].slot, same(kPlayToolGuide));
    });

    test('竖屏标题栏四条：撤销 → 重做 → 投屏 → 查看引导（分隔线不进竖屏行）', () {
      final items = kPlayToolRowPortraitTitleBar.items;
      expect(items.length, 4);
      expect(items[0].slot, same(kPlayToolUndo));
      expect(items[1].slot, same(kPlayToolRedo));
      expect(items[2].slot, same(kPlayToolCast));
      expect(items[3].slot, same(kPlayToolGuide));
      expect(
        items.any((i) => i.isSeparator),
        isFalse,
        reason: '分隔线是行集成员：标题栏行集没有它，就是不进',
      );
    });

    test('竖屏视频工具栏第一行两条靠右：全局镜像 → 局部镜像', () {
      final items = kPlayToolRowPortraitVideoToolbarTop.items;
      expect(items.length, 2);
      expect(items[0].slot, same(kPlayToolMirror));
      expect(items[1].slot, same(kPlayToolLocalMirror));
      expect(items.any((i) => i.isSeparator), isFalse);
    });

    test('竖屏视频工具栏第二行五条：音画同步 → 取景调整 → 节拍提示 → 倍速设置 → 对比练习（取景调整在「音画同步」右侧）', () {
      final items = kPlayToolRowPortraitVideoToolbarBottom.items;
      expect(items.length, 5);
      expect(items[0].slot, same(kPlayToolAvSync));
      expect(items[1].slot, same(kPlayToolFramingAdjust));
      expect(items[2].slot, same(kPlayToolBeatPrompt));
      expect(items[3].slot, same(kPlayToolSpeedSettings));
      expect(items[4].slot, same(kPlayToolCompare));
      expect(items.any((i) => i.isSeparator), isFalse);
    });

    test('紧凑档横屏顶栏十一位 = 九条工具加两条分隔线（「更多」落在「全局镜像」左侧）', () {
      final items = kPlayToolRowLandscapeTopBarCompact.items;
      expect(items.length, 11);
      expect(items[0].slot, same(kPlayToolUndo));
      expect(items[1].slot, same(kPlayToolRedo));
      expect(items[2].isSeparator, isTrue, reason: '撤销/重做与「更多」之间');
      expect(items[3].slot, same(kPlayToolMore));
      expect(items[4].slot, same(kPlayToolMirror));
      expect(items[5].slot, same(kPlayToolLocalMirror));
      expect(items[6].slot, same(kPlayToolSpeedSettings));
      expect(items[7].isSeparator, isTrue, reason: '倍速设置与对比练习之间');
      expect(items[8].slot, same(kPlayToolCompare));
      expect(items[9].slot, same(kPlayToolCast));
      expect(items[10].slot, same(kPlayToolGuide));
      // 三枚收在「更多」菜单里，不在紧凑档横屏顶栏。
      expect(
        items.any(
          (i) =>
              i.slot == kPlayToolAvSync ||
              i.slot == kPlayToolFramingAdjust ||
              i.slot == kPlayToolBeatPrompt,
        ),
        isFalse,
        reason: '音画同步/取景调整/节拍提示由「更多」承载',
      );
    });

    test('投屏态顶栏三枚：断开投屏 → 系统镜像 → 查看引导（查看引导恒在末位、无分隔线）', () {
      final items = kPlayToolRowCastTopBar.items;
      expect(items.length, 3);
      expect(items[0].slot, same(kPlayToolDisconnectCast));
      expect(items[1].slot, same(kPlayToolSystemMirror));
      expect(items[2].slot, same(kPlayToolGuide));
      expect(items.any((i) => i.isSeparator), isFalse);
      // 编辑态那些槽一枚都不进投屏态顶栏——投屏态不占编辑态的位置预算。
      final editorSlots = {
        for (final row in [
          kPlayToolRowLandscapeTopBar,
          kPlayToolRowLandscapeTopBarCompact,
          kPlayToolRowPortraitTitleBar,
          kPlayToolRowPortraitVideoToolbarTop,
          kPlayToolRowPortraitVideoToolbarBottom,
        ])
          ...row.slots,
      };
      for (final slot in kPlayToolRowCastTopBar.slots) {
        if (identical(slot, kPlayToolGuide)) continue;
        expect(
          editorSlots.contains(slot),
          isFalse,
          reason: '${slot.key} 是投屏态专属槽',
        );
      }
    });

    test('十四条声明各不相同、覆盖无遗漏', () {
      final declarations = [
        kPlayToolUndo,
        kPlayToolRedo,
        kPlayToolAvSync,
        kPlayToolFramingAdjust,
        kPlayToolBeatPrompt,
        kPlayToolMirror,
        kPlayToolLocalMirror,
        kPlayToolSpeedSettings,
        kPlayToolCompare,
        kPlayToolCast,
        kPlayToolDisconnectCast,
        kPlayToolSystemMirror,
        kPlayToolGuide,
        kPlayToolMore,
      ];
      expect(declarations.toSet().length, 14);
    });
  });

  group('横屏顶栏行集选择（紧凑档判据结果 → 行集）', () {
    test('紧凑档选到紧凑行集，常规档选到原行集', () {
      expect(
        playToolLandscapeTopBarRow(compact: true),
        same(kPlayToolRowLandscapeTopBarCompact),
      );
      expect(
        playToolLandscapeTopBarRow(compact: false),
        same(kPlayToolRowLandscapeTopBar),
      );
    });

    test('两组合计穷尽全部槽身份', () {
      final compact = playToolLandscapeTopBarRow(compact: true).slots;
      final regular = playToolLandscapeTopBarRow(compact: false).slots;
      expect(
        {
          ...compact,
          ...regular,
          ...kPlayToolRowCastTopBar.slots,
        }.map((s) => s.id).toSet(),
        PlayToolSlotId.values.toSet(),
        reason: '紧凑档 + 常规档 + 投屏态三组合计穷尽全部槽身份',
      );
      expect(compact.map((s) => s.id).toList(), [
        PlayToolSlotId.undo,
        PlayToolSlotId.redo,
        PlayToolSlotId.more,
        PlayToolSlotId.mirror,
        PlayToolSlotId.localMirror,
        PlayToolSlotId.speedSettings,
        PlayToolSlotId.compare,
        PlayToolSlotId.cast,
        PlayToolSlotId.guide,
      ], reason: '紧凑档次序：撤销→重做→更多→全局镜像→局部镜像→倍速设置→对比练习→投屏→查看引导');
    });
  });

  group('「模式 → 顶栏行集」唯一映射', () {
    test('投屏态两值取投屏行集：与朝向、紧凑档都无关', () {
      for (final mode in const [
        PlayerSessionMode.castControl,
        PlayerSessionMode.castWatching,
      ]) {
        for (final portrait in const [false, true]) {
          for (final compact in const [false, true]) {
            expect(
              playToolTopBarRowFor(
                mode: mode,
                portrait: portrait,
                compact: compact,
              ),
              same(kPlayToolRowCastTopBar),
              reason: '$mode 没有朝向/档位例外',
            );
          }
        }
      }
    });

    test('非投屏态沿用朝向与紧凑档：结果与既有两处选择逐位一致', () {
      for (final mode in PlayerSessionMode.values) {
        if (mode == PlayerSessionMode.castControl ||
            mode == PlayerSessionMode.castWatching) {
          continue;
        }
        for (final compact in const [false, true]) {
          expect(
            playToolTopBarRowFor(mode: mode, portrait: true, compact: compact),
            same(kPlayToolRowPortraitTitleBar),
            reason: '$mode 竖屏取竖屏标题栏行集',
          );
          expect(
            playToolTopBarRowFor(mode: mode, portrait: false, compact: compact),
            same(playToolLandscapeTopBarRow(compact: compact)),
            reason: '$mode 横屏按档位取行集',
          );
        }
      }
    });

    test('映射穷尽全部会话模式取值：每个取值都有明确答案', () {
      // 穷尽 switch 的编译期护栏由实现承接；本断言钉住「每个取值都能取到
      // 一份具名行集」，漏一个取值即在此点名。
      for (final mode in PlayerSessionMode.values) {
        final row = playToolTopBarRowFor(
          mode: mode,
          portrait: false,
          compact: false,
        );
        expect(row.slots, isNotEmpty, reason: '$mode 没取到行集');
      }
    });
  });

  group('每条槽的七个声明字段', () {
    test('槽键逐位等于今天渲染层 Key（十四个槽键字符串：十二个沿用、投屏与断开投屏与系统镜像新键）', () {
      expect(kPlayToolUndo.key, 'tool_undo');
      expect(kPlayToolRedo.key, 'tool_redo');
      expect(kPlayToolAvSync.key, 'tool_av_sync');
      expect(kPlayToolFramingAdjust.key, 'tool_framing_adjust');
      expect(kPlayToolBeatPrompt.key, 'tool_beat_prompt');
      expect(kPlayToolMirror.key, 'tool_mirror');
      expect(kPlayToolLocalMirror.key, 'tool_local_mirror');
      expect(kPlayToolSpeedSettings.key, 'tool_speed_settings');
      expect(kPlayToolCompare.key, 'tool_compare');
      expect(kPlayToolCast.key, 'tool_cast');
      expect(kPlayToolDisconnectCast.key, 'tool_cast_disconnect');
      expect(kPlayToolSystemMirror.key, 'tool_system_mirror');
      expect(kPlayToolGuide.key, 'tool_guide');
      expect(kPlayToolMore.key, 'tool_more');
    });

    test('文案逐位等于今天取值（倍速设置未激活标签 = 「倍速设置」）', () {
      expect(kPlayToolUndo.label, '撤销');
      expect(kPlayToolRedo.label, '重做');
      expect(kPlayToolAvSync.label, '音画同步');
      expect(kPlayToolFramingAdjust.label, '取景调整');
      expect(kPlayToolBeatPrompt.label, '节拍提示');
      expect(kPlayToolMirror.label, '全局镜像');
      expect(kPlayToolLocalMirror.label, '局部镜像');
      expect(kPlayToolSpeedSettings.label, '倍速设置');
      expect(kPlayToolCompare.label, '对比练习');
      expect(kPlayToolCast.label, '投屏');
      expect(kPlayToolDisconnectCast.label, '断开投屏');
      expect(kPlayToolSystemMirror.label, '系统镜像');
      expect(kPlayToolGuide.label, '查看引导');
      expect(kPlayToolMore.label, '更多');
    });

    test('图标 token 逐条等于今天图标（「更多」取横向省略号）', () {
      expect(kPlayToolUndo.icon, PlayToolIcon.undo);
      expect(kPlayToolRedo.icon, PlayToolIcon.redo);
      expect(kPlayToolAvSync.icon, PlayToolIcon.surroundSound);
      expect(kPlayToolFramingAdjust.icon, PlayToolIcon.cropFree);
      expect(kPlayToolBeatPrompt.icon, PlayToolIcon.graphicEq);
      expect(kPlayToolMirror.icon, PlayToolIcon.flip);
      expect(kPlayToolLocalMirror.icon, PlayToolIcon.flipCameraAndroid);
      expect(kPlayToolSpeedSettings.icon, PlayToolIcon.speed);
      expect(kPlayToolCompare.icon, PlayToolIcon.compare);
      expect(kPlayToolCast.icon, PlayToolIcon.cast);
      expect(kPlayToolDisconnectCast.icon, PlayToolIcon.castDisconnect);
      expect(kPlayToolSystemMirror.icon, PlayToolIcon.systemMirror);
      expect(kPlayToolGuide.icon, PlayToolIcon.helpOutline);
      expect(kPlayToolMore.icon, PlayToolIcon.more);
    });

    test('门清单显式声明：只有「局部镜像」报无对象门，其余显式空清单', () {
      expect(kPlayToolUndo.gates, isEmpty);
      expect(kPlayToolRedo.gates, isEmpty);
      expect(kPlayToolAvSync.gates, isEmpty);
      expect(
        kPlayToolFramingAdjust.gates,
        isEmpty,
        reason: '取景调整的装载未完成门归页面级声明（loadGateBlocksWrite），本表不重复声明',
      );
      expect(kPlayToolBeatPrompt.gates, isEmpty);
      expect(kPlayToolMirror.gates, isEmpty);
      expect(kPlayToolLocalMirror.gates, [ToolGateKind.noSubject]);
      expect(kPlayToolSpeedSettings.gates, isEmpty);
      expect(kPlayToolCompare.gates, isEmpty);
      expect(kPlayToolCast.gates, isEmpty);
      expect(kPlayToolDisconnectCast.gates, isEmpty);
      expect(
        kPlayToolSystemMirror.gates,
        isEmpty,
        reason: '系统镜像入口无门：跳得动就送、跳不动由降级链给短暂提示，不置灰',
      );
      expect(kPlayToolGuide.gates, isEmpty);
      expect(kPlayToolMore.gates, isEmpty);
    });

    test('引导锚点声明：只有「局部镜像」声明承载锚点，其余一律不声明', () {
      expect(kPlayToolUndo.carriesGuideAnchor, isFalse);
      expect(kPlayToolRedo.carriesGuideAnchor, isFalse);
      expect(kPlayToolAvSync.carriesGuideAnchor, isFalse);
      expect(kPlayToolFramingAdjust.carriesGuideAnchor, isFalse);
      expect(kPlayToolBeatPrompt.carriesGuideAnchor, isFalse);
      expect(kPlayToolMirror.carriesGuideAnchor, isFalse);
      expect(
        kPlayToolLocalMirror.carriesGuideAnchor,
        isTrue,
        reason: '局部镜像第二步锚这枚槽（锚点 key 即槽键），是顶栏唯一声明为真的一条',
      );
      expect(kPlayToolSpeedSettings.carriesGuideAnchor, isFalse);
      expect(kPlayToolCompare.carriesGuideAnchor, isFalse);
      expect(kPlayToolCast.carriesGuideAnchor, isFalse);
      expect(kPlayToolDisconnectCast.carriesGuideAnchor, isFalse);
      expect(kPlayToolGuide.carriesGuideAnchor, isFalse);
      expect(kPlayToolSystemMirror.carriesGuideAnchor, isFalse);
      expect(
        kPlayToolMore.carriesGuideAnchor,
        isFalse,
        reason: '「更多」不承载引导锚点（那两枚的引导锚点在各自气泡内部）',
      );
    });

    test('提示文案：只有「系统镜像」声明一条，且一句话说清两条路的代价差', () {
      expect(kPlayToolUndo.tooltip, isNull);
      expect(kPlayToolRedo.tooltip, isNull);
      expect(kPlayToolAvSync.tooltip, isNull);
      expect(kPlayToolFramingAdjust.tooltip, isNull);
      expect(kPlayToolBeatPrompt.tooltip, isNull);
      expect(kPlayToolMirror.tooltip, isNull);
      expect(kPlayToolLocalMirror.tooltip, isNull);
      expect(kPlayToolSpeedSettings.tooltip, isNull);
      expect(kPlayToolCompare.tooltip, isNull);
      expect(kPlayToolCast.tooltip, isNull);
      expect(kPlayToolDisconnectCast.tooltip, isNull);
      expect(kPlayToolGuide.tooltip, isNull);
      expect(kPlayToolMore.tooltip, isNull);

      // 这句文案是入口自己承担的取舍说明（ADR-0004）：整屏镜像那三笔代价
      // （有延迟、手机屏要亮着、控制层也上电视）与"我们这条路"的边界都要在
      // 一句话里出现——逐字重写、故意不从常量取，文案改了要能在测试里看见。
      expect(
        kPlayToolSystemMirror.tooltip,
        '整屏镜像：有延迟、手机屏要亮着、控制层也上电视；'
        '我们这条路推的是渲染好的投屏副本',
      );
    });

    test('软门标记：只有「局部镜像」是软门', () {
      expect(kPlayToolUndo.softGate, isFalse);
      expect(kPlayToolRedo.softGate, isFalse);
      expect(kPlayToolAvSync.softGate, isFalse);
      expect(kPlayToolFramingAdjust.softGate, isFalse);
      expect(kPlayToolBeatPrompt.softGate, isFalse);
      expect(kPlayToolMirror.softGate, isFalse);
      expect(kPlayToolLocalMirror.softGate, isTrue);
      expect(kPlayToolSpeedSettings.softGate, isFalse);
      expect(kPlayToolCompare.softGate, isFalse);
      expect(kPlayToolCast.softGate, isFalse);
      expect(kPlayToolDisconnectCast.softGate, isFalse);
      expect(kPlayToolSystemMirror.softGate, isFalse);
      expect(kPlayToolGuide.softGate, isFalse);
      expect(kPlayToolMore.softGate, isFalse);
    });
  });

  group('槽身份', () {
    test('十四条槽的 id 互不相同、覆盖无遗漏', () {
      final ids = [
        kPlayToolUndo.id,
        kPlayToolRedo.id,
        kPlayToolAvSync.id,
        kPlayToolFramingAdjust.id,
        kPlayToolBeatPrompt.id,
        kPlayToolMirror.id,
        kPlayToolLocalMirror.id,
        kPlayToolSpeedSettings.id,
        kPlayToolCompare.id,
        kPlayToolCast.id,
        kPlayToolDisconnectCast.id,
        kPlayToolSystemMirror.id,
        kPlayToolGuide.id,
        kPlayToolMore.id,
      ];
      expect(ids.toSet().length, 14);
      expect(
        ids.toSet(),
        PlayToolSlotId.values.toSet(),
        reason: '装配点按 id 穷尽 switch：表里每条槽都有身份，身份恰好十四个',
      );
    });

    test('行集引用的槽身份与声明一一对应（同一份声明的同一个身份）', () {
      final slots = [
        ...kPlayToolRowLandscapeTopBar.slots,
        ...kPlayToolRowLandscapeTopBarCompact.slots,
        ...kPlayToolRowPortraitTitleBar.slots,
        for (final row in portraitVideoToolbarRows) ...row.slots,
        ...kPlayToolRowCastTopBar.slots,
      ];
      expect(
        {for (final s in slots) s.id: s}.length,
        14,
        reason: '六份行集合计引用十四条不同身份，无第二份编码',
      );
    });
  });

  group('共享声明：结构上不可能分家', () {
    test('同一条槽出现在多份行集时是同一份声明（identical）', () {
      final landscape = kPlayToolRowLandscapeTopBar.slots;
      final titleBar = kPlayToolRowPortraitTitleBar.slots;
      final video = [for (final row in portraitVideoToolbarRows) ...row.slots];
      // 撤销/重做/查看引导：横屏与标题栏。
      bool sameSlot(Iterable<PlayToolSlot> row, PlayToolSlot slot) =>
          row.any((s) => identical(s, slot));
      for (final slot in titleBar) {
        expect(landscape, contains(slot));
        expect(sameSlot(landscape, slot), isTrue);
      }
      // 其余七条：横屏与视频工具栏。
      for (final slot in video) {
        expect(sameSlot(landscape, slot), isTrue);
      }
      // 紧凑档横屏顶栏引用的七条（除只在紧凑档出现的「更多」）与常规档
      // 同一批声明。
      final compactOnly = {kPlayToolMore};
      for (final slot in kPlayToolRowLandscapeTopBarCompact.slots) {
        if (compactOnly.contains(slot)) continue;
        expect(
          sameSlot([...landscape, ...titleBar, ...video], slot),
          isTrue,
          reason: '紧凑档横屏行集不内联复制声明',
        );
      }
    });

    test('十四条声明恰好被六份行集穷尽引用，表外无第二份', () {
      final all = <PlayToolSlot>{
        ...kPlayToolRowLandscapeTopBar.slots,
        ...kPlayToolRowLandscapeTopBarCompact.slots,
        ...kPlayToolRowPortraitTitleBar.slots,
        for (final row in portraitVideoToolbarRows) ...row.slots,
        ...kPlayToolRowCastTopBar.slots,
      };
      expect(all, {
        kPlayToolUndo,
        kPlayToolRedo,
        kPlayToolAvSync,
        kPlayToolFramingAdjust,
        kPlayToolBeatPrompt,
        kPlayToolMirror,
        kPlayToolLocalMirror,
        kPlayToolSpeedSettings,
        kPlayToolCompare,
        kPlayToolCast,
        kPlayToolDisconnectCast,
        kPlayToolSystemMirror,
        kPlayToolGuide,
        kPlayToolMore,
      });
    });
  });

  group('门谓词两态与软门可点性', () {
    test('无作用对象：局部镜像命中无对象门、不可用', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolLocalMirror.gates.toSet(),
        const ToolFacts(),
        hasSubject: false,
      );
      expect(verdict.available, isFalse);
      expect(verdict.kind, ToolGateKind.noSubject);
    });

    test('有作用对象：局部镜像无门命中、可用', () {
      final verdict = evaluateDeclaredGates(
        kPlayToolLocalMirror.gates.toSet(),
        const ToolFacts(),
        hasSubject: true,
      );
      expect(verdict.available, isTrue);
    });

    test('软门两态都可点：无片段置灰仍可点（点了自己解释原因），有片段正常', () {
      expect(
        playToolTappable(
          kPlayToolLocalMirror,
          hasSubject: false,
          enabled: false,
        ),
        isTrue,
        reason: '软门：置灰但仍可点',
      );
      expect(
        playToolTappable(kPlayToolLocalMirror, hasSubject: true, enabled: true),
        isTrue,
      );
    });
  });

  group('可点性派生', () {
    test('无门命中时随硬启用位（撤销/重做：置灰即不可点）', () {
      expect(
        playToolTappable(kPlayToolUndo, hasSubject: true, enabled: true),
        isTrue,
      );
      expect(
        playToolTappable(kPlayToolUndo, hasSubject: true, enabled: false),
        isFalse,
      );
      // 「查看引导」恒置灰硬门：即使声明 enabled 也走硬启用位入参。
      expect(
        playToolTappable(kPlayToolGuide, hasSubject: true, enabled: false),
        isFalse,
      );
    });

    test('有门命中时随判定结果：无对象门（第②行）可点，软门与硬门同向', () {
      // 假想的非软门无对象槽（用局部镜像的声明、去掉软门标记语义的对照：
      // 直接构造一条同门声明的硬门槽；身份借同门槽——本用例只测可点性
      // 派生，不涉装配）。
      const hardNoSubject = PlayToolSlot(
        id: PlayToolSlotId.localMirror,
        key: 'tool_hard_gate_probe',
        label: '探针',
        icon: PlayToolIcon.flip,
        gates: [ToolGateKind.noSubject],
        softGate: false,
      );
      expect(
        playToolTappable(hardNoSubject, hasSubject: false, enabled: false),
        isTrue,
        reason: '判定表第②行：无对象 → 置灰、可点',
      );
      expect(
        playToolTappable(hardNoSubject, hasSubject: true, enabled: true),
        isTrue,
      );
    });
  });
}
