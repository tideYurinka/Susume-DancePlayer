/// 引导演出层：引导唯一的渲染路径。宿主挂在
/// `MaterialApp.builder` 包住整个 App，跨首页与所有被 push 的路由只有这
/// 一个宿主；同屏只渲染判定命中的那一条引导步（结构保证）。
///
/// 本件是步推进的属主（advance / settle / choose / skip）；覆层件住在
/// [guide_layers.dart]，只收数据与回调。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'content_registry.dart';
import 'drill_task_bar.dart';
import 'guide_anchor.dart';
import 'guide_copy.dart';
import 'guide_layers.dart';
import 'guide_state.dart';
import 'help_documents.dart';
import 'help_root_navigator.dart';

/// 根 Navigator 的有状态包装：宿主栈里给 child 一个稳定的有状态槽位，
/// 演出层（以及经 [helpRootNavigatorState] 的渲染件）向下取到根 Navigator。
class _NavigatorHandle extends StatefulWidget {
  const _NavigatorHandle({super.key, required this.child});

  final Widget child;

  @override
  State<_NavigatorHandle> createState() => _NavigatorHandleState();
}

class _NavigatorHandleState extends State<_NavigatorHandle> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// 引导宿主：无命中步时原样放行 child；命中时压暗其余界面、给锚点一圈
/// 高亮描边、气泡带指向箭头与关闭钮，同屏只有这一条。
class GuideHost extends ConsumerStatefulWidget {
  const GuideHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends ConsumerState<GuideHost> {
  /// 锚点矩形连续缺席的帧数上限：锚点不在当前表面（如角标的控件尚未出现）
  /// 时不空转重查，本轮判定按无步放行，待其它重建源再次触发判定。
  static const int _anchorWaitFrameLimit = 3;

  int _anchorMissedFrames = 0;

  /// 上一帧等待的锚点 key：换了锚点（换步、或菜单类角标的新产物序号变了）
  /// 就重新给满等待帧数——否则前一条步（如首启）等待锚点耗尽次数后，后一条
  /// 步的锚点即使稍后才挂载也再没有重查机会。
  String? _waitingAnchorKey;

  /// 正在演出的短暂提示步：判定命中的短暂提示由宿主接住——**显示即置位**，
  /// 浮层留在本字段里、到点自散，不随判定翻转提前消失（状态位置位后判定
  /// 立刻不再命中该步）。在场期间不出其它引导步（一次只讲一件事）。
  GuideStep? _transientHint;

  /// 短暂提示的收场定时（到点自散）。
  Timer? _transientHintTimer;

  /// 同一帧只排一次接住回调的守卫。
  bool _transientHintScheduled = false;

  /// 正在「做到即填勾、停留后推进」的动手步 id：勾选态与在途推进的唯一
  /// 守卫（做到当场把勾选框填上、停约 0.4 秒再进下一步）。
  String? _holdingStepId;

  /// 停留计时（到点推进本步）。
  Timer? _holdTimer;

  /// 声明了锚点驻留的步（[GuideStep.stickyAnchor]）的锚点矩形：锚点控件
  /// 退场后已取得过的矩形仍供演出使用，步一换就清。
  Rect? _stickyAnchorRect;

  /// 已发过「进观看态」请求的步 id（一次演出只请求一次）。
  String? _enterWatchingRequestedStepId;

  @override
  void dispose() {
    _transientHintTimer?.cancel();
    _holdTimer?.cancel();
    super.dispose();
  }

  /// 动手步的「做到即勾选、停留后推进」：判据新成立时进勾选态并起 0.4 秒
  /// 计时；判据不再成立（如段体又缩回去）或锚点不在场即撤回。
  void _syncHandsOnHold(GuideStep step, Rect anchorRect) {
    // 本步已走完（判定面换步期间会短暂读到旧值）不再起停留：否则会对着一条
    // 已完成的步反复「做到 → 推进」，永远等不到下一步的停留计时。
    if (ref.read(guideSessionProvider).stepsDone.contains(step.id)) {
      _clearHandsOnHold();
      return;
    }
    if (!_handsOnDone(step, anchorRect)) {
      if (_holdingStepId == step.id) {
        _holdingStepId = null;
        _holdTimer?.cancel();
        _holdTimer = null;
        // 勾选态需要撤回（判据可能反转）：改状态排在帧尾。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      return;
    }
    if (_holdingStepId == step.id) return;
    // 判据新成立：本帧即填勾（build 读 [_holdingStepId]），帧尾起停留计时。
    _holdingStepId = step.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _holdingStepId != step.id) return;
      setState(() {});
      _holdTimer?.cancel();
      _holdTimer = Timer(kDrillTaskBarAdvanceHold, () {
        if (!mounted || _holdingStepId != step.id) return;
        _holdingStepId = null;
        _holdTimer = null;
        advanceGuideStep(ref, step);
      });
    });
  }

  /// 撤回在途的动手停留（步不在场 / 被压低 / 换步）。
  void _clearHandsOnHold() {
    _holdingStepId = null;
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child;
    final rects = ref.watch(guideAnchorRectsProvider);
    // 菜单类四条角标的锚点落在**刚落成的实物**上：实际锚点 key 按本会话
    // 记下的新产物序号拼出。序号
    // 取不到时退回基键——基键不承载任何实物，等同锚点缺席，下面照常放行。
    final session = ref.watch(guideSessionProvider);
    final artifactIndexes = session.artifactIndexes;
    // 演练优先：演练进行期间宿主不出任何引导步（含已触达的既有
    // 角标，屏幕归演练提示条）；收场后本处立即恢复渲染已命中的步。判定面
    // 照常求值（触达事实在演练期间照记），故收场当帧即可出现。
    final rawStep = ref.watch(currentGuideStepProvider).value;
    final guideCopy = ref.watch(helpContentProvider).value?.guideCopy;
    final ui = guideCopy?.ui ?? GuideUiCopy.empty;
    // 文案（随包文件）与结构（注册表）在此合流：缺一条文案的步不出场——判定
    // 面已按同一口径过滤，这里再取一次只为渲染取值；`step != null` 即
    // `stepCopy != null`。
    final stepCopy =
        rawStep != null && guideCopy != null && guideCopy.hasStepCopy(rawStep)
        ? guideCopy.steps[rawStep.id]
        : null;
    final step = stepCopy == null ? null : rawStep;
    final choice = session.firstRunChoice;
    final suppressed = session.drillRunning;
    // 动手演练步（编辑态上手两步）：停靠式待办条 + 跟着锚点走的高亮框，
    // 不接管手势、判"做到了"自动推进。**锚点在当前表面在场同样是一切形态
    // 的出场前提**（含动手演练）：锚点控件不在屏上（如收起控制层带走整条
    // 轨道带）就不出场、也不被消耗，等它回到屏上接着演。
    // 一次性图文不锚定（点外面关不掉），不走锚点通道；
    // 但首启的触发面是**首页首帧**：首页被 push 的路由压住时（帮助中心、
    // 新手引导页等）卡片不上场——复用「锚点不在当前表面即撤下」的既有机制，
    // 以首页两枚锚点的在场为门。
    final isCard =
        step?.form == GuideUnitForm.oneShotCard && _homeSurfacePresent(rects);
    final anchorKeys = suppressed || step == null || isCard
        ? const <String>[]
        : guideAnchorKeysOfStep(step, artifactIndexes);
    final primaryAnchorKey = anchorKeys.isEmpty ? null : anchorKeys.first;
    if (primaryAnchorKey != _waitingAnchorKey) {
      _waitingAnchorKey = primaryAnchorKey;
      _anchorMissedFrames = 0;
    }
    var anchorRect = primaryAnchorKey == null
        ? null
        : rects[primaryAnchorKey];
    // 贴框前提 = **锚点当前在屏上在场**；驻留锚点的步
    // （三指跳转 ②）矩形只继续用于画高亮框、不用于贴条——它讲的是一个屏幕
    // 手势，控制层随即收起带走锚点，恒停靠安全区顶，不随锚点在场的头几帧
    // 闪一下位置。
    final barAnchored = anchorRect != null && step?.stickyAnchor != true;
    // 三指跳转动手步：推进到本步的一帧，
    // 经组合根给的闭包请求播放页收起控制层进观看态（幂等；控制层未展开时
    // 收起动作是 no-op，等于什么都不做）。一次演出只请求一次；请求排在帧尾
    // ——此刻判定面还在构建中。
    final stickyHandsOn =
        !suppressed && step != null && step.stickyAnchor;
    if (stickyHandsOn && _enterWatchingRequestedStepId != step.id) {
      _enterWatchingRequestedStepId = step.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(guideEnterWatchingRequestProvider).request();
      });
    }
    // 锚点驻留步：锚点控件退场后用已取得的矩形继续演出；步一换（含单元
    // 收场）即清。
    if (stickyHandsOn) {
      if (anchorRect != null) _stickyAnchorRect = anchorRect;
      anchorRect ??= _stickyAnchorRect;
    } else {
      _stickyAnchorRect = null;
      _enterWatchingRequestedStepId = null;
    }
    final handsOn =
        !suppressed &&
        step != null &&
        step.form == GuideUnitForm.handsOnDrill &&
        anchorRect != null;
    // 动手步判据：做到当场填勾、停约 0.4 秒再推进（跳过仍走「跳过」钮，
    // 整单元置位）。判据未满足时提示条停在原地不消失。
    if (handsOn) {
      _syncHandsOnHold(step, anchorRect);
    } else {
      _clearHandsOnHold();
    }
    // 命中步是短暂提示形态：宿主帧尾接住——显示即置位（会话 + 状态位落盘），
    // 浮层留到 [kGuideTransientHintHold] 自散；判定随即翻转也不提前消失。
    if (!suppressed &&
        step != null &&
        step.form == GuideUnitForm.transientHint &&
        anchorRect != null &&
        _transientHint == null &&
        !_transientHintScheduled) {
      _transientHintScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _transientHintScheduled = false;
        if (!mounted || _transientHint != null) return;
        setState(() => _transientHint = step);
        ref.read(guideSessionProvider.notifier).markSeen(step.unitId);
        ref.invalidate(currentGuideStepProvider);
        ref.read(onboardingStorageProvider).markUnitSeen(step.unitId);
        _transientHintTimer?.cancel();
        _transientHintTimer = Timer(kGuideTransientHintHold, () {
          if (mounted) setState(() => _transientHint = null);
        });
      });
    }
    // 短暂提示的文案按 id 现取：文案文件在演出期间被换掉（热重载）时，
    // 取不到就撤下浮层，不硬解引用。
    final transientCopy = _transientHint == null
        ? null
        : guideCopy?.step(_transientHint!.id);
    final transientRect = _transientHint == null || transientCopy == null
        ? null
        : rects[guideAnchorKeyOfStep(_transientHint!, artifactIndexes)];
    // 锚点矩形要等后端布局完成才会被上报（首帧布局前查不到）：先放行，
    // 帧尾再查一次（矩形变动本身已由上报板补帧，见 GuideAnchorRects）。
    // 连续缺席超过上限即放弃（锚点大概率不在场），不再每帧空转。
    if (primaryAnchorKey != null && anchorRect == null) {
      if (_anchorMissedFrames < _anchorWaitFrameLimit) {
        _anchorMissedFrames += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {});
            WidgetsBinding.instance.scheduleFrame();
          }
        });
      }
    } else {
      _anchorMissedFrames = 0;
    }
    // 结构恒定：child 恒住同一个 Stack 槽位。若「出步」时把它塞进 Stack、
    // 「不出步」时直接返回 child，两个形态的根 widget 类型不同，整棵 child
    // 子树会被重建——播放页演练这类有挂载级状态的子树会因此从头开始（收场
    // 后刚解禁的步一出现就把演练重新挂回来，来回翻腾）。
    return Stack(
      children: [
        _NavigatorHandle(key: helpRootNavigatorKey, child: child),
        if (transientCopy != null && transientRect != null)
          GuideTransientHint(
            message: transientCopy.message,
            anchorRect: transientRect,
          ),
        // 短暂提示在场期间不出其它引导步（一次只讲一件事）。
        if (handsOn && _transientHint == null)
          Positioned.fill(
            child: HandsOnDrillLayer(
              step: step,
              copy: stepCopy!,
              ui: ui,
              anchorRect: anchorRect,
              barAnchored: barAnchored,
              choice: choice,
              checked: _holdingStepId == step.id,
              onSkip: () => skipGuideUnit(ref, step),
            ),
          )
        else if (!suppressed &&
            step != null &&
            isCard &&
            _transientHint == null)
          Positioned.fill(
            child: OneShotGuideLayer(
              step: step,
              copy: stepCopy!,
              onAction: (choice) async {
                await chooseFirstRunBranch(ref, choice);
                await advanceGuideStep(ref, step);
              },
            ),
          )
        else if (!suppressed &&
            step != null &&
            anchorRect != null &&
            _transientHint == null)
          Positioned.fill(
            child: GuideCover(
              step: step,
              copy: stepCopy!,
              ui: ui,
              anchorRects: [for (final key in anchorKeys) ?rects[key]],
              onAdvance: () => advanceGuideStep(ref, step),
              onSkip: () => skipGuideUnit(ref, step),
            ),
          ),
      ],
    );
  }

  /// 当前动手步的判据（按步上声明的判据查会话事实）：
  /// ①第一段段体在屏且渲染宽 ≥44 逻辑像素；②第一段学习段被激活过一次；
  /// ③刚落成的那条分段线被选中过一次；④三指跳转做到过一次。
  bool _handsOnDone(GuideStep step, Rect? anchorRect) {
    final criterion = step.handsOnCriterion;
    if (criterion == null) return false;
    // 判据①无会话闩：它是「段体此刻在屏」的当场事实，走矩形判断。
    if (criterion == HandsOnCriterion.editorIntroZoom) {
      return editorIntroZoomDone(anchorRect);
    }
    final session = ref.watch(guideSessionProvider);
    // 闩型判据：做到过一次即成立。
    if (session.criterionLatches.contains(criterion)) return true;
    // 取值型判据：做到的那个实物就是本单元刚落成的那一个。
    final selected = session.criterionValues[criterion];
    return selected != null &&
        selected == session.artifactIndexes[step.unitId];
  }
}

