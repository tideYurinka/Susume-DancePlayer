/// **范围的宿主对照**（`#37` 的验收入口）：拿**生产那一串命令行**
/// （`lib/cast/cast_render_plan.dart`，只把编码器换成本机无损 libx264）交给本机
/// ffmpeg 跑一遍，再逐帧读像素核对四件事：
///
/// 1. **副本时长与内容就是那一段**：产物时长 = 尾线 − 首线（半开口径），第一帧
///    是首线那一刻的源画面、末帧是尾线之前的那一帧，范围外的源秒一个都不进；
/// 2. **不用快速定位**：产命令行里没有 `-ss` / `-t` / `-to`（范围只在滤镜链的
///    中段：`trim` / `atrim`）；
/// 3. **范围与各滤镜时间窗的相对关系没被破坏**：局部镜像闸门的 `enable` 判的是
///    **源时间轴**——窗落在范围之外时副本一帧都不翻（拿 `-ss` 归零时间基准的
///    写法会让窗平移到副本 1–2 秒、在那里翻起来），窗落在范围之内时只有对应的
///    那一段翻；
/// 4. **倍速档不漂移**：0.5× 档上同一个窗仍落在**源**3–4 秒（副本 2–4 秒），
///    时长翻倍、内容不变。
///
/// 真机上那份（电视上的观感、接收端解码）只能真机看：宿主这一份验的是**滤镜图
/// 与产物的像素语义**，与平台无关。
///
/// 用法（仓库根目录）：
///   dart run tool/cast_range_check_host.dart [--out /tmp/cast_range] [--json 路径]
///
/// 退出码 0 = 上面的硬判据全过；非 0 = 有读数不成立。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';

/// 源片：6 秒 / 320×180 / 30fps，一秒一种「左半色 + 右半色」的组合。
///
/// 左右两半颜色不同，于是同一帧的读数同时回答两件事：**这是源片的第几秒**
/// （颜色对）与**这一帧有没有被翻**（左半是左色还是右色）。
const int _fps = 30;
const int _width = 320;
const int _height = 180;
const int _seconds = 6;

/// 范围：源 2 秒（含）→ 5 秒（不含）——3 秒那一段。
const int _rangeStartSecond = 2;
const int _rangeEndSecond = 5;

/// 逐秒的左右半色（rgb）。
const List<(int, int, int)> _leftColors = [
  (0xff, 0x00, 0x00),
  (0x00, 0x00, 0xff),
  (0xff, 0x00, 0xff),
  (0x80, 0x00, 0x00),
  (0x00, 0x00, 0x80),
  (0x80, 0x00, 0x80),
];
const List<(int, int, int)> _rightColors = [
  (0x00, 0xff, 0x00),
  (0xff, 0xff, 0x00),
  (0x00, 0xff, 0xff),
  (0x00, 0x80, 0x00),
  (0x80, 0x80, 0x00),
  (0x00, 0x80, 0x80),
];

/// 一跑的读数（留档用）。
final _report = <String, Object?>{};

Future<void> main(List<String> arguments) async {
  final outIndex = arguments.indexOf('--out');
  final root = Directory(
    outIndex >= 0 && outIndex + 1 < arguments.length
        ? arguments[outIndex + 1]
        : '/tmp/cast_range_check',
  );
  final jsonIndex = arguments.indexOf('--json');
  final jsonPath = jsonIndex >= 0 && jsonIndex + 1 < arguments.length
      ? arguments[jsonIndex + 1]
      : null;
  if (root.existsSync()) root.deleteSync(recursive: true);
  root.createSync(recursive: true);

  final problems = <String>[];
  try {
    await _runCases(root, problems);
  } on Object catch (error, stack) {
    problems.add('对照本身没跑完：$error\n$stack');
  }

  _report['problems'] = problems;
  stdout.writeln('\n== 汇总 ==');
  stdout.writeln('时长与内容：${_report['duration']}');
  stdout.writeln('音轨同段：${_report['audio']}');
  stdout.writeln('不用快速定位：${_report['noSeek']}');
  stdout.writeln('窗在范围外：${_report['windowOutside']}');
  stdout.writeln('窗在范围内：${_report['windowInside']}');
  stdout.writeln('倍速档不漂移：${_report['tier']}');
  if (jsonPath != null) {
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_report),
    );
    stdout.writeln('JSON 留档：$jsonPath');
  }
  if (problems.isEmpty) {
    stdout.writeln('\n全部判据通过。');
    return;
  }
  stderr.writeln('\n有读数不成立：');
  for (final problem in problems) {
    stderr.writeln('  - $problem');
  }
  exitCode = 1;
}

