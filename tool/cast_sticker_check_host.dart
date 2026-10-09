/// **备注贴纸的宿主逐像素对照**（`#29` 的验收入口）：把**生产那一串命令行**
/// （`lib/cast/cast_render_plan.dart`，只把编码器换成宿主的 libx264）交给本机
/// ffmpeg 跑一遍，再从产物里逐帧读像素核对四件事：
///
/// 1. **落位与尺寸**：贴纸墨迹在帧里的像素矩形 == 声明的那份归一化落位与尺寸
///    系数（含取景窗口换算与随面翻转）——期望值由本脚本按**简单算术**独立算出
///    （不反算被测代码的表达式）；
/// 2. **进出时刻**：贴纸窗的**半开**口径——窗的第一帧在、终点那一帧不在，
///    两侧各多查一帧（不多一帧不少一帧）；
/// 3. **透明度是乘不是设**：墨迹内部的像素等于 `α·贴纸色 + (1−α)·背景色`
///    （α 由输入 PNG 自己给出），并且有一张**反例图**（把 alpha 当预乘读）明显
///    不同——否则这条比对判不出东西；
/// 4. **彩色背景下边缘无脏边**：走 `rgba + overlay=format=rgb` 的那条路，墨迹
///    外沿一圈的偏差明显小于**默认路径**（`yuva420p` + 默认混合，色度 2×2
///    次采样）——规格里那句「默认会被色度 2×2 次采样、边缘会脏」的实测。
///
/// 真机上那份（字体、点名取色、观感）只能真机看：宿主这一份验的是**滤镜图与
/// 产物的像素语义**，与平台无关。
///
/// 用法（仓库根目录）：
///   dart run tool/cast_sticker_check_host.dart [--out /tmp/cast_sticker] [--json 路径]
///
/// 退出码 0 = 上面的硬判据全过；非 0 = 有读数不成立。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';

/// 固定输入：6 秒 / 640×360 / 30fps 的纯色源片（纯色让混合算式可独立复算）。
const int _fps = 30;
const double _seconds = 6;
const int _width = 640;
const int _height = 360;

/// 源片底色（成片里会被 yuv420p 来回一趟，读数一律取成片里那片区域的实测值）。
const String _background = '0x102030';

/// 贴纸墨迹的 alpha（输入 PNG 由本脚本按这个数造出来：alpha 是**乘**上去的）。
const double _stickerAlpha = 0.6;

/// 一条贴纸的声明（脚本侧的事实；期望值由此独立算出）。
class _SheetSpec {
  const _SheetSpec({
    required this.startMs,
    required this.endMs,
    required this.centerX,
    required this.centerY,
    required this.widthFraction,
    required this.heightFraction,
  });

  final int startMs;
  final int endMs;

  /// 源画面归一化中心（与文档几何同一个坐标口径）。
  final double centerX;
  final double centerY;

  /// 占**取景后画面**（= 成片帧）的比例。
  final double widthFraction;
  final double heightFraction;

  /// 落地用的 PNG 像素尺寸：按「帧的比例 × 源尺寸」造，缩放因此接近 1:1。
  int get pngWidth => (widthFraction * _width).round();
  int get pngHeight => (heightFraction * _height).round();
}

/// 一跑的全部读数（留档用）。
final _report = <String, Object?>{};

Future<void> main(List<String> arguments) async {
  final outIndex = arguments.indexOf('--out');
  final root = Directory(
    outIndex >= 0 && outIndex + 1 < arguments.length
        ? arguments[outIndex + 1]
        : '/tmp/cast_sticker_check',
  );
  final jsonIndex = arguments.indexOf('--json');
  final jsonPath = jsonIndex >= 0 && jsonIndex + 1 < arguments.length
      ? arguments[jsonIndex + 1]
      : null;
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);

  final problems = <String>[];
  try {
    await _checkCaseA(root, problems);
    await _checkCaseB(root, problems);
    await _checkCaseC(root, problems);
    await _checkWholeFile(root, problems);
  } on Object catch (error, stack) {
    problems.add('对照本身没跑完：$error\n$stack');
  }

  _report['problems'] = problems;
  stdout.writeln('\n== 汇总 ==');
  stdout.writeln('落位 / 尺寸：${_report['placement']}');
  stdout.writeln('进出时刻：${_report['window']}');
  stdout.writeln('透明度（乘不是设）：${_report['alpha']}');
  stdout.writeln('边缘无脏边：${_report['edge']}');
  stdout.writeln('整片帧数：${_report['frames']}');
  if (problems.isEmpty) {
    stdout.writeln('结论：全部通过');
  } else {
    stdout.writeln('结论：不通过');
    for (final problem in problems) {
      stdout.writeln('  ✗ $problem');
    }
  }
  if (jsonPath != null) {
    File(jsonPath)
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_report));
  }
  exit(problems.isEmpty ? 0 : 1);
}

