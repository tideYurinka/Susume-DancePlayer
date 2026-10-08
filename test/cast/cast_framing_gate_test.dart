import 'dart:math' as math;

import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/cast/cast_framing_gate.dart';
import 'package:dance_learning_app/cast/cast_render_plan.dart';
import 'package:dance_learning_app/cast/cast_render_request.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投屏取景闸门直测（纯件）：画面链里的**裁切与缩放节点是外部契约**（它决定
/// 产物），按关键片段快照式断言，不跑进程、不启动 widget。
///
/// 判定走两条**独立**的路，不拿被测代码反算：
/// 1. **与上屏同一份取值**：期望值来自取景纯域（[FramingSelection] 与
///    [framingSelectionRectOnPicture]，即画面上那块矩形的那一份数学），渲染这一
///    路把产物节点里的表达式按源尺寸**算回来**（下面的求值器读的是产出的字面量）；
/// 2. **与手机显示逐帧同相**：手机的取景是「包在画面件外面的剪辑窗」（翻转在
///    显示层、窗切在翻过的画面上），渲染这一路按产物节点表里**元件的先后**推
///    同一个映射——两式在错序时立刻分歧（下面有专门一条证明它不是空转）。
void main() {
  /// 把一条滤镜链按**元件的分隔逗号**切成元件：`\,`（表达式内的逗号）与
  /// 单引号内的时间窗逗号（`enable='gte(t,1)*lt(t,2)'`）都不是分隔符。
  List<String> filterNodesOf(String chain) {
    final nodes = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < chain.length; i++) {
      final character = chain[i];
      if (character == r'\' && i + 1 < chain.length) {
        buffer.write(character);
        buffer.write(chain[i + 1]);
        i++;
        continue;
      }
      if (character == "'") {
        quoted = !quoted;
        buffer.write(character);
        continue;
      }
      if (character == ',' && !quoted) {
        nodes.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(character);
    }
    if (buffer.isNotEmpty) nodes.add(buffer.toString());
    return nodes;
  }

  /// 装配一条画面类命令，并把 `[0:v]…[vout]` 那一段的元件表读出来。
  List<String> videoNodesOf({
    bool globalMirrored = false,
    bool localMirrorEnabled = true,
    List<LocalMirrorFragment> mirrorFragments = const [],
    FramingSelection? framingSelection,
    CastSpeedTier speedTier = CastSpeedTier.full,
    bool picture = true,
    bool sound = true,
  }) {
    final arguments = buildCastRenderArguments(
      request: CastRenderRequest(
        videoPath: '/videos/a.mp4',
        videoId: 'vid-a',
        duration: const Duration(minutes: 3),
        choices: CastRenderChoices(picture: picture, sound: sound),
        speedTier: speedTier,
        settings: CastRenderSettings(
          globalMirrored: globalMirrored,
          localMirrorEnabled: localMirrorEnabled,
        ),
        annotationFingerprint: 'fp-1',
        mirrorFragments: mirrorFragments,
        framingSelection: framingSelection,
      ),
      outputPath: '/cache/a.part',
      beatTrackPath: sound ? '/cache/a.clicks.wav' : null,
    );
    final chain = arguments[arguments.indexOf('-filter_complex') + 1]
        .split(';')
        .where((segment) => segment.startsWith('[0:v]'));
    if (chain.isEmpty) return const [];
    return filterNodesOf(chain.first.substring('[0:v]'.length));
  }

  bool isFlipNode(String node) =>
      node == 'hflip' || node.startsWith('hflip=enable=');

  /// `enable` 表达式的读回器：认 `gte(t,起)*lt(t,止)` 逐项相加，恒假给 `0`。
  bool Function(double) enableReader(String expression) {
    if (expression == '0') return (_) => false;
    final terms = <(double, double)>[];
    for (final term in expression.split('+')) {
      final match = RegExp(r'^gte\(t,([\d.]+)\)\*lt\(t,([\d.]+)\)$')
          .firstMatch(term);
      if (match == null) throw FormatException('读不出的时间窗项：$term');
      terms.add((double.parse(match.group(1)!), double.parse(match.group(2)!)));
    }
    return (seconds) =>
        terms.any((window) => window.$1 <= seconds && seconds < window.$2);
  }

  /// **产物侧读数**：这套元件在 `seconds`（源时间轴）是否净翻转。
  bool renderedMirroredAt(List<String> nodes, double seconds) {
    var flips = 0;
    for (final node in nodes) {
      if (node == 'hflip') {
        flips++;
        continue;
      }
      final match = RegExp(r"^hflip=enable='(.+)'$").firstMatch(node);
      if (match == null) continue;
      if (enableReader(match.group(1)!)(seconds)) flips++;
    }
    return flips.isOdd;
  }

  /// 产物节点表里裁切节点的四段表达式（`crop=w=…:h=…:x=…:y=…`）。
  Map<String, String> cropExpressionsOf(List<String> nodes) {
    final node = nodes.firstWhere(
      (candidate) => candidate.startsWith('crop='),
      orElse: () => throw StateError('这套节点里没有裁切：$nodes'),
    );
    final fields = <String, String>{};
    for (final piece in node.substring('crop='.length).split(':')) {
      final separator = piece.indexOf('=');
      fields[piece.substring(0, separator)] = piece.substring(separator + 1);
    }
    return fields;
  }

  /// **产物侧读数**：裁切窗口在给定源尺寸上的像素四边。
  ({double x, double y, double width, double height}) cropPixelsOf(
    List<String> nodes, {
    required int sourceWidth,
    required int sourceHeight,
  }) {
    final expressions = cropExpressionsOf(nodes);
    final variables = <String, double>{
      'iw': sourceWidth.toDouble(),
      'ih': sourceHeight.toDouble(),
    };
    final width = evaluateFilterExpression(expressions['w']!, variables);
    variables['ow'] = width;
    final height = evaluateFilterExpression(expressions['h']!, variables);
    variables['oh'] = height;
    return (
      x: evaluateFilterExpression(expressions['x']!, variables),
      y: evaluateFilterExpression(expressions['y']!, variables),
      width: width,
      height: height,
    );
  }

  /// **手机显示模型**：取景后画面里的内容位置 `(u, v)`（各自 `[0, 1]` 归一化，
  /// `u` 向右）上是源画面原相里的哪个**像素点**。
  ///
  /// 翻转是画面件的**显示层**变换、取景是包在它外面的剪辑窗——窗里那块是
  /// 「翻过的画面」在那块矩形上的样子（`FramingSelectionView` 把剪辑 Rect 挂在
  /// 画面件之上）。
  ({double x, double y}) onScreenPixel({
    required FramingSelection selection,
    required bool mirrored,
    required double u,
    required double v,
    int sourceWidth = 1920,
    int sourceHeight = 1080,
  }) {
    final x = (selection.left + u * selection.width) * sourceWidth;
    return (
      x: mirrored ? sourceWidth - x : x,
      y: (selection.top + v * selection.height) * sourceHeight,
    );
  }

  /// **产物模型**：按节点表里**裁切与翻转元件的先后**推同一个映射。
  ///
  /// 翻转在裁切之前 = 先翻画面、再把窗切在翻过的画面上（手机那一式）；翻转在
  /// 裁切之后 = 先切窗、再在窗内翻（另一式，两者在非居中选区上立刻分歧）。
  ({double x, double y}) renderedPixel({
    required List<String> nodes,
    required bool mirrored,
    required double u,
    required double v,
    int sourceWidth = 1920,
    int sourceHeight = 1080,
  }) {
    final cropIndex = nodes.indexWhere((node) => node.startsWith('crop='));
    expect(cropIndex, isNonNegative, reason: '取景必须产出裁切节点');
    final flipBefore = mirrored && nodes.take(cropIndex).any(isFlipNode);
    final flipAfter = mirrored && nodes.skip(cropIndex + 1).any(isFlipNode);
    final pixels = cropPixelsOf(
      nodes,
      sourceWidth: sourceWidth,
      sourceHeight: sourceHeight,
    );
    var x = pixels.x + (flipAfter ? 1 - u : u) * pixels.width;
    if (flipBefore) x = sourceWidth - x;
    return (x: x, y: pixels.y + v * pixels.height);
  }

  /// 逐点比对的像素容差：裁切四边按偶数对齐，最多各让出 2 像素。
  const pixelTolerance = 2.0;

  group('未取景：整条画面链一字不改', () {
    test('null（未调过）不装任何取景节点', () {
      expect(castFramingFilterNodes(null), isEmpty);
      expect(castFramingActive(null), isFalse);
      expect(
        videoNodesOf(framingSelection: null),
        isNot(contains(startsWith('crop='))),
      );
    });

    test('整帧选区 = 未调过的显示等价物：同样零节点（不引入多余的缩放）', () {
      const fullFrame = FramingSelection.fullFrame();

      expect(castFramingActive(fullFrame), isFalse);
      expect(castFramingFilterNodes(fullFrame), isEmpty);
      expect(
        videoNodesOf(framingSelection: fullFrame),
        isNot(contains(startsWith('crop='))),
      );
      expect(
        videoNodesOf(framingSelection: fullFrame).join(','),
        videoNodesOf(framingSelection: null).join(','),
        reason: '整帧取景与未取景必须是同一条链（逐位一致）',
      );
    });

    test('退化取值（零宽高 / 越界后非正）：安静按未取景处理，不产出空窗', () {
      for (final selection in const [
        FramingSelection(left: 0.5, top: 0.5, right: 0.5, bottom: 0.5),
        FramingSelection(left: 0.9, top: 0, right: 0.1, bottom: 1),
      ]) {
        expect(castFramingActive(selection), isFalse);
        expect(castFramingFilterNodes(selection), isEmpty);
      }
      expect(
        castFramingActive(
          const FramingSelection(left: double.nan, top: 0, right: 1, bottom: 1),
        ),
        isFalse,
      );
    });

    test('取景只在勾了画面类时装上：只勾声音类不进滤镜图', () {
      const selection = FramingSelection(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );

      final nodes = videoNodesOf(
        framingSelection: selection,
        picture: false,
        sound: true,
      );
      expect(nodes, isEmpty, reason: '视频流原样复制，画面链根本没进滤镜图');
    });
  });

  group('与上屏同一份取值：裁切窗口就是那块选区', () {
    test('偶数源尺寸上逐位相同（读回的四边 == framingSelectionRectOnPicture）', () {
      const selections = [
        FramingSelection(left: 0.1, top: 0.2, right: 0.9, bottom: 0.8),
        FramingSelection(left: 0.25, top: 0, right: 0.75, bottom: 1),
        FramingSelection(left: 0, top: 0, right: 0.5, bottom: 0.5),
      ];

      for (final selection in selections) {
        final nodes = castFramingFilterNodes(selection);
        final pixels = cropPixelsOf(
          nodes,
          sourceWidth: 1920,
          sourceHeight: 1080,
        );
        final rect = framingSelectionRectOnPicture(
          selection: selection,
          pictureLeft: 0,
          pictureTop: 0,
          pictureWidth: 1920,
          pictureHeight: 1080,
        );

        expect(pixels.width, closeTo(rect.right - rect.left, 1e-6));
        expect(pixels.height, closeTo(rect.bottom - rect.top, 1e-6));
        expect(pixels.x, closeTo(rect.left, 1e-6));
        expect(pixels.y, closeTo(rect.top, 1e-6));
      }
    });

    test('奇数源尺寸上最多让出亚像素级的偶数对齐（< 2px）', () {
      const selection = FramingSelection(
        left: 0.100333,
        top: 0.200777,
        right: 0.900111,
        bottom: 0.799333,
      );
      final pixels = cropPixelsOf(
        castFramingFilterNodes(selection),
        sourceWidth: 1921,
        sourceHeight: 1081,
      );
      final rect = framingSelectionRectOnPicture(
        selection: selection,
        pictureLeft: 0,
        pictureTop: 0,
        pictureWidth: 1921,
        pictureHeight: 1081,
      );

      expect(pixels.width, closeTo(rect.right - rect.left, 2));
      expect(pixels.height, closeTo(rect.bottom - rect.top, 2));
      expect(pixels.x, closeTo(rect.left, 2));
      expect(pixels.y, closeTo(rect.top, 2));
    });

    test('链上就一句：crop + 偶数收尾 + 方像素，链尾的 vout 不变', () {
      const selection = FramingSelection(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );

      expect(castFramingFilterNodes(selection), const [
        'crop=w=max(2\\,floor(iw*0.8/2)*2):'
            'h=max(2\\,floor(ih*0.6/2)*2):'
            'x=min(floor(iw*0.1/2)*2\\,iw-ow):'
            'y=min(floor(ih*0.2/2)*2\\,ih-oh)',
        'scale=trunc(iw/2)*2:trunc(ih/2)*2',
        'setsar=1',
      ]);
      final nodes = videoNodesOf(framingSelection: selection);
      expect(
        nodes.join(','),
        'crop=w=max(2\\,floor(iw*0.8/2)*2):'
        'h=max(2\\,floor(ih*0.6/2)*2):'
        'x=min(floor(iw*0.1/2)*2\\,iw-ow):'
        'y=min(floor(ih*0.2/2)*2\\,ih-oh),'
        'scale=trunc(iw/2)*2:trunc(ih/2)*2,setsar=1,fps=30,format=yuv420p[vout]',
        reason: '取景节点插在画面链中段，链尾的 fps / 像素格式与 [vout] 一字不动',
      );
    });

    test('缩放读的是裁切之后的尺寸：输出帧 = 选区那一块自己的宽高比', () {
      const selection = FramingSelection(
        left: 0.1,
        top: 0.2,
        right: 0.9,
        bottom: 0.8,
      );
      final nodes = castFramingFilterNodes(selection);
      final scale = nodes.firstWhere((node) => node.startsWith('scale='));
      final pixels = cropPixelsOf(nodes, sourceWidth: 1920, sourceHeight: 1080);

      // `iw`/`ih` 在 scale 里是裁切之后的尺寸（产物侧读数按同一个口径求值）。
      final outputWidth = evaluateFilterExpression(
        scale.substring('scale='.length).split(':').first,
        {'iw': pixels.width, 'ih': pixels.height},
      );
      final outputHeight = evaluateFilterExpression(
        scale.substring('scale='.length).split(':').last,
        {'iw': pixels.width, 'ih': pixels.height},
      );

      expect(outputWidth, pixels.width);
      expect(outputHeight, pixels.height);
      expect(
        outputWidth / outputHeight,
        closeTo(selection.contentAspectRatio(1920 / 1080), 1e-9),
        reason: '选区自己的宽高比就是上屏画面的宽高比（core/CONTEXT.md）',
      );
    });
  });

  group('取景与镜像同时生效：产物与手机显示逐帧同相', () {
    const selection = FramingSelection(
      left: 0.12,
      top: 0.2,
      right: 0.42,
      bottom: 0.7,
    );
    const fragments = [
      LocalMirrorFragment(startMs: 1000, endMs: 2000),
      LocalMirrorFragment(startMs: 3500, endMs: 5000),
    ];
    const positionsMs = [
      0,
      500,
      999,
      1000,
      1500,
      1999,
      2000,
      2500,
      3499,
      3500,
      4999,
      5000,
      6000,
    ];
    const grid = [0.0, 0.25, 0.5, 0.75, 1.0];

    test('先翻后切窗：手机那一式的节点先后', () {
      final nodes = videoNodesOf(
        globalMirrored: true,
        mirrorFragments: fragments,
        framingSelection: selection,
      );

      expect(nodes.first, 'hflip');
      expect(
        nodes.indexWhere((node) => node.startsWith('crop=')),
        2,
        reason: '两枚闸门（全局 + 时间窗局部）都在裁切之前',
      );
      expect(nodes.where((node) => node.startsWith('hflip')).length, 2);
    });

    for (final globalMirrored in [true, false]) {
      for (final localMirrorEnabled in [true, false]) {
        test('全局 $globalMirrored / 局部总开关 $localMirrorEnabled：逐帧逐点同相', () {
          final nodes = videoNodesOf(
            globalMirrored: globalMirrored,
            localMirrorEnabled: localMirrorEnabled,
            mirrorFragments: fragments,
            framingSelection: selection,
          );
          final gate = SourceVideoFlip(
            globalMirrored: globalMirrored,
            localMirrorEnabled: localMirrorEnabled,
            fragments: fragments,
          );

          for (final positionMs in positionsMs) {
            final seconds = positionMs / 1000;
            // 上屏那一份（画面件的翻转闸门）与产物那一份（滤镜节点的
            // enable 表达式）先各自读出来，再逐点比内容。
            final onScreen = gate.mirroredAt(positionMs);
            expect(
              renderedMirroredAt(nodes, seconds),
              onScreen,
              reason: '$positionMs ms：产物与上屏的翻转结果不同相',
            );
            for (final u in grid) {
              for (final v in grid) {
                final rendered = renderedPixel(
                  nodes: nodes,
                  mirrored: onScreen,
                  u: u,
                  v: v,
                );
                final onPhone = onScreenPixel(
                  selection: selection,
                  mirrored: onScreen,
                  u: u,
                  v: v,
                );
                expect(
                  rendered.x,
                  closeTo(onPhone.x, pixelTolerance),
                  reason:
                      '$positionMs ms 内容点 ($u, $v)：'
                      '取景窗口与翻转的先后与手机不同相',
                );
                expect(
                  rendered.y,
                  closeTo(onPhone.y, pixelTolerance),
                  reason:
                      '$positionMs ms 内容点 ($u, $v)：'
                      '取景窗口与翻转的先后与手机不同相',
                );
              }
            }
          }
        });
      }
    }

    test('这条用例不是空转：错序（先切窗后翻）在同一个选区上立刻分歧', () {
      final nodes = videoNodesOf(
        globalMirrored: true,
        framingSelection: selection,
      );
      final cropNode = nodes.firstWhere((node) => node.startsWith('crop='));
      final wrongOrder = <String>[cropNode, 'hflip'];

      expect(
        renderedPixel(nodes: wrongOrder, mirrored: true, u: 0, v: 0).x,
        isNot(
          closeTo(
            onScreenPixel(selection: selection, mirrored: true, u: 0, v: 0).x,
            pixelTolerance,
          ),
        ),
        reason: '非居中选区上两式必须可分辨，否则上面那条逐帧比对钉不住先后',
      );
    });
  });

  group('奇数与极端比例的兜底：产物仍可被接收端播', () {
    const cases =
        <({int sourceWidth, int sourceHeight, FramingSelection selection})>[
          (
            sourceWidth: 1920,
            sourceHeight: 1080,
            selection: FramingSelection(
              left: 0.1,
              top: 0.2,
              right: 0.9,
              bottom: 0.8,
            ),
          ),
          (
            sourceWidth: 1921,
            sourceHeight: 1081,
            selection: FramingSelection(
              left: 0.1003,
              top: 0.2007,
              right: 0.9001,
              bottom: 0.7993,
            ),
          ),
          (
            sourceWidth: 1921,
            sourceHeight: 1081,
            selection: FramingSelection(
              left: 0.5,
              top: 0.5,
              right: 1,
              bottom: 1,
            ),
          ),
          (
            sourceWidth: 1920,
            sourceHeight: 1080,
            selection: FramingSelection(
              left: 0.5,
              top: 0.05,
              right: 0.5001,
              bottom: 0.95,
            ),
          ),
          (
            sourceWidth: 1920,
            sourceHeight: 1080,
            selection: FramingSelection(
              left: 0.05,
              top: 0.5,
              right: 0.95,
              bottom: 0.5001,
            ),
          ),
          (
            sourceWidth: 1080,
            sourceHeight: 1920,
            selection: FramingSelection(
              left: 0.25,
              top: 0.25,
              right: 0.5,
              bottom: 0.5,
            ),
          ),
          (
            sourceWidth: 2,
            sourceHeight: 2,
            selection: FramingSelection(left: 0, top: 0, right: 1, bottom: 1),
          ),
        ];

    test('裁切尺寸恒为偶数、不小于 2 像素、钉在帧内', () {
      for (final testCase in cases) {
        final selection = testCase.selection;
        final nodes = castFramingFilterNodes(selection);
        final isFullFrame =
            selection.left == 0 &&
            selection.top == 0 &&
            selection.right == 1 &&
            selection.bottom == 1;
        if (!castFramingActive(selection)) {
          expect(isFullFrame, isTrue, reason: '退化取值另有专门用例');
          expect(nodes, isEmpty);
          continue;
        }
        final pixels = cropPixelsOf(
          nodes,
          sourceWidth: testCase.sourceWidth,
          sourceHeight: testCase.sourceHeight,
        );

        expect(pixels.width % 2, 0, reason: '$selection：yuv420p 要求偶数宽');
        expect(pixels.height % 2, 0, reason: '$selection：yuv420p 要求偶数高');
        expect(pixels.width, greaterThanOrEqualTo(2));
        expect(pixels.height, greaterThanOrEqualTo(2));
        expect(pixels.x, greaterThanOrEqualTo(0));
        expect(pixels.y, greaterThanOrEqualTo(0));
        expect(
          pixels.x + pixels.width,
          lessThanOrEqualTo(testCase.sourceWidth.toDouble()),
        );
        expect(
          pixels.y + pixels.height,
          lessThanOrEqualTo(testCase.sourceHeight.toDouble()),
        );

        // 收尾的 scale 读的是裁切之后的尺寸：输出恒偶数、且不小于 2。
        final scale = nodes
            .firstWhere((node) => node.startsWith('scale='))
            .substring('scale='.length)
            .split(':');
        final outputWidth = evaluateFilterExpression(scale.first, {
          'iw': pixels.width,
          'ih': pixels.height,
        });
        final outputHeight = evaluateFilterExpression(scale.last, {
          'iw': pixels.width,
          'ih': pixels.height,
        });
        expect(outputWidth % 2, 0);
        expect(outputHeight % 2, 0);
        expect(outputWidth, greaterThanOrEqualTo(2));
        expect(outputHeight, greaterThanOrEqualTo(2));
      }
    });

    test('未取景时没有这些节点：不引入多余的缩放或像素格式变化', () {
      final plain = videoNodesOf(framingSelection: null).join(',');
      expect(plain, 'fps=30,format=yuv420p[vout]');
      expect(plain, isNot(contains('crop=')));
      expect(plain, isNot(contains('scale=')));
      expect(plain, isNot(contains('setsar')));
    });
  });
}

