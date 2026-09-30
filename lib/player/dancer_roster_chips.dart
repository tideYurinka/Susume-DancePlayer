/// 舞者快捷区：名册在
/// 编辑器那一行里的一段舞者词条（名字 + 代表色圆点）。宽度按内容收缩、
/// 上限 260dp（词条少时紧贴右侧相邻控件不留空隙，多了左右滑动）；词条
/// 顺序按最近用过——点显示序前三名的词条不改变顺序、点之外的名字把它
/// 提到第一位。点词条的语义按模式分：备注态 = 在光标处写下 `@名字 `
/// （经 [DancerRosterChipBar.onInsertDancer] 由宿主写入编辑器文本框），
/// 名册态 = 弹出这位舞者的 24 色选色浮层
/// （[showDancerColorPicker]，选完 / 删除即收）。空名册即空段、不崩。
///
/// 名册增删改色全部走 [DancerRosterController] **直写**：不经标注编辑模块、
/// 不入撤销史、不受锁定分段与内容锁影响，只触碰 markers 的 `roster` 段。
/// 「最近用过」序是会话内呈现态、不持久化——名册的持久真源仍是文件序。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/dancer_roster.dart' show DancerRosterEntry;
import 'dancer_roster_controller.dart';
import 'visual_tokens.dart'
    show
        kHitTargetMinSize,
        kNoteEditorPanelColor,
        kRosterPalette,
        kRosterPaletteNames;

const double kRosterStripMaxWidth = 260;

/// 词条名字宽上限：词条总宽（圆点 + 内边距 + 边距另计）不超过
/// [kRosterStripMaxWidth]、超出单行省略——大字号下长名字不撑破一行。
const double kRosterChipTextMaxWidth = 200;

/// 新建舞者的默认代表色：取色板里**尚未被名册占用**的第一色——
/// 新建完立刻弹选色浮层，取消（或点外面收掉）时留下的就是这个色，取未占
/// 用色才不会建出两个同色的舞者。名册把 24 色占满时回过头取首色。
int firstUnusedPaletteColor(Iterable<int> usedColors) {
  final used = usedColors.toSet();
  for (final color in kRosterPalette) {
    if (!used.contains(color)) return color;
  }
  return kRosterPalette.first;
}

/// 词条「最近用过」序：会话内名单，名字在前 = 更近用过；未入
/// 名单的词条按名册文件序跟随。不持久化——名册文件序仍是持久真源。
final dancerChipRecencyProvider =
    NotifierProvider<DancerChipRecency, List<String>>(
      DancerChipRecency.new,
    );

class DancerChipRecency extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  /// 点词条后登记：显示序 [tappedIndex] 前三名不动，
  /// 之外把被点名字提到第一位（[displayNames] 为当前显示序）。
  void registerTap(List<String> displayNames, int tappedIndex) {
    state = recencyAfterTap(state, displayNames, tappedIndex);
  }
}

/// 显示序（纯函数）：「最近用过」名单里还在名册中的名字在前、按名单序，
/// 其余词条按名册文件序跟随；名单里的失效名字（已删舞者）忽略。
List<DancerRosterEntry> orderChipsByRecency(
  List<DancerRosterEntry> roster,
  List<String> recency,
) {
  final byName = {for (final entry in roster) entry.name: entry};
  final seen = <String>{};
  return [
    for (final name in recency)
      if (byName.containsKey(name) && seen.add(name)) byName[name]!,
    for (final entry in roster)
      if (seen.add(entry.name)) entry,
  ];
}

/// 「最近用过」序变更（纯函数）：[tappedIndex] 是被点词条
/// 在显示序里的下标——前三名（0–2）顺序不变，之外把该名字提到第一位
/// （原名单中的旧位置移除）。
List<String> recencyAfterTap(
  List<String> recency,
  List<String> displayNames,
  int tappedIndex,
) {
  if (tappedIndex < 0 ||
      tappedIndex >= displayNames.length ||
      tappedIndex < 3) {
    return recency;
  }
  final name = displayNames[tappedIndex];
  return [name, ...recency.where((n) => n != name)];
}

/// 舞者快捷区：挂在编辑器那一行上，宽度按内容收缩、上限 260dp——上限只在
/// 横屏那一行为真（宿主非弹性供位）；竖屏宿主用 [Expanded] 紧约束
/// 供位，占满动作行剩余宽，词条渲染随名册控制器与「最近用过」序即时反映。
class DancerRosterChipBar extends ConsumerWidget {
  const DancerRosterChipBar({
    super.key,
    required this.rosterMode,
    this.onInsertDancer,
  });

  /// 当前编辑器形态：true = 名册态（点词条弹选色浮层），false = 备注态
  /// （点词条插入点名）。
  final bool rosterMode;