/// 每张贴纸 PNG 里墨迹相对图边的内缩（像素）——造图时算出来的同一份数，逐像素
/// 比对的期望值要用它（图边有一圈透明余量）。
final _inkInsets = <String, ({int x, int y})>{};

/// 造固定输入：纯色源片 + 两张带 alpha 的单帧 PNG。
Future<void> _prepareInputs(Directory root) async {
  final source = File('${root.path}/source.mp4');
  if (!source.existsSync()) {
    await _run([
      '-hide_banner',
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=$_background:s=${_width}x$_height:rate=$_fps:duration=$_seconds',
      // 带一条静音音轨：生产那条路在不勾声音类时会给视频流配 `-map 0:a`
      // （音轨原样复制），输入没有音轨就装配不起来。
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=48000:cl=stereo',
      '-shortest',
      // 宿主要看的是滤镜图的像素语义：编码损失压到最小（`-qp 0` 无损）。
      '-c:v',
      'libx264',
      '-qp',
      '0',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      source.path,
    ]);
  }
  for (final entry in _specsA.entries) {
    await _stickerPng(File('${root.path}/${entry.key}.png'), entry.value);
  }
  await _stickerPng(File('${root.path}/s2.png'), _specB);
}

/// 造一张「透明外框 + 实心半透明墨迹」的单帧 PNG（硬边，便于逐像素判）。
///
/// 墨迹 = `α` 的纯黄：alpha 用 `colorchannelmixer=aa=` **乘**上去（这正是输入
/// 侧「透明度是乘」的那一步）。
Future<void> _stickerPng(File file, _SheetSpec spec) async {
  if (file.existsSync()) return;
  final insetX = (spec.pngWidth * 0.15).round();
  final insetY = (spec.pngHeight * 0.25).round();
  _inkInsets[file.uri.pathSegments.last.split('.').first] = (
    x: insetX,
    y: insetY,
  );
  await _run([
    '-hide_banner',
    '-y',
    '-f',
    'lavfi',
    '-i',
    'color=c=black@0.0:s=${spec.pngWidth}x${spec.pngHeight},format=rgba',
    '-f',
    'lavfi',
    '-i',
    'color=c=yellow:s=${spec.pngWidth - insetX * 2}x'
        '${spec.pngHeight - insetY * 2},format=rgba',
    '-filter_complex',
    '[0:v][1:v]overlay=x=$insetX:y=$insetY:format=rgb,'
        'colorchannelmixer=aa=$_stickerAlpha',
    '-frames:v',
    '1',
    '-f',
    'image2',
    file.path,
  ]);
  // 输入侧事实先自己读回来：png 的墨迹色与 alpha 是后面混合算式的两个输入。
  final rgba = await _rawPixels(file.path, pixelFormat: 'rgba');
  final offset =
      ((spec.pngHeight ~/ 2) * spec.pngWidth + spec.pngWidth ~/ 2) * 4;
  _report['sticker_pixel'] = [
    rgba[offset],
    rgba[offset + 1],
    rgba[offset + 2],
    rgba[offset + 3],
  ];
}

/// **生产那一串命令行**（只换编码器为宿主 libx264）。
Future<List<String>> _productionArgs(
  Directory root,
  String name, {
  required Map<String, _SheetSpec> specs,
  FramingSelection? selection,
  List<LocalMirrorFragment> mirrorFragments = const [],
  bool globalMirrored = false,
  _AlphaMode? alphaMode,
}) async {
  final output = File('${root.path}/$name.mp4');
  final sheets = <CastSticker>[];
  for (final entry in specs.entries) {
    final bytes = File('${root.path}/${entry.key}.png').readAsBytesSync();
    sheets.add(
      CastSticker(
        imageBytesOf: () async => Uint8List.fromList(bytes),
        startMs: entry.value.startMs,
        endMs: entry.value.endMs,
        centerX: entry.value.centerX,
        centerY: entry.value.centerY,
        widthFraction: entry.value.widthFraction,
        heightFraction: entry.value.heightFraction,
      ),
    );
  }
  final request = CastRenderRequest(
    videoPath: '${root.path}/source.mp4',
    videoId: 'bench',
    duration: Duration(milliseconds: (_seconds * 1000).round()),
    choices: const CastRenderChoices(picture: true, sound: false),
    speedTier: CastSpeedTier.full,
    settings: CastRenderSettings(
      globalMirrored: globalMirrored,
      localMirrorEnabled: true,
    ),
    annotationFingerprint: 'bench',
    mirrorFragments: mirrorFragments,
    framingSelection: selection,
    stickers: sheets,
  );
  final stickerInputs = <CastStickerInput>[
    for (final (i, key) in specs.keys.indexed)
      CastStickerInput(
        sticker: request.stickers[i],
        // 这份宿主验收没备拍声轨，贴纸从 1 号输入起。
        sidecar: CastRenderSidecar(
          path: '${root.path}/$key.png',
          index: 1 + i,
        ),
      ),
  ];
  var args = buildCastRenderArguments(
    request: request,
    outputPath: output.path,
    staging: CastRenderStaging(stickers: stickerInputs),
  );
  // 宿主替换：编码器换成本机 libx264（**无损**，好让逐像素比对判得动）；滤镜图
  // 一个字不改。
  args = _hostEncoderArgs(args);
  switch (alphaMode) {
    case _AlphaMode.naive:
      // 反例图：第二路走默认的 `yuva420p`（色度 2×2 次采样）、混合走默认格式。
      args = _naiveAlphaArgs(args);
    case _AlphaMode.premultiplied:
      // 反例图：把直通 alpha 当预乘读（「设」而不是「乘」）。
      args = _premultipliedAlphaArgs(args);
    case null:
      break;
  }
  return args;
}

