/// 自动消退「短暂提示」模块。
///
/// 收敛原三份同构实现：临时衔接段提示（`transition_prompt.dart`）、
/// 三指跳转提示（`three_finger_toast.dart`，带淡出）与居中确认提示
/// （`centered_prompt.dart`，无淡出、序号 provider 触发）。`lib/player/CONTEXT.md`
/// 词条「短暂提示」：状态或事件触发的全屏短暂胶囊浮层——纯提示不承载交互、
/// 点按穿透（[IgnorePointer]）、定时自动消退。
///
/// 模块面：
/// - [NoticeController]：纯 Dart 显隐状态机，fake 时钟直测；`fade == 0`
///   为「到时直接隐藏」变体（原 centered 语义），`fade > 0` 为
///   「停留 + 淡出」两段语义（原 transition/toast 语义）。
/// - [NoticeOverlay]：居中浮层（IgnorePointer → Center →
///   AnimatedOpacity），key 与内容由调用侧传入。
/// - [NoticeId] / [NoticeSpec] / [noticeTimingOf]：身份、域内声明与
///   「缺省 + 只列例外」的时长表。
/// - [noticeTriggerProvider] / [NoticeHost]：按身份取用的计数器触发面与
///   演出层唯一宿主——宿主只渲染当前一条，同屏不可能出现两条。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notice_badge.dart';
import 'segment_jump.dart' show ThreeFingerSwipeDirection;

/// 提示身份：十二条短暂提示一次声明齐，按**语义**
/// 命名（不按它渲染什么）。内容由所属域经 [NoticeSpec] 声明，不出现在本
/// 模块里。
enum NoticeId {
  /// 步进启用（倍速步进入口）。
  stepEnabled,

  /// 浮层 ✕ 关闭（播放页浮层关闭路径）。
  beatOverlayClose,

  /// 节拍分析中（控制层自动分段门）。
  beatAnalyzing,

  /// 无节拍数据（控制层自动分段门）。
  beatNoData,

  /// 正在装载（装载门）。
  loadGate,

  /// 局部镜像无片段（顶栏软门）。
  localMirrorEmpty,

  /// 锁定分段（控制层、标注编辑模块、轨道带三处触发）。
  layoutLock,

  /// 无对象（灰钮给做法）：没有作用对象时按下去弹「该怎么做」。
  noSubject,

  noteContentLock,

  compareRecordRejected,

  /// 三指跳转（播放手势仲裁 / 演出会话）。
  threeFingerToast,

  /// 临时衔接段激活（轨道带）。
  transition,

  /// 文档只读（按视频文档读到只读版本、写回被挡时）。
  documentReadOnly,

  /// 投屏断了（遥控动作失败 / 掉线：断开并回编辑态）。
  castInterrupted,

  /// 没接上接收端（起投失败：连不上 / 被拒 / 递出通道起不来）。
  castNotStarted,

  /// 系统投屏设置打不开（系统镜像入口的降级链两级都没接住）。
  systemMirrorUnavailable,

  /// 投屏入口被门挡下（副本丢失 / 校准中 / 录制中 / 对比或取景 / 渲染中：
  /// 灰着那枚按下去只解释原因）。
  castEntryBlocked,
}

/// 一条提示的声明（由所属域给出）：身份 + 内容 + 定位 key。
class NoticeSpec {
  const NoticeSpec({required this.id, required this.content, this.noticeKey});

  final NoticeId id;

  /// 提示内容（胶囊内 child）。
  final Widget Function(BuildContext) content;

  /// 胶囊测试定位 key（逐字沿用既有取值）。
  final Key? noticeKey;
}

/// 停留时长缺省：改「提示统一停多久」= 改这一个值。
const Duration kDefaultNoticeHold = Duration(milliseconds: 1500);

/// 停留 + 淡出时长。未在 [noticeTimingOf] 列出的身份取
/// `hold = [kDefaultNoticeHold]`、`fade = Duration.zero`。
class NoticeTiming {
  const NoticeTiming({
    this.hold = kDefaultNoticeHold,
    this.fade = Duration.zero,
  });

  final Duration hold;

