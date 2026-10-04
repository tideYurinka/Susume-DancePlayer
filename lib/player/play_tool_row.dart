part of 'control_layer.dart';

/// 顶栏播放设置工具行与竖屏视频工具栏：行集声明遍历、活值束装配、单槽
/// 视图渲染、标签收起量宽与分隔线。槽声明在 play_tool_table.dart，动作
/// 按槽身份在 `_assemblePlayTool` 穷尽装配。

extension _ControlLayerPlayToolRow on ControlLayerState {
  /// 顶栏唯一的门事实（收窄为具名谓词）：**有没有作用对象**——
  /// 今天它就是「有没有局部镜像片段」。不再传恒空的宽类型事实对象
  /// （[ToolFacts] 只活在共用求值入口内部）；将来顶栏真出现第二种门时，
  /// 把本谓词升格成完整事实装配是一次有依据的改动。
  bool get _playToolHasSubject =>
      ref.watch(localMirrorFragmentsProvider).isNotEmpty;

  /// 顶栏装配一次所需的**活值**：声明在表（[PlayToolSlot]），本束
  /// 只装每次构建会变的求值结果；镜像状态机不经此束——装配点直读
  /// `widget.mirror`，使监听对象触发的重装配取到当前值。
  _PlayToolLive get _playToolLive {
    // 顶栏播放设置工具图标的激活反馈只看「生效中」的设置。
    // 倍速槽并入步进后，激活语义扩为「倍速侧任一生效中」——步进
    // 生效，或步进停用且手动倍速 ≠ 1.0（域谓词 [SpeedControlState.speedSideInEffect]）。
    final speed = ref.watch(speedControlProvider);
    // 撤销/重做按钮（顶栏工具区左起），无历史/无可重做置灰。
    final editHistory = ref.watch(annotationEditHistoryProvider);
    // 「对比练习」槽的激活高亮 = 处于对比态（对比-控制层内可见）。
    final compareActive = ref.watch(playerSessionProvider).isCompare;
    // 定宽：激活标签 + 倍率槽形态与未激活形态取宽者，使启用 /
    // 停用步进不改槽宽、顶栏不重排；渲染宽与定宽同源。
    final speedSlotWidth = topBarSpeedSlotWidth(
      textScaler: MediaQuery.textScalerOf(context),
    );
    return _PlayToolLive(
      speed: speed,
      canUndo: editHistory.canUndo,
      canRedo: editHistory.canRedo,
      hasSubject: _playToolHasSubject,
      compareActive: compareActive,
      speedSlotWidth: speedSlotWidth,
    );
  }

