/// 带内拖动手势域模块级套件。
///
/// 行为接缝只开在 [TrackBandDragSession] 自己的公开接口上（按族注册 +
/// 起手 + [TrackBandDragHandle] 的逐帧与收口）：不 pump widget、不注容器，
/// 用假会话与记录器直接驱动。断言的都是域交出的外部可观察事实——某次起手
/// 该不该成立、未注册的族起手是不是空、提示弹不弹、请求落点被钳到哪、
/// 陈旧句柄的操作是否为空、逐帧空落点是否不驱动钩子、收口是否幂等。
library;

import 'package:dance_learning_app/annotation/interval_fragment_row.dart'
    show IntervalEdge;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:flutter_test/flutter_test.dart';

/// 全片换手的八族门禁目标（分段线 + 半拍线 + 首尾端标 + 镜像两族 + 备注两族
/// + 练习片段截取）。
const _allGates = <AnnotationGestureTarget>[
  AnnotationGestureTarget.segmentLineMove,
  AnnotationGestureTarget.halfBeatLineMove,
  AnnotationGestureTarget.rangeBoundaryDrag,
  AnnotationGestureTarget.localMirrorMove,
  AnnotationGestureTarget.localMirrorEdgeDrag,
  AnnotationGestureTarget.noteMove,
  AnnotationGestureTarget.noteEdgeDrag,
  AnnotationGestureTarget.practiceClipTrim,
];

/// 本片第二批换手的四族目标身份（镜像两族 + 备注两族）。
const _fourFamilies = <TrackBandDragTarget>[
  TrackBandDragTarget.mirrorMove(2),
  TrackBandDragTarget.mirrorEdge(2, IntervalEdge.end),
  TrackBandDragTarget.noteMove(3),
  TrackBandDragTarget.noteEdge(3, IntervalEdge.start),
];

/// 本片第三批换手的三族目标身份（半拍线 + 首尾端标 + 练习片段截取）。
const _threeFamilies = <TrackBandDragTarget>[
  TrackBandDragTarget.halfBeat(1),
  TrackBandDragTarget.range(VideoRangeBoundary.start),
  TrackBandDragTarget.clipTrim(1, IntervalEdge.end),
];

/// 被门禁拒绝时弹一次提示的只有分段线与首尾端标，其余族静默。
bool _defaultPrompt(AnnotationGestureTarget gate) =>
    gate == AnnotationGestureTarget.segmentLineMove ||
    gate == AnnotationGestureTarget.rangeBoundaryDrag;

/// 假模块会话：记录每一次 [moveTo] 的请求，按注入的落点规则返回。
class _FakeDragSession implements DurationDragSession {
  _FakeDragSession({required this.landing});

  final Duration? Function(Duration request) landing;
  final List<Duration> requests = <Duration>[];
  int ends = 0;

  @override
  Duration? moveTo(Duration target) {
    requests.add(target);
    return landing(target);
  }

  @override
  void end() => ends++;
}

/// 域 + 依赖闭包 + 记录器的一次装配。
class _Harness {
  _Harness({
    Set<AnnotationGestureTarget>? declaredGates,
    this.promptOnGateReject,
    this.yieldOnMixedBurst,
    this.admit,
    this.readGrabOffsetMs,
  }) {
    for (final gate in declaredGates ?? _allGates) {
      families.register(gate, _declarationFor(gate));
    }
    session = TrackBandDragSession(
      families: families,
      isPinchActive: () => pinchActive,
      isMixedBurstActive: () => mixedBurstActive,
      loadGateActive: () => loadGateActive,
      gestureStartRejected: (target) {
        rejectedQueries.add(target);
        return rejected.contains(target);
      },
      promptOnReject: (target) => prompts.add(target),
      bandWidth: () => width,
    );
  }

  /// 按族构造一条声明：登记进注册表的就是它，取回时能逐位对上是同一对象。
  TrackBandDragDeclaration _declarationFor(AnnotationGestureTarget gate) {
    return TrackBandDragDeclaration(
      toTime: (x, width) => toTime(x, width),
      beginSession: (target) {
        beginCalls.add(target);
        events.add('session');
        final session = _FakeDragSession(landing: (r) => landing(r));
        sessions.add(session);
        return session;
      },
      promptOnGateReject: promptOnGateReject ?? _defaultPrompt(gate),
      yieldOnMixedBurst: yieldOnMixedBurst ?? false,
      admit: admit,
      readGrabOffsetMs: readGrabOffsetMs,
      onBegin: (target) {
        beginHooks.add(target);
        events.add('beginHook');
      },
      onFrame: (landing) => frameHooks.add(landing),
      onEnd: () => endHooks++,
    );
  }

