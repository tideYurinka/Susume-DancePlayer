/// **投屏取景闸门**（纯件，零 Flutter、零 IO）：把「源画面取景选区」折成画面
/// 滤镜链里的**裁切**与**缩放**节点。
///
/// ## 与上屏取值同源
///
/// 裁切窗口就是手机取景用的那一份取值——[FramingSelection]（四边按**源画面
/// 矩形**归一化，与路径、容器、屏面无关；`null` = 未调过 = 整帧）。它不是
/// 第二份口径：装配处（`player/cast_render_wiring.dart`）读一次
/// `framingStateProvider.source`，一路进缓存键的规范串，一路进渲染请求，本件
/// 只吃那份值对象。裁切窗口的尺寸与起点因此逐位等于上屏所读的同一个选区。
///
/// ## 先后：**先翻、后切窗**（与手机显示逐帧同相）
///
/// 手机上「翻转」是画面件自己的**显示层**变换（`picture_layer.dart` 的
/// `_SourceVideoSurface`），**取景**是包在它外面的那层剪辑窗（`FramingSelectionView`
/// 把剪辑 Rect 挂在画面件之上）——于是翻转落在取景之前：窗里的像素是「翻过的
/// 画面」在那块矩形上的样子。等价式是「按源坐标裁、后翻转」在同一画面上的
/// 另一种写法（`flip(源[a,b]) == 翻过的画面[c,d]`，两式在 `a=1-d, b=1-c` 时
/// 相等）；但**局部镜像是时间窗**，而 `crop` 不支持时间窗——要让窗逐帧跟着
/// 翻转走，只有「翻转节点在前、裁切在后」这一种写法。故选区四边原样进
/// `crop`（它判的就是翻过的那一帧的坐标），链上的次序在
/// `cast_render_plan.dart` 里写死，并由 `cast_framing_gate_test.dart` 用
/// 「产物节点 vs 手机显示模型」逐帧比对钉住。
///
/// ## 口径：窗里那一块自己成一份画面
///
/// 手机把选区内容按 contain 装进可用区（[FramingSelectionTransform]），故
/// **选区自己的宽高比就是上屏画面的宽高比**（`core/CONTEXT.md`）。投屏副本照
/// 这个口径走：输出帧就是裁切出来的那一块（尺寸即裁切尺寸），接收端再把它按
/// contain 铺到电视上——不把手机那块屏的宽高比烤进产物。
///
/// ## 兜底：奇数与极端比例
///
/// 源尺寸在装配期未知，故窗口用 ffmpeg 表达式写在源尺寸上（`iw`/`ih`）：
///
/// - **偶数对齐**：`floor(iw*宽/2)*2`——yuv420p 要求偶数，宁少一个像素也不
///   让色度平面错位；
/// - **最小 2 像素**：`max(2, …)`——手改文件里读到的一像素级选区不该产出
///   零尺寸帧；
/// - **钉在帧内**：`min(…, iw-ow)`——四边硬钳回整帧（`FramingSelection` 的
///   写侧本就钳过，这一道是给越界/手改值兜底）；
/// - **收尾的 `scale` 再兜一次**：把输出尺寸截到偶数（极小时不小到 0），并把
///   像素长宽比钉成 1:1。
///
/// 未取景（`null`）、退化形状（宽或高非正、非有限）与**整帧选区**都折成
/// **零节点**：整帧选区是「未调过」的显示等价物，不装裁切才不会给未取景的
/// 链路引入多余的缩放或像素格式变化（源尺寸为奇数时，整帧裁切反而会把画面
/// 少切一个像素）。
library;

import '../annotation/framing_selection.dart';
import 'cast_render_request.dart';

/// 比例字面量（进滤镜表达式）：六位小数、去掉尾零——够精确到亚像素，又能让
/// 留档里的算式读得出来（`0.8` 不写成 `0.800000`）。
String castRatioLiteral(double value) {
  if (!value.isFinite) return '0';
  var text = value.toStringAsFixed(6);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text == '-0' ? '0' : text;
}

