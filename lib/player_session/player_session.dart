/// player_session 小库（播放会话模式单一 owner；自足、无环）：
/// 回答「播放器当前处于观看 / 编辑 / 待命态中的哪一种」并执行进入与退出。
/// 纯值库——零 UI、零服务，只依赖 `dart:` 与 Riverpod；相机授权这类异步
/// 进入前置由宿主编排（经待办槽介接后走唯一提交入口），不在本库内。
/// 方向是设备事实、不进本库（编辑面进入前置为无）。
///
/// ## 库头契约（不变量清单）
///
/// 1. **取值与展开位**：模式取值十值——观看 / 编辑 / 待命态×2 /
///    对比-播放态 / 对比-控制层 / 对比取景调节态 / 单画面取景调节态 /
///    投屏态×2（投屏-控制层 / 投屏-观看态）（[PlayerSessionMode]）。控制层
///    展开位由取值派生（[PlayerSession.controlOpen]：观看面为否，编辑面为是），
///    本库内外不存在可独立写的展开位布尔；「待命态却未展开」在类型上
///    写不出来。
/// 2. **进入前置归属**：进入前置是**目标取值的属性**（逐值一行进
///    [playerSessionEntryDeclarationTable]，N 维而非 N² 转换对表）；
///    「需宿主编排」不等于「一定弹窗」。域就绪不足（网格未就绪、
///    相机未授权）不进本库，分账给节拍侧与相机侧。
/// 3. **唯一写路径与结果族**：一切变更经 [PlayerSessionModel.enter]
///    （[collapse] / [openEditor] 是走同一声明表的具名便捷，不构成
///    第二条写路径）。结果族三成员：已进入 / 本就在目标态（幂等
///    no-op，不是错误）/ 不成立（不抛异常）；失败零副作用——值一位
///    不动、待办槽不残留。
/// 4. **待办槽语义**：单槽，非空即「有一次待处理的进入」。发起路径
///    可多（[PlayerSessionModel.requestEntry]）、提交点唯一
///    （[PlayerSessionModel.commit]，空槽提交 = 结构不成立）；取消经
///    [PlayerSessionModel.cancelPendingEntry]。重复落待办不叠加。
///    直接进入不清待办——宿主须显式提交或取消。
/// 5. **复位触发点**：离开这支舞 = [PlayerSessionModel.reset] 一次
///    调用，触发点两个——换视频、离开播放页，没有手写退出点。
/// 6. **库边界**：可被 widget 层与标注编辑模块库 import，依赖方向
///    单向、反向不可（依赖约束断言在册）。这是「对比态只读」将来
///    作为门禁第二个原因在结构上可行的前提。
///
/// ## 交接三条（致对比切片）
///
/// 1. 对比行集经轨道带既有的行集参数传入（接口已就位），轨道带对
///    模式保持无知。
/// 2. 「对比态只读」采用「一个门禁 N 个原因」的泛化方向、不建第二
///    张平行动词表；实施时开 ADR 承接既有的门禁（逐
///    verb 门禁收进标注编辑模块）。
/// 3. 进入对比态走本库进入路径（经声明表 + 唯一提交入口）；权限询问
///    与横屏弹窗的编排在宿主侧，对比态不需要第二个布尔。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 播放会话模式十取值：观看 / 编辑 / 八拍矫正待命态 / 段内倍频待命态 /
/// 对比-播放态 / 对比-控制层 / 对比取景调节态 / 单画面取景调节态 /
/// 投屏-控制层 / 投屏-观看态。
///
/// 控制层展开位由取值派生（[PlayerSession.controlOpen]：观看面为否，编辑
/// 面为是），不存在可独立写的展开位字段——「待命态却未展开」这类组合在类型上
/// 写不出来（`compareFraming` 第三值由
/// 落地）。
enum PlayerSessionMode {
  watching,
  editing,
  beatCorrectionStandby,

  /// 段内倍频待命态：编辑面取值、无进入
  /// 前置；底部工具槽换装为段内倍频赋值三钮 + 退出。
  segmentDensityStandby,
  compareWatching,
  compareEditing,

  /// 对比态取景调节态：对比态内的画面取景面——控制层收起、画面
  /// 手势完全交给取景；退出回对比-控制层。
  compareFraming,

