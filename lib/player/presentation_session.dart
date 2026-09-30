/// 演出层会话：演出层里没有画面的那一半——浮层
/// 控制器、备注贴纸接线、选中/混区/全局缩放状态机、三指提示与播放页浮层
/// 手势钩子都自持在这里；[PresentationLayer] 只把同一份事实画出来，播放页只
/// 建会话、接手势域与画面构建。
///
/// 契约：构造收显式依赖（浮层控制器、读取闭包与回调），不碰容器句柄、不读
/// 构建上下文；跨帧状态（选中、混区闩锁、缩放会话）自持在本对象。
///
/// 依赖方向（单向）：本对象 → 浮层控制器、浮层值库与内容类接线；手势仲裁域
/// 与本对象单向（手势域调用本对象的钩子），本对象不反向 import 手势仲裁域，
/// 也不 import 播放页与中枢。短暂提示不再由本对象持有
/// ——触发只报身份，方向经注入点写读。
library;

import 'package:flutter/gestures.dart'
    show PointerDownEvent, ScaleStartDetails, ScaleUpdateDetails;
import 'package:flutter/widgets.dart' show Offset, Size;

import 'metronome_overlay.dart'
    show MetronomeOverlayController, OverlayMixedBurstTracker;
import 'note_sticker_overlay_registration.dart'
    show
        NoteStickerOverlayRegistration,
        PlaybackOverlayTapAction,
        resolvePlaybackOverlayTap;
import 'overlay.dart';

/// 演出层会话（层域的非 widget 部分）。
class PresentationSession {
  PresentationSession({
    required this.metronome,
    required this.isControlOpen,
    required this.metronomeVisible,
  }) : noteSticker = NoteStickerOverlayRegistration();

  /// 数拍跟练浮层控制器（选中态/位置/缩放；手势与画面共用同一份）。
  final MetronomeOverlayController metronome;

  /// 备注贴纸的窗内矩形与选中态（随会话失效）。
  final NoteStickerOverlayRegistration noteSticker;

  // 「进观看态」把手：收起控制层属演出
  // 层组装的浮层件，把手由画面层装配点（[EditorEntry.collapse] 的注入处）
  // 随装配交入本域；组合根与帮助域的请求注入点只经 [collapseControlLayer]
  // 间接驱动，不经本域持有的域实例。
  void Function()? _collapseControlLayer;

  /// 画面层装配点交入收起把手（幂等覆盖）。
  void attachCollapseControlLayer(void Function() collapse) =>
      _collapseControlLayer = collapse;

  /// 收起控制层（回观看态）；把手未交入（控制层尚未装配过）时为 no-op。
  void collapseControlLayer() => _collapseControlLayer?.call();

  /// 控制层是否展开（浮层手势的前置事实）。
  final bool Function() isControlOpen;

  /// 浮层内容是否可见（`beatOverlayContentVisibleProvider` 的读取闭包）。
  final bool Function() metronomeVisible;

  /// 全局双指缩放会话：浮层选中态下 ≥2 指起手的 scale 会话整场归选中浮层
  /// 缩放，未选中态不变。
  bool _globalPinch = false;

  /// 浮层混区 burst 跟踪：burst 内指针落选中态浮层上/外分账；落选中态浮层
  /// 上的 burst 同时抑制播放手势语义。
  final OverlayMixedBurstTracker _burstTracker = OverlayMixedBurstTracker();

  /// 视口/姿态变化时重注浮层视口与当前格（方向与尺寸是宿主读好的布局事实）。
  void applyViewport({
    required Size viewport,
    required bool landscape,
    required bool compare,
  }) {
    metronome.setViewport(viewport);
    setCell(landscape: landscape, compare: compare);
  }

  /// 对比态进出时切格（不动选中态与锁定态；生效位置与命中区随即由新格派生）。
  void setCell({required bool landscape, required bool compare}) {
    metronome.setCell(
      resolveOverlayPlacementCell(landscape: landscape, compare: compare),
    );
  }

  /// 几何存取接线：恢复流 → 控制器（`fireImmediately` 按现值就位），
  /// 控制器变更 → 回写存取面；双向均以相等性防环（装配一次即可，重复调用以
  /// 最后一次 [store] 为准）。
  void attachGeometry({required OverlayGeometryStore store}) {
    metronome.setStore(store);
    store.listen((next) {
      if (next != null && next != metronome.placements) {
        metronome.applyPlacements(next);
      }
    }, fireImmediately: true);
    metronome.addListener(() {
      if (store.read() != metronome.placements) {
        store.write(metronome.placements);
      }
    });
  }

  /// 内容转为为空即退出选中态（浮层不存在时不可保持选中）。
  void onContentVisibilityChanged(bool visible) {
    if (!visible) metronome.deselect();
  }

