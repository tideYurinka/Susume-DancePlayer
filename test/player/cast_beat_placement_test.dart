import 'package:dance_learning_app/player/beat_animation.dart'
    show BeatAnimationStyle;
import 'package:dance_learning_app/player/cast_beat_placement.dart';
import 'package:dance_learning_app/player/overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// **视口 → 画面区域的换算直测**（`#30` 验收第 3 条）：四格记忆与尺寸系数都
/// 参与落位；期望值一律由本测试按**手算**给出（不反算被测代码）。
///
/// 手机侧的事实（本测试的输入）：
/// - 视口 400×800（竖屏）；矩形形态框 = 320×120（视口联动上限 400/320 = 1.25
///   在系数 1 时不生效）；
/// - 画面区域 = 视频画面在视口里 contain 出来的那一块，此处取
///   `(0, 300, 400, 225)`（上下留黑）；
/// - 数字行量测尺寸 100×56。
///
/// 数字那一行在框里的中心（与上屏同一份布局算术，手算）：
///   底衬高 = 56（数字行）+ 6（间距）+ 28（动画位；矩形形态）+ 10×2（内边距）
///          = 110
///   中心 = (320/2, (120 − 110)/2 + 10 + 56/2) = (160, 43)
/// 于是屏幕坐标里的中心 = 框左上 + (160, 43)；画布（底衬）尺寸
/// = (100 + 16×2) × (56 + 10×2) = 132×76。归一化分母 = 画面矩形 (0,300,400,225)。
void main() {
  const viewport = Size(400, 800);
  const picture = Rect.fromLTWH(0, 300, 400, 225);
  const numbers = Size(100, 56);

  OverlayPlacements placements({
    Map<OverlayPlacementCell, Offset> offsets = const {},
    double rectWidthFactor = 1,
    double pendulumScale = 1,
  }) => OverlayPlacements(
    offsets: offsets,
    rectWidthFactor: rectWidthFactor,
    pendulumScale: pendulumScale,
  );

  CastBeatPlacement? placementOf({
    OverlayPlacements? cellPlacements,
    OverlayPlacementCell cell = OverlayPlacementCell.portraitNormal,
    BeatAnimationStyle style = BeatAnimationStyle.bar,
    Size numbersSize = numbers,
    Rect pictureRect = picture,
    Size viewportSize = viewport,
    double textScale = 1,
  }) => castBeatPlacementOf(
    placements: cellPlacements ?? placements(),
    cell: cell,
    style: style,
    viewport: viewportSize,
    pictureRect: pictureRect,
    numbersSize: numbersSize,
    textScale: textScale,
  );

  group('相对画面区域归一化', () {
    test('未自定义格：默认位（贴左、纵向视口高 12%）→ 中心与尺寸逐项对', () {
      final placement = placementOf()!;

      // 框左上 = (0, 0.12 × 800 = 96)；数字中心 = (160, 96 + 43 = 139)。
      expect(placement.centerX, closeTo(160 / 400, 1e-9));
      expect(placement.centerY, closeTo((139 - 300) / 225, 1e-9));
      expect(placement.widthFraction, closeTo(132 / 400, 1e-9));
      expect(placement.heightFraction, closeTo(76 / 225, 1e-9));
      expect(placement.usable, isTrue);
    });

    test('可用的判定：非有限 / 零 / 负尺寸一律不可用（与数拍层同一条）', () {
      CastBeatPlacement at({
        double centerX = 0.5,
        double centerY = 0.5,
        double widthFraction = 0.3,
        double heightFraction = 0.2,
      }) => CastBeatPlacement(
        centerX: centerX,
        centerY: centerY,
        widthFraction: widthFraction,
        heightFraction: heightFraction,
      );

      expect(at().usable, isTrue);
      expect(at(widthFraction: 0).usable, isFalse);
      expect(at(heightFraction: -0.1).usable, isFalse);
      expect(at(centerX: double.nan).usable, isFalse);
      expect(at(centerY: double.infinity).usable, isFalse);
      expect(at(widthFraction: double.nan).usable, isFalse);
    });

    test('画面矩形整体平移：相对量随之变化（换算的是相对位置）', () {
      final shifted = placementOf(
        pictureRect: picture.shift(const Offset(20, -60)),
      )!;

      expect(shifted.centerX, closeTo((160 - 20) / 400, 1e-9));
      expect(shifted.centerY, closeTo((139 - 240) / 225, 1e-9));
      expect(shifted.widthFraction, closeTo(132 / 400, 1e-9));
      expect(shifted.heightFraction, closeTo(76 / 225, 1e-9));
    });
  });

  group('四格记忆', () {
    // 四个格各有自定义位（都在视口内，故不触发钳制）：
    //   portraitNormal (40, 400) → 中心 (200, 443)
    //   landscapeNormal (0, 0)   → 中心 (160, 43)
    //   portraitCompare (10, 200)→ 中心 (170, 243)
    //   landscapeCompare (80, 680)→ 中心 (240, 723)
    final custom = placements(
      offsets: const {
        OverlayPlacementCell.portraitNormal: Offset(40, 400),
        OverlayPlacementCell.landscapeNormal: Offset(0, 0),
        OverlayPlacementCell.portraitCompare: Offset(10, 200),
        OverlayPlacementCell.landscapeCompare: Offset(80, 680),
      },
    );

    test('取的是当前格的自定义位（四格各走各的）', () {
      final byCell = {
        for (final cell in OverlayPlacementCell.values)
          cell: placementOf(cellPlacements: custom, cell: cell)!,
      };

      expect(byCell[OverlayPlacementCell.portraitNormal]!.centerX,
          closeTo(200 / 400, 1e-9));
      expect(byCell[OverlayPlacementCell.portraitNormal]!.centerY,
          closeTo((443 - 300) / 225, 1e-9));
      expect(byCell[OverlayPlacementCell.landscapeNormal]!.centerX,
          closeTo(160 / 400, 1e-9));
      expect(byCell[OverlayPlacementCell.landscapeNormal]!.centerY,
          closeTo((43 - 300) / 225, 1e-9));
      expect(byCell[OverlayPlacementCell.portraitCompare]!.centerX,
          closeTo(170 / 400, 1e-9));
      expect(byCell[OverlayPlacementCell.portraitCompare]!.centerY,
          closeTo((243 - 300) / 225, 1e-9));
      expect(byCell[OverlayPlacementCell.landscapeCompare]!.centerX,
          closeTo(240 / 400, 1e-9));
      expect(byCell[OverlayPlacementCell.landscapeCompare]!.centerY,
          closeTo((723 - 300) / 225, 1e-9));
      expect(byCell.values.toSet().length, 4, reason: '四格互不相同');
    });

    test('当前格未自定义时回落默认位（与「只有别的格有自定义」无关）', () {
      final onlyOtherCell = placements(
        offsets: const {
          OverlayPlacementCell.landscapeCompare: Offset(80, 680),
        },
      );

      expect(
        placementOf(
          cellPlacements: onlyOtherCell,
          cell: OverlayPlacementCell.portraitNormal,
        ),
        placementOf(),
      );
    });

    test('越界的自定义位按视口钳制后再换算（钳制只进生效面）', () {
      final beyond = placements(
        offsets: const {
          // 视口 400×800、框 320×120 → dx 上限 80、dy 上限 680。
          OverlayPlacementCell.portraitNormal: Offset(999, 999),
        },
      );
      final placement = placementOf(
        cellPlacements: beyond,
        cell: OverlayPlacementCell.portraitNormal,
      )!;

      // 生效框左上 = (80, 680) → 数字中心 = (240, 723)。
      expect(placement.centerX, closeTo(240 / 400, 1e-9));
      expect(placement.centerY, closeTo((723 - 300) / 225, 1e-9));
    });
  });

  group('尺寸系数', () {
    test('矩形宽系数：框宽受视口联动上限（400/320 = 1.25），中心随框心横移', () {
      final wide = placementOf(cellPlacements: placements(rectWidthFactor: 2))!;

      // 生效框宽 = 320 × 1.25 = 400（铺满视口）；框心 x = 200。
      // 数字仍在框心、且横向居中：中心 = (200, 96 + 43 = 139)；画布尺寸不变。
      expect(wide.centerX, closeTo(200 / 400, 1e-9));
      expect(wide.centerY, closeTo((139 - 300) / 225, 1e-9));
      expect(wide.widthFraction, closeTo(132 / 400, 1e-9));
      expect(wide.heightFraction, closeTo(76 / 225, 1e-9));
    });

    test('摆锤等比系数：数字与底衬一起等比，中心随内容区等比缩放', () {
      final pendulum = placementOf(
        cellPlacements: placements(pendulumScale: 2),
        style: BeatAnimationStyle.pendulum,
      )!;

      // 摆锤生效系数 = min(2, 视口上限 min(400/220, 800/120) = 1.8181818)。
      const s = 400 / 220;
      // 基准盒（220×120）里：底衬高 = 56 + 6 + 32（摆锤动画位）+ 20 = 114，
      // 中心 = (110, (120 − 114)/2 + 10 + 28 = 41) → ×s = (200, 74.5454…)；
      // 框偏移 = 默认位 (0, 96)（框高 120×s = 218.18，视口内不钳）。
      expect(pendulum.centerX, closeTo(200 / 400, 1e-9));
      expect(pendulum.centerY, closeTo((96 + 41 * s - 300) / 225, 1e-9));
      // 画布 = (132×76) × s。
      expect(pendulum.widthFraction, closeTo(132 * s / 400, 1e-9));
      expect(pendulum.heightFraction, closeTo(76 * s / 225, 1e-9));
    });

    test('系统字号只抬内容区竖向容量（数字中心随之下移），不改画布尺寸', () {
      final scaled = placementOf(textScale: 1.5)!;

      // 内容区高 = 120 × 1.5 = 180：中心 y = (180 − 110)/2 + 10 + 28 = 73；
      // 框偏移仍是默认位 96 → 屏幕 y = 169；画布尺寸不随字号容量变。
      expect(scaled.centerX, closeTo(160 / 400, 1e-9));
      expect(scaled.centerY, closeTo((169 - 300) / 225, 1e-9));
      expect(scaled.widthFraction, closeTo(132 / 400, 1e-9));
      expect(scaled.heightFraction, closeTo(76 / 225, 1e-9));
    });
  });

  group('贴边（画面里没有它原来的位置时）', () {
    test('信箱黑边上的默认位被钳到画面最近的边（不是凭空消失）', () {
      final raw = placementOf()!;
      expect(raw.centerY, lessThan(0), reason: '竖屏 + 横片：默认位落在画面上方的黑边里');

      final placement = castBeatPlacementInPicture(
        placements: placements(),
        cell: OverlayPlacementCell.portraitNormal,
        style: BeatAnimationStyle.bar,
        viewport: viewport,
        pictureRect: picture,
        numbersSize: numbers,
      )!;

      // 钳到画面顶：中心 y = 300 + 76/2 = 338；x 在画面内不动（160）。
      expect(placement.centerY, closeTo((338 - 300) / 225, 1e-9));
      expect(placement.centerX, closeTo(160 / 400, 1e-9));
      expect(placement.widthFraction, closeTo(132 / 400, 1e-9));
      expect(placement.heightFraction, closeTo(76 / 225, 1e-9));
    });

    test('画面之内原样返回：钳制不改变画面内的那一档', () {
      final inside = placementOf(
        cellPlacements: placements(
          offsets: const {
            OverlayPlacementCell.portraitNormal: Offset(0, 320),
          },
        ),
      )!;

      expect(
        castBeatPlacementClamped(placement: inside, pictureRect: picture),
        inside,
      );
    });

    test('装不下（比画面还大）的那一轴居中', () {
      final huge = placementOf(numbersSize: const Size(500, 300))!;

      final clamped = castBeatPlacementClamped(
        placement: huge,
        pictureRect: picture,
      );

      expect(clamped.centerX, closeTo(0.5, 1e-9));
      expect(clamped.centerY, closeTo(0.5, 1e-9));
    });
  });

  group('退化输入与值语义', () {
    test('画面矩形量不到（空 / 非有限）时不装这一层', () {
      expect(placementOf(pictureRect: Rect.zero), isNull);
      expect(
        placementOf(pictureRect: const Rect.fromLTWH(0, 0, 400, double.nan)),
        isNull,
      );
    });

    test('视口 / 数字尺寸退化时不装这一层', () {
      expect(placementOf(viewportSize: Size.zero), isNull);
      expect(placementOf(numbersSize: Size.zero), isNull);
    });

    test('值对象按内容判等，且位置一动记号就变（进缓存键）', () {
      expect(placementOf(), placementOf());
      expect(
        placementOf(cellPlacements: placements(rectWidthFactor: 2)),
        isNot(placementOf()),
      );
      expect(placementOf()!.token, contains('bo:'));
    });
  });
}