/// 用生产那一串命令行渲一份 mp4。
Future<File> _render(
  Directory root,
  String name, {
  required Map<String, _SheetSpec> specs,
  FramingSelection? selection,
  List<LocalMirrorFragment> mirrorFragments = const [],
  bool globalMirrored = false,
  _AlphaMode? alphaMode,
}) async {
  final args = await _productionArgs(
    root,
    name,
    specs: specs,
    selection: selection,
    mirrorFragments: mirrorFragments,
    globalMirrored: globalMirrored,
    alphaMode: alphaMode,
  );
  await _run(args);
  return File('${root.path}/$name.mp4');
}

/// **同一张滤镜图、产物换成一张 PNG**：宿主要看的「边缘有没有脏」必须绕开
/// h264 那层 4:2:0 量化（它本身就会糊一格、把两条路的差别压没）。滤镜图一个字
/// 不改，只在链尾挂一句 `select` 取第 [frame] 帧，丢掉音轨与 mp4 相关项。
Future<File> _renderStill(
  Directory root,
  String name, {
  required Map<String, _SheetSpec> specs,
  required int frame,
  FramingSelection? selection,
  List<LocalMirrorFragment> mirrorFragments = const [],
  bool globalMirrored = false,
  _AlphaMode? alphaMode,
}) async {
  final args = await _productionArgs(
    root,
    name,
    specs: specs,
    selection: selection,
    mirrorFragments: mirrorFragments,
    globalMirrored: globalMirrored,
    alphaMode: alphaMode,
  );
  final output = File('${root.path}/$name.png');
  final inputs = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-i') inputs.addAll(['-i', args[i + 1]]);
  }
  var graph = args[args.indexOf('-filter_complex') + 1];
  final last = graph.lastIndexOf('[vout]');
  graph =
      '${graph.substring(0, last)}[vpre]'
      ";[vpre]select='eq(n\\,$frame)'[vout]";
  await _run([
    '-hide_banner',
    '-y',
    ...inputs,
    '-filter_complex',
    graph,
    '-map',
    '[vout]',
    '-frames:v',
    '1',
    '-f',
    'image2',
    output.path,
  ]);
  return output;
}

/// 把生产参数里的硬编编码器换成本机无损 libx264。
List<String> _hostEncoderArgs(List<String> args) {
  final patched = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-c:v' && i + 1 < args.length && args[i + 1] != 'copy') {
      patched.addAll(['-c:v', 'libx264', '-qp', '0']);
      i++;
      continue;
    }
    if (args[i] == '-b:v') {
      // `-b:v` 与 `-qp 0` 同时给会打架：宿主这一跑不要码率这项。
      i++;
      continue;
    }
    patched.add(args[i]);
  }
  return patched;
}

/// 反例：把 overlay 的直通 alpha 当**预乘**读（「设」而不是「乘」）。
List<String> _premultipliedAlphaArgs(List<String> args) => [
  for (final arg in args)
    arg.replaceAll(
      'format=rgb:eof_action',
      'alpha=premultiplied:format=rgb:eof_action',
    ),
];

/// 反例：把第二路的 `format=rgba` 改成 `yuva420p`、把 overlay 的 `format=rgb`
/// 拿掉——就是「默认会被色度 2×2 次采样」的那条路。
List<String> _naiveAlphaArgs(List<String> args) {
  final patched = [...args];
  for (var i = 0; i < patched.length; i++) {
    patched[i] = patched[i]
        .replaceAll('format=rgba', 'format=yuva420p')
        .replaceAll('format=rgb:eof_action', 'eof_action');
  }
  return patched;
}

/// 一帧的像素读数（rgb24 / rgba）。
Future<Uint8List> _rawPixels(
  String path, {
  int? frame,
  String pixelFormat = 'rgb24',
}) async {
  // 像素是二进制：stdout 不做 UTF-8 解码（会当场炸在半截多字节序列上）。
  final result = await Process.run(
    'ffmpeg',
    [
      '-v',
      'error',
      '-i',
      path,
      if (frame != null) ...['-vf', "select='eq(n\\,$frame)'", '-vsync', '0'],
      '-frames:v',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      pixelFormat,
      '-',
    ],
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('读帧失败（$path 第 $frame 帧）：${result.stderr}');
  }
  return Uint8List.fromList(result.stdout as List<int>);
}

