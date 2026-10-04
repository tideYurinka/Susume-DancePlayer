import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/private_json.dart';
import 'content_registry.dart';
import 'help_documents.dart';

/// 「已看过」状态位存取 seam：`global_private.json`
/// 顶层 `onboarding` 对象，布尔字段与引导单元一一对应（见
/// [onboardingFlagFields]）；字段名按单元 id 的驼峰式（`first_run` →
/// `firstRun`）。
///
/// 读面按**全表**给出：一次读盘返回已置位的单元集（调用方要的从来不是单个
/// 单元——判定面要「第一条未看过的」，清点页要整张表）。缺失/损坏按「未看过」；
/// 写入失败静默（不弹错、不阻塞、不影响当前界面），与既有设备级设置同一兜底
/// 范式。读不出（如无平台通道）向上抛，由调用面兜底：引导判定不可判定即不弹、
/// 不挡界面，新手引导页按「未完成」显示。
abstract interface class OnboardingStorage {
  /// 一次读盘返回已置位的单元集；schema 之外的旧键不影响结果。
  Future<Set<String>> loadSeenUnits();

  /// 置位「已看过」（写失败静默）。
  Future<void> markUnitSeen(String unitId);

  /// 清一项「已看过」：该单元回到「未完成」（写失败静默）。
  Future<void> clearUnitSeen(String unitId);

  /// 清全部「已看过」：所有引导单元回到「未完成」（写失败静默）。
  Future<void> clearAllUnitsSeen();
}

/// 状态位字段清单：以注册表的**引导单元表**为准（单元表增项即增字段）——
/// 单元 id → `global_private.json` 里 `onboarding` 对象的布尔字段名（驼峰式）；
/// 缺省 false（= 未看过），缺字段按未看过。表本身不可改（派生自注册表，
/// 单元表增项即增字段）。
final Map<String, String> onboardingFlagFields = Map.unmodifiable({
  for (final unit in helpGuideUnits) unit.id: _camelCase(unit.id),
});

/// 单元 id → 状态位布尔字段名（`first_run` → `firstRun`）。
String _camelCase(String unitId) {
  final parts = unitId.split('_');
  return [
    parts.first,
    for (final part in parts.skip(1))
      '${part[0].toUpperCase()}${part.substring(1)}',
  ].join();
}

class OnboardingStore implements OnboardingStorage {
  OnboardingStore(this._storage);

  static const _key = 'onboarding';

  final PrivateJsonStorage _storage;

  @override
  Future<Set<String>> loadSeenUnits() async {
    final flags = (await _storage.read())[_key];
    if (flags is! Map) return const {};
    return {
      for (final entry in onboardingFlagFields.entries)
        if (flags[entry.value] == true) entry.key,
    };
  }

  @override
  Future<void> markUnitSeen(String unitId) =>
      _writeFlag(unitId: unitId, seen: true);

  @override
  Future<void> clearUnitSeen(String unitId) =>
      _writeFlag(unitId: unitId, seen: false);

  @override
  Future<void> clearAllUnitsSeen() async {
    try {
      await _storage.mutate((json, {required bool present}) {
        final existing = json[_key];
        final flags = existing is Map
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{};
        for (final field in onboardingFlagFields.values) {
          flags[field] = false;
        }
        json[_key] = flags;
      });
    } on Object {
      // 写失败静默：本会话内已重置，下次启动最多再看一次。
    }
  }

  /// 单字段写入（置位 / 清除同路）：读改写全程写失败静默。
  Future<void> _writeFlag({required String unitId, required bool seen}) async {
    try {
      await _storage.mutate((json, {required bool present}) {
        final existing = json[_key];
        final flags = existing is Map
            ? Map<String, dynamic>.from(existing)
            : <String, dynamic>{};
        flags[_fieldName(unitId)] = seen;
        json[_key] = flags;
      });
    } on Object {
      // 写失败静默：本会话内已生效，下次启动最多再看一次。
    }
  }

  /// 单元 id → 状态位布尔字段名：以派生自注册表的 schema 表为准，表外按
  /// `first_run` → `firstRun` 的驼峰式兜底（读写同一处取名字，不立第二个口径）。
  static String _fieldName(String unitId) =>
      onboardingFlagFields[unitId] ?? _camelCase(unitId);
}

/// 「已看过」状态位存取注入点（测试经内存私密 JSON 覆盖）。
final onboardingStorageProvider = Provider<OnboardingStorage>((ref) {
  return OnboardingStore(ref.watch(privateJsonStorageProvider));
});

