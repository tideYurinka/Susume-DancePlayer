/// **投屏准备记忆**（票 #40）：**投屏准备**面板那两个渲染勾选档与
/// **投屏倍速档**多选**按这支舞**记住的取值，以及面板取值的来源与回写口。
///
/// ## 落本地文档的 `prefs.castPrep`（随这支舞）
///
/// 身份是**随这支舞的本地文档字段**，不是设备级设置——限定词是「按这支舞」，
/// 与 `prefs.beatPrompt`（节拍提示记忆）、`prefs.speedRate`（手动倍率记忆）
/// 同层同款：换一支舞就换一份。可见性等级为**完全私密**（ADR-0002）：它不进
/// susume 包、随整机备份走。
///
/// 文档那一侧是**纯值层**的原始投影（`persistence/local_document.dart` 的
/// `CastPrepMemoryFields`）；本件是它与投屏域取值之间的**唯一**一层换算，
/// 投屏域的档位枚举因此不进文档层。
///
/// ## 静默降级（缺一样都不抛）
///
/// - 整份记录不存在（`prefs.castPrep` 缺键）→ 回默认；
/// - 逐字段缺席 → **只该字段**回默认（两个勾选档全选 / 档表回「与手动倍率
///   最接近的那一档」），其余字段仍按记忆；
/// - 记住的档**已不可用**（记号不在当时候选里，例如日后砍掉一档或文件被手改）
///   → 在**文档层边界**就被拦下（`persistence/local_document.dart` 的记号词表），
///   这里读到的记号一律认得；档表空（= 对档位没有意见，与缺键同义）回默认那一
///   档——「至少留一档」这条约束在预置时成立，预置绝不落成空集合。
///
/// ## 面板不认持久化
///
/// 面板只认 [CastPrepMemoryPort] 这一个口（取值来源 + 回写口）；默认装配
/// [castPrepMemoryPortOf] 读会话记忆槽 [castPrepMemoryProvider]，落盘由设置
/// 持久化接线（`player/settings_persistence.dart`）承担——与节拍提示记忆
/// 同一形态。
///
/// ## 与投屏缓存互相不碰
///
/// 记住的取值只是**面板的预置**，不进任何渲染请求，也不进缓存键；清空
/// **投屏缓存**（详细设置那一行）不动这些取值，改这些取值也不动缓存里的
/// 产物——两本账各归各。
library;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_render_request.dart'
    show CastRenderChoices, CastSpeedTier;
import '../cast/cast_speed_tier.dart'
    show defaultCastSpeedTiersFor, kCastSpeedTierCandidates;
import '../persistence/local_document.dart' show CastPrepMemoryFields;

/// 面板的取值：两个渲染勾选档 + 一个**投屏倍速档**集合。
///
/// 不变量：`tiers` 至少一档（投屏总得有一份可播的）——默认与解码两条构造
/// 路径都保证这一点，面板的勾选也挡着最后一档；写侧把空集合落成「没有意见」
/// （见 [castPrepMemoryFieldsOf]）。
class CastPrepMemory {
  const CastPrepMemory({required this.choices, required this.tiers});

  final CastRenderChoices choices;

  /// 勾了哪几档（次序不入语义；写侧按候选次序归一）。
  final Set<CastSpeedTier> tiers;

  @override
  bool operator ==(Object other) =>
      other is CastPrepMemory &&
      other.choices == choices &&
      setEquals(other.tiers, tiers);

  @override
  int get hashCode =>
      Object.hash(choices, Object.hashAllUnordered(tiers));

  @override
  String toString() =>
      'CastPrepMemory($choices, tiers: ${tiers.map((t) => t.token).join(',')})';
}

/// 面板打开时的**默认**取值：两个勾选档全选 + 与 [manualRate] 最接近的那
/// 一档（与「默认勾哪一档」的既有纯件同源）。
CastPrepMemory defaultCastPrepMemoryFor(double manualRate) => CastPrepMemory(
  choices: const CastRenderChoices.all(),
  tiers: defaultCastSpeedTiersFor(manualRate),
);

