/// 投屏运行域（播放页侧）：把「这次投的**投屏会话** + 那条**递出通道** +
/// 这次备的**投屏倍速档**」的持有、起投、换档、断开与遥控镜像收在一处。
///
/// ## 它回答什么
///
/// - **现在投的是谁**：[state] 的接收端（null = 没投）——投屏胶囊、断开面与
///   倍速档切换都读它；
/// - **起投**：[start] = 起递出通道 → 连上接收端 → 推**起投档**那一份 →
///   起播，随后把其余档交给后台渲（[state] 的 `tiers` 逐档给进度）。任一步
///   失败即把已起的部分收干净（停服 + 断连）、状态回未投屏，异常向上抛——
///   零残留（准备面板与宿主据此给失败面）。**递出通道是一次性的**
///   （`cast_delivery_channel.dart` 的注入点给的是工厂）：
///   每次 [start] 取一份新的、[_teardown] 关掉当次那一份，于是
///   「投 → 断开 → 重选 → 再投」可以反复进行；
/// - **换档**：[switchTier] = 让接收端**换一个文件播**——递出通道换路径 →
///   推片 → 按源坐标换算续播位置。有明确过程态
///   （[CastRunState.switching]）；新文件拉不到就**回退旧文件**并给一句提示
///   （回退也失败才走「会话建立之后的失败」收口）；
/// - **断开**：[disconnect] 是唯一出口——先停服（在飞连接一并断）、再断连，
///   并把在飞的后台渲染一并取消，随后 [PlayerSessionModel.exitCast] 回编辑态。
///   重复调用与未投屏时都是空操作；
/// - **生命周期**（票 #41）：真正退到后台 / 锁屏 = 把**投屏会话视为暂停**
///   （[pauseForBackground]：让接收端停下，不引前台服务、会话也不比播放页活
///   得久）；回来时按接收端上报的状态**续上**（[refreshPlaybackState] →
///   [handlePlaybackState]）——上报状态 → 界面 / 会话动作是一张穷尽映射
///   （`cast_playback_follow.dart`，接收端是权威），paused 一支不留空操作；
/// - **遥控镜像**（[CastMirror]）：投屏态内本机的播放 / 暂停 / 跳转**同时**
///   作用于接收端。跳转按**当前档**换算坐标（源坐标 ↔ 副本坐标），否则 0.5×
///   档上「跳到 10 秒」会让电视停在 10 秒处而不是源片第 10 秒；副本 0 是**首线**
///   时（范围生效，`#37`）还得先减去原点——否则整条遥控都偏「首线」那么多。
///   换算本身是纯件（`lib/cast/cast_coordinates.dart`），本域只按当前档问它。
///   三个动作都**不抛**：失败由本域收口（断开 + 回编辑态 + 短暂提示），本机
///   播放不因一次投屏失败被带停。
/// - **遥控项判据与音量**（票 #38）：起投时问一次接收端支持哪些传输动作，
///   连同**这次探测读到的音量**算成 [CastRemoteControls] 放进 [state]——
///   界面那三枚遥控项（进度 / 播放暂停 / 音量）显不显示只读它
///   （[castRemoteControlsProvider]），音量那枚**不许再叠第二个条件**；判据
///   说「不显示」的那一枚，遥控一条都不发（[_mirror] 先过判据）。**音量**的
///   写入经 [CastVolume] 口：[setVolume] 写接收端，音量显示的基线取
///   [CastRunState.reportedVolume]（起投探测那一次的上报值，问不到就按
///   「不显示」收）——手势的那条接缝按会话模式分派到这里（`cast_volume.dart`）。
///
/// ## 一档一份副本、先投后渲
///
/// 倍速不靠接收端支持，靠**换文件**：0.5 / 0.75 / 1 各一份副本、各自进缓存
/// （缓存键的第五分量就是倍速档）。准备面板只渲**起投档**（与当前手动倍率最
/// 接近的那一档，见 `cast_speed_tier.dart`），投上之后其余档在本域**顺序**
/// 后台渲——前台遥控与后台渲染互不阻塞（渲染不占用会话，遥控不等待渲染）。
/// 渲染进行中那一位事实写进 [castRenderInProgressProvider]（投屏入口的门读它）。
///
/// ## 失败分流（票 #35：两种收场，逐条钉住）
///
/// - **会话没建立起来的失败**（搜不到接收端 / 推片被拒 / 连不上 / 递出通道
///   起不来 / 换接收端失败）：[start] 零残留地收干净并把异常**向上抛**，
///   模式值一位不动（用户本就在编辑态）；失败面由宿主给一句短暂提示
///   （`cast_not_started_prompt`）。「搜不到」更早一步发生在准备面板空态。
/// - **会话建立之后的失败**（失联 / 电视端停止）：一律**回编辑态**再给短暂
///   提示——遥控动作失败走 [_mirror] 的收口，电视端停止走
///   [handlePlaybackState] 的收口，两条都落进 [_fail]（断开 + 停服 + 回编辑
///   态 + `cast_interrupted_prompt`），且并发只收口一次。**换档失败不在这一
///   条**：它是「这一次换没换成」，会话本身还活着——[switchTier] 回退旧文件
///   + `cast_speed_switch_prompt`；只有回退也失败才落回 [_fail]。
///
/// ## 断开触发点收在既有复位一处
///
/// 换视频与离开播放页都经 [PlayerSessionModel.reset]（见
/// `open_restore.dart` 与播放页 dispose），本域只听「离开投屏态」这一条
/// 边沿即断开——**不新增手写退出点**。主动断开走 [disconnect]：它自己收完
/// 会话与通道再翻模式值，那条边沿随之再走一遍是幂等空操作。
///
/// ## 投屏期屏幕常亮（票 #39）
///
/// 投屏态的画面区被投屏画面覆盖件换掉——连源画面件都不挂，于是播放内核
/// 那份「画面件持着」的唤醒没有持有者，屏幕照常熄灭。本域因此在**进投屏态
/// 那一下**经 [castScreenAwakeProvider] 持有唤醒（画面件持不了、内核也不能
/// 独立于画面件持，见 `cast_screen_awake.dart`），在**既有复位一处**
/// （[_teardown]）放掉：断开 / 换视频 / 离开播放页 / 起投失败的零残留都经它
/// ——进出各只有一处，不在三处各写一遍。不引前台服务。
///
/// 另有**一帧末的再确认**（[reassertScreenAwake]，由画面区挂载时叫）：退场的
/// 源画面件在同一帧收尾时 dispose，会放开同一个平台开关（它不是引用计数的）
/// ——不是第二个持有者，只是把同一份持有重新按一遍。
///
/// ## 边界
///
/// 本域不读构建上下文、不构控件；模式值仍归其既有单一 owner
/// [PlayerSessionModel]（本域只消费它的读面与写缝）。渲染**请求**由宿主装配
/// （各域现值只见于组合根），本域只吃请求与产物路径。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show BuildContext, Key, Text, Widget;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_coordinates.dart';
import '../cast/cast_delivery_channel.dart';
import '../cast/cast_failure.dart' show CastSessionDropped;
import '../cast/cast_playback_follow.dart';
import '../cast/cast_receiver.dart';
import '../cast/cast_render_activity.dart' show castRenderInProgressProvider;
import '../cast/cast_render_orchestrator.dart'
    show castRenderOrchestratorProvider;
