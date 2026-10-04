/// 取景域宿主会话。
///
/// 取景调节态内那段**进入（起手 + 按下点分派）→ 跟手（建框橡皮筋 / 整体平移
/// / 八个取景控制点调形）→ 退出（按实际看到的框定格）**的编排由本模块自持：
/// 落点是否在画面内、屏幕坐标到源画面归一化的换算、硬钳与最小边、点画面外
/// 退出都在这里；播放页只做**取值接线**：把构建上下文里的事实读成一个
/// [FramingViewport]、把会话态读写交给显式回调。取景只有**源画面**一份，取值
/// 全走取景选区（`framing_selection.dart` 纯件）——三条拖动路径共用同一条
/// 「四边硬钳在整帧内 + 最小边」算式。
///
/// 依赖一律显式（读取闭包 + 回调），不收容器句柄、不碰构建上下文：
///
/// - [readViewport]：视口尺寸、姿态、源画面宽高比与所在路径（单画面 /
///   对比分屏，随值携带贴底骨架与系统栏内缩）；
/// - [isActive]：取景调节态谓词（对比取景与单画面取景两个模式值的派生
///   读面）；
/// - [readCommitted]：会话已提交取值（源画面取景选区）读面；
/// - [applySource]：把取景选区写到会话态（写面；null = 清除）；
/// - [exitFraming]：点画面外退出（模式值写面；分派归宿主——对比路径回
///   对比-控制层、单画面路径回编辑态）。
///
/// 依赖方向单向：本模块只 import 取景纯域（`annotation/framing_selection.dart`）、
/// 跨域可读的命中盒下限（`core/hit_target.dart`）与几何纯件
/// （`compare_framing_view.dart`、`framing_stage.dart`）；不 import 中枢，也不
/// 出现 `BuildContext`。
library;

import 'dart:ui' show Offset, Rect, Size;

import '../annotation/framing_selection.dart'
    show
        FramingSelection,
        FramingSelectionGestureSession,
        FramingSelectionHandle,
        framingSelectionFromDiagonal,
        framingSelectionHandleAt,
        framingSelectionMinEdge,
        framingSelectionRectOnPicture,
        framingSelectionResized,
        framingSelectionTranslated,
        isFramingSelectionLargeEnough,
        resolveFramingSelectionGestureSession;
import '../core/hit_target.dart' show kHitTargetMinSize;
import 'framing_session_state.dart' show FramingState;
import 'compare_framing_view.dart' show compareFramingPictureRect;
import 'editor_skeleton.dart' show EditorSkeleton;
import 'framing_stage.dart' show singlePicturePictureRectOnScreen;

/// 取景几何事实的一次取值（构建上下文读面的产物）：视口尺寸、姿态、源
/// 画面宽高比与所在路径。播放页按当前 `MediaQuery` 读好传入——本模块不读
/// 构建上下文。
class FramingViewport {
  const FramingViewport({
    required this.size,
    required this.landscape,
    required this.sourceAspectRatio,
    this.singlePicture = false,
    this.editingSkeleton,
    this.systemTopInset = 0,
  });

  /// 播放页视口逻辑尺寸（`MediaQuery.sizeOf`）。
  final Size size;

  /// 姿态（`MediaQuery.orientationOf`）：横屏左右等分半区、竖屏上下等分。
  final bool landscape;

  /// 源画面宽高比（引擎事实）；null = 未知，按画面即容器兜底。
  final double? sourceAspectRatio;

  /// 是否单画面路径：true = 单画面取景（整帧 contain / 竖屏编辑态贴底画面
  /// 带）；false = 对比态分屏路径（源侧半区 contain）。
  final bool singlePicture;

  /// 单画面编辑面的骨架（竖屏贴底分支的几何来源；单画面取景态恒传——
  /// 控制层收起不代表骨架缺席）；对比路径不消费。
  final EditorSkeleton? editingSkeleton;

  /// 系统栏顶内缩（贴底分支的画面区屏幕原点换算项）。
  final double systemTopInset;
}

/// 一次拖动 burst 的作用路径（按下点分派，优先级：控制点 > 框内 > 框外）。
/// 三态各自携带它需要的事实——**建框**无基准（跟手橡皮筋）、**整体平移**与
/// **调形**按会话给出的起手基准求值，调形再带所抓的控制点。
sealed class _FramingDrag {
  const _FramingDrag();
}

/// 建框（未调过或框外起手）：起手点与当帧点围成对角橡皮筋。
class _CreateDrag extends _FramingDrag {
  const _CreateDrag();
}

/// 整体平移（框内起手）：四边同加位移，形状不变。
class _TranslateDrag extends _FramingDrag {
  const _TranslateDrag();
}

/// 调形（八个**取景控制点**之一）：四角调两轴、四边中点只调那一条边。
class _ResizeDrag extends _FramingDrag {
  const _ResizeDrag(this.handle);

  final FramingSelectionHandle handle;
}