/// 源片路径与生产参数装配共用的输入。
///
/// [fragment] 是那条**局部镜像片段**：闸门的 `enable` 判的是**源时间轴**，
/// 于是它落在范围外 / 范围内时副本里的翻转段完全不同——这正是本脚本要看的。
CastRenderRequest _request({
  required String videoPath,
  required CastSpeedTier tier,
  LocalMirrorFragment? fragment,
}) => CastRenderRequest(
  videoPath: videoPath,
  videoId: 'range-check',
  duration: const Duration(seconds: _seconds),
  choices: const CastRenderChoices(picture: true, sound: false),
  speedTier: tier,
  settings: const CastRenderSettings(localMirrorEnabled: true),
  annotationFingerprint: 'range-check',
  mirrorFragments: [?fragment],
  range: const CastRange(
    start: Duration(seconds: _rangeStartSecond),
    end: Duration(seconds: _rangeEndSecond),
  ),
);

Future<void> _runCases(Directory root, List<String> problems) async {
  final source = File('${root.path}/source.mp4');
  await _buildSource(source);

  // ── 用例 1：1× 档、无闸门：时长与内容就是那一段 ────────────────────────
  final plain = File('${root.path}/plain.mp4');
  final plainArgs = buildCastRenderArguments(
    request: _request(videoPath: source.path, tier: CastSpeedTier.full),
    outputPath: plain.path,
    staging: const CastRenderStaging(),
  );
  await _run(_hostEncoderArgs(plainArgs));

  final plainDuration = await _probeDuration(plain.path);
  final plainAudio = await _probeAudioDuration(plain.path);
  final frames = await _readFrames(plain.path);
  const expectedFrames = (_rangeEndSecond - _rangeStartSecond) * _fps;
  final headSecond = frames.first.classified.second;
  final tailSecond = frames.last.classified.second;
  _report['duration'] = {
    'duration': plainDuration.inMilliseconds,
    'audioDuration': plainAudio.inMilliseconds,
    'frames': frames.length,
    'headSourceSecond': headSecond,
    'tailSourceSecond': tailSecond,
    'flippedFrames': frames.where((f) => f.flipped).length,
  };
  if ((plainDuration.inMilliseconds - 3000).abs() > 40) {
    problems.add('1× 档产物时长 ${plainDuration.inMilliseconds}ms ≠ 3000ms');
  }
  if (frames.length != expectedFrames) {
    problems.add('1× 档产物 ${frames.length} 帧 ≠ $expectedFrames 帧');
  }
  if ((plainAudio.inMilliseconds - plainDuration.inMilliseconds).abs() > 120) {
    problems.add(
      '音轨时长 ${plainAudio.inMilliseconds}ms 与画面 '
      '${plainDuration.inMilliseconds}ms 不同段',
    );
  }
  if (headSecond != _rangeStartSecond) {
    problems.add('首帧是源片第 $headSecond 秒，不是首线那一刻（$_rangeStartSecond）');
  }
  if (tailSecond != _rangeEndSecond - 1) {
    problems.add('末帧是源片第 $tailSecond 秒，不是尾线之前的最后一秒');
  }
  if (frames.any((f) => f.flipped)) {
    problems.add('没有闸门窗时却有色帧被翻（${frames.where((f) => f.flipped).length} 帧）');
  }
  _report['audio'] = plainAudio.inMilliseconds;

  // ── 用例 2：不用快速定位 ────────────────────────────────────────────────
  final seekArgs = plainArgs.where((a) => a == '-ss' || a == '-t' || a == '-to');
  _report['noSeek'] = {'forbiddenFlags': seekArgs.toList()};
  if (seekArgs.isNotEmpty) {
    problems.add('产命令行里出现了 ${seekArgs.join(' ')}（本票明确不用快速定位）');
  }

  // ── 用例 3：闸门窗落在范围**之外**（源 1–2 秒）：副本一帧都不该翻 ────────
  //
  // 这一段是**判据能否分辨**的关键：窗若被时间基准归零带着平移（`-ss` 那种
  // 写法），同一个窗就会落到副本 1–2 秒上、在那里翻起来——用例 3b 就是那条
  // 反例（把范围改回快速定位），它必须**翻**，否则说明这条比对什么都判不出。
  final outsideFragment = const LocalMirrorFragment(
    startMs: 1000,
    endMs: 2000,
  );
  final outside = File('${root.path}/window_outside.mp4');
  final outsideArgs = buildCastRenderArguments(
    request: _request(
      videoPath: source.path,
      tier: CastSpeedTier.full,
      fragment: outsideFragment,
    ),
    outputPath: outside.path,
    staging: const CastRenderStaging(),
  );
  await _run(_hostEncoderArgs(outsideArgs));
  final outsideFrames = await _readFrames(outside.path);

  final quickSeek = File('${root.path}/window_outside_quick_seek.mp4');
  final quickSeekArgs = _quickSeekArgs(outsideArgs, quickSeek.path);
  await _run(_hostEncoderArgs(quickSeekArgs));
  final quickSeekFrames = await _readFrames(quickSeek.path);

  final outsideFlipped = _flippedIndicesInWindow(outsideFrames);
  final quickSeekFlipped = _flippedIndicesInWindow(quickSeekFrames);
  _report['windowOutside'] = {
    'flippedFrames': outsideFlipped.count,
    'quickSeekFlippedFrames': quickSeekFlipped.count,
    'quickSeekFirstFlipped': quickSeekFlipped.first,
    'quickSeekLastFlipped': quickSeekFlipped.last,
  };
  if (outsideFlipped.count != 0) {
    problems.add(
      '窗落在范围之外却有色帧被翻（${outsideFlipped.count} 帧）'
      '——时间基准被归零了',
    );
  }
  if (quickSeekFlipped.count == 0) {
    problems.add('反例（`-ss` 快速定位）一帧都没翻：这条比对分辨不出两种写法');
  }

  // ── 用例 4：闸门窗落在范围**之内**（源 3–4 秒 → 副本 1–2 秒）：只有那一段翻 ─
  final inside = File('${root.path}/window_inside.mp4');
  final insideArgs = buildCastRenderArguments(
    request: _request(
      videoPath: source.path,
      tier: CastSpeedTier.full,
      fragment: const LocalMirrorFragment(startMs: 3000, endMs: 4000),
    ),
    outputPath: inside.path,
    staging: const CastRenderStaging(),
  );
  await _run(_hostEncoderArgs(insideArgs));
  final insideFrames = await _readFrames(inside.path);
  final flippedInside = _flippedIndicesInWindow(insideFrames);
  _report['windowInside'] = {
    'flippedFrames': flippedInside.count,
    'firstFlipped': flippedInside.first,
    'lastFlipped': flippedInside.last,
  };
  // 半开窗：源 3 秒那一帧在窗内、源 4 秒那一帧已在窗外。
  if (flippedInside.first != _fps || flippedInside.last != 2 * _fps - 1) {
    problems.add(
      '窗内翻转的帧区间 [${flippedInside.first}, ${flippedInside.last}] '
      '不是半开窗 [$_fps, ${2 * _fps - 1}]',
    );
  }

  // ── 用例 5：0.5× 档：窗仍在**源** 3–4 秒（副本 2–4 秒），时长翻倍 ─────────
  final half = File('${root.path}/half.mp4');
  final halfArgs = buildCastRenderArguments(
    request: _request(
      videoPath: source.path,
      tier: CastSpeedTier.half,
      fragment: const LocalMirrorFragment(startMs: 3000, endMs: 4000),
    ),
    outputPath: half.path,
    staging: const CastRenderStaging(),
  );
  await _run(_hostEncoderArgs(halfArgs));
  final halfDuration = await _probeDuration(half.path);
  final halfFrames = await _readFrames(half.path);
  final halfFlipped = _flippedIndicesInWindow(halfFrames);
  final halfHeadSecond = halfFrames.first.classified.second;
  _report['tier'] = {
    'duration': halfDuration.inMilliseconds,
    'frames': halfFrames.length,
    'headSourceSecond': halfHeadSecond,
    'flippedFrames': halfFlipped.count,
    'firstFlipped': halfFlipped.first,
    'lastFlipped': halfFlipped.last,
  };
  if ((halfDuration.inMilliseconds - 6000).abs() > 40) {
    problems.add('0.5× 档产物时长 ${halfDuration.inMilliseconds}ms ≠ 6000ms');
  }
  if (halfFrames.length != expectedFrames * 2) {
    problems.add('0.5× 档产物 ${halfFrames.length} 帧 ≠ ${expectedFrames * 2} 帧');
  }
  if (halfHeadSecond != _rangeStartSecond) {
    problems.add('0.5× 档首帧是源片第 $halfHeadSecond 秒（应仍为首线）');
  }
  if (halfFlipped.first != 2 * _fps || halfFlipped.last != 4 * _fps - 1) {
    problems.add(
      '0.5× 档窗内翻转的帧区间 [${halfFlipped.first}, ${halfFlipped.last}] '
      '不是 [${2 * _fps}, ${4 * _fps - 1}]（窗随倍速档漂移了）',
    );
  }
}

