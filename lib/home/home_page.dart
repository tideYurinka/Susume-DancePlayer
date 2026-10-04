import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../about/about_page.dart';
import '../core/text_extent.dart';
import '../dance/cover_frame_providers.dart';
import '../dance/dance_library.dart';
import '../dance/dance_library_providers.dart';
import '../dance/mastery_label.dart';
import '../help/content_registry.dart'
    show homeHelpEntryAnchorKey, importVideoAnchorKey;
import '../help/guide_anchor.dart';
import '../help/help_center_page.dart';
import '../import/import_providers.dart';
import '../import/picked_video.dart';
import '../import/video_importer.dart';
import '../player/player_page.dart';
import '../package/backup_sheet.dart';
import '../package/scheme_import_flow.dart';
import '../share_channel/share_channel.dart';
import 'cover_placeholder.dart';
import 'dance_detail_page.dart';
import 'prep_settings_page.dart';

/// 新导入等索引落盘的预算：后台 SHA-256 → 索引写通常在秒级完成。
const int _indexWriteRetryLimit = 30;
const Duration _indexWriteRetryInterval = Duration(milliseconds: 500);

/// 首页 = 舞库：两列卡片列出全部已导入的舞——大封面（底部渐变
/// 暗底上压熟练度百分比与已练遍数一行白字）、最多两行的署名标题、通栏
/// 细线、「查看详情 ›」详情行，按最近练习倒序。卡片量与排序全部来自舞库
/// 快照，本页只渲染不算术。
///
/// 点封面或标题直接打开续播，点详情行进舞详情；导入入口常驻（右下浮动钮），
/// 空库时另有空态。练完或导入落盘后回到本页重算读面，卡片字段与排序刷新。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _importing = false;
  StreamSubscription<InboundShare>? _inboundSub;

  @override
  void initState() {
    super.initState();
    final channel = ref.read(shareChannelProvider);
    // 热启动推送（onNewIntent）。
    _inboundSub = channel.inboundShares.listen(
      (share) => _onInboundShare(share, channel),
    );
    // 冷启动拉取：原生侧留存的 intent 由 Dart 取走（容量 1）。
    _pullPendingInbound(channel);
  }

  @override
  void dispose() {
    _inboundSub?.cancel();
    super.dispose();
  }

  /// 首页「⋯」动作：备份走备份面；「恢复备份」与方案导入共用同一套选包
  /// 与包形态识别分流（备份包进恢复确认面，方案包按组员方案导入）；
  /// 「详细设置」进设备级设置页；「关于」进关于页。
  Future<void> _openMoreMenu() async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        key: const Key('home_more_menu_dialog'),
        title: const Text('更多'),
        children: [
          SimpleDialogOption(
            key: const Key('backup_menu_item'),
            onPressed: () => Navigator.of(context).pop('backup'),
            child: const Text('备份'),
          ),
          SimpleDialogOption(
            key: const Key('restore_backup_menu_item'),
            onPressed: () => Navigator.of(context).pop('restore_backup'),
            child: const Text('恢复备份'),
          ),
          SimpleDialogOption(
            key: const Key('settings_menu_item'),
            onPressed: () => Navigator.of(context).pop('settings'),
            child: const Text('详细设置'),
          ),
          SimpleDialogOption(
            key: const Key('about_menu_item'),
            onPressed: () => Navigator.of(context).pop('about'),
            child: const Text('关于'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'backup':
        await showDialog<void>(
          context: context,
          builder: (_) => const BackupSheet(),
        );
      case 'settings':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PrepSettingsPage()),
        );
      case 'about':
        await Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const AboutPage()));
      case 'restore_backup':
        // 与「导入视频」、入站分享共用同一把导入互斥。
        if (_importing) return;
        setState(() => _importing = true);
        try {
          await runSchemeImportFlow(context, ref);
        } finally {
          if (mounted) setState(() => _importing = false);
        }
    }
  }

  Future<void> _pullPendingInbound(ShareChannel channel) async {
    try {
      final pending = await channel.takePendingInbound();
      if (pending != null) await _onInboundShare(pending, channel);
    } on Object {
      // 通道不在（平台侧未注册）即没有入站，拉取失败无事可做。
    }
  }

  /// 入站分享：先物化进应用目录，再走与「恢复备份」
  /// 共用的导入流程——非 Susume 包由包模块明确拒绝，不崩。
  Future<void> _onInboundShare(InboundShare share, ShareChannel channel) async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final file = await channel.materialize(share);
      if (!mounted) return;
      await runSchemeImportFlowWithFile(
        context,
        ref,
        PickedVideo(name: p.basename(file.path), sourceUri: file.uri),
      );
    } on ShareMaterializeException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importAndPlay() async {
    if (_importing) return;
    setState(() => _importing = true);
    ImportedVideo? result;
    try {
      // 选择 → 复制到私有目录 → 清理选择器缓存；取消时返回 null。
      result = await ref.read(videoImporterProvider).import();
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
      return;
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (result == null || !mounted) return;

    final video = result;
    // 首次导入的新视频：进播放器前弹歌曲命名框；
    // 既有条目/遗留旧视频不弹。
    await _openPlayer(video.uri, askNaming: video.isNewImport);
    // 导入返回时条目已落盘（见 VideoImporter）；这里仍按副本路径确认一次，
    // 条目在则重算读面让新卡出现。
    if (mounted) await _waitForImportedIndexEntry(video.uri);
  }

  /// 点卡片主体：打开该舞续播（续播位置与「从头播放？」归播放器侧）。
  Future<void> _openDance(DanceSnapshot dance) =>
      _openPlayer(File(dance.entry.filePath).uri);

  /// 打开一支舞的播放器；回到本页后重算读面（本次练习的统计已落盘）。
  Future<void> _openPlayer(Uri source, {bool askNaming = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(source: source, askNaming: askNaming),
      ),
    );
    if (!mounted) return;
    _reloadLibrary();
  }

  /// 点卡片右下角：进舞详情；回到本页后重算读面（详情页里练完的统计已落盘）。
  Future<void> _openDetail(DanceSnapshot dance) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DanceDetailPage(videoId: dance.videoId),
      ),
    );
    if (!mounted) return;
    _reloadLibrary();
  }

  /// 回到本页重算两个读面（口径在舞库模块内，本页只触发）。
  void _reloadLibrary() => invalidateDanceLibraryFrom(ref);

  /// 首页顶栏「帮助」（在「⋯」左边）：push 帮助中心。
  void _openHelpCenter() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const HelpCenterPage()));
  }

  /// 等本次导入的索引条目落盘：按副本路径轮询索引，条目出现即重算读面让
  /// 新卡出现（既有条目第一轮即命中，只多一次读）；页面不在场或预算用尽
  /// 即停，不遗留挂起工作。
  Future<void> _waitForImportedIndexEntry(Uri uri) async {
    final filePath = uri.toFilePath();
    final indexStore = ref.read(videoIndexStoreProvider);
    for (var i = 0; i < _indexWriteRetryLimit && mounted; i++) {
      final index = await indexStore.load();
      if (!mounted) return;
      if (index.findByFilePath(filePath) != null) {
        _reloadLibrary();
        return;
      }
      await Future<void>.delayed(_indexWriteRetryInterval);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(danceLibrarySnapshotProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Susume'),
        actions: [
          GuideAnchor(
            // 首启第 2 步的锚点：只包一层上报矩形，钮本身不动（定位 key 不变）。
            anchorKey: homeHelpEntryAnchorKey,
            child: IconButton(
              key: const Key('home_help_entry'),
              tooltip: '帮助',
              onPressed: _openHelpCenter,
              icon: const Icon(Icons.help_outline),
            ),
          ),
          IconButton(
            key: const Key('home_more_menu'),
            tooltip: '更多',
            onPressed: _openMoreMenu,
            icon: const Icon(Icons.more_vert),
          ),
        ],
      ),
      floatingActionButton: GuideAnchor(
        // 首启第 1 步的锚点：只包一层上报矩形，钮本身不动（定位 key 不变）。
        anchorKey: importVideoAnchorKey,
        child: FloatingActionButton.extended(
          key: const Key('import_video_button'),
          heroTag: 'import_video',
          onPressed: _importing ? null : _importAndPlay,
          icon: const Icon(Icons.video_library_outlined),
          label: const Text('导入视频'),
        ),
      ),
      body: library.when(
        // 静态加载态：读面是本地文件读，不引入持续动画。
        loading: () => const Center(child: Text('加载中…')),
        error: (_, _) => const Center(child: Text('舞库读取失败')),
        data: (snapshot) => snapshot.dances.isEmpty
            ? const _EmptyLibrary()
            : _DanceGrid(
                dances: snapshot.dances,
                onOpen: _openDance,
                onDetail: _openDetail,
              ),
      ),
    );
  }
}

