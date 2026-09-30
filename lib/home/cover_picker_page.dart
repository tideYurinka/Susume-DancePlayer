import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/annotation_timeline.dart';
import '../core/hit_target.dart' show kHitTargetMinSize;
import '../core/playback/playback_engine.dart';
import '../core/playback/playback_engine_providers.dart';
import '../dance/cover_frame_providers.dart';
import '../dance/dance_library_providers.dart';
import '../core/frame_time.dart';
import '../core/playback/seek_submitter.dart';
import '../player/scrub_session.dart';

/// 换封面选帧界面：视频面 + 一条覆盖整支舞的时间轴与
/// 预览线 + 当前预览线时刻 + 「用这一帧」/「恢复为默认」。不做逐帧步进、
/// 不做时间轴缩放。
///
/// 预览**复用同一条播放内核**（应用内单例，[playbackEngineProvider]）与既有
/// 拖动链路（[ScrubSession] + [SeekSubmitter]）：进入时打开并暂停，拖动即
/// 「在播先暂停定格 → 逐帧 seek 入队」，引擎内按 seek 时间线自动识别拖动
/// 突发（关键帧快速寻址闭环派发 + 静默 250ms 后单发精确 seek
/// 收尾），因此松手静默后画面帧级准确。界面只做打开 / 暂停 / seek，
/// **不 dispose 内核**、不新建解码实例、不使用播放器截图。
///
/// 确认按预览线时刻用 ffmpeg 取帧（与默认封面同一条命令路径：写公开标记
/// 文件封面位置字段的原子读改写 → 使该舞封面缓存失效 → 按新位置重新生成），
/// 随后作废舞库读面，详情与首页随即显示新封面；「恢复为默认」清空字段、
/// 按「跟随首线」的有效位置重新生成；返回或取消不写入任何字段。
class CoverPickerPage extends ConsumerStatefulWidget {
  const CoverPickerPage({
    super.key,
    required this.videoId,
    required this.sourcePath,
    required this.initialPosition,
  });

  /// 舞身份（内容寻址哈希）。
  final String videoId;

  /// 源视频文件路径：内核打开（转 file URI）与取帧命令共用同一份事实。
  final String sourcePath;

  /// 进入时预览线位置 = 该舞当前封面位置（读面 `coverPosition`）。
  final Duration initialPosition;

  @override
  ConsumerState<CoverPickerPage> createState() => _CoverPickerPageState();
}

class _CoverPickerPageState extends ConsumerState<CoverPickerPage> {
  /// 应用内单例内核：只打开 / 暂停 / seek，生命周期归 ProviderScope。
  late final PlaybackEngine _engine = ref.read(playbackEngineProvider);

  /// 当前预览线时刻（显示位与提交目标同源，不读引擎实际 position——串行
  /// latest-wins seek 期间引擎位置会滞后）。
  final ValueNotifier<Duration> _preview = ValueNotifier(Duration.zero);

  /// seek 唯一提交口（与播放页同一条链路：player 面不节流、无窗口跟随）。
  late final SeekSubmitter _seeks = SeekSubmitter(
    engineSeek: _engine.seek,
    total: () => _engine.duration,
    // 选帧界面不建标注会话：时间线只用于 seek 落点，清循环无对象。
    timeline: () =>
        AnnotationTimeline.wholeVideo(_engine.duration ?? Duration.zero),
    clearLoops: (_, _) {},
  );

  /// 定格预览会话：在播起手先 pause（pause 先于任何 seek）、基准 = 定格点
  /// 快照、逐帧落点经 [_seeks]、松手恢复手势前播放态。
  late final ScrubSession _scrub = ScrubSession(
    seek: _seeks,
    pause: _engine.pause,
    play: _engine.play,
    isPlaying: () => _engine.isPlaying,
    position: () => _engine.position,
    indicator: _preview,
    requireKnownDuration: true,
  );

  /// 当前视频总时长（打开后可用；未知为零 → 拖动静默不起会话）。
  ///
  /// 内核契约 P2：`open` 返回后 [PlaybackEngine.duration] 应可用；异常源
  /// 超时带 null 返回时本界面优雅降级——时间轴留作静态展示、拖不动，仍可
  /// 返回。内核对已打开源的时长不再变化，故打开时取一次即稳定。
  Duration _total = Duration.zero;

  /// 本次拖动累计像素位移与上一次换算出的累计时长：位移**整段**换算一次、
  /// 逐帧只提交增量，避免按帧取整的累积漂移（落点 = 手指位移，不随事件
  /// 拆分漂移）。
  double _dragPx = 0;
  Duration _draggedBy = Duration.zero;

