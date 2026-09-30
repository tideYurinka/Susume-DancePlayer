/// 播放页手势演练（帮助域的层域）。
///
/// 第一次进播放页时在用户正打开的这支舞上做一遍手势演练：单指滑 / 双指滑 /
/// 末步把双击、双指双击、长按 2× 各做一次（三个子勾），做对打勾、随时可跳
/// 过。演练**不接管手势、不加识别器、不改任何手势行为**——它只读既有手势域
/// 的读面，把「用户做到了这一类动作」记成一勾：
///
/// - 单指滑 / 双指滑 —— 进度拖动相位（scrubbing）且本次手势起始手指数为
///   1 / ≥2（读面：手势反馈控制器）；
/// - 双击 —— 播放态翻转；双指双击 —— 延迟播放会话开始；长按 2× —— 临时
///   倍速会话开始。末步**不要求单击**（单击唤出控制层会与双指双击互相搅
///   乱）。三指滑不在此教。
///
/// 条子与编辑态上手那条**共用同一件** [DrillTaskBar]：停靠安全区顶、动作图标
/// + 待做勾选框 + 一句话 +「N/M」+ 一排进度点 + 带底「跳过」，末步的三个子勾
/// 以勾片排在文案下方、做对一个亮一个；做到当场填勾、停约 0.4 秒再推进，条身
/// 除「跳过」外不吃触摸。
///
/// 演练只判「做到了这一类动作」，不判别用户意图；进度不落盘——跳过或未
/// 走完退出都不置位，下次进播放页从头做；三步全做完才置位
/// （`onboarding.playerDrill`），此后不再自动出现。
///
/// 依赖方向：播放页 → 本域（组合根只挂**一个** widget、收一个显式输入值
/// 对象 [PlayerDrillInput]）；本域对播放域零 import——播放侧事实全部以
/// 闭包 / 流 / provider 取值面的形状经输入值对象进来。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/misc.dart' show ProviderListenable;

import 'content_registry.dart';
import 'drill_task_bar.dart';
import 'guide_state.dart';
import 'help_documents.dart';

/// 进度拖动读面（同一反馈控制器的三个事实收成一件，组合根一次指向）。
class DrillScrubFace {
  const DrillScrubFace({
    required this.changes,
    required this.isScrubbing,
    required this.startPointerCount,
  });

  /// 手势反馈相位的变化源（scrubbing 起止时通知）。
  final Listenable changes;

  /// 是否处于进度拖动相位（scrubbing）。
  final bool Function() isScrubbing;

  /// 本次手势的起始手指数（进度拖动两档灵敏度按它分）。
  final int Function() startPointerCount;
}

/// 手势演练输入值对象（层域入口形状）：本层要的全部读面一次给全。
/// 字段均为普通 Dart/Flutter 类型——本文件不 import 播放域。末步没有「控制层
/// 开合」这一项：单击不再被要求，也没有任何读面能喂出这一勾。
class PlayerDrillInput {
  const PlayerDrillInput({
    required this.scrub,
    required this.playingFlips,
    required this.transientRateActive,
    required this.delayedPlayPreparing,
  });

  /// 进度拖动读面（单指滑 / 双指滑两勾的来源）。
  final DrillScrubFace scrub;

  /// 播放态边沿流（每次播放态翻转一个事件）。
  final Stream<void> playingFlips;

  /// 临时倍速会话是否激活（长按 2× 的读面）。
  final ProviderListenable<bool> transientRateActive;

  /// 延迟播放会话是否在预备（双指双击的读面）。
  final ProviderListenable<bool> delayedPlayPreparing;
}

/// 步与子勾的具名位次（`helpDrillSteps` 表序；表格重排时随表同步）。
const int _stepSingleFinger = 0;
const int _stepTwoFinger = 1;
const int _stepTaps = 2;
const int _subDoubleTap = 0;
const int _subTwoFingerDoubleTap = 1;
const int _subLongPress = 2;

