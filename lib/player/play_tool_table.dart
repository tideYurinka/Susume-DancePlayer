/// 看片工具槽表：看片工具的声明单一来源。
///
/// **模块面**：[PlayToolIcon]（图标 token）→ [PlayToolSlot]（一条槽的
/// 声明：槽键、文案、图标、门清单、软门标记、提示文案）→ 六份具名行集
/// [kPlayToolRowLandscapeTopBar]（常规档横屏顶栏，十一条工具加两条分隔线，
/// 十三个位置）/ [kPlayToolRowLandscapeTopBarCompact]（紧凑档横屏顶栏，
/// 九条加两条分隔线，十一个位置）/ [kPlayToolRowPortraitTitleBar]
/// （竖屏标题栏，四条）/
/// [kPlayToolRowPortraitVideoToolbarTop] 与
/// [kPlayToolRowPortraitVideoToolbarBottom]（竖屏视频工具栏两行，两条 + 五条）/
/// [kPlayToolRowCastTopBar]（投屏态顶栏，三枚——「断开投屏」→「系统镜像」→
/// 末位的「查看引导」；规格里最终五枚，倍速切换与画面开关随后两票按次序
/// 补位）；
/// 顶栏取哪一份行集由纯件 [playToolTopBarRowFor] 一处决定——**投屏态两值
/// 有自己那份行集（与朝向、紧凑档无关），其余取值沿用朝向与紧凑档**
/// （[playToolLandscapeTopBarRow]）；行集成员 [PlayToolRowItem]（一条槽的
/// 引用，或一条分隔线）。槽身份
/// [PlayToolSlotId] 是唯一消费点穷尽 `switch` 装配活值的判定依据——加槽
/// 漏补装配即编译报错。可点性派生
/// [playToolTappable]（无门命中时随硬启用位、有门命中时随判定结果，软门另
/// 或上自己的标记）。
///
/// **与标注工具区的关系**：两个工具面并列、各自成表；只共用门判定——
/// 门种类 [ToolGateKind] 与求值入口 [evaluateDeclaredGates] 取自槽库
/// `tool_slots.dart`，「灰着的入口按下去绝不执行动作」这条契约因此只有
/// 一份实现。顶栏的门事实今天有两类：那枚软门的「有没有作用对象」
/// （求值的 `hasSubject` 入参）与投屏入口那五条（`facts` 入参，票 #35
/// 起升格为完整事实装配）——两类都经同一次 [evaluateDeclaredGates] 求值，
/// 命中集 = 声明 ∩ 事实。
///
/// **什么进表、什么进视图**：唯一判据是「不动的东西才进表」——槽键、
/// 文案、图标、门清单、软门标记、引导锚点声明、提示文案七样不变的事实进表；
/// 一切
/// 需要构建期求值或实例同一性的东西进视图，由唯一消费点按槽装配：激活位
/// 与激活标签
/// （生效中的设置）、倍率读数、定宽（依赖系统字号）、气泡锚点（需要稳定
/// 实例）、监听对象（需要与状态机同一个实例）、点击动作（捕获状态与
/// 容器）、图标到 `IconData` 的映射（[PlayToolIcon] 只是 token，表不引
/// Flutter）。派生状态（可点性、生效标签、生效激活位）由视图在装配时
/// 算出，不存进表。
///
/// **一条工具一条声明**：十四条槽各一条 `const` 声明，六份行集引用同一份
/// ——同一条槽出现在多份行集时结构上不可能出现两份可能分家的编码。
/// 「分隔线不进竖屏行」是行集里明写的成员事实（竖屏三份行集不含分隔线
/// 成员），不再依赖任何字段的缺省值。
///
/// 本模块纯 Dart、零框架依赖（不引 Flutter、不引 dart:ui、不引
/// Riverpod），不读状态、不依赖任何外部对象，可在不启动 widget 环境的
/// 情况下直测；不许反向依赖页面侧。
library;

import 'package:dance_learning_app/player/tool_slots.dart';
import 'package:dance_learning_app/player_session/player_session.dart'
    show PlayerSessionMode;

