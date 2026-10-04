import 'package:dance_learning_app/annotation/compare_materials.dart'
    show MaterialRecord, PracticeClip;
import 'package:dance_learning_app/player/annotation_editor.dart'
    show practiceClipsProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 练习片段表写面收口：库外只有三个具名写
/// 入口——装载（以文档值为准）/ 登记录制产出 / 按素材删除引用；编辑 verb
/// 与历史回放走库内私有写缝。装载与入轨经规范化落表：乱序或重叠输入落
/// 表后恒按源起点升序、两两不重叠。
void main() {
  late ProviderContainer container;

  PracticeClip clipAt(String id, int sourceStartMs, int sourceEndMs) =>
      PracticeClip(
        id: id,
        materialId: 'm_$id',
        materialSourceStartMs: sourceStartMs,
        inMs: 0,
        outMs: sourceEndMs - sourceStartMs,
        materialDurationMs: 60000,
      );

  MaterialRecord record(String id, int sourceStartMs) => MaterialRecord(
    id: id,
    videoId: 'v1',
    createdAt: DateTime(2026, 1, 1),
    durationMs: 10000,
    sourceStartMs: sourceStartMs,
    fileName: '$id.mp4',
    sizeBytes: 1,
  );

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  group('装载入口（以文档值为准）', () {
    test('读到文档后装载文档值；换会话空装载清空轨道', () {
      final docClips = [clipAt('c1', 0, 10000), clipAt('c2', 20000, 30000)];
      container.read(practiceClipsProvider.notifier).restore(docClips);
      expect(container.read(practiceClipsProvider), docClips);

      container.read(practiceClipsProvider.notifier).restore(const []);
      expect(container.read(practiceClipsProvider), isEmpty);
    });

    test('乱序或重叠输入装载落表后恒升序、两两不重叠', () {
      container.read(practiceClipsProvider.notifier).restore([
        clipAt('late', 40000, 50000),
        clipAt('early', 0, 25000),
        clipAt('mid', 20000, 30000),
      ]);
      final clips = container.read(practiceClipsProvider);
      expect(
        [for (final clip in clips) clip.id],
        ['early', 'mid', 'late'],
        reason: '升序落表；重叠的条目裁到不重叠（mid 钳到 early 边界）',
      );
      expect(clips[0].sourceStartMs, 0);
      expect(clips[0].sourceEndMs, 25000);
      expect(clips[1].sourceStartMs, 25000);
      expect(clips[1].sourceEndMs, 30000);
      expect(clips[2].sourceStartMs, 40000);
      for (var i = 1; i < clips.length; i++) {
        expect(
          clips[i].sourceStartMs,
          greaterThanOrEqualTo(clips[i - 1].sourceEndMs),
        );
      }
    });
  });

  group('登记录制产出入口', () {
    test('入轨先清理旧引用再登记新片段，落表恒升序、不重叠', () {
      // 既有片段起点晚于新片段：朴素追加会落成乱序——入轨经规范化收口。
      container.read(practiceClipsProvider.notifier).restore([
        clipAt('kept', 20000, 30000),
      ]);
      container
          .read(practiceClipsProvider.notifier)
          .addFromMaterial(record('m_new', 0), preambleMs: 0);

      final clips = container.read(practiceClipsProvider);
      expect(clips.first.id, 'clip_m_new');
      expect(clips.first.sourceStartMs, 0);
      expect(clips.last.id, 'kept', reason: '不重叠的既有引用保留');
      expect(
        clips.first.sourceStartMs <= clips.last.sourceStartMs,
        isTrue,
        reason: '落表恒按源起点升序',
      );
    });

    test('入轨清理被新片段覆盖/重叠的旧引用（口径不变）', () {
      container.read(practiceClipsProvider.notifier).restore([
        clipAt('covered', 0, 10000),
        clipAt('partial', 8000, 20000),
        clipAt('far', 30000, 40000),
      ]);
      container
          .read(practiceClipsProvider.notifier)
          .addFromMaterial(record('m_new', 0));
      final clips = container.read(practiceClipsProvider);
      expect(
        [for (final clip in clips) clip.id],
        ['clip_m_new', 'partial', 'far'],
      );
    });
  });

  group('按素材删除引用入口', () {
    test('移除引用该素材的全部轨道片段，其余原样', () {
      container.read(practiceClipsProvider.notifier).restore([
        clipAt('a', 0, 10000),
        clipAt('b', 20000, 30000),
      ]);
      container.read(practiceClipsProvider.notifier).removeByMaterial('m_a');
      expect(
        [for (final clip in container.read(practiceClipsProvider)) clip.id],
        ['b'],
      );
    });
  });
}