/// 反例：把中段的 `trim` / `atrim` 换成**快速定位**（`-ss` 在 `-i` 之前，
/// 输出路径换成 [outputPath]）——时间基准被归零，各闸门的时间窗跟着平移。
///
/// 这一条不进产物，只用来证明上面的翻转比对**分辨得出**两种写法。
List<String> _quickSeekArgs(List<String> args, String outputPath) {
  final trim = 'trim=start=$_rangeStartSecond:end=$_rangeEndSecond,'
      'setpts=PTS-STARTPTS,';
  final aTrim = 'atrim=start=$_rangeStartSecond:end=$_rangeEndSecond,'
      'asetpts=PTS-STARTPTS,';
  final patched = <String>[];
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.contains(trim) || arg.contains(aTrim)) {
      patched.add(arg.replaceAll(trim, '').replaceAll(aTrim, ''));
      continue;
    }
    if (arg == '-i') {
      patched.addAll(['-ss', '$_rangeStartSecond', '-i']);
      continue;
    }
    if (i == args.length - 1) {
      patched.add(outputPath);
      continue;
    }
    patched.add(arg);
  }
  return patched;
}

/// 造源片：逐秒两半色 + 一条正弦音轨（6 秒）。
Future<void> _buildSource(File target) async {
  final inputs = <String>[];
  final filters = <String>[];
  for (var second = 0; second < _seconds; second++) {
    inputs.addAll([
      '-f',
      'lavfi',
      '-i',
      'color=c=0x${_hexOf(_leftColors[second])}:s=${_width ~/ 2}x$_height:'
          'd=1:r=$_fps',
    ]);
  }
  for (var second = 0; second < _seconds; second++) {
    inputs.addAll([
      '-f',
      'lavfi',
      '-i',
      'color=c=0x${_hexOf(_rightColors[second])}:s=${_width ~/ 2}x$_height:'
          'd=1:r=$_fps',
    ]);
  }
  for (var second = 0; second < _seconds; second++) {
    filters.add(
      '[$second:v][${second + _seconds}:v]'
      'hstack=inputs=2[v$second]',
    );
  }
  filters.add(
    '${[for (var i = 0; i < _seconds; i++) '[v$i]'].join()}'
    'concat=n=$_seconds:v=1:a=0[vout]',
  );
  await _run([
    '-hide_banner',
    '-y',
    ...inputs,
    '-f',
    'lavfi',
    '-i',
    'sine=frequency=440:duration=$_seconds',
    '-filter_complex',
    filters.join(';'),
    '-map',
    '[vout]',
    '-map',
    '${_seconds * 2}:a',
    '-c:v',
    'libx264',
    '-pix_fmt',
    'yuv420p',
    '-g',
    '$_fps',
    '-r',
    '$_fps',
    '-c:a',
    'aac',
    '-ar',
    '48000',
    '-ac',
    '2',
    '-shortest',
    target.path,
  ]);
}

