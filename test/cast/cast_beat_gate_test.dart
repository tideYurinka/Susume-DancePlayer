import 'dart:typed_data';

import 'package:dance_learning_app/cast/cast_beat_count.dart';
import 'package:dance_learning_app/cast/cast_beat_gate.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投屏数拍闸门直测（纯件）：**图像序列的清单**与滤镜节点是外部契约（它们决定
/// 产物与真机开销），按关键片段快照式断言；判定不拿被测代码反算——清单口径与
/// 真机那一份对照见 `tool/cast_beat_check_host.dart`。
void main() {
  CastBeatCountText text(String eight, String beat, {String? group}) =>
      CastBeatCountText(eightCount: eight, beatCount: beat, group: group);

  CastBeatCountRow row(int startMs, int endMs, {CastBeatCountText? value}) =>
      CastBeatCountRow(startMs: startMs, endMs: endMs, text: value);

  CastBeatCountOverlay overlay({
    required List<CastBeatCountRow> rows,
    double centerX = 0.5,
    double centerY = 0.25,
    double widthFraction = 0.3,
    double heightFraction = 0.2,
  }) => CastBeatCountOverlay(
    rows: rows,
    centerX: centerX,
    centerY: centerY,
    widthFraction: widthFraction,
    heightFraction: heightFraction,
    imageBytesOf: (index) async => Uint8List.fromList(<int>[index]),
  );

  group('逐拍时间窗 → `-f concat` 清单', () {
    test('一格一条 file + duration，末条重列一次（否则最后一格的时长不生效）', () {
      final rows = <CastBeatCountRow>[
        row(0, 1500, value: text('0', '7')),
        row(1500, 2000, value: text('1', '1')),
      ];

      expect(
        castBeatSlidesContent(rows: rows, paths: const ['/c/a.beat0.png', '/c/a.beat1.png']),
        "file '/c/a.beat0.png'\n"
        'duration 1.500\n'
        "file '/c/a.beat1.png'\n"
        'duration 0.500\n'
        "file '/c/a.beat1.png'\n",
      );
    });

    test('毫秒级端点写进时长（半开窗的宽度就是它）', () {
      final rows = <CastBeatCountRow>[row(0, 1, value: text('1', '1'))];

      expect(
        castBeatSlidesContent(rows: rows, paths: const ['/c/a.beat0.png']),
        contains('duration 0.001'),
      );
    });

    test('路径里的单引号按 concat 的转义口径写出', () {
      final rows = <CastBeatCountRow>[row(0, 1000, value: text('1', '1'))];

      expect(
        castBeatSlidesContent(rows: rows, paths: const ["/c/o'k.png"]),
        contains(r"file '/c/o'\''k.png'"),
      );
    });

    test('图与窗对不上即报错（错位比什么都不画危险得多）', () {
      expect(
        () => castBeatSlidesContent(
          rows: <CastBeatCountRow>[row(0, 1000)],
          paths: const ['/c/a.png', '/c/b.png'],
        ),
        throwsArgumentError,
      );
    });

    test('没有格就没有清单（不装这一层）', () {
      expect(castBeatSlidesContent(rows: const [], paths: const []), '');
    });
  });

  group('装不装这一层', () {
    test('没有可画的格：不装（全是不显示的段也一样）', () {
      expect(castBeatCountActive(null), isFalse);
      expect(
        castBeatCountActive(overlay(rows: <CastBeatCountRow>[row(0, 1000)])),
        isFalse,
      );
    });

    test('落位退化（非有限 / 非正）不装', () {
      final rows = <CastBeatCountRow>[row(0, 1000, value: text('1', '1'))];

      expect(
        castBeatCountActive(overlay(rows: rows, widthFraction: 0)),
        isFalse,
      );
      expect(
        castBeatCountActive(overlay(rows: rows, centerX: double.nan)),
        isFalse,
      );
      expect(castBeatCountActive(overlay(rows: rows)), isTrue);
    });
  });

  group('滤镜节点：一路序列 + 一个叠加节点（不做逐拍节点、不做动画）', () {
    CastBeatCountGraph graphOf({List<CastBeatCountRow>? rows}) =>
        castBeatCountGraph(
          overlay: overlay(
            rows:
                rows ??
                <CastBeatCountRow>[
                  row(0, 1000, value: text('0', '8')),
                  row(1000, 2000, value: text('1', '1', group: '2')),
                ],
          ),
          startLabel: 'vbase',
          endLabel: 'vbeat',
          inputIndex: 2,
          fps: 30,
        );

    test('四条节点：序列归一（rgba + 主片帧率）、按帧比例缩放、送回 alpha、叠加', () {
      final graph = graphOf();

      expect(graph.nodes, hasLength(4));
      expect(graph.nodes[0], '[2:v]format=rgba,fps=30[bseq2]');
      expect(
        graph.nodes[1],
        '[bseq2][vbase]scale2ref=w=iw*0.3:h=ih*0.2[bcan2][bmai2]',
      );
      expect(graph.nodes[2], '[bcan2]format=rgba[bsa2]');
      expect(graph.endLabel, 'vbeat');
      expect(
        graph.nodes.last,
        '[bmai2][bsa2]overlay='
        'x=(W*0.5)-(w/2):y=(H*0.25)-(h/2):'
        'format=rgb:eof_action=repeat[vbeat]',
      );
    });

    test('一层只有一个 overlay：不做逐拍 enable 窗、也不做任何动画节点', () {
      final graph = graphOf();

      final overlays = graph.nodes.where((n) => n.contains('overlay='));
      expect(overlays, hasLength(1), reason: '上百拍若各一节点，真机开销陡增');
      for (final node in graph.nodes) {
        expect(node, isNot(contains('enable=')), reason: '时间窗在序列的时长里，不在 enable');
        expect(node, isNot(contains('drawtext')), reason: 'min 变体没有 drawtext');
        expect(node, isNot(contains('drawbox')), reason: '不做方块/游标一类的动画');
      }
    });

    test('不装时给零节点、链尾标签原样穿过', () {
      final graph = castBeatCountGraph(
        overlay: overlay(rows: <CastBeatCountRow>[row(0, 1000)]),
        startLabel: 'vbase',
        endLabel: 'vbeat',
        inputIndex: 2,
        fps: 30,
      );

      expect(graph.nodes, isEmpty);
      expect(graph.endLabel, 'vbase');
    });
  });
}
