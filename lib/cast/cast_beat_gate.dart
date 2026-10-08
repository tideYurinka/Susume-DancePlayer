/// **投屏数拍闸门**（纯件，零 Flutter、零 IO；`#30`）：把「逐拍静态数字」折成
/// 画面链里的**一条**时间窗文本流 + 一个 `overlay` 节点，以及图像序列
/// 解复用器要读的那份清单。
///
/// ## 为什么是「一条序列」而不是「一格一路输入」
///
/// 已链接的 ffmpeg 变体（`ffmpeg_kit_flutter_new_min`）里**没有 `drawtext`**
/// （它要 `libfreetype`，min 变体零外部库；见 `lib/cast/docs/real-device-
/// acceptance.md` 的实测留档），所以字得由**播放页侧**按上屏同一份样式光栅化
/// 成 PNG——与备注贴纸（`#29`）同一条路。区别在数量：贴纸是一支舞几条，
/// 数拍是**一拍一格**（一支三分钟的舞就上百格）。
///
/// 上百路 `-i` + 上百个 `overlay` 节点在真机上代价陡增（宿主实测：1080p/5s
/// 上 300 个节点已经要 0.85s，是同一段素材纯编码的几倍），故这里走
/// **图像序列**：一格一张同尺寸 PNG，按 [CastBeatCountRow.durationMs] 写进
/// `-f concat` 清单，整条序列当**一路输入**喂给一个 `overlay`。逐拍时间窗因此
/// 仍在（每格的时长就是它的窗），而滤镜图与真机开销是常数级。
///
/// ## 单输入的时间窗文本
///
/// 规格那句「呈现类只烤逐拍静态数字（**单输入的时间窗文本**）」在这里是：
/// 序列输入 + 一个叠加节点（不是每拍一个节点），文字由播放页光栅化
/// （`player/cast_beat_sheet.dart`），链上不再拼字体。
///
/// ## 清单为什么末条要重列一次
///
/// `concat` 解复用器的既有口径：`duration` 指令描述**前一条**文件，最后一条
/// 若没有后继条目，它的时长不生效（序列会提前结束）。故清单末尾把最后一格再
/// 列一次（不带 duration）——这是外部契约的一部分，`cast_beat_gate_test.dart`
/// 逐字钉住。
///
/// ## 与上屏同源
///
/// 落位（[CastBeatCountOverlay] 的四个数）由播放页按「视口 → 画面区域」换算
/// 后带过来；本件只把它写成 `scale2ref` 的比例与 `overlay` 的 `x`/`y` 表达式
/// ——与备注贴纸同一套写法（第二路先按帧的比例缩放，再叠上去）。
library;

import 'cast_beat_count.dart';
import 'cast_framing_gate.dart'
    show castOverlayXExpression, castOverlayYExpression, castRatioLiteral;

/// 数拍层在画面链里装出来的东西：进 `filter_complex` 的节点 + 链尾标签。
class CastBeatCountGraph {
  const CastBeatCountGraph({required this.nodes, required this.endLabel});

  /// 数拍层的节点（三条：序列归一、按帧比例缩放、叠加）。
  final List<String> nodes;

  /// 数拍链的输出标签（不装这一层时等于调用方给的 `startLabel`）。
  final String endLabel;
}

/// 这条层要不要装：没有可画的格、落位退化（非有限 / 非正）都**不装**
/// ——宁可不画也不画错（与「探测不到一律按不显示处理」同口径）。
///
/// 落位那四个数的判定不在这里写第二遍：它是 [CastBeatCountOverlay.usable]，
/// 而与播放页 `CastBeatPlacement.usable` 共用同一条判定（见
/// `castOverlayPlacementUsable`）。
bool castBeatCountActive(CastBeatCountOverlay? overlay) =>
    overlay != null && overlay.hasVisibleRow && overlay.usable;

/// `-f concat` 清单的正文：逐格 `file` + `duration`，末尾重列最后一格。
///
/// [paths] 与 [rows] 一一对应、次序相同（空格的格也要有一张全透明的画布——
/// 序列要连续覆盖整片，漏一格整条时间轴就错位）。
String castBeatSlidesContent({
  required List<CastBeatCountRow> rows,
  required List<String> paths,
}) {
  if (paths.length != rows.length) {
    throw ArgumentError(
      '数拍格图（${paths.length}）与时间窗（${rows.length}）对不上',
    );
  }
  if (rows.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    // 单引号路径里的单引号按 concat 解复用器的转义口径写成 '\''。
    buffer.writeln("file '${paths[i].replaceAll("'", r"'\''")}'");
    buffer.writeln('duration ${rows[i].durationLiteral}');
  }
  buffer.writeln("file '${paths.last.replaceAll("'", r"'\''")}'");
  return buffer.toString();
}

/// 装配数拍层：序列输入先归到主片帧率网格与 rgba，再按帧的比例缩放、
/// 全分辨率 alpha 送回，最后 `overlay` 叠上去。
///
/// [inputIndex] 是那份 `-f concat` 输入在 `-i` 里的下标；[startLabel] 是前置
/// 画面链（镜像 + 取景）的输出标签；[endLabel] 是数拍层的输出标签（后面的
/// 贴纸层接在它上面——层序与上屏一致：贴纸画在数拍之上）。
CastBeatCountGraph castBeatCountGraph({
  required CastBeatCountOverlay overlay,
  required String startLabel,
  required String endLabel,
  required int inputIndex,
  required int fps,
}) {
  if (!castBeatCountActive(overlay)) {
    return CastBeatCountGraph(nodes: const [], endLabel: startLabel);
  }
  // 时间窗的判定网格必须与主片同一格：第二路显式过 fps（与贴纸同款）。
  final seq = 'bseq$inputIndex';
  final scaled = 'bcan$inputIndex';
  final ref = 'bmai$inputIndex';
  final alpha = 'bsa$inputIndex';
  return CastBeatCountGraph(
    nodes: <String>[
      '[$inputIndex:v]format=rgba,fps=$fps[$seq]',
      // `iw`/`ih` 是参考路（主片帧）的尺寸——与贴纸层同一写法：比例要落在帧上
      // 就得读主路，PNG 自己的像素尺寸不进这两个数（见 `cast_sticker_gate.dart`）。
      '[$seq][$startLabel]scale2ref='
          'w=iw*${castRatioLiteral(overlay.widthFraction)}:'
          'h=ih*${castRatioLiteral(overlay.heightFraction)}'
          '[$scaled][$ref]',
      '[$scaled]format=rgba[$alpha]',
      '[$ref][$alpha]overlay='
          'x=${castOverlayXExpression(overlay.centerX)}:'
          'y=${castOverlayYExpression(overlay.centerY)}:'
          'format=rgb:eof_action=repeat[$endLabel]',
    ],
    endLabel: endLabel,
  );
}