  /// 单画面取景调节态：观看面上的取景面——控制层收起、
  /// 除取景手势外手势全停、画面即源视频；不属于对比态、无进入前置；退出三同路
  /// （完成 / 系统返回 / 点画面外）一律回编辑态。
  framing,

  /// 投屏-控制层：投屏态的编辑面取值——控制层展开，顶栏换成投屏态那份
  /// 行集、底排槽集取空集、轨道带只留分段轨。进入前置 = **投屏准备**
  /// （选接收端、起递出通道、推片、起播，编排在宿主侧）。
  castControl,

  /// 投屏-观看态：投屏态的观看面取值——控制层收起（投屏胶囊归
  /// 另一票）；点画面即展开回投屏-控制层。进入前置为无（它由
  /// 投屏-控制层收起而来，不再重跑投屏准备）。
  castWatching,
}

/// 模式所在面：观看面 / 编辑面。
enum PlayerSessionFace { watchingFace, editorFace }

/// 进入前置：进入某模式前必须完成、且可能被用户拒绝的宿主编排。
///
/// 「需宿主编排」不等于「一定弹窗」。方向不是会话取值：编辑面
/// 无方向前置，竖屏与横屏同一路径直接进入。
enum PlayerSessionEntryRequirement {
  /// 无前置。
  none,

  /// 相机授权（进入对比-播放态先按系统流程询问相机权限；拒绝
  /// 不进入、零副作用，编排仍在宿主侧）。
  cameraPermission,

  /// 投屏准备（进入投屏-控制层先选**接收端**、起递出通道、推片、起播；
  /// 取消或起投失败不进入、零副作用，编排仍在宿主侧）——与相机授权同构：
  /// 「需宿主编排」不等于「一定弹窗」。
  castPreparation,
}

/// 进入声明：所在面 + 进入前置（逐值一行，N 维而非 N² 转换对表）。
class PlayerSessionEntryDeclaration {
  const PlayerSessionEntryDeclaration(this.face, this.requirement);

  final PlayerSessionFace face;
  final PlayerSessionEntryRequirement requirement;
}

/// 进入声明表：每个取值一行，行数与 [PlayerSessionMode.values] 相等
/// （结构断言在册，加取值只改一处即失败）。编辑面三值无前置（竖屏点画面
/// 直接进，不再问方向）；`compareWatching`与
/// `compareFraming`的进入前置 = 相机授权，编排仍在宿主侧。
const playerSessionEntryDeclarationTable =
    <PlayerSessionMode, PlayerSessionEntryDeclaration>{
      PlayerSessionMode.watching: PlayerSessionEntryDeclaration(
        PlayerSessionFace.watchingFace,
        PlayerSessionEntryRequirement.none,
      ),
      PlayerSessionMode.editing: PlayerSessionEntryDeclaration(
        PlayerSessionFace.editorFace,
        PlayerSessionEntryRequirement.none,
      ),
      PlayerSessionMode.beatCorrectionStandby: PlayerSessionEntryDeclaration(
        PlayerSessionFace.editorFace,
        PlayerSessionEntryRequirement.none,
      ),
      // 段内倍频待命态：编辑面、无进入前置
      // ——「待命态是会话模式的一个取值」同款形态。
      PlayerSessionMode.segmentDensityStandby: PlayerSessionEntryDeclaration(
        PlayerSessionFace.editorFace,
        PlayerSessionEntryRequirement.none,
      ),
      PlayerSessionMode.compareWatching: PlayerSessionEntryDeclaration(
        PlayerSessionFace.watchingFace,
        // 进入前置 = 相机授权：拒绝不进入对比态、零副作用。
        PlayerSessionEntryRequirement.cameraPermission,
      ),
      PlayerSessionMode.compareEditing: PlayerSessionEntryDeclaration(
        PlayerSessionFace.editorFace,
        PlayerSessionEntryRequirement.none,
      ),
      PlayerSessionMode.compareFraming: PlayerSessionEntryDeclaration(
        PlayerSessionFace.watchingFace,
        // 进入前置 = 相机授权（沿用同一口径）：对比态内进入时授权
        // 已由 compareWatching 的进入编排取得。
        PlayerSessionEntryRequirement.cameraPermission,
      ),
      // 单画面取景调节态：观看面、无进入前置——
      // 不涉相机，普通编辑面直接进入。
      PlayerSessionMode.framing: PlayerSessionEntryDeclaration(
        PlayerSessionFace.watchingFace,
        PlayerSessionEntryRequirement.none,
      ),
      // 投屏-控制层：编辑面、进入前置 = 投屏准备（唯一入口是顶栏那枚投屏
      // 工具落待办，宿主编排完准备面板与起投后经唯一提交入口提交）。
      PlayerSessionMode.castControl: PlayerSessionEntryDeclaration(
        PlayerSessionFace.editorFace,
        PlayerSessionEntryRequirement.castPreparation,
      ),
      // 投屏-观看态：观看面、无进入前置——它只从投屏-控制层收起而来
      // （点画面展开回去），不重跑投屏准备。
      PlayerSessionMode.castWatching: PlayerSessionEntryDeclaration(
        PlayerSessionFace.watchingFace,
        PlayerSessionEntryRequirement.none,
      ),
    };