  /// 一行看片工具：行集声明驱动——有哪些槽、什么次序、有没有
  /// 分隔线全由行集决定，本行不写死任何子序；分隔线是行集成员。每条槽经
  /// [_assemblePlayTool] 按身份装配成视图件。
  ///
  /// 标签收起判据（视口无关）：本行的工效不变量是
  /// **全部入口一次放下、命中盒不小于命中下限、不整体缩放**（缩放会使命中
  /// 偏移失真）；可用宽（[maxWidth] = 顶栏内容宽 − 返回键 −
  /// 工具间隙，null = 判据不适用、永不收标签；标题由 `Expanded` 吸收余量、
  /// 其自身有自动滚动与裁剪）放不下带标签形态时收起文字标签、保留图标入口
  /// （逐槽钳到命中下限，语义经 [Semantics] 保留）——与节拍提示面板「唯一
  /// 判据是可用宽是否放得下」同一范式。分隔线各 1px 不入估宽（亚像素级）。
  Widget _playToolRow(PlayToolRowSet rowSet, {double? maxWidth}) {
    final live = _playToolLive;
    // 量宽与渲染同源（规则 2）：估宽吃调用处同一 textScaler。
    final textScaler = MediaQuery.textScalerOf(context);
    final views = [
      for (final item in rowSet.items)
        if (!item.isSeparator) _assemblePlayTool(item.slot!, live),
    ];
    // 带标签形态的行宽实测：定宽槽（倍速）用定宽，其余按 [_topBarSlotWidth]
    // 同一口径估宽。
    var labeledWidth = 0.0;
    var separatorCount = 0;
    for (final item in rowSet.items) {
      if (item.isSeparator) {
        separatorCount++;
        continue;
      }
      final v = views.firstWhere((view) => identical(view.slot, item.slot));
      labeledWidth +=
          v.fixedWidth ?? _topBarSlotWidth(v.label, textScaler: textScaler);
    }
    // 分隔线各 1px 也计入估宽（槽位到 12 位后窄视口
    // 已无余量，漏计 2px 即真溢出）。
    labeledWidth += separatorCount.toDouble();
    // 收纳判据带安全余量：估宽与真实渲染之间存在
    // 逐槽取整/对齐的累积差（槽位到 12 位后窄视口无余量吸收），判据宁早
    // 不晚——早收标签只损失文字、晚收整行真溢出。
    const widthSafety = 8.0;
    final iconOnly = maxWidth != null && labeledWidth > maxWidth - widthSafety;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in rowSet.items)
          item.isSeparator
              ? const _PlayToolSeparator()
              : _buildPlayToolSlot(item.slot!, live, iconOnly: iconOnly),
      ],
    );
  }

  /// 可点性派生（共用求值入口的短手）：门事实取 [_playToolHasSubject]。
  bool _playToolTappable(PlayToolSlot slot, _PlayToolLive live, bool enabled) =>
      playToolTappable(slot, hasSubject: live.hasSubject, enabled: enabled);

  /// 单槽视图件（气泡锚点 + Listenable 包裹在此统一处理）：监听对象触发时
  /// **重装配**（按同一槽身份取当前活值，如镜像琥珀），不能用旧视图。
  Widget _buildPlayToolSlot(
    PlayToolSlot slot,
    _PlayToolLive live, {
    required bool iconOnly,
  }) {
    final view = _assemblePlayTool(slot, live);
    final listenable = view.listenable;
    return listenable != null
        ? ListenableBuilder(
            listenable: listenable,
            builder: (_, _) => _renderPlayTool(
              _assemblePlayTool(slot, live),
              iconOnly: iconOnly,
            ),
          )
        : _renderPlayTool(view, iconOnly: iconOnly);
  }

  /// 条目装配（唯一映射点）：按槽身份穷尽 `switch`——新增一条槽
  /// 而漏补装配时编译期报错（底排槽面同款纪律）。表给声明（槽键、文案、
  /// 图标 token、门清单、软门标记），本 switch 只装配活值：可用位、激活位、
  /// 生效标签、倍率读数、定宽、气泡锚点、监听对象与点击动作；派生
  /// （可点性）经 [playToolTappable] 走共用求值入口。
  _PlayToolView _assemblePlayTool(PlayToolSlot slot, _PlayToolLive live) {
    return switch (slot.id) {
      // 撤销/重做位于顶栏工具区左起；无历史/无可重做置灰。
      // 撤销/重做入口走标注编辑模块（内部先清选中）。
      PlayToolSlotId.undo => _PlayToolView(
        slot: slot,
        enabled: live.canUndo,
        tappable: _playToolTappable(slot, live, live.canUndo),
        onTap: () => ref.read(annotationEditorProvider).undo(),
      ),
      PlayToolSlotId.redo => _PlayToolView(
        slot: slot,
        enabled: live.canRedo,
        tappable: _playToolTappable(slot, live, live.canRedo),
        onTap: () => ref.read(annotationEditorProvider).redo(),
      ),
      // 音画同步入口：节拍提示紧左（撤销/重做分隔线之后、
      // 节拍提示之前）；点开锚定小气泡（当前设备名 + 读数 + −/＋ + 重置，
      // 与倍速/节拍提示气泡互斥单开）。气泡展开不是生效态——不点亮琥珀。
      PlayToolSlotId.avSync => _PlayToolView(
        slot: slot,
        tappable: true,
        bubbleLink: _avSyncLink,
        onTap: _activateAvSync,
      ),
      // 节拍提示入口：顶栏
      // 播放设置工具体系；点开节拍提示锚定气泡（与数拍
      // 浮层选中态角工具同一气泡组件，互斥单开）。气泡展开不是设置生效
      // 态——不点亮琥珀激活。
      PlayToolSlotId.beatPrompt => _PlayToolView(
        slot: slot,
        tappable: true,
        bubbleLink: _beatPromptLink,
        onTap: _activateBeatPrompt,
      ),
      // 镜像状态接线：镜像开启即琥珀；控制器为 Listenable，
      // 开启/关闭即时重装配（[_buildPlayToolSlot]）。改名
      // 「全局镜像」（槽键与点击行为不变，仍是整片开关）。
      PlayToolSlotId.mirror => _PlayToolView(
        slot: slot,
        tappable: true,
        listenable: widget.mirror,
        active: widget.mirror.mirrored,
        onTap: _toggleMirror,
      ),
      // 局部镜像总开关：紧邻「全局镜像」右侧、同一分隔
      // 段内；有片段时可点、点亮琥珀 = 总开关开（片段整组生效），再点取消。
      // **顶栏软门之一**（共两处，另一处 = 标题改名入口受装载门）：
      // 无片段时置灰但仍可点，点一下弹居中轻提示「请添加局部镜像片段」且不
      // 产生任何状态变化（顶栏其余槽一律「置灰即不可点」的硬门，见
      // [_PlayTool] 的 tappable 注释）。门事实 = 具名谓词
      // [_playToolHasSubject]（同一取值兼作置灰观感的视觉位）。
      PlayToolSlotId.localMirror => _PlayToolView(
        slot: slot,
        enabled: live.hasSubject,
        tappable: _playToolTappable(slot, live, live.hasSubject),
        listenable: widget.mirror,
        active: widget.mirror.localMirrorEnabled,
        onTap: _toggleLocalMirror,
      ),
      // 「倍速设置」槽：位于「局部镜像」右侧、「对比练习」之前
      // （同一分隔段内，段右即分隔线）；竖屏一行与横屏顶栏同读这一份次序。
      // 激活态标签按生效侧取「步进」/「倍速」——两者同为两字，
      // 搭配同口径定宽使启用 / 停用步进不改变槽宽与几何中心；倍率槽显示
      // 当前**生效**倍率（步进中随档位循环跳动）。
      PlayToolSlotId.speedSettings => _PlayToolView(
        slot: slot,
        tappable: true,
        active: live.speed.speedSideInEffect,
        activeLabel: live.speed.stepEnabled ? '步进' : _kSpeedSettingsActiveLabel,
        rate: live.speed.speedSideInEffect ? live.speed.effectiveRate : null,
        fixedWidth: live.speedSlotWidth,
        bubbleLink: _speedSettingsLink,
        onTap: () => _toggleBubble(SpeedBubbleMode.speed),
      ),
      // 顶栏只有「倍速设置」一个倍速槽：步进并入其气泡右栏（步进栏），
      // 无独立槽与锚点。
      // 对比练习开关：编辑面
      // 点按进入对比态（经待办槽的唯一提交入口，控制层随进入收起、单画面
      // 换分屏）；对比-控制层点按退出对比态回单画面（编辑面）。对比态内
      // 激活高亮（[compareActive]）。校准会话进行中拒绝进入（互斥）：
      // 静默 no-op，模式值与会话值一位不动。
      PlayToolSlotId.compare => _PlayToolView(
        slot: slot,
        tappable: true,
        active: live.compareActive,
        onTap: _toggleCompare,
      ),
      // 取景调整：普通编辑面与对比-控制层共用的
      // 同一枚取景入口。点按目标按当前态分派：对比-控制层 → 分屏取景
      // （compareFraming，只调源侧）；其余编辑面 → 单画面取景（framing）。
      // 两路都落待办、经唯一提交入口提交——装载未完成门在本入口挡下并弹
      // 既有提示（页面级声明 [PageWriteEntryId.framingAdjust]），录制期
      // （含准备期）沿编排的既有拒绝路径（取消待办、静默）。
      PlayToolSlotId.framingAdjust => _PlayToolView(
        slot: slot,
        tappable: true,
        onTap: _toggleFramingAdjust,
      ),
      // 取景入口统一为本枚顶栏「取景调整」，对比专用工具区只剩
      //
      // 「练习镜像」。
      // 查看引导：槽填上、不再恒置灰——无作用对象也可点（本槽
      // 无门禁，门事实不参与），点击进帮助域的新手引导页。
      PlayToolSlotId.guide => _PlayToolView(
        slot: slot,
        tappable: true,
        onTap: _openGuideUnits,
      ),
      // 「更多」：紧凑档横屏顶栏承载的三枚（音画同步 / 取景调整 /
      // 节拍提示）的入口，落在「全局镜像」左侧。点开向上弹出菜单
      // （[_showMoreMenu]），锚点 = 本钮自身（[onTapWithAnchor]）。气泡展开
      // 与模式进入都不是生效态——本槽不点亮；音画同步与节拍提示的气泡锚也
      // 接在本钮（紧凑档横屏下这两枚不常驻顶栏，[_buildBubbleOverlay]
      // 取 [_moreLink]，两枚气泡才有在场锚点）。
      PlayToolSlotId.more => _PlayToolView(
        slot: slot,
        tappable: true,
        bubbleLink: _moreLink,
        onTapWithAnchor: _showMoreMenu,
      ),
    };
  }

  /// 竖屏视频播放工具栏**两行**：第一行两枚（全局
  /// 镜像、局部镜像）靠右，第二行五枚（音画同步、取景调整、节拍提示、倍速
  /// 设置、对比练习）五等分列；第一行两枚各对到第二行最右两列的中心。
  ///
  /// 两行共用同一个**等分列网格**（[kPortraitVideoToolbarColumnCount] 列、
  /// 列宽 = 可用宽 ÷ 列数）：第二行每枚居中于自己那一列，第一行两枚居中于
  /// 最右两列（其余列留空）——两行的列中心由同一份分配天然同位，第一行不必
  /// 再算一次对齐。本落点读自己的具名行集（上排 / 下排两份，分隔线
  /// 不进竖屏行是行集里明写的成员事实）；声明、门禁与气泡锚点由装配点按槽
  /// 身份装配。全部内联、无溢出入口、无横向滚动。
  ///
  /// 放不下等比缩小（兜底照旧）：逐列 [FittedBox]（[BoxFit.scaleDown]）以
  /// **无界约束**量出槽的自然宽，列宽装不下才等比缩小、放得下零缩放（不能
  /// 让槽直接吃列宽约束：文字标签会折行而不是缩小）。行名义高钉在
  /// [kEditorVideoToolbarHeight]（两行，缩放只缩内容、不缩名义高）。
  Widget _buildVideoToolRows() {
    return Container(
      key: const Key('control_layer_video_toolbar'),
      // 与顶栏同款深色半透明底：竖屏下它压在背景位画面上。
      color: Colors.black.withValues(alpha: 0.35),
      child: SizedBox(
        height: kEditorVideoToolbarHeight,
        child: Column(
          children: [
            Expanded(
              child: _videoToolbarRow(
                kPlayToolRowPortraitVideoToolbarTop,
                emptyLeadingColumns:
                    kPortraitVideoToolbarColumnCount -
                    kPlayToolRowPortraitVideoToolbarTop.slots.length,
              ),
            ),
            Expanded(
              child: _videoToolbarRow(kPlayToolRowPortraitVideoToolbarBottom),
            ),
          ],
        ),
      ),
    );
  }

  /// 竖屏视频工具栏的一行：按 [kPortraitVideoToolbarColumnCount] 等分列摆放
  /// [rowSet] 的槽（跳过分隔线成员——与顶栏 [_playToolRow] 同一份行集解码
  /// 口径），前 [emptyLeadingColumns] 列留空——上排两枚因此靠右、且与下排
  /// 最右两列同列心。分列与缩放取舍见 [_buildVideoToolRows]。
  Widget _videoToolbarRow(
    PlayToolRowSet rowSet, {
    int emptyLeadingColumns = 0,
  }) {
    final live = _playToolLive;
    return Row(
      children: [
        if (emptyLeadingColumns > 0) Spacer(flex: emptyLeadingColumns),
        for (final slot in rowSet.slots)
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // 槽外面的列 [FittedBox] 已收列宽（本面既有口径），标签收起
                // 判据只归顶栏两处落点——此处不传可用宽、永不触发。
                child: _buildPlayToolSlot(slot, live, iconOnly: false),
              ),
            ),
          ),
      ],
    );
  }
}