String _hexOf((int, int, int) rgb) =>
    '${rgb.$1.toRadixString(16).padLeft(2, '0')}'
    '${rgb.$2.toRadixString(16).padLeft(2, '0')}'
    '${rgb.$3.toRadixString(16).padLeft(2, '0')}';

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

/// 一帧的读数：左右两半的像素色，以及它有没有被翻。
class _Frame {
  const _Frame({required this.left, required this.right});

  final (int, int, int) left;
  final (int, int, int) right;

  /// 这一帧对应源片的第几秒、有没有被翻（按最近色对判）。
  ({int second, bool flipped}) get classified => _classify(left, right);

  /// 源片那一秒的左半色在这一帧的左边 → 没翻；在右边 → 翻了。
  bool get flipped => classified.flipped;
}

/// 整片一次读完（`-f rawvideo` 一把读，不逐帧起进程——180 帧起 180 个进程太慢）。
Future<List<_Frame>> _readFrames(String path) async {
  final result = await Process.run(
    'ffmpeg',
    [
      '-v',
      'error',
      '-i',
      path,
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgb24',
      '-',
    ],
    stdoutEncoding: null,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    throw StateError('读帧失败（$path）：${result.stderr}');
  }
  final bytes = Uint8List.fromList(result.stdout as List<int>);
  const frameBytes = _width * _height * 3;
  final frames = <_Frame>[];
  for (var offset = 0; offset + frameBytes <= bytes.length; offset += frameBytes) {
    frames.add(
      _Frame(
        left: _pixelAt(bytes, offset, 20, _height ~/ 2),
        right: _pixelAt(bytes, offset, _width - 20, _height ~/ 2),
      ),
    );
  }
  return frames;
}