/// 记忆字段 → 面板取值（**唯一**一处降级判据，见库头的三条）。
///
/// [fields] 为 null（这支舞没有记忆记录）即整份回默认；逐字段缺席只让该字段
/// 回默认；档表的记号已在文档层边界校验过，这里只做记号 → 档的一次换算，档表
/// 空（与缺键同义）即回默认那一档。
CastPrepMemory castPrepMemoryOf(
  CastPrepMemoryFields? fields, {
  required double manualRate,
}) {
  final fallback = defaultCastPrepMemoryFor(manualRate);
  if (fields == null) return fallback;
  final tokens = fields.tiers;
  return CastPrepMemory(
    choices: CastRenderChoices(
      picture: fields.picture ?? fallback.choices.picture,
      sound: fields.sound ?? fallback.choices.sound,
    ),
    tiers: tokens.isEmpty
        ? fallback.tiers
        : {for (final token in tokens) _tierByToken[token]!},
  );
}

/// 面板取值 → 记忆字段（写侧绝对终值）：三个字段都给全。
///
/// 档表按**候选次序**（从慢到快）写，界面上勾选的先后因此不进文件——同一份
/// 取值落盘逐字相同（值无变化时协调器据此跳过写盘）。空集合（违背不变量、只能
/// 由手写构造造出）落成**空表 = 没有意见**（文档层按缺键处理，与
/// `practiceClips` 同款）：读回即回默认那一档，「至少留一档」在写侧也不落空。
CastPrepMemoryFields castPrepMemoryFieldsOf(CastPrepMemory memory) =>
    CastPrepMemoryFields(
      picture: memory.choices.picture,
      sound: memory.choices.sound,
      tiers: [
        for (final tier in kCastSpeedTierCandidates)
          if (memory.tiers.contains(tier)) tier.token,
      ],
    );

/// 面板取值的来源与回写口（两个钩子，与仓内既有写端口同款）：
/// 打开面板时问 [presetFor] 取预置值，用户改了取值时经 [remember] 回写。
///
/// 面板自身不认持久化、不读文档层——默认装配读会话记忆槽
/// （[castPrepMemoryPortOf]），测试注入自己的两个钩子。
class CastPrepMemoryPort {
  const CastPrepMemoryPort({
    required this.presetFor,
    required this.remember,
  });

  /// 打开面板那一刻的预置取值；[manualRate] 是那一刻的手动倍率（没有记忆或
  /// 记忆已不可用时按它就近取档）。
  final CastPrepMemory Function(double manualRate) presetFor;

  /// 用户改了取值（勾选档或档表）时的回写口：**变更即写**，面板关闭不丢
  /// （问题就在「面板关闭即丢」）。
  final void Function(CastPrepMemory memory) remember;
}

/// 面板默认装配的口：读会话记忆槽 [castPrepMemoryProvider]（槽由设置持久化
/// 按舞装载与落盘）。
CastPrepMemoryPort castPrepMemoryPortOf(WidgetRef ref) => CastPrepMemoryPort(
  presetFor: (manualRate) =>
      castPrepMemoryOf(ref.read(castPrepMemoryProvider), manualRate: manualRate),
  remember: (memory) =>
      ref.read(castPrepMemoryProvider.notifier).remember(memory),
);

/// 当前这支舞的**投屏准备记忆**（打开/落盘两端的接线点）：槽里放的就是文档
/// 字段形状（null = 这支舞没有记忆记录），转换只在读写两侧各做一次。
final castPrepMemoryProvider =
    NotifierProvider<CastPrepMemoryModel, CastPrepMemoryFields?>(
      CastPrepMemoryModel.new,
    );

class CastPrepMemoryModel extends Notifier<CastPrepMemoryFields?> {
  @override
  CastPrepMemoryFields? build() => null;

  /// 换会话复位（换视频清空语义）：上一支舞的记忆不留在下一支舞。
  void clear() => state = null;

  /// 恢复装载：整份记录落会话槽（null = 这支舞无记忆记录）。只读装载，
  /// 不触发任何落盘。
  void restoreFor(CastPrepMemoryFields? memory) => state = memory;

  /// 面板的回写口：**变更即写**（用户改动算表态，与节拍提示记忆同款），
  /// 值无变化时协调器按文档相等跳过写盘。
  void remember(CastPrepMemory memory) =>
      state = castPrepMemoryFieldsOf(memory);
}

/// 档位记号 → 档：**记号词表在文档层边界校验**（`persistence/local_document.dart`
/// 的 `kCastPrepTierTokens`，与这里的候选档由词表锁测试钉住），表里认不得的
/// 记号到不了这里，故读侧是一次全命中查表。表由候选档派生，加减档只改枚举。
final Map<String, CastSpeedTier> _tierByToken = {
  for (final tier in kCastSpeedTierCandidates) tier.token: tier,
};