/// 顶栏「倍速设置」槽的激活标签：槽名（未激活标签）归表
/// （[kPlayToolSpeedSettings].label，[topBarSpeedSlotWidth] 同源取它）——
/// 改槽名只动声明、改激活标签只动这里。
const String _kSpeedSettingsActiveLabel = '倍速';

/// 顶栏工具槽标签的**量宽口径**样式（[_topBarSlotWidth] 用来实测标签宽）。
/// 文本渲染默认继承环境字距（Material 0.25），比该口径宽 0.25/字；未定宽槽
/// 沿用既有渲染样式，而**定宽槽**（倍速槽）必须把渲染样式也钉成
/// 这一份，否则紧约束的 SizedBox 会因这 0.5px 报 RenderFlex 溢出。
/// 语义档（随系统字号）：槽标签与倍速读数承载语义、随系统字号缩放，
/// [topBarSpeedSlotWidth] 的量测吃调用处同一缩放值。
const TextStyle _kTopToolLabelStyle = TextStyle(fontSize: 10, letterSpacing: 0);

/// 工具区小按钮：播放设置工具 / 置灰项。
class _PlayTool extends StatelessWidget {
  const _PlayTool({
    super.key,
    required this.label,
    required this.icon,
    this.rate,
    this.active = false,
    this.enabled = true,
    this.tappable = true,
    this.onTap,
    this.labelMetrics,
    this.iconOnly = false,
  });