/// 看片工具的图标 token：表不引 Flutter，`IconData` 由装配点按 token
/// 映射（映射取值 = 今天十四枚图标的逐位对照，见各条目注释）。
enum PlayToolIcon {
  undo, // Icons.undo
  redo, // Icons.redo
  surroundSound, // Icons.surround_sound（音画同步）
  graphicEq, // Icons.graphic_eq（节拍提示）
  flip, // Icons.flip（全局镜像）
  flipCameraAndroid, // Icons.flip_camera_android（局部镜像）
  speed, // Icons.speed（倍速设置）
  compare, // Icons.compare（对比练习）
  cropFree, // Icons.crop_free（取景调整）
  cast, // Icons.cast（投屏）
  castDisconnect, // Icons.tv_off（断开投屏）
  systemMirror, // Icons.screen_share（系统镜像）
  helpOutline, // Icons.help_outline（查看引导）
  more, // Icons.more_horiz（更多）
}

/// 槽身份：唯一消费点的穷尽 `switch` 按它装配活值——新增一条槽
/// 而漏补装配时编译期报错（底排 [ToolSlotId] 同款纪律）。图标 token 是
/// 声明字段、可能重值，不作身份；身份只归本枚举。
enum PlayToolSlotId {
  undo,
  redo,
  avSync,
  beatPrompt,
  mirror,
  localMirror,
  speedSettings,
  compare,
  framingAdjust,

  /// 投屏（编辑面顶栏入口：进投屏准备面板）。
  cast,

  /// 断开投屏（只在投屏态顶栏行集内：同一动作的第二处入口是左上角
  /// 退出箭头）。
  disconnectCast,

  /// 系统镜像（只在投屏态顶栏行集内：先断开投屏、再跳到系统自带的
  /// 「投屏 / 无线显示」设置，见 [kPlayToolSystemMirror]）。
  systemMirror,
  guide,
  more,
}

/// 单条看片工具槽的声明：槽键、文案、图标、门清单、软门标记、引导锚点与
/// 提示文案。
///
/// 槽键字符串与渲染层 Key 逐位一致，是渲染层与测试共同的定位手段；
/// 门清单显式声明（无门写成空清单，不靠缺席表达——读者能区分「故意
/// 不管」与「忘了管」）；软门 = 置灰但仍可点、点击由动作自己解释原因。
class PlayToolSlot {
  const PlayToolSlot({
    required this.id,
    required this.key,
    required this.label,
    required this.icon,
    required this.gates,
    required this.softGate,
    this.carriesGuideAnchor = false,
    this.tooltip,
  });

  /// 槽身份（装配点穷尽 `switch` 的判定依据；全表唯一——两条槽共用同一
  /// 身份会让装配臂无法区分）。
  final PlayToolSlotId id;

  /// 槽键（与渲染层的 Key 逐位一致）。
  final String key;

  /// 文案（未激活态的基础标签；激活态标签是构建期取值，归视图）。
  final String label;

  /// 图标 token（`IconData` 的映射在装配点）。
  final PlayToolIcon icon;

  /// 本动作有哪些门（显式声明；无门即空清单）。
  final List<ToolGateKind> gates;

  /// 软门：置灰但仍可点，点击由动作解释原因（今天只有「局部镜像」无片段
  /// 一处；其余槽「置灰即不可点」的硬门）。判定表第②行（无对象）
  /// 起本身即「置灰、可点」，本字段与之同向——顶栏的可点性声明面不因此
  /// 改写成读底排判定。
  final bool softGate;

  /// 本槽是否承载引导锚点（锚点 key 就是 [key]——与底栏工具槽
  /// `ToolSlot.carriesGuideAnchor` 同形、同一口径）。**逐槽声明**而不是按
  /// 槽键集判：同一枚槽键出现在多份行集里是同一份声明，声明为真的槽由渲染
  /// 点包锚点包装器，读者从声明就能区分「故意不接」与「忘了接」。
  final bool carriesGuideAnchor;

  /// 入口上的**提示文案**（长按/悬停时显示；null = 本槽没有额外提示）。
  /// 文案是「不动的事实」故进表，与 [label] 同源同处：今天只有「系统镜像」
  /// 声明一条——那枚入口自己承担两条路的取舍说明（ADR-0004：整屏镜像有
  /// 延迟、手机屏要亮着、控制层也上电视），这是它的**唯一一份**文案，
  /// 准备面板空态里那同一枚入口也读它。
  final String? tooltip;
}

/// 十四条槽声明（唯一一份）：横屏顶栏两份、竖屏标题栏、竖屏视频工具栏
/// 两行、投屏态顶栏共六份行集引用同一批，不内联复制。

