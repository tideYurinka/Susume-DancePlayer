import 'package:dance_learning_app/annotation/framing_selection.dart';
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
    CastRenderSettings settings = const CastRenderSettings(),
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
  }) => CastRenderRequest(
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    duration: const Duration(minutes: 3),
    choices: choices,
    speedTier: speedTier,
    settings: settings,
    annotationFingerprint: 'fp-1',
    mirrorFragments: mirrorFragments,
    framingSelection: framingSelection,
    beatClicks: const [],
  );

  List<String> args({
    CastRenderChoices choices = const CastRenderChoices(
      picture: false,
      sound: true,
    ),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastRenderSettings settings = const CastRenderSettings(),
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
    String? beatTrackPath = '/cache/a.clicks.wav',
  }) => buildCastRenderArguments(
    request: request(
      choices: choices,
      speedTier: speedTier,
      settings: settings,
      mirrorFragments: mirrorFragments,
      framingSelection: framingSelection,
    ),
    outputPath: '/cache/a.part',
    beatTrackPath: beatTrackPath,
  );

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

    test('只勾声音却没有拍声轨：报错（不悄悄推一条没有拍声的「副本」）', () {
      expect(() => args(beatTrackPath: null), throwsA(isA<ArgumentError>()));
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

      expect(filter, contains('[0:v]fps=30,format=yuv420p[vout]'));
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

      expect(filter, contains('[0:v]hflip,fps=30,format=yuv420p[vout]'));
      expect(
        filter.split(';').where((s) => s.contains('[vout]')).single,
        '[0:v]hflip,fps=30,format=yuv420p[vout]',
        reason: '镜像只是插进画面链的中段，链尾仍是 [vout]',
      );
    });

    test('只开局部：链首一枚带时间窗的 hflip，窗是半开区间', () {
      final filter = filterOf(pictureArgs(mirrorFragments: const [fragment]));

      expect(
        filter,
        contains(
          "[0:v]hflip=enable='gte(t,1)*lt(t,2)',fps=30,format=yuv420p[vout]",
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
          'fps=30,format=yuv420p[vout]',
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

      expect(filter, contains('[0:v]hflip,fps=30,format=yuv420p[vout]'));
      expect(filter, isNot(contains('enable=')));
    });

    test('都不开：画面链一字不改（与 #26 的底链逐字一致）', () {
      final filter = filterOf(pictureArgs(mirrorFragments: const []));

      expect(filter, contains('[0:v]fps=30,format=yuv420p[vout]'));
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
          'fps=30,format=yuv420p[vout]',
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
        contains('[0:v]setpts=PTS/0.5,fps=30,format=yuv420p[vout]'),
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
          'fps=30,format=yuv420p[vout]',
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
          'setpts=PTS/0.5,fps=30,format=yuv420p[vout]',
        ),
      );
    });

    test('未取景：裁切与缩放都不进链（与整屏 contain 逐位一致）', () {
      final filter = filterOf(pictureArgs());

      expect(filter, contains('[0:v]fps=30,format=yuv420p[vout]'));
      expect(filter, isNot(contains('crop=')));
      expect(filter, isNot(contains('scale=')));
      expect(filter, isNot(contains('setsar')));
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
        contains('[0:v]setpts=PTS/0.5,fps=30,format=yuv420p[vout]'),
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
}