import '../cast/cast_render_request.dart';
import '../cast/cast_screen_awake.dart';
import '../cast/cast_session.dart';
import '../cast/cast_speed_tier.dart';
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider;
import '../player_session/player_session.dart';
import 'cast_mirror.dart';
import 'cast_volume.dart' show CastVolume;
import 'notice.dart' show NoticeId, NoticeSpec, noticeTriggerProvider;
import 'visual_tokens.dart' show kNoticeTextStyle;

/// 投屏遥控镜像口：投屏态内本机的播放动作同时作用于接收端。
///
/// 实现（[CastRunModel]）自身收口失败——本口不抛（见库头「遥控镜像」）。
/// 未接投屏的宿主与测试用 [NoCastMirror]（三动作皆空操作）。
export 'cast_mirror.dart' show CastMirror, NoCastMirror;

/// 「投屏断了」提示内容：一句话说明已回到编辑态。
Widget _castInterruptedNoticeContent(BuildContext _) =>
    const Text('投屏断了，回到编辑态', style: kNoticeTextStyle);

const castInterruptedNoticeSpec = NoticeSpec(
  id: NoticeId.castInterrupted,
  content: _castInterruptedNoticeContent,
  noticeKey: Key('cast_interrupted_prompt'),
);

/// 「没接上接收端」提示内容：起投失败（连不上 / 被拒 / 递出通道起不来）
/// 时那一句——准备面板已关，这是唯一的失败面。
Widget _castNotStartedNoticeContent(BuildContext _) =>
    const Text('没接上这台接收端', style: kNoticeTextStyle);

const castNotStartedNoticeSpec = NoticeSpec(
  id: NoticeId.castNotStarted,
  content: _castNotStartedNoticeContent,
  noticeKey: Key('cast_not_started_prompt'),
);

/// 「换档没成功」提示内容：新文件拉不到、已经退回上一档那一句。
Widget _castSpeedSwitchFailedNoticeContent(BuildContext _) =>
    const Text('换档没成功，回到上一档', style: kNoticeTextStyle);

const castSpeedSwitchFailedNoticeSpec = NoticeSpec(
  id: NoticeId.castSpeedSwitchFailed,
  content: _castSpeedSwitchFailedNoticeContent,
  noticeKey: Key('cast_speed_switch_prompt'),
);

/// 一档副本的渲染状态。
enum CastTierRenderStatus {
  /// 还没轮到渲（后台顺序渲，排在后面）。
  queued,

  /// 正在渲（[CastTierRender.fraction] 是这一档的进度）。
  rendering,

  /// 有一份可投的产物（[CastTierRender.filePath] 非空）——可切。
  ready,

  /// 这一档没渲出来：不可切（断开投屏重来）。
  failed,
}

/// 一档副本的运行账：这一档现在什么状态、渲到哪、产物在哪。
class CastTierRender {
  const CastTierRender({
    required this.tier,
    required this.status,
    this.fraction,
    this.filePath,
  });

  /// 排队待渲的一档（还没轮到）。
  const CastTierRender.queued(CastSpeedTier tier)
    : this(tier: tier, status: CastTierRenderStatus.queued);

