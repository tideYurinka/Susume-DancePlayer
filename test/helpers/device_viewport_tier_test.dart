import 'package:dance_learning_app/player/editor_skeleton.dart'
    show editorIsCompact;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'device_viewport.dart';

void main() {
  group('具名视口档档表', () {
    test('五档各只声明一个 (物理尺寸, 像素比) 二元组', () {
      expect(ViewportTier.values, hasLength(5));
      expect(
        ViewportTier.small.physicalSize,
        const Size(320, 640),
      );
      expect(ViewportTier.small.devicePixelRatio, 1.0);
      expect(
        ViewportTier.compact.physicalSize,
        const Size(1264, 2736),
      );
      expect(ViewportTier.compact.devicePixelRatio, 3.5);
      expect(
        ViewportTier.regular.physicalSize,
        const Size(393, 852),
      );
      expect(ViewportTier.regular.devicePixelRatio, 1.0);
      expect(
        ViewportTier.large.physicalSize,
        const Size(480, 1000),
      );
      expect(ViewportTier.large.devicePixelRatio, 1.0);
      expect(
        ViewportTier.tablet.physicalSize,
        const Size(820, 1180),
      );
      expect(ViewportTier.tablet.devicePixelRatio, 1.0);
    });

    test('逻辑尺寸由二元组折出', () {
      expect(
        ViewportTier.small.logicalSize,
        const Size(320, 640),
      );
      expect(ViewportTier.compact.logicalSize.width, closeTo(361.1, 0.1));
      expect(ViewportTier.compact.logicalSize.height, closeTo(781.7, 0.1));
      expect(
        ViewportTier.regular.logicalSize,
        const Size(393, 852),
      );
      expect(
        ViewportTier.large.logicalSize,
        const Size(480, 1000),
      );
      expect(
        ViewportTier.tablet.logicalSize,
        const Size(820, 1180),
      );
    });
  });

  group('具名视口档落哪一档', () {
    test('现有四档全落紧凑档、平板档落常规档', () {
      const compactTiers = [
        ViewportTier.small,
        ViewportTier.compact,
        ViewportTier.regular,
        ViewportTier.large,
      ];
      for (final tier in compactTiers) {
        expect(
          editorIsCompact(tier.logicalSize),
          isTrue,
          reason: '${tier.name} 落紧凑档',
        );
      }
      expect(
        editorIsCompact(ViewportTier.tablet.logicalSize),
        isFalse,
        reason: 'tablet 820×1180 落常规档',
      );
      expect(
        editorIsCompact(
          Size(
            ViewportTier.tablet.logicalSize.height,
            ViewportTier.tablet.logicalSize.width,
          ),
        ),
        isFalse,
        reason: 'tablet 横屏 1180×820 仍落常规档',
      );
    });

    testWidgets('字号档不参与档位判定：同一视口在 1.0× 与 1.6× 下同一档', (tester) async {
      Future<({bool compact, double textScale})> tierAt(
        double textScale,
      ) async {
        useNamedViewport(tester, ViewportTier.small, textScale: textScale);
        late bool compact;
        late double scale;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                final media = MediaQuery.of(context);
                compact = editorIsCompact(media.size);
                scale = media.textScaler.scale(10) / 10;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        return (compact: compact, textScale: scale);
      }

      final atNormal = await tierAt(1.0);
      final atLarge = await tierAt(1.6);
      expect(atNormal.textScale, 1.0);
      expect(atLarge.textScale, 1.6, reason: '两次环境确实换了字号档');
      expect(
        atLarge.compact,
        atNormal.compact,
        reason: '同一尺寸在 1.0× 与 1.6× 下得到同一档',
      );
    });
  });

  testWidgets('入口按档设置物理尺寸与像素比', (tester) async {
    useNamedViewport(tester, ViewportTier.compact);
    expect(tester.view.physicalSize, const Size(1264, 2736));
    expect(tester.view.devicePixelRatio, 3.5);
    expect(tester.view.physicalSize.width / tester.view.devicePixelRatio, closeTo(361.1, 0.1));
    expect(tester.view.physicalSize.height / tester.view.devicePixelRatio, closeTo(781.7, 0.1));
  });

  testWidgets('合成档像素比也被显式设置', (tester) async {
    // 先证明测试环境默认像素比不是 1.0，断言才可区分"显式设置"与"碰巧默认"。
    expect(tester.view.devicePixelRatio, 3.0);
    useNamedViewport(tester, ViewportTier.small);
    expect(tester.view.physicalSize, const Size(320, 640));
    expect(tester.view.devicePixelRatio, 1.0);
  });

  testWidgets('横屏返回逻辑宽高对调的视口', (tester) async {
    useNamedViewport(tester, ViewportTier.compact, landscape: true);
    expect(tester.view.physicalSize.width, closeTo(2736, 0.001));
    expect(tester.view.physicalSize.height, closeTo(1264, 0.001));
    expect(tester.view.devicePixelRatio, 3.5);
    expect(tester.view.physicalSize.width / tester.view.devicePixelRatio, closeTo(781.7, 0.1));
    expect(tester.view.physicalSize.height / tester.view.devicePixelRatio, closeTo(361.1, 0.1));
  });

  testWidgets('字号档传递到平台派发器', (tester) async {
    useNamedViewport(tester, ViewportTier.large, textScale: 1.6);
    expect(tester.platformDispatcher.textScaleFactor, 1.6);
  });
}