/// 撤销（硬启用位 = 有历史可撤销）。
const PlayToolSlot kPlayToolUndo = PlayToolSlot(
  id: PlayToolSlotId.undo,
  key: 'tool_undo',
  label: '撤销',
  icon: PlayToolIcon.undo,
  gates: [],
  softGate: false,
);

/// 重做（硬启用位 = 有可重做）。
const PlayToolSlot kPlayToolRedo = PlayToolSlot(
  id: PlayToolSlotId.redo,
  key: 'tool_redo',
  label: '重做',
  icon: PlayToolIcon.redo,
  gates: [],
  softGate: false,
);

/// 音画同步（气泡入口）。
const PlayToolSlot kPlayToolAvSync = PlayToolSlot(
  id: PlayToolSlotId.avSync,
  key: 'tool_av_sync',
  label: '音画同步',
  icon: PlayToolIcon.surroundSound,
  gates: [],
  softGate: false,
);

/// 节拍提示（气泡入口）。
const PlayToolSlot kPlayToolBeatPrompt = PlayToolSlot(
  id: PlayToolSlotId.beatPrompt,
  key: 'tool_beat_prompt',
  label: '节拍提示',
  icon: PlayToolIcon.graphicEq,
  gates: [],
  softGate: false,
);

/// 全局镜像（镜像开启 → 琥珀激活）。
const PlayToolSlot kPlayToolMirror = PlayToolSlot(
  id: PlayToolSlotId.mirror,
  key: 'tool_mirror',
  label: '全局镜像',
  icon: PlayToolIcon.flip,
  gates: [],
  softGate: false,
);

/// 局部镜像总开关（顶栏唯一软门：无片段时置灰但仍可点，点一下弹
/// 「请添加局部镜像片段」且不产生任何状态变化；门 = 无对象，事实 =
/// 没有局部镜像片段）。**顶栏唯一承载引导锚点的槽**：局部镜像第二步指住
/// 这枚开关，渲染点按本声明包装锚点（锚点 key 即槽键 `tool_local_mirror`）。
const PlayToolSlot kPlayToolLocalMirror = PlayToolSlot(
  id: PlayToolSlotId.localMirror,
  key: 'tool_local_mirror',
  label: '局部镜像',
  icon: PlayToolIcon.flipCameraAndroid,
  gates: [ToolGateKind.noSubject],
  softGate: true,
  carriesGuideAnchor: true,
);

/// 倍速设置（气泡入口；激活态标签与倍率读数归视图）。
const PlayToolSlot kPlayToolSpeedSettings = PlayToolSlot(
  id: PlayToolSlotId.speedSettings,
  key: 'tool_speed_settings',
  label: '倍速设置',
  icon: PlayToolIcon.speed,
  gates: [],
  softGate: false,
);

/// 对比练习开关（对比态内激活高亮）。
const PlayToolSlot kPlayToolCompare = PlayToolSlot(
  id: PlayToolSlotId.compare,
  key: 'tool_compare',
  label: '对比练习',
  icon: PlayToolIcon.compare,
  gates: [],
  softGate: false,
);

/// 取景调整：普通编辑面与对比-控制层共用的同一枚
/// 取景入口（点按目标按当前态分派：对比-控制层 → 分屏路径；其余编辑面 →
/// 单画面路径，分派归装配点）。文案恒为「取景调整」、裁剪类图标；装载
/// 未完成门归页面级声明（[PageWriteEntryId.framingAdjust]——写公开标记
/// 文件的直写入口），本表不重复声明；录制期（含准备期）的拒绝沿待办编排
/// 的既有路径（宿主取消进入、静默），不新增门种。
const PlayToolSlot kPlayToolFramingAdjust = PlayToolSlot(
  id: PlayToolSlotId.framingAdjust,
  key: 'tool_framing_adjust',
  label: '取景调整',
  icon: PlayToolIcon.cropFree,
  gates: [],
  softGate: false,
);

