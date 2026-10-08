/// 投屏准备面板：进入**投屏态**之前那一段编排的界面——列同一局域网上的
/// **接收端**、勾选要渲染的东西、**多选投屏倍速档**、看渲染进度、可取消，
/// 并把两条**门事实**当场拦下并说明。
///
/// ## 它回答三件事
///
/// 1. **投什么**：两个勾选档（画面类 / 声音类，默认全选）。三句实话各配一种
///    组合：都不勾 = 直接推原片；只勾声音 = 秒级；勾了画面 = 预计分钟级、
///    改一次设置就要重渲一次（见 [castPrepRenderSentenceFor]）。
/// 2. **投几档**：**投屏倍速档多选**——候选只有 0.5 / 0.75 / 1 三档，默认勾
///    与当前手动倍率最接近的那一档（`cast_speed_tier.dart` 的纯件）；至少留
///    一档。都不勾渲染档时只剩原片这一档（1×）：没有副本可换，勾别档没有
///    意义。
/// 3. **投到哪台**：接收端列表（选中一台即开始渲染，渲好即带出接收端、档计划
///    与产物路径）。
///
/// ## 渲染发生在这里（进度与取消也在这里）
///
/// 选中接收端后本面板经**渲染编排**（`cast_render_orchestrator.dart`）渲
/// **起投档**（当前倍率最近的那一档）：进度条读执行器报的进度，取消按钮走
/// 编排的取消。其余档**不在这里渲**——投上之后由投屏运行域后台接着渲
/// （先投后渲），所以本面板的进度只关起投档。渲染失败给一句失败话并回到
/// 列表（可以再试或换勾选）；**取消不是失败**，回到列表原样。渲染成功才 pop
/// 出 [CastPrepOutcome]——起递出通道、连会话、推片、起播与进入投屏态的编排
/// 都在宿主。
///
/// ## 两条门都在面板里当场拦下并说明
///
/// - **副本丢失**（[kCastPrepCopyMissingText]）：这支舞的**视频副本**不在
///   本机——面板只出这一句说明，不出接收端列表（推一份不在盘上的文件没有
///   意义）。存在性问的是全 App 唯一那一处判定
///   （`lib/dance/video_copy_presence.dart`）。
/// - **发现不到接收端**（[kCastPrepNoReceiverText]）：搜到空表（或发现本身
///   出不了网，两者同一口径）——空态说明「手机与电视要在同一个 Wi-Fi、电视
///   别开访客网络」，并把重扫按钮留在眼前。
///
/// 本文件零网络实现：发现走发现接缝、渲染走编排接缝（真实实现分别走 SSDP 与
/// 已链接的 ffmpeg，测试注入脚本化替身）。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cast/cast_render_activity.dart' show castRenderInProgressProvider;
import '../cast/cast_render_executor.dart' show CastRenderProgress;
import '../cast/cast_render_orchestrator.dart';
import '../cast/cast_render_request.dart';
import '../cast/cast_receiver.dart';
import '../cast/cast_speed_tier.dart';
import '../dance/video_copy_presence.dart' show videoCopyPresenceProvider;
import 'play_tool_table.dart' show kSystemMirrorHintText;
import 'system_mirror_entry.dart' show openSystemMirrorEntry;
import 'visual_tokens.dart' show kPlayerSkinColor;

/// 副本丢失门的文案（唯一一份生产取值；测试逐字重写期望值，故意不从本
/// 常量取——文案改了要能在测试里看见）。
const String kCastPrepCopyMissingText = '这支舞的视频副本不在本机，先把副本找回来再投屏';

/// 发现不到接收端（不在同一局域网）门的文案。
const String kCastPrepNoReceiverText = '没找到接收端：手机与电视要在同一个 Wi-Fi，电视别开访客网络';

/// 正在搜索的那一句（重扫期间也在）。
const String kCastPrepScanningText = '正在搜索同一局域网上的接收端…';

