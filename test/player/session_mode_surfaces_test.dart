/// 「模式 → 界面」三处映射的测试钉：底排槽集、轨道行集、取景态谓词。
///
/// 这三处今天都是**无护栏**的模式映射——漏接一个取值不报错，只是静默走
/// 兜底默认值。本文件对现有**全部**会话模式取值逐值断言映射结果，并各带一条
/// 覆盖断言：新增取值（如投屏态两值）未接时断言点名缺的是哪个取值。
///
/// 零框架环境依赖：直测映射声明表与取道函数，不启动 widget、不读 provider。
library;

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
      // 待命态各换自己那份，其余取值共用正常槽集。
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
  });

  group('模式 → 轨道行集', () {
    test('逐值断言现有全部会话模式取值', () {
      // 今天只有对照-控制层换行集；观看面各取值（含两个取景调节态）都用
      // 正常行集——取景调节态换的是画面呈现，不是轨道行集。
      const expected = <PlayerSessionMode, TrackRowTable>{
        PlayerSessionMode.watching: TrackRowTable.normal,
        PlayerSessionMode.editing: TrackRowTable.normal,
        PlayerSessionMode.beatCorrectionStandby: TrackRowTable.normal,
        PlayerSessionMode.segmentDensityStandby: TrackRowTable.normal,
        PlayerSessionMode.compareWatching: TrackRowTable.normal,
        PlayerSessionMode.compareEditing: TrackRowTable.compare,
        PlayerSessionMode.compareFraming: TrackRowTable.normal,
        PlayerSessionMode.framing: TrackRowTable.normal,
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
  });

  group('模式 → 取景态谓词', () {
    test('逐值断言现有全部会话模式取值', () {
      // 取景调节态两值（对照路径与单画面路径）为真，其余为假——含待命态与
      // 对照-播放/控制层。
      const expected = <PlayerSessionMode, bool>{
        PlayerSessionMode.watching: false,
        PlayerSessionMode.editing: false,
        PlayerSessionMode.beatCorrectionStandby: false,
        PlayerSessionMode.segmentDensityStandby: false,
        PlayerSessionMode.compareWatching: false,
        PlayerSessionMode.compareEditing: false,
        PlayerSessionMode.compareFraming: true,
        PlayerSessionMode.framing: true,
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
}