/// 首页表面的锚点键（首页首帧挂载的两枚锚点，首页被 push 的路由压住时
/// 会被既有机制撤下）：「首页此刻是否是当前表面」按它们的在场推出，锚点
/// 清单的唯一来源在 home_page 的装配。
const List<String> homeSurfaceAnchorKeys = [
  homeHelpEntryAnchorKey,
  importVideoAnchorKey,
];

/// 首页此刻是否是当前表面：[homeSurfaceAnchorKeys] 任一在场即算。
/// 首启图文只在这扇表面上演出。
bool _homeSurfacePresent(Map<String, Rect> rects) =>
    homeSurfaceAnchorKeys.any(rects.containsKey);

/// 步推进：记下本步走完；单元收场步走完即整单元置位；重新判定。
Future<void> advanceGuideStep(WidgetRef ref, GuideStep step) async {
  ref.read(guideSessionProvider.notifier).markStepDone(step.id);
  if (guideIsFinalStepOfUnit(
    step,
    ref.read(guideSessionProvider).firstRunChoice,
  )) {
    await settleGuideUnit(ref, step);
  }
  ref.invalidate(currentGuideStepProvider);
}

/// 首启分支落地（按钮按下即记）：分支是会话事实、不落盘。「跳过教程」这一支
/// 另把全部单元一次置位——按下即已完成，此后怎么看都是已完成；该支欠的那次
/// 指认照常演出（见 [firstRunSkipRecognitionStepId]）。
Future<void> chooseFirstRunBranch(WidgetRef ref, FirstRunChoice choice) async {
  ref.read(guideSessionProvider.notifier).choose(choice);
  if (choice != FirstRunChoice.skip) return;
  final session = ref.read(guideSessionProvider.notifier);
  final storage = ref.read(onboardingStorageProvider);
  for (final unit in helpGuideUnits) {
    session.markSeen(unit.id);
    await storage.markUnitSeen(unit.id);
  }
}

/// 整单元置位：会话置位 + 状态位落盘（写失败静默）。
Future<void> settleGuideUnit(WidgetRef ref, GuideStep step) async {
  ref.read(guideSessionProvider.notifier).markSeen(step.unitId);
  await ref.read(onboardingStorageProvider).markUnitSeen(step.unitId);
}

/// 整单元跳过：与走完同样置位，此后不再自动出现（含重启）。
Future<void> skipGuideUnit(WidgetRef ref, GuideStep step) async {
  await settleGuideUnit(ref, step);
  ref.invalidate(currentGuideStepProvider);
}