/// 演练此刻是否应出现：单元未置位（状态位）且本会话未被置位才出现。
/// 进度不落盘：走完才置位，跳过/未走完退出均不置位。
final playerDrillActiveProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(guideSessionProvider).seen.contains(playerDrillUnitId)) {
    return false;
  }
  final storage = ref.watch(onboardingStorageProvider);
  try {
    return !(await storage.loadSeenUnits()).contains(playerDrillUnitId);
  } on Object {
    return false; // 状态位读不出（无平台通道等）：不可判定即不弹。
  }
});

/// 手势演练层：由播放页组合根挂载的唯一 widget。未激活或已收场时零占位、
/// 不拦截任何触摸；激活时停靠安全区顶显示待办条（本步文案 + N/3 进度 +
/// 末步的三个子勾 + 跳过钮），其余界面照常可手势。
class PlayerDrill extends ConsumerStatefulWidget {
  const PlayerDrill({super.key, required this.input});

  final PlayerDrillInput input;

  @override
  ConsumerState<PlayerDrill> createState() => _PlayerDrillState();
}

class _PlayerDrillState extends ConsumerState<PlayerDrill> {
  /// 本步判据已成立（原始事实；做到当场即入，等停留结束才落定）。
  final Set<int> _criterionMet = {};

  /// 已落定的步（勾选停留结束）：只有它推进当前步。
  final Set<int> _stepsDone = {};

  /// 末步三个子勾的完成位（做对一个亮一个）。
  final Set<int> _subChecksDone = {};

  /// 正在「做到即填勾、停留后推进」的步：勾选态与在途推进的唯一守卫。
  int? _holdingStep;

  /// 停留计时（到点落定本步）。
  Timer? _holdTimer;

  /// 本页内已收场（走完置位 / 跳过）：本次挂载内不再出现。
  bool _dismissed = false;

  /// 「演练进行中」的上报口：宿主据此在演练期间不出
  /// 任何引导步。缓存写入口闭包，让 dispose 无需再经已失效的 ref。
  late final void Function(bool) _setDrillRunning;

  /// 上一次已上报的值（同值不重复排帧）。
  bool? _reportedRunning;

  StreamSubscription<void>? _playingFlipsSub;

  @override
  void initState() {
    super.initState();
    _setDrillRunning = ref.read(guideSessionProvider.notifier).setDrillRunning;
    widget.input.scrub.changes.addListener(_observeScrub);
    _playingFlipsSub = widget.input.playingFlips.listen(
      (_) => _metSubCriterion(_subDoubleTap),
    );
  }

  @override
  void dispose() {
    // 离开播放页即演练不再是「进行中」（演练进度本就不落盘）；不置 false
    // 会把宿主永久压住，让别处的引导步再也出不来。dispose 期间改 provider
    // 会被 Riverpod 判为「构建中改写」，故推到本帧定稿之后；容器若已随
    // 页面一起销毁，该会话事实本就随之消失，写失败静默。
    final setDrillRunning = _setDrillRunning;
    scheduleMicrotask(() {
      try {
        setDrillRunning(false);
      } on Object {
        // 容器已销毁：无需处理。
      }
    });
    _holdTimer?.cancel();
    widget.input.scrub.changes.removeListener(_observeScrub);
    unawaited(_playingFlipsSub?.cancel());
    super.dispose();
  }