  /// 提交中防重复点击（写盘 + 取帧期间再点不重入）。
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _preview.value = widget.initialPosition;
    _openSource();
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  /// 进入时打开并暂停：预览是定格态，画面落在当前封面位置那一帧。
  ///
  /// 内核是应用内单例：这里只 open / pause / seek，**不 dispose**（生命周期
  /// 归 ProviderScope），也不新建解码实例。
  Future<void> _openSource() async {
    try {
      await _engine.open(File(widget.sourcePath).uri);
      if (!mounted) return;
      await _engine.pause();
      _total = _engine.duration ?? Duration.zero;
      final initial = _clamped(widget.initialPosition);
      await _engine.seek(initial);
      if (!mounted) return;
      setState(() {
        _preview.value = initial;
      });
    } on Object {
      // 坏源打开失败：时间轴保持不可拖动，界面照常可见（可返回）。
      if (mounted) setState(() => _total = Duration.zero);
    }
  }

  /// 钳制到 `[0, 总时长]`（总时长未知时只钳下界）。
  Duration _clamped(Duration target) {
    if (target < Duration.zero) return Duration.zero;
    if (_total > Duration.zero && target > _total) return _total;
    return target;
  }

  /// 时间轴拖动帧：本帧位移按整条时间轴换算为时长增量（`px × 总时长 ÷
  /// 轴宽`），经既有拖动链路落点。与 [_CoverTimeline] 摆放预览线用的是
  /// 同一个轴宽分母，故手指落点与预览线位置互为精确逆映射。
  ///
  /// 累计量在 begin **之前**复位：begin 在播分支有 await，复位放在其后会
  /// 抹掉 await 窗口内已到达的后续帧。
  Future<void> _onTimelineDrag(double deltaPx, double width) async {
    if (_total <= Duration.zero || width <= 0) return;
    if (!_scrub.isActive) {
      _dragPx = 0;
      _draggedBy = Duration.zero;
      await _scrub.begin();
    }
    if (!_scrub.isActive) return;
    _dragPx += deltaPx;
    final cumulative = Duration(
      milliseconds: (_dragPx * _total.inMilliseconds / width).round(),
    );
    _scrub.moveBy(cumulative - _draggedBy);
    _draggedBy = cumulative;
  }

  Future<void> _onTimelineDragEnd() => _scrub.end();

  /// 时间轴点按定位：与拖动同一个换算分母
  /// （`fraction × 总时长`）把落点钳到 `[0, 总时长]` 后 seek，并同步预览线
  /// 时刻。除拖动之外的替代路径，不经过拖动会话。
  void _onTimelineTap(double fraction) {
    if (_total <= Duration.zero) return;
    final target = Duration(
      milliseconds: (fraction.clamp(0.0, 1.0) * _total.inMilliseconds).round(),
    );
    final clamped = _clamped(target);
    _preview.value = clamped;
    unawaited(_engine.seek(clamped));
  }

  /// 「用这一帧」：按当前预览线时刻写入封面位置。
  Future<void> _confirmFrame() => _apply(
    () => ref.read(danceLibraryWritesProvider).setCoverPosition(
      videoId: widget.videoId,
      positionMs: _preview.value.inMilliseconds,
    ),
  );

  /// 「恢复为默认」：清空封面位置字段（回到跟随首线），按写路径回答的生效
  /// 首线位置重新生成封面。
  Future<void> _resetToDefault() => _apply(
    () => ref.read(danceLibraryWritesProvider).setCoverPosition(
      videoId: widget.videoId,
      positionMs: null,
    ),
  );