/// 本会话的引导事实集（不可变快照）：都只活在本会话、都不落盘、都随该单元的
/// 重置一并清掉，故同居一个属主——会话置位、已走完的步、一次性副作用、功能
/// 触达、实物序号、首启分支、演练进行中、动手判据的闩与取值。
class GuideSessionState {
  const GuideSessionState({
    this.seen = const {},
    this.stepsDone = const {},
    this.sideEffects = const {},
    this.triggered = const {},
    this.artifactIndexes = const {},
    this.firstRunChoice,
    this.drillRunning = false,
    this.criterionLatches = const {},
    this.criterionValues = const {},
  });

  /// 本会话内已关掉的引导单元（状态位写失败静默时，关掉仍在本会话内生效，
  /// 不弹错、不阻塞、不影响当前界面）。
  final Set<String> seen;

  /// 本会话内已走完的引导步 id（多步单元顺序推进用：一步关掉才轮到下一步，
  /// 单元置位前重启则从该单元第一步重头——单元未置位即未走完）。
  final Set<String> stepsDone;

  /// 本会话内已经为哪些单元做过「上场前的一次性播放域副作用」：今天的唯一
  /// 一处是首尾线单元上场时把轨道铺开成整片。该副作用**本会话只做一次**，
  /// 此后用户怎么缩放平移、收起再展开控制层，视野都不再被拉回。随该单元的
  /// 重置一并清掉（重置后走到该单元，铺开照常再做一次）。
  final Set<String> sideEffects;

  /// 本会话内已被首次触达的功能单元（角标触发面）：播放域在功能第一次真正
  /// 被使用——动作真正发生（既有可用门已过）、或承载该功能角标锚点的控件挂载
  /// 且可用（如编辑态里第一段段体的挂载）——时记入其单元 id。角标是否出现过
  /// 仍由状态位裁决，故重装/重启后重复触达不重放。
  final Set<String> triggered;

  /// 「刚落成的实物」序号（菜单类四条角标的会话事实）：单元 id → 该单元第一
  /// 次真正使用时落成的那个实物的序号（备注块 0、镜像块 N、被标记的分段线 N、
  /// 新落的半拍线 N）。触发点本来就在「添加」菜单条目的动作里，那一刻把新产物
  /// 序号记进本会话——轨道带按那个序号包锚点，引导宿主按同一序号取矩形。序号
  /// 取不到（没落成 / 入口不可用）即锚点缺席，宿主放行，不弹错、不挡界面。
  final Map<String, int> artifactIndexes;

  /// 本会话里的首启分支：欢迎卡与下载卡的按钮取值。**会话事实、不落盘**——
  /// 中途杀掉 App，下次打开首启尚未置位，从头走（欢迎卡重新上场，分支重新选）。
  final FirstRunChoice? firstRunChoice;

  /// 手势演练是否正在进行（会话内事实）：按「演练优先」，进行期间宿主不出
  /// 任何引导步——演练自带提示条，屏幕归它；收场（走完或跳过）置回 false 后，
  /// 已触达且未看过的步立刻按既有判定出现。由演练层在挂载且未收场时置 true、
  /// 收场或离开播放页时置 false。
  final bool drillRunning;

  /// 动手判据里「某件事做到过一次」型的闩（判据声明在步上）：做到即记入，
  /// 重置后须再次做到才可能推进。
  final Set<HandsOnCriterion> criterionLatches;

  /// 动手判据里「做到的是哪一个实物」型的取值：记的是**序号**而不是一个布尔
  /// ——判据 = 它就是本会话刚落成的那条线（[artifactIndexes] 记的序号），点在
  /// 别的线上的柄/线身不算做到刚落这条。后一次做到接管（与单选槽一致）。
  final Map<HandsOnCriterion, int> criterionValues;

  GuideSessionState copyWith({
    Set<String>? seen,
    Set<String>? stepsDone,
    Set<String>? sideEffects,
    Set<String>? triggered,
    Map<String, int>? artifactIndexes,
    Object? firstRunChoice = _unsetFirstRunChoice,
    bool? drillRunning,
    Set<HandsOnCriterion>? criterionLatches,
    Map<HandsOnCriterion, int>? criterionValues,
  }) => GuideSessionState(
    seen: seen ?? this.seen,
    stepsDone: stepsDone ?? this.stepsDone,
    sideEffects: sideEffects ?? this.sideEffects,
    triggered: triggered ?? this.triggered,
    artifactIndexes: artifactIndexes ?? this.artifactIndexes,
    firstRunChoice: identical(firstRunChoice, _unsetFirstRunChoice)
        ? this.firstRunChoice
        : firstRunChoice as FirstRunChoice?,
    drillRunning: drillRunning ?? this.drillRunning,
    criterionLatches: criterionLatches ?? this.criterionLatches,
    criterionValues: criterionValues ?? this.criterionValues,
  );
}

