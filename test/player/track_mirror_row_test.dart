import 'package:dance_learning_app/annotation/interval_fragment_row.dart';
import 'package:dance_learning_app/annotation/local_mirror.dart';
import 'package:dance_learning_app/player/annotation_editor.dart'
    show AnnotationGestureTarget, DurationDragSession;
import 'package:dance_learning_app/player/track_band_drag.dart';
import 'package:dance_learning_app/player/track_geometry.dart'
    show TrackBandGeometry, kTrackPrefixWidth;
import 'package:dance_learning_app/player/track_mirror_row.dart';
import 'package:dance_learning_app/player/track_row_table.dart'
    show TrackRowRect;
import 'package:dance_learning_app/player/track_time.dart'
    show TimelineAxis, TimelineWindow;
import 'package:dance_learning_app/player/visual_tokens.dart'
    show
        kLocalMirrorEdgeHitWidth,
        kLocalMirrorEnabledColor,
        kLocalMirrorEnabledIconColor,
        kLocalMirrorNarrowWidth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 直测默认回调：顶层函数声明，故同一份 tear-off 恒相等——域输入按字段
/// 判等（含回调）时，「字段全等、实例不同」的输入才真等值。
void _noopIndex(int _) {}
void _noopDuration(Duration _) {}
void _noopOffset(Offset _) {}
bool _denyHit(Offset _) => false;
void _noop() {}
String? _noAnchor(int _) => null;

/// 直测记录型模块会话：记录逐帧落点，落点非空 = "写后真实落点"。
class _RecordingSession implements DurationDragSession {
  _RecordingSession(this.startMs);

  final List<int> movedTo = [];
  int endCount = 0;

  final int startMs;

  @override
  Duration? moveTo(Duration target) {
    movedTo.add(target.inMilliseconds);
    return target;
  }

  @override
  void end() => endCount++;
}

