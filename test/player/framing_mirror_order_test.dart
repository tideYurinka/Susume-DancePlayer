import 'package:dance_learning_app/annotation/framing_selection.dart';
import 'package:dance_learning_app/player/framing_selection_view.dart';
import 'package:dance_learning_app/player/framing_session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// **上屏的先后**：翻转是画面件的显示层变换、取景是包在它外面的那层剪辑窗
/// （`picture_layer.dart` 的 `_SourceVideoSurface` 包在 `framing_selection_view.dart`
/// 里）——于是窗里那块像素是「**翻过的画面**在那块矩形上的样子」。
///
/// 这条口径是投屏取景窗口（#28）的**对齐对象**：`lib/cast/cast_framing_gate.dart`
/// 把裁切节点排在镜像节点之后，`test/cast/cast_framing_gate_test.dart` 按它逐帧
/// 同判。这里用**画出来的位置**（`getRect` 走绘制变换，含显示层翻转与取景缩放）
/// 把上屏那一份读出来，免得「手机显示是什么样」只在投屏侧的测试里以模型自证。
///
/// 读法：源画面竖着切成四条等宽色条，取景选区取**左半**（0–1/2）。若取景在
/// 翻转**之后**切窗（上屏的实际组合），窗里从左到右应是第 4 条与第 3 条
/// （源画面右半翻过来）；若取景在翻转**之前**切窗，窗里应是第 1 条与第 2 条。
void main() {
  const leftHalf = FramingSelection(left: 0, top: 0, right: 0.5, bottom: 1);

  /// 400×200 的画面区（宽高比 2 = 源画面宽高比，画面即整块舞台），
  /// 显示层翻转按开关落在树上（与生产路径同形：那层恒在，不翻转时缩放为 1）。
  Future<void> pumpPicture(WidgetTester tester, {required bool mirrored}) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          framingStateProvider.overrideWithBuild(
            (ref, _) => const FramingState(source: leftHalf),
          ),
        ],
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: const Key('stage'),
              width: 400,
              height: 200,
              child: FramingSelectionView(
                aspectRatio: 2,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(mirrored ? -1 : 1, 1, 1),
                  child: Row(
                    children: [
                      for (var stripe = 1; stripe <= 4; stripe++)
                        Expanded(
                          child: SizedBox.expand(
                            child: ColoredBox(
                              key: Key('stripe_$stripe'),
                              color: const Color(0xFF000000),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 取景后**画面矩形**（全局坐标）：取景窗把选区内容按 contain 装进舞台
  /// ——本用例的选区内容宽高比 = 1，舞台 400×200，故窗是居中的 200×200。
  Rect contentWindow(WidgetTester tester) {
    final stage = tester.getRect(find.byKey(const Key('stage')));
    return Rect.fromLTWH(stage.left + 100, stage.top, 200, 200);
  }

  /// 点落在哪一条色条上（读的是**画出来的**位置）。
  String stripeAt(WidgetTester tester, Offset point) {
    for (var stripe = 1; stripe <= 4; stripe++) {
      final rect = tester.getRect(find.byKey(Key('stripe_$stripe')));
      if (rect.contains(point)) return 'stripe_$stripe';
    }
    return 'none';
  }

  testWidgets('不翻转：窗里是源画面的左半（第 1 条 → 第 2 条）', (tester) async {
    await pumpPicture(tester, mirrored: false);
    await tester.pumpAndSettle();
    final window = contentWindow(tester);

    expect(
      stripeAt(tester, window.centerLeft + const Offset(10, 0)),
      'stripe_1',
    );
    expect(
      stripeAt(tester, window.centerRight - const Offset(10, 0)),
      'stripe_2',
    );
  });

  testWidgets('翻转：窗里是「翻过的画面」那一块（第 4 条 → 第 3 条）', (tester) async {
    await pumpPicture(tester, mirrored: true);
    await tester.pumpAndSettle();
    final window = contentWindow(tester);

    expect(
      stripeAt(tester, window.centerLeft + const Offset(10, 0)),
      'stripe_4',
      reason: '取景窗切在**翻过**的画面上：窗左是源画面最右那一条',
    );
    expect(
      stripeAt(tester, window.centerRight - const Offset(10, 0)),
      'stripe_3',
    );
  });
}