/// [GuideSessionState.copyWith] 的「未传该参数」哨兵：`null` 是首启分支的
/// 合法取值，不能拿它当缺省。
const Object _unsetFirstRunChoice = Object();

/// 本会话引导事实集的唯一属主：置位、步进度、副作用、触达、实物序号、首启
/// 分支、演练进行中、判据闩与取值的全部读写都归这里。
final guideSessionProvider = NotifierProvider<GuideSession, GuideSessionState>(
  GuideSession.new,
);

class GuideSession extends Notifier<GuideSessionState> {
  @override
  GuideSessionState build() => const GuideSessionState();

  /// 置位本会话内已关掉该单元。
  void markSeen(String unitId) {
    if (state.seen.contains(unitId)) return;
    state = state.copyWith(seen: {...state.seen, unitId});
  }

  /// 清掉本会话内该单元的置位（引导重置用）。
  void clearSeen(String unitId) {
    if (!state.seen.contains(unitId)) return;
    state = state.copyWith(seen: {...state.seen}..remove(unitId));
  }

  /// 记下该步走完。
  void markStepDone(String stepId) {
    if (state.stepsDone.contains(stepId)) return;
    state = state.copyWith(stepsDone: {...state.stepsDone, stepId});
  }

  /// 清掉本会话内该单元已走完的步：该单元从第一步重头。
  void clearSteps(String unitId) {
    final stepIds = <String>{
      for (final step in helpGuideSteps)
        if (step.unitId == unitId) step.id,
    };
    if (!state.stepsDone.any(stepIds.contains)) return;
    state = state.copyWith(
      stepsDone: {...state.stepsDone}..removeWhere(stepIds.contains),
    );
  }

  /// 记入一次「该单元的一次性副作用已经做过」（幂等）。
  void markSideEffect(String unitId) {
    if (state.sideEffects.contains(unitId)) return;
    state = state.copyWith(sideEffects: {...state.sideEffects, unitId});
  }

  /// 清掉「该单元的一次性副作用已经做过」（引导重置用）。
  void clearSideEffect(String unitId) {
    if (!state.sideEffects.contains(unitId)) return;
    state = state.copyWith(sideEffects: {...state.sideEffects}..remove(unitId));
  }

  /// 记下本次按下的首启按钮取值。
  void choose(FirstRunChoice choice) {
    if (state.firstRunChoice == choice) return;
    state = state.copyWith(firstRunChoice: choice);
  }

  /// 清掉首启分支（引导重置用）：重置首启即从欢迎卡重头。
  void clearFirstRunChoice() {
    if (state.firstRunChoice == null) return;
    state = state.copyWith(firstRunChoice: null);
  }

  /// 记入一次「演练正在进行」（幂等）。
  void setDrillRunning(bool running) {
    if (state.drillRunning == running) return;
    state = state.copyWith(drillRunning: running);
  }

  /// 记入一次功能触达（幂等）。
  void trigger(String unitId) {
    if (state.triggered.contains(unitId)) return;
    state = state.copyWith(triggered: {...state.triggered, unitId});
  }

  /// 清掉本会话内某单元的触达（引导重置用）：该单元须再次走到触发点才可能
  /// 出现。
  void clearTriggered(String unitId) {
    if (!state.triggered.contains(unitId)) return;
    state = state.copyWith(triggered: {...state.triggered}..remove(unitId));
  }

  /// 记入一次「新产物是谁」（同单元后落成的实物接管锚点；幂等体现在值相同时
  /// 不通知，避免无谓重建）。
  void recordArtifact(String unitId, int index) {
    if (state.artifactIndexes[unitId] == index) return;
    state = state.copyWith(
      artifactIndexes: {...state.artifactIndexes, unitId: index},
    );
  }

  /// 清掉本会话内某单元的实物序号（引导重置用）。序号只用来把锚点包在刚
  /// 落成的那个实物上，清掉即该单元的角标回到「锚点缺席」。
  void clearArtifact(String unitId) {
    if (!state.artifactIndexes.containsKey(unitId)) return;
    state = state.copyWith(
      artifactIndexes: {...state.artifactIndexes}..remove(unitId),
    );
  }