Future<({int width, int height})> _sizeOf(String path) async {
  final result = await Process.run('ffprobe', [
    '-v',
    'error',
    '-select_streams',
    'v:0',
    '-show_entries',
    'stream=width,height',
    '-of',
    'csv=p=0',
    path,
  ]);
  final parts = (result.stdout as String).trim().split(',');
  return (width: int.parse(parts[0]), height: int.parse(parts[1]));
}

/// 数一数整片解出多少帧（`-stats` 的 `frame=` 行）。
Future<int> _frameCount(String path) async {
  final result = await Process.run('ffmpeg', [
    '-hide_banner',
    '-v',
    'error',
    '-stats',
    '-i',
    path,
    '-f',
    'null',
    '-',
  ]);
  final matches = RegExp(r'frame=\s*(\d+)').allMatches('${result.stderr}');
  return matches.isEmpty ? -1 : int.parse(matches.last.group(1)!);
}

Future<void> _run(List<String> args) async {
  final result = await Process.run('ffmpeg', args);
  if (result.exitCode != 0) {
    throw StateError(
      'ffmpeg 返回 ${result.exitCode}：${args.join(' ')}\n${result.stderr}',
    );
  }
}

// ── 用例 C：细节墨迹上的「乘」与「边缘无脏边」 ──────────────────────────────

/// 一跑里 α 的两条**反例**路径（生产那一跑之外）：
///
/// - [naive]：第二路走默认的 `yuva420p`、混合走默认格式——规格里那句「默认会被
///   色度 2×2 次采样、边缘会脏」；
/// - [premultiplied]：把直通 alpha 当**预乘**读（`alpha=premultiplied`）——这就是
///   「设」而不是「乘」的那条错路。
enum _AlphaMode { naive, premultiplied }

/// 按 PNG 自己的像素算「α 乘上去」的期望，并分三块报偏差：墨迹内部（从墨迹
/// 包围盒内缩 2 像素）、墨迹外沿一圈（2 像素宽）、以及 alpha 为 0 的那一圈。
///
/// 期望值来自 **PNG 自己的像素**（`α·PNG + (1−α)·背景`），不是脚本假设的颜色
/// ——于是「乘」这条算式本身是被检验的对象。
Future<
  ({
    double deepMax,
    double deepMean,
    double nearEdgeMax,
    double nearEdgeMean,
    double outsideMax,
  })
