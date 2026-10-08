import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:dance_learning_app/cast/cast_range_gate.dart';
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:flutter_test/flutter_test.dart';

/// 数拍层进命令行的直测（`#30`）：**数拍层的输入与节点位置是外部契约**
/// （它决定产物与真机开销），按关键片段断言。
void main() {
  CastBeatCountOverlay overlay({
    List<CastBeatCountRow>? rows,
    double centerX = 0.5,
    double centerY = 0.25,
    double widthFraction = 0.3,
    double heightFraction = 0.2,
  }) => CastBeatCountOverlay(
    rows:
        rows ??
        const <CastBeatCountRow>[
          CastBeatCountRow(
            startMs: 0,
            endMs: 1000,
            text: CastBeatCountText(eightCount: '0', beatCount: '8'),
          ),
          CastBeatCountRow(
            startMs: 1000,
            endMs: 2000,
            text: CastBeatCountText(eightCount: '1', beatCount: '1'),
          ),
        ],
    centerX: centerX,
    centerY: centerY,
    widthFraction: widthFraction,
    heightFraction: heightFraction,
    imageBytesOf: (index) async => Uint8List.fromList(<int>[index]),
  );

  CastRenderRequest request({
    CastRenderChoices choices = const CastRenderChoices.all(),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastBeatCountOverlay? beatOverlay,
    List<CastSticker> stickers = const [],
    CastRange? range,
  }) => CastRenderRequest(
    videoPath: '/videos/a.mp4',
    videoId: 'vid-a',
    duration: const Duration(minutes: 3),
    choices: choices,
    speedTier: speedTier,
    settings: const CastRenderSettings(),
    annotationFingerprint: 'fp-1',
    stickers: stickers,
    beatOverlay: beatOverlay,
    beatClicks: const [],
    range: range,
  );

  CastSticker sticker() => CastSticker(
    imageBytesOf: () async => Uint8List.fromList(const <int>[1]),
    startMs: 0,
    endMs: 1000,
    centerX: 0.5,
    centerY: 0.5,
    widthFraction: 0.2,
    heightFraction: 0.1,
  );

  List<String> args({
    CastRenderChoices choices = const CastRenderChoices.all(),
    CastSpeedTier speedTier = CastSpeedTier.full,
    CastBeatCountOverlay? beatOverlay,
    List<CastSticker> stickers = const [],
    CastRange? range,
    String? beatSlidesPath = '/cache/a.beats.txt',
  }) => buildCastRenderArguments(
    request: request(
      choices: choices,
      speedTier: speedTier,
      beatOverlay: beatOverlay,
      stickers: stickers,
      range: range,
    ),
    outputPath: '/cache/a.part',
    beatTrackPath: '/cache/a.clicks.wav',
    beatSlidesPath: beatSlidesPath,
    stickerPaths: [
      for (var i = 0; i < stickers.length; i++) '/cache/a.sticker$i.png',
    ],
  );

  String filterOf(List<String> arguments) =>
      arguments[arguments.indexOf('-filter_complex') + 1];

  group('数拍层的输入是那份图像序列清单', () {
    test('清单按 `-f concat -safe 0 -i` 给进，排在拍声轨之后、贴纸之前', () {
      final arguments = args(
        beatOverlay: overlay(),
        stickers: <CastSticker>[sticker()],
      );

      expect(
        arguments,
        containsAllInOrder(<String>[
          '-i',
          '/videos/a.mp4',
          '-i',
          '/cache/a.clicks.wav',
          '-f',
          'concat',
          '-safe',
          '0',
          '-i',
          '/cache/a.beats.txt',
          '-i',
          '/cache/a.sticker0.png',
        ]),
      );
    });

    test('贴纸的输入下标跟着数拍层顺延（错位比多喂一个输入危险得多）', () {
      final arguments = args(
        beatOverlay: overlay(),
        stickers: <CastSticker>[sticker()],
      );

      // 0 = 源片、1 = 拍声轨、2 = 数拍序列、3 = 第一条贴纸。
      expect(filterOf(arguments), contains('[3:v]format=rgba,fps=30[csti0]'));
      expect(filterOf(arguments), contains('[2:v]format=rgba,fps=30[bseq2]'));
    });

    test('没装这一层时命令行里没有 concat 输入、也没有数拍节点', () {
      final arguments = args();

      expect(arguments, isNot(contains('concat')));
      expect(filterOf(arguments), isNot(contains('bseq')));
      expect(filterOf(arguments), isNot(contains('bov')));
    });

    test('只勾声音类：数拍是画面内容类的东西，不进命令', () {
      final arguments = args(
        choices: const CastRenderChoices(picture: false, sound: true),
        beatOverlay: overlay(),
      );

      expect(arguments, isNot(contains('concat')));
      expect(filterOf(arguments), isNot(contains('bseq')));
    });

    test('装了却没有清单路径 = 编程错误（宁可不装配一条读不出东西的链）', () {
      expect(
        () => args(beatOverlay: overlay(), beatSlidesPath: null),
        throwsArgumentError,
      );
    });
  });

  group('链上的位置与层序', () {
    test('数拍接在取景之后、倍速 setpts 之前（时间窗判的是源时间轴）', () {
      final filter = filterOf(
        args(
          beatOverlay: overlay(),
          speedTier: CastSpeedTier.half,
        ),
      );

      expect(filter, contains('[0:v]null[vbase]'));
      expect(
        filter.indexOf('[2:v]format=rgba,fps=30[bseq2]'),
        lessThan(filter.indexOf('setpts=PTS/0.5')),
        reason: '排在 setpts 之前，窗才不随倍速档漂移',
      );
    });

    test('层序：数拍在贴纸之下（与上屏的挂载次序一致）', () {
      final filter = filterOf(
        args(beatOverlay: overlay(), stickers: <CastSticker>[sticker()]),
      );

      expect(filter.indexOf('bseq2'), lessThan(filter.indexOf('csti0')));
      expect(
        filter,
        contains('eof_action=repeat[vbeat]'),
        reason: '数拍链的输出标签交给贴纸层当起点',
      );
      expect(filter, contains('[vstk]fps=30,format=yuv420p[vout]'));
    });

    test('数拍那一层只有一份序列输入与一个叠加节点（不逐拍建节点）', () {
      final filter = filterOf(args(beatOverlay: overlay()));

      expect(RegExp(r'overlay=').allMatches(filter).length, 1);
      expect(filter, isNot(contains('enable=')));
      expect(filter, isNot(contains('drawtext')));
    });
  });

  group('范围（#37）与层序：收窄发生在最后一层之后', () {
    const range = CastRange(
      start: Duration(seconds: 2),
      end: Duration(seconds: 5),
    );

    test('数拍 + 贴纸 + 范围：trim 挂在最后一个 overlay 的输出上', () {
      final filter = filterOf(
        args(
          beatOverlay: overlay(),
          stickers: <CastSticker>[sticker()],
          range: range,
        ),
      );

      expect(
        filter,
        contains(
          '[vstk]trim=start=2:end=5,setpts=PTS-STARTPTS,'
          'fps=30,format=yuv420p[vout]',
        ),
        reason: '层都看过整片之后才裁范围；第二路输入因此仍与主片同轴',
      );
      expect(
        filter.indexOf('trim=start=2:end=5'),
        greaterThan(filter.lastIndexOf('overlay=')),
      );
      expect(
        filter.indexOf('trim=start=2:end=5'),
        greaterThan(filter.indexOf('csti0')),
      );
      expect(filter, isNot(contains('-ss')));
    });

    test('范围 + 0.5× 档：trim 之后才是倍速 setpts（窗不随档漂移）', () {
      final filter = filterOf(
        args(
          beatOverlay: overlay(),
          range: range,
          speedTier: CastSpeedTier.half,
        ),
      );

      expect(
        filter,
        contains(
          '[vbeat]trim=start=2:end=5,setpts=PTS-STARTPTS,setpts=PTS/0.5,'
          'fps=30,format=yuv420p[vout]',
        ),
      );
      expect(
        filter.indexOf('trim=start=2:end=5'),
        lessThan(filter.indexOf('setpts=PTS/0.5')),
      );
    });

    test('数拍序列本身仍覆盖整片（清单不由范围裁剪：裁的是链上的帧）', () {
      // 清单正文（每格的时长）由 `castBeatSlidesContent` 从逐拍行生成，与范围
      // 无关；范围只在链上把范围外的帧丢掉——序列因此不会整体错位。
      final arguments = args(beatOverlay: overlay(), range: range);

      expect(arguments, contains('-f'));
      expect(arguments, contains('/cache/a.beats.txt'));
      expect(filterOf(arguments), contains('bseq2'));
    });
  });
}