  /// 两类内容类的选中互斥唯一落点：按目标选中对同时收敛两侧（至多一个选中；
  /// 两侧 select/deselect 各自幂等）。无参调用 = 只清选中。
  void clearExclusiveSelections({
    bool noteSelected = false,
    bool metronomeSelected = false,
  }) {
    noteSelected ? noteSticker.select() : noteSticker.deselect();
    metronomeSelected ? metronome.select() : metronome.deselect();
  }

  /// 播放态浮层点选仲裁：命中取顶层、选中互斥；都未接手 → 返回 false，由
  /// 手势域走宿主默认（唤出编辑器入口）。
  bool onOverlayTap(Offset? down) {
    final action = resolvePlaybackOverlayTap(
      hitNoteSticker: down != null && noteSticker.hitTest(down),
      noteSelected: noteSticker.selected,
      metronomeVisible: metronomeVisible(),
      metronomeSelected: metronome.selected,
      hitMetronome: down != null && metronome.hitTest(down),
    );
    switch (action) {
      case PlaybackOverlayTapAction.selectNoteSticker:
        clearExclusiveSelections(noteSelected: true);
        return true;
      case PlaybackOverlayTapAction.selectMetronome:
        clearExclusiveSelections(metronomeSelected: true);
        return true;
      case PlaybackOverlayTapAction.deselectOnly:
        clearExclusiveSelections();
        return true;
      case PlaybackOverlayTapAction.keepSelected:
        return true;
      case PlaybackOverlayTapAction.hostDefault:
        return false;
    }
  }

  /// 双击是否落在**选中态浮层**上（选中态浮层只有选中与几何手势语义，
  /// 双击暂停播放不作用于它）；输入与 [onOverlayTap] 同一份——note 分支不查
  /// 可见性、metronome 分支查，两处不对称是既定点选仲裁语义。
  bool consumesOverlayDoubleTap(Offset? down) {
    if (down == null) return false;
    return (noteSticker.selected && noteSticker.hitTest(down)) ||
        (metronome.selected && metronomeVisible() && metronome.hitTest(down));
  }

  /// 手势会话起手：数拍浮层进入单指平移预备，并按选中态/锁定态解析全局
  /// 双指缩放会话。
  void onGestureSessionStarted(ScaleStartDetails details) {
    metronome.beginMove();
    _globalPinch =
        !isControlOpen() &&
        details.pointerCount >= 2 &&
        metronome.selected &&
        !metronome.locked &&
        metronomeVisible();
    if (_globalPinch) metronome.beginPinch();
  }

  /// 全局双指缩放帧：会话整场被收编时返回 true，手势域不再进入播放语义分支。
  bool tryConsumeOverlayPinchFrame(ScaleUpdateDetails details) {
    if (!_globalPinch) return false;
    if (details.pointerCount >= 2) {
      metronome.updatePinch(
        scale: details.scale,
        horizontalScale: details.horizontalScale,
      );
    }
    return true;
  }

  /// 选中态浮层单指平移帧：未锁定时落浮层上的单指即拖动平移、不落播放语义；
  /// 返回 true 表示本帧已被浮层消费。
  bool tryConsumeOverlayPanFrame(ScaleUpdateDetails details) {
    if (!_burstTracker.burstTouchesSelectedOverlay || metronome.locked) {
      return false;
    }
    if (details.pointerCount == 1) {
      metronome.moveBy(details.focalPointDelta);
    }
    return true;
  }

  /// 手势会话收尾：结束数拍浮层平移与全局双指缩放会话。
  void onGestureSessionEnded() {
    metronome.endMove();
    if (_globalPinch) {
      _globalPinch = false;
      metronome.endPinch();
    }
  }

  /// 原始指针按下：浮层混区簿记与混区闩锁回写（选中态缩放是明确模态，不进
  /// 混区锁）。
  void onRawPointerDown(PointerDownEvent event) {
    _burstTracker.pointerDown(
      event.pointer,
      onOverlay:
          !isControlOpen() &&
          metronomeVisible() &&
          metronome.selected &&
          metronome.hitTest(event.position),
    );
    if (!metronome.selected) {
      metronome.setBurstSuppressed(_burstTracker.burstEverMixed);
    }
  }

  /// 原始指针抬起/取消：浮层混区簿记摘除 + 闩锁状态回写；浮层选中态不回写。
  void onRawPointerUp(int pointer) {
    _burstTracker.pointerUp(pointer);
    if (!metronome.selected) {
      metronome.setBurstSuppressed(_burstTracker.burstEverMixed);
    }
  }

  void dispose() {
    noteSticker.dispose();
    metronome.dispose();
  }
}