>
_blendAgainstSheet(
  Uint8List frame,
  ({int width, int height}) size,
  String sheet,
  _SheetSpec spec,
  Directory root, {
  FramingSelection? selection,
}) async {
  final pngSize = await _sizeOf('${root.path}/$sheet.png');
  final pngPixels = await _rawPixels(
    '${root.path}/$sheet.png',
    pixelFormat: 'rgba',
  );
  final rect = _expectedRect(spec, size: size, selection: selection);
  final background = _backgroundSample(frame, size);

  // **观测到的墨迹掩码**（成片里与背景差得多的像素）：分类按它算，不按期望
  // 几何——期望几何与成片之间本来就可能差一个像素（缩放取整），拿它当边界量
  // 「边缘脏不脏」会把取整误差当成脏边。
  final inkMask = <bool>[];
  for (var y = rect.top.floor() - 2; y <= rect.bottom + 2; y++) {
    for (var x = rect.left.floor() - 2; x <= rect.right + 2; x++) {
      final inside = x >= 0 && x < size.width && y >= 0 && y < size.height;
      final offset = inside ? (y * size.width + x) * 3 : -1;
      final isInk =
          inside &&
          [
                (frame[offset] - background.$1).abs(),
                (frame[offset + 1] - background.$2).abs(),
                (frame[offset + 2] - background.$3).abs(),
              ].reduce((a, b) => a > b ? a : b) >
              30;
      inkMask.add(isInk);
    }
  }
  final gridWidth = rect.right.floor() + 2 - (rect.left.floor() - 2) + 1;
  bool isInk(int x, int y) {
    final localX = x - (rect.left.floor() - 2);
    final localY = y - (rect.top.floor() - 2);
    if (localX < 0 || localY < 0) return false;
    final index = localY * gridWidth + localX;
    if (index < 0 || index >= inkMask.length) return false;
    return inkMask[index];
  }

  var deepMax = 0.0;
  var deepSum = 0.0;
  var deepCount = 0;
  var nearEdgeMax = 0.0;
  var nearEdgeSum = 0.0;
  var nearEdgeCount = 0;
  var outsideMax = 0.0;
  const nearEdgeBand = 3;
  for (var y = rect.top.floor() - 2; y <= rect.bottom + 2; y++) {
    for (var x = rect.left.floor() - 2; x <= rect.right + 2; x++) {
      if (x < 0 || x >= size.width || y < 0 || y >= size.height) continue;
      final inked = isInk(x, y);
      final pngX = (((x - rect.left) / rect.width) * pngSize.width)
          .floor()
          .clamp(0, pngSize.width - 1);
      final pngY = (((y - rect.top) / rect.height) * pngSize.height)
          .floor()
          .clamp(0, pngSize.height - 1);
      final pngOffset = (pngY * pngSize.width + pngX) * 4;
      final alpha = pngPixels[pngOffset + 3] / 255.0;
      final offset = (y * size.width + x) * 3;
      var deviation = 0.0;
      for (var channel = 0; channel < 3; channel++) {
        final expected =
            alpha * pngPixels[pngOffset + channel] +
            (1 - alpha) *
                [background.$1, background.$2, background.$3][channel];
        final value = (frame[offset + channel] - expected).abs();
        if (value > deviation) deviation = value;
      }
      if (!inked) {
        // 墨迹之外（离观测到的墨迹边 ≥ 1 像素）：应当就是背景。
        var touchesInk = false;
        for (var dy = -1; dy <= 1 && !touchesInk; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (isInk(x + dx, y + dy)) {
              touchesInk = true;
              break;
            }
          }
        }
        if (!touchesInk && deviation > outsideMax) outsideMax = deviation;
        continue;
      }
      var nearBoundary = false;
      for (var dy = -nearEdgeBand; dy <= nearEdgeBand && !nearBoundary; dy++) {
        for (var dx = -nearEdgeBand; dx <= nearEdgeBand; dx++) {
          if (!isInk(x + dx, y + dy)) {
            nearBoundary = true;
            break;
          }
        }
      }
      if (nearBoundary) {
        if (deviation > nearEdgeMax) nearEdgeMax = deviation;
        nearEdgeSum += deviation;
        nearEdgeCount++;
      } else {
        if (deviation > deepMax) deepMax = deviation;
        deepSum += deviation;
        deepCount++;
      }
    }
  }
  return (
    deepMax: deepMax,
    deepMean: deepCount == 0 ? 0.0 : deepSum / deepCount,
    nearEdgeMax: nearEdgeMax,
    nearEdgeMean: nearEdgeCount == 0 ? 0.0 : nearEdgeSum / nearEdgeCount,
    outsideMax: outsideMax,
  );
}

