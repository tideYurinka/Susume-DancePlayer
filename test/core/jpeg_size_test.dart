import 'dart:typed_data';

import 'package:dance_learning_app/core/cover_frame.dart';
import 'package:dance_learning_app/core/jpeg_size.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/jpeg_bytes.dart';

/// JPEG 尺寸读取直测：从图片自身头部解出宽高——比例
/// 是图片自身的属性，不落盘尺寸字段。
void main() {
  test('竖屏封面：读出 540×720', () {
    expect(
      parseJpegSize(fakeJpegBytes(width: 540, height: 720)),
      const VideoFrameSize(width: 540, height: 720),
    );
  });

  test('横屏封面：读出 720×540', () {
    expect(
      parseJpegSize(fakeJpegBytes(width: 720, height: 540)),
      const VideoFrameSize(width: 720, height: 540),
    );
  });

  test('非 JPEG 字节：null', () {
    expect(parseJpegSize(Uint8List.fromList([1, 2, 3, 4])), isNull);
    expect(parseJpegSize(Uint8List(0)), isNull);
  });

  test('截断在尺寸之前：null', () {
    final full = fakeJpegBytes(width: 540, height: 720);
    // 切掉尺寸字段之后的全部字节仍应读不出（宽高不齐即 null）。
    expect(parseJpegSize(full.sublist(0, full.length - 11)), isNull);
    expect(parseJpegSize(full.sublist(0, 5)), isNull);
  });

  test('零尺寸：null（不是可渲染的封面）', () {
    expect(parseJpegSize(fakeJpegBytes(width: 0, height: 720)), isNull);
    expect(parseJpegSize(fakeJpegBytes(width: 540, height: 0)), isNull);
  });
}