  /// 淡出动画时长；[Duration.zero] = 到时直接隐藏。
  final Duration fade;
}

/// 时长表：缺省之外**只列例外**（浮层 ✕ 关闭 2000ms；三指跳转 600/200ms；
/// 临时衔接段 300ms 淡出）。
NoticeTiming noticeTimingOf(NoticeId id) => switch (id) {
  NoticeId.beatOverlayClose => const NoticeTiming(
    hold: Duration(milliseconds: 2000),
  ),
  NoticeId.threeFingerToast => const NoticeTiming(
    hold: Duration(milliseconds: 600),
    fade: Duration(milliseconds: 200),
  ),
  NoticeId.transition => const NoticeTiming(fade: Duration(milliseconds: 300)),
  _ => const NoticeTiming(),
};

/// 通用触发面：按身份取用，保持计数器语义——
/// 自增即触发；同一身份连续触发由宿主重排停留定时。调用方只报身份，
/// 不再各自持有专属触发类。
class NoticeTrigger extends Notifier<int> {
  NoticeTrigger(this.id);

  /// 本触发面绑定的提示身份（family 参数）。
  final NoticeId id;

  @override
  int build() => 0;

  void show() => state++;
}

/// 通用触发注入点。
final noticeTriggerProvider =
    NotifierProvider.family<NoticeTrigger, int, NoticeId>(NoticeTrigger.new);

/// 三指跳转方向注入点：由触发跳转的那一处（手势
/// 仲裁的三指跳转）写入；内容声明经它读取方向取图标，内容因此可以是常量。
/// 方向是取图标的事实，不是提示内容——内容仍由所属域声明。
class ThreeFingerToastDirection extends Notifier<ThreeFingerSwipeDirection> {
  @override
  ThreeFingerSwipeDirection build() => ThreeFingerSwipeDirection.left;

  /// 触发跳转的那一处写入的方向。
  void write(ThreeFingerSwipeDirection direction) => state = direction;
}

/// 三指跳转方向注入点。
final threeFingerToastDirectionProvider =
    NotifierProvider<ThreeFingerToastDirection, ThreeFingerSwipeDirection>(
      ThreeFingerToastDirection.new,
    );

/// 提示宿主：演出层挂**唯一一条**，取代十一行并列
/// 挂载。宿主从组合根收到声明清单，只渲染**当前这一条**——同屏不可能出现
/// 两条；后触发者接管。按当前身份新建 [NoticeController]（时长取
/// [noticeTimingOf]），换身份时销毁旧的——定时器不跨提示泄漏。
class NoticeHost extends ConsumerStatefulWidget {
  const NoticeHost({super.key, required this.specs});

  /// 组合根装配的提示声明清单。
  final List<NoticeSpec> specs;

  @override
  ConsumerState<NoticeHost> createState() => _NoticeHostState();
}