  /// 已有一份可投的产物。
  const CastTierRender.ready(CastSpeedTier tier, String filePath)
    : this(tier: tier, status: CastTierRenderStatus.ready, filePath: filePath);

  final CastSpeedTier tier;
  final CastTierRenderStatus status;

  /// 这一档的渲染进度（0..1）；只在 [CastTierRenderStatus.rendering] 下有值。
  final double? fraction;

  /// 可投的那一份（产物路径，或「不渲染」时的原片路径）。
  final String? filePath;

  /// 可切：有产物。
  bool get ready => status == CastTierRenderStatus.ready && filePath != null;

  @override
  bool operator ==(Object other) =>
      other is CastTierRender &&
      other.tier == tier &&
      other.status == status &&
      other.fraction == fraction &&
      other.filePath == filePath;

  @override
  int get hashCode => Object.hash(tier, status, fraction, filePath);

  @override
  String toString() =>
      'CastTierRender(${tier.token}, $status, $fraction, $filePath)';
}

/// 投屏运行状态：没投 / 正投到某台接收端（含这次备了哪几档、现在播哪一档）。
class CastRunState {
  const CastRunState.idle()
    : receiver = null,
      activeTier = CastSpeedTier.full,
      tiers = const [],
      switching = false,
      remoteControls = const CastRemoteControls.none(),
      reportedVolume = null;

  const CastRunState.casting(
    this.receiver, {
    this.activeTier = CastSpeedTier.full,
    this.tiers = const [],
    this.switching = false,
    this.remoteControls = const CastRemoteControls.none(),
    this.reportedVolume,
  });

  /// 正投的那台接收端；null = 没投。
  final CastReceiver? receiver;

  /// 接收端**此刻在播**的那一档（换档成功那一刻翻过去）。
  final CastSpeedTier activeTier;

  /// 这次投屏备的档（声明次序；空 = 老调用方那条单档路）。
  final List<CastTierRender> tiers;

  /// 换档过程中（过程态：换文件 + 换算位置 + 等接收端起播）。
  final bool switching;

  /// **遥控项判据**（票 #38）：起投时问一次接收端支持哪些传输动作、连同**这次
  /// 探测读到的音量**算出来的那一份。**探测不到 / 探测失败 = 空集**（哪一项都
  /// 不显示，见 `cast_session.dart`）；未投屏也是空集。
  final CastRemoteControls remoteControls;

  /// 起投探测那一次读到的**接收端上报音量**（0..1；null = 没端点 / 设备不答 /
  /// 探测失败）。它与 [remoteControls] 的 `showsVolume` 由同一次探测一起定
  /// （`castVolumeReported`），音量显示的**基线**取它就够——界面因此不必自己
  /// 再问接收端一遍（票 #38 的「问一次答一次」）。
  final double? reportedVolume;

  bool get active => receiver != null;

  /// 某一档的运行账；没备这一档时为空。
  CastTierRender? renderFor(CastSpeedTier tier) {
    for (final render in tiers) {
      if (render.tier == tier) return render;
    }
    return null;
  }

  /// 这一档现在可不可切：已渲好、不是正在播的那一档、也不在换档过程中。
  bool canSwitchTo(CastSpeedTier tier) =>
      active &&
      !switching &&
      tier != activeTier &&
      (renderFor(tier)?.ready ?? false);

  /// 有没有档还在渲（后台渲染在场）。
  bool get renderingTiers =>
      tiers.any((render) => render.status == CastTierRenderStatus.rendering);

  CastRunState _with({
    CastSpeedTier? activeTier,
    List<CastTierRender>? tiers,
    bool? switching,
    CastRemoteControls? remoteControls,
    double? reportedVolume,
  }) => CastRunState.casting(
    receiver,
    activeTier: activeTier ?? this.activeTier,
    tiers: tiers ?? this.tiers,
    switching: switching ?? this.switching,
    remoteControls: remoteControls ?? this.remoteControls,
    reportedVolume: reportedVolume ?? this.reportedVolume,
  );

  @override
  bool operator ==(Object other) =>
      other is CastRunState &&
      other.receiver == receiver &&
      other.activeTier == activeTier &&
      other.switching == switching &&
      other.remoteControls == remoteControls &&
      other.reportedVolume == reportedVolume &&
      other.tiers.length == tiers.length &&
      other.tiers.every(tiers.contains);

  @override
  int get hashCode => Object.hash(
    receiver,
    activeTier,
    switching,
    remoteControls,
    reportedVolume,
    Object.hashAll(tiers),
  );

  @override
  String toString() => active
      ? 'CastRunState.casting(${receiver!}, ${activeTier.token}, '
            '${tiers.map((t) => t.status.name).join('/')}'
            '${switching ? ', switching' : ''}, $remoteControls)'
      : 'idle';
}

/// 起投那一次**遥控项探测**的读数：判据 + 读到的那条接收端音量。
///
/// 两者出自**同一次**探测（`CastRunModel._probeRemoteControls`）：判据里的
/// `showsVolume` 由「有端点 ∧ 读到了值」折出来（[castVolumeReported]），读到
/// 的值本身留给音量滑条的基线用。一个值对象而不是两个字段，是因为这两样一旦
/// 分头去问，就会出现「判据说显示、基线却读不到」的自相矛盾现场。
class CastRunControlsProbe {
  const CastRunControlsProbe({
    required this.controls,
    required this.reportedVolume,
  });

