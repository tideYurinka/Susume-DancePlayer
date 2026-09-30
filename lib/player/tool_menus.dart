part of 'control_layer.dart';

/// 工具菜单壳：「添加」/「自动分段」两个升出式菜单的渲染装配、互斥单开
/// 登记、统一打开路径与带引导锚点的菜单路由。条目动作在
/// tool_menu_actions.dart。

/// 「添加」菜单的渲染装配：门事实与条目动作都由 [tool_menu_actions] 给出，
/// 本处只按声明表逐条目问 verdict、渲染 `PopupMenuItem` 并派发点击。
Future<void> _showAddMenu(
  BuildContext context,
  WidgetRef ref,
  MirrorController mirror,
  TrackBandSession session,
) async {
  final facts = addMenuFacts(ref);
  final actions = addEntryActions(ref, mirror: mirror, session: session);
  final items = [
    for (final entry in AddEntryTable.normal.entries)
      () {
        // 「无对象」前提由库内按条目标识的穷尽 switch 解析（与槽面同构）。
        final hasSubject = addEntryHasSubject(entry.id, facts);
        final verdict = evaluateDeclaredGates(
          entry.gates.toSet(),
          facts,
          hasSubject: hasSubject,
          // 这一门有没有一句做法由条目自己声明，本处不另判。
          noSubjectExplained: entry.noSubjectHint != null,
        );
        return PopupMenuItem<VoidCallback?>(
          key: Key(entry.key),
          enabled: verdict.tappable,
          // 判定 → 动作的唯一映射（[_gatedTap]）：正常态走动作，装载 /
          // 锁定弹各自原因、动作不发生；无对象弹该条目声明的
          // 做法、动作不发生。
          value: _gatedTap(
            ref,
            verdict,
            onInvoke: actions[entry.id]!,
            onNoSubject: _noSubjectHintTap(ref, entry.noSubjectHint),
          ),
          // 置灰可点：门命中时文字用浅底菜单的不可用 token
          // （取值理由见 visual_tokens），仍可选——点一下弹原因
          // （锁定期即「已锁定分段」），动作不发生。
          child: Text(
            addEntryLabel(ref, entry),
            style: verdict.available
                ? null
                : const TextStyle(color: kToolMenuDisabledTextColor),
          ),
        );
      }(),
  ];

  final action = await _openUpwardMenu(context, ref, items);
  action?.call();
}

/// 工具菜单互斥单开登记：任意时刻至多一个工具菜单开着。
/// 状态 = 当前开着的菜单的收起回调（带 token 防跨菜单误清）。
typedef _ToolMenuCloser = ({Object token, void Function() close});

class _ToolMenuOpenNotifier extends Notifier<_ToolMenuCloser?> {
  @override
  _ToolMenuCloser? build() => null;

  /// 登记（带 token）；[closeUpTo] 收起当前登记的菜单并清登记（token 不符
  /// 即已被别的菜单接管，不动）。
  void register(Object token, void Function() close) =>
      state = (token: token, close: close);

  void unregisterIf(Object token) {
    final current = state;
    if (current != null && identical(current.token, token)) {
      state = null;
    }
  }

  void closeCurrent() => state?.close.call();
}

final _toolMenuOpenProvider =
    NotifierProvider<_ToolMenuOpenNotifier, _ToolMenuCloser?>(
      _ToolMenuOpenNotifier.new,
    );

/// 工具菜单的统一打开路径：向上弹出、锚定槽位自身（菜单底缘
/// 贴槽上缘；位置估算不足处由菜单路由收进屏幕边缘兜底，不会越界），并在
/// 打开前收起已开着的工具菜单、关闭（自选条目或点外收起）时清登记。
///
/// 「添加」条目菜单与「自动分段」条目菜单同走此路径——各菜单的锚定写法与
/// 互斥单开只有这一处实现；[T] 为菜单条目值类型（动作闭包）。
///
/// [guideAnchorKey] 非空时（「自动分段」菜单）改走自建容器的
/// [_AnchoredGuideMenuRoute]：容器包引导锚点包装器向引导宿主上报菜单矩形；
/// 菜单关闭时撤下矩形，免得宿主按已关菜单的位置画洞。
Future<T?> _openUpwardMenu<T>(
  BuildContext context,
  WidgetRef ref,
  List<PopupMenuEntry<T>> items, {
  String? guideAnchorKey,
}) async {
  ref.read(_toolMenuOpenProvider.notifier).closeCurrent();
  final box = context.findRenderObject();
  final overlayBox = Overlay.of(context).context.findRenderObject();
  if (box is! RenderBox || !box.attached) return null;
  if (overlayBox is! RenderBox || !overlayBox.attached) return null;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
  final menuHeight =
      items.length * kMinInteractiveDimension + _kToolMenuVerticalPadding;
  final anchor = RelativeRect.fromLTRB(
    topLeft.dx,
    math.max(0.0, topLeft.dy - menuHeight),
    overlayBox.size.width -
        box
            .localToGlobal(
              box.size.bottomRight(Offset.zero),
              ancestor: overlayBox,
            )
            .dx,
    overlayBox.size.height - topLeft.dy - box.size.height,
  );
  final token = Object();
  final navigator = Navigator.of(context);
  ref.read(_toolMenuOpenProvider.notifier).register(token, navigator.pop);
  try {
    if (guideAnchorKey != null) {
      return await navigator.push(
        _AnchoredGuideMenuRoute<T>(
          anchor: anchor,
          items: items,
          menuAnchorKey: guideAnchorKey,
        ),
      );
    }
    return await showMenu<T>(context: context, position: anchor, items: items);
  } finally {
    if (guideAnchorKey != null) {
      ref.read(guideAnchorRectsProvider.notifier).remove(guideAnchorKey);
    }
    ref.read(_toolMenuOpenProvider.notifier).unregisterIf(token);
  }
}

