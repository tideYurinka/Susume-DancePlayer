/// 画面方向快照的装配与下发。
///
/// 「画面方向」的求值入参是逐项 `required` 的 [SurfaceMoment]。本模块是这份
/// 快照在播放场景里的**唯一交接点**：
///
/// - [assembleSurfaceDirection] 是快照构造的唯一处（局部镜像两项 = 总开关与
///   片段表在此读一次），播放页两处求值点都经它取快照，加一个输入位只改这里；
/// - [SurfaceFaceAssembly] 是**源视频面**快照的装配点：把四个来源（全局镜像
///   状态机、局部镜像总开关、会话内启用片段集合、当前显示位置）收成一处，
///   **仅当方向真变才重建下游**（位置每帧推进只更新快照，不重建画面）；
/// - [SurfaceFaceScope] 是下发面：一次求值的结果下发给两处消费者——取景分屏
///   里源半区的视频画面件与注解层（备注贴纸），两处读同一份取值。取景与浮层
///   装配两域因此共享同一份快照。
///
/// 依赖方向单向：本模块 import 画面方向纯值库、镜像/练习镜像/局部镜像的
/// provider 与播放位置（位置 provider 归播放内核中立 home，不读中枢），两个
/// 域模块不 import 本模块、本模块也不 import 两个域模块。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/local_mirror.dart' show LocalMirrorFragment;
import '../core/playback/playback_engine_providers.dart'
    show playbackEngineProvider, playbackPositionProvider;
import '../surface_direction/surface_direction.dart';
import 'annotation_editor.dart'
    show localMirrorEnabledProvider, localMirrorFragmentsProvider;
import 'mirror.dart';
import 'practice_mirror.dart' show effectivePracticeMirrorProvider;
import 'surface_basis_key.dart' show liveSurfaceBaselinesProvider;

/// 装配一份画面方向快照：把逐项入参收成 [SurfaceMoment] 再交给
/// [SurfaceDirection]（快照是唯一入参，构造器逐项 required——缺项不静默取
/// 默认）。
///
/// 局部镜像两项（总开关 [localMirrorEnabledProvider]、片段表
/// [localMirrorFragmentsProvider]）在此经 [ref] 读一次，其余输入由各求值点
/// 按自己的订阅面传入：[practiceMirror] 练习侧必须订阅（练习镜像是**活
/// 输入**，录制中拨开关当场生效），源视频面不读它、只需取值不老；
/// [baselines] = 本次求值读的**基线项**（源视频面读设备事实当前值，练习侧在
/// 录制期读会话武装冻结的那份）。
SurfaceDirection assembleSurfaceDirection(
  WidgetRef ref, {
  required bool globalMirrored,
  required bool practiceMirror,
  required int positionMs,
  required SurfaceBaselines baselines,
}) => _snapshot(
  globalMirrored: globalMirrored,
  localMirrorEnabled: ref.read(localMirrorEnabledProvider),
  fragments: ref.read(localMirrorFragmentsProvider),
  positionMs: positionMs,
  practiceMirror: practiceMirror,
  baselines: baselines,
);

/// 练习侧画面方向（相机与练习面域消费）：练习两面只读**练习镜像**与**基线
/// 项**——源视频面的三项输入（全局镜像、局部镜像总开关与片段表、显示位置）
/// 不参与相机预览面与片段回放面的取值，按「不镜像、无片段、零位置」读入
/// （[SurfaceMoment.practiceOnly]）。
///
/// 与源视频面共用同一处快照构造（[SurfaceMoment] 仍只在本模块构造一次）：
/// 练习面与源视频面的方向口径因此是同一张表。
SurfaceDirection assemblePracticeFaceDirection({
  required bool practiceMirror,
  required SurfaceBaselines baselines,
}) => SurfaceDirection(
  moment: SurfaceMoment.practiceOnly(
    practiceMirror: practiceMirror,
    baselines: baselines,
  ),
);

SurfaceDirection _snapshot({
  required bool globalMirrored,
  required bool localMirrorEnabled,
  required List<LocalMirrorFragment> fragments,
  required int positionMs,
  required bool practiceMirror,
  required SurfaceBaselines baselines,
}) => SurfaceDirection(
  moment: SurfaceMoment(
    globalMirrored: globalMirrored,
    localMirrorEnabled: localMirrorEnabled,
    fragments: fragments,
    positionMs: positionMs,
    practiceMirror: practiceMirror,
    baselines: baselines,
  ),
);

/// 源视频面方向的装配点：把四个输入来源收成一处，装配出当前这一刻的快照
/// （[SurfaceMoment]）交给画面件——画面件只读快照，不各自读值。
///
/// [mirror] 是 ChangeNotifier（不在 Riverpod 值道上），其余三个来源经
/// `listenManual` 订阅；任一来源变更即重新装配，**仅当方向真变才重建下游**
/// （位置每帧推进只更新快照，不重建画面）。
///
/// 方向口径归画面方向库（`surface_direction.dart`）：源视频面取值 = 全局镜像
/// ⊕（局部镜像开关 ∧ 片段覆盖当前位置）。
class SurfaceFaceAssembly extends ConsumerStatefulWidget {
  const SurfaceFaceAssembly({
    super.key,
    required this.mirror,
    required this.builder,
  });

  /// 全局镜像状态机（宿主保有；其 `mirrored` 是快照输入之一）。
  final MirrorController mirror;

  /// 用当前这一刻的快照构建下游（画面件）。
  final Widget Function(BuildContext context, SurfaceDirection direction)
  builder;

  @override
  ConsumerState<SurfaceFaceAssembly> createState() =>
      _SurfaceFaceAssemblyState();
}