/// 取景手势会话的宿主：持有一次 burst 的会话值，编排进入/建框/收尾三段。
///
/// 会话值的**规则**归纯件（[resolveFramingSelectionGestureSession]——起手与
/// 重设基准），本类负责落点判定、按下点分派、坐标换算与写面调用；播放页只把
/// 当帧手势数据接进来，不持有会话字段、不分支三段时序。
class FramingSessionHost {
  FramingSessionHost({
    required this.readViewport,
    required this.isActive,
    required this.readCommitted,
    required this.applySource,
    required this.exitFraming,
  });

  /// 取当前视口事实（构建上下文读面）。
  final FramingViewport Function() readViewport;

  /// 取景调节态谓词（模式值 = 单画面取景 `framing` 或对比取景 `compareFraming`）。
  final bool Function() isActive;

  /// 读会话已提交取值（源画面取景选区）。
  final FramingState Function() readCommitted;

  /// 把取景选区写到会话态（手势提交的唯一写面；null = 清除）。
  final void Function(FramingSelection? selection) applySource;

  /// 点画面外退出（模式值写面）。
  final void Function() exitFraming;

  /// burst 的取景选区手势会话。
  FramingSelectionGestureSession? _session;

  /// 本 burst 起手前的已提交取值（松手不成框时回退到它；null = 原未调过）。
  FramingSelection? _initialBase;

  /// 本 burst 是否已被判定为「不写取值」（黑边起手、系统让路、多指）。
  bool _suppressed = false;

  /// 本 burst 是否写过取值（松手判定「是否成框」只在写过时才有意义）。
  bool _writing = false;

  /// 本 burst 的作用路径（按下点分派一次、整场不变）。
  _FramingDrag _drag = const _CreateDrag();

  /// 是否有进行中的取景会话（按会话整场接管手势的判据）。
  bool get hasSession => _session != null;

  /// 手势开始（进入）：取基准 + 按下点分派。会话已开即整场由取景接管（识别
  /// 器重启的 begin，同一次 burst——重设基准、不重分派）。[panYielded] = 起手
  /// 落在系统手势让路区且起手为单指：本 burst 不写取值（沿用既有让路机制）。
  /// 落点在画面外的黑边起手、或起手即多指，同样只吞帧不写值。
  void begin({
    required Offset focal,
    required int pointerCount,
    bool panYielded = false,
  }) {
    final restarted = _session != null;
    final pictureRect = _pictureRect();
    final mapped = pictureRect == null || pictureRect.isEmpty
        ? null
        : pictureRect;
    final suppressed =
        pointerCount != 1 ||
        panYielded ||
        mapped == null ||
        !_containsInclusive(mapped, focal);
    if (!restarted) {
      _initialBase = readCommitted().source;
      _writing = false;
      _suppressed = suppressed;
      _dispatch(focal: focal, pictureRect: mapped);
    } else if (suppressed) {
      _suppressed = true;
    }
    _session = resolveFramingSelectionGestureSession(
      current: _session,
      committed: readCommitted().source,
      focalX: focal.dx,
      focalY: focal.dy,
      pointerCount: pointerCount,
      recognizerRestarted: restarted,
    );
  }

  /// 手势更新（跟手）：返回 true = 本帧由取景会话接手（**不回落播放语义**）。
  ///
  /// 三条拖动路径共用同一条「四边硬钳在整帧内 + 最小边」算式：建框造对角橡
  /// 皮筋（取交集、是否成框由松手判），整体平移四边同加位移但作为整体贴边即
  /// 停（尺寸不变），控制点只动被拖的那条边（贴到边即停、往回拖即随手指回
  /// 缩）。
  ///
  /// 取景态在 burst 中途退出时只吞掉余帧、不再改建框，也不把未起的手势会话
  /// 回落给 seek/音量/亮度。
  bool adjust({required Offset focal, required int pointerCount}) {
    final session = _session;
    if (session == null) return false;
    if (!isActive()) return true;
    if (pointerCount != session.pointerCount) {
      _session = resolveFramingSelectionGestureSession(
        current: session,
        committed: readCommitted().source,
        focalX: focal.dx,
        focalY: focal.dy,
        pointerCount: pointerCount,
        recognizerRestarted: false,
      );
      if (pointerCount != 1) _suppressed = true;
      return true;
    }
    // 多指不产生缩放/旋转等新语义；黑边起手与让路会话不写取值。
    if (pointerCount != 1 || _suppressed) return true;
    final pictureRect = _pictureRect();
    if (pictureRect == null || pictureRect.isEmpty) return true;
    final base = session.base;
    final dx = (focal.dx - session.focalX) / pictureRect.width;
    final dy = (focal.dy - session.focalY) / pictureRect.height;
    // 三条路径各自走纯件对应入口，共用那唯一一条钳制算式。
    final frame = switch (_drag) {
      _CreateDrag() => framingSelectionFromDiagonal(
        x0: (session.focalX - pictureRect.left) / pictureRect.width,
        y0: (session.focalY - pictureRect.top) / pictureRect.height,
        x1: (focal.dx - pictureRect.left) / pictureRect.width,
        y1: (focal.dy - pictureRect.top) / pictureRect.height,
      ),
      _TranslateDrag() =>
        base == null
            ? null
            : framingSelectionTranslated(
                base: base,
                dx: dx,
                dy: dy,
                minEdge: _minEdge(pictureRect),
              ),
      _ResizeDrag(:final handle) =>
        base == null
            ? null
            : framingSelectionResized(
                base: base,
                handle: handle,
                dx: dx,
                dy: dy,
                minEdge: _minEdge(pictureRect),
              ),
    };
    if (frame == null) return true;
    applySource(frame);
    _writing = true;
    return true;
  }

