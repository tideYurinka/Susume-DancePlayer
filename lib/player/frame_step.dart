part of 'control_layer.dart';

/// 帧步进簇：单帧时长换算、选中目标（半拍线 / 首尾端标）格点跳步、
/// 无选中预览 ±1 帧与长按连续步进的按钮件。入口动作的三态语义见
/// `ControlLayerState._stepFrame`。

/// 格点跳步轻震注入点：左右钮格点跳步实际生效后的单次轻触反馈。
/// 默认系统轻触反馈（[HapticFeedback.selectionClick]，与轨道带预览磁吸
/// 同款）；widget 测试经 override 注入记录器断言。
final gridStepHapticProvider = Provider<VoidCallback>(
  (ref) => HapticFeedback.selectionClick,
);

extension _ControlLayerFrameStep on ControlLayerState {
  // ---- 帧步进 ----

  /// 单帧时长：引擎 demux-fps 优先，取不到回退 30fps（帧时长换算）。
  Duration _frameDuration() => frameDurationFor(
    ref.read(playbackEngineProvider).videoFps ?? kDefaultVideoFps,
  );

  /// 带方向的单帧位移（Duration 不支持 int × Duration 运算符）。
  Duration _step(int direction, Duration frame) =>
      direction < 0 ? -frame : frame;

  /// 帧步进 / 拍点跳步入口（[direction] = -1 左移 / +1 右移）。
  ///
  /// 目标优先级 = 当前选中的半拍线 → 当前选中的首/尾线端标
  /// （带外选中源）→ 无选中则预览进度（在播先暂停、定格逐帧 seek）。
  /// 分段线不在目标链中（分段线只落八拍点，不支持逐帧微调）。
  ///
  /// 步进三态语义（强制对齐，无「吸附开关」分支）：选中半拍线 =
  /// 该方向**相邻半拍格点**（相邻拍点中点，严格越过当前位置；
  /// 原始目标直接提交，模块提交时落点解析幂等）；选中首/尾
  /// 端标 = 网格覆盖区内该方向**相邻真实拍点**；无选中 = 预览 ±1 帧（含
  /// 长按连续）。端标步进保留「步进/方向换算等读取侧纯
  /// 函数 helper 留在原纯域」授权的读取换算（覆盖语境 + 相邻拍点方向
  /// helper），落点解析权威在模块：提交经 SetVideoRange 模块
  /// 内吸附 + 归一化钳制。跳步单击即跳、单步入史、轻震一次、不做长按
  /// 连续（按钮侧按上下文关闭长按重复）；无相邻拍点 / 越邻 / 触界 / 区
  /// 间外 = 模块既有 no-op（不提交、不入史、不轻震）。锁定分段下目标为
  /// 线/端标 → 提交被模块门禁拒绝（EditLocked = 无动作 + 提示；预览进度
  /// 步进不受锁）。
  void _stepFrame(int direction) {
    final error = ref.read(beatGridProvider).isSecondsFallback;
    final frame = _step(direction, _frameDuration());
    // 端标拍点跳步的前提：有界真实网格且当前位置在覆盖区内；否则 ±1 帧
    // 自由回退（半拍格点派生在占位网格上同样有效，无需有界前提）。
    final halfBeatIndex = ref.read(selectedHalfBeatLineIndexProvider);
    if (halfBeatIndex != null) {
      final index = halfBeatIndex;
      final timeline = ref.read(annotationTimelineProvider);
      final current = timeline.halfBeatLines[index].position;
      final grid = ref.read(beatGridProvider);
      _stepSelectedEdit(
        current: current,
        gridUsable: !error,
        adjacent: error
            ? null
            : (direction < 0
                  ? previousHalfBeatPoint(current, grid: grid)
                  : nextHalfBeatPoint(current, grid: grid)),
        frame: frame,
        submit: (target) => ref
            .read(annotationEditorProvider)
            .submit(MoveHalfBeatLine(index: index, to: target))
            .applied,
        readAfter: () =>
            ref.read(annotationTimelineProvider).halfBeatLines[index].position,
      );
      return;
    }
    final boundary = ref.read(selectedVideoRangeBoundaryProvider);
    if (boundary != null) {
      final timeline = ref.read(annotationTimelineProvider);
      final current = boundary == VideoRangeBoundary.start
          ? timeline.rangeStart
          : timeline.rangeEnd;
      final grid = ref.read(beatGridProvider);
      // 落点解析权威在模块（SetVideoRange 提交时吸附 + 归一化
      // 钳制），widget 只保留「步进/方向换算读取侧纯函数 helper 留在
      // 原纯域」授权的读取换算：有界真实网格覆盖区内取该方向相邻真实拍点
      // 为请求位置（模块对拍点目标幂等），覆盖区外/异常态无相邻语境 → 原
      // 样 ±1 帧自由步进（模块落点解析对覆盖外请求自由直通）。
      final inCoverage =
          grid.hasRealBeats &&
          current >= grid.beatTime(0) &&
          current <= grid.beatTime(grid.lastBeatIndex!);
      _stepSelectedEdit(
        current: current,
        gridUsable: inCoverage,
        adjacent: !inCoverage
            ? null
            : (direction < 0
                  ? previousBeatPoint(current, grid: grid)
                  : nextBeatPoint(current, grid: grid)),
        frame: frame,
        submit: (target) => ref
            .read(annotationEditorProvider)
            .submit(
              boundary == VideoRangeBoundary.start
                  ? SetVideoRange(start: target)
                  : SetVideoRange(end: target),
            )
            .applied,
        readAfter: () {
          final after = ref.read(annotationTimelineProvider);
          return boundary == VideoRangeBoundary.start
              ? after.rangeStart
              : after.rangeEnd;
        },
      );
      return;
    }
    unawaited(_stepPreviewBy(frame));
  }

