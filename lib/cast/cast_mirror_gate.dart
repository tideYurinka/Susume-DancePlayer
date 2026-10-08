/// **投屏镜像闸门**（纯件，零 Flutter、零 IO）：把「全局镜像 ⊕ 局部镜像片段」
/// 折成画面滤镜链里的翻转节点。
///
/// ## 与上屏取值同源
///
/// 闸门取值来自画面方向库的 [SourceVideoFlip]——那是源视频面翻转的**唯一声明
/// 处**（`lib/surface_direction/surface_direction.dart`）：手机在屏取它的
/// 逐位置读法（[SourceVideoFlip.mirroredAt]），这里取它的逐区间读法
/// （[SourceVideoFlip.localActiveWindows]）。于是「电视上的翻转与手机上实际
/// 显示的逐帧一致」不是两处各自对齐的口径，而是同一个值的两种读法。
///
/// ## 两枚闸门 = 合成而不是叠加
///
/// 节点集里最多两枚 `hflip`：**全局镜像**一朵无时间窗（整片施加），**局部
/// 镜像**一朵带 `enable`（限在片段窗内）。窗内两枚同时生效 = 净不翻，窗外只剩
/// 全局那一枚——这正是 `全局镜像 ⊕（局部镜像 ∧ 在区间内）` 的像素样子。
///
/// ## 时间窗是半开区间，判的是**源时间轴**
///
/// 每窗写成 `gte(t,起)*lt(t,止)`，**不用 `between`**（它两端都含，会多翻一帧）。
/// 闸门在画面链里排在倍速 `setpts` **之前**（见 `cast_render_plan.dart`），
/// 所以 `t` 是源片时间、窗与投屏倍速档不耦合：0.5 档下 `t` 仍是源片时间，与
/// 手机上按源位置求值的那一份对齐。
library;

import '../core/local_mirror_fragment.dart';
import '../surface_direction/surface_direction.dart';
import 'cast_render_request.dart';

/// 秒的字面量写法：整秒不写成 `2.0`——滤镜图是要进留档文档的外部契约，读数人
/// 看到的是锚点本身（`2`）、不是它的浮点表示。
String castSeconds(double seconds) => seconds == seconds.roundToDouble()
    ? seconds.toInt().toString()
    : seconds.toString();

/// 一窗的 `enable` 表达式：半开区间 `[起, 止)` → `gte(t,起)*lt(t,止)`，
/// **不用 `between`**（它两端都含、会多一帧）。
///
/// 镜像闸门与贴纸闸门（`cast_sticker_gate.dart` 的
/// `CastStickerSegment.enableExpression`）共用这一处：两边的窗都判**源时间
/// 轴**（闸门排在倍速 `setpts` 之前），判法必须逐字一致。
String castHalfOpenWindowExpression(int startMs, int endMs) =>
    'gte(t,${castSeconds(startMs / 1000)})*lt(t,${castSeconds(endMs / 1000)})';

/// 多窗并成一条 `enable` 表达式（按 `+` 相加：叠交只是真值非零，不重叠时各自
/// 成窗）。退化窗（起 = 止，恒假）不产出项；一项不剩时给恒假表达式 `0`。
String castMirrorUnionExpression(Iterable<LocalMirrorFragment> windows) {
  final terms = <String>[
    for (final window in windows)
      if (window.startMs < window.endMs)
        castHalfOpenWindowExpression(window.startMs, window.endMs),
  ];
  return terms.isEmpty ? '0' : terms.join('+');
}

/// 这套闸门里有没有**生效的时间窗**（总开关关掉或片段退化时都没有）。
bool castMirrorHasWindow(SourceVideoFlip gate) =>
    gate.localActiveWindows.any((window) => window.startMs < window.endMs);

/// 从渲染请求装配闸门：全局镜像与局部镜像总开关读设置快照，片段表读请求
/// （装配处与上屏求值读**同一份** provider 取值，见 `cast_render_wiring.dart`）。
SourceVideoFlip castMirrorGateOf(CastRenderRequest request) => SourceVideoFlip(
  globalMirrored: request.settings.globalMirrored,
  localMirrorEnabled: request.settings.localMirrorEnabled,
  fragments: request.mirrorFragments,
);

/// 画面链里要装的镜像翻转节点（0 / 1 / 2 枚，按上面的次序）：
/// 先全局那一枚（无窗），再局部那一枚（限窗）。
List<String> castMirrorFilterNodes(SourceVideoFlip gate) => <String>[
  if (gate.globalMirrored) 'hflip',
  if (castMirrorHasWindow(gate))
    "hflip=enable='${castMirrorUnionExpression(gate.localActiveWindows)}'",
];