  /// 一次封面提交：先写（[write] 返回写后生效的封面位置毫秒，null = 写未
  /// 成立、文件零副作用），再使该舞封面缓存失效 → 按新位置重新生成 →
  /// 清掉同名路径已解码的旧图 → 作废舞库读面（详情与首页随即显示新封面）。
  ///
  /// 写未成立只如实告知，不碰缓存、不重新生成。提交中不重入（防双点重复
  /// 写与重复 pop）。
  Future<void> _apply(Future<int?> Function() write) async {
    if (_committing) return;
    _committing = true;
    try {
      final positionMs = await write();
      if (!mounted) return;
      if (positionMs == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('换封面失败')));
        }
        return;
      }
      final position = Duration(milliseconds: positionMs);
      final cache = await ref.read(coverCacheProvider.future);
      final generator = await ref.read(coverGeneratorProvider.future);
      await cache.deleteFor(widget.videoId);
      final generated = await generator.generate(
        videoId: widget.videoId,
        sourcePath: widget.sourcePath,
        position: position,
      );
      await FileImage(await cache.fileFor(widget.videoId)).evict();
      if (!mounted) return;
      invalidateDanceLibraryFrom(ref);
      if (!generated) {
        // 位置已落盘但这一帧取不出来（或本会话该舞已失败过、不再重试）：
        // 详情与首页按占位图显示，如实告知，不假装封面已换好。
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('封面生成失败')));
      }
      Navigator.of(context).pop();
    } finally {
      _committing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fps = _engine.videoFps ?? kDefaultVideoFps;
    return Scaffold(
      key: const Key('cover_picker_page'),
      appBar: AppBar(title: const Text('换封面')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: Center(child: _engine.buildVideoSurface())),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ValueListenableBuilder<Duration>(
                      valueListenable: _preview,
                      builder: (_, value, _) => Text(
                        formatFrameTime(value, fps: fps),
                        key: const Key('cover_picker_time'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _CoverTimeline(
                    total: _total,
                    preview: _preview,
                    onDrag: _onTimelineDrag,
                    onDragEnd: _onTimelineDragEnd,
                    onTap: _onTimelineTap,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          key: const Key('cover_picker_reset'),
                          onPressed: _resetToDefault,
                          child: const Text('恢复为默认'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          key: const Key('cover_picker_confirm'),
                          onPressed: _confirmFrame,
                          child: const Text('用这一帧'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 预览线宽度（逻辑像素）。
const double _playheadWidth = 2;

/// 整支舞时间轴：一条轨道 + 可在其上水平拖动的预览线。预览线位置与当前
/// 预览时刻同源（[ValueListenable]），拖动只上报像素位移与轴宽，换算留在
/// 宿主（唯一换算点）；点按同样按轴宽换算成比例交给宿主（替代路径，见）。
///
/// 点按用 [Listener] 自己判（按下→抬起位移不超过触摸 slop），**不**在同一
/// 手势竞技场里加 tap 识别器——否则拖动的首次位移会被竞技场裁决吃掉，
/// 破坏既有的「起手先暂停定格」手感。
class _CoverTimeline extends StatefulWidget {
  const _CoverTimeline({
    required this.total,
    required this.preview,
    required this.onDrag,
    required this.onDragEnd,
    required this.onTap,
  });

  final Duration total;
  final ValueListenable<Duration> preview;
  final void Function(double deltaPx, double width) onDrag;
  final VoidCallback onDragEnd;

  /// 点按落点（0–1 比例）。
  final ValueChanged<double> onTap;

  @override
  State<_CoverTimeline> createState() => _CoverTimelineState();
}

class _CoverTimelineState extends State<_CoverTimeline> {
  Offset? _downPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      // 高度取命中盒下限：44 → 48 只改可点纵向
      // 容量，轨道 4 与预览线 22 的视觉尺寸不变。
      height: kHitTargetMinSize,
      key: const Key('cover_picker_timeline'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final travel = (width - _playheadWidth).clamp(0.0, double.infinity);
          return Listener(
            onPointerDown: (event) => _downPosition = event.localPosition,
            onPointerUp: (event) {
              final down = _downPosition;
              _downPosition = null;
              if (down == null || width <= 0) return;
              if ((event.localPosition - down).distance > kTouchSlop) return;
              widget.onTap(event.localPosition.dx / width);
            },
            onPointerCancel: (_) => _downPosition = null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) =>
                  widget.onDrag(details.delta.dx, width),
              onHorizontalDragEnd: (_) => widget.onDragEnd(),
              onHorizontalDragCancel: widget.onDragEnd,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  ValueListenableBuilder<Duration>(
                    valueListenable: widget.preview,
                    builder: (_, value, _) {
                      final fraction = widget.total <= Duration.zero
                          ? 0.0
                          : (value.inMilliseconds / widget.total.inMilliseconds)
                                .clamp(0.0, 1.0);
                      return Positioned(
                        // 预览线中心对准 `fraction × 轴宽`（与拖动换算同一分母），
                        // 首尾各钳到轴内，不与手指错开半个线宽。
                        left: (fraction * width - _playheadWidth / 2).clamp(
                          0.0,
                          travel,
                        ),
                        child: Container(
                          key: const Key('cover_picker_playhead'),
                          width: _playheadWidth,
                          height: 22,
                          color: theme.colorScheme.primary,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
