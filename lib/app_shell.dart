import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dance/dance_library_providers.dart';
import 'home/home_page.dart';
import 'persistence/practice_plan_providers.dart';
import 'plan/plan_page.dart';
import 'plan/practice_reminders_provider.dart';
import 'stats/practice_stats_records_provider.dart';
import 'stats/stats_page.dart';
import 'update/update_prompt.dart';
import 'update/update_state.dart';

/// App 根壳：底部「首页 / 统计 / 计划」三个固定
/// Tab，默认落首页。播放器与舞详情仍是全屏 push 路由，不进 Tab。计划 Tab
/// 在有待提醒项时出红点。
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

/// 懒构建 Tab 的装配：首次进入才构建页，进入即作废其读面重算。
class _LazyTab {
  _LazyTab({required this.page, required this.invalidateReadFaces});

  final Widget page;

  /// 进入该 Tab 时作废的读面（不新增缓存）。
  final List<void Function(WidgetRef ref)> invalidateReadFaces;

  bool built = false;
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const int _homeTab = 0;

  int _index = _homeTab;

  /// 统计 / 计划页首次进入才构建（不在启动时白读一次文件）；构建后由
  /// IndexedStack 保活。计划页的当日练习读数复用练习记录读面，一并作废。
  late final List<_LazyTab> _lazyTabs = [
    _LazyTab(
      page: const StatsPage(),
      invalidateReadFaces: [
        (ref) => ref.invalidate(practiceStatsRecordsProvider),
      ],
    ),
    _LazyTab(
      page: const PlanPage(),
      invalidateReadFaces: [
        (ref) => ref.invalidate(practicePlanEntriesProvider),
        // 团检达标判定读舞库快照里的段档位：进计划 Tab 重读，标注页里改过
        // 的档位不残留旧值。
        (ref) => ref.invalidate(danceLibrarySnapshotProvider),
        (ref) => ref.invalidate(practiceStatsRecordsProvider),
        // 应用内提醒在进入计划 Tab 时评估一次。
        (ref) => ref.invalidate(practiceRemindersProvider),
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 启动静默检查一次：版本行与提示条读的是同一台状态机，启动这一查就是两处
    // 共同的结论来源；异步、不阻塞启动，失败不出声（不弹条）。放在首帧之后，
    // 免得在构建期改状态机。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(updateProvider.notifier).check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 应用内提醒在回到前台时评估一次。
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(practiceRemindersProvider);
      // 从「安装未知应用」设置页返回时重查一次授权：已放行就继续完成安装；
      // 没放行则提示条留在原处等用户再按。
      unawaited(ref.read(updateProvider.notifier).onAppResumed());
    }
  }

  void _select(int index) {
    if (index > _homeTab) {
      final tab = _lazyTabs[index - 1];
      tab.built = true;
      for (final invalidate in tab.invalidateReadFaces) {
        invalidate(ref);
      }
    }
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    // 进入 App 时评估一次应用内提醒：根壳 build 首次 watch 即触发，结果接到
    // 计划 Tab 红点（待提醒项非空出红点）。提示条常挂 Stack 里（IndexedStack
    // 之外，跨三个 Tab 存活），它只读状态机；启动那一次静默检查由上面的
    // initState 发起。
    final hasReminders =
        ref.watch(practiceRemindersProvider).asData?.value.isNotEmpty ?? false;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              const HomePage(),
              for (final tab in _lazyTabs)
                tab.built ? tab.page : const SizedBox.shrink(),
            ],
          ),
          const Positioned(left: 16, bottom: 16, child: UpdatePromptBar()),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          const NavigationDestination(
            key: Key('tab_home'),
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          const NavigationDestination(
            key: Key('tab_stats'),
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: '统计',
          ),
          NavigationDestination(
            key: const Key('tab_plan'),
            icon: hasReminders
                // 待办角标带文字：文字随角标并入计划 Tab 的
                // 语义名字，读屏报得出有待办。
                ? const Badge(
                    key: Key('tab_plan_dot'),
                    label: Text('待办'),
                    child: Icon(Icons.event_note_outlined),
                  )
                : const Icon(Icons.event_note_outlined),
            selectedIcon: const Icon(Icons.event_note),
            label: '计划',
          ),
        ],
      ),
    );
  }
}
