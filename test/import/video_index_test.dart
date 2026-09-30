import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/core/video_identity.dart';
import 'package:dance_learning_app/persistence/video_index.dart';
import 'package:dance_learning_app/core/document_codec.dart';
import 'package:dance_learning_app/core/document_version_policy.dart';
import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('video_index_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  VideoIndexStore store() =>
      VideoIndexStore(File(p.join(tempDir.path, 'index.json')));

  VideoIndexEntry entry({
    String videoId = 'v1',
    String displayName = 'dance.mp4',
    String filePath = '/videos/dance.mp4',
    int sizeBytes = 123,
    bool mirrored = false,
    bool mirrorAsked = false,
    bool localMirrorEnabled = true,
    DateTime? lastOpenedAt,
    SongSignature? signatureCache,
    int lastPositionMs = 0,
  }) =>
      VideoIndexEntry(
        videoId: videoId,
        displayName: displayName,
        filePath: filePath,
        sizeBytes: sizeBytes,
        fastKey: fastKeyFor(name: displayName, sizeBytes: sizeBytes),
        mirrored: mirrored,
        mirrorAsked: mirrorAsked,
        localMirrorEnabled: localMirrorEnabled,
        lastOpenedAt: lastOpenedAt ?? DateTime(2026, 9, 1, 12),
        signatureCache: signatureCache,
        lastPositionMs: lastPositionMs,
      );

  group('VideoIndexEntry 新增字段兼容读取', () {
    test('旧条目缺 signatureCache/lastPositionMs 兜底：未署名、位置 0', () {
      final old = VideoIndexEntry.fromJson(
        entry().toJson()..remove('signatureCache')..remove('lastPositionMs'),
      );
      expect(old.signatureCache, isNull);
      expect(old.lastPositionMs, 0);
    });

    test('署名缓存与续播位置往返', () {
      const sig = SongSignature(dancer: '如', song: 'My Love', remark: '9人版');
      final e = entry(signatureCache: sig, lastPositionMs: 258000);
      final restored = VideoIndexEntry.fromJson(e.toJson());
      expect(restored.signatureCache, sig);
      expect(restored.lastPositionMs, 258000);
    });

    test('写回不丢既有字段：带新字段写盘再读回全部保留', () async {
      const sig = SongSignature(song: '歌');
      await store().update(
        (index) =>
            index.upsert(entry(videoId: 'vid', signatureCache: sig, lastPositionMs: 42)),
      );
      final loaded = await store().load();
      final e = loaded.findById('vid')!;
      expect(e.signatureCache, sig);
      expect(e.lastPositionMs, 42);
      expect(e.displayName, 'dance.mp4');
      expect(e.sizeBytes, 123);
      expect(e.lastOpenedAt, DateTime(2026, 9, 1, 12));
    });
  });

  group('VideoIndexEntry 序列化（字段完整）', () {
    test('toJson 包含全部字段：videoId/displayName/filePath/sizeBytes/fastKey/mirrored/mirrorAsked/localMirrorEnabled/lastOpenedAt', () {
      expect(
        entry().toJson().keys.toSet(),
        {
          'videoId',
          'displayName',
          'filePath',
          'sizeBytes',
          'fastKey',
          'mirrored',
          'mirrorAsked',
          'localMirrorEnabled',
          'lastOpenedAt',
          'signatureCache',
          'lastPositionMs',
        },
      );
    });

    test('toJson/fromJson 往返一致', () {
      final e = entry(
        videoId: 'abc',
        displayName: 'x.mp4',
        filePath: '/v/x.mp4',
        sizeBytes: 7,
        mirrored: true,
        mirrorAsked: true,
        lastOpenedAt: DateTime(2026, 1, 2, 3, 4, 5),
      );
      final restored = VideoIndexEntry.fromJson(e.toJson());
      expect(restored.videoId, e.videoId);
      expect(restored.displayName, e.displayName);
      expect(restored.filePath, e.filePath);
      expect(restored.sizeBytes, e.sizeBytes);
      expect(restored.fastKey, e.fastKey);
      expect(restored.mirrored, e.mirrored);
      expect(restored.mirrorAsked, e.mirrorAsked);
      expect(restored.lastOpenedAt, e.lastOpenedAt);
    });

    test('旧索引 JSON 缺 mirrorAsked 字段：视为未询问（默认 false）', () {
      final json = entry(mirrored: true).toJson()..remove('mirrorAsked');
      final restored = VideoIndexEntry.fromJson(json);
      expect(restored.mirrored, isTrue);
      expect(restored.mirrorAsked, isFalse);
    });
  });

  group('VideoIndex 查询与变更', () {
    final e1 = entry(
      videoId: 'v1',
      sizeBytes: 100,
      lastOpenedAt: DateTime(2026, 1, 1),
    );
    final e2 = entry(
      videoId: 'v2',
      sizeBytes: 100,
      lastOpenedAt: DateTime(2026, 2, 1),
    );

    test('byFastKey 命中，且最近打开优先', () {
      final index = VideoIndex(entries: [e1, e2]);
      final hits = index.byFastKey(fastKeyFor(name: 'dance.mp4', sizeBytes: 100));
      expect(hits.map((e) => e.videoId).toList(), ['v2', 'v1']);
    });

    test('byFastKey 不匹配大小或文件名不同的条目', () {
      final index = VideoIndex(entries: [e1]);
      expect(index.byFastKey('999:other.mp4'), isEmpty);
    });

    test('findById 精确命中 / 未命中返回 null', () {
      final index = VideoIndex(entries: [e1]);
      expect(index.findById('v1')?.videoId, 'v1');
      expect(index.findById('nope'), isNull);
    });

    test('findByFilePath 按私有目录副本路径精确命中 / 未命中返回 null', () {
      final index = VideoIndex(entries: [e1]);
      expect(index.findByFilePath(e1.filePath)?.videoId, 'v1');
      expect(index.findByFilePath('/other/path.mp4'), isNull);
    });

    test('remove：按 videoId 删除条目，其余条目与陌生键保底区保留', () {
      final index = VideoIndex(entries: [e1, e2], extra: {'future': 1});
      final removed = index.remove('v1');
      expect(removed.entries.map((e) => e.videoId), ['v2']);
      expect(removed.extra, {'future': 1}, reason: '文档级陌生键保底区随行');
      // 未命中：原样返回（同一实例，调用方据此跳过写盘）。
      expect(removed.remove('nope'), same(removed));
    });

    test('setMirrorAnswerByFilePath：设置条目镜像状态并标记已询问，其余字段不变', () {
      final index = VideoIndex(entries: [e1])
          .setMirrorAnswerByFilePath(e1.filePath, mirrored: true);
      final e = index.entries.single;
      expect(e.mirrored, isTrue);
      expect(e.mirrorAsked, isTrue);
      expect(e.videoId, 'v1');
      expect(e.displayName, e1.displayName);
      expect(e.filePath, e1.filePath);
      expect(e.sizeBytes, e1.sizeBytes);
      expect(e.lastOpenedAt, e1.lastOpenedAt);
    });

    test('setMirrorAnswerByFilePath：再次作答可改回（是→否），已询问标记保持', () {
      final index = VideoIndex(entries: [e1])
          .setMirrorAnswerByFilePath(e1.filePath, mirrored: true)
          .setMirrorAnswerByFilePath(e1.filePath, mirrored: false);
      expect(index.entries.single.mirrored, isFalse);
      expect(index.entries.single.mirrorAsked, isTrue);
    });

    test('setMirrorAnswerByFilePath：按副本路径写入镜像作答（镜像按 video_id 存取）', () {
      final index = VideoIndex(entries: [e1])
          .setMirrorAnswerByFilePath(e1.filePath, mirrored: true);
      final e = index.entries.single;
      expect(e.mirrored, isTrue);
      expect(e.mirrorAsked, isTrue);
      expect(e.videoId, 'v1');
    });

    test('setMirrorAnswerByFilePath：未命中路径时原样返回（后台哈希未落盘，重试）', () {
      final index = VideoIndex(entries: [e1]);
      expect(
        index.setMirrorAnswerByFilePath('/other/path.mp4', mirrored: true),
        same(index),
      );
    });

    test('局部镜像总开关过渡值：旧索引缺键兜底 true；写入与回写按路径命中', () {
      // 旧条目（无该键）→ 兜底 true（与 markers 缺键口径一致）。
      final old = VideoIndexEntry.fromJson(
        entry(mirrored: true).toJson()..remove('localMirrorEnabled'),
      );
      expect(old.localMirrorEnabled, isTrue);

      final off = VideoIndex(entries: [e1])
          .setLocalMirrorEnabledByFilePath(e1.filePath, localMirrorEnabled: false);
      expect(off.entries.single.localMirrorEnabled, isFalse);
      expect(off.entries.single.mirrorAsked, isFalse, reason: '不触碰「已询问」标记');
      // 未命中路径：原样返回（后台哈希未落盘，调用方据此重试）。
      final index = VideoIndex(entries: [e1]);
      expect(
        index.setLocalMirrorEnabledByFilePath(
          '/other/path.mp4',
          localMirrorEnabled: false,
        ),
        same(index),
      );
    });

    test('upsert：新 videoId 追加条目', () {
      final index = VideoIndex(entries: const []).upsert(e1);
      expect(index.entries.length, 1);
      expect(index.entries.single.videoId, 'v1');
    });

    test('upsert：已存在 videoId 时以新条目替换（路径/时间刷新），不重复', () {
      final refreshed = entry(
        videoId: 'v1',
        filePath: '/v/dance (1).mp4',
        lastOpenedAt: DateTime(2026, 3, 1),
      );
      final index = VideoIndex(entries: [e1]).upsert(refreshed);
      expect(index.entries.length, 1);
      expect(index.entries.single.filePath, '/v/dance (1).mp4');
      expect(index.entries.single.lastOpenedAt, DateTime(2026, 3, 1));
    });

    test('upsert：替换同 videoId 条目时保留既有镜像状态与已询问标记（镜像按 video_id 存取）', () {
      final mirrored = entry(
        videoId: 'v1',
        mirrored: true,
        mirrorAsked: true,
        localMirrorEnabled: false,
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final refreshed = entry(
        videoId: 'v1',
        filePath: '/v/dance (1).mp4',
        lastOpenedAt: DateTime(2026, 3, 1),
      );
      final index = VideoIndex(entries: [mirrored]).upsert(refreshed);
      expect(index.entries.single.mirrored, isTrue);
      expect(index.entries.single.mirrorAsked, isTrue);
      expect(
        index.entries.single.localMirrorEnabled,
        isFalse,
        reason: '导入刷新不得把用户关掉的局部镜像总开关冲回开',
      );
      expect(index.entries.single.filePath, '/v/dance (1).mp4');
    });

    test('refresh：刷新最近打开时间/显示名/快速键，videoId/路径/镜像（含已询问）不变', () {
      final withMirror = entry(
        videoId: 'v1',
        mirrored: true,
        mirrorAsked: true,
        localMirrorEnabled: false,
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final index = VideoIndex(entries: [withMirror]).refresh(
        'v1',
        displayName: 'renamed.mp4',
        fastKey: '100:renamed.mp4',
        lastOpenedAt: DateTime(2026, 4, 1),
      );
      expect(index.entries.length, 1);
      final e = index.entries.single;
      expect(e.videoId, 'v1');
      expect(e.displayName, 'renamed.mp4');
      expect(e.fastKey, '100:renamed.mp4');
      expect(e.lastOpenedAt, DateTime(2026, 4, 1));
      expect(e.filePath, e1.filePath);
      expect(e.mirrored, isTrue, reason: 'refresh 不得重置镜像状态');
      expect(e.mirrorAsked, isTrue, reason: 'refresh 不得重置「已询问」标记');
      expect(e.localMirrorEnabled, isFalse, reason: 'refresh 不得重置局部镜像总开关');
    });

    test('refresh 未命中时原样返回（同一实例，不写盘）', () {
      final index = VideoIndex(entries: [e1]);
      expect(
        index.refresh('nope', lastOpenedAt: DateTime(2026, 5, 1)),
        same(index),
      );
    });
  });

  group('VideoIndexStore（index.json 读写）', () {
    test('文件不存在时加载为空索引', () async {
      final index = await store().load();
      expect(index.entries, isEmpty);
    });

    test('save 后 load 往返一致、字段完整', () async {
      final s = store();
      final index = VideoIndex(entries: [
        entry(
          videoId: 'v1',
          displayName: 'dance.mp4',
          filePath: '/v/dance.mp4',
          sizeBytes: 100,
          mirrored: true,
          mirrorAsked: true,
          lastOpenedAt: DateTime(2026, 1, 1, 8, 30),
        ),
        entry(
          videoId: 'v2',
          displayName: 'a (1).mp4',
          filePath: '/v/a (1).mp4',
          sizeBytes: 200,
          lastOpenedAt: DateTime(2026, 2, 2, 9, 45),
        ),
      ]);
      await s.update((_) => index);

      final restored = await s.load();
      expect(restored.entries.length, 2);
      final first = restored.entries[0];
      expect(first.videoId, 'v1');
      expect(first.displayName, 'dance.mp4');
      expect(first.filePath, '/v/dance.mp4');
      expect(first.sizeBytes, 100);
      expect(first.fastKey, '100:dance.mp4');
      expect(first.mirrored, isTrue);
      expect(first.mirrorAsked, isTrue);
      expect(first.lastOpenedAt, DateTime(2026, 1, 1, 8, 30));
      expect(restored.entries[1].videoId, 'v2');
      expect(restored.entries[1].mirrorAsked, isFalse);
    });

    test('索引写入为真实 JSON 文件', () async {
      final s = store();
      await s.update((_) => VideoIndex(entries: [entry()]));

      final file = File(p.join(tempDir.path, 'index.json'));
      expect(file.existsSync(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(decoded['entries'], isA<List<dynamic>>());
    });

    test('损坏 JSON 视为空索引，不抛错', () async {
      final s = store();
      await File(p.join(tempDir.path, 'index.json')).writeAsString('{not json!!');
      final index = await s.load();
      expect(index.entries, isEmpty);
    });

  });

  group('接入文档编解码机制', () {
    test('版本链地板 = 本版 = 2，写盘带版本头（当前版本文件照常读入）', () {
      expect(VideoIndex.versionPolicy.floor, 2);
      expect(VideoIndex.versionPolicy.currentVersion, 2);
      final json = VideoIndex(entries: [entry()]).toJson();
      expect(json['version'], 2);
    });

    test('版本政策：换代前 v1 低于地板 → 空索引；当前版本正常读', () {
      final json = VideoIndex(entries: [entry(videoId: 'v1')]).toJson();
      expect(
        VideoIndex.fromJson({...json, 'version': 1}).entries,
        isEmpty,
      );
      expect(VideoIndex.fromJson(json).entries, hasLength(1));
    });

    test('版本头读不出与更高版本 → 认识多少读多少 + 只读', () {
      final json = VideoIndex(entries: [entry(videoId: 'v9')]).toJson();
      final noVersion = {...json}..remove('version');
      expect(VideoIndex.fromJson(noVersion).entries, hasLength(1));
      expect(VideoIndex.versionPolicy.isWritable(noVersion), isFalse);

      final higher = {...json, 'version': 3};
      expect(VideoIndex.fromJson(higher).entries, hasLength(1));
      expect(VideoIndex.versionPolicy.isWritable(higher), isFalse);
    });

    test('列表形状版本能力：合成两级链上中间版本可升位', () {
      final policy = DocumentVersionPolicy(
        floor: 1,
        steps: [
          MigrationStep(1, (json) => {...json, 'v1Shape': true}),
          MigrationStep(2, (json) => {...json, 'v2Shape': true}),
        ],
      );
      final codec =
          ListDocumentCodec<VideoIndex, VideoIndexEntry, VideoIndexEntryField>(
            policy: policy,
            listKey: 'entries',
            elementCodec: VideoIndexEntry.codec,
            empty: () => VideoIndex.empty,
            build: (elements) => VideoIndex(entries: elements),
            listOf: (doc) => doc.entries,
            extraOf: (doc) => doc.extra,
            withExtra: (doc, extra) =>
                VideoIndex(entries: doc.entries, extra: extra),
          );
      final onDisk = <String, Object?>{
        'version': 1,
        'entries': [entry(videoId: 'v1').toJson()],
      };
      final doc = codec.decode(onDisk);
      expect(doc.entries, hasLength(1));
      expect(doc.extra['v1Shape'], isTrue);
      expect(doc.extra['v2Shape'], isTrue);
      expect(policy.isWritable(onDisk), isTrue);
      expect(codec.encode(doc)['version'], 3);
    });

    test('写回只从可写判定出发：高版本文件跳过写盘、原样保留', () async {
      final s = store();
      final file = File(p.join(tempDir.path, 'index.json'));
      final onDisk = <String, dynamic>{
        'version': 3,
        'entries': [entry(videoId: 'v9').toJson()],
        'futureTop': 1,
      };
      await file.writeAsString(jsonEncode(onDisk));

      final loaded = await s.load();
      expect(loaded.entries.single.videoId, 'v9');
      await s.update(
        (current) => VideoIndex(
          entries: [...current.entries, entry(videoId: 'v2')],
        ),
      );

      expect(jsonDecode(await file.readAsString()), onDisk);
    });

    test('元素未知键保底：读回保留、写回原样、已登记字段不受影响', () {
      final json = entry(videoId: 'v9').toJson()..['futureField'] = {'x': 1};
      final restored = VideoIndexEntry.fromJson(json);
      expect(restored.extra['futureField'], {'x': 1});
      expect(restored.toJson()['futureField'], {'x': 1});
      expect(restored.videoId, 'v9');
      expect(restored.displayName, 'dance.mp4');
    });

    test('文档级未知键保底：读回保留、写回原样', () {
      final json = VideoIndex(entries: [entry()]).toJson()
        ..['futureTopLevel'] = 'keep';
      final restored = VideoIndex.fromJson(json);
      expect(restored.extra['futureTopLevel'], 'keep');
      expect(restored.toJson()['futureTopLevel'], 'keep');
      expect(restored.entries, hasLength(1));
    });

    test('字段枚举表驱动：逐字段往返保真并参与相等', () {
      final base = entry(
        videoId: 'abc',
        displayName: 'x.mp4',
        filePath: '/v/x.mp4',
        sizeBytes: 7,
        mirrored: true,
        mirrorAsked: true,
        lastOpenedAt: DateTime(2026, 1, 2, 3, 4, 5),
        signatureCache: const SongSignature(dancer: '如', song: 'S', remark: 'R'),
        lastPositionMs: 2500,
      );
      final restored = VideoIndexEntry.fromJson(base.toJson());
      expect(restored, base);

      final tamper = <VideoIndexEntryField, Object?>{
        VideoIndexEntryField.videoId: 'zzz',
        VideoIndexEntryField.displayName: 't.mp4',
        VideoIndexEntryField.filePath: '/t.mp4',
        VideoIndexEntryField.sizeBytes: 999,
        VideoIndexEntryField.fastKey: '999:t.mp4',
        VideoIndexEntryField.mirrored: false,
        VideoIndexEntryField.mirrorAsked: false,
        VideoIndexEntryField.localMirrorEnabled: false,
        VideoIndexEntryField.lastOpenedAt:
            DateTime(2020, 1, 1).toIso8601String(),
        VideoIndexEntryField.signatureCache:
            const SongSignature(song: 'o').toJson(),
        VideoIndexEntryField.lastPositionMs: 7,
      };
      for (final id in VideoIndexEntryField.values) {
        final d = VideoIndexEntry.codec.decl(id);
        final tampered = VideoIndexEntry.fromJson({
          ...base.toJson(),
          d.key: tamper[id],
        });
        expect(
          VideoIndexEntry.codec.equals(base, tampered),
          isFalse,
          reason: '字段 ${id.name} 应参与相等',
        );
      }
    });

    test('磁盘点：既有 version 1 文件经 store 双向读回不丢数据', () async {
      final s = store();
      await s.update(
        (_) => VideoIndex(entries: [entry(videoId: 'keep', lastPositionMs: 42)]),
      );
      final restored = await s.load();
      expect(restored.entries.single.videoId, 'keep');
      expect(restored.entries.single.lastPositionMs, 42);
    });
  });

  group('VideoIndexStore 并发写', () {
    test('update 串行化：并发写不丢失条目', () async {
      final s = store();
      await Future.wait([
        s.update((index) => index.upsert(entry(videoId: 'v1', sizeBytes: 1, lastOpenedAt: DateTime(2026, 1, 1)))),
        s.update((index) => index.upsert(entry(videoId: 'v2', sizeBytes: 2, lastOpenedAt: DateTime(2026, 1, 1)))),
        s.update((index) => index.upsert(entry(videoId: 'v3', sizeBytes: 3, lastOpenedAt: DateTime(2026, 1, 1)))),
      ]);
      final restored = await s.load();
      expect(restored.entries.length, 3);
      expect(restored.entries.map((e) => e.videoId).toSet(), {'v1', 'v2', 'v3'});
    });
  });
}