  final String label;
  final IconData icon;

  /// 非空时标签 = `label + 当前倍率`，倍率文字走固定宽度槽位：
  /// 位数变化不改变工具宽与几何中心（气泡锚点稳定）。空时标签为纯 [label]。
  final double? rate;

  /// 高亮（「生效中」设置激活；面板展开不算激活）。
  final bool active;

  /// 置灰项为 false（不可点）。
  final bool enabled;

  /// 是否可点（与 [enabled] 分开）。
  ///
  /// 刻意拆成两个值：顶栏的约定是**硬门**——置灰即不可点（`enabled` 与
  /// `tappable` 同真同假，置灰项与锁定态的槽都如此）；**例外**是
  /// 「局部镜像」在没有任何片段时：置灰（`enabled: false`）**但仍可点**
  /// （`tappable: true`），点一下弹居中轻提示「请添加局部镜像片段」——用户
  /// 要能知道"灰是因为还没加东西，而不是它坏了"。这是顶栏软门之一（标题改名入口受装载门：
  /// 置灰可点、弹「正在装载」），**不要**按
  /// "顶栏一律硬门"的直觉把它们统一掉（见词条「局部镜像」）；底排标注工具区
  /// 的可点性另由判定表按不可用种类决定，与本参数无关。
  final bool tappable;