  /// 备注态点词条时由宿主把 `@名字 ` 写进编辑器文本框光标处（快捷区不
  /// 持有文本框——插入位置归编辑器那条所有）；null = 无宿主文本框
  /// （如直测脚手架），点词条只登记「最近用过」序。
  final ValueChanged<String>? onInsertDancer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(dancerRosterControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final recency = ref.watch(dancerChipRecencyProvider);
        final roster = orderChipsByRecency(controller.roster, recency);
        return ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: kRosterStripMaxWidth,
          ),
          child: SingleChildScrollView(
            key: const Key('note_editor_roster_strip'),
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < roster.length; i++)
                  _RosterChip(
                    entry: roster[i],
                    onTap: () {
                      final insertDancer = onInsertDancer;
                      ref
                          .read(dancerChipRecencyProvider.notifier)
                          .registerTap(
                            [for (final e in roster) e.name],
                            i,
                          );
                      final name = roster[i].name;
                      if (rosterMode) {
                        showDancerColorPicker(context, ref, name);
                      } else {
                        insertDancer?.call(name);
                      }
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 一个舞者词条：代表色圆点 + 名字；点按语义由 [DancerRosterChipBar]
/// 按模式分发。
class _RosterChip extends StatelessWidget {
  const _RosterChip({required this.entry, required this.onTap});

  final DancerRosterEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 透明命中盒：词条视觉件（内边距 8/4、圆点
    // 10、字号 13）一个像素不动，命中矩形外扩到通行下限——词条段是横滚的
    // 一排、词条之间只隔「右 8」边距，但命中域各自独占盒子、互不重叠，
    // 48 达得到、不走密集区兜底。
    return GestureDetector(
      key: Key('roster_chip_${entry.name}'),
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: kHitTargetMinSize,
          minHeight: kHitTargetMinSize,
        ),
        child: Align(
          // factor 1：按视觉件收缩、不被外层松约束撑大（Center 在有界松
          // 约束下会撑满，词条会被拉满行高）——外扩只发生在外框 min 48。
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: Color(entry.color),
                    shape: BoxShape.circle,
                  ),
                ),
                // 长名字省略：名字封顶、单行省略号——词条总宽
                // 不超过快捷区上限（该上限之上由横滚接管）。
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: kRosterChipTextMaxWidth,
                  ),
                  child: Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 选色浮层：给 [name] 选代表色——色板 24 色
/// （[kRosterPalette] 集中视觉常量），选完即收；「删除」删掉这位舞者。
/// 点浮层以外（屏障）= 取消、不改任何东西。增删改色均直写控制器。
Future<void> showDancerColorPicker(
  BuildContext context,
  WidgetRef ref,
  String name,
) => showModalBottomSheet<void>(
      context: context,
      backgroundColor: kNoteEditorPanelColor,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选代表色',
                key: const Key('roster_color_sheet'),
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < kRosterPalette.length; i++)
                    GestureDetector(
                      key: Key('roster_palette_color_$i'),
                      onTap: () {
                        ref
                            .read(dancerRosterControllerProvider)
                            .changeColor(name, kRosterPalette[i]);
                        Navigator.of(sheetContext).pop();
                      },
                      // 每格报出自己的颜色：色块是唯一视觉信息，
                      // 读屏用户听不到——按集中色名表给按钮语义。
                      child: Semantics(
                        button: true,
                        label: '选代表色：${kRosterPaletteNames[i]}',
                        // 透明命中盒：色块视觉 24×24 居中不动，命中
                        // 矩形定到通行下限 48×48——格子各自独占盒子（Wrap
                        // 间距 8），命中域互不重叠，48 达得到、不走兜底。
                        child: SizedBox(
                          width: kHitTargetMinSize,
                          height: kHitTargetMinSize,
                          child: Center(
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: Color(kRosterPalette[i]),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                key: Key('roster_palette_delete_$name'),
                onPressed: () => _confirmRemoveDancer(context, sheetContext, ref, name),
                child: const Text(
                  '删除',
                  style: TextStyle(color: Color(0xFFEF5350), fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// 删舞者二次确认：取消 = 名册不动；确认后
/// 直写控制器并收浮层。名册直写不入撤销史，故不引入撤销，只拦一次手滑。
Future<void> _confirmRemoveDancer(
  BuildContext context,
  BuildContext sheetContext,
  WidgetRef ref,
  String name,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: const Key('roster_palette_delete_dialog'),
      content: const Text('删除后这位舞者将从名册移除；已写的点名会因此失去颜色'),
      actions: [
        TextButton(
          key: const Key('roster_palette_delete_cancel'),
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('roster_palette_delete_confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  ref.read(dancerRosterControllerProvider).removeDancer(name);
  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
}
