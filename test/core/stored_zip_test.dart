import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dance_learning_app/core/stored_zip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stored_zip_test');
  });

  tearDown(() async => tempDir.delete(recursive: true));

  test('字节与文件条目按清单顺序 STORED 写出', () async {
    final source = File('${tempDir.path}/part.bin');
    await source.writeAsBytes(List<int>.generate(20000, (i) => i % 251));
    final output = File('${tempDir.path}/out.zip');

    await writeStoredZip(output, [
      (name: 'a.txt', bytes: utf8.encode('hello'), file: null),
      (name: 'media/part.bin', bytes: null, file: source),
      (name: 'b.json', bytes: utf8.encode('{"k":1}'), file: null),
    ]);

    final archive = ZipDecoder().decodeBytes(output.readAsBytesSync());
    expect(
      [for (final file in archive.files) file.name],
      ['a.txt', 'media/part.bin', 'b.json'],
    );
    for (final file in archive.files) {
      expect(file.compression, CompressionType.none, reason: file.name);
    }
    expect(utf8.decode(archive.files[0].content as List<int>), 'hello');
    expect(archive.files[1].content, await source.readAsBytes());
    expect(utf8.decode(archive.files[2].content as List<int>), '{"k":1}');
  });
}
