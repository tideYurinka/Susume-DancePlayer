/// 投屏渲染计时入口（宿主侧）：把**同一份**滤镜图与命令行交给本机 ffmpeg CLI
/// 跑一遍，量墙钟、验产物、验镜像闸门。
///
/// 它是设备入口（`tool/cast_render_bench.dart`，走已链接的 ffmpeg 包、
/// `h264_mediacodec` 硬编）的对照：两侧共用 `tool/cast_render_bench/bench_core.dart`
/// 的命令与判定，所以读数可比。**真机吞吐的结论只能由设备入口给**，宿主这一份
/// 的用途是：先把滤镜图与口径验对（滤镜语义与平台无关），并且给出一个
/// 「不含真机硬编」的参照。
///
/// 用法（仓库根目录）：
///   dart run tool/cast_render_bench_host.dart --out /tmp/cast_bench \
///     [--runs 3] [--encoder libx264] [--report docs/research/xxx.json]
///
/// 退出码 0 = 两档分辨率都拿到可播产物、镜像闸门通过；非 0 = 有读数不成立。
library;

import 'dart:convert';
import 'dart:io';

import 'cast_render_bench/bench_core.dart';

/// 宿主对照用的编码器：本机 ffmpeg 有 libx264，真机那条路用硬编。
const String _defaultHostEncoder = 'libx264';

/// 镜像闸门的探针时刻（秒）。两个在窗外、两个正好落在窗的端点上——
/// 端点那两帧钉住**半开区间**：起点算窗内、终点算窗外。
const double _probeOutside = 1.0;
const double _probeInside = 3.0;
const double _probeWindowStart = 2.0;
const double _probeWindowEnd = 4.0;

Future<void> main(List<String> argv) async {
  final options = _Options.parse(argv);
  final bench = _HostBench(options);
  final ok = await bench.run();
  exit(ok ? 0 : 1);
}

/// 命令行选项。
class _Options {
  _Options({
    required this.outDir,
    required this.runs,
    required this.encoder,
    required this.reportPath,
    required this.prepareOnly,
  });

  final Directory outDir;
  final int runs;
  final String encoder;
  final String? reportPath;

  /// 只把固定输入准备好（供设备入口推送），不做任何渲染。
  final bool prepareOnly;

  static _Options parse(List<String> argv) {
    String? value(String flag) {
      final i = argv.indexOf(flag);
      return i >= 0 && i + 1 < argv.length ? argv[i + 1] : null;
    }

    return _Options(
      outDir: Directory(value('--out') ?? '/tmp/cast_render_bench'),
      runs: int.tryParse(value('--runs') ?? '3') ?? 3,
      encoder: value('--encoder') ?? _defaultHostEncoder,
      reportPath: value('--report'),
      prepareOnly: argv.contains('--prepare-only'),
    );
  }
}

/// 宿主侧的一次完整计时。
class _HostBench {
  _HostBench(this.options);

  final _Options options;

  final Map<String, Object?> _report = <String, Object?>{};
  final List<BenchRunResult> _runs = <BenchRunResult>[];

