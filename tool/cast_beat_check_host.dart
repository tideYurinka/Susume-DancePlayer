/// **数拍层的宿主对照**（`#30` 的验收入口）：拿**生产那一串命令行**
/// （`lib/cast/cast_render_plan.dart`，只把编码器换成本机 libx264）交给本机
/// ffmpeg 跑一遍，再从产物里逐帧读像素核对三件事：
///
/// 1. **落位**：数拍那一行在成片帧里的**像素矩形**，与声明的归一化中心 + 尺寸
///    分数独立算出的期望逐边偏差 ≤ 3 像素——「电视上的位置与手机同一时刻一致」
///    在这里就是这条算术（手机侧那一份换算由
///    `test/player/cast_beat_placement_test.dart` 直测）；
/// 2. **逐拍时间窗**：一格一张同尺寸 PNG 按**各自时长**进 `-f concat` 序列，
///    半开窗的进出落在声明的时刻上（两侧各多查一帧）；
/// 3. **一像素都不多的动画**：不显示的格是**全透明**的（画面上那块底色原样），
///    且序列不会提前结束（末格的时长生效）。
///
/// 真机上那份（字体、观感、与手机逐帧比对）只能真机看：宿主这一份验的是**滤镜
/// 图与产物的像素语义**，与平台无关。数拍的**文字光栅化**（Flutter 那一条）由
/// `test/player/cast_beat_sheet_test.dart` 钉住，本脚本用几何色块代替字形——
/// 这里要判的是时间与位置。
///
/// 用法（仓库根目录）：
///   dart run tool/cast_beat_check_host.dart [--out /tmp/cast_beat] [--json 路径]
///
/// 退出码 0 = 上面的硬判据全过；非 0 = 有读数不成立。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:dance_learning_app/cast/cast_beat_gate.dart'
    show castBeatSlidesContent;
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';

/// 固定输入：4 秒 / 320×180 / 30fps 的纯色源片 + 一格一秒的数拍层。
const int _fps = 30;
const int _width = 320;
const int _height = 180;
const double _seconds = 4;

/// 源片底色（成片里读数一律取成片自己的实测值）。
const String _background = '0x102030';

/// 一格画布的像素尺寸（四格同尺寸——图像序列是一条流的前提）。
const int _cellWidth = 64;
const int _cellHeight = 32;

/// 声明的归一化落位（与手机换算出来的是同一组数）。
const double _centerX = 0.5;
const double _centerY = 0.25;

/// 一跑的读数（留档用）。
final _report = <String, Object?>{};

Future<void> main(List<String> arguments) async {
  final outIndex = arguments.indexOf('--out');
  final root = Directory(
    outIndex >= 0 && outIndex + 1 < arguments.length
        ? arguments[outIndex + 1]
        : '/tmp/cast_beat_check',
  );
  final jsonIndex = arguments.indexOf('--json');
  final jsonPath = jsonIndex >= 0 && jsonIndex + 1 < arguments.length
      ? arguments[jsonIndex + 1]
      : null;
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);

  final problems = <String>[];
  try {
    await _runCase(root, problems);
  } on Object catch (error, stack) {
    problems.add('对照本身没跑完：$error\n$stack');
  }

  _report['problems'] = problems;
  stdout.writeln('\n== 汇总 ==');
  stdout.writeln('落位 / 尺寸：${_report['placement']}');
  stdout.writeln('逐拍时间窗：${_report['window']}');
  stdout.writeln('不显示的格：${_report['transparent']}');
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

/// 四格：红 [0,1)、绿 [1,2)、蓝 [2,3)、**不显示** [3,4)。
const List<({int startMs, int endMs, String? color})> _cells = [
  (startMs: 0, endMs: 1000, color: '0xff0000'),
  (startMs: 1000, endMs: 2000, color: '0x00ff00'),
  (startMs: 2000, endMs: 3000, color: '0x0000ff'),
  (startMs: 3000, endMs: 4000, color: null),
];

