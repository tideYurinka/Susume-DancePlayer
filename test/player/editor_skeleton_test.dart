import 'dart:ui' show Rect, Size;

import 'package:dance_learning_app/player/editor_skeleton.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetMinSize, kCornerPromptCardPaddingV;
import 'package:flutter_test/flutter_test.dart';

/// 竖屏编辑面骨架分配纯件直测（收口画面落位两分支）。
///
/// 只断言「给定输入 → 输出的几何与落位」：方向判定、画面区高与画面落位两
/// 分支。期望值取实数（本机竖屏真机基准 361.1×781.7dp、360×800 合成视口、
/// 横屏 781.7×361.1dp），不复写实现公式。
void main() {
  /// 本机竖屏真机基准（1264×2736 @3.5 = 361.1×781.7dp）。
  const portraitScreen = Size(361.1, 781.7);
  const normalTrackBandHeight = 208.0; // normal 行集整带高（行高表之和）
  const compareTrackBandHeight = 186.0; // compare 行集整带高

  /// 名义可用高（画面区从它再扣轨道带）：781.7 − (顶栏 52 + 底栏两行 104 +
  /// 视频播放工具栏两行 104 + 设置条 48) = 473.7；画面区高 = 本值 − 轨道带高
  /// （视频工具栏一行变两行、设置条命中盒下限 48，名义高表随之重算）。
  const nominalAbove = 473.7;

  /// 普通行集下的画面区高：473.7 − 208 = 265.7。
  const normalPictureArea = 265.7;

  EditorSkeleton skeletonFor({
    Size screen = portraitScreen,
    double trackBandHeight = normalTrackBandHeight,
    double? aspectRatio,
  }) => editorSkeletonFor(
    screen: screen,
    trackBandHeight: trackBandHeight,
    videoAspectRatio: aspectRatio,
  );

  group('方向判定（唯一读点）', () {
    test('屏高大于屏宽为竖屏、反之为横屏', () {
      expect(editorIsPortrait(const Size(361.1, 781.7)), isTrue);
      expect(editorIsPortrait(const Size(781.7, 361.1)), isFalse);
      expect(editorIsPortrait(const Size(400, 400)), isFalse, reason: '正方形按横屏行处理');
    });
  });

  group('紧凑档判定（唯一读点）', () {
    test('阈值两侧：最短边 599 判紧凑档、600 判常规档', () {
      expect(editorIsCompact(const Size(599, 800)), isTrue);
      expect(editorIsCompact(const Size(600, 800)), isFalse);
      expect(editorIsCompact(const Size(361.1, 781.7)), isTrue, reason: '手机竖屏');
      expect(editorIsCompact(const Size(820, 1180)), isFalse, reason: '平板竖屏');
    });

    test('最短边取宽高较小者：朝向对调得到同一档', () {
      expect(editorIsCompact(const Size(700, 599)), isTrue);
      expect(editorIsCompact(const Size(599, 700)), isTrue);
      expect(editorIsCompact(const Size(700, 600)), isFalse);
      expect(editorIsCompact(const Size(600, 700)), isFalse);
      expect(editorIsCompact(const Size(1180, 820)), isFalse, reason: '平板横屏');
    });
  });

  group('横屏行（布局逐位不变）', () {
    test('横屏屏：不分配骨架（画面带 0、画面区 0）', () {
      final s = skeletonFor(
        screen: const Size(781.7, 361.1),
        aspectRatio: 16 / 9,
      );
      expect(s.portrait, isFalse);
      expect(s.pictureBandHeight, 0, reason: '横屏行不分配画面带');
      expect(s.pictureBandTop, 0);
      expect(s.pictureAreaHeight, 0);
    });
  });

  group('画面落位两分支', () {
    test('横屏源（16:9）：满宽 contain 放得进画面区 → 贴底', () {
      const ar = 16 / 9;
      final s = skeletonFor(aspectRatio: ar);
      const pictureArea = normalPictureArea; // 265.7
      final containHeight = portraitScreen.width / ar; // ≈203.1
      expect(containHeight, lessThan(pictureArea));
      expect(s.portrait, isTrue);
      expect(s.pictureAreaHeight, closeTo(pictureArea, 0.01));
      expect(s.picturePlacement, PicturePlacement.stickToBottom);
      expect(s.pictureBandHeight, closeTo(containHeight, 0.01));
      expect(
        s.pictureBandTop,
        closeTo(pictureArea - containHeight, 0.01),
        reason: '底边贴画面区下缘、黑区留在画面上方',
      );
      expect(
        s.pictureBandTop + s.pictureBandHeight,
        closeTo(s.pictureAreaHeight, 0.01),
        reason: '画面底边 = 画面区下缘',
      );
    });

    test('竖向源（9:16）：满宽 contain 超出画面区 → 观看态背景位', () {
      const ar = 9 / 16;
      final s = skeletonFor(aspectRatio: ar);
      expect(portraitScreen.width / ar, greaterThan(normalPictureArea));
      expect(s.picturePlacement, PicturePlacement.background);
      expect(s.pictureBandHeight, 0, reason: '背景位不分配画面带（整屏 contain）');
      expect(s.pictureBandTop, 0);
      expect(s.pictureAreaHeight, closeTo(normalPictureArea, 0.01));
    });

    test('近方形源（1.1:1）：满宽 328.3 超出画面区 265.7 → 背景位', () {
      final s = skeletonFor(aspectRatio: 1.1);
      expect(portraitScreen.width / 1.1, closeTo(328.3, 0.05));
      expect(
        s.picturePlacement,
        PicturePlacement.background,
        reason: '画面区 265.7 放不下近方形源的满宽 contain 328.3（设置条 48）',
      );
      expect(s.pictureBandHeight, 0);
    });

    test('严格 1:1 源：满宽 361.1 仍超出画面区 265.7 → 背景位', () {
      final s = skeletonFor(aspectRatio: 1);
      expect(s.picturePlacement, PicturePlacement.background);
      expect(s.pictureBandHeight, 0);
    });

    test('宽高比未知：先按观看态出画（背景位），首帧就绪后重算', () {
      final s = skeletonFor(screen: const Size(360, 800), aspectRatio: null);
      expect(s.picturePlacement, PicturePlacement.background);
      expect(s.pictureBandHeight, 0, reason: '未知时先出观看态画面、不撑错误尺寸');
      expect(s.pictureBandTop, 0);
      expect(s.pictureAreaHeight, 800 - 308 - 208);
    });

    test('非法宽高比（0/负）按未知处理 → 背景位', () {
      expect(
        skeletonFor(aspectRatio: 0).picturePlacement,
        PicturePlacement.background,
      );
      expect(
        skeletonFor(aspectRatio: -1).picturePlacement,
        PicturePlacement.background,
      );
    });
  });

  group('边界：满宽 contain 高恰好等于画面区高', () {
    test('恰好相等 → 贴底（等于即放得进），差一点 → 背景位', () {
      // 360 宽、16:9 满宽 contain = 202.5；画面区 = 202.5 需可用高 410.5
      // → 屏高 410.5 + 308 = 718.5（固定段合计 308 = 顶栏 52 + 底栏两行 104
      // + 视频工具栏两行 104 + 设置条 48）。
      final exact = skeletonFor(
        screen: const Size(360, 718.5),
        aspectRatio: 16 / 9,
      );
      expect(exact.pictureAreaHeight, closeTo(202.5, 0.01));
      expect(exact.picturePlacement, PicturePlacement.stickToBottom);
      expect(exact.pictureBandHeight, closeTo(202.5, 0.01));
      expect(exact.pictureBandTop, closeTo(0, 0.01), reason: '恰好相等时画面顶 = 画面区顶');

      final oneLess = skeletonFor(
        screen: const Size(360, 718.4),
        aspectRatio: 16 / 9,
      );
      expect(
        oneLess.picturePlacement,
        PicturePlacement.background,
        reason: '差一点即放不进',
      );
    });
  });

  group('轨道行集高度参与画面区高计算', () {
    test('普通行集 208：画面区 = 可用高 − 208', () {
      final s = skeletonFor(trackBandHeight: normalTrackBandHeight);
      expect(s.pictureAreaHeight, closeTo(normalPictureArea, 0.01));
    });

    test('对比行集 186：画面区 = 可用高 − 186（比普通行集高 22dp）', () {
      final s = skeletonFor(
        trackBandHeight: compareTrackBandHeight,
        aspectRatio: 16 / 9,
      );
      expect(s.pictureAreaHeight, closeTo(nominalAbove - 186, 0.01));
      // 16:9 在对比行集下仍放得进，但黑区更窄（画面区更高）。
      expect(s.picturePlacement, PicturePlacement.stickToBottom);
      expect(s.pictureBandTop, closeTo(287.7 - 203.11875, 0.05));
    });

    test('极近方形源随行集高度翻分支：普通行集背景位、对比行集贴底', () {
      // 1.3:1 满宽 contain ≈277.8：普通行集画面区 265.7 放不进，对比行集
      // 287.7 放得进——同一条规则按实测高度分岔，不按源方向手写判断。
      const ar = 1.3;
      expect(portraitScreen.width / ar, closeTo(277.8, 0.05));
      final normal = skeletonFor(
        trackBandHeight: normalTrackBandHeight,
        aspectRatio: ar,
      );
      expect(normal.picturePlacement, PicturePlacement.background);
      final compare = skeletonFor(
        trackBandHeight: compareTrackBandHeight,
        aspectRatio: ar,
      );
      expect(compare.picturePlacement, PicturePlacement.stickToBottom);
      expect(
        compare.pictureBandTop + compare.pictureBandHeight,
        closeTo(compare.pictureAreaHeight, 0.01),
      );
    });
  });

  group('落位按选区内容宽高比', () {
    /// 选区内容宽高比 = (选区宽 ÷ 选区高) × 源比，故用归一化宽高比构造。
    double framingRatio({
      required double width,
      required double height,
      double sourceRatio = 16 / 9,
    }) => (width / height) * sourceRatio;

    test('未调过（framingAspectRatio = null）与今日逐像素一致', () {
      final today = skeletonFor(aspectRatio: 16 / 9);
      final explicit = editorSkeletonFor(
        screen: portraitScreen,
        trackBandHeight: normalTrackBandHeight,
        videoAspectRatio: 16 / 9,
        framingAspectRatio: null,
      );
      expect(explicit, today);
    });

    test('选区更「高」（内容比 < 源比）：盒高封顶在未取景画面矩形高、顶边不上移', () {
      const sourceRatio = 16 / 9;
      // 选区宽 0.5、高 0.6 → 内容比 ≈ 1.4815，满宽 contain ≈ 243.7 放得进
      // 画面区 265.7（贴底），但比未取景的 203.1 高——封顶后带高仍是 203.1。
      final contentRatio = framingRatio(width: 0.5, height: 0.6);
      expect(contentRatio, lessThan(sourceRatio), reason: '内容比源画面更「高」');
      final unframed = skeletonFor(aspectRatio: sourceRatio);
      final s = editorSkeletonFor(
        screen: portraitScreen,
        trackBandHeight: normalTrackBandHeight,
        videoAspectRatio: sourceRatio,
        framingAspectRatio: contentRatio,
      );
      final uncapped = portraitScreen.width / contentRatio;
      expect(uncapped, greaterThan(unframed.pictureBandHeight), reason: '未封顶会顶穿上方黑区');
      expect(uncapped, lessThan(normalPictureArea), reason: '仍放得进画面区 → 贴底');
      expect(s.picturePlacement, PicturePlacement.stickToBottom);
      expect(
        s.pictureBandHeight,
        closeTo(unframed.pictureBandHeight, 0.01),
        reason: '盒高封顶在未取景画面矩形高',
      );
      expect(
        s.pictureBandTop,
        closeTo(normalPictureArea - unframed.pictureBandHeight, 0.01),
        reason: '画面顶边不上移、上方黑区一字不动',
      );
      expect(s.pictureBandTop, greaterThan(0));
    });

    test('选区更「宽」（内容比 > 源比）：盒高 = 屏宽 ÷ 选区内容比（比未取景更矮）', () {
      const sourceRatio = 16 / 9;
      final contentRatio = framingRatio(width: 0.8, height: 0.4);
      expect(contentRatio, greaterThan(sourceRatio));
      final unframed = skeletonFor(aspectRatio: sourceRatio);
      final s = editorSkeletonFor(
        screen: portraitScreen,
        trackBandHeight: normalTrackBandHeight,
        videoAspectRatio: sourceRatio,
        framingAspectRatio: contentRatio,
      );
      final contain = portraitScreen.width / contentRatio;
      expect(contain, lessThan(unframed.pictureBandHeight));
      expect(s.picturePlacement, PicturePlacement.stickToBottom);
      expect(s.pictureBandHeight, closeTo(contain, 0.01));
      expect(
        s.pictureBandTop + s.pictureBandHeight,
        closeTo(s.pictureAreaHeight, 0.01),
        reason: '底边仍贴画面区下缘',
      );
    });

    test('选区内容比放不进画面区 → 观看态背景位（不分配画面带）', () {
      const sourceRatio = 16 / 9;
      // 宽 0.5、高 1 → 内容比 ≈ 0.8889，满宽 contain ≈ 406.2 > 265.7。
      final contentRatio = framingRatio(width: 0.5, height: 1);
      final s = editorSkeletonFor(
        screen: portraitScreen,
        trackBandHeight: normalTrackBandHeight,
        videoAspectRatio: sourceRatio,
        framingAspectRatio: contentRatio,
      );
      expect(portraitScreen.width / contentRatio, greaterThan(normalPictureArea));
      expect(s.picturePlacement, PicturePlacement.background);
      expect(s.pictureBandHeight, 0);
      expect(s.pictureBandTop, 0);
    });

    test('边界：选区内容比与源比相同 → 与未取景逐像素一致', () {
      const sourceRatio = 16 / 9;
      final s = editorSkeletonFor(
        screen: portraitScreen,
        trackBandHeight: normalTrackBandHeight,
        videoAspectRatio: sourceRatio,
        framingAspectRatio: sourceRatio,
      );
      expect(s, skeletonFor(aspectRatio: sourceRatio));
    });
  });

  group('画面矩形求解', () {
    Rect rectFor({
      Size screen = portraitScreen,
      double systemTopInset = 24,
      double? aspectRatio = 16 / 9,
      EditorSkeleton? skeleton,
    }) => videoPictureRect(
      screen: screen,
      systemTopInset: systemTopInset,
      videoAspectRatio: aspectRatio,
      skeleton: skeleton,
    );

    test('观看态竖屏：16:9 源 contain 居中，圆心落在画面上角而非屏幕上角', () {
      final rect = rectFor();
      expect(rect.width, portraitScreen.width);
      // 画面高 = 361.1 / (16/9)。
      expect(rect.height, closeTo(361.1 * 9 / 16, 0.01));
      expect(rect.top, greaterThan(24), reason: '画面居中，上方留黑边——取消区圆心跟画面走');
      expect(rect.top, lessThan(portraitScreen.height / 2));
      expect(rect.left, 0);
      expect(rect.center.dy, closeTo(portraitScreen.height / 2, 0.01));
    });

    test('横屏屏：16:9 源高度铺满（左右留黑），取消区圆心仍在屏幕上角', () {
      final rect = rectFor(screen: const Size(781.7, 361.1));
      expect(rect.top, 0, reason: '画面高铺满屏幕——画面上角即屏幕上角，结果与今天一致');
      expect(rect.height, 361.1);
      expect(rect.width, closeTo(361.1 * 16 / 9, 0.01));
      expect(rect.center.dx, closeTo(781.7 / 2, 0.01));
    });

    test('竖屏源在竖屏屏：按宽铺满、上下留黑', () {
      final rect = rectFor(aspectRatio: 9 / 16);
      expect(rect.width, portraitScreen.width);
      expect(rect.height, closeTo(portraitScreen.width * 16 / 9, 0.01));
      expect(rect.top, greaterThan(0));
    });

    test('宽高比未知：退化为系统栏内的屏幕可用区（照旧可用、不崩）', () {
      final rect = rectFor(aspectRatio: null);
      expect(rect.left, 0);
      expect(rect.top, 24);
      expect(rect.width, portraitScreen.width);
      expect(rect.height, portraitScreen.height - 24);
      final rectNonPositive = rectFor(aspectRatio: -1);
      expect(rectNonPositive.top, 24);
    });

    test('编辑态贴底分支：矩形 = 画面带（带顶按系统栏换算）', () {
      const stick = EditorSkeleton(
        portrait: true,
        pictureAreaHeight: 200,
        picturePlacement: PicturePlacement.stickToBottom,
        pictureBandHeight: 100,
        pictureBandTop: 50,
      );
      final rect = rectFor(skeleton: stick);
      // bandTopIn = 系统栏 24 + 顶栏 52 + 带顶 50。
      expect(rect.top, 24 + kEditorTopBarHeight + 50);
      expect(rect.height, 100);
      expect(rect.left, 0);
      expect(rect.width, portraitScreen.width);
    });

    test('编辑态背景位（骨架非贴底）：同观看态整屏 contain 居中', () {
      const background = EditorSkeleton(
        portrait: true,
        pictureAreaHeight: 200,
        picturePlacement: PicturePlacement.background,
        pictureBandHeight: 0,
        pictureBandTop: 0,
      );
      final rect = rectFor(skeleton: background);
      expect(rect, rectFor(skeleton: null));
    });
  });

  group('横屏「转为竖屏」钮锚', () {
    /// 横屏基准屏（padding = 0，781.7 × 361.1）的轨道带上缘：
    /// 361.14 − 底栏 52 − 轨道带 208。
    const trackBandTop = 101.14;

    test('尺寸 62 × 32：左缘 = 左系统栏内缩 + 间隙（与返回键同列）', () {
      final noInset = landscapeToPortraitButtonRect(
        systemTopInset: 0,
        systemLeftInset: 0,
        trackBandTop: trackBandTop,
      );
      expect(noInset.width, 62);
      expect(noInset.height, 32);
      expect(noInset.left, 4);
      expect(noInset.top, kEditorTopBarHeight + 4, reason: '返回键正下方');
      expect(noInset.bottom, lessThanOrEqualTo(trackBandTop));

      // 号机横屏左内缩 39.4dp：x 43.4–105.4、y 56–88。
      final device = landscapeToPortraitButtonRect(
        systemTopInset: 0,
        systemLeftInset: 39.4,
        trackBandTop: trackBandTop,
      );
      expect(device.left, closeTo(43.4, 0.01));
      expect(device.right, closeTo(105.4, 0.01));
      expect(
        device.right,
        lessThanOrEqualTo(130),
        reason: '右缘在数拍数字默认位（x ≈ 130–190）之左',
      );
    });

    test('顶部锚随顶系统栏内缩下移（返回键正下方）', () {
      final rect = landscapeToPortraitButtonRect(
        systemTopInset: 39.4,
        systemLeftInset: 0,
        trackBandTop: 150,
      );
      expect(rect.top, closeTo(39.4 + kEditorTopBarHeight + 4, 0.01));
    });

    test('短屏：底边不越过轨道带上缘（上移），再挤也不越过顶系统栏内缩', () {
      final clamped = landscapeToPortraitButtonRect(
        systemTopInset: 0,
        systemLeftInset: 0,
        trackBandTop: 88,
      );
      expect(clamped.bottom, lessThanOrEqualTo(88));
      expect(clamped.top, closeTo(52, 0.01), reason: '中带容不下 32dp 时整体上移');

      final floored = landscapeToPortraitButtonRect(
        systemTopInset: 0,
        systemLeftInset: 0,
        trackBandTop: 30,
      );
      expect(floored.top, 0, reason: '再挤也不越过顶系统栏内缩');
    });
  });

  group('取消区半径', () {
    test('常规画面：半径 = 88dp 上限', () {
      expect(
        cancelZoneRadius(const Rect.fromLTWH(0, 0, 800, 600)),
        kScrubCancelZoneSize,
      );
      expect(kScrubCancelZoneSize, 88);
    });

    test('画面很扁：半径随画面短边收缩', () {
      expect(cancelZoneRadius(const Rect.fromLTWH(0, 0, 400, 50)), 50);
      expect(cancelZoneRadius(const Rect.fromLTWH(0, 0, 30, 100)), 30);
    });
  });

  group('竖屏名义高表', () {
    test('计入底栏两行与视频播放工具栏两行', () {
      expect(kEditorPortraitToolbarRowsHeight, kEditorToolbarHeight * 2);
      expect(kEditorVideoToolbarHeight, kEditorToolbarHeight * 2,
          reason: '视频播放工具栏拆两行，名义高随之翻倍');
      // 未知宽高比时画面区仍按同一名义高表扣除（先出观看态画面）。
      final s = skeletonFor(screen: const Size(360, 800), aspectRatio: null);
      expect(
        s.pictureAreaHeight,
        800 -
            kEditorTopBarHeight -
            kEditorPortraitToolbarRowsHeight -
            kEditorVideoToolbarHeight -
            kEditorSettingsClusterHeight -
            normalTrackBandHeight,
      );
    });
  });

  group('左下角提示卡锚', () {
    // 号机基准：361.1 × 781.7dp、竖屏顶内缩 39.4、
    // 系统手势让路带取既有代表值：左 16 / 底 44、普通态轨道带 208dp。
    const portrait = Size(361.1, 781.7);
    const landscape = Size(781.7, 361.1);
    const deviceTopInset = 39.4;
    const yieldLeft = 16.0;
    const yieldBottom = 44.0;
    const trackBand = 208.0;

    // 八格表的画面矩形（八格表原值）。
    const bandRect = Rect.fromLTWH(0, 166.6, 361.1, 203.1); // 竖屏编辑·贴底画面带
    const tallRect = Rect.fromLTWH(0, 69.9, 361.1, 641.9); // 竖源 contain
    const watchingRect = Rect.fromLTWH(0, 289.3, 361.1, 203.1); // 观看态 16:9
    const wideRect = Rect.fromLTWH(69.9, 0, 641.9, 361.1); // 横屏 16:9（左右留黑）
    const landscapeTallRect = Rect.fromLTWH(289.3, 0, 203.1, 361.1); // 横屏 9:16

    // 编辑面骨架：竖屏 16:9 贴底（画面区 278.3、画面带 203.1）；横屏不分配。
    final portraitSkeleton = editorSkeletonFor(
      screen: const Size(361.1, 781.7 - deviceTopInset),
      trackBandHeight: trackBand,
      videoAspectRatio: 16 / 9,
    );
    final landscapeSkeleton = editorSkeletonFor(
      screen: landscape,
      trackBandHeight: trackBand,
      videoAspectRatio: 16 / 9,
    );

    ({double left, double bottom})? anchorOf({
      required Rect picture,
      required Size screen,
      EditorSkeleton? editing,
      double gestureLeft = yieldLeft,
      double gestureBottom = yieldBottom,
    }) => cornerPromptAnchor(
      pictureRect: picture,
      screen: screen,
      // 横屏基准 padding 为 0；竖屏基准顶内缩 39.4。
      systemTopInset: editorIsPortrait(screen) ? deviceTopInset : 0,
      systemBottomInset: 0,
      gestureLeft: gestureLeft,
      gestureBottom: gestureBottom,
      editingSkeleton: editing,
      trackBandHeight: trackBand,
    );

    test('名义高 = 命中下限 48 + 紧凑档垂直内边距 ×2 = 48', () {
      expect(kCornerPromptCardNominalHeight, 48);
      expect(
        kCornerPromptCardNominalHeight,
        kHitTargetMinSize + kCornerPromptCardPaddingV * 2,
      );
    });

    test('八格表：姿态 × 源方向 × 控制层展开/收起 → 卡左下角', () {
      final cells =
          <({
            String name,
            Rect picture,
            Size screen,
            EditorSkeleton? editing,
            double? left,
            double? bottom,
          })>[
        (
          name: '竖·横源·展开',
          picture: bandRect,
          screen: portrait,
          editing: portraitSkeleton,
          left: 24,
          bottom: 293.7,
        ),
        (
          name: '竖·竖源·展开（上抬到画面区下缘之上）',
          picture: tallRect,
          screen: portrait,
          editing: portraitSkeleton,
          left: 24,
          bottom: 293.7,
        ),
        (
          name: '竖·横源·收起',
          picture: watchingRect,
          screen: portrait,
          editing: null,
          left: 24,
          bottom: 468.4,
        ),
        (
          name: '竖·竖源·收起',
          picture: tallRect,
          screen: portrait,
          editing: null,
          left: 24,
          bottom: 687.8,
        ),
        (
          name: '横·横源·展开（放不下）',
          picture: wideRect,
          screen: landscape,
          editing: landscapeSkeleton,
          left: null,
          bottom: null,
        ),
        (
          name: '横·竖源·展开（放不下）',
          picture: landscapeTallRect,
          screen: landscape,
          editing: landscapeSkeleton,
          left: null,
          bottom: null,
        ),
        (
          name: '横·横源·收起',
          picture: wideRect,
          screen: landscape,
          editing: null,
          left: 93.9,
          bottom: 317.1,
        ),
        (
          name: '横·竖源·收起（跟着居中的画面走）',
          picture: landscapeTallRect,
          screen: landscape,
          editing: null,
          left: 313.3,
          bottom: 317.1,
        ),
      ];

      for (final cell in cells) {
        final anchor = anchorOf(
          picture: cell.picture,
          screen: cell.screen,
          editing: cell.editing,
        );
        if (cell.left == null) {
          expect(anchor, isNull, reason: '${cell.name}：放不下 → 不画');
          continue;
        }
        expect(anchor, isNotNull, reason: '${cell.name}：本次应画出');
        expect(anchor!.left, closeTo(cell.left!, 0.05), reason: '${cell.name} 左');
        expect(
          anchor.bottom,
          closeTo(cell.bottom!, 0.05),
          reason: '${cell.name} 底',
        );
      }
    });

    test('让路推出带外：只有真的贴到屏幕边的那条边被推（横屏）', () {
      // 带为 0（未上报不触发）：卡停在画面矩形内缩 24dp 处。
      final flushed = anchorOf(
        picture: wideRect,
        screen: landscape,
        gestureLeft: 0,
        gestureBottom: 0,
      );
      expect(flushed!.left, 93.9);
      expect(flushed.bottom, 337.1, reason: '卡底仍贴画面左下角内缩 24dp');

      // 底边落进让路带（44）：只推底边，左缘 93.9 在带外不动。
      final yielded = anchorOf(picture: wideRect, screen: landscape);
      expect(yielded!.left, 93.9, reason: '左缘在左右让路带之外，不被平白推开');
      expect(yielded.bottom, 317.1, reason: '底 = 屏高 − 让路带底');
    });

    test('竖屏各态：让路带取 0 与 44/16 两档落位逐位不变（不触发让路）', () {
      final cells = <({Rect picture, EditorSkeleton? editing})>[
        (picture: bandRect, editing: portraitSkeleton),
        (picture: tallRect, editing: portraitSkeleton),
        (picture: watchingRect, editing: null),
        (picture: tallRect, editing: null),
      ];
      for (final cell in cells) {
        final none = anchorOf(
          picture: cell.picture,
          screen: portrait,
          editing: cell.editing,
          gestureLeft: 0,
          gestureBottom: 0,
        );
        final band = anchorOf(
          picture: cell.picture,
          screen: portrait,
          editing: cell.editing,
        );
        expect(none, isNotNull);
        expect(none!.left, band!.left);
        expect(none.bottom, band.bottom);
      }
    });

    test('占用区上抬：竖屏竖向源编辑态抬到画面区下缘之上 24dp', () {
      final watching = anchorOf(picture: tallRect, screen: portrait);
      expect(watching!.bottom, closeTo(687.8, 0.05), reason: '收起控制层：贴画面左下角');

      final editing = anchorOf(
        picture: tallRect,
        screen: portrait,
        editing: portraitSkeleton,
      );
      expect(
        editing!.bottom,
        closeTo(293.7, 0.05),
        reason: '展开控制层：画面区下缘 317.7 − 24',
      );
      expect(editing.left, closeTo(24, 0.001), reason: '横向仍贴画面左缘');
    });

    test('放不下判空：横屏编辑态（中带只剩 49.1dp）与贴顶的矮画面', () {
      expect(
        anchorOf(
          picture: wideRect,
          screen: landscape,
          editing: landscapeSkeleton,
        ),
        isNull,
      );
      // 竖屏：画面贴顶且太矮——卡顶边（名义高 48）越不过顶栏下缘。
      final tooShort = anchorOf(
        picture: const Rect.fromLTWH(0, 0, 203.1, 120),
        screen: const Size(361.1, 120),
        gestureLeft: 0,
        gestureBottom: 0,
      );
      expect(tooShort, isNull);
    });

    test('顶边恰好落在顶栏下缘：等于即放得进，差 0.1 即判空', () {
      // 卡底 = 顶内缩 39.4 + 顶栏 52 + 名义高 48 = 139.4 时顶边恰好贴上。
      final exact = anchorOf(
        picture: const Rect.fromLTWH(0, 0, 361.1, 163.4),
        screen: portrait,
        gestureLeft: 0,
        gestureBottom: 0,
      );
      expect(exact!.bottom, closeTo(139.4, 0.001));
      expect(
        exact.bottom - kCornerPromptCardNominalHeight,
        closeTo(deviceTopInset + kEditorTopBarHeight, 0.001),
        reason: '顶边恰好落在顶栏下缘',
      );

      final oneLess = anchorOf(
        picture: const Rect.fromLTWH(0, 0, 361.1, 163.3),
        screen: portrait,
        gestureLeft: 0,
        gestureBottom: 0,
      );
      expect(oneLess, isNull, reason: '差一点即放不下');
    });
  });
}