  final VoidCallback? onTap;

  /// 非空时用它（补上取色）渲染标签：定宽槽传入估宽口径样式
  /// [_kTopToolLabelStyle]，使渲染宽与 [_topBarSlotWidth] 的实测一致；
  /// 空时沿用既有样式（继承环境字距）。
  final TextStyle? labelMetrics;

  /// 标签收起形态：只渲染图标、不渲染文字标签，
  /// 命中盒不缩；语义经 [Semantics] 保留。判据见 [_playToolRow]。
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    // 顶栏工具槽与底排标注工具区是两回事：本槽的 enabled 是
    // **硬门**——置灰且不可点（`enabled` 与 [tappable] 同真同假）；底排槽
    // 的可点性由判定表按不可用种类决定（软门：置灰仍可能可点、弹原因/锁提
    // 示）。两槽只共享不可用视觉 token（[kToolSlotDisabledIconColor] 等），
    // 不共享可点语义——不要按顶栏直觉往底排传「只改颜色」的参数。
    // 顶栏自身也有破例（[tappable] 独立于 enabled，起共两处：
    // 局部镜像的无片段软门与标题改名入口的装载门），见其注释。
    final color = !enabled
        ? kToolSlotDisabledIconColor
        : active
        ? kHighlightAmber
        : kToolSlotEnabledIconColor;
    final labelStyle = (labelMetrics ?? const TextStyle(fontSize: 10)).copyWith(
      color: color,
    );
    final iconWidget = Icon(icon, color: color, size: 22);
    final content = iconOnly
        ? Semantics(label: label, child: iconWidget)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconWidget,
              const SizedBox(height: 2),
              if (rate != null)
                // 倍率文字入固定宽度槽位（居中）——位数变化不改
                // 变工具宽与几何中心（气泡锚点稳定）。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: labelStyle),
                    // 槽位自身含前后内边距（kRateSlotHorizontalPadding），
                    // 不再外加间隙。
                    RateTextSlot(rate: rate!, style: labelStyle),
                  ],
                )
              else
                Text(label, style: labelStyle),
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: tappable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: content,
        ),
      ),
    );
  }
}