  /// 记入一次判据闩（幂等）。
  void latch(HandsOnCriterion criterion) {
    if (state.criterionLatches.contains(criterion)) return;
    state = state.copyWith(
      criterionLatches: {...state.criterionLatches, criterion},
    );
  }

  /// 记入一次判据取值（同判据后一次接管）。
  void recordCriterion(HandsOnCriterion criterion, int value) {
    if (state.criterionValues[criterion] == value) return;
    state = state.copyWith(
      criterionValues: {...state.criterionValues, criterion: value},
    );
  }

  /// 清掉某个判据的会话事实（闩与取值一并清；引导重置用）。
  void clearCriterion(HandsOnCriterion criterion) {
    if (!state.criterionLatches.contains(criterion) &&
        !state.criterionValues.containsKey(criterion)) {
      return;
    }
    state = state.copyWith(
      criterionLatches: {...state.criterionLatches}..remove(criterion),
      criterionValues: {...state.criterionValues}..remove(criterion),
    );
  }

  /// 清掉该单元的本会话进度：置位、已走完的步、一次性副作用、触达、实物序号、
  /// 步上声明的判据会话事实（闩与取值）一并清掉；首启单元连带清掉分支。该单元
  /// 回到「从第一步重头、须再次做到判据」的状态，不留任何陈闩。
  ///
  /// 逐份事实按序清掉，不并成一次原子替换：副作用闩的消费者（轨道带铺开）挂
  /// 在「置位 / 步进度」上，它必须在看到进度被清的那一刻仍读到闩还在——否则
  /// 重置这一趟就把该单元的铺开提前花掉，该单元重新触达时反倒不再铺开整片。
  /// 每份事实各自「没变就什么都不做」，全都没变即整个调用不发任何通知。
  void clearUnit(String unitId) {
    final criteria = <HandsOnCriterion>{
      for (final step in helpGuideSteps)
        if (step.unitId == unitId && step.handsOnCriterion != null)
          step.handsOnCriterion!,
    };
    clearSeen(unitId);
    clearSteps(unitId);
    clearSideEffect(unitId);
    clearTriggered(unitId);
    clearArtifact(unitId);
    for (final criterion in criteria) {
      clearCriterion(criterion);
    }
    if (unitId == firstRunUnitId) clearFirstRunChoice();
  }
}

/// 此刻该显示哪一条引导步（判定纯面）。
///
/// 结构保证同屏至多一条。**已触达的功能步优先于首启**：先取第一条已触达
/// （[GuideSessionState.triggered]、且属于 [guideTriggerGatedUnitIds]）未看过
/// 的步，再按注册表序取第一条未看过的其余步——功能提示是「用户此刻正在用
/// 的功能」的就地讲解，绝不排在首启之后等待（不排队）；
/// 其余步内部仍按注册表序顺序推进（首启第 1 步关掉之后第 2 步才出现）。
/// 命中即返回、不重放；置位后此处返回 null，宿主不再渲染任何引导层。
final currentGuideStepProvider = FutureProvider<GuideStep?>((ref) async {
  final storage = ref.watch(onboardingStorageProvider);
  final session = ref.watch(guideSessionProvider);
  final copyFuture = ref.watch(helpContentProvider.future);
  try {
    final copy = (await copyFuture).guideCopy;
    // 状态位读一次得全表：判定一遍只读一次盘。
    final seenUnits = await storage.loadSeenUnits();
    GuideStep? triggeredHit;
    GuideStep? plainHit;
    for (final step in helpGuideSteps) {
      // 文案缺一条即该步不出场、也不被消耗（不进本会话的已走完集合）：
      // 作者补上文案后走到触发点仍会演。
      if (!copy.hasStepCopy(step)) continue;
      if (session.stepsDone.contains(step.id)) continue;
      // 首启分支门槛：带取值的步只在会话分支取同一取值时才可能命中
      // 指认步的锚点与文案按分支取。
      if (step.firstRunChoice != null &&
          step.firstRunChoice != session.firstRunChoice) {
        continue;
      }
      // 跳过支路的那一次指认：按下「跳过教程」即已把全部单元置位，这一步
      // 仍欠一次演出——只看本会话走完没有（上面那行），不看状态位。
      if (step.id == firstRunSkipRecognitionStepId &&
          session.firstRunChoice == FirstRunChoice.skip) {
        plainHit ??= step;
        continue;
      }
      if (session.seen.contains(step.unitId)) continue;
      if (guideTriggerGatedUnitIds.contains(step.unitId)) {
        // 功能提示只对已触达的功能可能出现；用户没走到就永远不命中。
        if (triggeredHit == null &&
            session.triggered.contains(step.unitId) &&
            !seenUnits.contains(step.unitId)) {
          triggeredHit = step;
        }
        continue;
      }
      if (plainHit == null && !seenUnits.contains(step.unitId)) {
        plainHit = step;
      }
    }
    return triggeredHit ?? plainHit;
  } on Object {
    // 状态位读不出（如测试环境无平台通道）：不可判定即不弹，不挡界面。
    return null;
  }
});

