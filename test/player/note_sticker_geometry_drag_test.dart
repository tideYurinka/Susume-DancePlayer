import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/core/playback/playback_engine_providers.dart';
import 'package:dance_learning_app/player/annotation_edit.dart';
import 'package:dance_learning_app/player/annotation_editor.dart';
import 'package:dance_learning_app/player/notice.dart' show NoticeId, noticeTriggerProvider;
import 'package:dance_learning_app/player/note_sticker_layout.dart';
import 'package:dance_learning_app/player/note_sticker_overlay.dart';
import 'package:dance_learning_app/player/note_sticker_overlay_registration.dart';
import 'package:dance_learning_app/surface_direction/surface_direction.dart'
    show FaceDirection;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_playback_engine.dart';

/// 「贴纸几何（单指移 + 双指等比缩放）」widget 缝直测：
/// 窗内播放态、选中态的贴纸主体接单指平移与双指等比缩放（像素 → 归一化
/// 换算按内容矩形、钳制在模块内单点收口）；未选中 / 编辑态（readOnly）
/// 不接手势；手势中出窗走会话结束路径收口（恰一个撤销步）。
void main() {
  const contentRect = Rect.fromLTWH(0, 0, 800, 600);

  late ProviderContainer container;
  late NoteStickerOverlayRegistration registration;

  NoteGeometry geometry() =>
      container.read(noteStickersProvider).single.geometry;

  int historyLength() =>
      container.read(annotationEditHistoryProvider).length;

  Future<void> pumpHost(
    WidgetTester tester, {
    int positionMs = 3000,
    Rect rect = contentRect,
    bool readOnly = false,
    FaceDirection faceDirection = FaceDirection.original,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              NoteStickerOverlay(
                positionMs: positionMs,
                contentRect: rect,
                faceDirection: faceDirection,
                registration: registration,
                readOnly: readOnly,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    container = ProviderContainer(
      overrides: [
        playbackEngineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
    );
    container
        .read(annotationEditorProvider)
        .restoreDocument(
          const AnnotationRestoreDocument(
            notes: [NoteSticker(startMs: 1000, endMs: 5000, text: '这里注意手')],
          ),
        );
    registration = NoteStickerOverlayRegistration();
  });

  tearDown(() => container.dispose());

  group('单指拖动平移（播放态 + 选中态）', () {
    testWidgets('贴纸主体随手指平移：归一化中心按内容矩形换算，一次手势一个撤销步',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();

      final start = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(start);
      await tester.pump();
      // 先越过识别 slop，再施平移量（识别起点的位移不计入会话基准）。
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final after = geometry();
      expect(after.centerX, greaterThan(noteDefaultCenterX + 40 / 800));
      expect(after.centerY, greaterThan(noteDefaultCenterY + 24 / 600));
      expect(after.scale, noteDefaultScale);
      // 一次手势 = 恰一个撤销步；undo 逐位回放。
      expect(historyLength(), 1);
      container.read(annotationEditorProvider).undo();
      expect(geometry(), const NoteGeometry());
    });

    testWidgets('随面：镜像下贴纸仍跟手指走（屏幕向右 = 贴纸向右）',
        (tester) async {
      // 镜像下屏幕位置 = 1 − 归一化 x：手指向右时归一化 x 必须变小，
      // 渲染才向右。屏幕增量 → 归一化增量按面方向反相一次。
      await pumpHost(tester, faceDirection: FaceDirection.mirrored);
      registration.select();
      await tester.pump();

      final before = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(before);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(56, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      // 归一化中心向左移（屏幕向右），贴纸渲染位置随手指向右。
      expect(geometry().centerX, lessThan(noteDefaultCenterX));
      expect(geometry().centerX, lessThan(noteDefaultCenterX - 40 / 800));
      final after = tester.getRect(find.byType(NoteStickerText)).center;
      expect(after.dx - before.dx, greaterThan(60));
      expect(after.dy, moreOrLessEquals(before.dy, epsilon: 0.01));
      expect(historyLength(), 1);
    });

    testWidgets('拖回原位收口：无净变化、无撤销步', (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();

      final start = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(start);
      await tester.pump();
      // 首个越 slop 的位移整段计入会话（识别点 = 落点）——位移全部取
      // 25px 的整数倍：25/800 = 1/32 在二进制浮点下精确，净位移 0 时
      // 几何逐位回到原值。
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(25, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-50, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(historyLength(), 0);
    });

    testWidgets('未选中：贴纸不接手势（穿透，几何与历史不动）', (tester) async {
      await pumpHost(tester);
      final before = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(before);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(geometry(), const NoteGeometry());
      expect(historyLength(), 0);
    });

    testWidgets('编辑态（readOnly）：选中态也不接手势（纯展示）', (tester) async {
      await pumpHost(tester, readOnly: true);
      registration.select();
      await tester.pump();

      final before = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(before);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(geometry(), const NoteGeometry());
      expect(historyLength(), 0);
    });
  });

  group('双指等比缩放（字号随整体缩放承担）', () {
    testWidgets('双指张开：等比系数放大、渲染字号随之；一次手势一个撤销步',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();

      final center = tester.getRect(find.byType(NoteStickerText)).center;
      final g1 = await tester.startGesture(center - const Offset(24, 0));
      final g2 = await tester.startGesture(center + const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();

      expect(geometry().scale, greaterThan(1.0),
          reason: '双指张开等比放大');
      // 双指起手瞬间焦点中点可有微小漂移（两指识别起点不完全对称），中心
      // 只断言未离开邻域；等比放大本身不受影响。
      expect(geometry().centerX, closeTo(noteDefaultCenterX, 0.1));
      expect(historyLength(), 1);
      // 字号由贴纸整体缩放承担：渲染字号大于基准字号。
      final fontSize =
          tester.widget<Text>(find.byType(Text).first).style?.fontSize;
      expect(fontSize, greaterThan(kNoteStickerBaseFontSize));
    });
  });

  group('转屏粘附与手势中出窗', () {
    testWidgets('转屏（内容矩形变化）后贴纸粘在画面同一点（归一化中心不变）',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();
      final start = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final dragged = geometry();
      // 竖屏内容矩形：同一归一化几何 → 相对位置逐位不变。
      const portrait = Rect.fromLTWH(0, 0, 600, 800);
      await pumpHost(tester, rect: portrait);
      final rendered = tester.getRect(find.byType(NoteStickerText)).center;
      expect(
        (rendered.dx - portrait.left) / portrait.width,
        closeTo(dragged.centerX, 0.01),
      );
      expect(
        (rendered.dy - portrait.top) / portrait.height,
        closeTo(dragged.centerY, 0.01),
      );
    });

    testWidgets('几何交叉断言：角落 + 大系数下模块几何与渲染像素一致收敛',
        (tester) async {
      // 模块单点钳制把中心钳进 [0,1]、系数钳进具名界（读回落点即模块
      // 几何）；渲染侧把像素矩形完整收进内容矩形——两层口径在此交叉。
      await pumpHost(tester);
      container.read(annotationEditorProvider).submit(
            const SetNoteGeometry(
              index: 0,
              geometry: NoteGeometry(centerX: 0.99, centerY: 0.99, scale: 99),
            ),
          );
      await pumpHost(tester);

      final geometryAfter = geometry();
      // 中心 0.99 本就在归一化域内原样保留；系数 99 钳到具名上界。
      expect(geometryAfter, const NoteGeometry(
        centerX: 0.99,
        centerY: 0.99,
        scale: noteMaxScale,
      ));
      final rendered = tester.getRect(find.byType(NoteStickerText));
      // 渲染像素矩形完整落在内容矩形内（角工具恒可达）。
      expect(rendered.left >= contentRect.left, isTrue);
      expect(rendered.top >= contentRect.top, isTrue);
      expect(rendered.right <= contentRect.right, isTrue);
      expect(rendered.bottom <= contentRect.bottom, isTrue);
      // 渲染字号随模块几何系数放大（基准 24 × noteMaxScale）：填充层与描边层
      // 同源基准样式，两层都必须是该字号。
      final scaledTexts = tester
          .widgetList<Text>(
            find.byWidgetPredicate((w) => w is Text && w.style?.fontSize != null),
          )
          .toList();
      expect(
        scaledTexts.map((text) => text.style!.fontSize).toSet(),
        {kNoteStickerBaseFontSize * noteMaxScale},
      );
    });

    testWidgets('手势进行中播放头出窗：会话走结束路径收口（净变化照常提交）',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();
      final start = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();

      // 播放头出窗（宿主换播放头重建 → 注册表注销 + 会话中断）。
      await pumpHost(tester, positionMs: 5000);
      expect(registration.selected, isFalse);
      // 净变化照常提交：恰一个撤销步。
      expect(historyLength(), 1);
      expect(find.byType(NoteStickerText), findsNothing);
      await gesture.up();
    });
  });

  group('内容锁：贴纸几何手势起手静默不参与', () {
    setUp(() {
      container
          .read(annotationEditorProvider)
          .restoreDocument(
            const AnnotationRestoreDocument(
              notes: [
                NoteSticker(
                  startMs: 1000,
                  endMs: 5000,
                  text: '这里注意手',
                  locked: true,
                ),
              ],
            ),
          );
    });

    testWidgets('已锁贴纸单指平移起手静默：几何与历史不动、不弹提示',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();

      final promptCount = container.read(noticeTriggerProvider(NoticeId.noteContentLock));
      final start = tester.getRect(find.byType(NoteStickerText)).center;
      final gesture = await tester.startGesture(start);
      await tester.pump();
      await gesture.moveBy(const Offset(24, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(60, 48));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(geometry(), const NoteGeometry(), reason: '已锁贴纸平移不起手');
      expect(historyLength(), 0);
      expect(
        container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
        promptCount,
        reason: '起手静默不参与：不弹「备注已锁定」提示',
      );
    });

    testWidgets('已锁贴纸双指缩放起手静默：系数与历史不动、不弹提示',
        (tester) async {
      await pumpHost(tester);
      registration.select();
      await tester.pump();

      final promptCount = container.read(noticeTriggerProvider(NoticeId.noteContentLock));
      final center = tester.getRect(find.byType(NoteStickerText)).center;
      final g1 = await tester.startGesture(center - const Offset(24, 0));
      final g2 = await tester.startGesture(center + const Offset(24, 0));
      await tester.pump(const Duration(milliseconds: 200));
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      await g1.up();
      await g2.up();
      await tester.pump();

      expect(geometry().scale, noteDefaultScale, reason: '已锁贴纸缩放不起手');
      expect(historyLength(), 0);
      expect(
        container.read(noticeTriggerProvider(NoticeId.noteContentLock)),
        promptCount,
        reason: '缩放起手同样静默：不弹提示（入口判定一致）',
      );
    });
  });
}