(int, int, int) _pixelAt(Uint8List bytes, int frameOffset, int x, int y) {
  final index = frameOffset + (y * _width + x) * 3;
  return (bytes[index], bytes[index + 1], bytes[index + 2]);
}

/// 按**最近色对**判：源片是 yuv420p，`rgb24` 读回来时 255 会变成 253 一类，
/// 逐位相等判不出来——比「左半色 + 右半色」与「翻过来的那一对」哪个更近即可。
({int second, bool flipped}) _classify(
  (int, int, int) left,
  (int, int, int) right,
) {
  var bestSecond = -1;
  var bestFlipped = false;
  var bestDistance = 1 << 30;
  for (var second = 0; second < _seconds; second++) {
    final direct =
        _channelDistance(left, _leftColors[second]) +
        _channelDistance(right, _rightColors[second]);
    final flipped =
        _channelDistance(left, _rightColors[second]) +
        _channelDistance(right, _leftColors[second]);
    if (direct < bestDistance) {
      bestDistance = direct;
      bestSecond = second;
      bestFlipped = false;
    }
    if (flipped < bestDistance) {
      bestDistance = flipped;
      bestSecond = second;
      bestFlipped = true;
    }
  }
  // 色对之间差着整个色域，这一档阈值只用来兜「读到一帧不是色块」。
  if (bestDistance > 3000) return (second: -1, flipped: false);
  return (second: bestSecond, flipped: bestFlipped);
}

int _channelDistance((int, int, int) a, (int, int, int) b) {
  final dr = a.$1 - b.$1;
  final dg = a.$2 - b.$2;
  final db = a.$3 - b.$3;
  return dr * dr + dg * dg + db * db;
}

/// 窗内翻转的帧区间（首、末、条数）。
({int first, int last, int count}) _flippedIndicesInWindow(List<_Frame> frames) {
  final indices = <int>[
    for (var i = 0; i < frames.length; i++)
      if (frames[i].flipped) i,
  ];
  if (indices.isEmpty) return (first: -1, last: -1, count: 0);
  return (first: indices.first, last: indices.last, count: indices.length);
}

Future<Duration> _probeDuration(String path) async {
  final result = await Process.run('ffprobe', [
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'csv=p=0',
    path,
  ]);
  final text = (result.stdout as String).trim();
  final seconds = double.tryParse(text);
  if (seconds == null) throw StateError('ffprobe 读不出时长：$text');
  return Duration(microseconds: (seconds * 1000000).round());
}

Future<Duration> _probeAudioDuration(String path) async {
  final result = await Process.run('ffprobe', [
    '-v',
    'error',
    '-select_streams',
    'a:0',
    '-show_entries',
    'stream=duration',
    '-of',
    'csv=p=0',
    path,
  ]);
  final text = (result.stdout as String).trim();
  final seconds = double.tryParse(text);
  if (seconds == null) throw StateError('ffprobe 读不出音轨时长：$text');
  return Duration(microseconds: (seconds * 1000000).round());
}

Future<void> _run(List<String> args) async {
  final result = await Process.run('ffmpeg', args);
  if (result.exitCode != 0) {
    throw StateError(
      'ffmpeg 返回 ${result.exitCode}：${args.join(' ')}\n${result.stderr}',
    );
  }
}
