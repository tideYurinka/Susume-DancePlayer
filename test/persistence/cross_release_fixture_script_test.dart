import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/generate_cross_release_fixtures.dart' as generator;

/// 夹具生成脚本的机械性 + 幂等（缝 3：发布时顺手多一格证据）。
void main() {
  final committedFloor = Directory(
    '${generator.crossReleaseFixturesRoot}/${generator.floorRelease}',
  );
  final generatedReleases = generator.crossReleaseReleases
      .where((release) => release != generator.floorRelease)
      .toList();
  final docCount = committedFloor.listSync().whereType<File>().length;

  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('cross-release-fixtures-');
  });

  tearDown(() => temp.deleteSync(recursive: true));

  String fileNameOf(File file) => file.path.split(Platform.pathSeparator).last;

  /// 把已提交的地板夹具（手钉，脚本只读）铺进临时仓库。
  void seedFloorFixtures() {
    final target = Directory(
      '${temp.path}/${generator.crossReleaseFixturesRoot}/'
      '${generator.floorRelease}',
    )..createSync(recursive: true);
    for (final file in committedFloor.listSync().whereType<File>()) {
      File('${target.path}/${fileNameOf(file)}')
          .writeAsStringSync(file.readAsStringSync());
    }
  }

  Directory generatedDir(String release) =>
      Directory('${temp.path}/${generator.crossReleaseFixturesRoot}/$release');

  test('按版本网格产出全部格子，且与提交的夹具逐字节一致', () {
    seedFloorFixtures();

    final written = generator.generateCrossReleaseFixtures(
      repositoryRoot: temp,
    );

    expect(written, hasLength(generatedReleases.length * docCount));
    expect(
      written.where((path) => path.contains('/${generator.floorRelease}/')),
      isEmpty,
      reason: '地板夹具一次性手钉，脚本不得重写',
    );

    for (final release in generator.crossReleaseReleases) {
      final committed = Directory(
        '${generator.crossReleaseFixturesRoot}/$release',
      );
      for (final file in committed.listSync().whereType<File>()) {
        final generated = File(
          '${generatedDir(release).path}/${fileNameOf(file)}',
        );
        expect(
          generated.existsSync(),
          isTrue,
          reason: '$release/${fileNameOf(file)}',
        );
        expect(
          generated.readAsStringSync(),
          file.readAsStringSync(),
          reason: '$release/${fileNameOf(file)} 与提交夹具不一致',
        );
      }
    }
  });

  test('同一 tag 上重复生成幂等：第二次不重写任何文件', () {
    seedFloorFixtures();
    for (final release in generatedReleases) {
      generator.generateCrossReleaseFixtures(
        repositoryRoot: temp,
        releaseSelection: {release},
      );
    }
    Map<String, DateTime> modifiedTimes() => {
      for (final release in generatedReleases)
        for (final file in generatedDir(release).listSync().whereType<File>())
          file.path: file.lastModifiedSync(),
    };
    final before = modifiedTimes();
    expect(before, hasLength(generatedReleases.length * docCount));

    generator.generateCrossReleaseFixtures(repositoryRoot: temp);

    expect(modifiedTimes(), before, reason: '重复运行不得重写内容一致的文件');
  });

  test('只选一个发布版时只写该版', () {
    seedFloorFixtures();
    final release = generatedReleases.last;

    final written = generator.generateCrossReleaseFixtures(
      repositoryRoot: temp,
      releaseSelection: {release},
    );

    expect(written, hasLength(docCount));
    expect(written.every((path) => path.contains('/$release/')), isTrue);
    expect(generatedDir(generatedReleases.first).existsSync(), isFalse);
    expect(
      generatedDir(release).listSync().whereType<File>(),
      hasLength(docCount),
    );
  });
}
