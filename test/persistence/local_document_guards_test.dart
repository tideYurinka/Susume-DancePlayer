import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_guard.dart';

/// 本地文档里**按舞记忆**的登记面护栏（`#47` 验收第 1 条，`#21` 整改补齐后半）：
/// 「新增一份按舞记忆的代价 = 一个键 + 一张字段表」。
///
/// 一个键 + 一张字段表 = 一条 `_MemoryDecl` + 登记表（`_memoryBindings`）里一行；
/// `prefs` 段那份编解码（读 / 写 / 判等 / 装配）与段值形状都读登记表，不再逐份
/// 记忆各占一个字段、一条声明分支与一处装配。这一条是**源码事实**，落成源码护栏
/// （与 `test/cast/cast_foundation_guards_test.dart` 同款范式）。
///
/// 编译器逐处强制的残留只剩两处，都绕不开：`LocalDocument` 上那个**类型化字段**
/// （记录 + 它的复制底座；字段级 API 保持形状）与 `_PrefsField` 里那个**同名
/// 取值**（`RecordCodec` 是一格一个键；穷尽 switch 的兜底臂据此认领它）。
void main() {
  test('prefs 段的记忆片读登记表：声明分支与装配不再逐份记忆各写一遍', () {
    final code = codeOf('lib/persistence/local_document.dart');

    expect(
      RegExp(r'_PrefsField\s*\.\s*(beatPrompt|castPrep)\s*=>\s*FieldDecl')
          .hasMatch(code),
      isFalse,
      reason: '记忆的读 / 写 / 判等由登记表派生：加一份记忆不必再加一条声明分支',
    );
    expect(
      RegExp(r'values\[_PrefsField\s*\.\s*(beatPrompt|castPrep)\]')
          .hasMatch(code),
      isFalse,
      reason: '记忆片的装配由登记表派生：加一份记忆不必再动 `_buildPrefs`',
    );
    expect(
      RegExp(r'_Memory<(BeatPromptMemoryFields|CastPrepMemoryFields)>')
          .hasMatch(code),
      isFalse,
      reason: '段值里只有一片「键 → 段值」的记忆表，不逐份记忆各占一个字段',
    );
    expect(
      code.contains('_memoryByKey[id.name]'),
      isTrue,
      reason: '护栏自身要扫到那一处（字段 id 的取值名就是记忆键名）',
    );
  });

  test('每份记忆仍只声明一次键与字段表：登记表不再抄一遍', () {
    final code = codeOf('lib/persistence/local_document.dart');

    for (final key in const ['beatPrompt', 'castPrep']) {
      expect(
        RegExp("key: '$key'").allMatches(code).length,
        1,
        reason: '$key：键只在它那份 `_MemoryDecl` 里声明（登记表拿的是现成的声明）',
      );
    }
  });
}
