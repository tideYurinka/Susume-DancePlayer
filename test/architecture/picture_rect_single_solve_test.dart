import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 「上屏画面矩形只剩一处解」的源码护栏（票 #45）。
///
/// 同一块画面矩形原先有三处求值（组合根的 scrub 取消区那个、投屏贴纸那个、
/// 演出层的注解层读数那个），还有两条不同的「宽高比未知」兜底——画面矩形一动
/// （竖屏骨架、取景、转屏）必有一处漏。收口之后：
///
/// - **单画面只有一处求解**：`framing_stage.dart` 的 `pictureRectOnScreen`（对比
///   路径仍是 `compare_framing_view.dart` 的 `compareFramingPictureRect` 那一份，
///   两条规则的求解各只一处）；
/// - **组合根只有一个入口**：`player_page.dart` 的 `_pictureRect` 分派两条纯件，
///   手势仲裁域、演出层现读闭包与投屏渲染装配都读它；
/// - **演出层不自解**：取消区标记、角落提示卡、备注贴纸落位与局部镜像标识都转发
///   那道 `Rect Function()` 闭包（`presentation_layer.dart` 里不得再出现 contain
///   算术或自己的「宽高比未知」兜底）。
void main() {
  const framingStage = 'lib/player/framing_stage.dart';
  const compareStage = 'lib/player/compare_framing_view.dart';
  const playerPage = 'lib/player/player_page.dart';
  const presentationLayer = 'lib/player/presentation_layer.dart';
  const framingSession = 'lib/player/framing_session.dart';

  test('单画面画面矩形只有一处求解点', () {
    expect(
      libDartFilesWhere(
        (source) => codeLinesOf(source).contains('Rect pictureRectOnScreen('),
      ),
      [framingStage],
    );
    expect(
      libDartFilesWhere(
        (source) =>
            codeLinesOf(source).contains('Rect compareFramingPictureRect('),
      ),
      [compareStage],
    );
  });

  test('两处旧解与「系统栏内可用区」那条兜底已不存在', () {
    for (final gone in const [
      'videoPictureRect',
      'singlePicturePictureRectOnScreen',
      'singlePictureFramedPictureRectOnScreen',
    ]) {
      expect(
        libDartFilesWhere((source) => codeLinesOf(source).contains(gone)),
        isEmpty,
        reason: '$gone 应已收进唯一求解点',
      );
    }
  });

  test('组合根只有一个画面矩形入口，三处读数与投屏装配都读它', () {
    final page = codeOf(playerPage);
    expect(RegExp(r'Rect _pictureRect\(').allMatches(page).length, 1);
    expect(RegExp(r'pictureRectOnScreen\(').allMatches(page).length, 1);
    expect(RegExp(r'compareFramingPictureRect\(').allMatches(page).length, 1);
    // 定义 + 手势仲裁域 + 演出层闭包 + 投屏渲染装配。
    expect(RegExp(r'pictureRect: _pictureRect\b').allMatches(page).length, 2);
    expect(page.contains('pictureRectOf: _pictureRect'), isTrue);
  });

  test('取景手势域的落点分母读同一处解', () {
    final session = codeOf(framingSession);
    expect(RegExp(r'pictureRectOnScreen\(').allMatches(session).length, 1);
    expect(
      RegExp(r'compareFramingPictureRect\(').allMatches(session).length,
      1,
    );
  });

  test('演出层不自解画面矩形：取消区、提示卡、贴纸与标识都转发那道闭包', () {
    final presentation = codeOf(presentationLayer);
    for (final forbidden in const [
      'videoContentRectInBox',
      'framedContentRectInStage',
      'compareFramingPictureRect',
      'singlePicture',
      'videoPictureRect',
    ]) {
      expect(
        presentation.contains(forbidden),
        isFalse,
        reason: '演出层不得自解画面矩形：$forbidden',
      );
    }
    // 标识落位、贴纸落位、提示卡锚点三处各自现读同一条闭包。
    expect(
      RegExp(r'input\.pictureRectOf\(\)').allMatches(presentation).length,
      3,
    );
    // 取消区标记经画面层反馈会话吃同一份（同一条闭包转交）。
    expect(
      RegExp(r'pictureRectOf: input\.pictureRectOf\b')
          .allMatches(presentation)
          .length,
      1,
    );
  });
}