class _SurfaceFaceAssemblyState extends ConsumerState<SurfaceFaceAssembly> {
  /// 当前位置：位置流每帧推进只更新它，不重建画面。
  Duration _position = Duration.zero;

  /// 当前这一刻的快照（装配结果）。
  late SurfaceDirection _direction;

  @override
  void initState() {
    super.initState();
    widget.mirror.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 初始就位各源现值（含引擎已 seek 到目标、位置流未发新事件的定格）。
    _position = _currentPosition();
    _direction = _assemble();
    // 位置推进 / seek 定格补发 → 重新装配。
    ref.listenManual<AsyncValue<Duration>>(playbackPositionProvider, (_, next) {
      _refresh(position: next.value);
    });
    // 片段建/删/移/端点变更 → 重新装配。
    ref.listenManual<List<LocalMirrorFragment>>(
      localMirrorFragmentsProvider,
      (_, _) => _refresh(),
    );
    // 局部镜像总开关切换（恢复装载 / 顶栏开关）→ 重新装配。
    ref.listenManual<bool>(localMirrorEnabledProvider, (_, _) => _refresh());
    // 练习镜像切换 → 重新装配：源视频面不读它，但快照是「一次求值的全部
    // 入参」，练习镜像又是**活输入**，取值要跟着走、不被这一份快照冻住。
    ref.listenManual<bool>(
      effectivePracticeMirrorProvider,
      (_, _) => _refresh(),
    );
  }

  @override
  void didUpdateWidget(SurfaceFaceAssembly oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mirror != widget.mirror) {
      oldWidget.mirror.removeListener(_refresh);
      widget.mirror.addListener(_refresh);
      _refresh();
    }
  }

  @override
  void dispose() {
    widget.mirror.removeListener(_refresh);
    super.dispose();
  }

  /// 重新装配快照；**仅当方向真变才重建下游**（位置每帧推进只更新快照，
  /// 下一次重建带上新位置，不重建画面）。局部镜像生效取值由同一式与全局
  /// 镜像合成进方向（`方向 = 全局 ⊕ 局部生效`），它一变方向必翻，故画面
  /// 标识与画面件共用这一条重建条件即可。
  void _refresh({Duration? position}) {
    if (!mounted) return;
    _position = position ?? _currentPosition();
    final next = _assemble();
    if (next.directionOf(SurfaceFace.sourceVideo) ==
        _direction.directionOf(SurfaceFace.sourceVideo)) {
      _direction = next;
      return;
    }
    setState(() => _direction = next);
  }

  SurfaceDirection _assemble() => assembleSurfaceDirection(
    ref,
    globalMirrored: widget.mirror.mirrored,
    // 练习镜像：源视频面不消费，按现值读入（其切换经 listenManual 重新装配）。
    practiceMirror: ref.read(effectivePracticeMirrorProvider),
    positionMs: _position.inMilliseconds,
    // 基线项：源视频面不消费设备事实（它只读全局/局部镜像与位置），按当前
    // 取值读入即可——录制期的冻结归练习侧求值点。
    baselines: ref.read(liveSurfaceBaselinesProvider),
  );

  /// 当前显示位置：位置流现值优先，未就绪回落引擎现读位置。
  Duration _currentPosition() =>
      ref.read(playbackPositionProvider).value ??
      ref.read(playbackEngineProvider).position;

  @override
  Widget build(BuildContext context) => widget.builder(context, _direction);
}

/// 源视频面方向作用域：装配点（[SurfaceFaceAssembly]）一次求值的结果经本件
/// 下发给**两处消费者**——取景分屏里源半区的视频画面件与注解层（备注
/// 贴纸），两处读同一份取值。
///
/// [of] 给出的是**源视频面的方向**（用户可见事实）：该面的画面即参照系，
/// 故方向与「该面施加的缩放」同值——画面件按它套变换，注解层按它做坐标
/// 换算。未装配即读 = 接线错，断言报错、不静默取默认。
class SurfaceFaceScope extends InheritedWidget {
  const SurfaceFaceScope({
    super.key,
    required this.snapshot,
    required super.child,
  });

  /// 当前这一帧的源视频面求值快照：画面件、注解层（备注贴纸）与画面标识
  /// 读的是**同一份**求值结果。
  final SurfaceDirection snapshot;

  static SurfaceFaceScope _scopeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SurfaceFaceScope>();
    assert(scope != null, '源视频面方向作用域缺失：画面件 / 注解层 / 画面标识须挂在装配点之下');
    return scope!;
  }

  /// 源视频面的方向（用户可见事实）：该面的画面即参照系，故方向与「该面
  /// 施加的缩放」同值——画面件按它套变换，注解层按它做坐标换算。
  static FaceDirection of(BuildContext context) =>
      _scopeOf(context).snapshot.directionOf(SurfaceFace.sourceVideo);

  /// 当前这一帧局部镜像是否生效（画面标识的出现条件）：与画面翻转读**同一个
  /// 取值**（画面方向库的 [SurfaceDirection.localMirrorActive]）。
  static bool localMirrorActiveOf(BuildContext context) =>
      _scopeOf(context).snapshot.localMirrorActive;

  /// 方向真变才通知下游（局部镜像生效取值与方向由同一式合成，方向一变它
  /// 必随之变，故不另设第二条通知条件）。
  @override
  bool updateShouldNotify(SurfaceFaceScope oldWidget) =>
      oldWidget.snapshot.directionOf(SurfaceFace.sourceVideo) !=
      snapshot.directionOf(SurfaceFace.sourceVideo);
}