/// 用例 C：透明度是**乘**不是设，且走的是**全分辨率 alpha** 的那条路。
///
/// 用未取景那一跑里那张**纯色**贴纸（纯色让逐像素比对不受采样错位影响）：
/// - 生产：墨迹内部与「α·PNG + (1−α)·背景」一致（容差内）；
/// - 「设」的反例（预乘）：内部明显对不上——这条比对因此判得出「乘不是设」；
/// - 「默认次采样」的反例（yuva420p + 默认混合）：外沿一圈的平均偏差更大
///   （记读数；终段 `format=yuv420p` 本身也会在边缘糊一格，故这条是弱判据）。
Future<void> _checkCaseC(Directory root, List<String> problems) async {
  const spec = {
    's0': _SheetSpec(
      startMs: 500,
      endMs: 1500,
      centerX: 0.25,
      centerY: 0.25,
      widthFraction: 0.2,
      heightFraction: 0.12,
    ),
  };
  final product = await _renderStill(root, 'caseC', specs: spec, frame: 20);
  final premultiplied = await _renderStill(
    root,
    'caseC_premultiplied',
    specs: spec,
    frame: 20,
    alphaMode: _AlphaMode.premultiplied,
  );
  final naive = await _renderStill(
    root,
    'caseC_naive',
    specs: spec,
    frame: 20,
    alphaMode: _AlphaMode.naive,
  );
  final size = await _sizeOf(product.path);
  final frame = await _rawPixels(product.path);
  final premultipliedFrame = await _rawPixels(premultiplied.path);
  final naiveFrame = await _rawPixels(naive.path);

  final reading = await _blendAgainstSheet(
    frame,
    size,
    's0',
    spec['s0']!,
    root,
  );
  final premultipliedReading = await _blendAgainstSheet(
    premultipliedFrame,
    size,
    's0',
    spec['s0']!,
    root,
  );
  final naiveReading = await _blendAgainstSheet(
    naiveFrame,
    size,
    's0',
    spec['s0']!,
    root,
  );
  _report['alpha'] = {
    'formula': 'α·PNG像素 + (1−α)·背景色（α 逐像素读自 PNG 自己）',
    'production_deep_max': reading.deepMax,
    'production_deep_mean': reading.deepMean,
    'production_outside_max': reading.outsideMax,
    'premultiplied_deep_max': premultipliedReading.deepMax,
  };
  _report['edge'] = {
    'note':
        '静帧（同一张滤镜图、产物换 PNG）上量，绕开 h264 那层 4:2:0 量化；'
        '「近边」= 观测到的墨迹边界内 3 像素以内那一圈。**这不是硬判据**：'
        '产物链尾的 `format=yuv420p` 自己就会在边缘糊一格（两条路都糊），'
        '所以这一圈只留读数；「全分辨率 alpha」由墨迹内部逐像素对上 + 滤镜图'
        '形状（rgba 进、rgb 混合）两条钉住',
    'production_near_edge_mean': reading.nearEdgeMean,
    'production_near_edge_max': reading.nearEdgeMax,
    'naive_yuva420p_near_edge_mean': naiveReading.nearEdgeMean,
    'naive_yuva420p_near_edge_max': naiveReading.nearEdgeMax,
  };
  if (reading.deepMax > 12) {
    problems.add(
      '墨迹内部与「α 逐像素乘上去」的算式差 ${reading.deepMax.toStringAsFixed(1)}'
      '（容差 12）——透明度不是乘出来的',
    );
  }
  if (reading.outsideMax > 20) {
    problems.add(
      '墨迹之外与背景色差 ${reading.outsideMax.toStringAsFixed(1)}（容差 20）'
      '——贴纸漏到了它不该在的地方',
    );
  }
  // 滤镜图形状：「全分辨率 alpha」这条路必须真的是 `rgba` 进、`rgb` 里混合，
  // 且单帧输入不配循环、不取最短（规格里那三条硬口径）。
  final probeArgs = await _productionArgs(root, 'caseC_probe', specs: spec);
  final graph = probeArgs[probeArgs.indexOf('-filter_complex') + 1];
  for (final required in const [
    'format=rgba',
    ':format=rgb:',
    'eof_action=repeat',
    'fps=$_fps',
  ]) {
    if (!graph.contains(required)) {
      problems.add('滤镜图里少了「$required」——第二路的 alpha 那条路不对');
    }
  }
  for (final forbidden in const ['-loop', '-shortest', 'yuva420p']) {
    if (graph.contains(forbidden)) {
      problems.add('滤镜图里出现了不该有的「$forbidden」');
    }
  }
  if (premultipliedReading.deepMax <= reading.deepMax + 20) {
    problems.add(
      '「设」（预乘）那条反例的偏差没有明显更大'
      '（${premultipliedReading.deepMax.toStringAsFixed(1)} vs '
      '${reading.deepMax.toStringAsFixed(1)}）——这条比对判不出「乘不是设」',
    );
  }
}

// ── 用例 A：未取景、未镜像，两条贴纸各自的时间窗与落位 ──────────────────────

const Map<String, _SheetSpec> _specsA = {
  's0': _SheetSpec(
    startMs: 500,
    endMs: 1500,
    centerX: 0.25,
    centerY: 0.25,
    widthFraction: 0.2,
    heightFraction: 0.12,
  ),
  's1': _SheetSpec(
    startMs: 2500,
    endMs: 3500,
    centerX: 0.7,
    centerY: 0.7,
    widthFraction: 0.2,
    heightFraction: 0.12,
  ),
};

