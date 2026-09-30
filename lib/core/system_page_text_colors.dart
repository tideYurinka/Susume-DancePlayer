/// 系统页文字对比度 token：播放器以外两处
/// 低对比文字的唯一取色来源——分享面板的包体警告与备份对话框的统计说明。
/// 取值是常量、不读 Theme.of（沿 `lib/player/visual_tokens.dart` 的取值
/// 哲学）；两色都用深档保持各自色相家族，对浅色系 surface 达到 4.5:1，
/// 达标由 `test/core/contrast_test.dart` 按共用纯函数断言。
library;

import 'package:flutter/material.dart';

/// 分享面板包体警告文字色（深橙档；原 `Colors.deepOrange` 压白底 3.16:1）。
const Color kShareWarningTextColor = Color(0xFFBF360C);

/// 备份对话框统计说明文字色（深绿档；原 `Colors.green` 压白底 2.78:1 且
/// 硬编码绕过 token）。
const Color kBackupNoteTextColor = Color(0xFF2E7D32);