  /// 「哪些遥控项显示」的唯一判据。
  final CastRemoteControls controls;

  /// 探测这次读到的接收端音量（会读不到时 null）。
  final double? reportedVolume;
}

/// 投屏运行域：当前这条投屏会话、递出通道与倍速档账的唯一持有者。
class CastRunModel extends Notifier<CastRunState>
    implements CastMirror, CastVolume {
  CastSession? _session;
  CastDeliveryChannel? _channel;

  /// 这次投屏的**坐标换算**（各档渲染请求 + 起投那一刻正在练的学习段）：后台
  /// 渲染逐档取请求、遥控跳转与换档续播取位置换算，都问这一处
  /// （纯件在 `lib/cast/cast_coordinates.dart`）。
  CastCoordinates _coordinates = const CastCoordinates();

  /// 后台渲染的代际号：断开 / 换视频即自增，在飞的那一轮作废。
  int _renderGeneration = 0;

  /// 后台渲染还在飞（断开时要把它取消掉）。
  bool _rendering = false;

  /// 投屏期这一屏**还持着唤醒**（进投屏态即持有、离开即释放；见
  /// `cast_screen_awake.dart`）。持有与释放严格配对：释放只在
  /// [CastScreenAwake.release] 该被调的那一刻调一次。
  bool _awake = false;

  @override
  CastRunState build() {
    // 断开触发点收在既有复位一处：只听「离开投屏态」这一条边沿
    // （换视频与离开播放页都经 [PlayerSessionModel.reset]）。
    ref.listen(playerSessionProvider, (previous, next) {
      final wasCasting = previous?.isCast ?? false;
      if (wasCasting && !next.isCast) unawaited(_teardown());
    });
    return const CastRunState.idle();
  }

  /// 正投的那台接收端（未投屏为 null）。
  CastReceiver? get receiver => _session?.receiver;

  /// 起投：起递出通道 → 连上接收端 → 推**起投档**那一份 → 起播，随后把其余
  /// 档交给后台渲。
  ///
  /// 一次只投一台：起投前先收掉上一条（换接收端 = 断开重投）。任一步失败即
  /// 零残留地收干净并把异常向上抛——**起投失败不回编辑态**（模式值本就没
  /// 离开过），由调用方给失败面。
  ///
  /// [plan] 为空 = 老调用方那条单档路（只有 1× 一档，没有后台渲染）；
  /// [requests] 是这次各档的渲染请求（后台渲染逐档取用；缺哪一档就按「这一
  /// 档没渲出来」收口）；[practiceSpan] 是起投那一刻正在练的学习段（源坐标，
  /// 换档时把续播位置钳进换算后的段内）。
  Future<void> start({
    required CastReceiver receiver,
    required File file,
    CastSpeedTierPlan? plan,
    Map<CastSpeedTier, CastRenderRequest> requests = const {},
    ({Duration start, Duration end})? practiceSpan,
  }) async {
    await _teardown();
    final effectivePlan = plan ?? CastSpeedTierPlan.single(CastSpeedTier.full);
    // 递出通道**一次投屏一份**：取一份新的（上一份刚在 [_teardown] 里停掉，
    // 它已经是一次性通道的终态——拿它再 serve 必抛 CastDeliveryClosed）。
    final channel = ref.read(castDeliveryChannelFactoryProvider)();
    final factory = ref.read(castSessionFactoryProvider);
    try {
      final source = await channel.serve(file);
      // 通道一挂上就记账：接下去任一步失败都要把它停掉（零残留）。
      _channel = channel;
      final session = await factory.connect(receiver);
      _session = session;
      _coordinates = CastCoordinates(
        requests: requests,
        practiceSpan: practiceSpan,
      );
      state = CastRunState.casting(
        receiver,
        activeTier: effectivePlan.startTier,
        tiers: [
          for (final tier in effectivePlan.tiers)
            tier == effectivePlan.startTier
                ? CastTierRender.ready(tier, file.path)
                : CastTierRender.queued(tier),
        ],
      );
      // 进投屏态即持有唤醒：这一刻起用户可能已经离屏两三米、手机不碰了
      // ——推片与起播的等待期同样不能熄屏（推片失败由 [_teardown] 配平放掉）。
      _holdScreenAwake();
      await session.push(source);
      await session.play();
      // **遥控项判据**：连上之后「问一次答一次」——接收端此刻支持哪些传输
      // 动作 + 这次探测读到的音量。探测失败（不答 / 掉线）收敛到空集，
      // 不把会话收掉、不向上抛（见 [CastRemoteControls]）。
      final probe = await _probeRemoteControls(session, receiver);
      if (!identical(_session, session)) return;
      state = state._with(
        remoteControls: probe.controls,
        reportedVolume: probe.reportedVolume,
      );
    } on Object {
      await _teardown();
      // 起投失败一律回编辑态：新投那条路径本就没离开过编辑态（exitCast 是
      // 幂等 no-op）；换接收端失败那条路径会剩一个「在投屏态却没有会话」的
      // 悬挂面，这里一并收口。
      ref.read(playerSessionProvider.notifier).exitCast();
      rethrow;
    }
    // 当前档已经渲好、也已经推上去在播：这一刻才起后台渲染（不 await——
    // 前台遥控不等它，它也不占会话）。
    _startBackgroundRenders(effectivePlan);
  }

  /// 问一次接收端此刻支持哪些传输动作，连同**这次探测读到的音量**算成那份
  /// **遥控项判据**。**探测不到 / 探测失败一律空集**——与设备确实不支持同一个
  /// 出口（「不显示」），静默降级。
  ///
  /// 音量那一位与动作集在**同一处、同一次**问出来（起投探测「问一次答一次」）：
  /// 设备描述里有 RenderingControl 端点不等于答得上 `GetVolume`，所以这里顺手
  /// 读一次上报值（读不到 / 抛错 = 那一项不显示）。界面侧的「显不显示」因此
  /// 只问 [CastRemoteControls.shows] 一处，没有第二个自判条件；这次读到的值
  /// 另存进 [CastRunState.reportedVolume] 给音量滑条的基线用（`cast_volume.dart`
  /// 的显示路径），于是界面不必自己再问一遍接收端。
  Future<CastRunControlsProbe> _probeRemoteControls(
    CastSession session,
    CastReceiver receiver,
  ) async {
    final CastTransportActions actions;
    try {
      actions = await session.supportedTransportActions();
    } on Object {
      return const CastRunControlsProbe(
        controls: CastRemoteControls.none(),
        reportedVolume: null,
      );
    }
    double? volume;
    if (receiver.controlUrls.renderingControl != null) {
      try {
        volume = await session.volume();
      } on Object {
        // 设备不答 / 掉线：与「没有端点」同一个出口（不显示），不把会话收掉。
        volume = null;
      }
    }
    return CastRunControlsProbe(
      controls: CastRemoteControls.of(
        actions: actions,
        hasVolumeControl: castVolumeReported(
          hasVolumeEndpoint: receiver.controlUrls.renderingControl != null,
          probedVolume: volume,
        ),
      ),
      reportedVolume: volume,
    );
  }

  /// 换档：**让接收端换一个文件播**——递出通道换路径 → 推片 → 按比例换算
  /// 位置续播。有明确过程态（[CastRunState.switching]）。
  ///
  /// 未投屏 / 正在换档 / 这一档就是当前档 / 这一档还没渲好：都是**空操作**
  /// （未渲好的档在界面上不可点，这里是那道门的结构性兜底）。
  ///
  /// 新文件拉不到就**回退旧文件**（重新递出旧文件 → 推回去 → 换算回旧档位置
  /// → 续播）并给 `cast_speed_switch_prompt`；回退也失败才走 [_fail] 收口。
  Future<void> switchTier(CastSpeedTier tier) async {
    final session = _session;
    final channel = _channel;
    if (session == null || channel == null) return;
    if (state.switching || tier == state.activeTier) return;
    final target = state.renderFor(tier);
    final from = state.activeTier;
    final origin = state.renderFor(from);
    if (target == null || !target.ready || origin == null) return;

    state = state._with(switching: true);

    // 接收端此刻位置（**旧档副本坐标**）：问不到就从头起（静默降级），
    // 掉线则照既有失败收口走一遍。
    var reported = Duration.zero;
    try {
      reported = await session.position();
    } on CastSessionDropped {
      await _fail();
      return;
    } on Object {
      reported = Duration.zero;
    }
    if (!identical(_session, session)) return;

    final destination = _coordinates.resumePositionOf(
      position: reported,
      from: from,
      to: tier,
    );

    try {
      final source = await channel.serve(File(target.filePath!));
      await session.push(source);
      await session.seek(destination);
      await session.play();
    } on Object {
      await _recover(
        session: session,
        channel: channel,
        file: origin.filePath!,
        fromTier: tier,
        toTier: from,
        position: destination,
      );
      return;
    }
    if (!identical(_session, session)) return;
    state = state._with(activeTier: tier, switching: false);
  }

  /// 接收端此刻上报的播放位置，**换成源片坐标**（投屏本地预览的起播定位
  /// 用；预览放的是源片）。
  ///
  /// 未投屏 = null；**连接断了**（[CastSessionDropped]）= null 并照既有失败
  /// 收口走一遍（断开 + 回编辑态 + 短暂提示）；**设备只是这一问答不上来**
  /// （[CastActionRefused] 一类）= null 且静默降级——预览从头起就好，不拿一次
  /// 探测把投屏整条收掉（与「探测不到一律按不显示处理」同一口径）。
  Future<Duration?> reportedPosition() async {
    final session = _session;
    if (session == null) return null;
    final Duration reported;
    try {
      reported = await session.position();
    } on CastSessionDropped {
      await _fail();
      return null;
    } on Object {
      return null;
    }
    return _coordinates.sourcePositionOf(reported, state.activeTier);
  }

  /// 断开：唯一出口——先停服（在飞连接一并断）、再断连，并把在飞的后台渲染
  /// 一并取消，随后模式值回编辑态。
  ///
  /// 递出通道**先停**：会话的收尾动作（停播）可能被设备拖住，停服不该等它
  /// ——「立刻不可达」不依赖接收端的回应。未投屏或重复调用都是空操作。
  Future<void> disconnect() async {
    final wasCasting = _session != null;
    await _teardown();
    if (wasCasting) {
      ref.read(playerSessionProvider.notifier).exitCast();
    }
  }

  /// 遥控镜像：未投屏 = 空操作；失败收口，不向上抛。
  ///
  /// 跳转按**当前档**换算坐标：本机报的是源片位置，接收端要的是那一档副本
  /// 里的位置（0.5× 档上源片 10 秒 = 副本 20 秒；范围生效时副本 0 是**首线**）
  /// ——换算问纯件 [CastCoordinates.copyPositionOf]，本域不自己算。
  ///
  /// **判据先过一遍**（票 #38）：接收端没自述支持的那一枚（播放暂停 / 跳转 /
  /// 音量），遥控一条都不发——界面那边也不显示它；这里是**结构性兜底**
  /// （判据说不显示就不发），不是第二处判据。
  @override
  Future<void> play() =>
      _mirror(CastRemoteItem.playPause, (session) => session.play());

  @override
  Future<void> pause() =>
      _mirror(CastRemoteItem.playPause, (session) => session.pause());

  @override
  Future<void> seek(Duration position) => _mirror(
    CastRemoteItem.progress,
    (session) =>
        session.seek(_coordinates.copyPositionOf(position, state.activeTier)),
  );

  /// 把接收端音量设成 [volume]（0..1；音量手势在投屏态下走这条）。
  /// 设备没有音量端点（判据说这一项不显示）时是空操作。
  @override
  Future<void> setVolume(double volume) =>
      _mirror(CastRemoteItem.volume, (session) => session.setVolume(volume));

  /// 接收端此刻上报的音量——**起投探测那一次读到的值**
  /// （[CastRunState.reportedVolume]）：没有端点 / 设备不答 / 问不到的一律 null。
  ///
  /// 它**不再自己向会话问一遍**（票 #38 的口径：探测「问一次答一次」）。这样
  /// 音量滑条的基线与「这一项显不显示」出自同一次读数，不会出现「判据说显示、
  /// 基线却读不到」的自相矛盾现场。掉线那一支由别的遥控动作与回前台续上负责
  /// 收口，一次读数不承担失败面。
  @override
  Future<double?> reportedVolume() async => state.reportedVolume;

  Future<void> _mirror(
    CastRemoteItem item,
    Future<void> Function(CastSession session) action,
  ) async {
    final session = _session;
    if (session == null) return;
    if (!state.remoteControls.shows(item)) return;
    try {
      await action(session);
    } on Object {
      await _fail();
    }
  }

  /// **电视端停止**收口：接收端自己停了（那边被按了停 / 片子被卸了）。
  ///
  /// 会话建立之后的失败与遥控失败同一条收场——断开（含停服）+ 回编辑态 +
  /// 短暂提示。接收端上报的当前播放状态由 [refreshPlaybackState]（回前台
  /// 问一次）喂进来，本域只负责按穷尽映射续上，不自己起轮询。
  /// 未投屏时空操作。
  ///
  /// **不是一个「只认停止、其余 return」的窄口**（票 #41）：上报状态的每个
  /// 取值都经 [castPlaybackFollowOf] 落到一件明确的事——
  ///
  /// - 在播 → 本机界面追成播放态（**不重推接收端**）；
  /// - 暂停 → 本机界面追成暂停态，**不自动抢播**；
  /// - 已停 / 无媒体 → 既有失败收口（[_fail]）；
  /// - 过渡中 / 问不到 → 一位不动（不猜）。
  ///
  /// 本机界面同步**走既有的播放态来源**（[playbackEngineProvider] 那只内核
  /// ——界面显示的播放态就是它）：不在本域另起一个「投屏暂停位」让界面读，
  /// 否则界面会与电视各说各话。同步失败不向上抛、也不收口——一次本机界面
  /// 跟不上不该把还活着的投屏掐掉。
  Future<void> handlePlaybackState(CastPlaybackState reported) async {
    if (_session == null) return;
    switch (castPlaybackFollowOf(reported)) {
      case CastPlaybackFollow.syncPlaying:
        await _followLocalPlayback(playing: true);
      case CastPlaybackFollow.syncPaused:
        await _followLocalPlayback(playing: false);
      case CastPlaybackFollow.failSession:
        await _fail();
      case CastPlaybackFollow.hold:
        return;
    }
  }

  /// 退后台 / 锁屏 = 把投屏会话**视为暂停**（票 #41）：让接收端停下。
  ///
  /// **落在会话层，不是界面态**——不引前台服务（退后台就不是「还在投」），
  /// 会话本身也不在这里断（离开播放页 / 换视频由既有复位一处断开）：电视停在
  /// 那一帧等着，回来时按它上报的状态续上（[refreshPlaybackState]）。
  /// 本机界面在退后台这一刻不预判，与「接收端是权威」同一口径。
  ///
  /// **按不停也算会话建立之后的失败**（掉线 / 设备回绝）：一律走既有失败收口
  /// （断开 + 停服 + 回编辑态 + 短暂提示），不另开第二条失败路径——电视若不听
  /// 这一下，它就还在播，那就不是「视为暂停」。未投屏时空操作。
  Future<void> pauseForBackground() async {
    final session = _session;
    if (session == null) return;
    try {
      await session.pause();
    } on Object {
      await _fail();
    }
  }

  /// 回前台（播放页 `didChangeAppLifecycleState` 的 resumed 支）问一次接收端
  /// 此刻的播放状态，喂给 [handlePlaybackState] 按穷尽映射续上：那边已停就
  /// 断开回编辑态、给短暂提示；暂停 / 仍在播就同步本机界面；过渡 / 问不到
  /// 一位不动。
  ///
  /// **问不到也算会话建立之后的失败**（掉线）——同样收口，不留一个点不动的
  /// 界面。未投屏时空操作。
  Future<void> refreshPlaybackState() async {
    final session = _session;
    if (session == null) return;
    final CastPlaybackState reported;
    try {
      reported = await session.playbackState();
    } on Object {
      await _fail();
      return;
    }
    await handlePlaybackState(reported);
  }

  /// 本机界面追上接收端上报的播放态：驱动**既有播放态来源**（主内核）的
  /// play / pause。
  ///
  /// **不向接收端回推**：这一趟是「界面追电视」，不是又一次遥控——paused
  /// 一支尤其不许抢播。内核起不来 / 已随容器拆掉时静默跳过（不抛、不收口）。
  Future<void> _followLocalPlayback({required bool playing}) async {
    try {
      final engine = ref.read(playbackEngineProvider);
      if (playing) {
        await engine.play();
      } else {
        await engine.pause();
      }
    } on Object {
      // 本机界面跟不上一次不改变投屏这件事本身的去向。
    }
  }

  /// 后台把 [plan] 里**起投档之外**的档逐档渲出来（顺序渲：一次一条命令）。
  ///
  /// 不阻塞前台：本方法是 fire-and-forget（起投成功后调用），渲染不占会话、
  /// 遥控不等它。断开 / 换视频时代际号自增，这一轮在下一档之前就退出，在飞的
  /// 那一条由 [_teardown] 经渲染编排取消。
  void _startBackgroundRenders(CastSpeedTierPlan plan) {
    final pending = [
      for (final tier in plan.tiers)
        if (tier != plan.startTier) tier,
    ];
    if (pending.isEmpty) return;
    unawaited(_renderTiers(pending));
  }

  Future<void> _renderTiers(List<CastSpeedTier> tiers) async {
    final generation = _renderGeneration;
    final orchestrator = ref.read(castRenderOrchestratorProvider);
    final activity = ref.read(castRenderInProgressProvider.notifier);
    _rendering = true;
    var announced = false;
    try {
      for (final tier in tiers) {
        if (generation != _renderGeneration || !ref.mounted) return;
        final current = state.renderFor(tier);
        if (current == null ||
            current.ready ||
            current.status == CastTierRenderStatus.failed) {
          continue;
        }
        final request = _coordinates.requestFor(tier);
        if (request == null) {
          // 没给这一档的请求：它就是渲不出来（界面照「不可点」呈现）。
          _replaceTier(
            CastTierRender(tier: tier, status: CastTierRenderStatus.failed),
          );
          continue;
        }
        if (!request.choices.renders) {
          // 这一档不渲染：产物就是源片本身（零等待），直接可切。
          _replaceTier(CastTierRender.ready(tier, request.videoPath));
          continue;
        }
        if (!announced) {
          activity.begin();
          announced = true;
        }
        _replaceTier(
          CastTierRender(tier: tier, status: CastTierRenderStatus.rendering),
        );
        final result = await orchestrator.render(
          request,
          onProgress: (progress) {
            if (generation != _renderGeneration || !ref.mounted) return;
            _replaceTier(
              CastTierRender(
                tier: tier,
                status: CastTierRenderStatus.rendering,
                fraction: progress.fraction,
              ),
            );
          },
        );
        if (generation != _renderGeneration || !ref.mounted) return;
        final filePath = result.filePath;
        _replaceTier(
          filePath == null
              ? CastTierRender(tier: tier, status: CastTierRenderStatus.failed)
              : CastTierRender.ready(tier, filePath),
        );
      }
    } finally {
      _rendering = false;
      // 宿主容器可能已经拆掉（离开播放页 / 测试收场）：那一刻不再写事实位。
      if (announced && ref.mounted) activity.end();
    }
  }

  /// 换档失败的回退：重新递出**旧文件** → 推回去 → 按比例换算回旧档位置 →
  /// 续播，然后给一句 `cast_speed_switch_prompt`。
  ///
  /// 回退也失败 = 会话建立之后的失败（掉线一类），落回 [_fail]：断开 + 回
  /// 编辑态 + 既有那句提示。两条路都不会把「在投屏态却没有会话」留在屏上。
  Future<void> _recover({
    required CastSession session,
    required CastDeliveryChannel channel,
    required String file,
    required CastSpeedTier fromTier,
    required CastSpeedTier toTier,
    required Duration position,
  }) async {
    try {
      final source = await channel.serve(File(file));
      await session.push(source);
      await session.seek(
        _coordinates.resumePositionOf(
          position: position,
          from: fromTier,
          to: toTier,
        ),
      );
      await session.play();
    } on Object {
      await _fail();
      return;
    }
    if (!identical(_session, session)) return;
    state = state._with(switching: false);
    ref
        .read(noticeTriggerProvider(NoticeId.castSpeedSwitchFailed).notifier)
        .show();
  }

  /// 换掉某一档的运行账（后台渲染逐次推进状态用）。容器已拆时是空操作。
  void _replaceTier(CastTierRender render) {
    if (!ref.mounted) return;
    state = state._with(
      tiers: [
        for (final each in state.tiers)
          if (each.tier == render.tier) render else each,
      ],
    );
  }

  /// 失败收口：断开（含停服）+ 回编辑态 + 短暂提示。无会话时是空操作——
  /// 并发失败只收口一次，不重复弹提示。
  Future<void> _fail() async {
    if (_session == null) return;
    await disconnect();
    ref.read(noticeTriggerProvider(NoticeId.castInterrupted).notifier).show();
  }

  /// 进投屏态即持有唤醒（[CastScreenAwake.hold] 是引用计数式：重复持有只真的
  /// 拿一次）。只在 [start] 那一条边上调用——起投失败由 [_teardown] 配平。
  void _holdScreenAwake() {
    if (_awake) return;
    _awake = true;
    unawaited(ref.read(castScreenAwakeProvider).hold());
  }

  /// 离开投屏态即放掉唤醒。**唯一释放点**是 [_teardown]（断开 / 换视频 /
  /// 离开播放页 / 起投失败都经它）——不在三处各写一遍；没持有时不调
  /// （一次多余的释放会把画面件那一份唤醒也关掉）。
  void _releaseScreenAwake() {
    if (!_awake) return;
    _awake = false;
    unawaited(ref.read(castScreenAwakeProvider).release());
  }

  /// 投屏态的画面区接管那一帧的**帧末**再确认一次唤醒（画面区挂载时调，
  /// 见 `cast_picture_area.dart`）。
  ///
  /// 起投那一刻持的唤醒会被**退场的源画面件**踩掉：投屏态的画面区在源画面件
  /// 退场那一帧接管，而那个画面件要到同一帧收尾才 dispose——dispose 时它放开
  /// 自己那份唤醒，打的是同一个平台开关（那个开关不是引用计数的）。所以帧末
  /// 补按一次「开」。持有者仍只有本域一处：这不是第二个持有者，也没有计数 +1
  /// （见 [CastScreenAwake.reassert]）。没持有时是空操作。
  void reassertScreenAwake() {
    if (!_awake) return;
    unawaited(ref.read(castScreenAwakeProvider).reassert());
  }

  /// 收干净：取消在飞的后台渲染 + 停服 + 断连 + 状态回未投屏。三步各自
  /// best-effort——收尾失败不阻断另一步，也不向上抛（用户按下的那一下不能被
  /// 一次失败的收尾挡住）。
  Future<void> _teardown() async {
    // 唤醒**先放**：断连那一下可能被设备拖住，而「离开投屏态」这一刻屏幕就该
    // 回系统行为——不跟着收尾的耗时一起挂着。进出各一处：持有在 [start]，
    // 释放只在这里（断开 / 换视频 / 离开播放页 / 起投失败都经本方法）。
    _releaseScreenAwake();
    // 在飞的后台渲染随之作废并取消：它的进度不再属于任何一次投屏，它的
    // 半成品由渲染编排的收尾清掉。
    _renderGeneration++;
    final rendering = _rendering;
    _rendering = false;
    _coordinates = const CastCoordinates();
    final session = _session;
    final channel = _channel;
    _session = null;
    _channel = null;
    if (state.active) state = const CastRunState.idle();
    if (rendering) {
      try {
        await ref.read(castRenderOrchestratorProvider).cancel();
      } on Object {
        // 取消不掉不阻断停服：那条命令的收尾由编排自己兜（失败即删半成品）。
      }
    }
    if (channel != null) {
      try {
        await channel.close();
      } on Object {
        // 停服失败不阻断断连：通道是设备级缓存，进程退出即回收。
      }
    }
    if (session != null) {
      try {
        await session.disconnect();
      } on Object {
        // 断开本身不再抛（会话契约）。
      }
    }
  }
}

