/// JPEG 尺寸读取：从图片自身头部解出宽高，供卡片按
/// 真实比例渲染封面——比例是图片自身的属性，不落盘任何尺寸字段。
/// 零 Flutter 纯件：输入字节、输出尺寸或 null。
library;

import 'dart:typed_data';

import 'cover_frame.dart' show VideoFrameSize;

/// 从 JPEG 字节读出画面尺寸；非 JPEG / 截断 / 非法尺寸返回 null。
///
/// 只扫到第一个 SOF 段（SOF0–SOF15，跳过 DHT/JPG/DAC 三个非尺寸段）即返回；
/// 之前的分段按长度跳过。找不到 SOF 或字节不足即 null。
VideoFrameSize? parseJpegSize(Uint8List bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    i += 2;
    // 填充字节：0xFF 后可跟多个 0xFF。
    if (marker == 0xFF) {
      i--;
      continue;
    }
    // 无长度字段的独立标记（TEM、RSTn、SOI、EOI）。
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD9)) {
      continue;
    }
    if (i + 1 >= bytes.length) return null;
    final length = (bytes[i] << 8) | bytes[i + 1];
    if (length < 2) return null;
    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 && // DHT
        marker != 0xC8 && // JPG
        marker != 0xCC; // DAC
    if (isSof) {
      if (i + 6 >= bytes.length) return null;
      final height = (bytes[i + 3] << 8) | bytes[i + 4];
      final width = (bytes[i + 5] << 8) | bytes[i + 6];
      if (width <= 0 || height <= 0) return null;
      return VideoFrameSize(width: width, height: height);
    }
    if (i + length > bytes.length) return null;
    i += length;
  }
  return null;
}