/// 面板标题。
const String kCastPrepTitle = '投屏到哪台设备';

/// 都不勾时的实话：不渲染、直接推原片。
const String kCastPrepSentencePassThrough = '不渲染：直接把原片推给电视，不用等';

/// 只勾声音类时的实话：秒级。
const String kCastPrepSentenceSoundOnly = '只重做音轨：拍声混进去，秒级出结果';

/// 勾了画面类时的实话：分钟级，且改设置要重渲。
const String kCastPrepSentencePicture = '画面要重编码：预计分钟级；改一次设置就要重渲一次';

/// 倍速档那一段的标题。
const String kCastPrepTierTitle = '投屏倍速档';

/// 都不勾渲染档时的实话：没有副本可换，只有原片这一档。
const String kCastPrepTierPassThrough = '不渲染就没有别的倍速档可换：只有原片这一档（1×）';

/// 渲染失败时的那一句。
const String kCastPrepRenderFailedText = '这次没渲出来：可以再试一次，或改一下勾选';

/// 正在渲染的那一句（后面带百分比）。
const String kCastPrepRenderingText = '正在渲染投屏副本';

/// 勾选档 → 那一句实话（三句，逐组合唯一）。
String castPrepRenderSentenceFor(CastRenderChoices choices) {
  if (!choices.renders) return kCastPrepSentencePassThrough;
  if (!choices.picture) return kCastPrepSentenceSoundOnly;
  return kCastPrepSentencePicture;
}

/// 档计划 → 那一句实话（先投后渲：先渲哪一档、其余档去哪）。
String castPrepTierSentenceFor(CastSpeedTierPlan plan) {
  if (plan.pending.isEmpty) {
    return '只备「${castSpeedTierLabel(plan.startTier)}」这一档：'
        '投上之后没有别的档要渲';
  }
  return '先渲「${castSpeedTierLabel(plan.startTier)}」这一档，投上之后'
      '其余 ${plan.pending.length} 档在后台接着渲';
}

/// 一档在准备面板里的定位 key（测试与界面共用）。
Key castPrepTierKey(CastSpeedTier tier) => Key('cast_speed_tier_${tier.name}');

/// 面板的出参：投到哪台 + 这次备哪几档 + 各档的渲染请求 + 要立刻推的那一份。
class CastPrepOutcome {
  const CastPrepOutcome({
    required this.receiver,
    required this.plan,
    required this.requests,
    required this.filePath,
  });

  final CastReceiver receiver;

  /// 这次备的档（要备哪几档、先渲哪一档）。
  final CastSpeedTierPlan plan;

  /// 各档的渲染请求（投上之后后台渲染逐档取用）。
  final Map<CastSpeedTier, CastRenderRequest> requests;

  /// 要立刻推给接收端的文件路径：**起投档**的产物；都不勾渲染就是原片。
  final String filePath;

  @override
  String toString() =>
      'CastPrepOutcome(${receiver.friendlyName}, $plan, $filePath)';
}

/// 投屏准备面板（宿主经 `showDialog` 呈现；出参 = 接收端 + 档计划 + 要推的
/// 那一份）。
class CastPrepPanel extends ConsumerStatefulWidget {
  const CastPrepPanel({
    super.key,
    required this.videoFilePath,
    required this.manualRate,
    required this.requestOf,
  });

  /// 这支舞的**视频副本**路径（副本存在性判定的输入，也是不渲染时的产物）。
  final String videoFilePath;

  /// 打开面板那一刻的**手动倍率**（默认勾哪一档、先渲哪一档都按它就近取值）。
  /// 由宿主读数交入——面板不认倍速域。
  final double manualRate;

  /// 按当前勾选档与**某一档**装配一份渲染请求（各域读面由宿主读齐，见
  /// `cast_render_wiring.dart`）。
  final CastRenderRequest Function(
    CastRenderChoices choices,
    CastSpeedTier tier,
  )
  requestOf;

