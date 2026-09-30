import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_identity.dart';
import '../help/help_markdown_body.dart'
    show copyHelpLink, helpLinkOpenFailedMessage;
import '../help/platform_help_actions.dart' show helpExternalLinkOpenerProvider;
import '../update/update_state.dart';
import 'contributors_page.dart';

/// 更新说明的落点：**下载页**上「更新说明」那一块的就地锚点——浏览器落在锚点
/// 上即展开该块，不必让用户自己在页面上找。下载页地址是固定地址
/// （见 `lib/help/CONTEXT.md`）。
const String aboutUpdateNotesUrl =
    'https://susume.yurinka.top/download/#notes';

/// 版本号的显示串：只给用户看版本名（形如 `0.1.0`），构建号不进用户可见的
/// 版本号；构建号只留在诊断信息（`lib/feedback/device_snapshot.dart`）里。
String aboutVersionLabel(PackageInfo info) => info.version;

/// 版本号装载：经 `package_info_plus` 从构建产物读，交给 [aboutVersionLabel]
/// 取成一处字符串。
///
/// 读不出（平台通道不在）时页面按「没有版本号」处理，照常开得了。
final aboutAppVersionProvider = FutureProvider<String>((ref) async {
  return aboutVersionLabel(await PackageInfo.fromPlatform());
});

/// 应用信息头：居中的圆形应用图标 + 应用名 + 一句话简介，**不含任何操作**。
/// 关于页与贡献者名单页共用同一个它，两页因此看起来是同一处往下走的两层。
class AboutAppInfoHeader extends StatelessWidget {
  const AboutAppInfoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('about_app_info_header'),
      children: [
        ClipOval(
          child: Image.asset(
            appIconAsset,
            key: const Key('about_app_icon'),
            width: 96,
            height: 96,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          appDisplayName,
          key: const Key('about_app_name'),
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          appTagline,
          key: const Key('about_app_tagline'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 关于页：先交代这个 App 是什么（**应用信息头**），再给往下走的三条门——
/// **版本行**、更新说明行与**贡献者名单**行。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 64),
        children: const [
          AboutAppInfoHeader(),
          SizedBox(height: 36),
          AboutVersionRow(),
          AboutUpdateNotesRow(),
          _ContributorsRow(),
        ],
      ),
    );
  }
}

/// **贡献者名单**行：按下推入**贡献者名单**页。
class _ContributorsRow extends StatelessWidget {
  const _ContributorsRow();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: const Key('about_contributors_row'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.people_outline),
      title: const Text('贡献者名单'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ContributorsPage()),
      ),
    );
  }
}

/// 更新说明行：点一下把 [aboutUpdateNotesUrl] 交系统浏览器打开，落在下载页的
/// 更新说明那一块；打不开时按既有**外部网址**口径收场——把地址复制到剪贴板并
/// 提示，不新写打开件。
class AboutUpdateNotesRow extends ConsumerWidget {
  const AboutUpdateNotesRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      key: const Key('about_update_notes_row'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.description_outlined),
      title: const Text('更新说明'),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => _open(context, ref),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final opened = await ref
        .read(helpExternalLinkOpenerProvider)
        .open(aboutUpdateNotesUrl);
    if (!context.mounted || opened) return;
    copyHelpLink(
      context,
      aboutUpdateNotesUrl,
      message: helpLinkOpenFailedMessage,
    );
  }
}

/// **版本行**：横排三段——左「版本号 + 本机版本值」、中「一句状态文字 + 下载
/// 进度槽」、右一颗定尺寸按钮。它与**更新提示条**读同一台更新状态机，所以两处
/// 说的永远是同一件事；开页不自动检查，检查由右端按钮发起。
///
/// 中间格宽高写死、按钮空心与实心同形，所以七态换来换去都不推动行高与两侧位置；
/// 本机版本值只显示版本名，构建号不进屏。
class AboutVersionRow extends ConsumerWidget {
  const AboutVersionRow({super.key});

  /// 中间格：状态文字的长短、进度槽的有无都只在自己这格里变。
  static const double _middleWidth = 148;
  static const double _middleHeight = 27;

