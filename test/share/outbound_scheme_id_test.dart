import 'dart:io';

import 'package:dance_learning_app/share/outbound_scheme_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late File file;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('scheme_id_test');
    file = File('${tempDir.path}/scheme_ids.json');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('同一支舞反复取同一标识；不同舞标识不同', () async {
    final store = OutboundSchemeIdFileStore(file);
    final first = await store.idFor('video-a');
    expect(await store.idFor('video-a'), first);
    expect(await store.idFor('video-b'), isNot(first));
  });

  test('标识持久化：新开 store 实例读回同一标识', () async {
    final first = await OutboundSchemeIdFileStore(file).idFor('video-a');
    final second = await OutboundSchemeIdFileStore(file).idFor('video-a');
    expect(second, first);
  });

  test('文件损坏视作空态重建，不抛错', () async {
    await file.writeAsString('not json');
    final id = await OutboundSchemeIdFileStore(file).idFor('video-a');
    expect(id, isNotEmpty);
  });
}