  @override
  ConsumerState<CastPrepPanel> createState() => _CastPrepPanelState();
}

class _CastPrepPanelState extends ConsumerState<CastPrepPanel> {
  /// 默认全选（画面类 + 声音类）。
  CastRenderChoices _choices = const CastRenderChoices.all();

  /// 勾了哪几档（默认 = 与手动倍率最接近的那一档）。
  late Set<CastSpeedTier> _tiers = defaultCastSpeedTiersFor(widget.manualRate);

  bool _scanning = true;
  List<CastReceiver> _receivers = const [];

  /// 正在渲染的那台接收端（null = 没在渲染）。
  CastReceiver? _pending;
  CastRenderProgress? _progress;
  bool _renderFailed = false;

  /// 这次渲染还在飞（面板被关掉时要把它取消掉；`_pending` 在成功 pop 的那一
  /// 刻仍留着给「投到谁」那行字用，所以另用一个旗标）。
  bool _inFlight = false;

  bool get _rendering => _pending != null;

  @override
  void initState() {
    super.initState();
    // 打开即扫一次；重扫就是再调一次（发现是「问一次答一次」，不是长跑
    // 订阅）。副本丢失时不必扫——那条门先拦住。
    if (!ref.read(videoCopyPresenceProvider).exists(widget.videoFilePath)) {
      _scanning = false;
      return;
    }
    unawaited(_scan());
  }

  @override
  void dispose() {
    // 面板被关掉（取消 / 返回 / 离开页面）时，在飞的那次渲染一并取消：
    // 投屏准备的取消是「回到进它之前的样子、零副作用」——不让一条 ffmpeg 在
    // 面板不在时继续跑，半成品由编排收尾清掉。
    final orchestrator = _orchestrator;
    if (_inFlight && orchestrator != null) {
      unawaited(orchestrator.cancel());
    }
    super.dispose();
  }

  /// 这次准备用的编排器（起渲染时抓住；`dispose` 里不能再读 provider）。
  CastRenderOrchestrator? _orchestrator;

  /// 副本丢失门的事实：存在性问的是全 App 唯一那一处判定
  /// （`lib/dance/video_copy_presence.dart`）。同步查询，构建期直读。
  bool get _copyMissing =>
      !ref.watch(videoCopyPresenceProvider).exists(widget.videoFilePath);

  Future<void> _scan() async {
    setState(() => _scanning = true);
    List<CastReceiver> found;
    try {
      found = await ref.read(castReceiverDiscoveryProvider).discover();
    } on Object {
      // 发现本身出不了网 / 替身注入失败：与「一台都没发现」同一口径
      // （空表不是失败，见发现接缝）。
      found = const [];
    }
    if (!mounted) return;
    setState(() {
      _receivers = found;
      _scanning = false;
    });
  }

  void _setChoice(CastRenderChoices choices) {
    if (_rendering) return;
    setState(() {
      _choices = choices;
      _renderFailed = false;
    });
  }

  /// 这次要备哪几档、先渲哪一档（纯件算；都不勾渲染档时只剩原片这一档）。
  CastSpeedTierPlan get _plan => castSpeedTierPlanFor(
    renders: _choices.renders,
    manualRate: widget.manualRate,
    selected: _tiers,
  );

  /// 界面上三个勾选框此刻的样子：都不勾渲染档时固定「只有 1× 这一档」。
  Set<CastSpeedTier> get _shownTiers =>
      _choices.renders ? _tiers : const {CastSpeedTier.full};

  /// 勾/取消一档。**至少留一档**：取消最后一档是空操作（投屏总得有一份可
  /// 播的）。渲染期间不可改（改了要重来一次）。
  void _setTier(CastSpeedTier tier, bool checked) {
    if (_rendering || !_choices.renders) return;
    final next = {..._tiers};
    if (checked) {
      next.add(tier);
    } else {
      if (next.length <= 1) return;
      next.remove(tier);
    }
    setState(() {
      _tiers = next;
      _renderFailed = false;
    });
  }

