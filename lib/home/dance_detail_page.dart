import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dance/cover_frame_providers.dart';
import '../dance/dance_library.dart';
import '../dance/dance_library_providers.dart';
import '../annotation/learning_segment_attributes.dart'
    show LearningMastery, learningMasteryLabel;
import '../dance/mastery_label.dart' show kMasteredLabel, kNotMasteredLabel;
import '../dance/practice_distribution.dart';
import '../persistence/member_scheme_store.dart'
    show MemberSchemeRecord, memberSchemeStoreProvider, memberSchemesProvider;
import '../persistence/song_signature.dart' show songFallbackName;
import 'dance_detail_plan_section.dart' show DancePlanSection;
import '../player/player_page.dart';
import '../player/scheme_open.dart'
    show AutoSchemeOpen, MemberSchemeOpen, MySchemeOpen, SchemeOpen;
import '../player/song_naming.dart';
import '../share/dance_share_sheet.dart';
import '../share_channel/share_channel.dart';
import '../stats/practice_stats_format.dart';
import 'cover_placeholder.dart';
import 'cover_picker_page.dart';
import 'practice_distribution_chart.dart';

/// 舞详情页：一屏看到总览（练习总时长、最近练习、平均练习遍数、完全掌握）、
/// 练习分布图（卡上一键完全掌握并撤销）与组员方案区；「我的标注 · 逐段」
/// 逐段量与熟练度在练习分布图上读。点一行方案即以那一份方案
/// 进入播放；改名（版本舞者 + 歌曲名 + 版本注记三字段）、「分享」与删除这支
/// 舞收在 AppBar 右上「⋯」菜单里，页尾只留「继续播放」一颗主钮。
///
/// 总览量全部来自舞库单支舞入口，本页只渲染不算术；打开/续播沿用
/// 卡片主体的同一次打开（续播位置与「从头播放？」归播放器侧）。一键
/// 完全掌握经舞库管理写落盘后作废读面，卡片百分比与完成勾随即更新；其
/// 撤销用页面内快照（不入标注编辑历史），无分段线时入口按「无
/// 对象」置灰不可点。改名经舞库管理写落盘后作废读面，卡片与详情同显新名
/// （不必重开）；删除经舞库自持写路径（[deleteDanceFrom]）：索引先写、文件
/// best-effort、素材连带、统计保留，成功后返回舞库。
class DanceDetailPage extends ConsumerStatefulWidget {
  const DanceDetailPage({super.key, required this.videoId});

  /// 舞身份（内容寻址哈希）：详情量按此经舞库单支入口重取。
  final String videoId;

  @override
  ConsumerState<DanceDetailPage> createState() => _DanceDetailPageState();
}

class _DanceDetailPageState extends ConsumerState<DanceDetailPage> {
  /// 一键完全掌握点击前的页面内快照；null = 本页还没点过，不出撤销入口。
  /// 只在首次点击时记录——重复点击不覆盖，撤销始终回到最初点击之前。
  DanceMasteryValues? _markAllMasteredSnapshot;