  /// 演练进行中 = 本页显示着演练待办条（激活且未收场）。收集在同一帧尾
  /// 上报，避免布局期改写 provider。
  void _reportRunning(bool running) {
    if (_reportedRunning == running) return;
    _reportedRunning = running;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _setDrillRunning(running);
    });
  }

  /// 进度拖动相位事实：起始手指数 1 → 单指勾、≥2 → 双指勾。
  void _observeScrub() {
    final scrub = widget.input.scrub;
    if (!scrub.isScrubbing()) return;
    if (scrub.startPointerCount() <= 1) {
      _metCriterion(_stepSingleFinger);
    } else {
      _metCriterion(_stepTwoFinger);
    }
  }

  /// 某步的判据成立（原始事实）：记下并尝试推进。
  void _metCriterion(int index) {
    if (_dismissed || _criterionMet.contains(index)) return;
    setState(() => _criterionMet.add(index));
    _syncHold();
  }

  /// 某步的子勾做到（原始事实）：集齐末步全部子勾才算该步判据成立。
  void _metSubCriterion(int index) {
    if (_subChecksDone.contains(index) || _dismissed) return;
    setState(() => _subChecksDone.add(index));
    if (_subChecksDone.length == helpDrillSteps.last.subChecks.length) {
      _metCriterion(_stepTaps);
    }
  }

  /// 当前步判据已成立且无在途停留 → 进勾选态并起停留计时；列在后面的步若
  /// 已乱序做到，等轮到它时同样在这里续上。
  void _syncHold() {
    if (_dismissed || _holdTimer != null) return;
    final index = _currentStep;
    if (!_criterionMet.contains(index)) return;
    setState(() => _holdingStep = index);
    _holdTimer = Timer(kDrillTaskBarAdvanceHold, _commitHeldStep);
  }

  /// 停留到点：把本步落定、撤下勾选态，再看下一步。
  void _commitHeldStep() {
    _holdTimer = null;
    final index = _holdingStep;
    if (index == null || !mounted) return;
    setState(() {
      _holdingStep = null;
      _stepsDone.add(index);
    });
    if (_stepsDone.length == helpDrillSteps.length) {
      _settleIfComplete();
      return;
    }
    _syncHold();
  }

  /// 三步全做完 → 置位，此后不再自动出现（含重启）。
  Future<void> _settleIfComplete() async {
    if (_stepsDone.length != helpDrillSteps.length || _dismissed) return;
    _dismissed = true;
    ref.read(guideSessionProvider.notifier).markSeen(playerDrillUnitId);
    await ref.read(onboardingStorageProvider).markUnitSeen(playerDrillUnitId);
    if (mounted) ref.invalidate(playerDrillActiveProvider);
  }

  /// 跳过：不置位，下次进播放页从头做；在途停留一并作废。
  void _skip() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdingStep = null;
    setState(() => _dismissed = true);
  }

  /// 当前步 = 第一条未落定的步；末步三个子勾全勾才算落定。
  int get _currentStep {
    for (var i = 0; i < helpDrillSteps.length; i++) {
      if (!_stepsDone.contains(i)) return i;
    }
    return helpDrillSteps.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    // 点击类读面：变化即记勾（只判做到，不判当时处于哪一步）。
    ref.listen(input.transientRateActive, (prev, next) {
      if (next) _metSubCriterion(_subLongPress);
    });
    ref.listen(input.delayedPlayPreparing, (prev, next) {
      if (next) _metSubCriterion(_subTwoFingerDoubleTap);
    });

    final active = ref.watch(playerDrillActiveProvider).value ?? false;
    // 文案随包（assets/help/onboarding.yaml）；缺一条即该步不出场、不被消耗。
    final copy = ref.watch(helpContentProvider).value?.guideCopy;
    final index = _currentStep;
    final step = helpDrillSteps[index];
    final stepCopy = copy?.step(step.id);
    final running = active && !_dismissed && stepCopy != null;
    _reportRunning(running);
    if (!running) return const SizedBox.shrink();

    // 条子与编辑态上手同形同停靠位（共用 [DrillTaskBar]）：条身除「跳过」外
    // 不吃触摸，画在其下的手势照常生效——手感就是真手感。
    return Positioned.fill(
      child: DrillTaskBar(
        icon: step.actionIcon,
        message: stepCopy.message,
        stepIndicator: '${index + 1}/${helpDrillSteps.length}',
        stepCount: helpDrillSteps.length,
        currentStep: index,
        checked: _holdingStep == index,
        skipLabel: copy!.ui.skip,
        onSkip: _skip,
        subChecks: [
          for (var i = 0; i < step.subChecks.length; i++)
            DrillTaskSubCheck(
              id: step.subChecks[i].id,
              label: stepCopy.subChecks[step.subChecks[i].id] ?? '',
              done: _subChecksDone.contains(i),
            ),
        ],
      ),
    );
  }
}
