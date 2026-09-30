import 'package:flutter/widgets.dart';

/// 根 Navigator 的句柄：帮助渲染件在**根 Navigator 之上**渲染时（一次性图文
/// 卡由演出层直接铺在根 Navigator 上方，不在它里面）查不到祖先 Navigator，
/// 只能从这枚句柄向下取那棵根 Navigator 的状态来推路由。演出层把它套在根
/// Navigator 外，于是卡里的「打开完整正文页」与「打开大图查看器」走同一条
/// 推入通路。
final GlobalKey<NavigatorState> helpRootNavigatorKey =
    GlobalKey<NavigatorState>();

/// 根 Navigator 的状态；句柄不在树上时 null。
///
/// 根 Navigator 外面还包着一层 FocusScope（`WidgetsApp` 所为），不能只查直接
/// 子元素：向下找到那棵根 Navigator 为止。
NavigatorState? helpRootNavigatorState() {
  NavigatorState? state;
  void visit(Element element) {
    if (state != null) return;
    if (element is StatefulElement && element.state is NavigatorState) {
      state = element.state as NavigatorState;
      return;
    }
    element.visitChildElements(visit);
  }

  helpRootNavigatorKey.currentContext?.visitChildElements(visit);
  return state;
}
