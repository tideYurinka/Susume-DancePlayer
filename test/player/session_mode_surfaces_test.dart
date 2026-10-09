/// 「模式 → 界面」四处映射的测试钉：底排槽集、轨道行集、取景态谓词、
/// 顶栏行集。
///
/// 这四处今天都是**无护栏**的模式映射——漏接一个取值不报错，只是静默走
/// 兜底默认值。本文件对现有**全部**会话模式取值逐值断言映射结果，并各带一条
/// 覆盖断言：新增取值（如投屏态两值）未接时断言点名缺的是哪个取值。
///
/// 零框架环境依赖：直测映射声明表与取道函数，不启动 widget、不读 provider。
library;

import 'package:dance_learning_app/player/play_tool_table.dart';
import 'package:dance_learning_app/player/session_mode_surfaces.dart';
import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('模式 → 界面映射：声明表结构', () {
    test('声明表覆盖全部会话模式取值；漏接时点名缺哪个', () {
      final missing = PlayerSessionMode.values
          .where(
            (mode) => !sessionModeSurfaceDeclarationTable.containsKey(mode),
          )
          .toList();
      expect(missing, isEmpty, reason: '「模式 → 界面」声明表未接取值：$missing');
      expect(
        sessionModeSurfaceDeclarationTable.length,
        PlayerSessionMode.values.length,
        reason: '声明表行数与 [PlayerSessionMode.values] 不等——多出或少了行',
      );
      for (final mode in PlayerSessionMode.values) {
        expect(
          sessionModeSurfacesOf(mode),
          sessionModeSurfaceDeclarationTable[mode],
          reason: '$mode 的取道函数与声明表不是同一行',
        );
      }
    });
  });

  group('模式 → 底排槽集', () {
    test('逐值断言现有全部会话模式取值', () {
      // 期望值是今天的既有行为（独立于实现抄写）：对照态换对比槽集、两个
      // 待命态各换自己那份，其余取值共用正常槽集；投屏态两值取空集
      // （整排不出现）。
      const expected = <PlayerSessionMode, ToolSlotTable>{
        PlayerSessionMode.watching: ToolSlotTable.normal,
        PlayerSessionMode.editing: ToolSlotTable.normal,
        PlayerSessionMode.beatCorrectionStandby: ToolSlotTable.standby,
        PlayerSessionMode.segmentDensityStandby:
            ToolSlotTable.segmentDensityStandby,
        PlayerSessionMode.compareWatching: ToolSlotTable.normal,
        PlayerSessionMode.compareEditing: ToolSlotTable.compare,
        PlayerSessionMode.compareFraming: ToolSlotTable.normal,
        PlayerSessionMode.framing: ToolSlotTable.normal,
        PlayerSessionMode.castControl: ToolSlotTable.cast,
        PlayerSessionMode.castWatching: ToolSlotTable.cast,
      };
      final missing = PlayerSessionMode.values
          .where((mode) => !expected.containsKey(mode))
          .toList();
      expect(missing, isEmpty, reason: '「模式 → 底排槽集」未接取值：$missing');
      for (final mode in PlayerSessionMode.values) {
        expect(
          sessionModeSurfacesOf(mode).slotTable,
          expected[mode],
          reason: '「模式 → 底排槽集」对 $mode 的映射与期望不符',
        );
      }
    });

    test('投屏态槽集是空集：无槽可选、槽与添加条目的门禁一条也不在场', () {
      expect(ToolSlotTable.cast.slots, isEmpty);
      expect(
        sessionModeSurfacesOf(PlayerSessionMode.castControl).slotTable.slots,
        isEmpty,
      );
      expect(
        sessionModeSurfacesOf(PlayerSessionMode.castWatching).slotTable.slots,
        isEmpty,
      );
    });
  });

  group('模式 → 轨道行集', () {
    test('逐值断言现有全部会话模式取值', () {
      // 今天只有对照-控制层与投屏态两值换行集；观看面各取值（含两个取景
      // 调节态）都用正常行集——取景调节态换的是画面呈现，不是轨道行集。
      const expected = <PlayerSessionMode, TrackRowTable>{
        PlayerSessionMode.watching: TrackRowTable.normal,
        PlayerSessionMode.editing: TrackRowTable.normal,
        PlayerSessionMode.beatCorrectionStandby: TrackRowTable.normal,
        PlayerSessionMode.segmentDensityStandby: TrackRowTable.normal,
        PlayerSessionMode.compareWatching: TrackRowTable.normal,
        PlayerSessionMode.compareEditing: TrackRowTable.compare,
        PlayerSessionMode.compareFraming: TrackRowTable.normal,
        PlayerSessionMode.framing: TrackRowTable.normal,
        PlayerSessionMode.castControl: TrackRowTable.cast,
        PlayerSessionMode.castWatching: TrackRowTable.cast,
      };
      final missing = PlayerSessionMode.values
          .where((mode) => !expected.containsKey(mode))
          .toList();
      expect(missing, isEmpty, reason: '「模式 → 轨道行集」未接取值：$missing');
      for (final mode in PlayerSessionMode.values) {
        expect(
          sessionModeSurfacesOf(mode).rowTable,
          expected[mode],
          reason: '「模式 → 轨道行集」对 $mode 的映射与期望不符',
        );
      }
    });

    test('投屏行集只留分段轨：无槽可选、无柄可拖（结构性只读）', () {
      expect(TrackRowTable.cast.rows.map((r) => r.id), const [
        TrackRowId.learning,
      ]);
      expect(TrackRowTable.cast.prefixLabels, const ['分段']);
      // 无轨道手柄带行 = 首尾线与分段线的控制柄一并不渲染。
      expect(TrackRowTable.cast.hasRow(TrackRowId.handleStrip), isFalse);
      expect(
        TrackRowTable.cast.hasRow(TrackRowId.note),
        isFalse,
        reason: '备注轨不在投屏态行集内',
      );
      expect(
        TrackRowTable.cast.hasRow(TrackRowId.localMirror),
        isFalse,
        reason: '局部镜像轨不在投屏态行集内',
      );
      expect(
        TrackRowTable.cast.hasRow(TrackRowId.beat),
        isFalse,
        reason: '节拍轨不在投屏态行集内',
      );
      expect(
        TrackRowTable.cast.hasRow(TrackRowId.practiceVideo),
        isFalse,
        reason: '练习视频轨不在投屏态行集内',
      );
    });
  });

  group('模式 → 取景态谓词', () {
    test('逐值断言现有全部会话模式取值', () {
      // 取景调节态两值（对照路径与单画面路径）为真，其余为假——含待命态、
      // 对照-播放/控制层与投屏态两值。
      const expected = <PlayerSessionMode, bool>{
        PlayerSessionMode.watching: false,
        PlayerSessionMode.editing: false,
        PlayerSessionMode.beatCorrectionStandby: false,
        PlayerSessionMode.segmentDensityStandby: false,
        PlayerSessionMode.compareWatching: false,
        PlayerSessionMode.compareEditing: false,
        PlayerSessionMode.compareFraming: true,
        PlayerSessionMode.framing: true,
        PlayerSessionMode.castControl: false,
        PlayerSessionMode.castWatching: false,
      };
      final missing = PlayerSessionMode.values
          .where((mode) => !expected.containsKey(mode))
          .toList();
      expect(missing, isEmpty, reason: '「模式 → 取景态谓词」未接取值：$missing');
      for (final mode in PlayerSessionMode.values) {
        expect(
          sessionModeSurfacesOf(mode).framingActive,
          expected[mode],
          reason: '「模式 → 取景态谓词」对 $mode 的映射与期望不符',
        );
      }
    });
  });

  group('模式 → 顶栏行集', () {
    test('逐值断言现有全部会话模式取值：投屏态两值取自己那份，其余沿用朝向与紧凑档', () {
      // 期望值是今天的既有行为（独立于实现抄写）：投屏态两值取自己那份五枚
      // 行集、与朝向和紧凑档都无关；其余取值竖屏取竖屏标题栏、横屏按紧凑档
      // 取两份横屏行集之一。
      const castModes = {
        PlayerSessionMode.castControl,
        PlayerSessionMode.castWatching,
      };
      for (final mode in PlayerSessionMode.values) {
        for (final portrait in const [false, true]) {
          for (final compact in const [false, true]) {
            final row = sessionModeSurfacesOf(mode)
                .topBarRowOf(portrait: portrait, compact: compact);
            final where = '$mode（portrait=$portrait, compact=$compact）';
            if (castModes.contains(mode)) {
              expect(
                row,
                same(kPlayToolRowCastTopBar),
                reason: '「模式 → 顶栏行集」$where：投屏态两值没有朝向/档位例外',
              );
            } else if (portrait) {
              expect(
                row,
                same(kPlayToolRowPortraitTitleBar),
                reason: '「模式 → 顶栏行集」$where：竖屏取竖屏标题栏行集',
              );
            } else {
              expect(
                row,
                same(playToolLandscapeTopBarRow(compact: compact)),
                reason: '「模式 → 顶栏行集」$where：横屏按紧凑档取行集',
              );
            }
          }
        }
      }
    });

    test('每个取值都取到一份非空行集：漏接取值在此点名', () {
      for (final mode in PlayerSessionMode.values) {
        final row = sessionModeSurfacesOf(mode)
            .topBarRowOf(portrait: false, compact: false);
        expect(row.slots, isNotEmpty, reason: '$mode 没取到行集');
      }
    });
  });
}