/// 投屏（编辑面顶栏入口）：点按落待办进**投屏准备**（进入前置声明见
/// `player_session.dart` 的进入声明表），宿主编排准备面板与起投后经唯一
/// 提交入口提交。
///
/// **本槽声明五条门**（票 #35）：副本丢失 / 音画同步校准中 / 录制中（含
/// 准备期）/ 对比态或取景调节态 / 渲染进行中。命中任一条即置灰，但
/// **仍可点**——按下去只解释原因、绝不落待办、绝不开面板（判定表与点击
/// 语义复用底排同一条，见 `tool_slots.dart`）。**接收端不可达 / 搜不到**
/// 不在这五条里：它只能靠发现或起投那一下才知道，拦在准备面板与起投失败
/// 面上（短暂提示），做不成入口置灰。
///
/// 准备面板里那条「副本丢失」拦下是同一事实的**第二道**（防御进入与面板
/// 之间文件才丢的窗口），两道同说一句话。
const PlayToolSlot kPlayToolCast = PlayToolSlot(
  id: PlayToolSlotId.cast,
  key: 'tool_cast',
  label: '投屏',
  icon: PlayToolIcon.cast,
  gates: [
    ToolGateKind.castCopyMissing,
    ToolGateKind.castAvSyncCalibrating,
    ToolGateKind.castRecording,
    ToolGateKind.castCompareOrFraming,
    ToolGateKind.castRendering,
  ],
  softGate: false,
);

/// 断开投屏：**只在投屏态顶栏行集**（[kPlayToolRowCastTopBar]）里的一枚，
/// 与左上角退出箭头同义——两处入口都回编辑态。本槽不改文档、无门、恒可点
/// （「断开本身不再抛」的会话契约）。
const PlayToolSlot kPlayToolDisconnectCast = PlayToolSlot(
  id: PlayToolSlotId.disconnectCast,
  key: 'tool_cast_disconnect',
  label: '断开投屏',
  icon: PlayToolIcon.castDisconnect,
  gates: [],
  softGate: false,
);

/// 系统镜像：**只在投屏态顶栏行集**（[kPlayToolRowCastTopBar]）里的一枚，
/// 位置在「断开投屏」与末位的「查看引导」之间。点它 = **先断开投屏（含立即
/// 停服）、再跳**系统自带的「投屏 / 无线显示」设置——投屏与整屏镜像同时
/// 在场，电视上会两份画面打架；跳不动时降级到显示设置、再不行给一句**短暂
/// 提示**（降级链见 `lib/cast/platform_system_mirror.dart`）。
///
/// 本项目**不做屏幕镜像**（ADR-0004）；这枚入口只负责把用户送过去，因此
/// **无门、恒可点**——"跳不动"不是置灰的理由，是那条降级链要回答的事。
/// [tooltip] 是本槽唯一的提示文案：一句话说清两条路的代价差，准备面板
/// "搜不到接收端"空态里的同一枚入口也读它。
const PlayToolSlot kPlayToolSystemMirror = PlayToolSlot(
  id: PlayToolSlotId.systemMirror,
  key: 'tool_system_mirror',
  label: '系统镜像',
  icon: PlayToolIcon.systemMirror,
  gates: [],
  softGate: false,
  tooltip: kSystemMirrorHintText,
);

/// 系统镜像入口的提示文案（唯一一份）：一句话说清两条路的边界——整屏镜像
/// 那三笔代价（有延迟、手机屏要亮着、控制层也上电视）与"我们这条路"推的是
/// 什么。投屏态顶栏那枚与准备面板"搜不到接收端"空态那枚共用。
const String kSystemMirrorHintText =
    '整屏镜像：有延迟、手机屏要亮着、控制层也上电视；'
    '我们这条路推的是渲染好的投屏副本';

/// 查看引导（进新手引导页）。
const PlayToolSlot kPlayToolGuide = PlayToolSlot(
  id: PlayToolSlotId.guide,
  key: 'tool_guide',
  label: '查看引导',
  icon: PlayToolIcon.helpOutline,
  gates: [],
  softGate: false,
);

/// 更多（紧凑档横屏顶栏的溢出容器入口）：向上弹出菜单承载
/// 「音画同步」「取景调整」「节拍提示」三枚，位置在「全局镜像」左侧。
/// 无门、非软门；**不承载引导锚点**——那三枚工具的引导锚点都在各自气泡
/// 内部，本入口自身不是任何引导步的锚。
const PlayToolSlot kPlayToolMore = PlayToolSlot(
  id: PlayToolSlotId.more,
  key: 'tool_more',
  label: '更多',
  icon: PlayToolIcon.more,
  gates: [],
  softGate: false,
);

/// 行集成员：一条槽的引用，或一条分隔线。分隔线是行集里的成员，不靠
/// 任何字段的缺省值表达「进不进某行」。
class PlayToolRowItem {
  const PlayToolRowItem.slot(PlayToolSlot this.slot) : isSeparator = false;