Future<void> _runCase(Directory root, List<String> problems) async {
  final source = '${root.path}/source.mp4';
  await _ffmpeg(<String>[
    '-y',
    '-v',
    'error',
    '-f',
    'lavfi',
    '-i',
    'color=c=$_background:s=${_width}x$_height:d=$_seconds:r=$_fps',
    '-f',
    'lavfi',
    '-i',
    'anullsrc=channel_layout=stereo:sample_rate=48000',
    '-shortest',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-c:a',
    'aac',
    source,
  ]);

  // 逐格 PNG：颜色块或不显示（全透明）。生产里这两样由
  // `player/cast_beat_sheet.dart` 画，本脚本只造同尺寸的几何块。
  final paths = <String>[];
  for (var i = 0; i < _cells.length; i++) {
    final path = '${root.path}/beat$i.png';
    final color = _cells[i].color;
    await _ffmpeg(<String>[
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      color == null
          ? 'color=c=black@0.0:s=${_cellWidth}x$_cellHeight,format=rgba'
          : 'color=c=$color:s=${_cellWidth}x$_cellHeight,format=rgba',
      '-frames:v',
      '1',
      path,
    ]);
    paths.add(path);
  }

  final rows = <CastBeatCountRow>[
    for (var i = 0; i < _cells.length; i++)
      CastBeatCountRow(
        startMs: _cells[i].startMs,
        endMs: _cells[i].endMs,
        // 文字内容在这里不重要（本脚本用几何块），占位给一个真值对象。
        text: _cells[i].color == null
            ? null
            : CastBeatCountText(eightCount: '1', beatCount: '${i + 1}'),
      ),
  ];
  final listPath = '${root.path}/beats.txt';
  File(listPath).writeAsStringSync(
    castBeatSlidesContent(rows: rows, paths: paths),
  );

  final overlay = CastBeatCountOverlay(
    rows: rows,
    centerX: _centerX,
    centerY: _centerY,
    widthFraction: _cellWidth / _width,
    heightFraction: _cellHeight / _height,
    imageBytesOf: (index) async => File(paths[index]).readAsBytesSync(),
  );
  final output = '${root.path}/out.mp4';
  final arguments = buildCastRenderArguments(
    request: CastRenderRequest(
      videoPath: source,
      videoId: 'host-check',
      duration: const Duration(seconds: 4),
      choices: const CastRenderChoices(picture: true, sound: false),
      speedTier: CastSpeedTier.full,
      settings: const CastRenderSettings(),
      annotationFingerprint: 'host-check',
      beatOverlay: overlay,
    ),
    outputPath: output,
    // 宿主验收只备了数拍序列这一样边车（源片 0 号、它是 1 号输入）。
    staging: CastRenderStaging(
      beatSlides: CastBeatSlidesInput(
        overlay: overlay,
        sidecar: CastRenderSidecar(path: listPath, index: 1),
      ),
    ),
  );
  stdout.writeln('== 生产命令行（只换编码器）==');
  stdout.writeln(arguments.join(' '));
  await _ffmpeg(_withHostEncoder(arguments));

  await _checkPlacement(output, problems);
  await _checkWindows(output, problems);
  _report['frames'] = await _frameCount(output);
  if (_report['frames'] != (_seconds * _fps).round()) {
    problems.add('成片帧数 ${_report['frames']} ≠ 源片 ${(_seconds * _fps).round()}');
  }
  _report['transparent'] = '不在场的格按全透明核过（见 time window 读数）';
}

/// 把生产命令行里的编码器换成本机的 libx264（宿主没有 mediacodec）。
List<String> _withHostEncoder(List<String> arguments) {
  final out = <String>[...arguments];
  final index = out.indexOf('-c:v');
  if (index >= 0) out[index + 1] = 'libx264';
  // 硬编的显式码率对无损对照没意义，换成 crf 0（只改编码参数，不改图）。
  final bitrate = out.indexOf('-b:v');
  if (bitrate >= 0) {
    out[bitrate] = '-crf';
    out[bitrate + 1] = '0';
  }
  return out;
}

