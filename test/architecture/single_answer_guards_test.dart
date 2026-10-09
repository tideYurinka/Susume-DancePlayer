import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 「同一事实只写一遍」的源码护栏（票 #44）：
///
/// - **投屏态某一枚遥控项显不显示**只有一个回答处
///   （`castRemoteItemShownProvider`）：接收端能力判据只在投屏运行域被读，
///   手势层（进度 / 播放暂停 / 音量三段手势）与控制层（两枚控件在不在装配里）
///   读的是同一个 provider；
/// - **投屏入口的判定**只在入口那一处算（`cast_entry_gate.dart`）：顶栏不为
///   置灰把 verdict 重跑一遍，置灰观感与可点性出自同一次判定求值；
/// - **顶栏行集取道**只在会话模式声明表一处（`session_mode_surfaces.dart`）：
///   消费点读声明表那一行，不自己认得那几份具名行集。
///
/// 三条都是「仓库里的声明事实」；跑起来的行为由 `cast_mode_test.dart` 与
/// `session_mode_surfaces_test.dart` 各自钉住。
void main() {
  test('投屏态遥控项显示只有一个回答处：手势层与控制层读同一份', () {
    final holders = libDartFilesWhere(
      (source) => codeLinesOf(source).contains('castRemoteControlsProvider'),
      except: 'lib/player/cast_run.dart',
    )..sort();

    expect(
      holders,
      isEmpty,
      reason: '冒出第二个读接收端能力判据的地方：$holders（界面只问 castRemoteItemShownProvider）',
    );

    final readers = libDartFilesWhere(
      (source) => codeLinesOf(source).contains('castRemoteItemShownProvider'),
      except: 'lib/player/cast_run.dart',
    )..sort();

    expect(readers, [
      'lib/player/control_layer.dart',
      'lib/player/player_page.dart',
    ], reason: '「非投屏恒显示」的短路只有判据里那一处，读到它的只有手势层与控制层：$readers');
  });

  test('投屏入口的判定只在入口那一处算：顶栏不为置灰重跑一遍', () {
    final hits = libDartFilesWhere(
      (source) => codeLinesOf(source).contains('castEntryVerdict'),
      except: 'lib/player/cast_entry_gate.dart',
    )..sort();

    expect(
      hits,
      isEmpty,
      reason:
          '冒出第二处判定求值：$hits（顶栏读 playToolAvailability 的同一次判定，'
          '置灰观感与可点性出自它一次）',
    );
  });

  test('顶栏行集只有声明表一处取道：消费点不自己认得那几份行集', () {
    final hits = libDartFilesWhere((source) {
      final code = codeLinesOf(source);
      return code.contains('kPlayToolRowLandscapeTopBar') ||
          code.contains('kPlayToolRowPortraitTitleBar') ||
          code.contains('kPlayToolRowCastTopBar');
    })..sort();

    expect(hits, [
      'lib/player/play_tool_table.dart',
      'lib/player/session_mode_surfaces.dart',
    ], reason: '冒出第三个认得顶栏行集的文件：$hits（取道归模式声明表，消费点读它那一行）');
  });
}