/// 工具菜单竖向外边距估算值（菜单路由的菜单容器竖向 padding 上下各 8）。
const double _kToolMenuVerticalPadding = 16.0;

/// 「自动分段」菜单的渲染装配：门事实在此组装（条目动作见
/// [autoSegmentEntryActions]），渲染层逐条目问 verdict。
Future<void> _showAutoSegmentMenu(BuildContext context, WidgetRef ref) async {
  final track = ref.read(beatTrackStateProvider);
  // 就绪事实按同一口径读谓词；条目动作消费的网格 = 同一份 beatTrackState
  // 文档（锁定 + 未就绪同真时判定表答「锁定」、槽单击弹「已锁定分段」且菜单
  // 不展开；条目按声明补全同一语义——不空断言、不抛模块 StateError）。
  final ready = ref.read(beatGridProvider).hasRealBeats;
  final facts = ToolFacts(
    loading: ref.read(loadGateActiveProvider),
    locked: ref.read(layoutLockedProvider),
    gridNotReady: !ready,
  );
  final actions = autoSegmentEntryActions(ref);

  final items = [
    for (final entry in AutoSegmentEntryTable.normal.entries)
      () {
        final verdict = evaluateDeclaredGates(entry.gates.toSet(), facts);
        return PopupMenuItem<VoidCallback?>(
          key: Key(entry.key),
          enabled: verdict.tappable,
          value: _gatedTap(
            ref,
            verdict,
            onInvoke: actions[entry.id]!,
            onExplain: () => showBeatReadinessPrompt(ref, track),
          ),
          // 置灰可点：门命中时文字用浅底菜单的不可用 token
          // （取值理由见 visual_tokens），仍可选——点一下弹原因，
          // 动作不发生。
          child: Text(
            autoSegmentEntryLabel(entry),
            style: verdict.available
                ? null
                : const TextStyle(color: kToolMenuDisabledTextColor),
          ),
        );
      }(),
  ];

  final action = await _openUpwardMenu(
    context,
    ref,
    items,
    guideAnchorKey: autoSegmentMenuAnchorKey,
  );
  action?.call();
}

/// 带「刚打开的菜单」引导锚点的升出式菜单路由：观感与 [showMenu]
/// 的容器一致（深色菜单卡 + 竖向外边距 8 + 条目各占一档高），差别只在容器
/// 由本路由自建并包一层 [GuideAnchor]——就地讲解的洞挖在菜单本体上，洞内
/// 穿透使菜单项照常可点。摆位沿用调用方传入的 [RelativeRect]，本路由只做
/// 「越出屏幕边缘就收回来」的兜底钳制。
class _AnchoredGuideMenuRoute<T> extends PopupRoute<T> {
  _AnchoredGuideMenuRoute({
    required this.anchor,
    required this.items,
    required this.menuAnchorKey,
  });

  final RelativeRect anchor;
  final List<PopupMenuEntry<T>> items;
  final String menuAnchorKey;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _AnchoredMenuLayout(anchor),
    child: GuideAnchor(
      anchorKey: menuAnchorKey,
      child: Material(
        key: Key(menuAnchorKey),
        elevation: 8.0,
        // 菜单语义与 [showMenu] 的容器同口径（条目要求「menu」祖先语义）。
        child: Semantics(
          role: SemanticsRole.menu,
          scopesRoute: true,
          namesRoute: true,
          explicitChildNodes: true,
          child: IntrinsicWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: items),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 菜单卡摆位：取调用方算好的锚定 [RelativeRect] 的左上角，越出屏幕边缘时
/// 收回屏内（showMenu 由菜单路由兜底的同一件事）。
class _AnchoredMenuLayout extends SingleChildLayoutDelegate {
  const _AnchoredMenuLayout(this.anchor);

  final RelativeRect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      const BoxConstraints();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.left.clamp(0.0, math.max(0.0, size.width - childSize.width)),
    anchor.top.clamp(0.0, math.max(0.0, size.height - childSize.height)),
  );

  @override
  bool shouldRelayout(_AnchoredMenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}