  /// 手势收尾（退出）：按实际看到的框定格。建框松手时取景选区不足最小边即
  /// **不成框**——回退到起手前的取值（可能是未调过），免得一个中途退出或
  /// 误触留下退化框。整体平移与调形经同一算式已恒不小于最小边，无此判定。
  /// 下个 burst 重新取基准。
  void end() {
    final session = _session;
    _session = null;
    if (session == null) return;
    if (!_writing) return;
    _writing = false;
    if (_drag is! _CreateDrag) return;
    final pictureRect = _pictureRect();
    final committed = readCommitted().source;
    if (pictureRect == null || committed == null) return;
    if (!isFramingSelectionLargeEnough(
      selection: committed,
      minEdge: _minEdge(pictureRect),
    )) {
      applySource(_initialBase);
    }
  }

  /// 取景态内的单击（退出三路之三）：落点在本路径的画面矩形之外（黑边）
  /// 即退出——对比路径回对比-控制层、单画面路径回编辑态（写面归宿主），
  /// 画面内不唤出控制层。画面宽高比未知（画面即容器）时无「画面外」可达
  /// ——退出走完成/返回两路。
  void handleTap(Offset? down) {
    if (down == null) return;
    final pictureRect = _pictureRect();
    if (pictureRect == null) return;
    if (!_containsInclusive(pictureRect, down)) exitFraming();
  }

  /// 按下点分派（整场不变）：优先**取景控制点**（命中盒逐轴自适应、上限
  /// 48dp，四角优先于四边中点），其次**框内整体平移**，最后**框外新建
  /// （替换）**。未调过或无可映射画面矩形时一律建框。
  void _dispatch({required Offset focal, required Rect? pictureRect}) {
    final selection = readCommitted().source;
    if (selection == null || pictureRect == null) {
      _drag = const _CreateDrag();
      return;
    }
    final handle = framingSelectionHandleAt(
      selection: selection,
      pictureLeft: pictureRect.left,
      pictureTop: pictureRect.top,
      pictureWidth: pictureRect.width,
      pictureHeight: pictureRect.height,
      x: focal.dx,
      y: focal.dy,
      maxHitSize: kHitTargetMinSize,
    );
    if (handle != null) {
      _drag = _ResizeDrag(handle);
      return;
    }
    _drag = _containsInclusive(_selectionRect(selection, pictureRect), focal)
        ? const _TranslateDrag()
        : const _CreateDrag();
  }

  /// 选区在屏幕上的矩形（画面矩形内按四边线性映射）。
  Rect _selectionRect(FramingSelection selection, Rect pictureRect) {
    final rect = framingSelectionRectOnPicture(
      selection: selection,
      pictureLeft: pictureRect.left,
      pictureTop: pictureRect.top,
      pictureWidth: pictureRect.width,
      pictureHeight: pictureRect.height,
    );
    return Rect.fromLTRB(rect.left, rect.top, rect.right, rect.bottom);
  }

  /// 落点是否落在矩形内（**含**右/下边界）。画面矩形与选区矩形共用这一处判定：
  /// 贴到画面边的框，其右/下控制点中心正落在边界上，须仍抓得到；边线上的按下
  /// 也算框内（边线本体不是把手）。黑边（明确在画面矩形之外）起手仍不动作。
  bool _containsInclusive(Rect rect, Offset focal) =>
      focal.dx >= rect.left &&
      focal.dx <= rect.right &&
      focal.dy >= rect.top &&
      focal.dy <= rect.bottom;

  /// 本路径**取景态显示**的画面矩形（屏幕坐标）：屏幕落点 → 源画面归一化
  /// 的分母，也是「点画面外」与「黑边起手」的判定矩形。画面宽高比未知（画面
  /// 即容器、无变换）时返回 `null`——没有可映射的画面矩形，本场不建框。
  Rect? _pictureRect() {
    final viewport = readViewport();
    if (viewport.sourceAspectRatio == null ||
        viewport.sourceAspectRatio! <= 0) {
      return null;
    }
    if (viewport.singlePicture) {
      return singlePicturePictureRectOnScreen(
        screen: viewport.size,
        systemTopInset: viewport.systemTopInset,
        skeleton: viewport.editingSkeleton,
        aspectRatio: viewport.sourceAspectRatio,
      );
    }
    return compareFramingPictureRect(
      screen: viewport.size,
      landscape: viewport.landscape,
      aspectRatio: viewport.sourceAspectRatio,
    );
  }

  /// 该路径的最小边（屏幕 24dp 在画面坐标系里的等效量）。
  double _minEdge(Rect pictureRect) => framingSelectionMinEdge(
    pictureWidth: pictureRect.width,
    pictureHeight: pictureRect.height,
  );
}