  const PlayToolRowItem.separator() : slot = null, isSeparator = true;

  /// 被引用的槽声明（分隔线成员为 null）。
  final PlayToolSlot? slot;

  /// 是否分隔线。
  final bool isSeparator;
}

/// 一份有序行集：某落点下有哪些成员、什么次序，即声明次序。
class PlayToolRowSet {
  const PlayToolRowSet(List<PlayToolRowItem> items) : _items = items;

  final List<PlayToolRowItem> _items;

  /// 本行集的成员与次序（声明次序即呈现次序）。
  List<PlayToolRowItem> get items => List.unmodifiable(_items);

  /// 本行集的槽声明（按次序，跳过分隔线成员）。
  List<PlayToolSlot> get slots => [
    for (final item in _items)
      if (!item.isSeparator) item.slot!,
  ];
}

/// 横屏顶栏：十一条工具加两条分隔线，十三个位置——撤销 → 重做 → ｜ →
/// 音画同步 → 取景调整 → 节拍提示 → 全局镜像 → 局部镜像 → 倍速设置 → ｜ →
/// 对比练习 → 投屏 → 查看引导（取景调整在「音画同步」右侧；投屏与
/// 对比练习同属会话态入口、紧邻其右）。
const PlayToolRowSet kPlayToolRowLandscapeTopBar = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolUndo),
  PlayToolRowItem.slot(kPlayToolRedo),
  PlayToolRowItem.separator(),
  PlayToolRowItem.slot(kPlayToolAvSync),
  PlayToolRowItem.slot(kPlayToolFramingAdjust),
  PlayToolRowItem.slot(kPlayToolBeatPrompt),
  PlayToolRowItem.slot(kPlayToolMirror),
  PlayToolRowItem.slot(kPlayToolLocalMirror),
  PlayToolRowItem.slot(kPlayToolSpeedSettings),
  PlayToolRowItem.separator(),
  PlayToolRowItem.slot(kPlayToolCompare),
  PlayToolRowItem.slot(kPlayToolCast),
  PlayToolRowItem.slot(kPlayToolGuide),
]);

/// 紧凑档横屏顶栏：九条工具加两条分隔线，十一个位置——撤销 → 重做 → ｜ →
/// 更多 → 全局镜像 → 局部镜像 → 倍速设置 → ｜ → 对比练习 → 投屏 →
/// 查看引导。
/// 「更多」落在「全局镜像」左侧，使「全局镜像 → 局部镜像 → 倍速设置」
/// 这组视图设置的相邻关系不被打断；音画同步 / 取景调整 / 节拍提示由
/// 「更多」的向上弹出菜单承载，次序为音画同步 → 取景调整 → 节拍提示。
const PlayToolRowSet kPlayToolRowLandscapeTopBarCompact = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolUndo),
  PlayToolRowItem.slot(kPlayToolRedo),
  PlayToolRowItem.separator(),
  PlayToolRowItem.slot(kPlayToolMore),
  PlayToolRowItem.slot(kPlayToolMirror),
  PlayToolRowItem.slot(kPlayToolLocalMirror),
  PlayToolRowItem.slot(kPlayToolSpeedSettings),
  PlayToolRowItem.separator(),
  PlayToolRowItem.slot(kPlayToolCompare),
  PlayToolRowItem.slot(kPlayToolCast),
  PlayToolRowItem.slot(kPlayToolGuide),
]);

/// 投屏态顶栏：**三枚**——断开投屏 → 系统镜像 → 查看引导（查看引导恒在
/// 末位）。它是投屏态两值自己的那份行集：与朝向、紧凑档无关，也不占编辑态
/// 的位置预算（编辑态行集各自照旧）。规格里投屏态顶栏最终五枚（倍速切换、
/// 画面开关、断开投屏、系统镜像、查看引导），倍速切换与画面开关随后两票
/// 接入——补位只在这份声明里加成员，不另开第二处次序编码。
const PlayToolRowSet kPlayToolRowCastTopBar = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolDisconnectCast),
  PlayToolRowItem.slot(kPlayToolSystemMirror),
  PlayToolRowItem.slot(kPlayToolGuide),
]);