/// 所在面谓词：读进入声明表——面与进入前置在同一行声明；加取值漏行由
/// 结构断言（`player_session_test.dart`）拦下。
PlayerSessionFace faceOf(PlayerSessionMode mode) =>
    playerSessionEntryDeclarationTable[mode]!.face;

/// 进入结果族三成员（不抛异常）：已进入 / 本就在目标态（幂等 no-op，不是
/// 错误）/ 不成立。「本就在目标态」与仓内「交互越界 = 静默 no-op」口径
/// 一致。
enum PlayerSessionEntryResult { entered, alreadyThere, rejected }

/// 待办槽载荷：一次待宿主编排的进入。非宿主发起方（如气泡里的「八拍矫正」
/// 按钮）落一个待办；宿主完成前置编排后经唯一提交入口提交。
class PlayerSessionPendingEntry {
  const PlayerSessionPendingEntry(this.target);

  /// 待进入的目标取值。
  final PlayerSessionMode target;
}

/// 播放会话模式值：模式取值 + 派生谓词 + 待办槽。不可变值，一切变更经
/// [PlayerSessionModel] 的写缝。
class PlayerSession {
  const PlayerSession(this.mode) : pendingEntry = null;
  const PlayerSession._(this.mode, this.pendingEntry);

  /// 当前模式取值。
  final PlayerSessionMode mode;

  /// 待办槽：非空即「有一次待处理的进入」。
  final PlayerSessionPendingEntry? pendingEntry;

  /// 控制层展开位——由取值派生，无独立写入口。
  bool get controlOpen => faceOf(mode) == PlayerSessionFace.editorFace;

  /// 是否处于对比态（对比-播放态、对比-控制层或取景调节态）。
  bool get isCompare =>
      mode == PlayerSessionMode.compareWatching ||
      mode == PlayerSessionMode.compareEditing ||
      mode == PlayerSessionMode.compareFraming;

  bool get isBeatCorrectionStandby =>
      mode == PlayerSessionMode.beatCorrectionStandby;

  bool get isSegmentDensityStandby =>
      mode == PlayerSessionMode.segmentDensityStandby;

  /// 是否处于投屏态（投屏-控制层或投屏-观看态）。两值同属一个取值族：只
  /// 差控制层展开位——投屏态的三处换装（底排空集 / 只留分段轨 / 投屏顶栏）
  /// 与「断开投屏」都按本谓词取。
  bool get isCast =>
      mode == PlayerSessionMode.castControl ||
      mode == PlayerSessionMode.castWatching;

  PlayerSession _withMode(PlayerSessionMode mode) =>
      PlayerSession._(mode, pendingEntry);

  PlayerSession _withPending(PlayerSessionPendingEntry? pending) =>
      PlayerSession._(mode, pending);
}

/// 播放会话模式状态模型。唯一写路径是 [enter]（进入目标态）；
/// [collapse] / [openEditor] 是走同一声明表的具名便捷，不构成第二条写路径；
/// 非宿主发起经 [requestEntry] 落待办，宿主编排后 [commit]（唯一提交入口）
/// 或 [cancelPendingEntry]；[reset] 把值复位到观看态（换视频、离开播放页
/// 两个触发点调用）。
class PlayerSessionModel extends Notifier<PlayerSession> {
  @override
  PlayerSession build() => const PlayerSession(PlayerSessionMode.watching);