Future<void> _checkCaseA(Directory root, List<String> problems) async {
  await _prepareInputs(root);
  final product = await _render(root, 'caseA', specs: _specsA);
  final size = await _sizeOf(product.path);
  final placement = <Object?>[];
  final window = <Object?>[];

  // 第 20 帧（0.667s）：只有 s0 在；第 90 帧（3.0s）：只有 s1 在。
  for (final probe in const [
    (frame: 20, visible: 's0', hidden: 's1'),
    (frame: 90, visible: 's1', hidden: 's0'),
  ]) {
    final pixels = await _rawPixels(product.path, frame: probe.frame);
    for (final entry in _specsA.entries) {
      final rect = _expectedInkRect(entry.key, entry.value, size: size);
      final deviation = _deviationAt(pixels, size, rect.center);
      final present = deviation > 30;
      placement.add({
        'frame': probe.frame,
        'sheet': entry.key,
        'expected_rect': rect.toList(),
        'center_deviation': deviation,
        'present': present,
      });
      if (entry.key == probe.visible && !present) {
        problems.add(
          '第 ${probe.frame} 帧：${entry.key} 应可见，但落位中心与背景无差别'
          '（期望矩形 $rect）',
        );
      }
      if (entry.key == probe.hidden && present) {
        problems.add('第 ${probe.frame} 帧：${entry.key} 不该可见');
      }
    }
    // 墨迹包围盒与期望矩形逐边比。
    final visibleSpec = _specsA[probe.visible]!;
    final expected = _expectedInkRect(probe.visible, visibleSpec, size: size);
    final ink = _inkBounds(
      pixels,
      size,
      expected.inflate(6),
      _backgroundSample(pixels, size),
    );
    (placement.last as Map<String, Object?>)['ink_bounds'] = ink?.toList();
    for (final (label, actual, want) in [
      ('左', ink?.left, expected.left),
      ('上', ink?.top, expected.top),
      ('右', ink?.right, expected.right),
      ('下', ink?.bottom, expected.bottom),
    ]) {
      if (actual == null) {
        problems.add('第 ${probe.frame} 帧：${probe.visible} 找不到墨迹包围盒');
        continue;
      }
      if ((actual - want).abs() > 3) {
        problems.add(
          '第 ${probe.frame} 帧：${probe.visible} 的$label边在 $actual，'
          '期望 $want（容差 3px）',
        );
      }
    }
  }

  // 半开时间窗：s0 的窗 [500, 1500) → 首帧 15、末帧 44；14 与 45 都不该有。
  final s0 = _specsA['s0']!;
  final firstFrame = (s0.startMs / 1000 * _fps).ceil();
  final lastFrame = (s0.endMs / 1000 * _fps).ceil() - 1;
  for (final probe in [
    (frame: firstFrame - 1, expect: false, note: '窗前一帧'),
    (frame: firstFrame, expect: true, note: '窗的第一帧'),
    (frame: lastFrame, expect: true, note: '窗的最后一帧'),
    (frame: lastFrame + 1, expect: false, note: '窗的终点那一帧（半开：算窗外）'),
  ]) {
    final pixels = await _rawPixels(product.path, frame: probe.frame);
    final rect = _expectedInkRect('s0', s0, size: size);
    final deviation = _deviationAt(pixels, size, rect.center);
    final present = deviation > 30;
    window.add({
      'frame': probe.frame,
      'note': probe.note,
      'expected_present': probe.expect,
      'present': present,
    });
    if (present != probe.expect) {
      problems.add(
        '${probe.note}（第 ${probe.frame} 帧）：应${probe.expect ? '可见' : '不可见'}，'
        '实际${present ? '可见' : '不可见'}——进出时刻不在半开口径上',
      );
    }
  }

  _report['placement'] = placement;
  _report['window'] = window;
}

// ── 用例 B：取景 + 局部镜像片段跨过贴纸窗（窗口换算与随面翻转） ──────────────

const _specB = _SheetSpec(
  startMs: 1500,
  endMs: 3500,
  centerX: 0.3,
  centerY: 0.5,
  widthFraction: 0.2,
  heightFraction: 0.15,
);

Future<void> _checkCaseB(Directory root, List<String> problems) async {
  const selection = FramingSelection(
    left: 0.1,
    top: 0.1,
    right: 0.9,
    bottom: 0.9,
  );
  const fragment = LocalMirrorFragment(startMs: 2000, endMs: 3000);
  final product = await _render(
    root,
    'caseB',
    specs: const {'s2': _specB},
    selection: selection,
    mirrorFragments: const [fragment],
  );
  final size = await _sizeOf(product.path);
  final readings = <Object?>[];
  // 第 50 帧 = 1.667s（片段外，不翻）；第 75 帧 = 2.5s（片段内，翻）。
  for (final probe in const [
    (frame: 50, mirrored: false),
    (frame: 75, mirrored: true),
  ]) {
    final expected = _expectedInkRect(
      's2',
      _specB,
      size: size,
      selection: selection,
      mirrored: probe.mirrored,
    );
    final pixels = await _rawPixels(product.path, frame: probe.frame);
    final ink = _inkBounds(
      pixels,
      size,
      expected.inflate(6),
      _backgroundSample(pixels, size),
    );
    readings.add({
      'frame': probe.frame,
      'mirrored': probe.mirrored,
      'expected_rect': expected.toList(),
      'ink_bounds': ink?.toList(),
    });
    if (ink == null) {
      problems.add('第 ${probe.frame} 帧：取景 + 镜像下找不到贴纸墨迹');
      continue;
    }
    for (final (label, actual, want) in [
      ('左', ink.left, expected.left),
      ('上', ink.top, expected.top),
      ('右', ink.right, expected.right),
      ('下', ink.bottom, expected.bottom),
    ]) {
      if ((actual - want).abs() > 3) {
        problems.add(
          '第 ${probe.frame} 帧：${probe.mirrored ? '片段内（翻）' : '片段外（不翻）'}'
          '时贴纸的$label边在 $actual，期望 $want（容差 3px）',
        );
      }
    }
  }
  _report['framing_mirror'] = {
    'output_size': [size.width, size.height],
    'readings': readings,
  };
}

// ── 整片：帧数没掉（网格没有整段错位） ─────────────────────────────────────

Future<void> _checkWholeFile(Directory root, List<String> problems) async {
  final product = File('${root.path}/caseA.mp4');
  final frames = await _frameCount(product.path);
  final expected = (_seconds * _fps).round();
  _report['frames'] = {'decoded': frames, 'expected': expected};
  if ((frames - expected).abs() > 1) {
    problems.add('整片解出 $frames 帧，期望 $expected（容差 1）');
  }
}