  final families = TrackBandDragFamilies();
  final beginCalls = <TrackBandDragTarget>[];
  final sessions = <_FakeDragSession>[];
  final beginHooks = <TrackBandDragTarget>[];
  final frameHooks = <Duration>[];
  final rejectedQueries = <AnnotationGestureTarget>[];
  final prompts = <AnnotationGestureTarget>[];
  final events = <String>[];
  int endHooks = 0;

  bool pinchActive = false;
  bool mixedBurstActive = false;
  bool loadGateActive = false;
  final bool? promptOnGateReject;
  final bool? yieldOnMixedBurst;
  final rejected = <AnnotationGestureTarget>{};
  double? width = 800;
  Duration? Function(double localX, double bandWidth) toTime = (x, _) =>
      Duration(milliseconds: x.round());
  Duration? Function(Duration request) landing = (r) => r;
  final bool Function(TrackBandDragTarget target, double localX)? admit;
  final int? Function(TrackBandDragTarget target, Duration finger)?
  readGrabOffsetMs;

  late final TrackBandDragSession session;

  _FakeDragSession get onlySession => sessions.single;
}

/// 第九族（预览线拖动）的装配：**没有模块事务**（声明里无 `beginSession`），
/// 准入读起手局部 x，换算与三段钩子各记一笔。
class _PreviewLineHarness {
  _PreviewLineHarness({this.columnAdmits = true, this.width = 800}) {
    families.register(
      AnnotationGestureTarget.previewLineDrag,
      TrackBandDragDeclaration(
        // 与带级同形：seek 不是写盘入口，装载门不挡本族。
        respectLoadGate: false,
        toTime: (localX, bandWidth) {
          conversions.add((localX, bandWidth));
          return Duration(milliseconds: localX.round());
        },
        admit: (target, localX) {
          admits.add(localX);
          return columnAdmits;
        },
        onBegin: (target) => events.add('begin'),
        onFrame: frames.add,
        onEnd: () => events.add('end'),
      ),
    );
    session = TrackBandDragSession(
      families: families,
      isPinchActive: () => pinchActive,
      isMixedBurstActive: () => false,
      loadGateActive: () => loadGateActive,
      gestureStartRejected: (_) => false,
      promptOnReject: (_) => prompts++,
      bandWidth: () => width,
    );
  }

  final families = TrackBandDragFamilies();
  final bool columnAdmits;
  final conversions = <(double, double)>[];
  final admits = <double>[];
  final frames = <Duration>[];
  final events = <String>[];
  int prompts = 0;
  bool pinchActive = false;
  bool loadGateActive = false;
  double? width;

  late final TrackBandDragSession session;
}

/// 第十族（学习段圈选）的自家帧与记录器：帧工厂返回空 = 起手不成立
/// （只读拒绝），帧的三条出口各记一笔。
class _SpanHarness {
  _SpanHarness() {
    families.register(
      AnnotationGestureTarget.learningTrackTap,
      TrackBandDragDeclaration(
        yieldOnMixedBurst: true,
        // 与带级同形：半途加入由本族的帧回滚取消，域不代它冻结。
        freezeOnPinch: false,
        beginFrame: (target) {
          begins.add(target);
          if (!spanBegins) return null;
          final frame = TrackBandDragFrame(
            moveTo: moves.add,
            end: () => exits.add('commit'),
            cancel: () => exits.add('cancel'),
          );
          frames.add(frame);
          return frame;
        },
        onBegin: (target) => events.add('begin'),
      ),
    );
    session = TrackBandDragSession(
      families: families,
      isPinchActive: () => pinchActive,
      isMixedBurstActive: () => mixedBurstActive,
      loadGateActive: () => false,
      gestureStartRejected: (_) => false,
      promptOnReject: (_) => prompts++,
      bandWidth: () => 800,
    );
  }

  final families = TrackBandDragFamilies();
  final begins = <TrackBandDragTarget>[];
  final frames = <TrackBandDragFrame>[];
  final moves = <Offset>[];
  final exits = <String>[];
  final events = <String>[];
  int prompts = 0;
  bool spanBegins = true;
  bool pinchActive = false;
  bool mixedBurstActive = false;

  late final TrackBandDragSession session;
  TrackBandDragFrame get onlyFrame => frames.single;
}

