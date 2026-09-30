/// 备注贴纸内容类接线：窗内像素矩形、选中态与出窗中断。
///
/// - **窗内显隐**：播放头 ∈ 时间窗即显示、窗外出即消失（`noteStickerAt`），
///   与播放 / 暂停无关；宿主按播放头把「窗内贴纸的像素矩形 / null」经
///   [NoteStickerOverlayRegistration.setRect] 同步进来，命中判定由该矩形
///   现算。
/// - **选中态**：至多一选中由宿主 `clearExclusiveSelections` 与
///   [resolvePlaybackOverlayTap] 收敛；播放头出窗即清选中。
/// - **几何归属**：参考系 = **视频内容矩形归一化**、存取 = **公开标记文件**
///   （随 markers `notes` 段存、随公开分享还原）——几何命令归标注编辑模块
///   （经公开标记文件持久化），与节拍动画浮层的「播放页视口 + 本地私密」
///   刻意不同。
library;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/widgets.dart' show Offset, Rect;

/// 播放态单指点选的仲裁结论：两类内容类（备注贴纸 + 节拍动画
/// 浮层）跨类互斥、至多一选中；`deselectOnly` = 仅清选中、**不唤出控制
/// 层**；`hostDefault` = 交回宿主默认手势（唤出控制层）。
enum PlaybackOverlayTapAction {
  /// 选中备注贴纸（并交出节拍浮层的选中——命中取顶层）。
  selectNoteSticker,

  /// 选中节拍动画浮层（并交出备注贴纸的选中）。
  selectMetronome,

  /// 仅清选中（清的是当前选中的那一个），不唤出控制层。
  deselectOnly,

  /// 选中态点在其自身矩形上：保持选中，不唤出控制层。
  keepSelected,

  /// 无浮层接手：交回宿主默认手势（唤出控制层）。
  hostDefault,
}

/// 播放态单指点选仲裁（纯函数）：命中取顶层（备注贴纸浮层叠于
/// 节拍动画浮层之上，命中贴纸即贴纸优先）；两类选中互斥；选中态点空白
/// 只清选中、不唤出控制层（与节拍动画浮层同款）。
PlaybackOverlayTapAction resolvePlaybackOverlayTap({
  required bool hitNoteSticker,
  required bool noteSelected,
  required bool metronomeVisible,
  required bool metronomeSelected,
  required bool hitMetronome,
}) {
  if (hitNoteSticker) {
    return noteSelected
        ? PlaybackOverlayTapAction.keepSelected
        : PlaybackOverlayTapAction.selectNoteSticker;
  }
  if (metronomeVisible) {
    if (metronomeSelected) {
      return hitMetronome
          ? PlaybackOverlayTapAction.keepSelected
          : PlaybackOverlayTapAction.deselectOnly;
    }
    if (hitMetronome) {
      return PlaybackOverlayTapAction.selectMetronome;
    }
  }
  if (noteSelected) {
    return PlaybackOverlayTapAction.deselectOnly;
  }
  return PlaybackOverlayTapAction.hostDefault;
}

/// 备注贴纸的窗内矩形与选中态（宿主按播放头驱动矩形；选中随矩形现算）。
///
/// 选中态只对窗内（[setRect] 传过非空矩形）成立；**播放头离开时间窗即清
/// 选中**，且在「窗内 → 窗外」边沿经 [onWindowExit] 中断进行中的几何会话
/// 一次（幂等，净变化由会话照常提交、不半写）。
class NoteStickerOverlayRegistration extends ChangeNotifier {
  Rect? _rect;
  bool _selected = false;

  /// 出窗回调：手势进行中出窗则中断会话（既有拖动会话结束路径；
  /// 接线贴纸几何会话）。只在「窗内 → 窗外」边沿触发一次，幂等。
  void Function()? onWindowExit;

  /// 当前是否处于选中态。
  bool get selected => _selected;

  /// 命中查询（宿主点选仲裁入口）：窗内矩形现算。
  bool hitTest(Offset globalPosition) =>
      _rect?.contains(globalPosition) ?? false;

  /// 点选进选中态：窗内（有矩形）才成立；重复选中幂等且不多发通知。
  void select() {
    if (_selected || _rect == null) return;
    _selected = true;
    notifyListeners();
  }

  /// 退出选中态；未选中时幂等 no-op、不多发通知。
  void deselect() {
    if (!_selected) return;
    _selected = false;
    notifyListeners();
  }

  /// 编辑态：窗内贴纸只读常显、**完全不参与命中**——清矩形与选中
  /// （无命中面、无选中框残留）。时间窗未变，不走 [onWindowExit] 的出窗
  /// 中断语义；重复进入幂等、不多发通知。
  void enterEditingReadOnly() {
    if (_rect == null && !_selected) return;
    _rect = null;
    _selected = false;
    notifyListeners();
  }

  /// 同步窗内显隐：[rect] 非空 = 播放头在某条时间窗内，更新像素矩形；
  /// null = 窗外，清矩形与选中，并在「窗内 → 窗外」边沿经 [onWindowExit]
  /// 中断进行中的会话一次（显隐与播放状态无关，由宿主按播放头驱动）。
  void setRect(Rect? rect) {
    if (rect == null) {
      if (_rect == null) return;
      _rect = null;
      _selected = false;
      onWindowExit?.call();
      notifyListeners();
      return;
    }
    _rect = rect;
  }
}
