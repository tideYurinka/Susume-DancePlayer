/// 「发送问题日志」表单页：问题描述必答，几个可选
/// 的结构化回答（如何复现、实际表现、期望表现、出现频率）可留空，可从舞库
/// 全部舞里多选要附带的舞（按最近打开倒序、标题署名优先显示名兜底），勾中的
/// 舞连它的公开标记文件一起进包；填好后打包成一份问题日志包，交给系统分享
/// 面板由用户自己发给作者。应用不留副本。
///
/// 必答校验沿本仓「灰着的入口按下去绝不执行动作，只告诉你原因」这条契约：
/// 描述为空时「发送」置灰但按得动，按下弹一句「先说说遇到了什么问题」，
/// 不发生递出。递出失败只出一句「日志包未递出」，不重试、不二次弹面板。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dance/dance_library.dart';
import '../dance/dance_library_providers.dart';
import '../persistence/video_document_providers.dart';
import '../persistence/video_document_store.dart';
import '../share/dance_share.dart' show susumeShareDirectoryProvider;
import '../share_channel/share_channel.dart';
import 'device_snapshot.dart';
import 'issue_log_package.dart';
import 'issue_log_sink.dart';

/// 表单页标题，同时是帮助文档动作区那枚钮的文案（两处同源）。
const String issueReportTitle = '发送问题日志';

/// 出现频率三档：三选一、默认不选。[id] 只用于控件 key，[label] 是写进
/// `issue.txt` 的正文。
const List<({String id, String label})> kIssueFrequencyOptions = [
  (id: 'every_time', label: '每次都出现'),
  (id: 'sometimes', label: '偶尔出现'),
  (id: 'only_once', label: '只出现过一次'),
];

/// 四个输入框里的灰字引导。它们只出现在界面上；写进 `issue.txt` 的小标题是
/// `kIssueSection*` 那一套——两处读者不同（一个是填表的人，一个是读包的
/// 作者与它的 Agent），故各用各的字串。必答与选填由标题后的（必填）/（可选）
/// 标出，引导句只讲该怎么写。
const String kIssueDescriptionHint = '说清你遇到了什么问题，例如「导入视频后一直转圈」';
const String kIssueReproduceHint = '从打开 App 到问题出现，按顺序一步步写';
const String kIssueActualHint = '你实际看到的是什么，例如报错文字、卡住的画面';
const String kIssueExpectedHint = '你以为应该是什么，例如「应该直接进播放页」';

class IssueReportPage extends ConsumerStatefulWidget {
  const IssueReportPage({super.key});

  @override
  ConsumerState<IssueReportPage> createState() => _IssueReportPageState();
}

class _IssueReportPageState extends ConsumerState<IssueReportPage> {
  final TextEditingController _description = TextEditingController();
  final TextEditingController _reproduce = TextEditingController();
  final TextEditingController _actual = TextEditingController();
  final TextEditingController _expected = TextEditingController();

  /// 出现频率当前档（null = 不选）。
  String? _frequency;

  /// 本次勾选要附带的舞（视频标识集合）。
  final Set<String> _selectedVideoIds = {};

  bool _sending = false;