void main() {
  const target = AnnotationGestureTarget.segmentLineMove;

  group('起手门序言', () {
    test('双指在场让位：起手为空且不建会话、不弹提示', () {
      final h = _Harness()..pinchActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('装载门：起手为空且不建会话', () {
      final h = _Harness()..loadGateActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
    });

    test('门禁表拒绝：起手为空、不建会话，按声明弹一次提示', () {
      final h = _Harness()..rejected.add(target);
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.prompts, [target]);
      expect(h.beginCalls, isEmpty);
      expect(h.frameHooks, isEmpty);
    });

    test('静默族（不声明提示）：被拒时零提示', () {
      final h = _Harness(promptOnGateReject: false);
      h.rejected.add(target);
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.prompts, isEmpty);
    });

    test('准入不通过：起手为空且不建会话、不弹提示', () {
      final h = _Harness(admit: (t, x) => false);
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('边界读取失败（几何不可用）：起手为空且不建会话', () {
      final h = _Harness(readGrabOffsetMs: (t, finger) => null);
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
    });

    test('未注册的族：起手为空（不是接线错误），不建会话、零提示', () {
      final h = _Harness(declaredGates: const {});
      expect(
        h.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
    });

    test('次序：模块会话先建、起手钩子后到；句柄非空', () {
      final h = _Harness();
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        100,
      );
      expect(handle, isNotNull);
      expect(h.events, ['session', 'beginHook']);
      expect(h.beginHooks, [const TrackBandDragTarget.segmentLine(0)]);
    });
  });

  group('逐帧落点回写', () {
    test('写后落点为空：逐帧返回空且不触发落点钩子', () {
      final h = _Harness()..landing = (r) => null;
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      expect(handle.moveTo(120), isNull);
      expect(h.onlySession.requests, [const Duration(milliseconds: 120)]);
      expect(h.frameHooks, isEmpty);
    });

    test('写后落点非空：逐帧原样返回并恰好触发一次落点钩子', () {
      final h = _Harness()
        ..landing = (r) => r + const Duration(milliseconds: 5);
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      expect(handle.moveTo(120), const Duration(milliseconds: 125));
      expect(h.frameHooks, [const Duration(milliseconds: 125)]);
    });
  });

  group('钳制口径（一条规则、一处实现）', () {
    test('八族（含分段线）共用同一条规则：带外局部 x 一律钳到 [0, 带宽]', () {
      final h = _Harness();
      final families = <TrackBandDragTarget>[
        const TrackBandDragTarget.segmentLine(0),
        ..._fourFamilies,
        ..._threeFamilies,
      ];
      for (final target in families) {
        final handle = h.session.begin(target, 0)!;
        handle.moveTo(1200);
        handle.moveTo(-50);
        expect(h.sessions.last.requests, [
          const Duration(milliseconds: 800),
          Duration.zero,
        ], reason: '$target 与其余族同一口径：带外请求被钳在 [0, 带宽]');
        handle.end();
      }
    });

    test('几何不可用（带宽为空）：逐帧返回空且不碰模块会话', () {
      final h = _Harness();
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      h.width = null;
      expect(handle.moveTo(120), isNull);
      expect(h.onlySession.requests, isEmpty);
      expect(h.frameHooks, isEmpty);
    });
  });

  group('抓取偏移（边界读取）', () {
    test('请求 = 手指时间 − 抓取偏移', () {
      final h = _Harness(readGrabOffsetMs: (t, finger) => 40);
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      handle.moveTo(100);
      expect(h.onlySession.requests, [const Duration(milliseconds: 60)]);
    });
  });

  group('单槽与世代', () {
    test('新起手覆盖旧槽：旧句柄逐帧与收口都是空操作、不动新会话', () {
      final h = _Harness();
      final stale = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      final current = h.session.begin(
        const TrackBandDragTarget.segmentLine(1),
        0,
      )!;

      expect(stale.moveTo(100), isNull);
      expect(stale, isNot(same(current)));
      expect(h.sessions.first.requests, isEmpty);

      stale.end();
      expect(h.sessions.first.ends, 0);
      expect(h.endHooks, 0);
      expect(h.session.activeHandle, same(current));

      expect(current.moveTo(100), const Duration(milliseconds: 100));
      expect(h.sessions.last.requests, [const Duration(milliseconds: 100)]);
    });

    test('重复收口幂等：模块会话只收一次、收口钩子只触发一次', () {
      final h = _Harness();
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      handle.end();
      handle.end();
      expect(h.onlySession.ends, 1);
      expect(h.endHooks, 1);
      expect(h.session.activeHandle, isNull);
    });

    test('收口后逐帧为空操作', () {
      final h = _Harness();
      final handle = h.session.begin(
        const TrackBandDragTarget.segmentLine(0),
        0,
      )!;
      handle.end();
      expect(handle.moveTo(100), isNull);
      expect(h.onlySession.requests, isEmpty);
    });
  });

  group('按族注册入口与注册表完整性', () {
    test('目标身份携带模块门禁表里的门禁目标，且声明按它一一对应', () {
      const line = TrackBandDragTarget.segmentLine(3);
      expect(line.gateTarget, AnnotationGestureTarget.segmentLineMove);
      expect(line, isA<SegmentLineDragTarget>());
      expect((line as SegmentLineDragTarget).index, 3);
      expect(_Harness().families.declarationFor(line.gateTarget), isNotNull);
    });

    test('八族各恰好一条登记，门禁目标与模块门禁表一一对应', () {
      final families = _Harness().families;
      expect(families.gates, unorderedEquals(_allGates));
      expect(_allGates.toSet().length, 8, reason: '模块门禁表里八族 verb 各一个');
      expect(_fourFamilies.map((target) => target.gateTarget), [
        AnnotationGestureTarget.localMirrorMove,
        AnnotationGestureTarget.localMirrorEdgeDrag,
        AnnotationGestureTarget.noteMove,
        AnnotationGestureTarget.noteEdgeDrag,
      ]);
      expect(_threeFamilies.map((target) => target.gateTarget), [
        AnnotationGestureTarget.halfBeatLineMove,
        AnnotationGestureTarget.rangeBoundaryDrag,
        AnnotationGestureTarget.practiceClipTrim,
      ]);
      // 目标身份的八族成员与登记键一一对应（不多不少）。
      expect(
        <TrackBandDragTarget>[
          const TrackBandDragTarget.segmentLine(0),
          ..._fourFamilies,
          ..._threeFamilies,
        ].map((target) => target.gateTarget),
        unorderedEquals(_allGates),
      );
    });

    test('登记条目按门禁目标取回：提交的那一条就是取回的那一条', () {
      final h = _Harness(
        declaredGates: const {AnnotationGestureTarget.noteMove},
      );
      final submitted = h.families.declarationFor(
        AnnotationGestureTarget.noteMove,
      );
      expect(submitted, isNotNull);
      expect(
        h.session.families.declarationFor(AnnotationGestureTarget.noteMove),
        same(submitted),
      );

      // 未登记的门禁目标取回为空，且起手为空。
      expect(
        h.families.declarationFor(AnnotationGestureTarget.noteEdgeDrag),
        isNull,
      );
      expect(h.families.gates, [AnnotationGestureTarget.noteMove]);
      expect(
        h.session.begin(
          const TrackBandDragTarget.noteEdge(0, IntervalEdge.start),
          0,
        ),
        isNull,
      );
    });

    test('同族重复登记：后者覆盖前者、不新增键，起手用最后登记的那一条', () {
      final h = _Harness(
        declaredGates: const {AnnotationGestureTarget.noteMove},
      );
      final overridden = h.families.declarationFor(
        AnnotationGestureTarget.noteMove,
      )!;
      final replacement = TrackBandDragDeclaration(
        toTime: (x, width) => Duration(milliseconds: x.round()),
        beginSession: (target) {
          h.beginCalls.add(target);
          final session = _FakeDragSession(landing: (r) => r);
          h.sessions.add(session);
          return session;
        },
      );
      h.families.register(AnnotationGestureTarget.noteMove, replacement);

      expect(
        h.families.declarationFor(AnnotationGestureTarget.noteMove),
        same(replacement),
      );
      expect(
        h.families.declarationFor(AnnotationGestureTarget.noteMove),
        isNot(same(overridden)),
      );
      expect(h.families.gates, [AnnotationGestureTarget.noteMove]);
      expect(
        h.session.begin(const TrackBandDragTarget.noteMove(0), 0),
        isNotNull,
        reason: '同族重复登记后起手按最后登记的那一条进行',
      );
    });
  });

  // 本片换手的四族（镜像整体移 / 镜像端点拖 / 备注整体移 / 备注端点拖）。
  group('镜像与备注四族', () {
    test('目标身份承载线下标与端点，端点类型沿用模块既有词汇', () {
      const move = TrackBandDragTarget.mirrorMove(2);
      expect(move, isA<MirrorMoveDragTarget>());
      expect((move as MirrorMoveDragTarget).index, 2);

      const mirrorEdge = TrackBandDragTarget.mirrorEdge(2, IntervalEdge.end);
      expect((mirrorEdge as MirrorEdgeDragTarget).edge, IntervalEdge.end);

      const noteEdge = TrackBandDragTarget.noteEdge(4, IntervalEdge.start);
      expect((noteEdge as NoteEdgeDragTarget).index, 4);
      expect(noteEdge.edge, IntervalEdge.start);
    });

    test('抓取偏移与相对平移：四族请求 = 手指时间 − 该族边界偏移', () {
      final h = _Harness(readGrabOffsetMs: (target, finger) => 40);
      for (final target in _fourFamilies) {
        final handle = h.session.begin(target, 0)!;
        handle.moveTo(100);
        expect(h.sessions.last.requests, [
          const Duration(milliseconds: 60),
        ], reason: '$target 保持抓取点相对片段不动（不把片段首锚到手指）');
        handle.end();
      }
      expect(h.beginCalls, _fourFamilies);
    });

    test('钳制口径：四族逐帧钳到带内，请求被钳在 [0, 带宽]', () {
      final h = _Harness();
      for (final target in _fourFamilies) {
        final handle = h.session.begin(target, 0)!;
        handle.moveTo(1200);
        handle.moveTo(-50);
        expect(h.sessions.last.requests, [
          const Duration(milliseconds: 800),
          Duration.zero,
        ], reason: '$target 钳到带内');
        handle.end();
      }
    });

    test('越界准入：按列表长度的拒绝静默返回（不建会话、零提示）', () {
      final h = _Harness(admit: (target, x) => false);
      for (final target in _fourFamilies) {
        expect(h.session.begin(target, 0), isNull, reason: '$target 越界静默');
      }
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
      expect(h.beginHooks, isEmpty);
    });

    test('内容锁准入：备注两族被拒时静默不参与、不弹提示', () {
      final h = _Harness(
        admit: (target, x) =>
            target is! NoteMoveDragTarget && target is! NoteEdgeDragTarget,
      );
      expect(h.session.begin(const TrackBandDragTarget.noteMove(0), 0), isNull);
      expect(
        h.session.begin(
          const TrackBandDragTarget.noteEdge(0, IntervalEdge.start),
          0,
        ),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
      expect(
        h.session.begin(const TrackBandDragTarget.mirrorMove(0), 0),
        isNotNull,
        reason: '准入逐族声明：同一次装配下镜像族照常起手',
      );
    });

    test('几何不可用：四族起手与逐帧都返回空、不碰模块会话', () {
      final h = _Harness(readGrabOffsetMs: (target, finger) => 0);
      h.width = null;
      for (final target in _fourFamilies) {
        expect(h.session.begin(target, 0), isNull, reason: '$target 起手为空');
      }
      expect(h.beginCalls, isEmpty);

      h.width = 800;
      final handle = h.session.begin(
        const TrackBandDragTarget.mirrorMove(0),
        0,
      )!;
      h.width = null;
      expect(handle.moveTo(120), isNull);
      expect(h.onlySession.requests, isEmpty);
      expect(h.frameHooks, isEmpty);
    });

    test('跨族覆盖的单槽与世代：旧句柄空操作、不动新会话', () {
      final h = _Harness();
      final stale = h.session.begin(
        const TrackBandDragTarget.mirrorMove(0),
        0,
      )!;
      final current = h.session.begin(
        const TrackBandDragTarget.noteMove(0),
        0,
      )!;

      expect(stale.moveTo(100), isNull);
      stale.end();
      expect(h.sessions.first.requests, isEmpty);
      expect(h.sessions.first.ends, 0);
      expect(h.endHooks, 0);
      expect(h.session.activeHandle, same(current));

      expect(current.moveTo(100), const Duration(milliseconds: 100));
      expect(h.sessions.last.requests, [const Duration(milliseconds: 100)]);
    });
  });

  // 本片换手的三族（半拍线 / 首尾端标 / 练习片段截取）。
  group('半拍线、首尾端标与练习片段截取三族', () {
    test('目标身份承载下标 / 端标 / 端点，门禁目标取模块词汇', () {
      const halfBeat = TrackBandDragTarget.halfBeat(1);
      expect(halfBeat, isA<HalfBeatDragTarget>());
      expect(halfBeat.index, 1);
      expect(halfBeat.gateTarget, AnnotationGestureTarget.halfBeatLineMove);

      const range = TrackBandDragTarget.range(VideoRangeBoundary.end);
      expect(range, isA<RangeDragTarget>());
      expect((range as RangeDragTarget).boundary, VideoRangeBoundary.end);
      expect(range.gateTarget, AnnotationGestureTarget.rangeBoundaryDrag);

      const trim = TrackBandDragTarget.clipTrim(2, IntervalEdge.start);
      expect((trim as ClipTrimDragTarget).index, 2);
      expect(trim.edge, IntervalEdge.start);
      expect(trim.gateTarget, AnnotationGestureTarget.practiceClipTrim);
    });

    test('抓取偏移逐族声明：半拍线与首尾端标不记偏移，截取记偏移', () {
      // 不记偏移：请求即手指时间（换算输出原样）。
      final plain = _Harness();
      for (final target in const [
        TrackBandDragTarget.halfBeat(0),
        TrackBandDragTarget.range(VideoRangeBoundary.start),
      ]) {
        final handle = plain.session.begin(target, 0)!;
        handle.moveTo(100);
        expect(plain.sessions.last.requests, [
          const Duration(milliseconds: 100),
        ]);
        handle.end();
      }
      // 截取：请求 = 手指时间 − 抓取偏移（同镜像端点拖口径）。
      final offset = _Harness(readGrabOffsetMs: (t, finger) => 40);
      final handle = offset.session.begin(
        const TrackBandDragTarget.clipTrim(0, IntervalEdge.start),
        0,
      )!;
      handle.moveTo(100);
      expect(offset.sessions.last.requests, [const Duration(milliseconds: 60)]);
    });

    test('钳制口径：三族逐帧钳到带内，请求被钳在 [0, 带宽]', () {
      final h = _Harness();
      for (final target in _threeFamilies) {
        final handle = h.session.begin(target, 0)!;
        handle.moveTo(1200);
        handle.moveTo(-50);
        expect(h.sessions.last.requests, [
          const Duration(milliseconds: 800),
          Duration.zero,
        ], reason: '$target 钳到带内');
        handle.end();
      }
    });

    test('几何不可用：首尾端标自取几何轴的换算返回空，逐帧不驱动画面', () {
      final h = _Harness()..toTime = (x, width) => null;
      final handle = h.session.begin(
        const TrackBandDragTarget.range(VideoRangeBoundary.end),
        0,
      )!;
      expect(handle.moveTo(100), isNull);
      expect(h.onlySession.requests, isEmpty);
      expect(h.frameHooks, isEmpty);
    });

    test('混区 burst 让位逐族声明：截取族起手为空，其余族照常起手', () {
      final h = _Harness(yieldOnMixedBurst: true)..mixedBurstActive = true;
      expect(
        h.session.begin(
          const TrackBandDragTarget.clipTrim(0, IntervalEdge.start),
          0,
        ),
        isNull,
      );
      expect(h.beginCalls, isEmpty);

      // 未声明该让位的族在同一次装配下不受影响。
      final plain = _Harness()..mixedBurstActive = true;
      expect(
        plain.session.begin(const TrackBandDragTarget.halfBeat(0), 0),
        isNotNull,
      );
      expect(
        plain.session.begin(
          const TrackBandDragTarget.range(VideoRangeBoundary.start),
          0,
        ),
        isNotNull,
      );
    });

    test('首尾端标：不预检索引、被门禁拒时弹一次提示', () {
      final h = _Harness();
      // 首尾端标无索引准入：不声明 admit，起手照常成立。
      expect(
        h.session.begin(
          const TrackBandDragTarget.range(VideoRangeBoundary.start),
          0,
        ),
        isNotNull,
      );
      h.rejected.add(AnnotationGestureTarget.rangeBoundaryDrag);
      expect(
        h.session.begin(
          const TrackBandDragTarget.range(VideoRangeBoundary.end),
          0,
        ),
        isNull,
      );
      expect(h.prompts, [AnnotationGestureTarget.rangeBoundaryDrag]);
      expect(h.beginCalls.length, 1, reason: '被拒不建第二个会话');
    });

    test('越界准入：截取族按列表长度静默返回（不建会话、零提示）', () {
      final h = _Harness(admit: (target, x) => false);
      expect(
        h.session.begin(
          const TrackBandDragTarget.clipTrim(0, IntervalEdge.end),
          0,
        ),
        isNull,
      );
      expect(h.beginCalls, isEmpty);
      expect(h.prompts, isEmpty);
    });
  });

  group('第九族：预览线拖动（无模块事务）', () {
    test('目标身份取模块既有门禁词汇：预览线拖动 = previewLineDrag（无门）', () {
      expect(
        const TrackBandDragTarget.previewLine().gateTarget,
        AnnotationGestureTarget.previewLineDrag,
      );
      expect(const TrackBandDragTarget.previewLine().index, -1);
    });

    test('准入读起手局部 x：落点不在预览线命中列内 → 起手为空、零钩子、零痕迹', () {
      final h = _PreviewLineHarness(columnAdmits: false);
      expect(
        h.session.begin(const TrackBandDragTarget.previewLine(), 137),
        isNull,
      );
      expect(h.admits, [137], reason: '准入读的是本次起手的带内局部 x');
      expect(h.events, isEmpty);
      expect(h.frames, isEmpty);
      expect(h.prompts, 0);
    });

    test('落点在命中列内：起手成立，起手钩子恰好一次', () {
      final h = _PreviewLineHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        137,
      );
      expect(handle, isNotNull);
      expect(handle!.target, const TrackBandDragTarget.previewLine());
      expect(h.events, ['begin']);
    });

    test('装载门不挡本族：seek 不是写盘入口（逐族声明的既有差异）', () {
      final h = _PreviewLineHarness()..loadGateActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.previewLine(), 100),
        isNotNull,
        reason: '预览线拖动不过装载门；写盘各族照旧被挡',
      );
      final blocked = _Harness()..loadGateActive = true;
      expect(
        blocked.session.begin(const TrackBandDragTarget.segmentLine(0), 100),
        isNull,
        reason: '写盘族照旧被装载门挡下',
      );
    });

    test('双指在场：起手为空（让位），无模块事务也不留痕', () {
      final h = _PreviewLineHarness()..pinchActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.previewLine(), 100),
        isNull,
      );
      expect(h.events, isEmpty);
    });

    test('没有模块事务：请求即落点，逐帧恰好触发一次落点钩子并原样交回', () {
      final h = _PreviewLineHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        200,
      )!;
      expect(handle.moveTo(320), const Duration(milliseconds: 320));
      expect(h.frames, [const Duration(milliseconds: 320)]);
    });

    test('请求落点被钳到 [0, 带宽]：换算读到的是钳制后的局部 x 与同一带宽', () {
      final h = _PreviewLineHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      handle.moveTo(-50);
      handle.moveTo(900);
      expect(h.conversions, [(0.0, 800.0), (800.0, 800.0)]);
    });

    test('拖动中双指落下：逐帧为空且不驱动落点钩子（冻结）', () {
      final h = _PreviewLineHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      h.pinchActive = true;
      expect(handle.moveTo(300), isNull);
      expect(h.conversions, isEmpty);
      expect(h.frames, isEmpty);
    });

    test('几何不可用（带宽空）：逐帧为空、不驱动画面', () {
      final h = _PreviewLineHarness(width: null);
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      expect(handle.moveTo(300), isNull);
      expect(h.frames, isEmpty);
    });

    test('陈旧句柄：跨族覆盖后旧句柄逐帧与收口都为空操作', () {
      final h = _PreviewLineHarness();
      final stale = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      final fresh = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        400,
      )!;
      expect(stale.moveTo(120), isNull);
      expect(h.frames, isEmpty, reason: '旧句柄不动新会话，也不驱动画面');
      stale.end();
      expect(h.events, ['begin', 'begin'], reason: '旧句柄收口不触发收口钩子');
      expect(fresh.moveTo(500), const Duration(milliseconds: 500));
      expect(h.frames, [const Duration(milliseconds: 500)]);
    });

    test('收口幂等：end 两次只触发一次收口钩子；取消走同一条收口', () {
      final h = _PreviewLineHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      handle.end();
      handle.end();
      expect(h.events, ['begin', 'end']);
      final second = h.session.begin(
        const TrackBandDragTarget.previewLine(),
        100,
      )!;
      second.cancel();
      second.cancel();
      expect(h.events, ['begin', 'end', 'begin', 'end']);
    });
  });

  group('第十族：学习段圈选（自家帧）', () {
    test('目标身份取模块既有门禁词汇：学习段圈选 = learningTrackTap（无门），'
        '并承载落点解析出的段序', () {
      const target = TrackBandDragTarget.learningSpan(3);
      expect(target.gateTarget, AnnotationGestureTarget.learningTrackTap);
      expect(target.index, 3);
    });

    test('帧工厂返回空（只读拒绝）：起手为空、不起手钩子、不留痕', () {
      final h = _SpanHarness()..spanBegins = false;
      expect(
        h.session.begin(const TrackBandDragTarget.learningSpan(1), 0),
        isNull,
      );
      expect(h.begins, [const TrackBandDragTarget.learningSpan(1)]);
      expect(h.events, isEmpty);
      expect(h.exits, isEmpty);
    });

    test('混区 burst 让位：起手为空且不建帧（如实入表的既有差异）', () {
      final h = _SpanHarness()..mixedBurstActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.learningSpan(1), 0),
        isNull,
      );
      expect(h.begins, isEmpty);
    });

    test('双指在场：起手为空', () {
      final h = _SpanHarness()..pinchActive = true;
      expect(
        h.session.begin(const TrackBandDragTarget.learningSpan(1), 0),
        isNull,
      );
      expect(h.begins, isEmpty);
    });

    test('起手成立：起手钩子恰好一次，句柄承载本族身份', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(2),
        0,
      );
      expect(handle, isNotNull);
      expect(handle!.target, const TrackBandDragTarget.learningSpan(2));
      expect(h.events, ['begin']);
      expect(h.onlyFrame, isNotNull);
    });

    test('逐帧交回二维落点：纵坐标参与本族判定，不被吞掉', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(0),
        0,
      )!;
      handle.moveToPoint(const Offset(120, 44));
      handle.moveToPoint(const Offset(300, 12));
      expect(h.moves, [const Offset(120, 44), const Offset(300, 12)]);
    });

    test('拖动中双指落下：逐帧照旧交给自家帧（本族半途加入即回滚取消，不由域冻结）', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(0),
        0,
      )!;
      h.pinchActive = true;
      handle.moveToPoint(const Offset(120, 44));
      expect(h.moves, [const Offset(120, 44)], reason: '冻结与否是逐族声明的既有差异：本族自己回答');
    });

    test('横向入口转派自家帧：moveTo 把带内局部 x 包成落点（纵坐标留空）', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(0),
        0,
      )!;
      expect(handle.moveTo(120), isNull, reason: '自家帧族的落点由族自己解释');
      expect(h.moves, [const Offset(120, 0)]);
    });

    test('声明不变量：自家帧族与模块事务族二选一、必须有换算或自家帧', () {
      expect(
        () => TrackBandDragDeclaration(
          beginSession: (_) => _FakeDragSession(landing: (r) => r),
        ),
        throwsA(isA<AssertionError>()),
        reason: '模块事务族没有换算：拒绝登记',
      );
      expect(
        () => TrackBandDragDeclaration(
          toTime: (x, _) => Duration(milliseconds: x.round()),
          beginSession: (_) => _FakeDragSession(landing: (r) => r),
          beginFrame: (_) => null,
        ),
        throwsA(isA<AssertionError>()),
        reason: '两支帧事务同时声明：拒绝登记',
      );
    });

    test('陈旧句柄：跨族覆盖后旧句柄的逐帧、提交与取消都为空操作', () {
      final h = _SpanHarness();
      final stale = h.session.begin(
        const TrackBandDragTarget.learningSpan(0),
        0,
      )!;
      final fresh = h.session.begin(
        const TrackBandDragTarget.learningSpan(2),
        0,
      )!;
      stale.moveToPoint(const Offset(120, 44));
      stale.end();
      stale.cancel();
      expect(h.moves, isEmpty);
      expect(h.exits, isEmpty);
      fresh.moveToPoint(const Offset(200, 44));
      expect(h.moves, [const Offset(200, 44)]);
    });

    test('提交路径：end 恰好触发一次提交；幂等', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(1),
        0,
      )!;
      handle.end();
      handle.end();
      expect(h.exits, ['commit']);
      handle.moveToPoint(const Offset(200, 44));
      expect(h.moves, isEmpty, reason: '收口后句柄已陈旧，逐帧为空操作');
    });

    test('取消路径：cancel 走自己的那条收口（不是提交）', () {
      final h = _SpanHarness();
      final handle = h.session.begin(
        const TrackBandDragTarget.learningSpan(1),
        0,
      )!;
      handle.moveToPoint(const Offset(200, 44));
      handle.cancel();
      handle.cancel();
      expect(h.exits, ['cancel']);
      expect(h.moves, [const Offset(200, 44)]);
    });
  });
}
