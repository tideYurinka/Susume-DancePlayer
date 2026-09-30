/// 锚点层：矩形上报板与两个包装件——播放域与页面装配只 import 本件。
///
/// [GuideAnchor] 在每帧布局完成后上报自己的全局矩形，宿主按锚点 key 取用；
/// [GuideBadgeTrigger] 挂载即记一次「功能被真正触达」。两者只碰会话事实，
/// 不渲演出。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guide_state.dart';

/// 锚点矩形上报板：[GuideAnchor] 在每帧布局完成后上报自己的全局矩形，
/// 宿主按锚点 key 取用。
///
/// 走 Riverpod 状态面：宿主 `ref.watch` 必须真正收到「矩形变了」这件事
/// （把 ChangeNotifier 塞进 `Provider` 只给实例、不给通知）。
class GuideAnchorRects extends Notifier<Map<String, Rect>> {
  @override
  Map<String, Rect> build() => const {};

  Rect? rectOf(String anchorKey) => state[anchorKey];

  void report(String anchorKey, Rect rect) {
    // 宿主撤下（ProviderScope 被整体换掉）与锚点的帧尾上报无先后保证：
    // 容器已销毁时本帧回调还会跑一次，直接放弃。
    if (!ref.mounted) return;
    if (state[anchorKey] == rect) return;
    state = {...state, anchorKey: rect};
    _ensureFrame();
  }

  /// 撤下某锚点：锚点已不在当前表面时调用，免得宿主按上一次的位置画洞。
  void remove(String anchorKey) {
    if (!ref.mounted) return;
    if (!state.containsKey(anchorKey)) return;
    state = {...state}..remove(anchorKey);
    _ensureFrame();
  }

  /// 上报发生在帧尾（persistent 相位），此时 `markNeedsBuild` 不排新帧
  /// （`ensureVisualUpdate` 在该相位直接返回）：显式补一帧，否则宿主一直
  /// 停在旧矩形上。
  void _ensureFrame() => WidgetsBinding.instance.scheduleFrame();
}

final guideAnchorRectsProvider =
    NotifierProvider<GuideAnchorRects, Map<String, Rect>>(GuideAnchorRects.new);

/// 锚点量测壳：给包装器自己一个 render object，量到的就是包装器这一层的
/// 盒子（与被包控件同尺寸同位置），不受被包控件内部结构影响——`context
/// .findRenderObject()` 会下钻到子树里第一个 render object，那可能是控件
/// 内部某个盒子而不是控件本身。
class _AnchorProbe extends SingleChildRenderObjectWidget {
  const _AnchorProbe({super.child});

  @override
  RenderProxyBox createRenderObject(BuildContext context) => RenderProxyBox();
}

/// 锚点包装器：把**已有控件**包一层即上报全局矩形；被包控件的行为与外观
/// 逐位不变（它已有的定位 key 不因包装改变）。
class GuideAnchor extends ConsumerStatefulWidget {
  const GuideAnchor({super.key, required this.anchorKey, required this.child});

  /// 引导注册表里声明的锚点 key（`GuideStep.anchorKey`）。
  final String anchorKey;
  final Widget child;

  @override
  ConsumerState<GuideAnchor> createState() => _GuideAnchorState();
}

class _GuideAnchorState extends ConsumerState<GuideAnchor> {
  /// 上报板实例：dispose 时经它撤下本锚点（不再经可能已失效的 ref）。
  late final GuideAnchorRects _board;

  @override
  void initState() {
    super.initState();
    _board = ref.read(guideAnchorRectsProvider.notifier);
    // 矩形每帧随布局上报：宿主据此取用（见宿主的帧尾重查）。
    WidgetsBinding.instance.addPersistentFrameCallback(_report);
    // 锚点常在触发之后才挂载（如菜单类角标指着刚落成的实物）：挂载当帧的
    // 帧回调列表已在遍历中，本次上报要等下一帧——补一帧，锚点不依赖别处
    // 恰好也在排帧。
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    // 锚点从屏上撤下（如收起控制层带走整条轨道带）即从矩形板撤下：不撤的话
    // 宿主会拿旧矩形继续画高亮，指向一个已经不在屏上的控件。dispose 期间改
    // provider 会被 Riverpod 判为「构建中改写」，故推到本帧定稿之后；容器若
    // 已随之销毁，该会话事实本就消失，写失败静默。
    final board = _board;
    final anchorKey = widget.anchorKey;
    scheduleMicrotask(() {
      try {
        board.remove(anchorKey);
      } on Object {
        // 容器已销毁：无需处理。
      }
    });
    super.dispose();
  }

  void _report(Duration timeStamp) {
    if (!mounted) return;
    final board = _board;
    // 只认当前表面上的矩形：被 push 的路由（如播放页）压住本锚点时，本锚点
    // 仍在树里、仍在布局，若不撤下，宿主会拿它去画引导。
    if (ModalRoute.of(context)?.isCurrent == false) {
      board.remove(widget.anchorKey);
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    board.report(widget.anchorKey, box.localToGlobal(Offset.zero) & box.size);
  }

  @override
  Widget build(BuildContext context) => _AnchorProbe(child: widget.child);
}

/// 角标触发器：挂载即记一次「功能被真正触达」——「首次进对比态」
/// 这类以承载锚点的控件出现为准的触达，由播放域把它包在锚点控件外即可。
/// 幂等：同单元再挂载不产生任何变化；单元已看过与否仍由状态位裁决。
class GuideBadgeTrigger extends ConsumerStatefulWidget {
  const GuideBadgeTrigger({
    super.key,
    required this.unitId,
    this.enabled = true,
    required this.child,
  });

  /// 引导注册表里的单元 id（`GuideUnit.id`）。
  final String unitId;

  /// false = 功能此刻不可用（如取景调节态的录制钮置灰）：不触达、不消耗
  /// 角标（角标永不指向按不动的钮）。
  final bool enabled;
  final Widget child;

  @override
  ConsumerState<GuideBadgeTrigger> createState() => _GuideBadgeTriggerState();
}

class _GuideBadgeTriggerState extends ConsumerState<GuideBadgeTrigger> {
  @override
  void initState() {
    super.initState();
    // 帧尾触发：provider 不允许在挂载生命周期内被改写。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) {
        ref.read(guideSessionProvider.notifier).trigger(widget.unitId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
