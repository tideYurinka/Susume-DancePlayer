import 'package:flutter_test/flutter_test.dart';

import '../../tool/cast_render_bench/bench_core.dart';

/// 渲染路线关卡（#24）计时入口的纯件测试。
///
/// 这一层是**外部契约**的一部分：滤镜图与命令行决定产物，所以按关键片段
/// 快照式断言（沿用本仓「声明表 + 穷尽校验」型测试的口径），不测实现细节。
void main() {
  group('局部镜像时间窗：半开区间 [起, 止)', () {
    test('单窗表达式用 gte(t,起)*lt(t,止)，不用 between', () {
      const window = BenchWindow(2, 4);

      expect(window.enableExpression, "gte(t,2)*lt(t,4)");
      expect(window.enableExpression, isNot(contains('between')));
    });

    test('小数端点按原样落进表达式', () {
      const window = BenchWindow(10, 12.5);

      expect(window.enableExpression, "gte(t,10)*lt(t,12.5)");
    });

    test('多窗并集按 + 相加（重叠也只是真值非零）', () {
      const windows = <BenchWindow>[BenchWindow(2, 4), BenchWindow(10, 12.5)];

      expect(unionEnableExpression(windows), "gte(t,2)*lt(t,4)+gte(t,10)*lt(t,12.5)");
    });

    test('空窗集给恒假表达式，不产出半截滤镜', () {
      expect(unionEnableExpression(const <BenchWindow>[]), '0');
    });
  });

  group('完整滤镜图：镜像闸门 / 全分辨率 alpha 贴纸 / 取景 / 拍声', () {
    final graph1080 = renderFilterGraph(BenchResolution.p1080);

    test('全局镜像一次、局部镜像再一次（两个都开 = 净不翻）', () {
      final hflips = RegExp(r'hflip').allMatches(graph1080);

      expect(hflips.length, 2);
      expect(
        graph1080,
        contains(
          "hflip=enable='gte(t,2)*lt(t,4)+gte(t,10)*lt(t,12.5)'",
        ),
      );
    });

    test('贴纸走第二路输入、按全分辨率 alpha 混合、限时可见', () {
      expect(graph1080, contains('[1:v]format=rgba'));
      expect(
        graph1080,
        contains("overlay=x=96:y=76:enable='gte(t,6)*lt(t,9)':format=rgb"),
      );
    });

    test('取景先裁后铺满输出分辨率，末段归到编码器接受的像素格式', () {
      expect(graph1080, contains('crop=1728:972:96:54,scale=1920:1080'));
      expect(graph1080, contains('scale=1920:1080,setsar=1,format=yuv420p'));
      expect(
        renderFilterGraph(BenchResolution.p720),
        contains('crop=1728:972:96:54,scale=1280:720'),
      );
    });

    test('拍声作为第三路输入混进主音轨', () {
      expect(graph1080, contains('[0:a]aresample=48000[amain]'));
      expect(graph1080, contains('[2:a]aresample=48000,volume=0.6[abeat]'));
      expect(
        graph1080,
        contains(
          '[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]',
        ),
      );
    });
  });

  group('渲染命令行', () {
    test('1080p：硬编 H.264、显式码率/GOP/帧率、faststart', () {
      final args = renderArgs(
        resolution: BenchResolution.p1080,
        sourcePath: '/tmp/in/source.mp4',
        stickerPath: '/tmp/in/sticker.png',
        beatPath: '/tmp/in/beat.wav',
        outputPath: '/tmp/out/bench_1080p.mp4',
      );

      expect(args, containsAllInOrder(['-i', '/tmp/in/source.mp4']));
      expect(args, containsAllInOrder(['-i', '/tmp/in/sticker.png']));
      expect(args, containsAllInOrder(['-i', '/tmp/in/beat.wav']));
      expect(args, containsAllInOrder(['-c:v', 'h264_mediacodec']));
      expect(args, containsAllInOrder(['-b:v', '8M']));
      expect(args, containsAllInOrder(['-g', '60']));
      expect(args, containsAllInOrder(['-r', '30']));
      expect(args, containsAllInOrder(['-c:a', 'aac']));
      expect(args, containsAllInOrder(['-movflags', '+faststart']));
      expect(args, containsAllInOrder(['-map', '[vout]']));
      expect(args, containsAllInOrder(['-map', '[aout]']));
      expect(args.last, '/tmp/out/bench_1080p.mp4');
    });

    test('720p：同一张图，只降输出分辨率与码率（分辨率系数才有意义）', () {
      final args = renderArgs(
        resolution: BenchResolution.p720,
        sourcePath: 's.mp4',
        stickerPath: 'k.png',
        beatPath: 'b.wav',
        outputPath: 'o.mp4',
      );

      expect(args, containsAllInOrder(['-b:v', '4M']));
      expect(
        args[args.indexOf('-filter_complex') + 1],
        contains('scale=1280:720'),
      );
    });

    test('单帧贴纸输入不配 -loop 1、全命令不配 -shortest', () {
      final args = renderArgs(
        resolution: BenchResolution.p1080,
        sourcePath: 's.mp4',
        stickerPath: 'k.png',
        beatPath: 'b.wav',
        outputPath: 'o.mp4',
      );

      expect(args, isNot(contains('-loop')));
      expect(args, isNot(contains('-shortest')));
    });

    test('冒烟档只截前一秒，其余命令行一字不改', () {
      final full = renderArgs(
        resolution: BenchResolution.p1080,
        sourcePath: 's.mp4',
        stickerPath: 'k.png',
        beatPath: 'b.wav',
        outputPath: 'o.mp4',
      );
      final smoke = renderArgs(
        resolution: BenchResolution.p1080,
        sourcePath: 's.mp4',
        stickerPath: 'k.png',
        beatPath: 'b.wav',
        outputPath: 'o.mp4',
        limitSeconds: 1,
      );

      expect(smoke, containsAllInOrder(['-t', '1']));
      expect(smoke.indexOf('-t'), greaterThan(smoke.indexOf('+faststart')));
      expect(
        smoke.where((a) => a != '-t' && a != '1'),
        full,
      );
    });

    test('宿主基线可换编码器（真机硬编不可用时仍能验证同一张图）', () {
      final args = renderArgs(
        resolution: BenchResolution.p1080,
        sourcePath: 's.mp4',
        stickerPath: 'k.png',
        beatPath: 'b.wav',
        outputPath: 'o.mp4',
        encoder: 'libx264',
      );

      expect(args, containsAllInOrder(['-c:v', 'libx264']));
    });
  });

  group('固定输入：同一串参数生成同一份输入', () {
    test('源片 30s / 1080p / 30fps，音轨 48kHz', () {
      final args = sourceGenerationArgs(
        outputPath: 'source.mp4',
        encoder: 'libx264',
      );

      expect(args, containsAllInOrder(['-f', 'lavfi']));
      expect(
        args[args.indexOf('-i') + 1],
        contains('testsrc2=size=1920x1080:rate=30:duration=30'),
      );
      expect(
        args[args.indexOf('-i', args.indexOf('-i') + 1) + 1],
        contains('sine=frequency=440:sample_rate=48000:duration=30'),
      );
      expect(args, containsAllInOrder(['-c:v', 'libx264']));
      expect(args, containsAllInOrder(['-c:a', 'aac']));
    });

    test('贴纸是带 alpha 的单帧 PNG，尺寸等于归一化落位', () {
      final args = stickerGenerationArgs(outputPath: 'sticker.png');

      expect(args, containsAllInOrder(['-frames:v', '1']));
      // format=rgba 必须在 lavfi 输入图里——挂 -vf 上时 alpha 已经丢了。
      expect(args, contains('color=c=yellow@0.6:s=480x162,format=rgba'));
      expect(args, isNot(contains('-vf')));
      expect(args.last, 'sticker.png');
    });

    test('拍声是 120bpm 的整拍点击，30s、48kHz', () {
      final args = beatGenerationArgs(outputPath: 'beat.wav');

      expect(
        args.any((a) => a.contains('sine=frequency=880:sample_rate=48000:duration=30')),
        isTrue,
      );
      expect(args.any((a) => a.contains("volume=volume='lt(mod(t,0.5),0.06)'")), isTrue);
    });
  });

  group('计时统计：中位数、实时倍率、分辨率影响系数', () {
    BenchRunResult run(BenchResolution r, int ms) => BenchRunResult(
          resolution: r,
          wallClockMs: ms,
          rendered: true,
          artifact: const ArtifactVerdict(ok: true, problems: <String>[]),
          fullyDecodable: true,
        );

    test('中位数取自三次读数，实时倍率按 30s 时长换算', () {
      final summary = summarizeBenchRuns(<BenchRunResult>[
        run(BenchResolution.p1080, 10000),
        run(BenchResolution.p1080, 12000),
        run(BenchResolution.p1080, 11000),
      ]);

      expect(summary.p1080!.medianMs, 11000);
      expect(summary.p1080!.minMs, 10000);
      expect(summary.p1080!.maxMs, 12000);
      // 30s 素材 / 11s 墙钟 = 2.727× 实时：期望值由时长与中位数独立算出。
      expect(summary.p1080!.realtimeFactor, closeTo(30000 / 11000, 0.0001));
    });

    test('分辨率影响系数 = 1080p 中位数 ÷ 720p 中位数', () {
      final summary = summarizeBenchRuns(<BenchRunResult>[
        run(BenchResolution.p1080, 16000),
        run(BenchResolution.p720, 8000),
      ]);

      expect(summary.resolutionCoefficient, closeTo(2.0, 0.0001));
    });

    test('渲染失败或产物不可播的那次不进统计，另列在旁', () {
      final summary = summarizeBenchRuns(<BenchRunResult>[
        run(BenchResolution.p1080, 10000),
        BenchRunResult(
          resolution: BenchResolution.p1080,
          wallClockMs: 500,
          rendered: false,
          artifact: const ArtifactVerdict(
            ok: false,
            problems: <String>['ffmpeg 返回码非 0'],
          ),
        ),
      ]);

      expect(summary.p1080!.medianMs, 10000);
      expect(summary.p1080!.samplesMs, <int>[10000]);
      expect(summary.rejected, hasLength(1));
    });

    test('缺一档时系数为空，不凭空补一个数', () {
      final summary = summarizeBenchRuns(<BenchRunResult>[
        run(BenchResolution.p1080, 10000),
      ]);

      expect(summary.p720, isNull);
      expect(summary.resolutionCoefficient, isNull);
    });
  });

  group('产物可播放性判定', () {
    const good = ArtifactReading(
      durationSeconds: 30.0,
      width: 1920,
      height: 1080,
      hasVideoStream: true,
      hasAudioStream: true,
    );

    test('时长、分辨率、两路流齐备即通过', () {
      final verdict = judgeArtifact(good, expected: BenchResolution.p1080);

      expect(verdict.ok, isTrue);
      expect(verdict.problems, isEmpty);
    });

    test('缺音轨、分辨率不符、时长偏出容差都点出来', () {
      final verdict = judgeArtifact(
        const ArtifactReading(
          durationSeconds: 27.5,
          width: 1280,
          height: 720,
          hasVideoStream: true,
          hasAudioStream: false,
        ),
        expected: BenchResolution.p1080,
      );

      expect(verdict.ok, isFalse);
      expect(verdict.problems.join('｜'), contains('音轨'));
      expect(verdict.problems.join('｜'), contains('1920x1080'));
      expect(verdict.problems.join('｜'), contains('时长'));
    });
  });

  group('编码器组件名解读', () {
    test('从 ffmpeg 日志读出 MediaCodec 组件名并判硬/软', () {
      final pick = parseMediaCodecPick(<String>[
        'ffmpeg version 6.0',
        'MediaCodec started successfully: codec = c2.android.avc.encoder',
      ]);

      expect(pick!.component, 'c2.android.avc.encoder');
      expect(pick.hardwareAccelerated, isFalse);
    });

    test('厂商组件名按硬编处理', () {
      final pick = parseMediaCodecPick(<String>[
        'MediaCodec started successfully: codec = c2.qti.avc.encoder',
      ]);

      expect(pick!.hardwareAccelerated, isTrue);
    });

    test('日志里没有组件名时给空，不猜', () {
      expect(parseMediaCodecPick(<String>['ffmpeg version 6.0']), isNull);
    });
  });

  group('镜像闸门的像素级验收（PSNR 对照）', () {
    test('窗内像未翻的原片、窗外像翻过的原片即通过', () {
      final verdict = judgeFlipGate(
        insideWindow: const PsnrPair(plain: 40.0, flipped: 12.0),
        outsideWindow: const PsnrPair(plain: 11.5, flipped: 38.5),
      );

      expect(verdict.ok, isTrue);
      expect(verdict.problems, isEmpty);
    });

    test('窗外仍像未翻的那份 = 闸门没生效，点出来', () {
      final verdict = judgeFlipGate(
        insideWindow: const PsnrPair(plain: 40.0, flipped: 12.0),
        outsideWindow: const PsnrPair(plain: 39.5, flipped: 12.5),
      );

      expect(verdict.ok, isFalse);
      expect(verdict.problems.join('｜'), contains('窗外'));
    });

    test('解析 ffmpeg psnr 汇总行', () {
      expect(
        parsePsnrAverage(
          'PSNR y:39.99 u:44.29 v:44.35 average:40.85 min:36.1 max:52.3',
        ),
        40.85,
      );
      expect(parsePsnrAverage('frame= 30 fps=0.0'), isNull);
    });
  });

  group('编码器两问：能力输出与组件名探针', () {
    test('能力查询问的是同一个编码器的帮助页', () {
      expect(
        encoderCapabilityArgs(),
        <String>['-hide_banner', '-h', 'encoder=h264_mediacodec'],
      );
    });

    test('组件名探针是一小段带 debug 日志的编码，不产出文件', () {
      final args = encoderProbeArgs();

      expect(args, containsAllInOrder(['-loglevel', 'debug']));
      expect(args, containsAllInOrder(['-c:v', 'h264_mediacodec']));
      expect(args, contains('-f'));
      expect(args.last, 'null');
      expect(args, isNot(contains('out.mp4')));
    });

    test('能力输出里认得出编码器条目', () {
      expect(
        encoderCapabilityName(<String>[
          'Encoder h264_mediacodec [H.264/AVC (MediaCodec)]:',
          '    General capabilities: dr1 delay threads',
        ]),
        'h264_mediacodec',
      );
      expect(encoderCapabilityName(<String>['Codec not found']), isNull);
    });
  });

  group('参考帧滤镜链：与渲染共用同一段取景几何', () {
    test('未翻的那份不含 hflip，翻过的那份含', () {
      final plain = referenceFilterChain(BenchResolution.p1080);
      final flipped = referenceFilterChain(
        BenchResolution.p1080,
        mirrored: true,
      );

      expect(plain, isNot(contains('hflip')));
      expect(flipped, contains('hflip'));
      expect(plain, contains('crop=1728:972:96:54,scale=1920:1080'));
      expect(flipped, contains('crop=1728:972:96:54,scale=1920:1080'));
    });
  });

  group('产物事实的两处独立读数：ffprobe 与整片解码帧数', () {
    const ffprobeJson = """
{
  "streams": [
    {"codec_type": "video", "codec_name": "h264", "width": 1920, "height": 1080},
    {"codec_type": "audio", "codec_name": "aac"}
  ],
  "format": {"duration": "30.016000", "size": "24000000"}
}""";

    test('从 ffprobe 的 JSON 里读出两路流与分辨率时长', () {
      final reading = parseFfprobeOutput(ffprobeJson)!;

      expect(reading.hasVideoStream, isTrue);
      expect(reading.hasAudioStream, isTrue);
      expect(reading.width, 1920);
      expect(reading.height, 1080);
      expect(reading.durationSeconds, closeTo(30.016, 0.001));
    });

    test('只有音轨的产物要能一眼看出（本关卡的第一次真机读数就栽在这）', () {
      final reading = parseFfprobeOutput(
        '{"streams":[{"codec_type":"audio","codec_name":"aac"}],'
        '"format":{"duration":"30.0"}}',
      )!;

      expect(reading.hasVideoStream, isFalse);
      expect(
        judgeArtifact(reading, expected: BenchResolution.p1080).problems,
        contains('缺视频流'),
      );
    });

    test('日志里没有 JSON 时给空，不拿半截数据充数', () {
      expect(parseFfprobeOutput('ffprobe version 6.0\nNo such file'), isNull);
    });

    test('整片解码的帧数从 stats 行读出来', () {
      expect(
        parseDecodedFrameCount(
          'frame=  449 fps=300 q=-0.0 size=N/A time=00:00:14.9 bitrate=N/A'
          '\rframe=  900 fps=310 q=-0.0 size=N/A time=00:00:30.0 bitrate=N/A',
        ),
        900,
      );
      expect(parseDecodedFrameCount('nothing here'), isNull);
    });

    test('解码帧数偏出 30s×30fps 就点出来——掉帧的产物不能算可播', () {
      const reading = ArtifactReading(
        durationSeconds: 30.0,
        width: 1920,
        height: 1080,
        hasVideoStream: true,
        hasAudioStream: true,
      );

      expect(
        judgeArtifact(
          reading,
          expected: BenchResolution.p1080,
          decodedFrames: 900,
        ).ok,
        isTrue,
      );
      final dropped = judgeArtifact(
        reading,
        expected: BenchResolution.p1080,
        decodedFrames: 450,
      );
      expect(dropped.ok, isFalse);
      expect(dropped.problems.join('｜'), contains('帧'));
    });

    test('stats 行进日志不算解码报错，别的行算', () {
      expect(
        hasDecodeErrors('frame=  900 fps=310 q=-0.0 size=N/A\rframe=  901'),
        isFalse,
      );
      expect(
        hasDecodeErrors('frame=  900 fps=310\n[h264 @ 0x1] error while decoding'),
        isTrue,
      );
    });

    test('整片解码命令带上 -stats（没有它读不出帧数）', () {
      expect(decodeCheckArgs('x.mp4'), contains('-stats'));
      expect(decodeCheckArgs('x.mp4').last, '-');
    });
  });
}