  /// 选中一台接收端 = 开始这次准备：装配各档请求 → 渲**起投档** → 带出结局
  /// （其余档投上之后由投屏运行域后台渲）。
  Future<void> _pick(CastReceiver receiver) async {
    final CastSpeedTierPlan plan;
    final requests = <CastSpeedTier, CastRenderRequest>{};
    try {
      plan = _plan;
      for (final tier in plan.tiers) {
        requests[tier] = widget.requestOf(_choices, tier);
      }
    } on Object {
      // 读面还没就绪（例如标注尚未装载）——当场说明，不静默什么都不做。
      setState(() => _renderFailed = true);
      return;
    }

    setState(() {
      _pending = receiver;
      _progress = null;
      _renderFailed = false;
      _inFlight = true;
    });

    final orchestrator = ref.read(castRenderOrchestratorProvider);
    _orchestrator = orchestrator;
    // 起渲与收工都记进「渲染进行中」这一位事实（投屏入口的门读它）。
    final activity = ref.read(castRenderInProgressProvider.notifier);
    activity.begin();
    final CastRenderResult result;
    try {
      result = await orchestrator.render(
        requests[plan.startTier]!,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } finally {
      activity.end();
    }

    if (!mounted) return;
    _inFlight = false;
    final filePath = result.filePath;
    if (filePath != null) {
      Navigator.of(context).pop(
        CastPrepOutcome(
          receiver: receiver,
          plan: plan,
          requests: requests,
          filePath: filePath,
        ),
      );
      return;
    }
    setState(() {
      _pending = null;
      _progress = null;
      // 取消不是失败：回到列表原样；失败才给那一句。
      _renderFailed = result.exit == CastRenderExit.failed;
    });
  }

  /// 取消正在跑的这次渲染（编排侧取消执行器；半成品由编排收尾清掉）。
  void _cancelRender() {
    unawaited(ref.read(castRenderOrchestratorProvider).cancel());
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('cast_prep_panel'),
      backgroundColor: kPlayerSkinColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                kCastPrepTitle,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 8),
              _choicesRow(),
              const SizedBox(height: 4),
              Text(
                castPrepRenderSentenceFor(_choices),
                key: const Key('cast_render_sentence'),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              _tierSection(),
              const SizedBox(height: 8),
              if (_rendering)
                _renderProgress()
              else if (_copyMissing)
                _gateText(kCastPrepCopyMissingText, const Key('cast_gate_copy'))
              else ...[
                if (_renderFailed)
                  _gateText(
                    kCastPrepRenderFailedText,
                    const Key('cast_render_failed'),
                  ),
                if (_scanning)
                  _gateText(
                    kCastPrepScanningText,
                    const Key('cast_prep_scanning'),
                  )
                else if (_receivers.isEmpty) ...[
                  _gateText(
                    kCastPrepNoReceiverText,
                    const Key('cast_gate_no_receiver'),
                  ),
                  // 「我们这条路」此刻走不通，这里放**同一条**系统镜像入口
                  // （与投屏态顶栏那枚同一个动作、同一份文案）：把整屏镜像
                  // 那条路的代价摆在按钮上方，再送用户去系统设置。
                  _systemMirrorEntry(),
                ] else
                  for (final receiver in _receivers)
                    ListTile(
                      key: Key('cast_receiver_${receiver.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.tv, color: Colors.white70),
                      title: Text(
                        receiver.friendlyName,
                        style: const TextStyle(color: Colors.white),
                      ),
                      // 只列**能当投屏对象**的接收端（有 AVTransport 控制
                      // 端点）——发现接缝已按此过滤，这里不再二次判。
                      onTap: receiver.canReceiveCast
                          ? () => unawaited(_pick(receiver))
                          : null,
                    ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_rendering)
                    TextButton(
                      key: const Key('cast_render_cancel'),
                      onPressed: _cancelRender,
                      child: const Text('取消渲染'),
                    )
                  else ...[
                    if (!_copyMissing)
                      TextButton(
                        key: const Key('cast_prep_refresh'),
                        onPressed: _scanning ? null : _scan,
                        child: const Text('重新搜索'),
                      ),
                    TextButton(
                      key: const Key('cast_prep_cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 投屏倍速档那一段：三档多选（候选只有 0.5 / 0.75 / 1）+ 先投后渲那句实话
  /// +「都不勾渲染档时只剩原片这一档」。
  ///
  /// 至少留一档：唯一勾着的那一枚不能再取消（投屏总得有一份可播的）。
  /// 都不勾渲染档时三枚一律置灰、只勾着 1×——没有副本可换，勾别档没有意义。
  Widget _tierSection() {
    final shown = _shownTiers;
    final locked = _rendering || !_choices.renders;
    return Column(
      key: const Key('cast_speed_tiers'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          kCastPrepTierTitle,
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final tier in kCastSpeedTierCandidates)
              Expanded(
                child: CheckboxListTile(
                  key: castPrepTierKey(tier),
                  value: shown.contains(tier),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    castSpeedTierLabel(tier),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  onChanged: locked
                      ? null
                      : (checked) => _setTier(tier, checked ?? false),
                ),
              ),
          ],
        ),
        Text(
          _choices.renders
              ? castPrepTierSentenceFor(_plan)
              : kCastPrepTierPassThrough,
          key: const Key('cast_speed_tier_sentence'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  /// 「搜不到接收端」空态里那枚**系统镜像**入口：代价差文案 + 送出按钮。
  /// 文案取的是那条入口自己的提示文案（[kSystemMirrorHintText]，与投屏态
  /// 顶栏那枚共用一份）——在面板里有版面，就直白摆出来，不必长按；动作走
  /// [openSystemMirrorEntry]：先断开（这里本就没投，断开是幂等空操作）再跳、
  /// 降级链走不通给一句短暂提示。
  Widget _systemMirrorEntry() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        key: const Key('cast_prep_system_mirror_hint'),
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          kSystemMirrorHintText,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: const Key('cast_prep_system_mirror'),
          onPressed: () => unawaited(openSystemMirrorEntry(ref)),
          child: const Text('系统镜像'),
        ),
      ),
    ],
  );

  /// 两个勾选档（默认全选；渲染期间不可改——改了要重来一次）。
  Widget _choicesRow() {
    Widget box({
      required Key key,
      required String label,
      required bool value,
      required CastRenderChoices Function(bool checked) next,
    }) => Expanded(
      child: CheckboxListTile(
        key: key,
        value: value,
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        onChanged: _rendering
            ? null
            : (checked) => _setChoice(next(checked ?? false)),
      ),
    );

    return Row(
      children: [
        box(
          key: const Key('cast_choice_picture'),
          label: '画面类',
          value: _choices.picture,
          next: (checked) => _choices.copyWith(picture: checked),
        ),
        box(
          key: const Key('cast_choice_sound'),
          label: '声音类',
          value: _choices.sound,
          next: (checked) => _choices.copyWith(sound: checked),
        ),
      ],
    );
  }

  /// 渲染进度：比例条 + 百分比 + 投给谁（取消按钮在按钮行里）。
  Widget _renderProgress() {
    final fraction = _progress?.fraction;
    final percent = fraction == null ? null : (fraction * 100).round();
    return Column(
      key: const Key('cast_render_progress'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: 6),
        Text(
          percent == null
              ? '$kCastPrepRenderingText…'
              : '$kCastPrepRenderingText… $percent%',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          '投到「${_pending?.friendlyName ?? ''}」，先渲'
          '「${castSpeedTierLabel(_plan.startTier)}」这一档，'
          '渲好即开始推片',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
      ],
    );
  }

  Widget _gateText(String text, Key key) => Padding(
    key: key,
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(
      text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
    ),
  );
}