/// 一条滤镜表达式按给定变量求值：只认本域产出的语法（数字、`iw`/`ih`/`ow`/`oh`、
/// `floor`/`trunc`/`min`/`max`、`+ - * /` 与括号；逗号允许写成 `\,`）。
///
/// 它是**产物侧读数**：读的是产出的那串字面量，不反算被测代码的算式。
double evaluateFilterExpression(
  String expression,
  Map<String, double> variables,
) => _ExpressionReader(expression, variables).parse();

class _ExpressionReader {
  _ExpressionReader(this.expression, this.variables)
    : text = expression.replaceAll(r'\', '');

  final String expression;
  final Map<String, double> variables;
  final String text;
  int index = 0;

  int get end => text.length;

  void skipSpaces() {
    while (index < end && text[index] == ' ') {
      index++;
    }
  }

  double parse() {
    final value = parseExpression();
    skipSpaces();
    expect(index, end, reason: '表达式没读干净：$expression');
    return value;
  }

  double parseExpression() {
    var value = parseTerm();
    while (true) {
      skipSpaces();
      if (index < end && (text[index] == '+' || text[index] == '-')) {
        final op = text[index++];
        final rhs = parseTerm();
        value = op == '+' ? value + rhs : value - rhs;
      } else {
        return value;
      }
    }
  }

  double parseTerm() {
    var value = parseUnary();
    while (true) {
      skipSpaces();
      if (index < end && (text[index] == '*' || text[index] == '/')) {
        final op = text[index++];
        final rhs = parseUnary();
        value = op == '*' ? value * rhs : value / rhs;
      } else {
        return value;
      }
    }
  }

  double parseUnary() {
    skipSpaces();
    if (index < end && text[index] == '-') {
      index++;
      return -parseUnary();
    }
    if (index < end && text[index] == '+') {
      index++;
      return parseUnary();
    }
    return parsePrimary();
  }

  double parsePrimary() {
    skipSpaces();
    if (index < end && text[index] == '(') {
      index++;
      final value = parseExpression();
      skipSpaces();
      expect(text[index], ')', reason: '括号不配对：$expression');
      index++;
      return value;
    }
    final number = RegExp(r'^\d+(\.\d+)?').firstMatch(text.substring(index));
    if (number != null) {
      index += number.group(0)!.length;
      return double.parse(number.group(0)!);
    }
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*')
        .firstMatch(text.substring(index))!
        .group(0)!;
    index += identifier.length;
    skipSpaces();
    if (index < end && text[index] == '(') {
      index++;
      final args = <double>[];
      skipSpaces();
      if (text[index] != ')') {
        args.add(parseExpression());
        skipSpaces();
        while (index < end && text[index] == ',') {
          index++;
          args.add(parseExpression());
          skipSpaces();
        }
      }
      expect(text[index], ')', reason: '括号不配对：$expression');
      index++;
      return switch (identifier) {
        'floor' => args.first.floorToDouble(),
        'trunc' => args.first.truncateToDouble(),
        'min' => args.reduce(math.min),
        'max' => args.reduce(math.max),
        _ => throw FormatException('求值器不认的函数：$identifier'),
      };
    }
    final value = variables[identifier];
    if (value == null) throw FormatException('求值器不认的变量：$identifier');
    return value;
  }
}