/// 横屏顶栏行集选择（**唯一读点**）：吃档位判据的结果（
/// [editorIsCompact] 的返回值——判据本身住在播放页几何骨架，本表不重算），
/// 紧凑档给紧凑行集 [kPlayToolRowLandscapeTopBarCompact]、常规档给原行集
/// [kPlayToolRowLandscapeTopBar]。行集与档位的对应只有这一处。
PlayToolRowSet playToolLandscapeTopBarRow({required bool compact}) =>
    compact ? kPlayToolRowLandscapeTopBarCompact : kPlayToolRowLandscapeTopBar;

/// 「模式 → 顶栏行集」唯一映射：**投屏态两值取自己那份行集**
/// （[kPlayToolRowCastTopBar]，与朝向、紧凑档无关——投屏态是会话模式的一族，
/// 三处换装随族走）；**其余取值沿用朝向与紧凑档**（竖屏标题栏 /
/// 横屏 [playToolLandscapeTopBarRow]）。穷尽 switch：加会话模式取值即编译
/// 报错，不会静默落到某个默认面。
PlayToolRowSet playToolTopBarRowFor({
  required PlayerSessionMode mode,
  required bool portrait,
  required bool compact,
}) => switch (mode) {
  PlayerSessionMode.castControl ||
  PlayerSessionMode.castWatching => kPlayToolRowCastTopBar,
  PlayerSessionMode.watching ||
  PlayerSessionMode.editing ||
  PlayerSessionMode.beatCorrectionStandby ||
  PlayerSessionMode.segmentDensityStandby ||
  PlayerSessionMode.compareWatching ||
  PlayerSessionMode.compareEditing ||
  PlayerSessionMode.compareFraming ||
  PlayerSessionMode.framing =>
    portrait
        ? kPlayToolRowPortraitTitleBar
        : playToolLandscapeTopBarRow(compact: compact),
};

/// 竖屏标题栏：四条——撤销 → 重做 → 投屏 → 查看引导（返回键与标题之后）。
const PlayToolRowSet kPlayToolRowPortraitTitleBar = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolUndo),
  PlayToolRowItem.slot(kPlayToolRedo),
  PlayToolRowItem.slot(kPlayToolCast),
  PlayToolRowItem.slot(kPlayToolGuide),
]);

/// 竖屏视频工具栏**第一行**：两条——全局镜像 → 局部镜像（靠右；各对到
/// 第二行最右两列的中心）。
const PlayToolRowSet kPlayToolRowPortraitVideoToolbarTop = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolMirror),
  PlayToolRowItem.slot(kPlayToolLocalMirror),
]);

/// 竖屏视频工具栏**第二行**：五条——音画同步 → 取景调整 → 节拍提示 →
/// 倍速设置 → 对比练习（画面正下方一行；取景调整在「音画同步」右侧，
/// 拆两行归）。
const PlayToolRowSet kPlayToolRowPortraitVideoToolbarBottom = PlayToolRowSet([
  PlayToolRowItem.slot(kPlayToolAvSync),
  PlayToolRowItem.slot(kPlayToolFramingAdjust),
  PlayToolRowItem.slot(kPlayToolBeatPrompt),
  PlayToolRowItem.slot(kPlayToolSpeedSettings),
  PlayToolRowItem.slot(kPlayToolCompare),
]);

/// 可点性派生：无门命中时随硬启用位（[enabled]——撤销/重做等置灰即不可
/// 点）；有门命中时随判定结果（共用底排同一求值入口 [evaluateDeclaredGates]
/// 与判定表——「灰着的入口按下去绝不执行动作」只有一份实现），软门另或上
/// 自己的标记（今天与判定表第②行同向：无对象也是「置灰、可点」）。
///
/// 入参 [hasSubject] 是顶栏那枚软门的门事实「有没有作用对象」（具名谓词）；
/// [facts] 是**完整事实装配**（票 #35 起）：投屏入口那五条门的事实都在里面，
/// 不声明它们的槽一位不受影响（命中集 = 声明 ∩ 事实）。顶栏因此与底排读同
/// 一张判定表——门种 → 可点性不在本处另判。
bool playToolTappable(
  PlayToolSlot slot, {
  required bool hasSubject,
  required bool enabled,
  ToolFacts facts = const ToolFacts(),
}) {
  final verdict = evaluateDeclaredGates(
    slot.gates.toSet(),
    facts,
    hasSubject: hasSubject,
  );
  return verdict.available ? enabled : slot.softGate || verdict.tappable;
}