  /// 打开/续播：与卡片主体同一次打开；[scheme] = 这次打开带的方案参数
  /// （页尾「打开续播」不带参数，方案区的每一行带自己那一份）。回到本页
  /// 重算读面（本次练习的统计已落盘）。
  Future<void> _openPlayer(DanceSnapshot dance, SchemeOpen scheme) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            PlayerPage(source: File(dance.entry.filePath).uri, scheme: scheme),
      ),
    );
    if (!mounted) return;
    invalidateDanceLibraryFrom(ref);
  }

  /// 一次改档写：落盘成功返回 true；失败如实告知（原子写保证文件没有变化）
  /// 并返回 false。
  Future<bool> _writeMastery(String videoId, DanceMasteryValues values) async {
    final written = await ref
        .read(danceLibraryWritesProvider)
        .setSegmentsMastery(videoId: videoId, values: values);
    if (!written && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('改档失败')));
    }
    return written;
  }

  /// 一键完全掌握：全部段写最高档；点击前在页内捕获一次快照，撤销即回写该
  /// 快照——不放进标注编辑历史（本页不建会话）。
  Future<void> _markAllMastered(DanceSnapshot dance) async {
    final before = DanceMasteryValues.of(dance.segments);
    final written = await _writeMastery(dance.videoId, before.allMastered);
    if (!mounted || !written) return;
    setState(() => _markAllMasteredSnapshot ??= before);
    invalidateDanceLibraryFrom(ref);
  }

  /// 撤销一键完全掌握：回写点击前的页面内快照，读面重算——回到点之前的样子
  /// （当时未练的段重新缺席，稀疏存储不变）。
  Future<void> _undoMarkAllMastered(DanceSnapshot dance) async {
    final snapshot = _markAllMasteredSnapshot;
    if (snapshot == null) return;
    final written = await _writeMastery(dance.videoId, snapshot);
    if (!mounted || !written) return;
    setState(() => _markAllMasteredSnapshot = null);
    invalidateDanceLibraryFrom(ref);
  }

  /// 练习分布图上的就地改档（图例行右侧菜单按钮）：单段写熟练度，与播放器
  /// 标注工具区同一份管理写面落盘，读面作废后色带就地换色。
  Future<void> _changeSegmentMastery(
    DanceSnapshot dance,
    int order,
    LearningMastery mastery,
  ) async {
    final written = await _writeMastery(
      dance.videoId,
      DanceMasteryValues(orders: [order], mastery: {order: mastery}),
    );
    if (!mounted || !written) return;
    invalidateDanceLibraryFrom(ref);
  }

  /// 分享：弹出分享面（三项勾选 + 包体预检），确认后装配 `.susume` 并经
  /// 平台分享通道递出原文件（见 `share/dance_share_sheet.dart`）。
  Future<void> _share(DanceSnapshot dance) async {
    await showDialog<void>(
      context: context,
      builder: (_) => DanceShareSheet(dance: dance),
    );
  }

  /// 源视频 mp4 直发：把源视频副本作为普通 mp4 经
  /// 平台分享通道递出**原文件**（零复制），不装配 `.susume` 包。失败如实
  /// 告知，不静默。入口在 ⋯ 菜单里按源视频副本是否存在置灰（置灰原因见
  /// 菜单项文案）。
  Future<void> _shareVideoMp4(DanceSnapshot dance) async {
    try {
      await ref.read(shareChannelProvider).shareFile(_sourceVideoFile(dance));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('分享失败')));
    }
  }

  /// 源视频副本：mp4 直发的递出对象，与 ⋯ 菜单的存在性门同一处构造。
  File _sourceVideoFile(DanceSnapshot dance) => File(dance.entry.filePath);

  /// 改名：同款三字段编辑（版本舞者与版本注记可选），保存后经舞库管理写
  /// 落盘（署名真值先、索引署名缓存后），并作废读面——卡片与详情随即显示
  /// 新名，不必重开页面。
  ///
  /// 未署名舞的初值与该框的回退文本都取「文件名回落名」（去扩展名的显示
  /// 名）——与播放页顶栏、命名框、统计记账同一读面。
  Future<void> _rename(DanceSnapshot dance) async {
    final fallbackName = songFallbackName(dance.entry.displayName);
    final initial = resolveSongNamingInitial(
      scene: SongNamingScene.rename,
      current: dance.signature,
      fallbackFileName: fallbackName,
    );
    final result = await showDialog<SongNamingResult>(
      context: context,
      builder: (_) => SongNamingDialog(
        scene: SongNamingScene.rename,
        initialSong: initial.song,
        initialDancer: initial.dancer,
        initialRemark: initial.remark,
        fallbackText: fallbackName,
      ),
    );
    if (!mounted || result == null || !result.confirmed) return;
    final renamed = await ref
        .read(danceLibraryWritesProvider)
        .rename(entry: dance.entry, input: result.signature);
    if (!mounted) return;
    if (!renamed) {
      // 署名真值没写成 = 改名不成立，落盘内容原样：如实告知，不重算读面。
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('改名失败')));
      return;
    }
    invalidateDanceLibraryFrom(ref);
  }

  /// 换封面：进入简化选帧界面（预览复用同一播放内核与既有拖动链路）。
  /// 确认写盘后由选帧界面自己作废读面，返回时横幅已显示新封面；
  /// 返回或取消不写入，这里不需再作废。
  Future<void> _changeCover(DanceSnapshot dance) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CoverPickerPage(
          videoId: dance.videoId,
          sourcePath: dance.entry.filePath,
          initialPosition: dance.coverPosition,
        ),
      ),
    );
  }

  /// 删除一条组员方案：二次确认由本页承载（[MemberSchemeRecord.schemeId]
  /// 定位，只删那一条），落盘后作废组员方案读面——行即消失；我的标注文档
  /// 不经此路径，原样不动。写失败如实告知（原子写保证文件没有变化）。
  Future<void> _confirmRemoveScheme(
    String videoId,
    MemberSchemeRecord scheme,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('scheme_delete_dialog'),
        content: Text('删除「${memberDisplayName(scheme)}」的方案？只删这一条，我的标注不受影响'),
        actions: [
          TextButton(
            key: const Key('scheme_delete_cancel'),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('scheme_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(memberSchemeStoreProvider(videoId))
          .remove(scheme.schemeId);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败')));
      return;
    }
    if (!mounted) return;
    ref.invalidate(memberSchemesProvider(videoId));
  }

  /// 删除这支舞：二次确认由本页承载、默认不删（取消 = 什么都不做）。确认后
  /// 经舞库删除动作落盘——索引写失败 = 删除不成立，留在本页并提示；成功后
  /// 返回舞库（首页读面重算，卡片消失）。
  Future<void> _confirmDelete(DanceSnapshot dance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('dance_delete_dialog'),
        content: const Text('将连视频副本、公开标记文件、本地私密文件、组员方案与该舞练习素材一并删除；练舞统计保留'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            key: const Key('dance_delete_confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await deleteDanceFrom(ref, dance.videoId);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除失败')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dance = ref.watch(danceSnapshotProvider(widget.videoId));
    final snapshot = dance.asData?.value;
    final schemes = ref.watch(memberSchemesProvider(widget.videoId));
    return Scaffold(
      appBar: AppBar(
        title: Text(dance.asData?.value?.title ?? '舞详情'),
        // 管理动作收进右上「⋯」：页尾只留「打开续播」主钮。菜单仅在本支舞
        // 在库里时出现。
        actions: [
          if (snapshot != null)
            PopupMenuButton<String>(
              key: const Key('dance_detail_more'),
              tooltip: '更多操作',
              onSelected: (action) {
                if (action == 'share') {
                  _share(snapshot);
                } else if (action == 'rename') {
                  _rename(snapshot);
                } else if (action == 'delete') {
                  _confirmDelete(snapshot);
                } else if (action == 'share_mp4') {
                  _shareVideoMp4(snapshot);
                } else if (action == 'change_cover') {
                  _changeCover(snapshot);
                }
              },
              itemBuilder: (_) {
                // 存在性门：源视频副本不在时置灰并说明原因。在菜单展开时
                // 判定（本机文件存在性检查，代价可忽略）。
                final sourceExists = _sourceVideoFile(snapshot).existsSync();
                return [
                  PopupMenuItem<String>(
                    key: const Key('dance_detail_share'),
                    value: 'share',
                    child: const Text('分享'),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('dance_detail_share_mp4'),
                    value: 'share_mp4',
                    enabled: sourceExists,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('分享视频（mp4）'),
                        if (!sourceExists)
                          const Text(
                            '源视频副本不在',
                            key: Key('dance_detail_share_mp4_missing'),
                            style: TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('dance_detail_rename'),
                    value: 'rename',
                    child: const Text('改名'),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('dance_detail_change_cover'),
                    value: 'change_cover',
                    child: const Text('换封面'),
                  ),
                  PopupMenuItem<String>(
                    key: const Key('dance_detail_delete'),
                    value: 'delete',
                    child: const Text('删除这支舞'),
                  ),
                ];
              },
            ),
        ],
      ),
      body: dance.when(
        // 静态加载态：读面是本地文件读，不引入持续动画（与首页同款）。
        loading: () => const Center(child: Text('加载中…')),
        error: (_, _) => const Center(child: Text('舞详情读取失败')),
        data: (snapshot) => snapshot == null
            ? const Center(
                key: Key('dance_detail_missing'),
                child: Text('这支舞已不在舞库'),
              )
            : _DanceDetailBody(
                dance: snapshot,
                memberSchemes: schemes.whenData((document) => document.schemes),
                onOpenScheme: (scheme) => _openPlayer(snapshot, scheme),
                onMarkAllMastered: () => _markAllMastered(snapshot),
                onUndoMarkAllMastered: () => _undoMarkAllMastered(snapshot),
                canUndoMarkAllMastered: _markAllMasteredSnapshot != null,
                onSegmentMasteryChanged: (order, mastery) =>
                    _changeSegmentMastery(snapshot, order, mastery),
                onRemoveScheme: (scheme) =>
                    _confirmRemoveScheme(widget.videoId, scheme),
              ),
      ),
    );
  }
}

class _DanceDetailBody extends ConsumerStatefulWidget {
  const _DanceDetailBody({
    required this.dance,
    required this.memberSchemes,
    required this.onOpenScheme,
    required this.onMarkAllMastered,
    required this.onUndoMarkAllMastered,
    required this.canUndoMarkAllMastered,
    required this.onSegmentMasteryChanged,
    required this.onRemoveScheme,
  });

  final DanceSnapshot dance;

  /// 该舞的组员方案（只读导入的那批）；数据为空 = 区不出现（无物可点，也不
  /// 占视觉重量），读取失败如实出错误条，加载中不当作空。
  final AsyncValue<List<MemberSchemeRecord>> memberSchemes;

  /// 方案区每一行点击 = 以那一份方案进入播放（我的可写、组员只读）。
  final void Function(SchemeOpen scheme) onOpenScheme;
  final VoidCallback onMarkAllMastered;
  final VoidCallback onUndoMarkAllMastered;
  final bool canUndoMarkAllMastered;

  /// 练习分布图图例行右侧的就地改档：写面收在外层页状态
  /// （[DanceDetailPage]），与一键完全掌握同一份管理写。
  final void Function(int order, LearningMastery mastery)
  onSegmentMasteryChanged;

  final void Function(MemberSchemeRecord scheme) onRemoveScheme;

  @override
  ConsumerState<_DanceDetailBody> createState() => _DanceDetailBodyState();
}

class _DanceDetailBodyState extends ConsumerState<_DanceDetailBody> {
  /// 曲线两轴：默认时长 / 累计。
  PracticeDistributionMetric _metric = PracticeDistributionMetric.duration;
  PracticeDistributionRange _range = PracticeDistributionRange.cumulative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dance = widget.dance;
    final lastPracticedAt = dance.lastPracticedAt;
    final distribution = ref.watch(
      dancePracticeDistributionProvider(dance.videoId),
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _CoverBanner(dance: dance),
        const SizedBox(height: 16),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Column(
              children: [
                _OverviewRow(
                  label: '练习总时长',
                  valueKey: 'dance_detail_total',
                  value: Text(statsDurationText(dance.practiceTotal)),
                ),
                _OverviewRow(
                  label: '最近练习',
                  valueKey: 'dance_detail_last',
                  value: Text(
                    lastPracticedAt == null
                        ? '还没练过'
                        : dayLabel(lastPracticedAt, now: DateTime.now()),
                  ),
                ),
                // 无有效区间（未落盘或零长）显示 —，不用整片时长凑假数。
                _OverviewRow(
                  label: '平均练习遍数',
                  valueKey: 'dance_detail_average',
                  value: Text(
                    averagePracticeCountText(dance.averagePracticeCount),
                  ),
                ),
                // 完全掌握：段集非空且全段最高档才有勾；没标注不显示勾。
                // 真值配可读标签：对勾与破折号读屏都读不出。
                _OverviewRow(
                  label: '完全掌握',
                  valueKey: 'dance_detail_mastered',
                  value: Semantics(
                    container: true,
                    excludeSemantics: true,
                    label: dance.fullyMastered
                        ? kMasteredLabel
                        : kNotMasteredLabel,
                    child: dance.fullyMastered
                        ? Icon(
                            Icons.check_circle,
                            size: 18,
                            color: theme.colorScheme.primary,
                          )
                        : const Text('—'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('dance_detail_open'),
          onPressed: () => widget.onOpenScheme(const AutoSchemeOpen()),
          icon: const Icon(Icons.play_arrow),
          label: const Text('继续播放'),
        ),
        const SizedBox(height: 16),
        // 方案区：一排入口，不是单选器——「我的标注」与各组员方案并列成行，
        // 点一行即以那一份方案进入播放（我的可写、组员只读），组员那几行
        // 行尾可删。无组员方案时不出现（无物可点，也不占视觉重量）；加载中
        // 不当作空，读取失败如实出行内错误条。
        ...widget.memberSchemes.when(
          data: (schemes) => schemes.isEmpty
              ? const <Widget>[]
              : <Widget>[
                  Text('组员方案', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _MySchemeRow(
                    onTap: () => widget.onOpenScheme(const MySchemeOpen()),
                  ),
                  for (final scheme in schemes)
                    _MemberSchemeRow(
                      scheme: scheme,
                      onOpen: () => widget.onOpenScheme(
                        MemberSchemeOpen(scheme.schemeId),
                      ),
                      onDelete: () => widget.onRemoveScheme(scheme),
                    ),
                ],
          loading: () => const <Widget>[],
          error: (_, _) => [
            Card(
              key: const Key('dance_scheme_error'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '组员方案读取失败',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        distribution.when(
          data: _distributionCard,
          loading: () => const _DistributionNote('练习分布加载中…'),
          error: (_, _) => const _DistributionNote('练习分布读取失败'),
        ),
        const SizedBox(height: 16),
        // 计划区：DDL 编辑与清除、随舞曲库 / 复习提醒开关、准备清单与
        // 落档展示。收在页尾，不挤首屏总览。
        DancePlanSection(videoId: dance.videoId),
      ],
    );
  }

  /// 分布图卡：范围筛选与逐段练习值一次装配（`buildPracticeDistributionView`
  /// 同一次取钟），页面只渲染。
  Widget _distributionCard(PracticeDistributionInput source) {
    final dance = widget.dance;
    final view = buildPracticeDistributionView(
      source: source,
      range: _range,
      now: DateTime.now(),
    );
    return PracticeDistributionCard(
      buckets: view.distribution.buckets,
      metric: _metric,
      range: _range,
      beatGridNotReady: view.distribution.beatGridNotReady,
      // 熟练度色带：段几何取当前分段线、档位取逐段详情（缺项未练）；
      // 色带不随纵轴与范围切换变化。
      segments: source.segments,
      masteries: {
        for (final segment in dance.segments) segment.order: segment.mastery,
      },
      segmentPractices: view.segmentPractices,
      // 熟练度菜单按钮：单段就地改档；选中段收进卡片内部的段级选中态。
      onSegmentMasteryChanged: widget.onSegmentMasteryChanged,
      // 一键完全掌握：全部段置最高档；无分段线 = 无作用对象，本入口置灰
      // 不可点且静默。点过之后出撤销入口（页面内快照，不入标注编辑历史）。
      actions: Row(
        children: [
          FilledButton.icon(
            key: const Key('dance_detail_master_all'),
            onPressed: dance.segments.isEmpty ? null : widget.onMarkAllMastered,
            icon: const Icon(Icons.done_all, size: 18),
            label: const Text('一键完全掌握'),
          ),
          if (widget.canUndoMarkAllMastered) ...[
            const SizedBox(width: 8),
            TextButton(
              key: const Key('dance_detail_master_all_undo'),
              onPressed: widget.onUndoMarkAllMastered,
              child: const Text('撤销'),
            ),
          ],
        ],
      ),
      // 换纵轴不换横轴时刻：曲线就地按新口径重画。
      onMetricChanged: (metric) => setState(() => _metric = metric),
      onRangeChanged: (range) => setState(() => _range = range),
    );
  }
}

/// 分布读面的加载 / 失败位（读的是同一份舞文档，正常一闪而过）。
class _DistributionNote extends StatelessWidget {
  const _DistributionNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(padding: const EdgeInsets.all(16), child: Text(text)),
  );
}

/// 详情横幅高度（逻辑像素）：固定横条，不随封面比例与设备宽度变。
///
/// 「约 16:9 高」按常见手机内容宽（360–430dp 屏幕 → 328–398dp 内容宽）的
/// 16:9 中位值取整——该带宽对应 184–224，取 200；宽屏下更扁，且任何视口下
/// 高度都受限——总览与「打开续播」留在首屏。
const double _coverBannerHeight = 200;

/// 详情顶部封面横幅：固定高度横条 + 同一张封面图
/// **中心裁切**（`BoxFit.cover`，默认居中对齐）——与卡片按图片自身比例
/// 显示不同，这里首屏要留给总览与主按钮。封面缓存未就绪、缓存引用取不到
/// 或图片读取失败时一律出占位图，详情其余区块照常。
class _CoverBanner extends ConsumerWidget {
  const _CoverBanner({required this.dance});

  final DanceSnapshot dance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(coverCacheProvider).asData?.value;
    return SizedBox(
      key: const Key('dance_detail_cover_banner'),
      height: _coverBannerHeight,
      width: double.infinity,
      child: !dance.coverReady || cache == null
          ? const CoverPlaceholder(key: Key('dance_detail_cover_placeholder'))
          : FutureBuilder<File>(
              future: cache.fileFor(dance.videoId),
              builder: (context, snapshot) {
                final file = snapshot.data;
                if (file == null) {
                  return const CoverPlaceholder(
                    key: Key('dance_detail_cover_placeholder'),
                  );
                }
                return Image.file(
                  file,
                  key: const Key('dance_detail_cover_image'),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const CoverPlaceholder(
                    key: Key('dance_detail_cover_placeholder'),
                  ),
                );
              },
            ),
    );
  }
}

/// 「我的标注」行：方案区里唯一的可写入口，点击即以我的方案进入播放。
class _MySchemeRow extends StatelessWidget {
  const _MySchemeRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('scheme_open_mine'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(title: const Text('我的标注'), onTap: onTap),
    );
  }
}

/// 组员方案行：组员名、来源（发送方的方案名）、导入时间与那一次的熟练度
/// 快照；行主体点击即以这一份方案进入播放（只读），行尾一枚删除（确认后
/// 只删这一条）。
class _MemberSchemeRow extends StatelessWidget {
  const _MemberSchemeRow({
    required this.scheme,
    required this.onOpen,
    required this.onDelete,
  });

  final MemberSchemeRecord scheme;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final member = memberDisplayName(scheme);
    final id = scheme.schemeId;
    return Card(
      key: Key('dance_scheme_row_$id'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                key: Key('dance_scheme_open_$id'),
                onTap: onOpen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KeyedSubtree(
                      key: Key('dance_scheme_member_$id'),
                      child: Text(
                        '$member的方案',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (scheme.schemeName.isNotEmpty)
                      KeyedSubtree(
                        key: Key('dance_scheme_source_$id'),
                        child: Text(
                          '来源 ${scheme.schemeName}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    KeyedSubtree(
                      key: Key('dance_scheme_time_$id'),
                      child: Text(
                        '导入 ${dayLabel(scheme.importedAt, now: DateTime.now())}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    KeyedSubtree(
                      key: Key('dance_scheme_mastery_$id'),
                      child: Text(
                        _masterySnapshotText(scheme.mastery),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              key: Key('dance_scheme_delete_$id'),
              tooltip: '删除这个方案',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// 组员名展示值：缺署名回落「未署名」（行标题与删除确认弹窗共用一处）。
String memberDisplayName(MemberSchemeRecord scheme) {
  final name = scheme.memberName.trim();
  return name.isEmpty ? '未署名' : name;
}

/// 熟练度快照文案：按档位计数、高档在前；未随包（或无一有效档）如实说明。
String _masterySnapshotText(Map<int, int>? mastery) {
  if (mastery == null) return '熟练度快照 未随包';
  final counts = <int, int>{};
  for (final value in mastery.values) {
    if (value >= 0 && value < LearningMastery.values.length) {
      counts[value] = (counts[value] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) return '熟练度快照 未随包';
  final parts = [
    for (final level in LearningMastery.values.reversed)
      if (counts.containsKey(level.index))
        '${learningMasteryLabel(level)}×${counts[level.index]}',
  ];
  return '熟练度快照 ${parts.join(' · ')}';
}

/// 总览一行：左标签 + 右值（值按 [valueKey] 供测试与将来操作落点定位）。
class _OverviewRow extends StatelessWidget {
  const _OverviewRow({
    required this.label,
    required this.valueKey,
    required this.value,
  });

  final String label;
  final String valueKey;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          KeyedSubtree(key: Key(valueKey), child: value),
        ],
      ),
    );
  }
}
