import 'package:flutter/material.dart';

/// 帮助中心与新手引导页共用的方框件与行内文本件（两页共用版式）：
/// 两页的分组框、图标占位与「标题 + 一句说明」出同一份款式，
/// 颜色一律取自主题、文字随系统字号缩放。
///
/// 组件只负责"长什么样"：读数、计数、状态与点击语义由调用方按各自页面的
/// 事实喂入。

/// 描边方框：通栏、圆角描边 + 内边距。新手引导页的总览框与三组分组框、
/// 帮助中心的分组框共用；缺图条目的图标方框是它的紧凑变体。
class HelpOutlinedBox extends StatelessWidget {
  const HelpOutlinedBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// 图例方框：描边方框 + 框顶一行图例（组名 + 右侧计数，如「功能提示」与
/// 「3 / 9」）；框内内容由调用方给。
class HelpLegendBox extends StatelessWidget {
  const HelpLegendBox({
    super.key,
    required this.legend,
    this.trailing,
    required this.child,
  });

  final String legend;

  /// 框顶右侧的计数（如「2 / 4」）；null 时只出组名。
  final String? trailing;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HelpOutlinedBox(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  legend,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

/// 图标方框：还没有素材的条目占位（描边方框 + 一个图标），与列表行内缩略图
/// 同一个 64×44 槽位、行左缘照常对齐；边长固定、不随字号变化。
/// [color] 非 null 时描边与图标都用它（主色卡上的入口卡用 onPrimary）；
/// null 时描边取 outlineVariant、图标取 outline。
class HelpIconBox extends StatelessWidget {
  const HelpIconBox({super.key, required this.icon, this.color});

  static const double width = 64;
  static const double height = 44;

  final IconData icon;

  /// 描边与图标的前景色；null = 取主题默认两档。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        border: Border.all(color: color ?? colors.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 24, color: color ?? colors.outline),
    );
  }
}

/// 状态方框：已完成 = 主色填底的勾；未完成 = 描边空框。边长固定、不随字号
/// 变化。
class HelpStatusBox extends StatelessWidget {
  const HelpStatusBox({super.key, required this.done});

  static const double _side = 22;

  final bool done;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: _side,
      height: _side,
      decoration: BoxDecoration(
        color: done ? colors.primary : null,
        border: Border.all(color: done ? colors.primary : colors.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: done ? Icon(Icons.check, size: 16, color: colors.onPrimary) : null,
    );
  }
}

/// 进度方框：「标题 + 已完成数 / 总项数 + 百分比 + 进度条」，右下角可放一枚
/// 动作（新手引导页的「重置所有教程」）；动作缺席时框内只有读数。
class HelpProgressBox extends StatelessWidget {
  const HelpProgressBox({
    super.key,
    required this.title,
    required this.done,
    required this.total,
    this.action,
  });

  final String title;
  final int done;
  final int total;

  /// 框内右下角的动作；null = 不出现（如一条都没做过时的「重置所有教程」）。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = total == 0 ? 0.0 : done / total;
    return HelpOutlinedBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                helpCountLabel(done, total),
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: ratio, minHeight: 8),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(ratio * 100).round()}%',
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: action!),
          ],
        ],
      ),
    );
  }
}

/// 「已完成数 / 总项数」的唯一格式（总览框读数与组内图例计数共用）。
String helpCountLabel(int done, int total) => '$done / $total';

/// 可点文字按钮的透明外扩：走 Material 自带的 48 命中层，
/// 按钮视觉尺寸不变；两页的「重置」「重置所有教程」「查看」等文字按钮共用。
final ButtonStyle helpTapTargetButtonStyle = TextButton.styleFrom(
  tapTargetSize: MaterialTapTargetSize.padded,
);

/// 「标题 + 一句说明」行内文本件：帮助中心的条目行与新手引导页的每一行
/// 共用；标题 titleMedium、说明 bodySmall。
class HelpTitleDescription extends StatelessWidget {
  const HelpTitleDescription({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 2),
        Text(description, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
