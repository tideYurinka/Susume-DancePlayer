import 'package:dance_learning_app/player/metronome_overlay.dart'
    show MetronomeOverlayController;
import 'package:dance_learning_app/player/overlay.dart'
    show OverlayGeometryStore, OverlayPlacementCell, OverlayPlacements;
import 'package:dance_learning_app/player/presentation_session.dart'
    show PresentationSession;
import 'package:flutter/gestures.dart'
    show ScaleStartDetails, ScaleUpdateDetails;
import 'package:flutter/widgets.dart' show Size;
import 'package:flutter_test/flutter_test.dart';

/// 演出层会话模块面测试：不 pump widget、不注
/// 容器，直接驱动浮层选中/提示/缩放会话状态机与几何存取接线，断言它交出的
/// 外部可观察事实。
void main() {
  late MetronomeOverlayController metronome;
  late PresentationSession surface;
  late bool controlOpen;
  late bool metronomeVisible;

  setUp(() {
    metronome = MetronomeOverlayController();
    controlOpen = false;
    metronomeVisible = true;
    surface = PresentationSession(
      metronome: metronome,
      isControlOpen: () => controlOpen,
      metronomeVisible: () => metronomeVisible,
    );
  });

  tearDown(() {
    surface.dispose();
  });

  ScaleStartDetails start({int pointerCount = 1}) => ScaleStartDetails(
    focalPoint: Offset.zero,
    localFocalPoint: Offset.zero,
    pointerCount: pointerCount,
  );

  ScaleUpdateDetails update({int pointerCount = 1}) => ScaleUpdateDetails(
    focalPoint: const Offset(10, 10),
    localFocalPoint: const Offset(10, 10),
    pointerCount: pointerCount,
    scale: 1.5,
    horizontalScale: 1.2,
    focalPointDelta: const Offset(1, 0),
  );

  test('选中互斥唯一落点：选一侧即清另一侧，无参调用只清选中', () {
    metronome.select();
    surface.clearExclusiveSelections(noteSelected: true);
    expect(metronome.selected, isFalse, reason: '选贴纸即交出浮层选中');
    expect(
      surface.noteSticker.selected,
      isFalse,
      reason: '贴纸未窗内（无矩形）时选中是 no-op',
    );

    surface.clearExclusiveSelections(metronomeSelected: true);
    expect(metronome.selected, isTrue);

    surface.clearExclusiveSelections();
    expect(metronome.selected, isFalse);
  });

  test('内容转空即退出选中态', () {
    metronome.select();
    expect(metronome.selected, isTrue);
    surface.onContentVisibilityChanged(false);
    expect(metronome.selected, isFalse);
  });

  test('浮层点选仲裁：无接手交回宿主默认，选中态点空白只清选中', () {
    expect(surface.onOverlayTap(null), isFalse, reason: '无浮层接手 → hostDefault');

    metronome.select();
    expect(surface.onOverlayTap(null), isTrue, reason: '选中态点空白 → deselectOnly');
    expect(metronome.selected, isFalse);
  });

  test('双击浮层判定：点缺失或两侧未选中不消费；节拍浮层查可见性', () {
    expect(surface.consumesOverlayDoubleTap(null), isFalse);
    expect(surface.consumesOverlayDoubleTap(Offset.zero), isFalse);

    surface.applyViewport(
      viewport: const Size(800, 600),
      landscape: false,
      compare: false,
    );
    metronome.select();
    final center = metronome.hitRect().center;
    expect(
      surface.consumesOverlayDoubleTap(center),
      isTrue,
      reason: '选中且可见、点落在浮层上 → 消费双击',
    );
    metronomeVisible = false;
    expect(
      surface.consumesOverlayDoubleTap(center),
      isFalse,
      reason: '浮层内容不可见 → 不消费',
    );
  });

  test('全局双指缩放会话：选中态 ≥2 指起手整场被收编，收尾后恢复', () {
    metronome.select();
    surface.onGestureSessionStarted(start(pointerCount: 2));
    expect(
      surface.tryConsumeOverlayPinchFrame(update(pointerCount: 2)),
      isTrue,
      reason: '选中态双指起手 → 本帧被浮层缩放消费，不落播放语义',
    );

    surface.onGestureSessionEnded();
    expect(
      surface.tryConsumeOverlayPinchFrame(update(pointerCount: 2)),
      isFalse,
      reason: '会话收尾后不再消费',
    );
  });

  test('控制层展开或浮层未选中时不起全局缩放会话', () {
    controlOpen = true;
    metronome.select();
    surface.onGestureSessionStarted(start(pointerCount: 2));
    expect(surface.tryConsumeOverlayPinchFrame(update(pointerCount: 2)), isFalse);

    controlOpen = false;
    metronomeVisible = false;
    metronome.select();
    surface.onGestureSessionStarted(start(pointerCount: 2));
    expect(surface.tryConsumeOverlayPinchFrame(update(pointerCount: 2)), isFalse);
  });

  group('视口与切格', () {
    test('applyViewport：注入视口并切格', () {
      surface.applyViewport(
        viewport: const Size(800, 600),
        landscape: true,
        compare: false,
      );

      expect(metronome.cell, OverlayPlacementCell.landscapeNormal);
      // 生效位落在钳制框内（默认位贴左、纵向视口高 12%）。
      expect(metronome.effectiveOffset.dy, 600 * 0.12);
    });
  });

  group('几何存取接线', () {
    test('恢复流 → 控制器：装配即按现值就位（fireImmediately）', () {
      const restored = OverlayPlacements(
        offsets: {OverlayPlacementCell.landscapeNormal: Offset(24, 96)},
      );
      final store = _FakeGeometryStore(value: restored);

      surface.attachGeometry(store: store);

      expect(metronome.placements, restored);
    });

    test('控制器变更 → 回写：用户意图写回存取面', () {
      final store = _FakeGeometryStore(
        value: const OverlayPlacements(
          offsets: {OverlayPlacementCell.portraitNormal: Offset(12, 34)},
        ),
      );
      surface.attachGeometry(store: store);
      expect(metronome.placements, store.value);

      metronome.resetPlacement();

      expect(store.value, const OverlayPlacements(), reason: '重置 = 清除该格自定义位');
      expect(store.writes, contains(const OverlayPlacements()));
    });

    test('恢复流后续推送 → 控制器（装载落定后的恢复）', () {
      final store = _FakeGeometryStore();
      surface.attachGeometry(store: store);
      const incoming = OverlayPlacements(pendulumScale: 1.5);
      expect(metronome.placements, const OverlayPlacements());

      store.emit(incoming);

      expect(metronome.placements, incoming);
    });

    test('相等性防环：无变化的通知不产生写入', () {
      // 存取面现值与控制器一致（生产接线里「四格全未自定义」在存取面上即
      // null；此处直接用同值，断言通知不产生回写）。
      final store = _FakeGeometryStore(value: const OverlayPlacements());
      surface.attachGeometry(store: store);
      final writesBefore = store.writes.length;

      metronome.select();
      metronome.deselect();

      expect(store.writes.length, writesBefore);
    });
  });
}

/// 测试用几何存取面：内存值 + 记录写入 + 可手动推送恢复流。
class _FakeGeometryStore implements OverlayGeometryStore {
  _FakeGeometryStore({this.value});

  OverlayPlacements? value;
  final List<OverlayPlacements?> writes = [];
  void Function(OverlayPlacements? value)? _onChanged;

  @override
  OverlayPlacements? read() => value;

  @override
  void write(OverlayPlacements? value) {
    this.value = value;
    writes.add(value);
  }

  @override
  void listen(
    void Function(OverlayPlacements? value) onChanged, {
    required bool fireImmediately,
  }) {
    _onChanged = onChanged;
    if (fireImmediately) onChanged(value);
  }

  void emit(OverlayPlacements? next) {
    value = next;
    _onChanged?.call(next);
  }
}