class _NoticeHostState extends ConsumerState<NoticeHost> {
  NoticeController? _controller;
  NoticeSpec? _current;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _activate(NoticeSpec spec) {
    if (!mounted) return;
    setState(() {
      if (_current?.id != spec.id) {
        _controller?.dispose();
        final timing = noticeTimingOf(spec.id);
        _controller = NoticeController(hold: timing.hold, fade: timing.fade);
        _current = spec;
      }
      _controller?.show();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 触发与显示的连线收在模块内部：监听每条已声明身份的计数器，计数变化
    // 即接管当前显示槽（同一身份再次触发重排停留定时）。
    for (final spec in widget.specs) {
      ref.listen<int>(
        noticeTriggerProvider(spec.id),
        (_, _) => _activate(spec),
      );
    }
    final controller = _controller;
    final current = _current;
    if (controller == null || current == null) {
      return const SizedBox.shrink();
    }
    return NoticeOverlay(
      controller: controller,
      noticeKey: current.noticeKey,
      contentBuilder: current.content,
    );
  }
}

/// 短暂提示阶段。
enum NoticePhase {
  /// 无提示（浮层不占空间）。
  hidden,

  /// 提示可见（全不透明，停留 hold）。
  showing,

  /// 淡出中（透明度动画进行中，结束回 [NoticePhase.hidden]）。
  fading,
}

/// 短暂提示状态机：只维护「是否可见」并在切换时通知监听者。
///
/// [hold] 为停留时长；[fade] 为淡出动画时长，[Duration.zero] 表示无淡出
/// ——停留到点直接回 hidden（原居中确认提示语义）。
class NoticeController extends ChangeNotifier {
  NoticeController({required this.hold, this.fade = Duration.zero});

  /// 提示停留时长（随后开始淡出，或无淡出时直接隐藏）。
  final Duration hold;

  /// 淡出动画时长；[Duration.zero] = 到时直接 hidden。
  final Duration fade;

  NoticePhase _phase = NoticePhase.hidden;
  Timer? _holdTimer;
  Timer? _fadeTimer;
  bool _disposed = false;

  /// 当前提示阶段（浮层据此显隐/淡出）。
  NoticePhase get phase => _phase;

  /// 提示是否可见（showing 或 fading）。
  bool get visible => _phase != NoticePhase.hidden;

  /// 触发一次提示。已在展示中时重排定时（连续触发不叠加，后一次覆盖
  /// 前一次的消失时刻）；重复调用幂等收敛为同一相位序列。
  void show() {
    if (_disposed) return;
    _cancelTimers();
    _phase = NoticePhase.showing;
    notifyListeners();
    _holdTimer = Timer(hold, _beginFadeOut);
  }

  /// 强制立即隐藏（取消全部定时）。
  void hideNow() {
    if (_disposed) return;
    _cancelTimers();
    if (_phase == NoticePhase.hidden) return;
    _phase = NoticePhase.hidden;
    notifyListeners();
  }

  void _beginFadeOut() {
    _holdTimer = null;
    if (_disposed || _phase != NoticePhase.showing) return;
    if (fade == Duration.zero) {
      // 无淡出变体：到时直接隐藏（原居中确认提示语义）。
      _phase = NoticePhase.hidden;
      notifyListeners();
      return;
    }
    _phase = NoticePhase.fading;
    notifyListeners();
    _fadeTimer = Timer(fade, _completeFadeOut);
  }

  void _completeFadeOut() {
    _fadeTimer = null;
    if (_disposed) return;
    _phase = NoticePhase.hidden;
    notifyListeners();
  }

  void _cancelTimers() {
    _holdTimer?.cancel();
    _holdTimer = null;
    _fadeTimer?.cancel();
    _fadeTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}

/// 短暂提示浮层：showing/fading 期间屏幕正中叠加内容，hidden 不占空间。
///
/// 整体 [IgnorePointer]——纯提示、不拦截任何触摸。结构
/// IgnorePointer → Center → [AnimatedOpacity]（时长取 [NoticeController.fade]）
/// → [NoticeBadge] 胶囊（[noticeKey] 供测试定位）；内容经 [contentBuilder]
/// 由调用侧构建（每次控制器通知都重建，可随控制器状态变化取内容）。
class NoticeOverlay extends StatelessWidget {
  const NoticeOverlay({
    super.key,
    required this.controller,
    required this.contentBuilder,
    this.noticeKey,
  });

  /// 显隐状态机。
  final NoticeController controller;

  /// 提示内容（胶囊内 child，由调用侧构建）。
  final WidgetBuilder contentBuilder;

  /// 胶囊测试定位 key。
  final Key? noticeKey;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        if (phase == NoticePhase.hidden) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          child: Center(
            // showing ↔ fading 时透明度目标切换驱动淡出（fade == 0 时不
            // 进入 fading，淡入在首次挂载时不播放，避免出现闪烁）。
            child: AnimatedOpacity(
              opacity: phase == NoticePhase.showing ? 1.0 : 0.0,
              duration: controller.fade,
              curve: Curves.easeOut,
              // 胶囊底座收敛为 NoticeBadge——视觉与收敛前的
              // 手写 Material pill 一致（token 值即原字面量）。
              child: NoticeBadge(
                key: noticeKey,
                child: contentBuilder(context),
              ),
            ),
          ),
        );
      },
    );
  }
}