  /// 选中目标（半拍线 / 首尾端标）步进的共同骨架：格点可用时取该方向相邻
  /// 格点，不可用（异常网格 / 覆盖区外）回退 [frame] 自由微调；格点可用却
  /// 已无相邻格点（首拍左邻 / 末拍右邻出界）= no-op 不提交（模块对到达请求
  /// 的落点解析幂等）。提交落定才轻震（自由微调不震）、才同步播放头；
  /// [readAfter] 读提交后的目标位置。
  void _stepSelectedEdit({
    required Duration current,
    required bool gridUsable,
    required Duration? adjacent,
    required Duration frame,
    required bool Function(Duration target) submit,
    required Duration Function() readAfter,
  }) {
    if (gridUsable && adjacent == null) return;
    if (!submit(adjacent ?? current + frame)) return;
    if (gridUsable) ref.read(gridStepHapticProvider)();
    unawaited(_syncPlayheadAfterStep(readAfter()));
  }

  /// 帧步进同步播放头：线/端标被步进移动后，把播放头 seek 到该
  /// 线新位置并保持暂停定格预览该帧（在播先暂停、pause 先于 seek，不自动
  /// 续播）；与拖线预览「松手回原播放位」语义区分（仅帧步进采用同步）。
  /// 经 seek 唯一提交口提交：串行入队（latest-wins，连续步进即
  /// 连续实时预览调整处的画面）、预览线显示值/可视窗口随动、目标越出生效
  /// 循环范围取消激活（与其他 seek 入口同一判定）；不清选中（目标即选中
  /// 线本身，先例）；不入撤销（非时间线编辑）。
  Future<void> _syncPlayheadAfterStep(Duration target) async {
    final engine = ref.read(playbackEngineProvider);
    final total = engine.duration;
    if (total == null || total <= Duration.zero) return;
    if (engine.isPlaying) {
      await engine.pause();
    }
    _session.submit(target);
  }

