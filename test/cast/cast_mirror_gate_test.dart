import 'package:dance_learning_app/cast/cast_mirror_gate.dart';
import 'package:dance_learning_app/core/local_mirror_fragment.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart';
import 'package:flutter_test/flutter_test.dart';

/// 投屏镜像闸门直测（纯件）：画面链里的翻转节点**是外部契约**（它决定产物），
/// 按关键片段快照式断言，不跑进程、不启动 widget。
///
/// 判定走两条**独立**的路，不拿被测代码反算：
/// 1. 上屏那一路的期望值来自画面方向库（[SurfaceDirection] 的源视频面方向，
///    即手机上实际显示的那一份），渲染这一路来自本件产出的滤镜节点——两侧
///    都是**从产物节点里读回来**的（下面的 [renderedMirroredAt] 解析表达式），
///    因此「同一入参 → 同一翻转结果」是被真比对出来的；
/// 2. 半开区间的端点、多片段成窗等期望值按规格独立写在用例里。
void main() {
  const fragments = [
    LocalMirrorFragment(startMs: 1000, endMs: 2000),
    LocalMirrorFragment(startMs: 3000, endMs: 4000),
  ];

  /// 上屏取值：手机在 `positionMs` 显示的源视频面方向（画面方向库那一份）。
  ///
  /// 源视频面不读练习镜像与平台基线（只读全局镜像、局部镜像开关与片段表），
  /// 故这两项按「不镜像 / 两基准均原相」读入——取值口径不因此改变。
  FaceDirection onScreenAt({
    required bool globalMirrored,
    required bool localMirrorEnabled,
    required List<LocalMirrorFragment> mirrorFragments,
    required int positionMs,
  }) => SurfaceDirection(
    moment: SurfaceMoment(
      globalMirrored: globalMirrored,
      localMirrorEnabled: localMirrorEnabled,
      fragments: mirrorFragments,
      positionMs: positionMs,
      practiceMirror: false,
      baselines: const SurfaceBaselines(
        platformPreviewBasis: FaceDirection.original,
        platformSaveBasis: FaceDirection.original,
      ),
    ),
  ).directionOf(SurfaceFace.sourceVideo);

  SourceVideoFlip gateOf({
    required bool globalMirrored,
    required bool localMirrorEnabled,
    required List<LocalMirrorFragment> mirrorFragments,
  }) => SourceVideoFlip(
    globalMirrored: globalMirrored,
    localMirrorEnabled: localMirrorEnabled,
    fragments: mirrorFragments,
  );

  /// **测试侧的表达式读回器**：认 `gte(t,起)*lt(t,止)` 逐项相加（任一项为真
  /// 即真），恒假给 `0`。它与被测代码的窗口表无关——读的是产出的那串字面量。
  bool Function(double seconds) enableReader(String expression) {
    if (expression == '0') return (_) => false;
    final terms = <(double, double)>[];
    for (final term in expression.split('+')) {
      final match = RegExp(r'^gte\(t,([\d.]+)\)\*lt\(t,([\d.]+)\)$')
          .firstMatch(term);
      if (match == null) {
        throw FormatException('读不出的时间窗项：$term');
      }
      terms.add((double.parse(match.group(1)!), double.parse(match.group(2)!)));
    }
    return (seconds) =>
        terms.any((window) => window.$1 <= seconds && seconds < window.$2);
  }

  /// **产物侧读数**：这套滤镜节点在 `seconds`（源时间轴）是否**净翻转**。
  /// 两枚 `hflip` 同时生效即相消——这正是「两个都开 = 净不翻」的像素机关。
  bool renderedMirroredAt(List<String> nodes, double seconds) {
    var flips = 0;
    for (final node in nodes) {
      if (node == 'hflip') {
        flips++;
        continue;
      }
      final match = RegExp(r"^hflip=enable='(.+)'$").firstMatch(node);
      if (match == null) {
        throw FormatException('读不出的镜像节点：$node');
      }
      if (enableReader(match.group(1)!)(seconds)) {
        flips++;
      }
    }
    return flips.isOdd;
  }

  String enableExpressionOf(List<String> nodes) {
    final node = nodes.firstWhere(
      (n) => n.startsWith("hflip=enable='"),
      orElse: () => throw StateError('这套节点里没有时间窗闸门：$nodes'),
    );
    return RegExp(r"^hflip=enable='(.+)'$").firstMatch(node)!.group(1)!;
  }

  group('与上屏同一份出处：同一入参 → 同一翻转结果', () {
    for (final globalMirrored in [true, false]) {
      for (final localMirrorEnabled in [true, false]) {
        test('全局 $globalMirrored / 局部总开关 $localMirrorEnabled：逐格同判', () {
          final nodes = castMirrorFilterNodes(
            gateOf(
              globalMirrored: globalMirrored,
              localMirrorEnabled: localMirrorEnabled,
              mirrorFragments: fragments,
            ),
          );

          for (final positionMs in [
            0,
            500,
            1000,
            1500,
            1999,
            2000,
            2500,
            3000,
            3999,
            4000,
            5000,
            8000,
          ]) {
            expect(
              renderedMirroredAt(nodes, positionMs / 1000),
              onScreenAt(
                globalMirrored: globalMirrored,
                localMirrorEnabled: localMirrorEnabled,
                mirrorFragments: fragments,
                positionMs: positionMs,
              ).isMirrored,
              reason:
                  '位置 ${positionMs}ms 上，产物节点读回的翻转结果必须与'
                  '手机上实际显示的源视频面方向一致',
            );
          }
        });
      }
    }

    test('只开全局：整片一枚无窗闸门', () {
      final nodes = castMirrorFilterNodes(
        gateOf(
          globalMirrored: true,
          localMirrorEnabled: true,
          mirrorFragments: const [],
        ),
      );

      expect(nodes, <String>['hflip']);
      expect(renderedMirroredAt(nodes, 0), isTrue);
      expect(renderedMirroredAt(nodes, 1.5), isTrue);
      expect(renderedMirroredAt(nodes, 99), isTrue, reason: '窗外仍是镜面');
    });

    test('只开局部：窗内翻、窗外不翻', () {
      final nodes = castMirrorFilterNodes(
        gateOf(
          globalMirrored: false,
          localMirrorEnabled: true,
          mirrorFragments: fragments,
        ),
      );

      expect(renderedMirroredAt(nodes, 1.5), isTrue);
      expect(renderedMirroredAt(nodes, 2.5), isFalse);
      expect(renderedMirroredAt(nodes, 3.5), isTrue);
      expect(renderedMirroredAt(nodes, 0), isFalse);
      expect(renderedMirroredAt(nodes, 9), isFalse);
    });

    test('两个都开：窗内净不翻（两枚闸门相消）、窗外是镜面', () {
      final nodes = castMirrorFilterNodes(
        gateOf(
          globalMirrored: true,
          localMirrorEnabled: true,
          mirrorFragments: fragments,
        ),
      );

      expect(nodes, hasLength(2), reason: '全局一枚 + 局部一枚');
      expect(nodes.first, 'hflip', reason: '全局那一枚是整片无窗的');
      expect(renderedMirroredAt(nodes, 1.5), isFalse);
      expect(renderedMirroredAt(nodes, 2.5), isTrue);
    });

    test('总开关关掉：片段整组不参与，只剩全局那一枚', () {
      final nodes = castMirrorFilterNodes(
        gateOf(
          globalMirrored: true,
          localMirrorEnabled: false,
          mirrorFragments: fragments,
        ),
      );

      expect(nodes, <String>['hflip']);
      expect(renderedMirroredAt(nodes, 1.5), isTrue);
    });

    test('都不开：一枚闸门都不装（画面原样通过）', () {
      expect(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: false,
            localMirrorEnabled: true,
            mirrorFragments: const [],
          ),
        ),
        isEmpty,
        reason: '全局关、这支舞又没有局部镜像片段',
      );
      expect(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: false,
            localMirrorEnabled: false,
            mirrorFragments: fragments,
          ),
        ),
        isEmpty,
        reason: '全局关、局部总开关也关',
      );
    });
  });

  group('半开区间 [起, 止)：不多翻一帧也不少翻一帧', () {
    test('恰好落在起止时刻的两帧：起点算窗内、终点算窗外', () {
      // 期望值按规格独立写出：局部镜像只看窗内，全局镜像在窗外单独生效。
      final onlyLocal = castMirrorFilterNodes(
        gateOf(
          globalMirrored: false,
          localMirrorEnabled: true,
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 2000, endMs: 6000),
          ],
        ),
      );
      expect(
        renderedMirroredAt(onlyLocal, 2.0),
        isTrue,
        reason: '起点那一帧（t=2）算窗内',
      );
      expect(
        renderedMirroredAt(onlyLocal, 6.0),
        isFalse,
        reason: '终点那一帧（t=6）算窗外——between 在这里会多翻一帧',
      );
      expect(renderedMirroredAt(onlyLocal, 1.999), isFalse);
      expect(renderedMirroredAt(onlyLocal, 5.999), isTrue);

      final both = castMirrorFilterNodes(
        gateOf(
          globalMirrored: true,
          localMirrorEnabled: true,
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 2000, endMs: 6000),
          ],
        ),
      );
      expect(renderedMirroredAt(both, 2.0), isFalse, reason: '起点净不翻');
      expect(renderedMirroredAt(both, 6.0), isTrue, reason: '终点回到全局镜像');
    });

    test('时间窗写成 gte(t,起)*lt(t,止)，绝不出现 between', () {
      final expression = enableExpressionOf(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: false,
            localMirrorEnabled: true,
            mirrorFragments: const [
              LocalMirrorFragment(startMs: 2000, endMs: 6000),
            ],
          ),
        ),
      );

      expect(expression, 'gte(t,2)*lt(t,6)');
      expect(expression, isNot(contains('between')));
    });

    test('秒的字面量：整秒不写成 2.0，毫秒余数原样带出', () {
      expect(
        enableExpressionOf(
          castMirrorFilterNodes(
            gateOf(
              globalMirrored: false,
              localMirrorEnabled: true,
              mirrorFragments: const [
                LocalMirrorFragment(startMs: 2500, endMs: 10125),
              ],
            ),
          ),
        ),
        'gte(t,2.5)*lt(t,10.125)',
      );
      expect(castHalfOpenWindowExpression(0, 1000), 'gte(t,0)*lt(t,1)');
    });
  });

  group('多片段：互不重叠时各自成窗', () {
    test('两段的窗按 + 相加，各自半开', () {
      final nodes = castMirrorFilterNodes(
        gateOf(
          globalMirrored: false,
          localMirrorEnabled: true,
          mirrorFragments: const [
            LocalMirrorFragment(startMs: 1000, endMs: 2000),
            LocalMirrorFragment(startMs: 5000, endMs: 7000),
          ],
        ),
      );

      expect(enableExpressionOf(nodes), 'gte(t,1)*lt(t,2)+gte(t,5)*lt(t,7)');
      for (final (seconds, expected) in [
        (0.0, false),
        (1.0, true),
        (1.999, true),
        (2.0, false),
        (4.0, false),
        (5.0, true),
        (6.999, true),
        (7.0, false),
      ]) {
        expect(
          renderedMirroredAt(nodes, seconds),
          expected,
          reason: 't=$seconds 相对两段窗的判定',
        );
      }
    });

    test('空片段表 / 退化窗（起 = 止）都不产出时间窗闸门', () {
      expect(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: false,
            localMirrorEnabled: true,
            mirrorFragments: const [],
          ),
        ),
        isEmpty,
      );
      expect(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: false,
            localMirrorEnabled: true,
            mirrorFragments: const [
              LocalMirrorFragment(startMs: 2000, endMs: 2000),
            ],
          ),
        ),
        isEmpty,
        reason: '恒假窗不装节点——装了也只会多一次空转',
      );
      expect(
        castMirrorFilterNodes(
          gateOf(
            globalMirrored: true,
            localMirrorEnabled: true,
            mirrorFragments: const [
              LocalMirrorFragment(startMs: 2000, endMs: 2000),
              LocalMirrorFragment(startMs: 4000, endMs: 6000),
            ],
          ),
        ),
        <String>['hflip', "hflip=enable='gte(t,4)*lt(t,6)'"],
        reason: '退化窗被跳过，全局那一枚照旧',
      );
    });

    test('并集表达式：空窗集给恒假 0，读数人不该看到半截滤镜', () {
      expect(castMirrorUnionExpression(const []), '0');
      expect(
        castMirrorUnionExpression(const [
          LocalMirrorFragment(startMs: 1000, endMs: 2000),
          LocalMirrorFragment(startMs: 5000, endMs: 7000),
        ]),
        'gte(t,1)*lt(t,2)+gte(t,5)*lt(t,7)',
      );
    });
  });
}