  /// 右端按钮：空心与实心同一形状，只换文案与层级。
  static const double _actionButtonHeight = 40;
  static const double _actionButtonMinWidth = 96;
  static const ButtonStyle _actionButtonStyle = ButtonStyle(
    minimumSize: WidgetStatePropertyAll(
      Size(_actionButtonMinWidth, _actionButtonHeight),
    ),
    padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final state = ref.watch(updateProvider);
    final status = state.versionRowStatus;
    final downloading = status == VersionRowStatus.downloading;
    final version = ref.watch(aboutAppVersionProvider).value ?? '';
    return Padding(
      key: const Key('about_version_row'),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // 左：标题 + 本机版本值。
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('版本号', style: theme.textTheme.bodyLarge),
              Text(
                version,
                key: const Key('about_version_value'),
                style: muted,
              ),
            ],
          ),
          const SizedBox(width: 12),
          // 中：状态文字 + 进度槽。固定宽高，下载时文字让到上沿、进度条贴下沿。
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                key: const Key('about_version_middle'),
                width: _middleWidth,
                height: _middleHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        // 语义档（随系统字号）：这句状态文字承载语义、随系统
                        // 字号缩放；本格宽高写死（规格硬要求：状态换来换去都
                        // 不推动行高与两侧位置），所以字号放大到排不进这一格
                        // 时按仓库既有兜底等比收在格内（同 `play_tool_row`
                        // 逐列的 `FittedBox`），不画到格外的按钮上。
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            _statusOf(state, status),
                            key: const Key('about_version_status'),
                            maxLines: 1,
                            softWrap: false,
                            textAlign: TextAlign.right,
                            style: muted,
                          ),
                        ),
                      ),
                    ),
                    // 进度槽恒占位：不下载时是同样高的一条空槽。
                    SizedBox(
                      height: 6,
                      width: downloading ? null : 0,
                      child: downloading
                          ? LinearProgressIndicator(
                              key: const Key('about_version_progress'),
                              value: state.total > 0 ? state.progress : null,
                              minHeight: 6,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 右：动作按钮。命中盒下限（48×48）走 Material 自带的 48 命中层
          // （`tapTargetSize: padded` 的透明外扩，同 `help_boxes` 的
          // `helpTapTargetButtonStyle`）：可点层撑到下限、视觉件居中其内，
          // 那颗定尺寸按钮本身的尺寸与两侧位置不因此变。
          _action(ref, state, status),
        ],
      ),
    );
  }

  /// 中间格那句状态文字：**阶段优先、结论兜底**的读数翻成人话。
  String _statusOf(UpdateState state, VersionRowStatus status) =>
      switch (status) {
        VersionRowStatus.notChecked => '未检查',
        VersionRowStatus.checking => '检查中…',
        VersionRowStatus.upToDate => '已是最新',
        VersionRowStatus.updateAvailable =>
          '最新版本 ${state.manifest?.versionName ?? ''}',
        VersionRowStatus.downloading =>
          '下载中 ${(state.progress * 100).round()}%',
        VersionRowStatus.downloadFailed => '下载失败',
        VersionRowStatus.needsInstallPermission => '需要允许安装未知应用',
        VersionRowStatus.checkFailed => '无法检查更新',
      };

  /// 右端那颗按钮：文案与层级随态换，尺寸不变。所有动作都走既有那一条通路
  /// （检查、下载、取消、重试、前往设置）。交系统安装器那一下在飞时「下包」
  /// 这一下不再接受按下——与**更新提示条**同一结论，读同一台状态机就不会一处
  /// 说行、一处说不行。
  Widget _action(WidgetRef ref, UpdateState state, VersionRowStatus status) {
    final controller = ref.read(updateProvider.notifier);
    final installing = state.inFlight == UpdateInFlight.installing;
    switch (status) {
      case VersionRowStatus.checking:
        return const OutlinedButton(
          key: Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: null,
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              key: Key('about_version_checking'),
              strokeWidth: 2,
            ),
          ),
        );
      case VersionRowStatus.downloading:
        return OutlinedButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: controller.cancelDownload,
          child: const Text('取消'),
        );
      case VersionRowStatus.needsInstallPermission:
        return FilledButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: controller.openInstallSettings,
          child: const Text('前往设置'),
        );
      case VersionRowStatus.updateAvailable:
        return FilledButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: installing ? null : controller.download,
          child: const Text('下载'),
        );
      case VersionRowStatus.checkFailed:
        return OutlinedButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: controller.check,
          child: const Text('重试'),
        );
      case VersionRowStatus.downloadFailed:
        return OutlinedButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: installing ? null : controller.download,
          child: const Text('重试'),
        );
      case VersionRowStatus.notChecked:
      case VersionRowStatus.upToDate:
        return OutlinedButton(
          key: const Key('about_version_action'),
          style: _actionButtonStyle,
          onPressed: controller.check,
          child: const Text('检查更新'),
        );
    }
  }
}