class _PlayToolSeparator extends StatelessWidget {
  const _PlayToolSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 28, color: Colors.white24);
  }
}

/// 竖屏视频播放工具栏的**等分列数**：第二行五枚各
/// 占一列、整行铺满可用宽；第一行两枚住最右两列（其余列留空）。两行共读这
/// 一个值——「第一行对到第二行最右两列中心」因此是同一份列分配的结果，不是
/// 第二处对齐算术（留空列数由各行集自己的枚数推出，见 `_buildVideoToolRows`）。
const int kPortraitVideoToolbarColumnCount = 5;

/// 顶栏工具槽宽口径（与 [_PlayTool] 的盒模型一致——内容宽 = 图标 22 与
/// 标签文字宽（[withRateSlot] 时加倍率固定槽位宽）取大者，外加内外水平
/// 内边距 12 + 8）。只服务倍速槽的定宽渲染。
double _topBarSlotWidth(
  String label, {
  bool withRateSlot = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  const style = _kTopToolLabelStyle;
  // 标签量测与渲染同源：渲染处 Text 随环境缩放，量测吃同一个 textScaler。
  var content = measureTextExtent(
    label,
    style,
    scaler: textScaler,
  ).width.ceilToDouble();
  // 倍率槽宽自带缩放口径（量测吃调用处缩放、下限 1，随 `> 1` 放大），
  // 与标签各自缩放后相加、不整体二次缩放。
  if (withRateSlot) {
    content += rateLabelSlotWidth(style, textScaler: textScaler);
  }
  // 量宽逐槽向上取整（槽位到 12 位后窄视口无余量，
  // 渲染宽的逐槽取整累积不得超过估宽，否则 iconOnly 收不上、真溢出）。
  return math.max(22.0, content.ceilToDouble()) + 20.0;
}

/// 顶栏「倍速设置」槽的定宽：取「激活标签 + 倍率槽」形态与未
/// 激活形态（槽声明标签 [kPlayToolSpeedSettings]，无倍率槽）的宽者，使槽宽
/// 不随步进启用 /
/// 停用与手动倍速变化——顶栏不重排、气泡锚点不位移。激活标签「步进」与
/// [_kSpeedSettingsActiveLabel] 同为两字，故两激活形态同宽。
///
/// 缩放系数下限取 1：倍率槽是固定宽（不随文本缩放收缩），若定宽随
/// `textScaler < 1` 一起收缩，紧约束的 SizedBox 会比内容窄而溢出。
@visibleForTesting
double topBarSpeedSlotWidth({TextScaler textScaler = TextScaler.noScaling}) {
  final scaler = TextScaler.linear(math.max(1.0, textScaler.scale(1)));
  return math.max(
    _topBarSlotWidth(kPlayToolSpeedSettings.label, textScaler: scaler),
    _topBarSlotWidth(
      _kSpeedSettingsActiveLabel,
      withRateSlot: true,
      textScaler: scaler,
    ),
  );
}

/// 顶栏装配一次所需的**活值束**：声明在表（[PlayToolSlot]），本束
/// 只装每次构建会变的求值结果——倍速态、撤销/重做可用位、门事实谓词取值、
/// 对比态与倍速槽定宽。镜像状态机不经此束（装配点直读 `widget.mirror`，
/// 使监听对象触发的重装配取到当前值）。
class _PlayToolLive {
  const _PlayToolLive({
    required this.speed,
    required this.canUndo,
    required this.canRedo,
    required this.hasSubject,
    required this.compareActive,
    required this.speedSlotWidth,
  });

  final SpeedControlState speed;
  final bool canUndo;
  final bool canRedo;

  /// 门事实「有没有作用对象」此刻的取值（具名谓词
  /// `ControlLayerState._playToolHasSubject` 的结果）。
  final bool hasSubject;
  final bool compareActive;

  /// 「倍速设置」槽的定宽（依赖系统字号，构建期求值）。
  final double speedSlotWidth;
}

/// 一条看片工具槽的**视图件**：装配点按槽身份穷尽 `switch` 的产出
/// ——声明（槽键、文案、图标、门清单、软门标记）留在被引用的 [slot]，本件
/// 只装活值：可用位、激活位、生效标签、倍率读数、定宽、气泡锚点、监听
/// 对象与点击动作。派生（可点性）已由共用求值入口算好存于 [tappable]。
class _PlayToolView {
  const _PlayToolView({
    required this.slot,
    required this.tappable,
    this.enabled = true,
    this.active = false,
    this.activeLabel,
    this.rate,
    this.fixedWidth,
    this.bubbleLink,
    this.listenable,
    this.onTap,
    this.onTapWithAnchor,
  });

  /// 被引用的槽声明（槽键、文案、图标 token、门清单、软门标记的来源）。
  final PlayToolSlot slot;

  /// 置灰观感（视觉位）。
  final bool enabled;

  /// 当前是否可点（共用求值入口派生：软门置灰仍可点）。
  final bool tappable;

  /// 生效激活位（面板「展开中」不算激活）。
  final bool active;

  /// 激活态标签（如倍速槽的「步进」/「倍速」）。
  final String? activeLabel;

  /// 非空时标签旁加倍率读数（固定宽度槽位：位数变化不改工具宽与
  /// 几何中心——气泡锚点稳定）。
  final double? rate;

  /// 非空 = 槽位定宽（仅「倍速设置」使用）。
  final double? fixedWidth;

  /// 气泡锚点：槽位挂 CompositedTransformTarget 锚定自身。
  final LayerLink? bubbleLink;

  /// 非空时槽位经 ListenableBuilder 随之重装配刷新。
  final Listenable? listenable;

  final VoidCallback? onTap;

  /// 点按动作的另一种形态：非空时把**本槽自身的 `BuildContext`** 交给动作，
  /// 槽位盒因此可直接当锚点用——今天只有「更多」用它把本钮当向上弹出菜单的
  /// 锚点。两者不并用；都用时以本项为准，无锚点需求的槽只给 [onTap]。
  final void Function(BuildContext anchor)? onTapWithAnchor;

  /// 当前展示标签（激活态且有激活标签时用激活标签）。
  String get label => active && activeLabel != null ? activeLabel! : slot.label;
}

/// 图标 token → `IconData` 的映射（穷尽 `switch`）：表不引 Flutter，
/// 映射归装配侧；取值 = 九枚图标的逐位对照。
IconData _playToolIconData(PlayToolIcon token) => switch (token) {
  PlayToolIcon.undo => Icons.undo,
  PlayToolIcon.redo => Icons.redo,
  PlayToolIcon.surroundSound => Icons.surround_sound,
  PlayToolIcon.graphicEq => Icons.graphic_eq,
  PlayToolIcon.flip => Icons.flip,
  PlayToolIcon.flipCameraAndroid => Icons.flip_camera_android,
  PlayToolIcon.speed => Icons.speed,
  PlayToolIcon.compare => Icons.compare,
  PlayToolIcon.cropFree => Icons.crop_free,
  PlayToolIcon.helpOutline => Icons.help_outline,
  PlayToolIcon.more => Icons.more_horiz,
};

/// 由视图件渲染单槽（气泡锚点 + 定宽包裹统一处理）；[iconOnly] = 标签收起
/// 形态（判据见 [_playToolRow]），语义经 [Semantics] 保留。
Widget _renderPlayTool(_PlayToolView v, {required bool iconOnly}) {
  final fixedWidth = v.fixedWidth;
  final onTapWithAnchor = v.onTapWithAnchor;
  // 需要槽自身上下文当锚点的动作（「更多」的向上弹出菜单）：经 [Builder]
  // 取本槽元素，`findRenderObject()` 落到槽的盒上——锚定写法与底排菜单同一
  // 件事，槽键仍在 [_PlayTool] 上、定位手段不变。
  Widget tool = onTapWithAnchor == null
      ? _buildPlayToolWidget(v, iconOnly: iconOnly)
      : Builder(
          builder: (anchor) => _buildPlayToolWidget(
            v,
            iconOnly: iconOnly,
            onTap: () => onTapWithAnchor(anchor),
          ),
        );
  if (fixedWidth != null && !iconOnly) {
    tool = SizedBox(width: fixedWidth, child: tool);
  }
  if (iconOnly) {
    // 标签收起形态逐槽钳到邻接密集区兜底下限（[kHitTargetDenseMinSize]）：
    // 顶栏九槽同排属密集区、按 48 会互吞，此处达不到 48（代价清单见
    // visual_tokens 兜底清单本文件条目）；标签收起不得连带收命中盒。
    tool = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: kHitTargetDenseMinSize),
      child: tool,
    );
  }
  final link = v.bubbleLink;
  if (link != null) {
    tool = CompositedTransformTarget(link: link, child: tool);
  }
  // 锚点包装：横屏顶栏与竖屏标题栏/视频工具栏
  // 共用本渲染点，锚点在两种表面天然都对得上；**按槽自己的声明**包装
  // （锚点 key 即槽键）——声明为假的槽不包、不上报，与底栏 `_gatedInline`
  // 同一口径；注册表外的控件不进引导。
  if (v.slot.carriesGuideAnchor) {
    return GuideAnchor(anchorKey: v.slot.key, child: tool);
  }
  return tool;
}

/// 单槽视觉件：标签、倍率读数、图标、激活与置灰观感都来自视图件。
Widget _buildPlayToolWidget(
  _PlayToolView v, {
  required bool iconOnly,
  VoidCallback? onTap,
}) => _PlayTool(
  key: Key(v.slot.key),
  label: v.label,
  rate: v.rate,
  icon: _playToolIconData(v.slot.icon),
  active: v.active,
  enabled: v.enabled,
  tappable: v.tappable,
  iconOnly: iconOnly,
  // 定宽槽：标签按估宽口径渲染，渲染宽才不会超出定宽。
  labelMetrics: v.fixedWidth != null ? _kTopToolLabelStyle : null,
  onTap: onTap ?? v.onTap,
);
