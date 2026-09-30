/// STORED zip 写出：条目一律不压缩，文件条目经 `InputFileStream` 分块搬运。
///
/// **大文件不进 Dart 堆**：DEFLATE 路径会把整条内容先读进内存再写出，媒体 /
/// 日志这类大条目会 OOM，故本件固定 `CompressionType.none`。条目按清单顺序
/// 写出，条目流句柄与输出流都在本件内关闭。
library;

import 'dart:io';

import 'package:archive/archive_io.dart';

/// 一个待写出条目：[bytes] 与 [file] 二选一，[file] 走流式。
typedef StoredZipEntry = ({String name, List<int>? bytes, File? file});

/// 把 [entries] 按清单顺序写成 STORED zip 到 [output]。
Future<void> writeStoredZip(File output, List<StoredZipEntry> entries) async {
  final out = OutputFileStream(output.path);
  try {
    final encoder = ZipEncoder()..startEncode(out);
    for (final entry in entries) {
      final file = entry.file;
      if (file == null) {
        encoder.add(
          ArchiveFile.bytes(entry.name, entry.bytes!)
            ..compression = CompressionType.none,
        );
        continue;
      }
      final stream = InputFileStream(file.path);
      try {
        encoder.add(
          ArchiveFile.stream(entry.name, stream)
            ..compression = CompressionType.none,
        );
      } finally {
        await stream.close();
      }
    }
    encoder.endEncode();
  } finally {
    await out.close();
  }
}
