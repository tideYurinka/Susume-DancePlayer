import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 具名视口档：每档以 (物理尺寸, 像素比) 二元组声明，逻辑尺寸由它折出。
/// `compact` 是唯一带量测出处的档（1264×2736 @3.5 = 361.1×781.7dp），
/// 其余四档为合成档，像素比取 1.0；`tablet`（820×1180dp）是唯一落常规档的
/// 档，供常规档用例证明「平板上一切照旧」。
enum ViewportTier {
  small._(Size(320, 640), 1.0),
  compact._(Size(1264, 2736), 3.5),
  regular._(Size(393, 852), 1.0),
  large._(Size(480, 1000), 1.0),
  tablet._(Size(820, 1180), 1.0);

  const ViewportTier._(this.physicalSize, this.devicePixelRatio);

  final Size physicalSize;
  final double devicePixelRatio;

  Size get logicalSize => Size(
        physicalSize.width / devicePixelRatio,
        physicalSize.height / devicePixelRatio,
      );
}

/// 测试设置视口的唯一入口：按具名档查表设置物理尺寸与像素比，
/// 像素比随档固定、不留"调用方不传就用默认值"的分支。
/// [landscape] 取逻辑宽高对调；[textScale] 传字号档（1.0× / 1.6×），
/// 不传则不覆盖调用方自设的字号档。
/// 用例结束自动还原视口与字号档（框架不复位字号档，须显式清）。
void useNamedViewport(
  WidgetTester tester,
  ViewportTier tier, {
  bool landscape = false,
  double? textScale,
}) {
  tester.view.physicalSize = landscape
      ? Size(tier.physicalSize.height, tier.physicalSize.width)
      : tier.physicalSize;
  tester.view.devicePixelRatio = tier.devicePixelRatio;
  if (textScale != null) {
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
  }
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}
