import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/cast/cast_encoder_realtime.dart';
import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:flutter_test/flutter_test.dart';

/// 渲染参数直测（纯件）：滤镜图与命令行**是外部契约**（它决定产物），按快照
/// 式断言其关键片段——不启动 widget、不跑进程。
void main() {
  CastRenderRequest request({
    CastRenderChoices choices = const CastRenderChoices(
      picture: false,
      sound: true,
    ),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastRenderResolution resolution = CastRenderResolution.p1080,
    CastRenderSettings settings = const CastRenderSettings(),
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
    CastRange? range,
  }) => CastRenderRequest(
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    duration: const Duration(minutes: 3),
    choices: choices,
    speedTier: speedTier,
    resolution: resolution,
    settings: settings,
    annotationFingerprint: 'fp-1',
    mirrorFragments: mirrorFragments,
    framingSelection: framingSelection,
    beatClicks: const [],
    range: range,
  );

  /// **这一次的暂存输入**：与请求配套的边车（勾了声音类才有拍声轨、有数拍层
  /// 才有序列清单、画面类且有备注才有贴纸图）。下标按 `-i` 的次序现数一遍
  /// ——测试自己算，不拿被测件的算术当期望。
  CastRenderStaging stagingOf(
    CastRenderRequest request, {
    String? beatTrackPath = '/cache/a.clicks.wav',
    String? beatSlidesPath = '/cache/a.beats.txt',
    List<String> stickerPaths = const [],
  }) {
    var input = 1;
    final overlay = request.beatOverlay;
    final beatTrack = !request.choices.sound || beatTrackPath == null
        ? null
        : CastRenderSidecar(path: beatTrackPath, index: input++);
    final beatSlides =
        !request.choices.picture || overlay == null || beatSlidesPath == null
        ? null
        : CastBeatSlidesInput(
            overlay: overlay,
            sidecar: CastRenderSidecar(path: beatSlidesPath, index: input++),
          );
    return CastRenderStaging(
      beatTrack: beatTrack,
      beatSlides: beatSlides,
      stickers: [
        for (var i = 0; i < request.stickers.length; i++)
          CastStickerInput(
            sticker: request.stickers[i],
            sidecar: CastRenderSidecar(
              path: stickerPaths.length > i
                  ? stickerPaths[i]
                  : '/cache/a.sticker$i.png',
              index: input++,
            ),
          ),
      ],
    );
  }

  List<String> args({
    CastRenderChoices choices = const CastRenderChoices(
      picture: false,
      sound: true,
    ),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastRenderResolution resolution = CastRenderResolution.p1080,
    CastRenderSettings settings = const CastRenderSettings(),
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
    CastRange? range,
    String? beatTrackPath = '/cache/a.clicks.wav',
  }) {
    final buildRequest = request(
      choices: choices,
      speedTier: speedTier,
      resolution: resolution,
      settings: settings,
      mirrorFragments: mirrorFragments,
      framingSelection: framingSelection,
      range: range,
    );
    return buildCastRenderArguments(
      request: buildRequest,
      outputPath: '/cache/a.part',
      staging: stagingOf(buildRequest, beatTrackPath: beatTrackPath),
    );
  }

  /// `-c:v` 后紧跟的那个值（命令行里唯一的「视频编解码器」声明）。
  String videoCodecOf(List<String> arguments) =>
      arguments[arguments.indexOf('-c:v') + 1];

  String filterOf(List<String> arguments) =>
      arguments[arguments.indexOf('-filter_complex') + 1];

  group('只勾声音：视频流原样复制、音轨重编码', () {
    test('视频复制 + 音频 AAC + 混音 + faststart，且不进任何画面滤镜', () {
      final arguments = args();

      expect(videoCodecOf(arguments), 'copy', reason: '秒级出结果靠的就是这一句');
      expect(arguments, containsAllInOrder(['-c:a', 'aac']));
      expect(arguments, contains('/cache/a.clicks.wav'), reason: '拍声轨是第二路输入');
      expect(arguments, containsAllInOrder(['-movflags', '+faststart']));
      expect(arguments, containsAllInOrder(['-f', 'mp4']));
      expect(arguments.last, '/cache/a.part');
      expect(arguments.where((a) => a == '-vf'), isEmpty);
      expect(
        arguments.where((a) => a == '-ss'),
        isEmpty,
        reason: '范围不用快速定位（#26 不做首尾线范围，见票）',
      );
      expect(arguments, isNot(contains('-t')));
    });

    test('滤镜图：源音轨与拍声轨 amix，时长取源片', () {
      final filter = filterOf(args());
      expect(filter, contains('[0:a]aresample=48000'));
      expect(filter, contains('[1:a]aresample=48000'));
      expect(
        filter,
        contains(
          '[amain][abeat]amix=inputs=2:duration=first:dropout_transition=0[aout]',
        ),
      );
      expect(filter, isNot(contains('[0:v]')), reason: '画面这档不进滤镜');
    });

    test('映射：视频取输入流、音频取混音产物', () {
      final arguments = args();
      expect(arguments, containsAllInOrder(['-map', '0:v']));
      expect(arguments, containsAllInOrder(['-map', '[aout]']));
    });

    test('暂存里没有拍声轨 = 这次不混拍声（不按勾选档重推一遍）', () {
      final arguments = args(beatTrackPath: null);

      // 「勾了声音类却没有拍声轨」这条组合在暂存输入里没有位置：装配层读的是
      // 暂存表，表里没有这一路就是这一次没有这一路——没有可抛的非法组合。
      expect(
        arguments,
        isNot(contains('/cache/a.clicks.wav')),
        reason: '暂存表里没有的边车不进命令行',
      );
      expect(filterOf(arguments), isNot(contains('amix')));
      expect(arguments, containsAllInOrder(['-c:a', 'copy']));
    });
  });

  group('勾了画面类：视频重编码、画面滤镜进链', () {
    test('编码器、码率、GOP、帧率、像素格式都显式给出', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: true),
      );

      expect(videoCodecOf(arguments), kCastRenderVideoEncoder);
      expect(arguments, containsAllInOrder(['-b:v', '8M']));
      expect(arguments, containsAllInOrder(['-g', '60']));
      expect(arguments, containsAllInOrder(['-r', '30']));
      expect(arguments, containsAllInOrder(['-pix_fmt', 'yuv420p']));
      expect(arguments, containsAllInOrder(['-movflags', '+faststart']));
    });

    test('画面链以 fps + 编码器接受的像素格式收尾（后四票往中间插滤镜）', () {
      final filter = filterOf(
        args(choices: const CastRenderChoices(picture: true, sound: true)),
      );

      expect(
        filter,
        contains(
          "[0:v]scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(filter, contains('amix=inputs=2'));
    });

    test('勾画面不勾声音：音轨原样复制，不混拍声', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: false),
      );

      expect(videoCodecOf(arguments), kCastRenderVideoEncoder);
      expect(arguments, containsAllInOrder(['-c:a', 'copy']));
      expect(filterOf(arguments), isNot(contains('amix')));
      expect(filterOf(arguments), isNot(contains('aresample')));
      expect(arguments, isNot(contains('/cache/a.clicks.wav')));
    });
  });

  group('都不勾：不装配命令（调用方直接推原片）', () {
    test('报错，而不是给一条空转的转码命令', () {
      expect(
        () => args(choices: const CastRenderChoices.none()),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('投屏倍速档：视频 setpts、音轨 atempo，两者同倍率', () {
    test('0.5 档：画面压到半速、拍声轨同步拉长', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: true),
        speedTier: CastSpeedTier.half,
      );
      final filter = filterOf(arguments);

      expect(filter, contains('setpts=PTS/0.5'));
      expect(filter, contains('atempo=0.5'));
      expect(
        filter,
        contains('[1:a]atempo=0.5,aresample=48000[abeat]'),
        reason: '拍声轨不跟着缩放就会与画面错开',
      );
    });

    test('0.75 档同理（三档各一份副本）', () {
      final filter = filterOf(
        args(
          choices: const CastRenderChoices(picture: true, sound: true),
          speedTier: CastSpeedTier.threeQuarter,
        ),
      );

      expect(filter, contains('setpts=PTS/0.75'));
      expect(filter, contains('atempo=0.75'));
    });

    test('只勾声音 + 非 1×：视频不能复制（复制改不了倍速），改重编码', () {
      final arguments = args(speedTier: CastSpeedTier.half);

      expect(videoCodecOf(arguments), kCastRenderVideoEncoder);
      expect(filterOf(arguments), contains('setpts=PTS/0.5'));
    });

    test('1× 档不写 setpts / atempo（与不设倍速逐字一致）', () {
      final filter = filterOf(
        args(choices: const CastRenderChoices(picture: true, sound: true)),
      );

      expect(filter, isNot(contains('setpts')));
      expect(filter, isNot(contains('atempo')));
    });
  });

  group('画面链里的镜像闸门（#27）：与上屏同一份取值', () {
    const all = CastRenderChoices(picture: true, sound: true);
    const fragment = LocalMirrorFragment(startMs: 1000, endMs: 2000);

    /// 只勾画面类的命令行，按给定的镜像开关与片段表装配。
    List<String> pictureArgs({
      bool globalMirrored = false,
      bool localMirrorEnabled = true,
      List<LocalMirrorFragment> mirrorFragments = const [],
      CastSpeedTier speedTier = CastSpeedTier.full,
    }) => args(
      choices: all,
      speedTier: speedTier,
      settings: CastRenderSettings(
        globalMirrored: globalMirrored,
        localMirrorEnabled: localMirrorEnabled,
      ),
      mirrorFragments: mirrorFragments,
    );

    test('只开全局：链首一枚无窗 hflip，链尾的 vout 不变', () {
      final filter = filterOf(pictureArgs(globalMirrored: true));

      expect(
        filter,
        contains(
          "[0:v]hflip,scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(
        filter.split(';').where((s) => s.contains('[vout]')).single,
        "[0:v]hflip,scale=-2:'min(1080,ih)',setsar=1,fps=30,"
        'format=yuv420p[vout]',
        reason: '镜像只是插进画面链的中段，链尾仍是 [vout]',
      );
    });

    test('只开局部：链首一枚带时间窗的 hflip，窗是半开区间', () {
      final filter = filterOf(pictureArgs(mirrorFragments: const [fragment]));

      expect(
        filter,
        contains(
          "[0:v]hflip=enable='gte(t,1)*lt(t,2)',"
          "scale=-2:'min(1080,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
      );
      expect(filter, isNot(contains('between')));
    });

    test('两个都开：两枚 hflip 依次装上（窗内净不翻）', () {
      final filter = filterOf(
        pictureArgs(globalMirrored: true, mirrorFragments: const [fragment]),
      );

      expect(
        filter,
        contains(
          "[0:v]hflip,hflip=enable='gte(t,1)*lt(t,2)',"
          'scale=-2:\'min(1080,ih)\',setsar=1,fps=30,format=yuv420p[vout]',
        ),
      );
    });

    test('局部镜像总开关关掉：片段整组不参与（链首只剩全局那一枚）', () {
      final filter = filterOf(
        pictureArgs(
          globalMirrored: true,
          localMirrorEnabled: false,
          mirrorFragments: const [fragment],
        ),
      );

      expect(
        filter,
        contains(
          "[0:v]hflip,scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(filter, isNot(contains('enable=')));
    });

    test('都不开：画面链一字不改（与 #26 的底链逐字一致）', () {
      final filter = filterOf(pictureArgs(mirrorFragments: const []));

      expect(
        filter,
        contains(
          "[0:v]scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(filter, isNot(contains('hflip')));
    });

    test('非 1× 档：闸门排在 setpts 之前，enable 判的是源时间轴', () {
      final filter = filterOf(
        pictureArgs(
          globalMirrored: true,
          mirrorFragments: const [fragment],
          speedTier: CastSpeedTier.half,
        ),
      );

      expect(
        filter,
        contains(
          "[0:v]hflip,hflip=enable='gte(t,1)*lt(t,2)',setpts=PTS/0.5,"
          'scale=-2:\'min(1080,ih)\',setsar=1,fps=30,format=yuv420p[vout]',
        ),
        reason:
            '片段是源时间轴上的区间：闸门若排在 setpts 之后，'
            't 已被拉伸，窗就会与倍速档错开',
      );
    });

    test('只勾声音类：视频流原样复制，镜像闸门不进滤镜图', () {
      final arguments = args(
        settings: const CastRenderSettings(globalMirrored: true),
        mirrorFragments: const [fragment],
      );
      final filter = filterOf(arguments);

      expect(videoCodecOf(arguments), 'copy');
      expect(filter, isNot(contains('[0:v]')));
      expect(filter, isNot(contains('hflip')), reason: '画面不重编码，镜像自然无从烤进去');
    });

    test('只勾声音类 + 非 1×：视频为重编码，但镜像闸门仍不进链', () {
      final filter = filterOf(
        args(
          settings: const CastRenderSettings(globalMirrored: true),
          mirrorFragments: const [fragment],
          speedTier: CastSpeedTier.half,
        ),
      );

      expect(
        filter,
        contains(
          "[0:v]setpts=PTS/0.5,scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(
        filter,
        isNot(contains('hflip')),
        reason: '这里重编码只是为了倍速：用户没勾画面类，镜像就不该被烤进去',
      );
    });
  });

  group('画面链里的取景窗口（#28）：与上屏同一份取值', () {
    const all = CastRenderChoices(picture: true, sound: true);
    const selection = FramingSelection(
      left: 0.1,
      top: 0.2,
      right: 0.9,
      bottom: 0.8,
    );

    /// 只勾画面类的命令行，按给定的取景/镜像取值装配。
    List<String> pictureArgs({
      FramingSelection? framingSelection,
      bool globalMirrored = false,
      List<LocalMirrorFragment> mirrorFragments = const [],
      CastSpeedTier speedTier = CastSpeedTier.full,
    }) => args(
      choices: all,
      speedTier: speedTier,
      settings: CastRenderSettings(globalMirrored: globalMirrored),
      mirrorFragments: mirrorFragments,
      framingSelection: framingSelection,
    );

    test('取景：裁切 + 偶数收尾 + 方像素插进画面链中段，链尾不变', () {
      final filter = filterOf(pictureArgs(framingSelection: selection));

      expect(
        filter,
        contains(
          '[0:v]crop=w=max(2\\,floor(iw*0.8/2)*2):'
          'h=max(2\\,floor(ih*0.6/2)*2):'
          'x=min(floor(iw*0.1/2)*2\\,iw-ow):'
          'y=min(floor(ih*0.2/2)*2\\,ih-oh),'
          'scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,'
          'scale=-2:\'min(1080,ih)\',setsar=1,fps=30,format=yuv420p[vout]',
        ),
      );
    });

    test('镜像与取景同时生效：翻转节点排在裁切之前（先翻、后切窗）', () {
      final filter = filterOf(
        pictureArgs(
          framingSelection: selection,
          globalMirrored: true,
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 2000),
          ],
        ),
      );

      expect(
        filter,
        contains(
          "[0:v]hflip,hflip=enable='gte(t,1)*lt(t,2)',"
          'crop=w=max(2\\,floor(iw*0.8/2)*2)',
        ),
        reason: '手机上翻转是画面件的显示层变换、取景是包在它外面的剪辑窗',
      );
    });

    test('非 1× 档：取景与镜像都在 setpts 之前（窗不随倍速漂移）', () {
      final filter = filterOf(
        pictureArgs(
          framingSelection: selection,
          globalMirrored: true,
          speedTier: CastSpeedTier.half,
        ),
      );

      expect(
        filter,
        contains(
          '[0:v]hflip,crop=w=max(2\\,floor(iw*0.8/2)*2):'
          'h=max(2\\,floor(ih*0.6/2)*2):'
          'x=min(floor(iw*0.1/2)*2\\,iw-ow):'
          'y=min(floor(ih*0.2/2)*2\\,ih-oh),'
          'scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,'
          'setpts=PTS/0.5,'
          "scale=-2:'min(1080,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
      );
    });

    test('未取景：取景的裁切与偶数收尾都不进链（与整屏 contain 逐位一致）', () {
      final filter = filterOf(pictureArgs());

      expect(
        filter,
        contains(
          "[0:v]scale=-2:'min(1080,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
        reason: '链尾只剩分辨率档那一枚（保证档：高度封在 1080 行）',
      );
      expect(filter, isNot(contains('crop=')));
      expect(
        filter,
        isNot(contains('scale=trunc(')),
        reason: '取景那枚偶数收尾缩放不进链',
      );
    });

    test('整帧选区也是未取景：链与「没调过」逐字一致', () {
      expect(
        filterOf(
          pictureArgs(framingSelection: const FramingSelection.fullFrame()),
        ),
        filterOf(pictureArgs()),
      );
    });

    test('只勾声音类：取景不进滤镜图（画面不重编码，取景无从烤进去）', () {
      final arguments = args(
        settings: const CastRenderSettings(),
        framingSelection: selection,
      );
      final filter = filterOf(arguments);

      expect(videoCodecOf(arguments), 'copy');
      expect(filter, isNot(contains('[0:v]')));
      expect(filter, isNot(contains('crop=')));
    });

    test('只勾声音类 + 非 1×：视频为重编码，但取景仍不进链', () {
      final filter = filterOf(
        args(framingSelection: selection, speedTier: CastSpeedTier.half),
      );

      expect(
        filter,
        contains(
          "[0:v]setpts=PTS/0.5,scale=-2:'min(1080,ih)',setsar=1,fps=30,"
          'format=yuv420p[vout]',
        ),
      );
      expect(
        filter,
        isNot(contains('crop=')),
        reason: '这里重编码只是为了倍速：用户没勾画面类，取景就不该被烤进去',
      );
    });
  });

  group('编码参数与容器', () {
    test('音频一路显式给出编码、码率、采样率与声道数', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: true),
      );

      expect(
        arguments,
        containsAllInOrder([
          '-c:a',
          'aac',
          '-b:a',
          '192k',
          '-ar',
          '48000',
          '-ac',
          '2',
        ]),
      );
    });

    test('覆盖已有文件、安静启动（不给用户看 ffmpeg 的横幅）', () {
      final arguments = args();
      expect(arguments, containsAllInOrder(['-hide_banner', '-y']));
    });
  });

  group('画面链里的范围（#37）：首线→尾线落在链的中段', () {
    const all = CastRenderChoices(picture: true, sound: true);
    const range = CastRange(
      start: Duration(seconds: 2),
      end: Duration(seconds: 5),
    );
    const selection = FramingSelection(
      left: 0.1,
      top: 0.2,
      right: 0.9,
      bottom: 0.8,
    );
    const fragment = LocalMirrorFragment(startMs: 3000, endMs: 4000);

    /// 只勾画面类的命令行，按给定取值装配。
    List<String> pictureArgs({
      CastRange? range = range,
      FramingSelection? framingSelection,
      bool globalMirrored = false,
      List<LocalMirrorFragment> mirrorFragments = const [],
      CastSpeedTier speedTier = CastSpeedTier.full,
    }) => args(
      choices: all,
      speedTier: speedTier,
      settings: CastRenderSettings(globalMirrored: globalMirrored),
      mirrorFragments: mirrorFragments,
      framingSelection: framingSelection,
      range: range,
    );

    /// 链尾那条（接 `[vout]` 的那一条）——范围与前几票的节点次序都在它身上看。
    String tailChainOf(List<String> arguments) =>
        filterOf(arguments).split(';').firstWhere((s) => s.contains('[vout]'));

    test('范围：trim + 基准归零插在链的中段，链尾的 vout 不变', () {
      final arguments = pictureArgs();

      expect(
        filterOf(arguments),
        contains(
          '[0:v]trim=start=2:end=5,setpts=PTS-STARTPTS,'
          'scale=-2:\'min(1080,ih)\',setsar=1,fps=30,format=yuv420p[vout]',
        ),
      );
      expect(arguments, containsAllInOrder(['-map', '[vout]']));
    });

    test('不用快速定位：命令行里没有 -ss / -t / -to（范围只在滤镜链里）', () {
      final arguments = pictureArgs(speedTier: CastSpeedTier.half);

      expect(arguments.where((a) => a == '-ss'), isEmpty);
      expect(arguments, isNot(contains('-t')));
      expect(arguments, isNot(contains('-to')));
      expect(
        filterOf(arguments),
        contains('trim=start=2:end=5'),
        reason: '范围由链中段的 trim 表达，不是命令行首的定位',
      );
    });

    test('范围排在全部层之后、倍速 setpts 之前（闸门与窗仍判源时间轴）', () {
      final filter = filterOf(
        pictureArgs(
          globalMirrored: true,
          mirrorFragments: const [fragment],
          framingSelection: selection,
        ),
      );
      final tail = tailChainOf(
        pictureArgs(
          globalMirrored: true,
          mirrorFragments: const [fragment],
          framingSelection: selection,
        ),
      );

      expect(
        tail,
        startsWith(
          "[0:v]hflip,hflip=enable='gte(t,3)*lt(t,4)',"
          'crop=w=max(2\\,floor(iw*0.8/2)*2)',
        ),
        reason: '镜像闸门与取景窗口照旧，窗判的仍是源时间轴上的 3–4 秒',
      );
      expect(
        tail.indexOf('trim=start=2:end=5'),
        greaterThan(tail.indexOf('setsar=1')),
        reason: '收窄发生在取景之后：先按整片判哪一帧该翻、该切哪块',
      );
      expect(
        tail.indexOf('trim=start=2:end=5'),
        lessThan(tail.indexOf('fps=30')),
        reason: '范围在链的中段，链尾的 fps / 像素格式收口一字不改',
      );
      expect(filter, isNot(contains('-ss')));
    });

    test('逐档：范围窗口逐字一致、位置不漂移，setpts 排在 trim 之后', () {
      final tails = <CastSpeedTier, String>{
        for (final tier in CastSpeedTier.values)
          tier: tailChainOf(pictureArgs(speedTier: tier)),
      };

      for (final entry in tails.entries) {
        expect(
          entry.value,
          contains('trim=start=2:end=5,setpts=PTS-STARTPTS'),
          reason: '${entry.key.token} 档：窗在源时间轴上，逐字一致',
        );
      }
      expect(
        tails[CastSpeedTier.full],
        contains(
          'trim=start=2:end=5,setpts=PTS-STARTPTS,'
          "scale=-2:'min(1080,ih)',setsar=1,fps=30",
        ),
        reason: '1× 档没有第二句 setpts（与不设倍速一致）：trim 之后直接是分辨率档',
      );
      expect(
        tails[CastSpeedTier.half],
        contains(
          'trim=start=2:end=5,setpts=PTS-STARTPTS,setpts=PTS/0.5,'
          "scale=-2:'min(1080,ih)',setsar=1,fps=30",
        ),
        reason: '范围先收窄、倍速后缩放：先后定死，窗不随档漂移',
      );
      expect(
        tails[CastSpeedTier.threeQuarter],
        contains('setpts=PTS-STARTPTS,setpts=PTS/0.75'),
      );
    });

    test('音轨与拍声轨收在同一段上（atrim 各接一份，再 mix）', () {
      final filter = filterOf(pictureArgs(speedTier: CastSpeedTier.half));

      expect(
        filter,
        contains(
          '[0:a]atrim=start=2:end=5,asetpts=PTS-STARTPTS,'
          'atempo=0.5,aresample=48000[amain]',
        ),
      );
      expect(
        filter,
        contains(
          '[1:a]atrim=start=2:end=5,asetpts=PTS-STARTPTS,'
          'atempo=0.5,aresample=48000[abeat]',
        ),
        reason: '拍声轨不跟着收就会与画面错开',
      );
      expect(filtersAmixOf(filter), contains('[amain][abeat]amix=inputs=2'));
    });

    test('整片范围（未设首尾线）与不设范围逐字一致', () {
      const whole = CastRange(
        start: Duration.zero,
        end: Duration(minutes: 3),
      );

      expect(
        filterOf(pictureArgs(range: whole)),
        filterOf(pictureArgs(range: null)),
      );
      expect(
        args(choices: all, range: whole, speedTier: CastSpeedTier.half),
        args(choices: all, range: null, speedTier: CastSpeedTier.half),
      );
    });

    test('空区间 / 倒置区间：不装任何范围节点', () {
      for (final degenerate in const [
        CastRange(start: Duration(seconds: 5), end: Duration(seconds: 5)),
        CastRange(start: Duration(seconds: 5), end: Duration(seconds: 3)),
      ]) {
        expect(
          filterOf(pictureArgs(range: degenerate)),
          isNot(contains('trim=')),
          reason: '$degenerate 没有可收的一段',
        );
      }
    });
  });

  group('复制档明确不接受范围（只勾声音类 + 1×）', () {
    const range = CastRange(
      start: Duration(seconds: 2),
      end: Duration(seconds: 5),
    );

    test('复制档：视频原样复制、音轨照整片混，范围一个节点都不进', () {
      final arguments = args(range: range);

      expect(videoCodecOf(arguments), 'copy', reason: '秒级出结果靠的就是这一句');
      expect(arguments, containsAllInOrder(['-c:a', 'aac']));
      expect(
        filterOf(arguments),
        isNot(contains('trim=')),
        reason: '复制出来的流改不了长度：这一档明确不收范围',
      );
      expect(
        filterOf(arguments),
        isNot(contains('atrim=')),
        reason: '只收画面不收声音会让两者对不上，故整片一起推',
      );
      expect(
        filterOf(arguments),
        contains('[0:a]aresample=48000[amain]'),
        reason: '音轨这一路也照整片来（没有 atrim）',
      );
      expect(arguments, containsAllInOrder(['-map', '0:v']));
      expect(arguments, isNot(contains('-t')));
      expect(arguments.where((a) => a == '-ss'), isEmpty);
    });

    test('只勾声音类 + 非 1×：视频要重编码，范围照收（画面被解出过）', () {
      final arguments = args(range: range, speedTier: CastSpeedTier.half);

      expect(videoCodecOf(arguments), kCastRenderVideoEncoder);
      expect(
        filterOf(arguments),
        contains(
          '[0:v]trim=start=2:end=5,setpts=PTS-STARTPTS,setpts=PTS/0.5,'
          'scale=-2:\'min(1080,ih)\',setsar=1,fps=30,format=yuv420p[vout]',
        ),
      );
      expect(
        filterOf(arguments),
        contains('[1:a]atrim=start=2:end=5,asetpts=PTS-STARTPTS,atempo=0.5'),
      );
    });

    test('勾画面类不勾声音 + 范围：音轨跟着收窄（复制改不了范围）', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: false),
        range: range,
        beatTrackPath: null,
      );

      expect(
        arguments,
        containsAllInOrder(['-c:a', 'aac']),
        reason: '复制整片音轨会与收窄后的画面错开，只能重编码一条同段的',
      );
      expect(arguments, containsAllInOrder(['-map', '[amain]']));
      expect(arguments, isNot(contains('/cache/a.clicks.wav')));
      expect(
        filterOf(arguments),
        contains('[0:a]atrim=start=2:end=5,asetpts=PTS-STARTPTS,'
            'aresample=48000[amain]'),
      );
    });

    test('勾画面类不勾声音、无范围：音轨仍原样复制（与今天逐字一致）', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: false),
        beatTrackPath: null,
      );

      expect(arguments, containsAllInOrder(['-c:a', 'copy']));
      expect(arguments, containsAllInOrder(['-map', '0:a']));
    });

    test('不勾声音 + 非 1×：音轨跟着缩放（复制改不了时长，不跟就错开）', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: true, sound: false),
        speedTier: CastSpeedTier.half,
        beatTrackPath: null,
      );

      expect(arguments, containsAllInOrder(['-c:a', 'aac']));
      expect(
        filterOf(arguments),
        contains('[0:a]atempo=0.5,aresample=48000[amain]'),
        reason: '画面按 setpts 拉长了，音轨不跟就会与画面错开',
      );
    });
  });

  group('分辨率档：保证档钉 1080 行，不保证降到 720p', () {
    const picture = CastRenderChoices(picture: true, sound: true);

    test('问编码器的那一档帧率就是渲染帧率（问什么就渲什么）', () {
      expect(
        kCastGuaranteeQueryTarget.fps,
        kCastRenderFps,
        reason: '性能点是按这个帧率问的，编码参数里的 -r 也是它：两处不许各写一个数',
      );
    });

    test('保证档：链尾高度封在 1080 行（只降不升）、宽度按源比例，码率 8M', () {
      final arguments = args(choices: picture);
      final filter = filterOf(arguments);

      expect(
        filter,
        contains(
          "[0:v]scale=-2:'min(1080,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
        reason: '答案只保证到问的那一档：4K 源也收在 1080 行上，不放行更大的画面',
      );
      expect(arguments, containsAllInOrder(['-b:v', '8M']));
    });

    test('720p 档：链尾高度封在 720 行（只降不升）、宽度按源比例，码率 4M', () {
      final arguments = args(
        choices: picture,
        resolution: CastRenderResolution.p720,
      );

      expect(
        filterOf(arguments),
        contains(
          "[0:v]scale=-2:'min(720,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
        reason: '高度取 min(720,ih)：裁切后不足 720 行的选区原样留着，不放大',
      );
      expect(arguments, containsAllInOrder(['-b:v', '4M']));
    });

    test('720p 档接在镜像/取景/贴纸之后、链尾 fps 之前（层序不动）', () {
      final filter = filterOf(
        args(
          choices: picture,
          resolution: CastRenderResolution.p720,
          settings: const CastRenderSettings(globalMirrored: true),
          framingSelection: const FramingSelection(
            left: 0.1,
            top: 0.2,
            right: 0.9,
            bottom: 0.8,
          ),
        ),
      );

      expect(
        filter,
        contains(
          ',scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,'
          "scale=-2:'min(720,ih)',setsar=1,fps=30,format=yuv420p[vout]",
        ),
      );
    });

    test('只勾声音 + 1×：视频原样复制，分辨率档不进命令（没有可降的编码）', () {
      final arguments = args(resolution: CastRenderResolution.p720);

      expect(videoCodecOf(arguments), 'copy');
      expect(filterOf(arguments), isNot(contains('[0:v]')));
      expect(arguments, isNot(contains('-b:v')));
    });

    test('只勾声音 + 非 1×：视频重编码，分辨率档照样生效', () {
      final arguments = args(
        speedTier: CastSpeedTier.half,
        resolution: CastRenderResolution.p720,
      );

      expect(videoCodecOf(arguments), kCastRenderVideoEncoder);
      expect(
        filterOf(arguments),
        contains(
          "[0:v]setpts=PTS/0.5,scale=-2:'min(720,ih)',setsar=1,"
          'fps=30,format=yuv420p[vout]',
        ),
      );
      expect(arguments, containsAllInOrder(['-b:v', '4M']));
    });
  });
}

/// `amix` 那一条节点（链里唯一一条把两条音轨合起来的）。
String filtersAmixOf(String filter) =>
    filter.split(';').firstWhere((node) => node.contains('amix'));
