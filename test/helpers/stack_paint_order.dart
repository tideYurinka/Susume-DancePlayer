/// 共享 Stack 直系子级绘制序断言（从
/// `test/player/track_band_test.dart`「预览线 z 序置顶」的写法提取）：
/// 找两个目标的最近公共祖先 [Stack]，比较各自落在哪一直系子树，
/// 后入者绘制在上。不断言私有 widget 类型。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [candidate] 是否为 [target] 的祖先。
bool isAncestorOf(Element candidate, Element target) {
  var found = false;
  target.visitAncestorElements((ancestor) {
    if (ancestor == candidate) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

/// [target] 在 [stack] 直系子元素中的绘制序下标（后 = 上层）。
int paintIndexOf(Element stack, Element target) {
  final children = <Element>[];
  stack.visitChildElements(children.add);
  for (var i = 0; i < children.length; i++) {
    if (children[i] == target || isAncestorOf(children[i], target)) {
      return i;
    }
  }
  fail('目标不在 Stack 直系子树内');
}

/// [a] 与 [b] 的最近公共祖先 [Stack]（绘制序 = 子序，后入在上）。
Element sharedStackOf(WidgetTester tester, Finder a, Finder b) {
  Element? shared;
  tester.element(a).visitAncestorElements((ancestor) {
    if (ancestor.widget is Stack && isAncestorOf(ancestor, tester.element(b))) {
      shared = ancestor;
      return false;
    }
    return true;
  });
  expect(shared, isNotNull, reason: '两目标应共享同一 Stack');
  return shared!;
}