  Future<bool> run() async {
    await options.outDir.create(recursive: true);
    final work = Directory('${options.outDir.path}/work')
      ..createSync(recursive: true);
    final inputs = Directory('${options.outDir.path}/inputs')
      ..createSync(recursive: true);
    final artifacts = Directory('${options.outDir.path}/artifacts')
      ..createSync(recursive: true);

    final ffmpegVersion = await _toolVersion('ffmpeg');
    stdout.writeln('ffmpeg: $ffmpegVersion');

    final inputFiles = await _prepareInputs(inputs);
    if (options.prepareOnly) {
      final manifest = '${options.outDir.path}/inputs_manifest.json';
      File(manifest).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'inputs': inputFiles.toJson(),
          'inputsFixed': _fixedInputSpecJson(),
        }),
      );
      stdout.writeln('固定输入就绪：${options.outDir.path}/inputs');
      stdout.writeln('清单：$manifest');
      return true;
    }
    final capability = await _probeCapability();
    _report['runner'] = 'host';
    _report['ffmpeg'] = ffmpegVersion;
    _report['encoder'] = options.encoder;

    final artifactsByResolution = <BenchResolution, String>{};
    for (final resolution in BenchResolution.values) {
      for (var i = 1; i <= options.runs; i++) {
        final output = '${artifacts.path}/bench_${resolution.name}_$i.mp4';
        final result = await _runOnce(
          resolution: resolution,
          sourcePath: inputFiles.source,
          stickerPath: inputFiles.sticker,
          beatPath: inputFiles.beat,
          outputPath: output,
        );
        _runs.add(result);
        artifactsByResolution[resolution] = output;
        stdout.writeln(
          '  ${resolution.name} 第 $i 跑：${result.wallClockMs}ms，'
          '渲染 ${result.rendered ? '成功' : '失败'}，'
          '产物 ${result.artifact.ok ? '可播' : '不可播（${result.artifact.problems.join('；')}）'}',
        );
      }
    }

    final filterOnlyMs = await _timeFilterGraphOnly(
      sourcePath: inputFiles.source,
      stickerPath: inputFiles.sticker,
      beatPath: inputFiles.beat,
    );
    stdout.writeln('  只跑滤镜图（1080p，不编码）：${filterOnlyMs}ms');

    final flipGate = await _verifyFlipGate(
      sourcePath: inputFiles.source,
      artifactPath: artifactsByResolution[BenchResolution.p1080]!,
      workDir: work,
    );

    final summary = summarizeBenchRuns(_runs);
    _report['inputs'] = inputFiles.toJson();
    _report['inputsFixed'] = _fixedInputSpecJson();
    _report['encoderCapability'] = capability;
    _report['runs'] = _runs.map(_runJson).toList();
    _report['summary'] = _summaryJson(summary);
    _report['filterOnlyMs1080p'] = filterOnlyMs;
    _report['flipGate'] = flipGate;
    _report['finishedAt'] = DateTime.now().toIso8601String();

    final jsonPath = '${options.outDir.path}/cast_render_bench_host.json';
    File(jsonPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(_report),
    );

    final reportPath = options.reportPath;
    if (reportPath != null) {
      File(reportPath)
        ..createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(_report),
        );
    }

    _printSummary(summary, filterOnlyMs, flipGate, jsonPath);

    final flipOk = flipGate['ok'] == true;
    final timingOk =
        summary.p1080 != null && summary.p720 != null && summary.rejected.isEmpty;
    return flipOk && timingOk;
  }

  // ── 输入准备 ────────────────────────────────────────────────────────────

  Future<_BenchInputs> _prepareInputs(Directory inputs) async {
    final source = '${inputs.path}/source_1080p_30s.mp4';
    final sticker = '${inputs.path}/sticker_alpha.png';
    final beat = '${inputs.path}/beat_120bpm_30s.wav';

    if (!File(source).existsSync()) {
      await _mustRun('ffmpeg', sourceGenerationArgs(
        outputPath: source,
        encoder: options.encoder,
      ));
    }
    if (!File(sticker).existsSync()) {
      await _mustRun('ffmpeg', stickerGenerationArgs(outputPath: sticker));
    }
    if (!File(beat).existsSync()) {
      await _mustRun('ffmpeg', beatGenerationArgs(outputPath: beat));
    }

    final alphaRange = await _stickerAlphaRange(sticker);
    if (alphaRange == null) {
      stderr.writeln('贴纸的 alpha 读不出来：$sticker');
      exit(2);
    }
    if (alphaRange.$1 >= 250 || alphaRange.$2 == 0) {
      stderr.writeln(
        '贴纸不是「带 alpha」的：alpha 区间 ${alphaRange.$1}..${alphaRange.$2}',
      );
      exit(2);
    }
    stdout.writeln(
      '输入就绪：贴纸 alpha 区间 ${alphaRange.$1}..${alphaRange.$2}（全分辨率半透明）',
    );

    return _BenchInputs(
      source: source,
      sticker: sticker,
      beat: beat,
      hashes: <String, String>{
        'source': await _sha256(source),
        'sticker': await _sha256(sticker),
        'beat': await _sha256(beat),
      },
      stickerAlphaRange: alphaRange,
    );
  }

  /// 读单帧贴纸的 alpha 平面，返回 `(最小, 最大)`。读失败给 null。
  Future<(int, int)?> _stickerAlphaRange(String sticker) async {
    final result = await Process.run(
      'ffmpeg',
      <String>[
        '-hide_banner',
        '-v', 'error',
        '-i', sticker,
        '-vf', 'alphaextract',
        '-f', 'rawvideo',
        '-pix_fmt', 'gray',
        '-',
      ],
      stdoutEncoding: null,
    );
    if (result.exitCode != 0) {
      return null;
    }
    final bytes = result.stdout as List<int>;
    if (bytes.isEmpty) {
      return null;
    }
    var min = 255;
    var max = 0;
    for (final b in bytes) {
      if (b < min) min = b;
      if (b > max) max = b;
    }
    return (min, max);
  }

  // ── 编码器两问 ──────────────────────────────────────────────────────────

  Future<Map<String, Object?>> _probeCapability() async {
    final capability = await Process.run(
      'ffmpeg',
      encoderCapabilityArgs(encoder: options.encoder),
    );
    final lines = <String>[
      ...'${capability.stdout}'.split('\n'),
      ...'${capability.stderr}'.split('\n'),
    ];
    final name = encoderCapabilityName(lines);
    final raw = lines.where((l) => l.trim().isNotEmpty).take(40).join('\n');
    stdout.writeln('编码器能力：${name ?? '认不出（${options.encoder}）'}');
    return <String, Object?>{
      'encoder': options.encoder,
      'found': name != null,
      'name': name,
      'raw': raw,
    };
  }

  // ── 计时 ────────────────────────────────────────────────────────────────

  Future<BenchRunResult> _runOnce({
    required BenchResolution resolution,
    required String sourcePath,
    required String stickerPath,
    required String beatPath,
    required String outputPath,
  }) async {
    final args = renderArgs(
      resolution: resolution,
      sourcePath: sourcePath,
      stickerPath: stickerPath,
      beatPath: beatPath,
      outputPath: outputPath,
      encoder: options.encoder,
    );
    final stopwatch = Stopwatch()..start();
    final result = await Process.run('ffmpeg', args);
    stopwatch.stop();

    final decoded = result.exitCode == 0
        ? await _decodeCheck(outputPath)
        : (false, null);
    final artifact = await _probeArtifact(
      outputPath,
      resolution,
      decodedFrames: decoded.$2,
    );
    final decodable = result.exitCode == 0;
    return BenchRunResult(
      resolution: resolution,
      wallClockMs: stopwatch.elapsedMilliseconds,
      rendered: result.exitCode == 0,
      artifact: artifact,
      fullyDecodable: decodable,
      decodedFrames: decoded.$2,
      codecPick: parseMediaCodecPick(
        '${result.stderr}'.split('\n'),
      ),
      stdoutTail: _tail('${result.stderr}'),
    );
  }

  /// 只跑滤镜图（输出到 `null`）：把「滤镜与合成」的代价从「编码」里分出来。
  Future<int> _timeFilterGraphOnly({
    required String sourcePath,
    required String stickerPath,
    required String beatPath,
  }) async {
    final args = <String>[
      '-hide_banner',
      '-y',
      '-i', sourcePath,
      '-i', stickerPath,
      '-i', beatPath,
      '-filter_complex', renderFilterGraph(BenchResolution.p1080),
      '-map', '[vout]',
      '-map', '[aout]',
      '-f', 'null',
      '-',
    ];
    final stopwatch = Stopwatch()..start();
    final result = await Process.run('ffmpeg', args);
    stopwatch.stop();
    if (result.exitCode != 0) {
      stderr.writeln('只跑滤镜图失败：${_tail('${result.stderr}')}');
    }
    return stopwatch.elapsedMilliseconds;
  }

  // ── 产物验收 ────────────────────────────────────────────────────────────

  Future<ArtifactVerdict> _probeArtifact(
    String path,
    BenchResolution resolution, {
    int? decodedFrames,
  }) async {
    if (!File(path).existsSync()) {
      return const ArtifactVerdict(
        ok: false,
        problems: <String>['产物文件不存在'],
      );
    }
    final result = await Process.run('ffprobe', <String>[
      '-v', 'error',
      '-print_format', 'json',
      '-show_format',
      '-show_streams',
      path,
    ]);
    final reading = parseFfprobeOutput('${result.stdout}');
    if (result.exitCode != 0 || reading == null) {
      return ArtifactVerdict(
        ok: false,
        problems: <String>['ffprobe 读不出来：${_tail('${result.stderr}')}'],
      );
    }
    return judgeArtifact(
      reading,
      expected: resolution,
      decodedFrames: decodedFrames,
    );
  }

  /// 整片解码一遍（`-f null -`）：产物「能播、且没丢帧」的强证据。
  /// 返回（是否无解码错误，解码帧数）。
  Future<(bool, int?)> _decodeCheck(String path) async {
    final result = await Process.run('ffmpeg', decodeCheckArgs(path));
    final logs = '${result.stderr}';
    return (
      result.exitCode == 0 && !hasDecodeErrors(logs),
      parseDecodedFrameCount(logs),
    );
  }

  // ── 镜像闸门的像素级验收 ────────────────────────────────────────────────

  Future<Map<String, Object?>> _verifyFlipGate({
    required String sourcePath,
    required String artifactPath,
    required Directory workDir,
  }) async {
    final plain = '${workDir.path}/reference_plain.mp4';
    final flipped = '${workDir.path}/reference_flipped.mp4';
    for (final entry in <String, bool>{plain: false, flipped: true}.entries) {
      final result = await Process.run('ffmpeg', <String>[
        '-hide_banner',
        '-y',
        '-i', sourcePath,
        '-filter_complex',
        referenceFilterChain(BenchResolution.p1080, mirrored: entry.value),
        '-map', '[ref]',
        '-an',
        '-c:v', 'libx264',
        '-crf', '12',
        '-preset', 'veryfast',
        '-g', '$kBenchFps',
        '-r', '$kBenchFps',
        '-pix_fmt', 'yuv420p',
        '-f', 'mp4',
        entry.key,
      ]);
      if (result.exitCode != 0) {
        return <String, Object?>{
          'ok': false,
          'problems': <String>['参考帧生成失败：${_tail('${result.stderr}')}'],
        };
      }
    }

    final probes = <Map<String, Object?>>[];
    for (final probe in <double>[
      _probeOutside,
      _probeInside,
      _probeWindowStart,
      _probeWindowEnd,
    ]) {
      probes.add(<String, Object?>{
        't': probe,
        'plain': await _psnrAt(artifactPath, plain, probe),
        'flipped': await _psnrAt(artifactPath, flipped, probe),
      });
    }

    PsnrPair pairOf(double t) {
      final probe = probes.firstWhere((p) => p['t'] == t);
      return PsnrPair(
        plain: probe['plain'] as double,
        flipped: probe['flipped'] as double,
      );
    }

    final problems = <String>[];
    final midWindow = judgeFlipGate(
      insideWindow: pairOf(_probeInside),
      outsideWindow: pairOf(_probeOutside),
    );
    problems.addAll(midWindow.problems);
    final boundaries = judgeFlipGate(
      insideWindow: pairOf(_probeWindowStart),
      outsideWindow: pairOf(_probeWindowEnd),
    );
    problems.addAll(
      boundaries.problems.map((p) => '窗的端点（半开区间）：$p'),
    );

    stdout.writeln(
      '镜像闸门：${problems.isEmpty ? '通过' : '不通过（${problems.join('；')}）'}',
    );
    return <String, Object?>{
      'ok': problems.isEmpty,
      'problems': problems,
      'probes': probes,
      'note': 't=$_probeOutside/$_probeWindowEnd 应像翻过的那份，'
          't=$_probeWindowStart/$_probeInside 应像未翻的那份',
    };
  }

  /// 两个文件在时刻 `t` 的那一帧的平均 PSNR（越高越像）。
  Future<double> _psnrAt(String a, String b, double t) async {
    final result = await Process.run('ffmpeg', <String>[
      '-hide_banner',
      '-nostdin',
      '-ss', '$t',
      '-i', a,
      '-ss', '$t',
      '-i', b,
      '-filter_complex', '[0:v][1:v]psnr',
      '-frames:v', '1',
      '-f', 'null',
      '-',
    ]);
    for (final line in '${result.stderr}'.split('\n').reversed) {
      final parsed = parsePsnrAverage(line);
      if (parsed != null) {
        return parsed;
      }
    }
    stderr.writeln('PSNR 读不出来（t=$t）：${_tail('${result.stderr}')}');
    return 0;
  }

  // ── 小工具 ──────────────────────────────────────────────────────────────

  Future<void> _mustRun(String command, List<String> args) async {
    final result = await Process.run(command, args);
    if (result.exitCode != 0) {
      stderr.writeln('$command 失败：${_tail('${result.stderr}')}');
      exit(2);
    }
  }

  Future<String> _toolVersion(String tool) async {
    final result = await Process.run(tool, <String>['-version']);
    return '${result.stdout}'.split('\n').first.trim();
  }

  Future<String> _sha256(String path) async {
    final result = await Process.run('sha256sum', <String>[path]);
    return '${result.stdout}'.split(' ').first.trim();
  }

  String _tail(String text) {
    final lines = text.trim().split('\n');
    return lines.length <= 4 ? lines.join(' / ') : lines.sublist(lines.length - 4).join(' / ');
  }

  Map<String, Object?> _fixedInputSpecJson() => <String, Object?>{
        'durationSeconds': kBenchDurationSeconds,
        'fps': kBenchFps,
        'sourceWidth': kBenchSourceWidth,
        'sourceHeight': kBenchSourceHeight,
        'localMirrorWindows': kBenchLocalMirrorWindows
            .map((w) => <double>[w.start, w.end])
            .toList(),
        'stickerWindow': <double>[
          kBenchStickerWindow.start,
          kBenchStickerWindow.end,
        ],
        'stickerRectNormalized': <double>[
          kBenchStickerLeft,
          kBenchStickerTop,
          kBenchStickerWidth,
          kBenchStickerHeight,
        ],
        'framingRectNormalized': <double>[
          kBenchFramingLeft,
          kBenchFramingTop,
          kBenchFramingWidth,
          kBenchFramingHeight,
        ],
        'gop': kBenchGop,
        'bitrate1080p': BenchResolution.p1080.bitrate,
        'bitrate720p': BenchResolution.p720.bitrate,
      };

  Map<String, Object?> _runJson(BenchRunResult run) => <String, Object?>{
        'resolution': run.resolution.name,
        'wallClockMs': run.wallClockMs,
        'rendered': run.rendered,
        'artifactOk': run.artifact.ok,
        'artifactProblems': run.artifact.problems,
        'fullyDecodable': run.fullyDecodable,
        'decodedFrames': run.decodedFrames,
        'codecPick': run.codecPick == null
            ? null
            : <String, Object?>{
                'component': run.codecPick!.component,
                'hardwareAccelerated': run.codecPick!.hardwareAccelerated,
              },
        'stderrTail': run.stdoutTail,
      };

  Map<String, Object?> _summaryJson(BenchTimingSummary summary) =>
      <String, Object?>{
        'p1080': _timingJson(summary.p1080),
        'p720': _timingJson(summary.p720),
        'resolutionCoefficient': summary.resolutionCoefficient,
        'rejectedRuns': summary.rejected.length,
      };

  Map<String, Object?>? _timingJson(ResolutionTiming? timing) => timing == null
      ? null
      : <String, Object?>{
          'samplesMs': timing.samplesMs,
          'medianMs': timing.medianMs,
          'minMs': timing.minMs,
          'maxMs': timing.maxMs,
          'realtimeFactor': timing.realtimeFactor,
        };

  void _printSummary(
    BenchTimingSummary summary,
    int filterOnlyMs,
    Map<String, Object?> flipGate,
    String jsonPath,
  ) {
    stdout.writeln('');
    stdout.writeln('=== 宿主计时读数（${options.encoder}） ===');
    for (final entry in <String, ResolutionTiming?>{
      '1080p': summary.p1080,
      '720p': summary.p720,
    }.entries) {
      final timing = entry.value;
      if (timing == null) {
        stdout.writeln('${entry.key}：没有可用读数');
        continue;
      }
      stdout.writeln(
        '${entry.key}：中位 ${timing.medianMs}ms'
        '（min ${timing.minMs} / max ${timing.maxMs}，'
        '${timing.realtimeFactor.toStringAsFixed(2)}× 实时）',
      );
    }
    final coefficient = summary.resolutionCoefficient;
    stdout.writeln(
      '分辨率影响系数（1080p ÷ 720p）：'
      '${coefficient == null ? '缺一档' : coefficient.toStringAsFixed(2)}',
    );
    stdout.writeln('只跑滤镜图（1080p）：${filterOnlyMs}ms');
    stdout.writeln('镜像闸门：${flipGate['ok'] == true ? '通过' : '不通过'}');
    stdout.writeln('原始读数：$jsonPath');
  }
}

/// 固定输入三件套的路径与哈希。
class _BenchInputs {
  _BenchInputs({
    required this.source,
    required this.sticker,
    required this.beat,
    required this.hashes,
    required this.stickerAlphaRange,
  });

  final String source;
  final String sticker;
  final String beat;
  final Map<String, String> hashes;
  final (int, int) stickerAlphaRange;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': <String, Object?>{
          'path': source,
          'sha256': hashes['source'],
          'bytes': File(source).lengthSync(),
        },
        'sticker': <String, Object?>{
          'path': sticker,
          'sha256': hashes['sticker'],
          'bytes': File(sticker).lengthSync(),
          'alphaRange': <int>[stickerAlphaRange.$1, stickerAlphaRange.$2],
        },
        'beat': <String, Object?>{
          'path': beat,
          'sha256': hashes['beat'],
          'bytes': File(beat).lengthSync(),
        },
      };
}