  /// 进入目标态——本库唯一写路径。自反进入返回「本就在目标态」、值一位
  /// 不动；未知目标在封闭枚举下不可表示，故今天不存在被拒绝的跃迁
  /// （「不成立」成员由空槽提交路径承载，见 [commit]）。
  ///
  /// 直接进入不清待办槽：宿主须对落下的待办显式 [commit] 或
  /// [cancelPendingEntry]，残留待办的去向不出本库之手。
  PlayerSessionEntryResult enter(PlayerSessionMode target) {
    if (state.mode == target) return PlayerSessionEntryResult.alreadyThere;
    state = state._withMode(target);
    return PlayerSessionEntryResult.entered;
  }

  /// 收起控制层 = 回观看态（待命态随收起退出由结构承载）。对比-控制层
  /// 收起 = 退到对比-播放态（对比态开关语义：收起不退出对比，退出经
  /// 顶栏槽或返回箭头）；投屏-控制层收起 = 退到投屏-观看态（同理：收起不
  /// 离开投屏态、也不断开投屏）；投屏-观看态本就收起，是幂等 no-op——不把
  /// 投屏态误收回普通观看态（那会让投屏会话悬挂）。穷尽 switch：加取值即
  /// 编译报错。
  PlayerSessionEntryResult collapse() => switch (state.mode) {
    PlayerSessionMode.compareEditing => enter(
      PlayerSessionMode.compareWatching,
    ),
    PlayerSessionMode.castControl => enter(PlayerSessionMode.castWatching),
    PlayerSessionMode.castWatching => PlayerSessionEntryResult.alreadyThere,
    PlayerSessionMode.watching ||
    PlayerSessionMode.editing ||
    PlayerSessionMode.beatCorrectionStandby ||
    PlayerSessionMode.segmentDensityStandby ||
    PlayerSessionMode.compareWatching ||
    PlayerSessionMode.compareFraming ||
    PlayerSessionMode.framing => enter(PlayerSessionMode.watching),
  };

  /// 退出对比态 = 回观看态（单画面；退出口径：对比态内返回箭头先
  /// 退对比态回 `watching`、再按才回首页；系统返回同走此便捷）。非对比
  /// 态调用是幂等 no-op（返回「本就在目标态」、值一位不动——不误收控制
  /// 层）。对比态内需保持控制层承接面的出口（顶栏槽开关、音画同步工具
  /// 先退对比）不经此便捷、直接 `enter(editing)`（见各调用点注释）。
  PlayerSessionEntryResult exitCompare() => state.isCompare
      ? enter(PlayerSessionMode.watching)
      : PlayerSessionEntryResult.alreadyThere;

  PlayerSessionEntryResult openEditor() => enter(PlayerSessionMode.editing);

  /// 断开投屏 = 回编辑态（**唯一退出路径**：顶栏那枚「断开投屏」工具与
  /// 左上角退出箭头是同一动作的两处入口，两处都调本便捷）。非投屏态调用是
  /// 幂等 no-op（返回「本就在目标态」、值一位不动——不误收控制层）。
  /// 会话与递出通道的收尾归投屏运行域，本域只管模式值。
  PlayerSessionEntryResult exitCast() => state.isCast
      ? enter(PlayerSessionMode.editing)
      : PlayerSessionEntryResult.alreadyThere;

  /// 落待办：槽是单槽，重复落待办不叠加（后一次取代前一次）。
  void requestEntry(PlayerSessionMode target) {
    state = state._withPending(PlayerSessionPendingEntry(target));
  }

  /// 唯一提交入口：宿主完成前置编排后提交待办里的目标。空槽提交 = 结构
  /// 不成立，返回「不成立」、值一位不动、不抛异常。
  PlayerSessionEntryResult commit() {
    final pending = state.pendingEntry;
    if (pending == null) return PlayerSessionEntryResult.rejected;
    state = state._withPending(null);
    return enter(pending.target);
  }

  /// 取消待办：值一位不动、槽清空。
  void cancelPendingEntry() {
    state = state._withPending(null);
  }

  /// 复位：回到观看态并清空待办。幂等；四个手写退出点收成这一次调用。
  void reset() {
    state = const PlayerSession(PlayerSessionMode.watching);
  }
}

final playerSessionProvider =
    NotifierProvider<PlayerSessionModel, PlayerSession>(PlayerSessionModel.new);
