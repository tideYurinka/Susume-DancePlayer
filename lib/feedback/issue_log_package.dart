/// 问题日志包组装：把用户的回答、设备信息
/// 与日志目录装成一个 zip，交给系统分享面板由用户自己发给作者。**不复用
/// susume 容器**——那份自述清单与包格式版本门是给标注方案用的，诊断包是
/// 一次性消耗品，读它的是人和它的 Agent，不是 App。
///
/// 包内布局（对读包的人的契约）：
///
/// ```
/// susume-logs-<yyyyMMdd-HHmmss>.zip
/// ├── issue.txt   问题描述等小节（空节不写）；末尾「附带的数据」列出勾选的舞
/// ├── device.json
/// ├── dances.json 仅当勾了舞：[{ title, videoId, markers? }]；markers 是该舞的公开标记文件原文
/// └── logs/log.txt / logs/log.1.txt（存在才放）
/// ```
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/stored_zip.dart';
import 'device_snapshot.dart';
import 'issue_log_sink.dart'
    show
        kIssueLogCurrentFileName,
        kIssueLogDirectoryName,
        kIssueLogPreviousFileName,
        twoDigit;

/// 包内条目名（写读两处共用，模块外不出现字面量）。
const String kIssueReportEntry = 'issue.txt';
const String kIssueDeviceEntry = 'device.json';
const String kIssueDancesEntry = 'dances.json';

/// 用户勾选要附带的一支舞：标题、视频标识，以及公开标记文件原文。
/// 三者都是**完全公开**字段——本地文档那一批**完全私密**字段与媒体文件绝不
/// 进包。[markers] 为 null = 该舞还没有公开标记文件，此时不内联
/// 空壳。
class IssueDanceAttachment {
  const IssueDanceAttachment({
    required this.title,
    required this.videoId,
    this.markers,
  });

  /// 标题（署名优先、显示名兜底，与舞库读面同源）。
  final String title;

  /// 视频标识（内容哈希）。
  final String videoId;

  /// 公开标记文件原文（含节拍网格、分段线、首尾、半拍线、局部镜像片段、
  /// 备注、署名与镜像开关）；无文件时为 null。
  final Map<String, dynamic>? markers;

  /// `dances.json` 里一项的写向：确有原文才带 `markers`——无文件（null）或
  /// 空文件（`{}`）都不内联空壳。
  Map<String, Object?> toJson() => {
    'title': title,
    'videoId': videoId,
    if (markers != null && markers!.isNotEmpty) 'markers': markers,
  };
}

/// 包内日志条目的目录前缀；与落盘目录同名（`logs/`）。
const String kIssueLogsEntryPrefix = '$kIssueLogDirectoryName/';

/// issue.txt 各节的小标题；表单页的字段标签与包内小节同源，两处不出现第二份
/// 字面量。
const String kIssueSectionDescription = '问题描述';
const String kIssueSectionReproduce = '如何复现';
const String kIssueSectionActual = '实际表现';
const String kIssueSectionExpected = '期望表现';
const String kIssueSectionFrequency = '出现频率';

/// 包文件名：`susume-logs-<yyyyMMdd-HHmmss>.zip`（本地时间）。
String issueLogPackageFileName({required DateTime now}) {
  final stamp =
      '${now.year.toString().padLeft(4, '0')}${twoDigit(now.month)}'
      '${twoDigit(now.day)}-${twoDigit(now.hour)}${twoDigit(now.minute)}'
      '${twoDigit(now.second)}';
  return 'susume-logs-$stamp.zip';
}

/// issue.txt 正文（只装问题描述与末尾的「附带的数据」）：每节 =
/// 小标题 + 用户原文，留空的小节不
/// 写——包里不留空壳。[dances] 为空时不写「附带的数据」节。
String buildIssueReportText({
  required String description,
  String reproduce = '',
  String actual = '',
  String expected = '',
  String frequency = '',
  List<IssueDanceAttachment> dances = const [],
}) {
  final sections = <String>[];
  void add(String title, String body) {
    if (body.trim().isEmpty) return;
    sections.add('## $title\n$body');
  }

  add(kIssueSectionDescription, description);
  add(kIssueSectionReproduce, reproduce);
  add(kIssueSectionActual, actual);
  add(kIssueSectionExpected, expected);
  add(kIssueSectionFrequency, frequency);
  // 「附带的数据」必须留在最后一个 add：其余回答插在它之前，本节才始终
  // 是末尾一节。
  add(
    '附带的数据',
    [for (final dance in dances) '- ${dance.title}（${dance.videoId}）']
        .join('\n'),
  );
  return sections.join('\n\n');
}

/// 组装一份问题日志包到 [outputDir]，返回落盘文件。
///
/// [device] 是设备信息五项；[logDirectory] 是日志落盘件的目录，其中
/// `log.txt` 为当前份、`log.1.txt` 为上一份（存在才放）。没有任何日志行
/// 时 `logs/` 为空，包照常产出。
///
/// [dances] 是用户勾选要附带的舞（按列表次序），各舞连自己的公开标记文件
/// 原文一起进包；为空则不放 `dances.json`、`issue.txt` 也不写「附带的数据」节。
Future<File> assembleIssueLogPackage({
  required Directory outputDir,
  required String description,
  String reproduce = '',
  String actual = '',
  String expected = '',
  String frequency = '',
  required DeviceSnapshot device,
  required Directory logDirectory,
  required DateTime now,
  List<IssueDanceAttachment> dances = const [],
}) async {
  await outputDir.create(recursive: true);
  final output = File(
    p.join(outputDir.path, issueLogPackageFileName(now: now)),
  );

  final entries = <StoredZipEntry>[
    (
      name: kIssueReportEntry,
      bytes: utf8.encode(
        buildIssueReportText(
          description: description,
          reproduce: reproduce,
          actual: actual,
          expected: expected,
          frequency: frequency,
          dances: dances,
        ),
      ),
      file: null,
    ),
    (
      name: kIssueDeviceEntry,
      bytes: utf8.encode(jsonEncode(device.toJson())),
      file: null,
    ),
    if (dances.isNotEmpty)
      (
        name: kIssueDancesEntry,
        bytes: utf8.encode(
          jsonEncode([for (final dance in dances) dance.toJson()]),
        ),
        file: null,
      ),
  ];
  for (final name in [kIssueLogCurrentFileName, kIssueLogPreviousFileName]) {
    final file = File(p.join(logDirectory.path, name));
    if (!await file.exists()) continue;
    entries.add((name: '$kIssueLogsEntryPrefix$name', bytes: null, file: file));
  }
  await writeStoredZip(output, entries);
  return output;
}