/// `overlay` 的横向落位表达式：`(W*中心)-(w/2)`——`W` 是主片帧宽，`w` 是被
/// `scale2ref` 缩放后的第二路宽（帧的比例），故这是「按帧的比例把第二路居中
/// 落到归一化中心」。
///
/// 贴纸层与数拍层（`cast_sticker_gate.dart` / `cast_beat_gate.dart`）共用这
/// 一处：两层都是第二路输入 + 一个 `overlay`，落位写法必须逐字一致。
String castOverlayXExpression(double centerX) =>
    '(W*${castRatioLiteral(centerX)})-(w/2)';

/// `overlay` 的纵向落位表达式（与 [castOverlayXExpression] 同款）。
String castOverlayYExpression(double centerY) =>
    '(H*${castRatioLiteral(centerY)})-(h/2)';

/// 缩放的输出尺寸表达式：把裁切尺寸截到偶数。`iw`/`ih` 在 `scale` 里读的是
/// **裁切之后**的尺寸，故这一步是「给编码器的第二道兜底」，正常档下它与裁切
/// 尺寸一致（不是一次多余的缩放）。
const String kCastFramingScaleNode = 'scale=trunc(iw/2)*2:trunc(ih/2)*2';

/// 像素长宽比钉成方像素：接收端按方像素铺屏，产物不携带非 1:1 的 SAR。
const String kCastFramingSarNode = 'setsar=1';

/// 取景闸门的取值：请求里那份取景选区（未取景给 `null`）。
FramingSelection? castFramingGateOf(CastRenderRequest request) =>
    request.framingSelection;

/// 四边钳回整帧后仍非正的取值一概要（防手改/损坏值）。
FramingSelection? _clamped(FramingSelection? selection) {
  if (selection == null) return null;
  final left = selection.left.clamp(0.0, 1.0);
  final top = selection.top.clamp(0.0, 1.0);
  final right = selection.right.clamp(0.0, 1.0);
  final bottom = selection.bottom.clamp(0.0, 1.0);
  if (!left.isFinite ||
      !top.isFinite ||
      !right.isFinite ||
      !bottom.isFinite ||
      right <= left ||
      bottom <= top) {
    return null;
  }
  return FramingSelection(left: left, top: top, right: right, bottom: bottom);
}

/// 这套闸门要不要装节点：`null`、退化形状与**整帧选区**都算「未取景」。
bool castFramingActive(FramingSelection? selection) {
  final clamped = _clamped(selection);
  if (clamped == null) return false;
  const epsilon = 1e-6;
  final fullFrame =
      clamped.left.abs() <= epsilon &&
      clamped.top.abs() <= epsilon &&
      (clamped.right - 1).abs() <= epsilon &&
      (clamped.bottom - 1).abs() <= epsilon;
  return !fullFrame;
}

/// 取景的**裁切节点**：窗口四边全部写在源尺寸上（`iw`/`ih`），偶数对齐、
/// 最小 2 像素、钉在帧内——见库头「兜底」。私有：调用方只该经
/// [castFramingFilterNodes] 装节点，免得对着退化取值造一个空窗。
String _castFramingCropNode(FramingSelection selection) {
  final clamped = _clamped(selection)!;
  final width = castRatioLiteral(clamped.width);
  final height = castRatioLiteral(clamped.height);
  final left = castRatioLiteral(clamped.left);
  final top = castRatioLiteral(clamped.top);
  return 'crop='
      'w=max(2\\,floor(iw*$width/2)*2):'
      'h=max(2\\,floor(ih*$height/2)*2):'
      'x=min(floor(iw*$left/2)*2\\,iw-ow):'
      'y=min(floor(ih*$top/2)*2\\,ih-oh)';
}

/// 画面链里要装的取景节点（未取景 = 空表；取景 = 裁切 + 缩放 + 方像素）。
///
/// 这些节点插在**镜像节点之后**、倍速 `setpts` 之前——先后见库头。
List<String> castFramingFilterNodes(FramingSelection? selection) {
  if (!castFramingActive(selection)) return const [];
  return <String>[
    _castFramingCropNode(selection!),
    kCastFramingScaleNode,
    kCastFramingSarNode,
  ];
}
