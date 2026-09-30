import 'package:dance_learning_app/annotation/dancer_roster.dart';
import 'package:dance_learning_app/annotation/note_sticker.dart';
import 'package:dance_learning_app/player/dancer_roster_controller.dart';
import 'package:dance_learning_app/persistence/video_document_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/video_document_write_test_helpers.dart';
import '../helpers/in_memory_video_document_storage.dart';

/// 名册直写控制器直测：增 / 删 / 改色经协调器整表补写落盘、
/// 重开还原一致、同名合并、改色修复历史重复项、只触碰名册段（不碰
/// notes / beat / corrections、不受内容锁影响）、不入撤销史（不经编辑
/// 模块）、写失败静默（内存态已更新）。
void main() {
  DancerRosterController makeController(InMemoryVideoDocumentStorage storage) =>
      DancerRosterController(coordinator: VideoDocumentCoordinator(storage));

  test('增：直写落盘、内存态同步', () async {
    final storage = InMemoryVideoDocumentStorage();
    final controller = makeController(storage);
    await controller.addDancer('果', color: 0xFFE53935);
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFFE53935),
    ]);
    expect(storage.markersSnapshot['roster']['dancers'], [
      {'name': '果', 'color': 0xFFE53935},
    ]);
  });

  test('删与改色：直写落盘', () async {
    final storage = InMemoryVideoDocumentStorage(
      markers: {
        'version': 8,
        'roster': {
          'dancers': [
            {'name': '果', 'color': 0xFFE53935},
            {'name': '鸟', 'color': 0xFF1E88E5},
          ],
        },
      },
    );
    final controller = makeController(storage);
    await controller.restore();
    await controller.changeColor('果', 0xFF43A047);
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFF43A047),
      DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
    ]);
    await controller.removeDancer('鸟');
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFF43A047),
    ]);
    expect(storage.markersSnapshot['roster']['dancers'], [
      {'name': '果', 'color': 0xFF43A047},
    ]);
  });

  test('同名合并：增已有名字不产生重复条目、颜色最新优先', () async {
    final storage = InMemoryVideoDocumentStorage(
      markers: {
        'version': 8,
        'roster': {
          'dancers': [
            {'name': '果', 'color': 0xFFE53935},
          ],
        },
      },
    );
    final controller = makeController(storage);
    await controller.restore();
    await controller.addDancer('果', color: 0xFF1E88E5);
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFF1E88E5),
    ]);
  });

  test('改色修复历史重复项：整表补写时同名去重', () async {
    final storage = InMemoryVideoDocumentStorage(
      markers: {
        'version': 8,
        'roster': {
          'dancers': [
            {'name': '果', 'color': 0xFFE53935},
            {'name': '鸟', 'color': 0xFF1E88E5},
            {'name': '果', 'color': 0xFF8E24AA},
          ],
        },
      },
    );
    final controller = makeController(storage);
    await controller.restore();
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFF8E24AA),
      DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
    ]);
    await controller.changeColor('鸟', 0xFF43A047);
    expect(storage.markersSnapshot['roster']['dancers'], [
      {'name': '果', 'color': 0xFF8E24AA},
      {'name': '鸟', 'color': 0xFF43A047},
    ]);
  });

  test('缺 markers / 缺 roster 段：按空还原、不崩', () async {
    final controller = makeController(InMemoryVideoDocumentStorage());
    await controller.restore();
    expect(controller.roster, isEmpty);
  });

  test('重开还原一致', () async {
    final storage = InMemoryVideoDocumentStorage();
    final first = makeController(storage);
    await first.addDancer('果', color: 0xFFE53935);
    await first.addDancer('鸟', color: 0xFF1E88E5);
    final reopened = makeController(storage);
    await reopened.restore();
    expect(reopened.roster, first.roster);
  });

  test('只触碰名册段：notes（含已锁备注）/ beat / corrections 原样', () async {
    const note = NoteSticker(
      startMs: 8000,
      endMs: 16000,
      text: '这里注意手',
      locked: true,
    );
    final storage = InMemoryVideoDocumentStorage();
    final seed = VideoDocumentCoordinator(storage);
    await seed.patchMarkers(
      (doc) => doc.withNotes(const [note]).withRoster(const [
        DancerRosterEntry(name: '果', color: 0xFFE53935),
      ]),
    );
    final controller = makeController(storage);
    await controller.restore();
    await controller.addDancer('鸟', color: 0xFF1E88E5);
    final after = VideoDocumentCoordinator(storage);
    final doc = await after.readMarkers();
    // 已锁备注不被名册直写触碰；名册条目照常更新（不受任何锁影响）。
    expect(doc.notes, const [note]);
    expect(doc.roster, const [
      DancerRosterEntry(name: '果', color: 0xFFE53935),
      DancerRosterEntry(name: '鸟', color: 0xFF1E88E5),
    ]);
  });

  test('写失败静默：内存态已更新、不抛错', () async {
    final storage = InMemoryVideoDocumentStorage()..corruptMarkers();
    final controller = makeController(storage);
    await controller.addDancer('果', color: 0xFFE53935);
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFFE53935),
    ]);
  });

  test('空名 / 纯空白名不写入', () async {
    final storage = InMemoryVideoDocumentStorage();
    final controller = makeController(storage);
    await controller.addDancer('   ', color: 0xFFE53935);
    expect(controller.roster, isEmpty);
    expect(storage.markersSnapshot.containsKey('roster'), isFalse);
  });

  test('名字净化对称：增带首尾空白，删 / 改色按净化后名字匹配', () async {
    final storage = InMemoryVideoDocumentStorage();
    final controller = makeController(storage);
    await controller.addDancer('  果  ', color: 0xFFE53935);
    expect(controller.roster.single.name, '果');
    await controller.changeColor(' 果 ', 0xFF43A047);
    expect(controller.roster.single.color, 0xFF43A047);
    await controller.removeDancer(' 果 ');
    expect(controller.roster, isEmpty);
  });

  test('快速连续操作：在途整表补写串行落盘、最新优先不被交错打破', () async {
    final storage = InMemoryVideoDocumentStorage();
    final controller = makeController(storage);
    // 不等待第一次写完成即发起第二次（UI 快速连续操作口径）。
    final first = controller.addDancer('果', color: 0xFFE53935);
    final second = controller.changeColor('果', 0xFF43A047);
    await first;
    await second;
    expect(storage.markersSnapshot['roster']['dancers'], [
      {'name': '果', 'color': 0xFF43A047},
    ], reason: '后完成的补写携带最新终值，先完成的旧值不回卷');
  });

  test('协调器缺位（未接持久化的环境）：内存态生效、不抛错', () async {
    final controller = DancerRosterController();
    await controller.addDancer('果', color: 0xFFE53935);
    expect(controller.roster, const [
      DancerRosterEntry(name: '果', color: 0xFFE53935),
    ]);
  });

  test('名册只读面是直写控制器现值的活投影：增 / 改色 / 删都立刻反映', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(dancerRosterControllerProvider);
    expect(container.read(dancerRosterProvider), isEmpty);

    // 增：立刻出现（既有备注里对应的 `@名字` 由此点亮）。
    await controller.addDancer('果', color: 0xFFE53935);
    expect(container.read(dancerRosterProvider), const [
      DancerRosterEntry(name: '果', color: 0xFFE53935),
    ]);

    // 改色：立刻换色。
    await controller.changeColor('果', 0xFF43A047);
    expect(container.read(dancerRosterProvider).single.color, 0xFF43A047);

    // 删：立刻失色。
    await controller.removeDancer('果');
    expect(container.read(dancerRosterProvider), isEmpty);
  });
}