/// 新手引导页的读面：单元 id → 是否已完成（= 状态位是否置位）。读不出（含
/// 无平台通道）一律按「未完成」——页面是只读的清点表，不确定就不挡用户看；
/// 判定面（[currentGuideStepProvider]）对同一情形取「不弹」，各按自己的
/// 代价取兜底。
///
/// **不设缓存**：autoDispose，页面不在场即释放、再进页面重算，所以页面显示
/// 的「已完成 / 未完成」永远取当下的状态位（引导在别处被关掉/跳过后再回来
/// 看不会拿到旧读数）。
final guideUnitsSeenProvider = FutureProvider.autoDispose<Map<String, bool>>((
  ref,
) async {
  final storage = ref.watch(onboardingStorageProvider);
  Set<String> seen;
  try {
    // 状态位一次读盘得全表。
    seen = await storage.loadSeenUnits();
  } on Object {
    seen = const {};
  }
  return {for (final unit in helpGuideUnits) unit.id: seen.contains(unit.id)};
});

/// 引导重置注入点：清掉一个或全部引导单元的「已看过」
/// 状态位，让它下次走到触发点时再演一次。
final guideResetProvider = Provider<GuideReset>((ref) => GuideReset(ref));

/// 引导重置：只动状态位与**本会话里该单元的进度**——舞库、标注、设置、备份、
/// 素材一律不变；重置本身不演出任何东西。清完作废判定读面与页面读面，因此
/// 不重启即生效（回到首页立刻能看到该演的那条）。
class GuideReset {
  GuideReset(this._ref);

  final Ref _ref;

  Future<void> resetUnit(String unitId) async {
    _clearSessionProgress(unitId);
    await _ref.read(onboardingStorageProvider).clearUnitSeen(unitId);
    _invalidateReadFaces();
  }

  /// 清全部：注册表里的全部引导单元一次清掉。
  Future<void> resetAll() async {
    for (final unit in helpGuideUnits) {
      _clearSessionProgress(unit.id);
    }
    await _ref.read(onboardingStorageProvider).clearAllUnitsSeen();
    _invalidateReadFaces();
  }

  /// 本会话里该单元的进度：会话事实集一处清掉。
  void _clearSessionProgress(String unitId) =>
      _ref.read(guideSessionProvider.notifier).clearUnit(unitId);

  void _invalidateReadFaces() {
    if (!_ref.mounted) return;
    _ref.invalidate(guideUnitsSeenProvider);
    _ref.invalidate(currentGuideStepProvider);
  }
}

/// 「进观看态」请求注入点：
/// 组合根（播放页）在挂载时把自己的「收起控制层」动作挂进来（幂等；控制层
/// 未展开时是 no-op），引导宿主在推进到三指跳转单元第二步的那一帧经它请求。
/// 引导域只经本注入点拿闭包，对播放域保持零 import 依赖方向。
final guideEnterWatchingRequestProvider = Provider<GuideEnterWatchingRequest>(
  (ref) => GuideEnterWatchingRequest(),
);

class GuideEnterWatchingRequest {
  /// 组合根挂进来的收起动作（未挂时请求为 no-op，如播放页不在场）。
  void Function()? _collapse;

  /// 组合根挂载时挂入、dispose 时摘下（按闭包相等摘除）。
  void attach(void Function() collapse) => _collapse = collapse;

  /// 按相等摘除（同一实例的方法 tear-off 相等）：组合根不必另存引用。
  void detach(void Function() collapse) {
    if (_collapse == collapse) _collapse = null;
  }

  /// 请求进观看态：动作缺席（页面不在场/未挂）即什么都不做。
  void request() => _collapse?.call();
}
