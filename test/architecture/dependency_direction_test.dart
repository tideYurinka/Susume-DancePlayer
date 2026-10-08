import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../helpers/source_guard.dart';

/// 依赖方向护栏：域层不 import 播放页，播放页是唯一的组合根。
///
/// 读源码的 import 边（相对路径与 package 路径都归一成 lib 下的目标路径），
/// 落成三条结构性断言：
/// - 域层（持久化/标注/基础/节拍/统计/计划/舞库/更新/打包/投屏）不得
///   import `lib/player/**`；
/// - `lib/core` 不得 import 其他上下文目录（唯一豁免是 `annotation/
///   annotation_timeline.dart` 这一纯值类型，由
///   `core/playback/seek_submitter.dart` 的注入签名消费；`player_session` /
///   `beat_track_state` / `surface_direction` 三个单文件小模块按现状豁免，
///   当前 core 未 import 它们）；
/// - `lib/annotation` 不得 import `persistence` / `player`。
///
/// `lib/home` 到 `lib/player` 只有页面导航边与一处 scrub 边（见
/// [_homeAllowedPlayerImports] 的逐文件登记）。

const _contexts = [
  'persistence',
  'annotation',
  'core',
  'beat',
  'stats',
  'plan',
  'dance',
  'update',
  'package',
  'cast',
];

/// `lib/home` 允许的 player import：页面导航（打开播放页 / 组员方案 / 命名）
/// 与 `cover_picker_page` 的 scrub 链路（`ScrubSession` 依赖播放呈现层的
/// `GestureFeedbackController` 类型，仍住 `lib/player`）。打开一支舞的唯一
/// 入口（`dance_open.dart`：副本在场进播放页、副本丢失进找回面）是同一类
/// 导航边。
const _homeAllowedPlayerImports = <String, Set<String>>{
  'lib/home/home_page.dart': {'lib/player/player_page.dart'},
  'lib/home/dance_detail_page.dart': {
    'lib/player/player_page.dart',
    'lib/player/scheme_open.dart',
    'lib/player/song_naming.dart',
  },
  'lib/home/dance_open.dart': {
    'lib/player/player_page.dart',
    'lib/player/scheme_open.dart',
  },
  'lib/home/cover_picker_page.dart': {'lib/player/scrub_session.dart'},
};

/// `lib/core` 允许的跨上下文目标（单文件纯值/小模块豁免）。
const _coreAllowedCrossContext = <String>{
  'lib/annotation/annotation_timeline.dart',
  'lib/player_session/',
  'lib/beat_track_state/',
  'lib/surface_direction/',
};

Iterable<String> _libDartFiles() sync* {
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      yield entity.path.replaceAll(r'\', '/');
    }
  }
}

/// import 串 → lib 下的目标路径；外部包与 dart: 返回 null。
String? _targetOf(String filePath, String import) {
  if (import.startsWith('dart:') || import.startsWith('package:flutter')) {
    return null;
  }
  if (import.startsWith('package:dance_learning_app/')) {
    return 'lib/${import.substring('package:dance_learning_app/'.length)}';
  }
  if (import.startsWith('package:')) return null;
  return p.normalize(p.join(p.dirname(filePath), import)).replaceAll(r'\', '/');
}

/// 目标路径所属的上下文目录名（`lib/<主模块>/...`）；不在上下文内返回 null。
String? _contextOf(String target) {
  final parts = target.split('/');
  if (parts.length < 3 || parts.first != 'lib') return null;
  return parts[1];
}

List<String> _violations({
  required bool Function(String file, String target) forbidden,
  String? onlyContext,
}) {
  final hits = <String>[];
  for (final file in _libDartFiles()) {
    final context = _contextOf(file);
    if (onlyContext != null && context != onlyContext) continue;
    for (final import in dartImportsOf(file)) {
      final target = _targetOf(file, import);
      if (target == null) continue;
      if (forbidden(file, target)) hits.add('$file → $target');
    }
  }
  return hits;
}

void main() {
  test('扫描面非空：lib 下能读到 dart 文件与 import 边', () {
    final files = _libDartFiles().toList();
    expect(files, isNotEmpty, reason: '扫描不到 lib 源码，护栏自身已失效');
    expect(
      files.any((f) => dartImportsOf(f).isNotEmpty),
      isTrue,
      reason: '读不到任何 import 边，护栏自身已失效',
    );
  });

  test('域层不 import lib/player/**', () {
    final violations = _violations(
      forbidden: (file, target) =>
          _contexts.contains(_contextOf(file)) &&
          target.startsWith('lib/player/'),
    );
    expect(violations, isEmpty, reason: '域层不得 import 播放页：$violations');
  });

  test('lib/core 只 import 允许的跨上下文目标', () {
    final violations = _violations(
      onlyContext: 'core',
      forbidden: (file, target) {
        if (!target.startsWith('lib/')) return false;
        if (_contextOf(target) == 'core' || _contextOf(target) == null) {
          return false;
        }
        return !_coreAllowedCrossContext.any(target.startsWith);
      },
    );
    expect(violations, isEmpty, reason: 'core 不得 import 其他上下文目录：$violations');
  });

  test('lib/annotation 不 import persistence / player', () {
    final violations = _violations(
      onlyContext: 'annotation',
      forbidden: (file, target) =>
          target.startsWith('lib/persistence/') ||
          target.startsWith('lib/player/'),
    );
    expect(violations, isEmpty, reason: '标注层不得 import 持久化/播放页：$violations');
  });

  test('lib/home 到 lib/player 只有登记的导航/scrub 边', () {
    final violations = <String>[];
    for (final file in _libDartFiles()) {
      if (_contextOf(file) != 'home') continue;
      final allowed = _homeAllowedPlayerImports[file] ?? const <String>{};
      for (final import in dartImportsOf(file)) {
        final target = _targetOf(file, import);
        if (target == null || !target.startsWith('lib/player/')) continue;
        if (!allowed.contains(target)) violations.add('$file → $target');
      }
    }
    expect(violations, isEmpty, reason: 'home 到播放页出现未登记的 import：$violations');
  });
}
