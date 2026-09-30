import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../dance/dance_library_providers.dart' show invalidateDanceLibraryFrom;
import '../import/picked_video.dart';
import '../persistence/four_beat_bucket_providers.dart'
    show fourBeatBucketStoreProvider;
import '../persistence/practice_stats_providers.dart'
    show practiceStatsStoreProvider;
import 'package_picker.dart';
import 'scheme_import.dart';
import 'susume_package.dart';
import 'whole_machine_restore.dart';

/// 选包导入的页面流程（由首页 ⋯「恢复备份」进入）：
/// 选包后进 [runSchemeImportFlowWithFile]。
Future<void> runSchemeImportFlow(BuildContext context, WidgetRef ref) async {
  final picked = await ref.read(packagePickerProvider).pickPackage();
  if (picked == null || !context.mounted) return;
  await runSchemeImportFlowWithFile(context, ref, picked);
}

/// 选包导入流程的文件已定形态：解析取清单 →
/// 备份包分流到恢复 → 导入分支树问归属 → 组员名只在
/// 组员方案出口之后出现（发送方填过则预填）→ 导入编排 → 结果以短暂提示
/// 回报「谁、成了哪支舞的哪个方案（三种落点）」。主动选择（⋯「恢复备份」）
/// 与入站分享共用同一分流。
Future<void> runSchemeImportFlowWithFile(
  BuildContext context,
  WidgetRef ref,
  PickedVideo picked,
) async {
  final importer = ref.read(schemeImporterProvider);
  final SusumePackage package;
  try {
    package = await importer.readPackage(picked);
  } on SusumePackageException catch (error) {
    if (!context.mounted) return;
    _show(context, translateSusumePackageError(error));
    return;
  }
  if (!context.mounted) return;

  if (package.isBackup) {
    await _runRestoreFlow(context, ref, picked, package);
    return;
  }

  // 「包里没带源视频」先于归属选择：三分支一律拒绝，不弹任何面。
  if (!package.hasSourceVideo) {
    _show(context, schemeImportSourceVideoMissingMessage);
    return;
  }

  final danceExists = await importer.hasDance(package.manifest.videoId);
  if (!context.mounted) return;
  final branch = resolveImportBranch(
    danceExists: danceExists,
    packageHasMastery: package.manifest.mastery != null,
  );

  // 新舞没有旧标注可毁：直接建舞写成我的，不弹任何面；其余两分支各弹一张
  // 归属面（文案不同），由同一个出口折成 intent。
  final Widget? ownershipDialog = switch (branch) {
    SchemeImportBranch.createAsMine => null,
    SchemeImportBranch.askOwnership => _OwnershipDialog(
      schemeName: package.manifest.schemeName,
    ),
    // 建成我的标注方案：他带的熟练度快照丢弃（面里已写明）。
    SchemeImportBranch.askCreateOwnership => _CreateOwnershipDialog(
      schemeName: package.manifest.schemeName,
    ),
  };
  final intent = ownershipDialog == null
      ? const WriteAsMyMarkers()
      : await _askOwnershipIntent(context, ownershipDialog, package.manifest);
  if (intent == null) return;

  final outcome = await importer.importScheme(
    picked: picked,
    intent: intent,
    package: package,
    // 分支判定只查一次索引：以页面流程这次判定为准，编排不再重查。
    danceExists: danceExists,
  );
  if (!context.mounted) return;
  switch (outcome) {
    case SchemeImported(
      :final landing,
      :final memberName,
      :final danceTitle,
      :final createdDance,
      :final importedAt,
    ):
      invalidateDanceLibraryFrom(ref);
      _show(context, switch (landing) {
        SchemeImportLanding.writtenAsMine =>
          '${_when(importedAt)}已把 ${_who(memberName)} 的标注写成我的'
              '${createdDance ? "，新建舞「$danceTitle」" : "到「$danceTitle」"}',
        SchemeImportLanding.keptAsMemberScheme =>
          '${_when(importedAt)}已导入 ${_who(memberName)} 的方案到「$danceTitle」',
        SchemeImportLanding.createdAsMemberScheme =>
          '${_when(importedAt)}已导入 ${_who(memberName)} 的方案，'
              '新建舞「$danceTitle」',
      });
    case SchemeImportRejected(:final message):
      _show(context, message);
    case SchemeImportFailed(:final message):
      _show(context, message);
  }
}

/// 组员名对话框（只在组员方案出口之后出现）：发送方填过则预填；确认返回
/// 名字（可为空串），取消返回 null（什么都不做）。
Future<String?> _askMemberName(BuildContext context, SusumeManifest manifest) =>
    showDialog<String>(
      context: context,
      builder: (_) => _MemberNameDialog(manifest: manifest),
    );

/// 归属选择面的三分支出口：取消（面或组员名）返回 null = 什么都不做；选
/// 「写成我的」得 [WriteAsMyMarkers]；选组员方案则问组员名后得
/// [LandAsMemberScheme]。[dialog] 由调用方按分支给出，两个面文案不同。
Future<SchemeImportIntent?> _askOwnershipIntent(
  BuildContext context,
  Widget dialog,
  SusumeManifest manifest,
) async {
  final exit = await showDialog<_OwnershipExit>(
    context: context,
    builder: (_) => dialog,
  );
  if (exit == null || !context.mounted) return null;
  if (exit == _OwnershipExit.mine) return const WriteAsMyMarkers();
  final memberName = await _askMemberName(context, manifest);
  if (memberName == null || !context.mounted) return null;
  return LandAsMemberScheme(memberName);
}

String _who(String memberName) => memberName.isEmpty ? '未署名成员' : memberName;

