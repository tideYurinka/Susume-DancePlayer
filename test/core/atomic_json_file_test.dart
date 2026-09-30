import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/core/atomic_json_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('atomic_json_file_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  AtomicJsonFile atomic([String name = 'data.json']) =>
      AtomicJsonFile(File(p.join(tempDir.path, name)));

  group('read', () {
    test('文件缺失兜底空 Map', () async {
      expect(await atomic().read(), isEmpty);
    });

    test('损坏 JSON 兜底空 Map（FormatException）', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString('{not json');
      expect(await atomic().read(), isEmpty);
    });

    test('顶层非对象兜底空 Map', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString('[1, 2]');
      expect(await atomic().read(), isEmpty);
    });

    test('正常 JSON 读回内容', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString(jsonEncode({'a': 1}));
      expect(await atomic().read(), {'a': 1});
    });
  });

  group('readOrNull', () {
    test('文件缺失返回 null', () async {
      expect(await atomic().readOrNull(), isNull);
    });

    test('损坏 JSON 返回 null（FormatException）', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString('{not json');
      expect(await atomic().readOrNull(), isNull);
    });

    test('顶层非对象返回 null', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString('[1, 2]');
      expect(await atomic().readOrNull(), isNull);
    });

    test('正常 JSON（含空对象）读回内容', () async {
      final empty = File(p.join(tempDir.path, 'empty.json'));
      await empty.writeAsString('{}');
      expect(await atomic('empty.json').readOrNull(), isEmpty);
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString(jsonEncode({'a': 1}));
      expect(await atomic().readOrNull(), {'a': 1});
    });
  });

  group('write', () {
    test('父目录不存在时递归创建', () async {
      final target = p.join(tempDir.path, 'nested', 'dir', 'data.json');
      await AtomicJsonFile(File(target)).write({'k': 'v'});
      expect(jsonDecode(await File(target).readAsString()), {'k': 'v'});
    });

    test('不残留 .tmp 文件', () async {
      await atomic().write({'k': 'v'});
      expect(
        tempDir.listSync().whereType<File>().map((f) => f.path),
        isNot(contains(endsWith('.tmp'))),
      );
    });
  });

  group('mutate', () {
    test('链内读改写：并发两次 mutate 均保留（无 lost-update）', () async {
      final a = atomic();
      await a.write({'count': 0});
      await Future.wait([
        a.mutate((m, {required bool present}) => m['a'] = 1),
        a.mutate((m, {required bool present}) => m['b'] = 2),
      ]);
      expect(await a.read(), {'count': 0, 'a': 1, 'b': 2});
    });

    test('串行：前一次写入对后一次可见', () async {
      final a = atomic();
      await a.mutate((m, {required bool present}) => m['first'] = true);
      await a.mutate((m, {required bool present}) {
        expect(m['first'], true);
        m['second'] = true;
      });
      expect(await a.read(), {'first': true, 'second': true});
    });

    test('存在位：文件不在 present=false，存在但内容为空对象 present=true', () async {
      final a = atomic();
      final seen = <bool>[];
      await a.mutate((m, {required bool present}) => seen.add(present));
      await a.write(const {});
      await a.mutate((m, {required bool present}) => seen.add(present));
      expect(seen, [false, true]);
    });

    test('未变更跳写：不落盘、不创建文件', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      final a = AtomicJsonFile(file);
      await a.mutate((_, {required bool present}) {});
      expect(file.existsSync(), isFalse);
      await a.write({'k': 1});
      final before = file.lastModifiedSync();
      await a.mutate((m, {required bool present}) {
        m['k'] = 1; // 写回同值：编码不变，跳过写盘。
      });
      expect(file.lastModifiedSync(), before);
    });

    test('mutate 内抛错：调用方收到错误且写链继续可用', () async {
      final a = atomic();
      await expectLater(
        a.mutate((_, {required bool present}) => throw StateError('boom')),
        throwsStateError,
      );
      await a.mutate((m, {required bool present}) => m['after'] = true);
      expect(await a.read(), {'after': true});
    });
  });

  group('delete', () {
    test('删除已存在文件与 .tmp 残留；重复删除缺失文件不抛错', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString(jsonEncode({'k': 1}));
      await File('${file.path}.tmp').writeAsString('{}');
      final a = AtomicJsonFile(file);

      await a.delete();

      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
      await a.delete(); // 文件已缺：视作已删，不抛错。
      expect(await a.read(), isEmpty);
    });

    test('并入写链：排在已排队的写之后（写完再删）', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      final a = AtomicJsonFile(file);

      final write = a.write({'k': 1});
      await a.delete();
      await write;

      expect(file.existsSync(), isFalse, reason: 'delete 排在 write 之后执行');
    });
  });

  group('write 链错误', () {
    test('写中途失败旧文件仍在（tmp+rename 原子性）', () async {
      final file = File(p.join(tempDir.path, 'data.json'));
      await file.writeAsString(jsonEncode({'old': true}));
      // .tmp 路径被目录占用 → tmp 写失败，rename 永不发生。
      await Directory('${file.path}.tmp').create();
      final a = AtomicJsonFile(file);
      await expectLater(
        a.write({'new': true}),
        throwsA(isA<FileSystemException>()),
      );
      expect(jsonDecode(await file.readAsString()), {'old': true});
    });

    test('写失败后写链不卡死：修复路径后续写成功', () async {
      // 父路径被同名文件占用 → create(recursive: true) 失败。
      final blocker = File(p.join(tempDir.path, 'blocked'));
      await blocker.writeAsString('x');
      final bad = AtomicJsonFile(File(p.join(blocker.path, 'data.json')));
      await expectLater(
        bad.write({'x': 1}),
        throwsA(isA<FileSystemException>()),
      );
      // 路径恢复后，同一实例的写链仍可用。
      await blocker.delete();
      await bad.write({'ok': true});
      expect(await bad.read(), {'ok': true});
    });
  });
}