  @override
  void dispose() {
    _description.dispose();
    _reproduce.dispose();
    _actual.dispose();
    _expected.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    final description = _description.text;
    if (description.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先说说遇到了什么问题')));
      return;
    }

    setState(() => _sending = true);
    try {
      // 日志落盘件是缓冲写：打包前先强制落地，包里才有刚产生的那些行。
      final sink = ref.read(issueLogSinkProvider);
      await sink.flush();
      final device = await ref.read(deviceSnapshotProvider.future);
      final dances = await _selectedDanceAttachments();
      final output = await assembleIssueLogPackage(
        outputDir: await ref.read(susumeShareDirectoryProvider.future),
        description: description,
        reproduce: _reproduce.text,
        actual: _actual.text,
        expected: _expected.text,
        frequency: _frequency ?? '',
        device: device,
        logDirectory: sink.directory,
        now: DateTime.now(),
        dances: dances,
      );
      await ref.read(shareChannelProvider).shareFile(output);
      if (!mounted) return;
      // 无论能不能 pop（本页可能是根）都要退出加载态，不把按钮永久留在
      // 「正在打包…」。
      setState(() => _sending = false);
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('日志包未递出')));
    }
  }

  /// 一个输入框连同它上方的标题行：标题左、必答的那枚红星右（问卷式），框里
  /// 的灰字是引导句——空框时一直看得见，写起来即消失。
  Widget _answer({
    required Key key,
    required TextEditingController controller,
    required String title,
    required String hint,
    bool isRequired = false,
    ValueChanged<String>? onChanged,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            if (isRequired) ...[
              const Spacer(),
              Semantics(
                label: '必答',
                child: Text(
                  '*',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: key,
          controller: controller,
          minLines: 4,
          maxLines: null,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  /// 把勾选的舞转成包组装的输入：每支都读一次公开标记文件的**可分享
  /// 投影**（无文件为 null，不内联空壳）；非可分享字段与未登记键一概不
  /// 流出，本地文档等**完全私密**字段不读。
  Future<List<IssueDanceAttachment>> _selectedDanceAttachments() async {
    final selected = [
      for (final dance in await _libraryDances())
        if (_selectedVideoIds.contains(dance.videoId)) dance,
    ];
    if (selected.isEmpty) return const [];
    final storageFor = ref.read(videoDocumentStorageFactoryProvider);
    return [
      for (final dance in selected)
        IssueDanceAttachment(
          title: dance.title,
          videoId: dance.videoId,
          markers: await storageFor(dance.videoId).loadShareableMarkersOrNull(),
        ),
    ];
  }

  /// 发送时取舞列表：等读面就绪再取（不因仍在装入而悄悄少带 `dances.json`）；
  /// 读面失败按空库兜底——包照常送出，诊断用途不因舞库故障而不成立。
  Future<List<DanceSnapshot>> _libraryDances() async {
    try {
      final library = await ref.read(danceLibrarySnapshotProvider.future);
      return dancesByRecentOpen(library.dances);
    } on Object {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasDescription = _description.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text(issueReportTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _answer(
              key: const Key('issue_report_description'),
              controller: _description,
              title: '$kIssueSectionDescription（必填）',
              hint: kIssueDescriptionHint,
              isRequired: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _answer(
              key: const Key('issue_report_reproduce'),
              controller: _reproduce,
              title: '$kIssueSectionReproduce（可选）',
              hint: kIssueReproduceHint,
            ),
            const SizedBox(height: 16),
            _answer(
              key: const Key('issue_report_actual'),
              controller: _actual,
              title: '$kIssueSectionActual（可选）',
              hint: kIssueActualHint,
            ),
            const SizedBox(height: 16),
            _answer(
              key: const Key('issue_report_expected'),
              controller: _expected,
              title: '$kIssueSectionExpected（可选）',
              hint: kIssueExpectedHint,
            ),
            const SizedBox(height: 16),
            Text(kIssueSectionFrequency, style: theme.textTheme.titleSmall),
            RadioGroup<String>(
              groupValue: _frequency,
              onChanged: (value) => setState(() => _frequency = value),
              child: Column(
                children: [
                  for (final option in kIssueFrequencyOptions)
                    RadioListTile<String>(
                      key: Key('issue_report_frequency_${option.id}'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(option.label),
                      value: option.label,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _danceSection(),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('issue_report_send'),
              // 打包期间不可重复触发；描述为空时不装死——灰着但按得动，
              // 按下由 [_submit] 给出原因。
              onPressed: _sending ? null : _submit,
              style: hasDescription
                  ? null
                  : FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.12,
                      ),
                      foregroundColor: theme.colorScheme.onSurface.withValues(
                        alpha: 0.38,
                      ),
                    ),
              child: Text(_sending ? '正在打包…' : '发送'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _danceSection() {
    // 读面未就绪（装入中）或失败时不把整块舞附件区藏掉——顶部「全选/清除」
    // 与那句灰字始终在场，只有列表区随读面出内容。
    final dances = ref.watch(danceLibrarySnapshotProvider).asData?.value.dances;
    final ordered = dances == null
        ? const <DanceSnapshot>[]
        : dancesByRecentOpen(dances);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('附带哪些舞', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            TextButton(
              key: const Key('issue_dance_select_all'),
              onPressed: () => setState(
                () => _selectedVideoIds
                  ..clear()
                  ..addAll([for (final dance in ordered) dance.videoId]),
              ),
              child: const Text('全选'),
            ),
            TextButton(
              key: const Key('issue_dance_clear'),
              onPressed: () => setState(_selectedVideoIds.clear),
              child: const Text('清除'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(
            '勾选的舞会连它的公开标记文件一起带走（含节拍网格、分段结构与备注文本）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        if (dances == null)
          const SizedBox.shrink()
        else if (dances.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('舞库里还没有舞'),
          )
        else
          for (final dance in ordered)
            CheckboxListTile(
              key: Key('issue_dance_${dance.videoId}'),
              value: _selectedVideoIds.contains(dance.videoId),
              onChanged: (checked) => setState(() {
                if (checked ?? false) {
                  _selectedVideoIds.add(dance.videoId);
                } else {
                  _selectedVideoIds.remove(dance.videoId);
                }
              }),
              title: Text(dance.title),
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
            ),
      ],
    );
  }
}