/// 「什么时候」：导入时刻的时:分（提示即出即逝，当天时刻足够一眼核对）。
String _when(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')} ';

/// 恢复流程：确认面列出将发生什么 → 确认后
/// 留档 + 全量替换 → 结果以短暂提示回报。取消则什么都不做。
Future<void> _runRestoreFlow(
  BuildContext context,
  WidgetRef ref,
  PickedVideo picked,
  SusumePackage package,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => const _RestoreConfirmDialog(),
  );
  if (confirmed != true || !context.mounted) return;

  final outcome = await showDialog<RestoreOutcome>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RestoreProgressDialog(
      task: () => ref
          .read(wholeMachineRestorerProvider)
          .restore(
            package: package,
            packagePath: picked.sourceUri.toFilePath(),
          ),
    ),
  );
  if (outcome == null || !context.mounted) return;
  switch (outcome) {
    case RestoreCompleted():
      invalidateDanceLibraryFrom(ref);
      // 全量替换直写存储层，两个 store 的内存态随之作废：下次读重新自磁盘
      // 装入，恢复后的统计与桶当场可见。
      ref.invalidate(practiceStatsStoreProvider);
      ref.invalidate(fourBeatBucketStoreProvider);
      _show(context, '恢复完成，本机数据已替换为备份内容');
    case RestoreFailed(:final message):
      _show(context, message);
  }
}

/// 归属选择面的出口：写成我的（标注方案）或落成组员方案；取消以 null 表达。
enum _OwnershipExit { mine, member }

/// 恢复进行中：不可关的进度面——整机动数据期间不给第二条入口。任务完成
/// 即带着结果关闭。
class _RestoreProgressDialog extends StatefulWidget {
  const _RestoreProgressDialog({required this.task});

  final Future<RestoreOutcome> Function() task;

  @override
  State<_RestoreProgressDialog> createState() => _RestoreProgressDialogState();
}

class _RestoreProgressDialogState extends State<_RestoreProgressDialog> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final outcome = await widget.task();
      if (mounted) Navigator.pop(context, outcome);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在恢复…'),
            ],
          ),
        ),
      ),
    );
  }
}

/// 恢复确认面：把「将发生什么」逐条列出，用户知情后才动手。
class _RestoreConfirmDialog extends StatelessWidget {
  const _RestoreConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('restore_confirm_dialog'),
      title: const Text('恢复备份'),
      content: const Column(
        key: Key('restore_scope_list'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('· 本机全部数据将被备份包内容整体替换，不合并、不保留本机较新值'),
          SizedBox(height: 8),
          Text('· 替换前当前数据自动留一份档（应用目录「恢复留档」），可手动清'),
          SizedBox(height: 8),
          Text('· 练舞统计与四拍桶明细随包替换，不保留本机较新值'),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('restore_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('restore_confirm_button'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('开始恢复'),
        ),
      ],
    );
  }
}

void _show(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// 已有这支舞的归属选择面：两个出口加取消，取消即什么都不做、不落任何数据。
class _OwnershipDialog extends StatelessWidget {
  const _OwnershipDialog({required this.schemeName});

  final String schemeName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('scheme_import_ownership_dialog'),
      title: Text('导入「$schemeName」'),
      content: const Text('本机已有这支舞。他的标注要落成什么？'),
      actions: [
        TextButton(
          key: const Key('scheme_import_ownership_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('scheme_import_keep_as_member'),
          onPressed: () => Navigator.pop(context, _OwnershipExit.member),
          child: const Text('留成TA的方案'),
        ),
        FilledButton(
          key: const Key('scheme_import_write_as_mine'),
          onPressed: () => Navigator.pop(context, _OwnershipExit.mine),
          child: const Text('写成我的标注'),
        ),
      ],
    );
  }
}

/// 没有这支舞、包里带了熟练度的归属选择面：「建成我的标注方案」丢弃他带的
/// 熟练度快照——这一点写明在面里。
class _CreateOwnershipDialog extends StatelessWidget {
  const _CreateOwnershipDialog({required this.schemeName});

  final String schemeName;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('scheme_import_create_dialog'),
      title: Text('导入「$schemeName」'),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('本机没有这支舞，包里还带着他的熟练度。'),
          SizedBox(height: 8),
          Text('建成我的标注方案会丢弃这份熟练度快照。'),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('scheme_import_create_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('scheme_import_create_as_member'),
          onPressed: () => Navigator.pop(context, _OwnershipExit.member),
          child: const Text('建成组员方案'),
        ),
        FilledButton(
          key: const Key('scheme_import_create_as_mine'),
          onPressed: () => Navigator.pop(context, _OwnershipExit.mine),
          child: const Text('建成我的标注方案'),
        ),
      ],
    );
  }
}

/// 组员名对话框：发送方填过则预填；确认返回名字（可为空串），取消返回
/// null（什么都不做）。
class _MemberNameDialog extends StatefulWidget {
  const _MemberNameDialog({required this.manifest});

  final SusumeManifest manifest;

  @override
  State<_MemberNameDialog> createState() => _MemberNameDialogState();
}

class _MemberNameDialogState extends State<_MemberNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.manifest.memberName ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('scheme_import_dialog'),
      title: Text('导入「${widget.manifest.schemeName}」'),
      content: TextField(
        key: const Key('scheme_import_member_name_field'),
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '组员名',
          hintText: '这位队友的名字',
        ),
      ),
      actions: [
        TextButton(
          key: const Key('scheme_import_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('scheme_import_confirm'),
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('导入'),
        ),
      ],
    );
  }
}
