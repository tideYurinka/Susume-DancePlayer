import 'dart:typed_data';

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart'
    show NoteGeometry;
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/cast/cast_sticker_gate.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:dance_learning_app/player/note_sticker_layout.dart'
    show noteStickerRect;
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter/material.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';

/// 投屏贴纸闸门直测（纯件）：**第二路输入**与 `overlay` 节点是外部契约（它
/// 决定产物），按关键片段快照式断言；判定不拿被测代码反算，走两条独立的路：
///
/// 1. **与上屏同源**：期望值来自播放页真正用来画贴纸的那一份数学
///    （[noteStickerRect] —— 渲染矩形即命中矩形、上屏唯一的一处换算），本闸门
///    的落位与它逐点比；
/// 2. **与镜像闸门同判**：分段的那一半来自 [SourceVideoFlip]（源视频面翻转的
///    唯一声明处），期望值按它逐帧读出。
void main() {
  CastSticker sticker({
    int startMs = 1000,
    int endMs = 3000,
    double centerX = 0.3,
    double centerY = 0.2,
    double widthFraction = 0.25,
    double heightFraction = 0.1,
  }) => CastSticker(
    imageBytesOf: () async => Uint8List.fromList(const [1, 2, 3]),
    startMs: startMs,
    endMs: endMs,
    centerX: centerX,
    centerY: centerY,
    widthFraction: widthFraction,
    heightFraction: heightFraction,
  );

  /// **手机显示模型**：上屏那份贴纸矩形（归一化到它自己的画面矩形）。
  ///
  /// 走播放页真正那一条路（[noteStickerRect]），尺寸按「尺寸分数 × 画面矩形」
  /// 换算成像素——上屏量测到的贴纸尺寸除以画面矩形就是这两个分数，因此这里
  /// 不是第二份口径。
  ({double centerX, double centerY}) onScreenPlacement({
    required CastSticker sheet,
    required FramingSelection? selection,
    required bool mirrored,
    Size picture = const Size(960, 540),
  }) {
    final rect = noteStickerRect(
      geometry: NoteGeometry(centerX: sheet.centerX, centerY: sheet.centerY),
      contentRect: Offset.zero & picture,
      stickerSize: Size(
        sheet.widthFraction * picture.width,
        sheet.heightFraction * picture.height,
      ),
      faceDirection: mirrored ? FaceDirection.mirrored : FaceDirection.original,
      selection: selection,
    );
    return (
      centerX: rect.center.dx / picture.width,
      centerY: rect.center.dy / picture.height,
    );
  }

  SourceVideoFlip flip({
    bool globalMirrored = false,
    bool localMirrorEnabled = true,
    List<LocalMirrorFragment> fragments = const [],
  }) => SourceVideoFlip(
    globalMirrored: globalMirrored,
    localMirrorEnabled: localMirrorEnabled,
    fragments: fragments,
  );

  /// 装配一条画面类命令，并把滤镜图读出来（贴纸路径与请求里的贴纸一一对应）。
  List<String> graphOf({
    List<CastSticker> stickers = const [],
    bool globalMirrored = false,
    bool localMirrorEnabled = true,
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
    bool picture = true,
    bool sound = false,
  }) {
    final request = CastRenderRequest(
      videoPath: '/videos/a.mp4',
      videoId: 'vid-a',
      duration: const Duration(minutes: 3),
      choices: CastRenderChoices(picture: picture, sound: sound),
      speedTier: CastSpeedTier.full,
      settings: CastRenderSettings(
        globalMirrored: globalMirrored,
        localMirrorEnabled: localMirrorEnabled,
      ),
      annotationFingerprint: 'fp-1',
      mirrorFragments: mirrorFragments,
      framingSelection: framingSelection,
      stickers: stickers,
    );
    // **装哪几条贴纸输入读的是与编排层同一条规则**（`castStagedStickerSlots`，
    // `#21` 整改）：替身不再无条件为每条贴纸造输入（不勾画面类就一条不装）。
    final slots = castStagedStickerSlots(request);
    return buildCastRenderArguments(
      request: request,
      outputPath: '/cache/a.part',
      staging: CastRenderStaging(
        beatTrack: sound
            ? const CastRenderSidecar(path: '/cache/a.clicks.wav', index: 1)
            : null,
        stickers: [
          for (var i = 0; i < slots.length; i++)
            CastStickerInput(
              sticker: stickers[slots[i]],
              sidecar: CastRenderSidecar(
                path: '/cache/a.sticker${slots[i]}.png',
                index: (sound ? 2 : 1) + i,
              ),
            ),
        ],
      ),
    );
  }

  String filterOf(List<String> arguments) =>
      arguments[arguments.indexOf('-filter_complex') + 1];

  /// 滤镜图里 `overlay=` 节点的关键片段（enable 与落位）。
  List<String> overlayNodesOf(List<String> arguments) =>
      filterOf(arguments)
          .split(';')
          .where((node) => node.contains('overlay='))
          .toList();

  /// `overlay` 节点的 enable 表达式读回成判据：只认本域产出的语法。
  bool Function(double) enableReaderOf(String node) {
    final match = RegExp(r"enable='([^']+)'").firstMatch(node)!;
    final terms = match.group(1)!.split('+');
    final windows = <(double, double)>[];
    for (final term in terms) {
      final window = RegExp(r'^gte\(t,([\d.]+)\)\*lt\(t,([\d.]+)\)$')
          .firstMatch(term);
      if (window == null) throw FormatException('读不出的时间窗：$term');
      windows.add((
        double.parse(window.group(1)!),
        double.parse(window.group(2)!),
      ));
    }
    return (seconds) => windows.any((w) => w.$1 <= seconds && seconds < w.$2);
  }

  /// `overlay` 节点落位读回：`x=(W*<u>)-(w/2)` 里的 `<u>`。
  double overlayCenterXOf(String node) {
    final match = RegExp(r'x=\(W\*([-\d.]+)\)-\(w/2\)').firstMatch(node);
    if (match == null) throw FormatException('读不出的落位：$node');
    return double.parse(match.group(1)!);
  }

  group('贴纸是第二路输入：单帧 PNG、全分辨率 alpha、不配循环不取最短', () {
    test('每个贴纸一条带 alpha 的输入流，归到主片帧率网格', () {
      final arguments = graphOf(
        stickers: [sticker(), sticker(startMs: 4000, endMs: 5000)],
      );

      expect(arguments, containsAllInOrder(['-i', '/cache/a.sticker0.png']));
      expect(arguments, containsAllInOrder(['-i', '/cache/a.sticker1.png']));
      final filter = filterOf(arguments);
      expect(filter, contains('[1:v]format=rgba,fps=$kCastRenderFps[csti0]'));
      expect(filter, contains('[2:v]format=rgba,fps=$kCastRenderFps[csti1]'));
    });

    test('alpha 全分辨率：混合在 rgb 里做，alpha 通道不被改写', () {
      final filter = filterOf(graphOf(stickers: [sticker()]));

      expect(
        filter,
        contains('format=rgba[csta0_0]'),
        reason: '缩过之后仍要送回 rgba——不带这一句 alpha 会在协商里丢掉',
      );
      expect(filter, contains(':format=rgb:'));
      for (final forbidden in const [
        'alphaextract',
        'alphamerge',
        'geq',
        'lut',
        'yuva420p',
        'format=gray',
      ]) {
        expect(
          filter,
          isNot(contains(forbidden)),
          reason: '透明度是**乘**不是设：不许出现改写 alpha 的节点（$forbidden）',
        );
      }
    });

    test('单帧输入不配循环、全命令不配取最短（靠 overlay 重复末帧铺满）', () {
      final arguments = graphOf(stickers: [sticker()]);

      expect(arguments, isNot(contains('-loop')));
      expect(arguments, isNot(contains('-shortest')));
      expect(filterOf(arguments), contains('eof_action=repeat'));
    });

    test('贴纸只在勾了画面类时装上：只勾声音类不进滤镜图', () {
      // 只勾声音类：这一次的暂存表里根本没有贴纸这一路（装哪几条由
      // `castStagedStickerSlots` 回答，装配层照表落命令）。
      final arguments = graphOf(
        stickers: [sticker()],
        picture: false,
        sound: true,
      );

      expect(filterOf(arguments), isNot(contains('overlay=')));
      expect(arguments, isNot(contains('/cache/a.sticker0.png')));
    });

    test('没有贴纸时画面链与今天逐字一致（不引入多余的中间标签）', () {
      final filter = filterOf(graphOf());

      expect(
        filter,
        contains(
          "[0:v]scale=-2:'min(1080,ih)',setsar=1,"
          'fps=$kCastRenderFps,format=yuv420p[vout]',
        ),
        reason: '没有贴纸就只剩分辨率档那一枚（不引入多余的中间标签）',
      );
      expect(filter, isNot(contains('overlay=')));
      expect(filter, isNot(contains('scale2ref')));
    });
  });

  group('落位与上屏同源：归一化坐标与尺寸系数逐点比 noteStickerRect', () {
    const picture = Size(960, 540);
    final geometries = <(double, double)>[
      (0.5, 0.12),
      (0.05, 0.9),
      (0.95, 0.05),
      (0.2, 0.5),
    ];
    final sizes = <(double, double)>[(0.3, 0.08), (0.02, 0.02), (1.2, 1.4)];
    const selections = <FramingSelection?>[
      null,
      FramingSelection(left: 0.12, top: 0.2, right: 0.42, bottom: 0.7),
      FramingSelection(left: 0, top: 0, right: 0.5, bottom: 0.5),
    ];

    test('未调过取景：位置与尺寸系数在上屏那一份上逐点相同', () {
      for (final (cx, cy) in geometries) {
        for (final (w, h) in sizes) {
          for (final mirrored in [false, true]) {
            final sheet = sticker(
              centerX: cx,
              centerY: cy,
              widthFraction: w,
              heightFraction: h,
            );
            final gate = castStickerPlacementOf(
              sticker: sheet,
              selection: null,
              mirrored: mirrored,
            )!;
            final phone = onScreenPlacement(
              sheet: sheet,
              selection: null,
              mirrored: mirrored,
              picture: picture,
            );

            expect(
              gate.centerX,
              closeTo(phone.centerX, 1e-9),
              reason: '($cx,$cy) 尺寸 ($w,$h) 镜像 $mirrored：横向落位与上屏不同源',
            );
            expect(
              gate.centerY,
              closeTo(phone.centerY, 1e-9),
              reason: '($cx,$cy) 尺寸 ($w,$h)：纵向落位与上屏不同源',
            );
          }
        }
      }
    });

    test('调过取景：选区窗口换算 + 随面翻转 + 钳制与上屏逐点相同', () {
      for (final selection in selections) {
        for (final (cx, cy) in geometries) {
          for (final (w, h) in sizes) {
            for (final mirrored in [false, true]) {
              final sheet = sticker(
                centerX: cx,
                centerY: cy,
                widthFraction: w,
                heightFraction: h,
              );
              final gate = castStickerPlacementOf(
                sticker: sheet,
                selection: selection,
                mirrored: mirrored,
              )!;
              final phone = onScreenPlacement(
                sheet: sheet,
                selection: selection,
                mirrored: mirrored,
                picture: picture,
              );

              expect(
                gate.centerX,
                closeTo(phone.centerX, 1e-9),
                reason: '$selection ($cx,$cy) ($w,$h) 镜像 $mirrored：横向不同源',
              );
              expect(
                gate.centerY,
                closeTo(phone.centerY, 1e-9),
                reason: '$selection ($cx,$cy) ($w,$h)：纵向不同源',
              );
            }
          }
        }
      }
    });

    test('贴纸大于画面矩形：该轴居中（与上屏的钳制退化同款）', () {
      final sheet = sticker(
        centerX: 0.05,
        centerY: 0.95,
        widthFraction: 1.4,
        heightFraction: 2.0,
      );

      final gate = castStickerPlacementOf(
        sticker: sheet,
        selection: null,
        mirrored: false,
      )!;

      expect(gate.centerX, 0.5);
      expect(gate.centerY, 0.5);
    });

    test('退化取值（零宽 / 非有限）安静丢掉这一条，不产出坏表达式', () {
      expect(
        castStickerPlacementOf(
          sticker: sticker(widthFraction: 0),
          selection: null,
          mirrored: false,
        ),
        isNull,
      );
      expect(
        castStickerPlacementOf(
          sticker: sticker(centerX: double.nan),
          selection: null,
          mirrored: false,
        ),
        isNull,
      );
    });
  });

  group('镜像分段：与源视频面翻转闸门逐帧同判、无漏无重', () {
    const fragments = [
      LocalMirrorFragment(startMs: 1500, endMs: 2000),
      LocalMirrorFragment(startMs: 2500, endMs: 2600),
    ];

    for (final globalMirrored in [false, true]) {
      test('全局镜像 $globalMirrored：每段的状态与闸门同判、并集恒等于贴纸窗', () {
        final sheet = sticker(startMs: 1000, endMs: 3000);
        final gate = flip(globalMirrored: globalMirrored, fragments: fragments);
        final segments = castStickerSegmentsOf(
          sticker: sheet,
          selection: null,
          flip: gate,
        );

        expect(segments, isNotEmpty);
        expect(segments.first.startMs, sheet.startMs);
        expect(segments.last.endMs, sheet.endMs);
        for (var i = 0; i < segments.length; i++) {
          final segment = segments[i];
          expect(segment.endMs, greaterThan(segment.startMs));
          if (i > 0) {
            expect(
              segment.startMs,
              segments[i - 1].endMs,
              reason: '相邻两段必须首尾相接：既不能漏一段、也不能叠一段',
            );
          }
          expect(
            segment.mirrored,
            gate.mirroredAt(segment.startMs),
            reason: '第 $i 段（${segment.startMs}ms 起）的镜像状态与闸门不同判',
          );
        }
        // 逐帧判据：贴纸窗内每一帧都恰好落在一段里，且那一段的 enable 为真。
        for (var ms = sheet.startMs; ms < sheet.endMs; ms += 1000 ~/ 30) {
          final hits = segments.where((s) => s.startMs <= ms && ms < s.endMs);
          expect(hits, hasLength(1), reason: '${ms}ms 上有 ${hits.length} 段覆盖');
          expect(hits.single.mirrored, gate.mirroredAt(ms));
        }
      });
    }

    test('局部镜像总开关关掉：只剩一段，状态 = 全局那一枚', () {
      final segments = castStickerSegmentsOf(
        sticker: sticker(startMs: 1000, endMs: 3000),
        selection: null,
        flip: flip(
          globalMirrored: true,
          localMirrorEnabled: false,
          fragments: fragments,
        ),
      );

      expect(segments, hasLength(1));
      expect(segments.single.mirrored, isTrue);
    });

    test('窗口跨过片段端点：分成两段，各自的落位按各自的状态算', () {
      final sheet = sticker(
        startMs: 1500,
        endMs: 2500,
        centerX: 0.25,
        widthFraction: 0.2,
      );
      final segments = castStickerSegmentsOf(
        sticker: sheet,
        selection: null,
        flip: flip(fragments: fragments),
      );

      expect(segments, hasLength(2));
      expect(segments[0].mirrored, isTrue);
      expect(segments[1].mirrored, isFalse);
      expect(
        segments[0].placement.centerX,
        closeTo(0.75, 1e-9),
        reason: '片段内那一半是镜像态：贴纸横向取反，仍贴它标的那个舞者',
      );
      expect(segments[1].placement.centerX, closeTo(0.25, 1e-9));
    });

    test('空窗 / 倒置窗：一段都不产出（不喂 overlay 一条恒假的节点）', () {
      for (final window in const [(1000, 1000), (2000, 1000)]) {
        expect(
          castStickerSegmentsOf(
            sticker: sticker(startMs: window.$1, endMs: window.$2),
            selection: null,
            flip: flip(),
          ),
          isEmpty,
        );
      }
    });
  });

  group('时间窗：半开 [起, 止)，进出不多一帧不少一帧', () {
    test('表达式用 gte*lt，不用 between（起点算窗内、终点算窗外）', () {
      final nodes = overlayNodesOf(
        graphOf(stickers: [sticker(startMs: 2000, endMs: 4000)]),
      );

      expect(nodes, hasLength(1));
      expect(nodes.single, contains("enable='gte(t,2)*lt(t,4)'"));
      expect(nodes.single, isNot(contains('between')));
    });

    test('小数端点原样落进表达式（毫秒不被抹平）', () {
      final nodes = overlayNodesOf(
        graphOf(stickers: [sticker(startMs: 1033, endMs: 2667)]),
      );

      expect(nodes.single, contains("enable='gte(t,1.033)*lt(t,2.667)'"));
    });

    test('多张贴纸各自的时间窗：一条一段，互不串窗', () {
      final nodes = overlayNodesOf(
        graphOf(
          stickers: [
            sticker(startMs: 0, endMs: 1000),
            sticker(startMs: 5000, endMs: 6000),
          ],
        ),
      );

      expect(nodes, hasLength(2));
      final reader0 = enableReaderOf(nodes[0]);
      final reader1 = enableReaderOf(nodes[1]);
      expect(reader0(0.5), isTrue);
      expect(reader0(5.5), isFalse);
      expect(reader1(5.5), isTrue);
      expect(reader1(0.5), isFalse);
    });

    test('帧率网格归一：覆盖的主片帧集合恰好是「t 落在半开窗内」的那些帧', () {
      const fps = kCastRenderFps;
      const startMs = 1033;
      const endMs = 2667;
      final nodes = overlayNodesOf(
        graphOf(
          stickers: [sticker(startMs: startMs, endMs: endMs)],
        ),
      );
      final enabled = enableReaderOf(nodes.single);
      // 主片帧网格（30fps）：帧号 k 的时刻是 k/30 秒。
      final covered = [
        for (var k = 0; k <= (endMs / 1000 * fps).ceil(); k++)
          if (enabled(k / fps)) k,
      ];
      final expected = [
        for (var k = 0; k <= (endMs / 1000 * fps).ceil(); k++)
          if (startMs / 1000 <= k / fps && k / fps < endMs / 1000) k,
      ];

      expect(covered, expected, reason: '窗内帧不多不少，端点按半开判');
      expect(enabled((endMs / 1000) - 1 / fps), isTrue, reason: '窗的最后一帧仍在窗内');
      expect(enabled(endMs / 1000), isFalse, reason: '窗的终点那一帧必须算窗外');
    });

    test('这条用例不是空转：第二路没归到主片网格时端点会多一帧', () {
      const startMs = 1033;
      const endMs = 2667;
      final nodes = overlayNodesOf(
        graphOf(
          stickers: [sticker(startMs: startMs, endMs: endMs)],
        ),
      );
      final enabled = enableReaderOf(nodes.single);
      // 两路帧率不同的情形：第二路按 image2 的 25fps 走（没有 fps=30 归一）。
      const foreignFps = 25;
      bool foreignEnabled(double t) => enabled(t);
      final foreignCovered = [
        for (var k = 0; k <= 70; k++)
          if (foreignEnabled(k / foreignFps)) k,
      ];
      final mainCovered = [
        for (var k = 0; k <= 70; k++)
          if (foreignEnabled(k / kCastRenderFps)) k,
      ];

      expect(
        foreignCovered.length,
        isNot(mainCovered.length),
        reason:
            '同一段时间窗在两条不同的帧率网格上必须给出不同的帧数——'
            '否则「归到主片帧率网格」这句话没有可判的内容',
      );
      expect(
        filterOf(graphOf(stickers: [sticker()])),
        contains('fps=$kCastRenderFps'),
        reason: '第二路必须被显式归到主片帧率网格',
      );
    });
  });

  group('尺寸靠 scale2ref：读的必须是参考路（画面）的尺寸', () {
    /// 按 ffmpeg 的变量映射解出这一条缩放出来的宽度：`iw`/`ih` 是参考路（画面）
    /// 的尺寸，`main_w`/`main_h` 是被缩放那一路（贴纸 PNG）自己的尺寸——映射读
    /// 自 ffmpeg 6.0 `vf_scale.c` 的 `scale_eval_dimensions`。
    double scaledWidthOf(
      String node, {
      required double referenceWidth,
      required double inputWidth,
      required double inputHeight,
    }) {
      final match = RegExp(
        r'scale2ref=w=(iw|main_w)\*([\d.]+):h=(ih|main_h)\*([\d.]+)',
      ).firstMatch(node);
      if (match == null) throw FormatException('读不出的缩放节点：$node');
      final base = match.group(1) == 'iw' ? referenceWidth : inputWidth;
      return base * double.parse(match.group(2)!);
    }

    test('同一张贴纸换个像素密度仍占帧的同一个比例（用 main_w 就办不到）', () {
      final scaleNode = filterOf(
        graphOf(stickers: [sticker(widthFraction: 0.25, heightFraction: 0.1)]),
      ).split(';').firstWhere((node) => node.contains('scale2ref='));

      final coarse = scaledWidthOf(
        scaleNode,
        referenceWidth: 1920,
        inputWidth: 240,
        inputHeight: 54,
      );
      final fine = scaledWidthOf(
        scaleNode,
        referenceWidth: 1920,
        inputWidth: 960,
        inputHeight: 216,
      );

      expect(coarse, closeTo(480, 1e-9), reason: '帧宽的 25%');
      expect(fine, coarse, reason: '贴纸占的是帧的比例，与 PNG 自己的像素数无关');
      expect(scaleNode, contains('scale2ref=w=iw*'));
    });

    test('宽度分数与高度分数各自落在两条表达式上（不吃错变量）', () {
      final scaleNode = filterOf(
        graphOf(stickers: [sticker(widthFraction: 0.2, heightFraction: 0.35)]),
      ).split(';').firstWhere((node) => node.contains('scale2ref='));

      expect(scaleNode, contains('w=iw*0.2'));
      expect(scaleNode, contains('h=ih*0.35'));
    });
  });

  group('节点次序与输入下标', () {
    test('贴纸排在取景之后、倍速 setpts 之前（时间窗判的是源时间轴）', () {
      final filter = filterOf(
        graphOf(
          stickers: [sticker()],
          framingSelection: const FramingSelection(
            left: 0.1,
            top: 0.2,
            right: 0.9,
            bottom: 0.8,
          ),
        ),
      );
      final cropAt = filter.indexOf('crop=');
      final overlayAt = filter.indexOf('overlay=');
      final tailAt = filter.indexOf('fps=$kCastRenderFps,format=yuv420p[vout]');

      expect(cropAt, isNonNegative);
      expect(cropAt, lessThan(overlayAt), reason: '贴纸贴在取景后的那一块画面上');
      expect(overlayAt, lessThan(tailAt));
    });

    test('只勾画面类时贴纸占 1 号输入位；勾了声音类时拍声仍在 1 号位', () {
      final pictureOnly = filterOf(graphOf(stickers: [sticker()]));
      expect(pictureOnly, contains('[1:v]'));

      final withSound = filterOf(graphOf(stickers: [sticker()], sound: true));
      expect(withSound, contains('[1:a]'), reason: '拍声轨的输入位不因为贴纸进来而改变');
      expect(withSound, contains('[2:v]format=rgba'));
    });

    test('两条贴纸依次叠：后一条叠在前一条的产物上', () {
      final filter = filterOf(
        graphOf(stickers: [sticker(), sticker(startMs: 4000, endMs: 5000)]),
      );

      expect(
        filter,
        contains('[csti0][vbase]scale2ref='),
        reason: '第一条叠在取景后的画面上',
      );
      expect(filter, contains('[cstr0_0][csta0_0]overlay='));
      expect(
        filter,
        contains('[csti1][csm0_0]scale2ref='),
        reason: '第二条叠在第一条的产物上',
      );
      expect(
        filter.endsWith('fps=$kCastRenderFps,format=yuv420p[vout]'),
        isTrue,
      );
    });

    test('贴纸窗整段落在局部镜像片段内：只出一条 overlay 节点', () {
      final nodes = overlayNodesOf(
        graphOf(
          stickers: [sticker(startMs: 1200, endMs: 1800)],
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 2000),
          ],
        ),
      );

      expect(nodes, hasLength(1));
      expect(
        nodes.single,
        contains("enable='gte(t,1.2)*lt(t,1.8)'"),
        reason: '窗被片段整段覆盖，时段不分叉',
      );
    });

    test('一张贴纸的多段链要先分叉：一个输出 pad 只能被连一次', () {
      final filter = filterOf(
        graphOf(
          stickers: [sticker(startMs: 1000, endMs: 3000)],
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 1500, endMs: 2000),
          ],
        ),
      );

      expect(
        filter,
        contains('[csti0]split=3[csti0_0][csti0_1][csti0_2]'),
        reason: '三段各自一条 overlay 链，输入流必须先 split',
      );
      expect(filter, contains('[csti0_0][vbase]scale2ref='));
      expect(filter, contains('[csti0_1][csm0_0]scale2ref='));
      expect(filter, contains('[csti0_2][csm0_1]scale2ref='));
    });

    test('贴纸窗跨过片段端点：同一张贴纸出两条 overlay 节点，落位互为镜像', () {
      final nodes = overlayNodesOf(
        graphOf(
          stickers: [
            sticker(
              startMs: 1000,
              endMs: 3000,
              centerX: 0.3,
              widthFraction: 0.2,
            ),
          ],
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 1500, endMs: 2000),
          ],
        ),
      );

      expect(nodes, hasLength(3));
      expect(enableReaderOf(nodes[0])(1.2), isTrue);
      expect(enableReaderOf(nodes[1])(1.7), isTrue);
      expect(enableReaderOf(nodes[2])(2.5), isTrue);
      expect(overlayCenterXOf(nodes[0]), closeTo(0.3, 1e-9));
      expect(overlayCenterXOf(nodes[1]), closeTo(0.7, 1e-9));
      expect(overlayCenterXOf(nodes[2]), closeTo(0.3, 1e-9));
    });
  });
}