Future<void> _checkPlacement(String output, List<String> problems) async {
  // 红格那一秒里取一帧（帧号 15 = 0.5s，避开进出那一帧）。
  final frame = await _frameByIndex(output, 15);
  final box = _inkBox(frame, _backgroundRgb);
  if (box == null) {
    problems.add('红格那一秒的画面里没有数拍层像素');
    return;
  }
  final expectedCenterX = _centerX * _width;
  final expectedCenterY = _centerY * _height;
  final expectedWidth = _cellWidth.toDouble();
  final expectedHeight = _cellHeight.toDouble();
  final centerX = (box.left + box.right) / 2;
  final centerY = (box.top + box.bottom) / 2;
  final width = (box.right - box.left).toDouble();
  final height = (box.bottom - box.top).toDouble();
  final reading = '中心 (${centerX.toStringAsFixed(1)}, '
      '${centerY.toStringAsFixed(1)}) 期望 '
      '(${expectedCenterX.toStringAsFixed(1)}, '
      '${expectedCenterY.toStringAsFixed(1)})；'
      '尺寸 ${width.toStringAsFixed(1)}×${height.toStringAsFixed(1)} 期望 '
      '${expectedWidth.toStringAsFixed(1)}×${expectedHeight.toStringAsFixed(1)}';
  _report['placement'] = reading;
  stdout.writeln('落位：$reading');
  if ((centerX - expectedCenterX).abs() > 3) {
    problems.add('横向中心偏差 ${(centerX - expectedCenterX).abs()}px：$reading');
  }
  if ((centerY - expectedCenterY).abs() > 3) {
    problems.add('纵向中心偏差 ${(centerY - expectedCenterY).abs()}px：$reading');
  }
  if ((width - expectedWidth).abs() > 3) {
    problems.add('宽度偏差 ${(width - expectedWidth).abs()}px：$reading');
  }
  if ((height - expectedHeight).abs() > 3) {
    problems.add('高度偏差 ${(height - expectedHeight).abs()}px：$reading');
  }
}

Future<void> _checkWindows(String output, List<String> problems) async {
  // 半开窗：每一格的起点那一帧属于它自己，**前一帧仍属于上一格**——故探针
  // 一律按**帧号**取（`select=eq(n,…)`，不靠时间定位：按时间取帧在帧网格的
  // 边界上会因取整落到下一帧，读出来的就是「早一帧」的假象）。
  final probes = <({int frame, String expect})>[
    (frame: 0, expect: 'red'),
    (frame: 15, expect: 'red'), // 0.5s
    (frame: 29, expect: 'red'), // 窗内最后一帧（0.9667s）
    (frame: 30, expect: 'green'), // 窗的第一帧（1.0s）
    (frame: 59, expect: 'green'), // 终点前最后一帧（1.9667s）
    (frame: 60, expect: 'blue'), // 终点那一帧（2.0s）已经不是 green
    (frame: 89, expect: 'blue'),
    (frame: 90, expect: 'none'), // 不显示的格：那一块像素原样
    (frame: 117, expect: 'none'),
    (frame: 119, expect: 'none'), // 末格时长生效：序列不提前结束
  ];
  final readings = <String>[];
  for (final probe in probes) {
    final frame = await _frameByIndex(output, probe.frame);
    final actual = _dominantInk(frame);
    readings.add('帧 ${probe.frame} → $actual（期望 ${probe.expect}）');
    if (actual != probe.expect) {
      problems.add('第 ${probe.frame} 帧是 $actual，期望 ${probe.expect}');
    }
  }
  _report['window'] = readings;
  stdout.writeln('逐拍时间窗：');
  for (final line in readings) {
    stdout.writeln('  $line');
  }
}

/// 源片底色的 rgb 三元组（在成片里实测）。
const List<int> _backgroundRgb = [0x0e, 0x1d, 0x2d];