  /// 预览进度帧步进（无选中目标时）：在播先暂停定格（pause 先于 seek，
  /// 同一 FakeEngine 断言顺序）；带外选中清除（无选中时帧步进
  /// 属「其它操作」）；经 seek 唯一提交口提交：钳制到
  /// [0, 总时长]、越出循环范围取消激活、串行入队并驱动带内预览线与可视
  /// 窗口。不入撤销（非时间线编辑）。
  Future<void> _stepPreviewBy(Duration delta) async {
    final engine = ref.read(playbackEngineProvider);
    final total = engine.duration;
    if (total == null || total <= Duration.zero) return;
    ref.read(annotationSelectionDomainProvider).clear();
    if (engine.isPlaying) {
      await engine.pause();
    }
    _session.submit(engine.position + delta);
  }

  /// 选中目标在场（目标链为半拍线/端标）：选中半拍线或
  /// 首/尾端标时长按连续关闭；无选中预览步进保持长按连续（文案已
  /// 固定，本态不再切换按钮文案）。
  bool get _stepTargetSelected {
    return ref.watch(selectedHalfBeatLineIndexProvider) != null ||
        ref.watch(selectedVideoRangeBoundaryProvider) != null;
  }
}

/// 帧步进按钮：短按单步（按下即触发，反馈即时）；
/// 按住约 0.4s 后进入重复模式自动连续步进——每约 0.15s 一次并可随按住
/// 时长渐快（下限封顶、可随时中断），松开/取消即停且不补触发额外单步。
/// 每一步沿用 [_stepFrame] 既有语义（目标优先级/钳制/撤销/锁定裁决/播放
/// 头同步），本组件只负责重复节奏。
class _FrameStepButton extends StatefulWidget {
  const _FrameStepButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onStep,
    this.holdToRepeat = true,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onStep;

  /// 按住是否连续步进（长按连续：格点跳步上下文关闭——按住
  /// 只走按下那一步，不埋重复定时器）。
  final bool holdToRepeat;

  @override
  State<_FrameStepButton> createState() => _FrameStepButtonState();
}

class _FrameStepButtonState extends State<_FrameStepButton> {
  /// 长按启动阈值：按住超过此时长进入重复模式。
  static const _holdDelay = Duration(milliseconds: 400);

  /// 重复起始间隔与渐快参数：每触发一次递减，直到下限（可中断、有上限）。
  static const _initialInterval = Duration(milliseconds: 150);
  static const _acceleration = Duration(milliseconds: 15);
  static const _minInterval = Duration(milliseconds: 50);

  Timer? _holdTimer;
  Timer? _repeatTimer;
  Duration _interval = _initialInterval;
  bool _repeating = false;

  void _onDown() {
    widget.onStep();
    if (!widget.holdToRepeat) return;
    _holdTimer = Timer(_holdDelay, () {
      _repeating = true;
      _fireRepeat();
    });
  }

  void _fireRepeat() {
    if (!_repeating) return;
    widget.onStep();
    if (_interval > _minInterval) {
      final faster = _interval - _acceleration;
      _interval = faster < _minInterval ? _minInterval : faster;
    }
    _repeatTimer = Timer(_interval, _fireRepeat);
  }

  void _stop() {
    _repeating = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _repeatTimer?.cancel();
    _repeatTimer = null;
    _interval = _initialInterval;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      // 原为 IconButton（改自绘以挂指针级长按重复）：补回按钮语义并挂
      // 无障碍激活动作——指针长按走 [Listener]，读屏双击走这里的 `onTap`。
      child: Semantics(
        key: widget.buttonKey,
        button: true,
        label: widget.tooltip,
        onTap: widget.onStep,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => _onDown(),
          onPointerUp: (_) => _stop(),
          onPointerCancel: (_) => _stop(),
          child: SizedBox(
            // 命中盒下限：透明盒 = 命中盒，
            // 视觉图标居中其内。
            width: kHitTargetMinSize,
            height: kHitTargetMinSize,
            child: Icon(widget.icon, color: Colors.white, size: 24),
          ),
        ),
      ),
    );
  }
}