/// 空库空态：说明 + 常驻导入入口（右下浮动钮）即下一步。
class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const Key('dance_library_empty'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.video_library_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text('舞库还是空的', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('导入一支舞，开始练习', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// 两列错落网格：手写瀑布流——按封面比例估算卡片
/// 高度，把下一张放进当前较矮的一列，卡片高度随比例变化；不引入第三方
/// 瀑布流包。次序即快照次序（本页不重排）。
class _DanceGrid extends StatelessWidget {
  const _DanceGrid({
    required this.dances,
    required this.onOpen,
    required this.onDetail,
  });

  final List<DanceSnapshot> dances;
  final ValueChanged<DanceSnapshot> onOpen;
  final ValueChanged<DanceSnapshot> onDetail;

  @override
  Widget build(BuildContext context) {
    // 「最近练习」相对标签的参考时刻：整屏读一次，各卡一致。
    final now = DateTime.now();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth =
            (constraints.maxWidth - _kGridGutter * 2 - _kGridSpacing) / 2;
        final (left, right) = _balanceColumns(context, dances, columnWidth);
        return SingleChildScrollView(
          key: const Key('dance_grid_scroll'),
          // 底部留给常驻导入钮，末行不被遮。
          padding: const EdgeInsets.fromLTRB(
            _kGridGutter,
            _kGridGutter,
            _kGridGutter,
            96,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _DanceColumn(
                  dances: left,
                  now: now,
                  onOpen: onOpen,
                  onDetail: onDetail,
                ),
              ),
              const SizedBox(width: _kGridSpacing),
              Expanded(
                child: _DanceColumn(
                  dances: right,
                  now: now,
                  onOpen: onOpen,
                  onDetail: onDetail,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

const double _kGridGutter = 12;
const double _kGridSpacing = 12;

/// 卡片文字区的内缩：标题与详情行左右 10（详情行右侧留 4 给箭头）。
const double _kCardTextInset = 10;

/// 卡片文字区各行的上下内缩与通栏细线厚度：估算与渲染共用同一取值。
const double _kCardRowPadding = 8;
const double _kCardDividerHeight = 1;

/// 详情行的入口文案：渲染端与高度估算共用同一取值。
const String _kDetailRowLabel = '查看详情';

/// 文本的排版高度（当前主题样式 + 可用宽度实测，最多两行——标题口径）。
double _measuredTextHeight(
  String text,
  TextStyle style,
  double maxWidth,
  TextDirection textDirection,
) => measureTextExtent(
  text,
  style,
  direction: textDirection,
  maxWidth: maxWidth,
  maxLines: 2,
).height;

/// 卡片高度估算 = 封面高度 ＋ 标题实测高度 ＋ 细线 ＋ 详情行高度：标题按
/// 当前主题与列宽实测（最多两行），不再用固定信息块常量，分列估算与实际
/// 渲染一致。
(double, double) _cardTextHeights(
  BuildContext context,
  DanceSnapshot dance,
  double columnWidth,
) {
  final textTheme = Theme.of(context).textTheme;
  final textDirection = Directionality.of(context);
  final titleHeight =
      _measuredTextHeight(
        dance.title,
        textTheme.titleSmall!,
        columnWidth - 2 * _kCardTextInset,
        textDirection,
      ) +
      2 * _kCardRowPadding;
  final detailHeight =
      _measuredTextHeight(
        _kDetailRowLabel,
        textTheme.bodySmall!,
        columnWidth - _kCardTextInset - 4,
        textDirection,
      ) +
      2 * _kCardRowPadding +
      _kCardDividerHeight;
  return (titleHeight, detailHeight);
}

/// 把卡片按估算高度放进较矮的一列；返回（左列, 右列）。
(List<DanceSnapshot>, List<DanceSnapshot>) _balanceColumns(
  BuildContext context,
  List<DanceSnapshot> dances,
  double columnWidth,
) {
  final left = <DanceSnapshot>[];
  final right = <DanceSnapshot>[];
  var leftHeight = 0.0;
  var rightHeight = 0.0;
  for (final dance in dances) {
    final (titleHeight, detailHeight) = _cardTextHeights(
      context,
      dance,
      columnWidth,
    );
    final height =
        columnWidth / dance.coverAspectRatio + titleHeight + detailHeight;
    if (leftHeight <= rightHeight) {
      left.add(dance);
      leftHeight += height + _kGridSpacing;
    } else {
      right.add(dance);
      rightHeight += height + _kGridSpacing;
    }
  }
  return (left, right);
}

/// 一列：卡片纵向堆叠。
class _DanceColumn extends StatelessWidget {
  const _DanceColumn({
    required this.dances,
    required this.now,
    required this.onOpen,
    required this.onDetail,
  });

  final List<DanceSnapshot> dances;
  final DateTime now;
  final ValueChanged<DanceSnapshot> onOpen;
  final ValueChanged<DanceSnapshot> onDetail;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, dance) in dances.indexed) ...[
          if (index > 0) const SizedBox(height: _kGridSpacing),
          _DanceCard(
            key: ValueKey('dance_card_state_${dance.videoId}'),
            dance: dance,
            now: now,
            onOpen: () => onOpen(dance),
            onDetail: () => onDetail(dance),
          ),
        ],
      ],
    );
  }
}

/// 卡片：封面（真图或 3:4 占位，底部渐变暗底压熟练度百分比与已练遍数一行
/// 白字）+ 最多两行的署名标题 + 通栏细线 + 「查看详情 ›」详情行。没标注不出
/// 百分比，无有效区间不出遍数，两项都缺时信息条整行不出现。练习总时长与最近
/// 练习不上卡片（留在舞详情总览）。
///
/// 封面**惰性生成**：卡片进入可见区才向取帧队列排队，完成后本卡自动换成真图；
/// 未就绪/失败显示占位图，导入路径不触取帧。
class _DanceCard extends ConsumerStatefulWidget {
  const _DanceCard({
    super.key,
    required this.dance,
    required this.now,
    required this.onOpen,
    required this.onDetail,
  });

  final DanceSnapshot dance;

  /// 「最近练习」相对标签（今天/昨天/日期）的参考时刻。
  final DateTime now;

  final VoidCallback onOpen;
  final VoidCallback onDetail;

  @override
  ConsumerState<_DanceCard> createState() => _DanceCardState();
}

class _DanceCardState extends ConsumerState<_DanceCard> {
  /// 本次会话内本卡取帧成功后解析出的封面（文件 + 图片自身比例）；读面未
  /// 及时刷新也先按真图与真比例渲染。
  File? _coverFile;
  double? _coverAspectRatio;

  /// 所属滚动视口；null = 不在可滚动容器内（可见性判据直接放过）。
  ScrollableState? _scrollable;

  /// 是否已入队（每卡只排一次；失败本会话不重试）。
  bool _requested = false;

  /// 封面框比例：本次取到的图片自身比例优先，否则读面给的（未就绪 = 3:4）。
  double get _aspectRatio => _coverAspectRatio ?? widget.dance.coverAspectRatio;

  bool get _ready => _coverFile != null || widget.dance.coverReady;

  @override
  void initState() {
    super.initState();
    if (widget.dance.coverReady) unawaited(_resolveCoverFile());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    _watchScroll();
  }

  @override
  void didUpdateWidget(covariant _DanceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldDance = oldWidget.dance;
    if (oldDance.coverPosition != widget.dance.coverPosition) {
      // 首线/封面位置改了：旧图作废（缓存按位置判定就绪），按新位置重排。
      _coverFile = null;
      _coverAspectRatio = null;
      _requested = false;
      if (widget.dance.coverReady) {
        unawaited(_resolveCoverFile());
      } else {
        _watchScroll();
      }
      return;
    }
    if (!oldDance.coverReady && widget.dance.coverReady && _coverFile == null) {
      unawaited(_resolveCoverFile());
    }
  }

  @override
  void dispose() {
    _scrollable?.position.removeListener(_onScroll);
    super.dispose();
  }

  /// 监听滚动并立即查一次可见性：进入可见区的那一刻才排队取帧。
  void _watchScroll() {
    final scrollable = Scrollable.maybeOf(context);
    if (!identical(scrollable, _scrollable)) {
      _scrollable?.position.removeListener(_onScroll);
      _scrollable = scrollable;
    }
    _scrollable?.position.removeListener(_onScroll);
    _scrollable?.position.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  /// 进入可见区即排队取帧（只排一次；失败本会话不重试）。
  void _onScroll() {
    if (!mounted || _requested || _ready) return;
    if (!_isVisible()) return;
    _requested = true;
    _scrollable?.position.removeListener(_onScroll);
    unawaited(_requestCover());
  }

  Future<void> _requestCover() async {
    final ready = await ref.read(coverGenerationQueueProvider).request((
      videoId: widget.dance.videoId,
      sourcePath: widget.dance.entry.filePath,
      position: widget.dance.coverPosition,
    ));
    if (!mounted || !ready) return;
    await _resolveCoverFile();
  }

  /// 取读面就绪的封面文件与图片自身比例：一次原子读，未就绪即不动。
  Future<void> _resolveCoverFile() async {
    final cache = await ref.read(coverCacheProvider.future);
    final ready = await cache.readyCover(
      widget.dance.videoId,
      widget.dance.coverPosition,
    );
    if (!mounted || ready == null) return;
    setState(() {
      _coverFile = ready.file;
      _coverAspectRatio = ready.aspectRatio;
    });
  }

  /// 卡片是否与滚动视口相交（可见优先的唯一判据）。
  bool _isVisible() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return false;
    final viewport = _scrollable?.context.findRenderObject() as RenderBox?;
    // 不在滚动容器内（无视口可裁）：按可见处理。
    if (viewport == null || !viewport.hasSize) return true;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    final viewTop = viewport.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + viewport.size.height;
    return bottom > viewTop && top < viewBottom;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dance = widget.dance;
    // 单枚角标：逾期 > 临期 > 完全掌握勾。
    final badge = danceCardBadgeOf(dance, now: widget.now);
    return Card(
      key: Key('dance_card_${dance.videoId}'),
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面 + 标题：打开这支舞续播。
          InkWell(
            key: Key('dance_card_open_${dance.videoId}'),
            onTap: widget.onOpen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(badge),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: _kCardTextInset,
                    vertical: _kCardRowPadding,
                  ),
                  child: Text(
                    dance.title,
                    key: Key('dance_card_title_${dance.videoId}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
          ),
          // 通栏细线：上面是这支舞、下面是它的详情入口。
          Container(
            height: _kCardDividerHeight,
            color: theme.dividerColor.withValues(alpha: 0.5),
          ),
          // 详情行：整行可点 → 舞详情（不抢主体那一次点按）。
          InkWell(
            key: Key('dance_card_detail_${dance.videoId}'),
            onTap: widget.onDetail,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                _kCardTextInset,
                _kCardRowPadding,
                4,
                _kCardRowPadding,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _kDetailRowLabel,
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 封面区：按图片自身比例（竖屏 3:4 / 横屏 4:3）；未就绪按 3:4 占位。
  /// 底部渐变暗底（黑 0 → 约 0.65，覆盖下方约一半）上压左下角一行白字信息
  /// 条（熟练度百分比 · 已练遍数）；右上角一枚角标，单枚。
  Widget _cover(DanceCardBadge? badge) {
    final theme = Theme.of(context);
    final videoId = widget.dance.videoId;
    final placeholder = CoverPlaceholder(
      key: Key('dance_cover_placeholder_$videoId'),
    );
    final file = _coverFile;
    final percent = widget.dance.masteryPercent;
    final practiceCount = widget.dance.averagePracticeCount;
    final infoStyle = theme.textTheme.bodySmall!.copyWith(color: Colors.white);
    // 信息条：百分比与已练遍数各段缺省即不出现，两段都缺时整行不渲染，分隔符
    // 只在两段同现时出现。
    final info = <Widget>[
      if (percent != null)
        Text(
          '${percent.round()}%',
          key: Key('dance_card_percent_$videoId'),
          style: infoStyle,
        ),
      if (percent != null && practiceCount != null) ...[
        const SizedBox(width: 4),
        Text('·', style: infoStyle),
        const SizedBox(width: 4),
      ],
      if (practiceCount != null)
        Flexible(
          child: Text(
            '已练 ${averagePracticeCountText(practiceCount)}',
            key: Key('dance_card_average_$videoId'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: infoStyle,
          ),
        ),
    ];
    return AspectRatio(
      key: Key('dance_cover_$videoId'),
      aspectRatio: _aspectRatio,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final coverHeight = constraints.maxWidth / _aspectRatio;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (file == null)
                placeholder
              else
                Image.file(
                  file,
                  key: Key('dance_cover_image_$videoId'),
                  fit: BoxFit.cover,
                  // 图片读不出（被删/损坏）时如实退回占位图，不影响其余区块。
                  errorBuilder: (_, _, _) => placeholder,
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  key: Key('dance_cover_gradient_$videoId'),
                  height: coverHeight * 0.5,
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.65),
                      ],
                    ),
                  ),
                  child: info.isEmpty
                      ? null
                      : Row(
                          key: Key('dance_card_cover_info_$videoId'),
                          children: info,
                        ),
                ),
              ),
              if (badge != null)
                Positioned(
                  top: 6,
                  right: 6,
                  child: _BadgeMark(badge: badge, videoId: videoId),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// 卡片角标：单枚、克制——逾期红标、临期标、完全掌握勾。取值与
/// 优先级来自舞库纯件 [danceCardBadgeOf]，本件只渲染。
class _BadgeMark extends StatelessWidget {
  const _BadgeMark({required this.badge, required this.videoId});

  final DanceCardBadge badge;
  final String videoId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (badge) {
      DanceCardBadge.overdue => Container(
        key: Key('dance_card_badge_overdue_$videoId'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.error,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '逾期',
          style: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onError,
          ),
        ),
      ),
      DanceCardBadge.nearDeadline => Container(
        key: Key('dance_card_badge_near_$videoId'),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiary,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '临期',
          style: theme.textTheme.labelSmall!.copyWith(
            color: theme.colorScheme.onTertiary,
          ),
        ),
      ),
      // 完全掌握真值配可读标签：角标只有一枚勾，读屏读不出。
      DanceCardBadge.mastered => Semantics(
        container: true,
        excludeSemantics: true,
        label: kMasteredLabel,
        child: Icon(
          Icons.check_circle,
          key: Key('dance_card_badge_mastered_$videoId'),
          size: 20,
          color: theme.colorScheme.primary,
        ),
      ),
    };
  }
}
