import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// 解出一个 zip 的「条目名 → 字节」清单（问题日志包组装与表单递出两侧共用）。
Map<String, Uint8List> readZipEntries(String path) {
  final archive = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
  return {for (final file in archive.files) file.name: file.content};
}
