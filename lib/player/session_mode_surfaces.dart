/// 「模式 → 界面」映射声明表：会话模式取值 → 该态三处换装的唯一来源。
///
/// 三处换装是：**底排槽集**（底排承载哪些工具槽）、**轨道行集**（轨道带有
/// 哪些行）、**取景态谓词**（画面是否处于取景调节态）。三处原先是各消费点
/// 就地写的**无护栏**映射——漏接一个模式取值不报错，只是静默落到兜底默认值；
/// 本表把它们收成逐值一行，取值只由入参决定
/// （`test/player/session_mode_surfaces_test.dart` 逐值钉住现有全部取值）。
///
/// **一行一个模式取值**：行数与 [PlayerSessionMode.values] 相等（结构断言在
/// 册）；取道函数 [sessionModeSurfacesOf] 缺行即显式报错并点名取值，不静默
/// 兜底——新增会话模式取值（如投屏态两值）时漏接在测试与运行期都点名。
///
/// **槽集与行集各自对模式无知**：本层只回答「哪个取值用哪一份具名槽集 /
/// 行集」；具名槽集 [ToolSlotTable] 与具名行集 [TrackRowTable] 自身不读模式、
/// 不含映射。
///
/// **顶栏行集不在本表**：它今天按朝向与紧凑档选，投屏态两值另有一份自己的
/// 行集——那处「模式 → 顶栏行集」的唯一映射住在顶栏自己的声明库
/// （`play_tool_table.dart` 的 `playToolTopBarRowFor`），与三处换装并列。
///
/// 本模块零 widget：不构控件、不读 provider，可在不启动 widget 环境的情况下
/// 直测。
library;

import '../player_session/player_session.dart' show PlayerSessionMode;
import 'tool_slots.dart' show ToolSlotTable;
import 'track_row_table.dart' show TrackRowTable;

/// 一个会话模式取值下的三处换装取值。
class SessionModeSurfaces {
  const SessionModeSurfaces({
    required this.slotTable,
    required this.rowTable,
    required this.framingActive,
  });

  /// 底排槽集：该态底排承载哪些工具槽、什么次序（次序即槽集声明次序）。
  final ToolSlotTable slotTable;

  /// 轨道行集：该态轨道带有哪些行、什么次序。紧凑档下对本行集按「两轨当前
  /// 空否」再剪裁，那一步不属于本表（见播放页）。
  final TrackRowTable rowTable;

  /// 取景态谓词：该态是否处于取景调节态（画面手势归取景、控制层收起）。
  final bool framingActive;
}

/// 声明表：逐值一行。该态今天的取值即既有行为——正常槽集 / 正常行集为
/// 兜底形态不是「默认值」，而是四种取值共用的同一份具名槽集与六种取值共用的
/// 同一份具名行集（共享同一条 `const`，不是各自抄一份）。
const sessionModeSurfaceDeclarationTable =
    <PlayerSessionMode, SessionModeSurfaces>{
      PlayerSessionMode.watching: SessionModeSurfaces(
        slotTable: ToolSlotTable.normal,
        rowTable: TrackRowTable.normal,
        framingActive: false,
      ),
      PlayerSessionMode.editing: SessionModeSurfaces(
        slotTable: ToolSlotTable.normal,
        rowTable: TrackRowTable.normal,
        framingActive: false,
      ),
      PlayerSessionMode.beatCorrectionStandby: SessionModeSurfaces(
        slotTable: ToolSlotTable.standby,
        rowTable: TrackRowTable.normal,
        framingActive: false,
      ),
      PlayerSessionMode.segmentDensityStandby: SessionModeSurfaces(
        slotTable: ToolSlotTable.segmentDensityStandby,
        rowTable: TrackRowTable.normal,
        framingActive: false,
      ),
      // 对比-播放态仍是正常槽集：对比槽集随「对比-控制层」展开才换装。
      PlayerSessionMode.compareWatching: SessionModeSurfaces(
        slotTable: ToolSlotTable.normal,
        rowTable: TrackRowTable.normal,
        framingActive: false,
      ),
      PlayerSessionMode.compareEditing: SessionModeSurfaces(
        slotTable: ToolSlotTable.compare,
        rowTable: TrackRowTable.compare,
        framingActive: false,
      ),
      // 两个取景调节态（对比路径 / 单画面路径）：取景谓词为真，槽集与行集
      // 不换装——换的是画面呈现，不是底排与轨道带。
      PlayerSessionMode.compareFraming: SessionModeSurfaces(
        slotTable: ToolSlotTable.normal,
        rowTable: TrackRowTable.normal,
        framingActive: true,
      ),
      PlayerSessionMode.framing: SessionModeSurfaces(
        slotTable: ToolSlotTable.normal,
        rowTable: TrackRowTable.normal,
        framingActive: true,
      ),
      // 投屏态两值：底排槽集取**空集**（槽位整排不出现）、轨道行集只留
      // 分段轨（分段因此结构性只读）。两值同属一个取值族——三处换装全族
      // 一致，只差控制层展开位。顶栏行集不在本表：它由
      // `play_tool_table.dart` 的「模式 → 顶栏行集」唯一映射给出。
      PlayerSessionMode.castControl: SessionModeSurfaces(
        slotTable: ToolSlotTable.cast,
        rowTable: TrackRowTable.cast,
        framingActive: false,
      ),
      PlayerSessionMode.castWatching: SessionModeSurfaces(
        slotTable: ToolSlotTable.cast,
        rowTable: TrackRowTable.cast,
        framingActive: false,
      ),
    };

/// 取道函数：缺行即显式报错并点名取值（不静默兜底）。单一真相是上面的声明表，
/// 消费点不另抄映射。
SessionModeSurfaces sessionModeSurfacesOf(PlayerSessionMode mode) {
  final surfaces = sessionModeSurfaceDeclarationTable[mode];
  if (surfaces == null) {
    throw StateError(
      '会话模式 → 界面映射未接取值：$mode'
      '（请在 sessionModeSurfaceDeclarationTable 补一行）',
    );
  }
  return surfaces;
}