/// 局部镜像轨域直测：直接 pump 本域的整行
/// 子树，只给显式输入。断言口径是外部可观察行为——按输入渲染出的块矩形与端
/// 点带、行级点按命中与空白落穿、两族拖动经拖动域句柄的落点回写与钩子、空表
/// 与窗口不含时的退化；不断言实现细节。
void main() {
  const bandWidth = 400.0;
  const rowHeight = 30.0;
  const total = Duration(minutes: 1);

  /// 行矩形固定：本域只吃它做纵向几何（顶/高）。
  const rowRect = TrackRowRect(top: 0, height: rowHeight);

  /// 与带内**同一个构造入口**求本域时间轴（内容区让位片头带的口径同源；
  /// 窗口起点 > 0 时让位随窗口收回，故不手写 contentLeft）。
  TimelineAxis axisFor({TimelineWindow? window}) => TrackBandGeometry.eval(
    total: total,
    window: window ?? TimelineWindow.full(total),
    width: bandWidth,
    prefixWidth: kTrackPrefixWidth,
  ).axis;

  TimelineWindow windowOf(Duration start, Duration end) =>
      TimelineWindow(total: total, start: start, end: end);

  /// 紧窗（6s..23.5s）：直测里把片段块的像素宽放大到 40dp 阈值之上——块
  /// 几何本身与窗口无关（只由共用件求值决定），窗口只是取景。
  final tightWindow = windowOf(
    const Duration(seconds: 6),
    const Duration(milliseconds: 23500),
  );

  /// 内容区时间 → 全局 x（直测盒与带同宽同横原点：让位片头带）。
  double xOf(int ms) =>
      kTrackPrefixWidth +
      (ms / total.inMilliseconds) * (bandWidth - kTrackPrefixWidth);

  /// 紧窗下的 时间 → 全局 x（经本域时间轴，与渲染同源）。
  double tightXOf(int ms) => axisFor(window: tightWindow).timeToX(
    Duration(milliseconds: ms),
  );

  IntervalBlockRect? expectedBlock(
    LocalMirrorFragment fragment, {
    required TimelineWindow window,
  }) {
    final axis = axisFor(window: window);
    return intervalBlockRect(
      span: IntervalSpan(startMs: fragment.startMs, endMs: fragment.endMs),
      window: IntervalSpan(
        startMs: window.start.inMilliseconds,
        endMs: window.end.inMilliseconds,
      ),
      trackWidth: axis.contentWidth,
      contentLeft: axis.contentLeft,
    );
  }

  /// 直测布景：一个与带同宽、横原点一致的定宽盒。锚点包装件
  /// （[GuideAnchor]）是 ConsumerWidget，故给一个空 ProviderScope。
  Widget mount(Widget child) => ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: bandWidth,
            height: bandWidth,
            child: Stack(children: [child]),
          ),
        ),
      ),
    ),
  );

  /// 组装一份输入；未指定的回调取直测默认（顶层 tear-off，恒相等）。
  TrackMirrorRowInput buildInput({
    required TimelineAxis axis,
    List<LocalMirrorFragment> fragments = const [],
    TimelineWindow? window,
    bool masterSwitchOn = true,
    int? selectedIndex,
    String? Function(int index)? guideAnchorKeys,
    TrackBandDragSession? dragSession,
    TrackBandDragFamilies? dragFamilies,
    DurationDragSession Function(TrackBandDragTarget target)? beginSession,
    TimelineWindow? viewWindow,
    double? Function(Offset globalPosition)? localXOf,
    void Function(int index)? onTapFragment,
    void Function(Offset globalPosition)? onTapBlank,
    bool Function(Offset globalPosition)? onEditContentHit,
    void Function()? onDragVisualsBegin,
    void Function(Duration landing)? onDragFrame,
    void Function()? onDragVisualsEnd,
  }) => TrackMirrorRowInput(
    rowRect: rowRect,
    axis: axis,
    window: window ?? viewWindow ?? axis.window ?? TimelineWindow.full(total),
    fragments: fragments,
    masterSwitchOn: masterSwitchOn,
    selectedIndex: selectedIndex,
    guideAnchorKeys: guideAnchorKeys ?? _noAnchor,
    dragFamilies: dragFamilies ?? TrackBandDragFamilies(),
    dragSession: dragSession ?? emptyDragDomain(),
    beginSession: beginSession ?? _shippedBeginSession,
    localXOf: localXOf ?? (position) => position.dx,
    onTapFragment: onTapFragment ?? _noopIndex,
    onTapBlank: onTapBlank ?? _noopOffset,
    onEditContentHit: onEditContentHit ?? _denyHit,
    onDragVisualsBegin: onDragVisualsBegin ?? _noop,
    onDragFrame: onDragFrame ?? _noopDuration,
    onDragVisualsEnd: onDragVisualsEnd ?? _noop,
  );

  /// 带「取景窗」的输入（几何断言组专用：窗口只取景，块几何仍由共用件给）。
  TrackMirrorRowInput viewInput({
    required List<LocalMirrorFragment> fragments,
    int? selectedIndex,
    bool masterSwitchOn = true,
    String? Function(int index)? guideAnchorKeys,
    void Function(int index)? onTapFragment,
    void Function(Offset globalPosition)? onTapBlank,
    TrackBandDragSession? dragSession,
    TrackBandDragFamilies? dragFamilies,
    DurationDragSession Function(TrackBandDragTarget target)? beginSession,
    void Function()? onDragVisualsBegin,
    void Function(Duration landing)? onDragFrame,
    void Function()? onDragVisualsEnd,
  }) => buildInput(
    axis: axisFor(window: tightWindow),
    viewWindow: tightWindow,
    fragments: fragments,
    selectedIndex: selectedIndex,
    masterSwitchOn: masterSwitchOn,
    guideAnchorKeys: guideAnchorKeys,
    onTapFragment: onTapFragment,
    onTapBlank: onTapBlank,
    dragSession: dragSession,
    dragFamilies: dragFamilies,
    beginSession: beginSession,
    onDragVisualsBegin: onDragVisualsBegin,
    onDragFrame: onDragFrame,
    onDragVisualsEnd: onDragVisualsEnd,
  );

  group('片段块体渲染（块矩形与端点带）', () {
    testWidgets('块左缘/宽与共用件 intervalBlockRect 求值逐位一致（含片头让位）', (
      tester,
    ) async {
      const fragments = [
        LocalMirrorFragment(startMs: 8000, endMs: 12000),
        LocalMirrorFragment(startMs: 20000, endMs: 24000),
      ];
      await tester.pumpWidget(
        mount(TrackMirrorRow(input: viewInput(fragments: fragments))),
      );

      for (var i = 0; i < fragments.length; i++) {
        final expected = expectedBlock(fragments[i], window: tightWindow)!;
        final rendered = tester.getRect(
          find.byKey(ValueKey('mirror_fragment_$i')),
        );
        expect(
          rendered.left,
          closeTo(expected.left, 0.01),
          reason: '片段 $i 左缘与共用件几何一致（含片头让位）',
        );
        expect(
          rendered.width,
          closeTo(expected.width, 0.01),
          reason: '片段 $i 宽与共用件几何一致',
        );
        // 端点带贴块内侧、宽 = 既有常数。
        final startBand = tester.getRect(
          find.byKey(ValueKey('mirror_fragment_${i}_edge_start')),
        );
        final endBand = tester.getRect(
          find.byKey(ValueKey('mirror_fragment_${i}_edge_end')),
        );
        expect(startBand.width, closeTo(kLocalMirrorEdgeHitWidth, 0.01));
        expect(startBand.left, closeTo(rendered.left, 0.01));
        expect(endBand.right, closeTo(rendered.right, 0.01));
      }
    });

    testWidgets('窄块整段抑制端点带且不绘图标；宽块仍绘', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                // 视觉宽 50ms：即使在紧窗下也远窄于 40dp 阈值。
                LocalMirrorFragment(startMs: 8000, endMs: 8050),
                LocalMirrorFragment(startMs: 12000, endMs: 20000),
              ],
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('mirror_fragment_0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mirror_fragment_0_edge_start')),
        findsNothing,
        reason: '窄块端点带整段抑制',
      );
      expect(
        find.byKey(const ValueKey('mirror_fragment_0_edge_end')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mirror_fragment_0_icon')),
        findsNothing,
        reason: '窄块不绘反相图标（信息由填充/描边承担）',
      );
      expect(
        find.byKey(const ValueKey('mirror_fragment_1_edge_start')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mirror_fragment_1_icon')),
        findsOneWidget,
      );
    });

    testWidgets('阈值边界：块宽恰达 40dp 不算窄块，端点带仍在', (tester) async {
      // 40dp 阈值按**紧窗**的内容区宽换算为毫秒（ceil + 1ms 抹平毫秒粒度）。
      final narrowAxis = axisFor(window: tightWindow);
      final narrowMs =
          (kLocalMirrorNarrowWidth *
                  (tightWindow.end.inMilliseconds -
                      tightWindow.start.inMilliseconds) /
                  narrowAxis.contentWidth)
              .ceil();
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: [
                LocalMirrorFragment(startMs: 8000, endMs: 8000 + narrowMs + 1),
              ],
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('mirror_fragment_0'))).width,
        moreOrLessEquals(kLocalMirrorNarrowWidth, epsilon: 0.05),
        reason: '前置：块宽恰达阈值',
      );
      expect(
        find.byKey(const ValueKey('mirror_fragment_0_edge_start')),
        findsOneWidget,
        reason: 'width < 40 才是窄块：宽恰达 40dp 仍渲染端点带',
      );
    });

    testWidgets('总开关与选中态驱动块体视觉：琥珀/灰图标与白描边', (tester) async {
      const fragments = [
        LocalMirrorFragment(startMs: 8000, endMs: 18000),
        LocalMirrorFragment(startMs: 19000, endMs: 23000),
      ];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(fragments: fragments, selectedIndex: 1),
          ),
        ),
      );
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('mirror_fragment_0_icon')))
            .color,
        kLocalMirrorEnabledIconColor,
      );
      final selected = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('mirror_fragment_1')),
          matching: find.byType(Container),
        ),
      );
      expect(
        ((selected.decoration! as BoxDecoration).border! as Border).top.color,
        Colors.white,
        reason: '选中态由白描边承担（与开关无关）',
      );
      final plain = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('mirror_fragment_0')),
          matching: find.byType(Container),
        ),
      );
      expect(
        ((plain.decoration! as BoxDecoration).border! as Border).top.color,
        kLocalMirrorEnabledColor.withValues(alpha: 0.4),
      );

      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(fragments: fragments, masterSwitchOn: false),
          ),
        ),
      );
      expect(
        tester
            .widget<Icon>(find.byKey(const ValueKey('mirror_fragment_0_icon')))
            .color,
        Colors.white38,
        reason: '总开关关 = 全部片段按不生效视觉（灰）',
      );
    });

    testWidgets('角标锚点键按片段序上报：被包块体仍在、键仍逐位不变', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 18000),
                LocalMirrorFragment(startMs: 19000, endMs: 23000),
              ],
              guideAnchorKeys: (index) => index == 1 ? 'anchor_1' : null,
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mirror_fragment_1')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mirror_fragment_1_icon')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mirror_fragment_0')), findsOneWidget);
    });
  });

  group('退化输入', () {
    testWidgets('空片段表：无块体、无端点带，点按落穿带级空白仲裁', (tester) async {
      var blankTaps = 0;
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: buildInput(
              axis: axisFor(),
              onTapBlank: (_) => blankTaps++,
            ),
          ),
        ),
      );
      expect(find.byType(Container), findsNothing);
      await tester.tapAt(const Offset(200, 15));
      await tester.pumpAndSettle();
      expect(blankTaps, 1, reason: '空轨点按即空白：不吞指针');
    });

    testWidgets('窗口完全不含片段：块体安静不渲染', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: buildInput(
              axis: axisFor(
                window: windowOf(
                  const Duration(seconds: 40),
                  const Duration(seconds: 50),
                ),
              ),
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 12000),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mirror_fragment_0')), findsNothing);
      expect(
        find.byKey(const ValueKey('mirror_fragment_0_edge_start')),
        findsNothing,
      );
    });

    testWidgets('零宽片段（起点 = 终点）安静降级：不渲染且不抛错', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: buildInput(
              axis: axisFor(),
              fragments: const [LocalMirrorFragment(startMs: 8000, endMs: 8000)],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mirror_fragment_0')), findsNothing);
    });
  });

  group('行级点按与空白落穿', () {
    testWidgets('块体上点按 = 命中该片段（只报下标一次）', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 17000),
              ],
              onTapFragment: tapped.add,
            ),
          ),
        ),
      );
      await tester.tapAt(Offset(tightXOf(12000), rowHeight / 2));
      await tester.pumpAndSettle();
      expect(tapped, [0], reason: '行级解析命中唯一片段、只报一次');
    });

    testWidgets('小片段点附近即命中（最小命中宽 40dp 对称扩展，无死区）', (tester) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                // 视觉宽 50ms：远小于最小命中宽。
                LocalMirrorFragment(startMs: 8000, endMs: 8050),
              ],
              onTapFragment: tapped.add,
            ),
          ),
        ),
      );
      // 点在块体**外**（片段终点右侧约 250ms）仍在对称扩展命中域内。
      await tester.tapAt(Offset(tightXOf(8250), rowHeight / 2));
      await tester.pumpAndSettle();
      expect(tapped, [0], reason: '点附近即命中（内层算法仍归共用纯件）');
    });

    testWidgets('轨道空白点按：命中为空则落穿带级空白仲裁（全局位置原样）', (tester) async {
      final blank = <Offset>[];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 17000),
              ],
              onTapBlank: blank.add,
            ),
          ),
        ),
      );
      final position = Offset(tightXOf(22500), rowHeight / 2);
      await tester.tapAt(position);
      await tester.pumpAndSettle();
      expect(blank, hasLength(1), reason: '空白命中交回带级空白 tap 仲裁');
      expect(blank.single.dx, closeTo(position.dx, 0.01));
      expect(blank.single.dy, closeTo(position.dy, 0.01));
    });

    testWidgets('窗口不含点按时刻：命中为空同样落穿（退化不吞指针）', (tester) async {
      final blank = <Offset>[];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: buildInput(
              axis: axisFor(
                window: windowOf(
                  const Duration(seconds: 40),
                  const Duration(seconds: 50),
                ),
              ),
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 12000),
              ],
              onTapBlank: blank.add,
            ),
          ),
        ),
      );
      await tester.tapAt(Offset(xOf(8000), rowHeight / 2));
      await tester.pumpAndSettle();
      expect(blank, hasLength(1));
    });
  });

  group('拖动两族经拖动域句柄', () {
    /// 记录型模块会话按门禁目标就位（整体移族 / 端点拖族）。
    late Map<AnnotationGestureTarget, _RecordingSession> sessions;
    late List<String> hooks;
    late TrackBandDragFamilies families;
    late TrackBandDragSession domain;

    /// 组装点注入的模块会话工厂（唯一需要 provider 的一片）：按门禁目标取
    /// 记录型会话；抓取偏移、准入、换算与视觉钩子都归域自己装配。
    DurationDragSession beginSessionFor(TrackBandDragTarget target) =>
        sessions[target.gateTarget]!;

    /// 全局 x → 时间（与本域同一条几何口径，紧窗取景）：期望落点由它推出，
    /// 不写死数字。
    int msAt(double globalX) =>
        axisFor(window: tightWindow).xToTime(globalX).inMilliseconds;

    setUp(() {
      sessions = {
        AnnotationGestureTarget.localMirrorMove: _RecordingSession(8000),
        AnnotationGestureTarget.localMirrorEdgeDrag: _RecordingSession(8000),
      };
      hooks = [];
      families = TrackBandDragFamilies();
      domain = TrackBandDragSession(
        families: families,
        isPinchActive: () => false,
        isMixedBurstActive: () => false,
        loadGateActive: () => false,
        gestureStartRejected: (_) => false,
        promptOnReject: (_) {},
        bandWidth: () => bandWidth,
      );
    });

    testWidgets('整体移：抓取偏移 = 手指 − 片段起点，逐帧落点回写、起手/收口钩子各一次', (
      tester,
    ) async {
      final tapped = <int>[];
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 17000),
              ],
              dragSession: domain,
              dragFamilies: families,
              beginSession: beginSessionFor,
              onDragVisualsBegin: () => hooks.add('begin'),
              onDragFrame: (_) => hooks.add('frame'),
              onDragVisualsEnd: () => hooks.add('end'),
              onTapFragment: tapped.add,
            ),
          ),
        ),
      );

      // 抓在块体中部（12s 处）整体拖右移 3s：先越过拖动 slop 起手，再逐帧。
      final gesture = await tester.startGesture(
        Offset(tightXOf(12000), rowHeight / 2),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(Offset(tightXOf(15000) - tightXOf(12000) - 30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      final moved = sessions[AnnotationGestureTarget.localMirrorMove]!;
      expect(moved.movedTo, isNotEmpty, reason: '逐帧经本族句柄回写落点');
      // 相对平移（而非把片段首锚到手指）：请求 = 手指时间 − 抓取偏移，其中
      // 抓取偏移 = 起手那一刻的手指时间 − 片段起点。起手位置 = 按下点 +
      // 越过 slop 的那一次位移（本用例 30px）——期望值由同一份几何推出。
      final grabOffsetMs = msAt(tightXOf(12000) + 30) - 8000;
      final expectedLandingMs = msAt(tightXOf(15000)) - grabOffsetMs;
      expect(
        moved.movedTo.last,
        closeTo(expectedLandingMs, 30),
        reason: '整体移落点 = 手指时间 − 抓取偏移（相对平移）',
      );
      // 反向核对语义：落点 = 原起点 + 手指位移（而不是把片段首锚到手指上）。
      final pointerShiftMs = msAt(tightXOf(15000)) - msAt(tightXOf(12000) + 30);
      expect(
        moved.movedTo.last - 8000,
        closeTo(pointerShiftMs, 30),
        reason: '整体移 = 起点随手指位移平移（宽度与抓取点相对位置都不变）',
      );
      expect(
        moved.movedTo.last,
        lessThan(msAt(tightXOf(15000)) - 500),
        reason: '落点明显早于手指时间（抓取点在片段中部的证据）',
      );
      expect(hooks, contains('begin'), reason: '起手视觉钩子触发一次');
      expect(hooks, contains('end'), reason: '收口视觉钩子触发一次');
      expect(moved.endCount, 1, reason: '收口经句柄一次');
    });

    testWidgets('端点拖：端点带起手进端点族、块体族不被触发', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 17000),
              ],
              dragSession: domain,
              dragFamilies: families,
              beginSession: beginSessionFor,
            ),
          ),
        ),
      );

      final startEdgeX = tightXOf(8000) + kLocalMirrorEdgeHitWidth / 2;
      final gesture = await tester.startGesture(
        Offset(startEdgeX, rowHeight / 2),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      final edgeMoved =
          sessions[AnnotationGestureTarget.localMirrorEdgeDrag]!.movedTo;
      expect(edgeMoved, isNotEmpty, reason: '端点带起手进入端点拖族');
      // 端点拖的抓取偏移相对**被拖端点**（start = 片段起点 8000）：请求 =
      // 手指时间 − （起手手指时间 − 8000）。
      final edgeGrabMs = msAt(startEdgeX + 30) - 8000;
      expect(
        edgeMoved.last,
        closeTo(msAt(startEdgeX + 90) - edgeGrabMs, 30),
        reason: '端点拖落点 = 手指时间 − 相对被拖端点的抓取偏移',
      );
      expect(
        sessions[AnnotationGestureTarget.localMirrorMove]!.movedTo,
        isEmpty,
        reason: '块体族未被端点起手触发',
      );
      expect(
        sessions[AnnotationGestureTarget.localMirrorEdgeDrag]!.endCount,
        1,
        reason: '端点族收口一次',
      );
    });
  });

  group('片段表变化', () {
    testWidgets('输入片段表真变即重建：块体数量跟随', (tester) async {
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 18000),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mirror_fragment_1')), findsNothing);
      await tester.pumpWidget(
        mount(
          TrackMirrorRow(
            input: viewInput(
              fragments: const [
                LocalMirrorFragment(startMs: 8000, endMs: 18000),
                LocalMirrorFragment(startMs: 19000, endMs: 23000),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('mirror_fragment_1')), findsOneWidget);
    });
  });
}

/// 未接入拖动的直测域（默认输入用；本组不驱动任何族起手）。
TrackBandDragSession emptyDragDomain() => TrackBandDragSession(
  families: TrackBandDragFamilies(),
  isPinchActive: () => false,
  isMixedBurstActive: () => false,
  loadGateActive: () => false,
  gestureStartRejected: (_) => false,
  promptOnReject: (_) {},
  bandWidth: () => null,
);

/// 默认输入用的模块会话工厂（不参与断言，只为输入齐备）。
DurationDragSession _shippedBeginSession(TrackBandDragTarget target) =>
    _RecordingSession(0);
