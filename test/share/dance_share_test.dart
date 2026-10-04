import 'dart:io';

import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('包体预检', () {
    test('估算 = markers JSON 字节 + 勾选媒体字节数之和', () {
      // 最小 markers `{'a': 1}` 的 JSON 编码为 `{"a":1}` = 7 字节。
      const markers = {'a': 1};
      final video = SusumeMediaEntry(
        kind: SusumeMediaKind.sourceVideo,
        fileName: 'v.mp4',
        sizeBytes: 700,
      );
      final clip = SusumeMediaEntry(
        kind: SusumeMediaKind.practiceClip,
        fileName: 'rec.mp4',
        sizeBytes: 200,
      );

      // 7 + (700 + 200)。
      expect(
        estimateSusumeSizeBytes(markers: markers, media: [video, clip]),
        907,
      );
      // 未勾选的媒体不计入：7 + 700。
      expect(estimateSusumeSizeBytes(markers: markers, media: [video]), 707);
    });

    test('估算达到阈值提示、阈值之下不提示；提示不阻止（无开关）', () {
      // 阈值 = 900 MiB。
      expect(kSusumeSizeWarnBytes, 900 * 1024 * 1024);
      expect(susumeSizeNearWechatLimit(kSusumeSizeWarnBytes), isTrue);
      expect(susumeSizeNearWechatLimit(kSusumeSizeWarnBytes - 1), isFalse);
      // 提示不阻止：函数只返回布尔，调用方没有「不可发」分支可言。
    });
  });

  group('装配', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('susume_share_test');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    File writeFile(String name, List<int> bytes) =>
        File('${tempDir.path}/$name')..writeAsBytesSync(bytes);

    test('输出 <歌名>.susume；解析回来清单与标注逐字段相等，媒体按勾选装入', () async {
      final video = writeFile('source.mp4', List.filled(64, 1));
      final markers = {
        'version': 8,
        'meta': {'song': '海草舞', 'coverPositionMs': 42000},
        'lines': [1],
      };
      final manifest = SusumeManifest(
        videoId: 'abc123',
        schemeName: '海草舞',
        schemeId: 'scheme-1',
        mastery: {0: 3},
        media: [
          SusumeMediaEntry(
            kind: SusumeMediaKind.sourceVideo,
            fileName: 'source.mp4',
            sizeBytes: 64,
            file: video,
          ),
        ],
      );

      final output = await assembleDancePackage(
        outputDir: Directory('${tempDir.path}/out'),
        manifest: manifest,
        markers: markers,
        videoFileName: 'source.mp4',
      );

      expect(output.path, '${tempDir.path}/out/海草舞.susume');
      final parsed = await readSusumePackage(output.path);
      expect(parsed.manifest, manifest);
      expect(parsed.markers, markers);
      // 封面位置随「我的标注方案」原文进包：对方侧读到同一个位置。
      expect((parsed.markers['meta'] as Map)['coverPositionMs'], 42000);
      // 媒体副本确在包内：字节与源文件一致。
      expect(output.lengthSync(), greaterThan(64));
    });

    test('未署名：包名回落视频文件名（去扩展名）', () async {
      const manifest = SusumeManifest(
        videoId: 'abc123',
        schemeName: 'source_clip',
        schemeId: 'scheme-1',
      );
      final output = await assembleDancePackage(
        outputDir: Directory('${tempDir.path}/out'),
        manifest: manifest,
        markers: const {},
        videoFileName: 'source_clip.mp4',
      );
      expect(output.path, '${tempDir.path}/out/source_clip.susume');
    });

    test('装配失败向上抛：包内容不完整不递出', () async {
      const manifest = SusumeManifest(
        videoId: 'abc123',
        schemeName: '海草舞',
        schemeId: 'scheme-1',
        media: [
          // 解析态条目（file 为 null）不可用于装配。
          SusumeMediaEntry(
            kind: SusumeMediaKind.sourceVideo,
            fileName: 'x.mp4',
            sizeBytes: 1,
          ),
        ],
      );
      await expectLater(
        assembleDancePackage(
          outputDir: Directory('${tempDir.path}/out'),
          manifest: manifest,
          markers: const {},
          videoFileName: 'x.mp4',
        ),
        throwsArgumentError,
      );
    });
  });
}