/// 投屏运行域的注入点（唯一实例）。
final castRunProvider = NotifierProvider<CastRunModel, CastRunState>(
  CastRunModel.new,
);

/// 当前投屏会话的**遥控项判据**（票 #38）：接收端能力这一层的取值——未投屏
/// 时是「哪一项都不显示」那份。它是能力事实，不回答界面的「显不显示」：那一问
/// 的唯一回答处是 [castRemoteItemShownProvider]（它在这一层之上补「非投屏态
/// 恒显示」的短路）。select 只订阅这一个字段：后台渲染的进度变化不重建读它的
/// 控件。
final castRemoteControlsProvider = Provider<CastRemoteControls>(
  (ref) => ref.watch(castRunProvider.select((state) => state.remoteControls)),
);

/// 投屏态内某一枚遥控项此刻显不显示——**唯一回答处**（票 #44）：手势仲裁
/// （进度 / 播放暂停 / 音量三段手势）与控制层（两枚控件在不在装配里）同读
/// 它，两处不各自另判。
///
/// 「**非投屏态恒显示**」这条短路写在这里一次（改投屏判据不动非投屏行为）；
/// 投屏态逐项照 [CastRemoteControls.shows]（接收端能力判据，见
/// `lib/cast/cast_session.dart`）。
final castRemoteItemShownProvider = Provider<bool Function(CastRemoteItem)>((
  ref,
) {
  if (!ref.watch(playerSessionProvider.select((s) => s.isCast))) {
    return (_) => true;
  }
  return ref.watch(castRemoteControlsProvider).shows;
});