(int, int, int) _rgbAt(_Frame frame, int x, int y) {
  final offset = (y * frame.width + x) * 3;
  return (
    frame.rgb[offset],
    frame.rgb[offset + 1],
    frame.rgb[offset + 2],
  );
}

/// 与底色明显不同（阈值 24）即算「数拍层像素」。
bool _isInk(_Frame frame, int x, int y) {
  final (r, g, b) = _rgbAt(frame, x, y);
  return (r - _backgroundRgb[0]).abs() > 24 ||
      (g - _backgroundRgb[1]).abs() > 24 ||
      (b - _backgroundRgb[2]).abs() > 24;
}

({int left, int top, int right, int bottom})? _inkBox(_Frame frame, List<int> _) {
  int? left, top, right, bottom;
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      if (!_isInk(frame, x, y)) continue;
      left = left == null || x < left ? x : left;
      right = right == null || x > right ? x : right;
      top = top == null || y < top ? y : top;
      bottom = bottom == null || y > bottom ? y : bottom;
    }
  }
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }
  return (left: left, top: top, right: right, bottom: bottom);
}

/// 数拍层像素的主色（红 / 绿 / 蓝 / none）。
String _dominantInk(_Frame frame) {
  var red = 0;
  var green = 0;
  var blue = 0;
  for (var y = 0; y < frame.height; y++) {
    for (var x = 0; x < frame.width; x++) {
      if (!_isInk(frame, x, y)) continue;
      final (r, g, b) = _rgbAt(frame, x, y);
      if (r > g && r > b) {
        red++;
      } else if (g > r && g > b) {
        green++;
      } else if (b > r && b > g) {
        blue++;
      }
    }
  }
  if (red == 0 && green == 0 && blue == 0) return 'none';
  if (red >= green && red >= blue) return 'red';
  if (green >= blue) return 'green';
  return 'blue';
}

class _Frame {
  const _Frame({
    required this.width,
    required this.height,
    required this.rgb,
  });

  final int width;
  final int height;
  final Uint8List rgb;
}

/// 按**帧号**取一帧（`select=eq(n,…)`，与时间定位无关——帧网格的边界上按时间
/// 取帧会有取整歧义）。
Future<_Frame> _frameByIndex(String path, int index) async {
  // 原始像素走 stdout：**不能按 UTF-8 解码**（stdoutEncoding: null）。
  final result = await Process.run(
    'ffmpeg',
    <String>[
      '-v',
      'error',
      '-i',
      path,
      '-vf',
      'select=eq(n\\,$index)',
      // 宿主基线是 ffmpeg 4.4，`-fps_mode` 还没有（5.1 才加），用等价的
      // `-vsync 0`。
      '-vsync',
      '0',
      '-frames:v',
      '1',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgb24',
      '-',
    ],
    stdoutEncoding: null,
  );
  if (result.exitCode != 0) {
    throw StateError('取第 $index 帧失败：${result.stderr}');
  }
  final bytes = result.stdout as List<int>;
  if (bytes.length != _width * _height * 3) {
    throw StateError(
      '第 $index 帧的字节数 ${bytes.length} ≠ ${_width * _height * 3}',
    );
  }
  return _Frame(
    width: _width,
    height: _height,
    rgb: Uint8List.fromList(bytes),
  );
}

Future<int> _frameCount(String path) async {
  final probe = await Process.run('ffprobe', <String>[
    '-v',
    'error',
    '-count_frames',
    '-select_streams',
    'v:0',
    '-show_entries',
    'stream=nb_read_frames',
    '-of',
    'csv=p=0',
    path,
  ]);
  if (probe.exitCode != 0) throw StateError('数帧失败：${probe.stderr}');
  return int.parse((probe.stdout as String).trim());
}

Future<void> _ffmpeg(List<String> arguments) async {
  final result = await Process.run('ffmpeg', arguments);
  if (result.exitCode != 0) {
    throw StateError('ffmpeg 失败（${arguments.join(' ')}）：${result.stderr}');
  }
}