// ── 期望值与像素读数的小工具 ────────────────────────────────────────────

class _Rect {
  const _Rect(this.left, this.top, this.right, this.bottom);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  ({int x, int y}) get center =>
      (x: ((left + right) / 2).round(), y: ((top + bottom) / 2).round());

  _Rect inflate(double amount) =>
      _Rect(left - amount, top - amount, right + amount, bottom + amount);

  List<double> toList() => [left, top, right, bottom];
}

/// **期望的墨迹矩形**：贴纸图矩形再按 PNG 自己的透明余量往里收（图边那圈不是
/// 墨迹）。逐像素比对与包围盒比对都拿它做期望。
_Rect _expectedInkRect(
  String sheet,
  _SheetSpec spec, {
  required ({int width, int height}) size,
  FramingSelection? selection,
  bool mirrored = false,
}) {
  final image = _expectedRect(
    spec,
    size: size,
    selection: selection,
    mirrored: mirrored,
  );
  final insets = _inkInsets[sheet]!;
  return _Rect(
    image.left + insets.x / spec.pngWidth * image.width,
    image.top + insets.y / spec.pngHeight * image.height,
    image.right - insets.x / spec.pngWidth * image.width,
    image.bottom - insets.y / spec.pngHeight * image.height,
  );
}

/// **独立算出的期望矩形**：贴纸中心按取景窗口换算、镜像时横向取反，尺寸取
/// 帧的比例（不随取景缩放）——与脚本声明的那份归一化事实一一对应。
_Rect _expectedRect(
  _SheetSpec spec, {
  required ({int width, int height}) size,
  FramingSelection? selection,
  bool mirrored = false,
}) {
  final windowWidth = selection?.width ?? 1.0;
  final windowHeight = selection?.height ?? 1.0;
  final u0 = selection == null
      ? spec.centerX
      : (spec.centerX - selection.left) / windowWidth;
  final v0 = selection == null
      ? spec.centerY
      : (spec.centerY - selection.top) / windowHeight;
  final u = mirrored ? 1 - u0 : u0;
  final width = spec.widthFraction * size.width;
  final height = spec.heightFraction * size.height;
  final centerX = u * size.width;
  final centerY = v0 * size.height;
  return _Rect(
    centerX - width / 2,
    centerY - height / 2,
    centerX + width / 2,
    centerY + height / 2,
  );
}

/// 成片里那片纯色区域的实测底色（取左上角一块的众数式均值：纯色帧里处处一样）。
(int, int, int) _backgroundSample(
  Uint8List pixels,
  ({int width, int height}) size,
) {
  var red = 0;
  var green = 0;
  var blue = 0;
  var count = 0;
  for (var y = 1; y < 5; y++) {
    for (var x = 1; x < 5; x++) {
      final offset = (y * size.width + x) * 3;
      red += pixels[offset];
      green += pixels[offset + 1];
      blue += pixels[offset + 2];
      count++;
    }
  }
  return (red ~/ count, green ~/ count, blue ~/ count);
}

/// 某点与背景色的最大通道差（判「这里有没有墨迹」）。
double _deviationAt(
  Uint8List pixels,
  ({int width, int height}) size,
  ({int x, int y}) point,
) {
  final offset = (point.y * size.width + point.x) * 3;
  final background = _backgroundSample(pixels, size);
  return [
    (pixels[offset] - background.$1).abs(),
    (pixels[offset + 1] - background.$2).abs(),
    (pixels[offset + 2] - background.$3).abs(),
  ].reduce((a, b) => a > b ? a : b).toDouble();
}

/// 墨迹包围盒（在 [search] 里找与背景差得多的像素）。
_Rect? _inkBounds(
  Uint8List pixels,
  ({int width, int height}) size,
  _Rect search,
  (int, int, int) background,
) {
  double? left;
  double? top;
  double? right;
  double? bottom;
  for (var y = search.top.floor(); y <= search.bottom; y++) {
    if (y < 0 || y >= size.height) continue;
    for (var x = search.left.floor(); x <= search.right; x++) {
      if (x < 0 || x >= size.width) continue;
      final offset = (y * size.width + x) * 3;
      final deviation = [
        (pixels[offset] - background.$1).abs(),
        (pixels[offset + 1] - background.$2).abs(),
        (pixels[offset + 2] - background.$3).abs(),
      ].reduce((a, b) => a > b ? a : b);
      if (deviation <= 30) continue;
      left = left == null || x < left ? x.toDouble() : left;
      right = right == null || x > right ? x.toDouble() : right;
      top = top == null || y < top ? y.toDouble() : top;
      bottom = bottom == null || y > bottom ? y.toDouble() : bottom;
    }
  }
  if (left == null) return null;
  return _Rect(left, top!, right!, bottom!);
}
