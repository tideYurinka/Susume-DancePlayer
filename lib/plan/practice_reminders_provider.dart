import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../annotation/learning_segment_attributes.dart';
import '../core/device_clock.dart';
import '../dance/dance_library_providers.dart';
import '../persistence/practice_plan.dart';
import '../persistence/practice_plan_providers.dart';
import 'practice_reminders.dart';
import '../persistence/team_check_gate.dart';

/// 应用内提醒评估读面：从舞库快照与计划文档合成
/// 单舞输入，跑提醒规则表纯件。评估时机由调用方作废本读面驱动——进入
/// App（根壳 build 首次 watch）、回到前台（根壳生命周期回调）、进入计划
/// Tab（壳的 Tab 进场作废）与计划写成功（写路径统一作废）各评估一次，结果
/// 接到计划 Tab 红点（分组呈现）。触发提醒的舞经 store 落下提醒状态（冷却
/// 与同日一次随之生效），写失败静默承接（内存态仍在，本进程不重复提醒）。
final practiceRemindersProvider =
    FutureProvider.autoDispose<List<ReminderItem>>((ref) async {
      final store = ref.watch(practicePlanStoreProvider);
      final entries = await store.entries();
      final events = await store.events();
      final library = await ref.watch(danceLibrarySnapshotProvider.future);
      final now = ref.watch(deviceClockProvider)();
      final entryByVideoId = <String, DancePlanEntry>{
        for (final entry in entries) entry.videoId: entry,
      };
      final masteriesByVideoId = <String, Set<LearningMastery>>{
        for (final dance in library.dances)
          dance.videoId: {
            for (final segment in dance.segments) segment.mastery,
          },
      };
      final inputs = <ReminderDanceInput>[];
      for (final dance in library.dances) {
        final entry = entryByVideoId[dance.videoId];
        final ddl = entry?.ddl;
        final ddlActive =
            ddl != null &&
            ddl.settlement == null &&
            planRemainingDays(dueDay: ddl.date, now: now) >= 0;
        inputs.add(
          ReminderDanceInput(
            videoId: dance.videoId,
            level: danceReminderLevel(masteriesByVideoId[dance.videoId]!),
            lastPracticeDay: dance.lastPracticedAt,
            reviewReminders: entry?.reviewReminders ?? true,
            hasGoal: danceHasGoal(
              ddl: ddl,
              events: events,
              videoId: dance.videoId,
              now: now,
            ),
            state: entry?.reminderState,
            ddlRemainingDays: ddlActive
                ? planRemainingDays(dueDay: ddl.date, now: now)
                : null,
          ),
        );
      }
      final evaluation = evaluateReminders(
        dances: inputs,
        events: events,
        gateStatusOf: (event, videoId) => danceGateStatus(
          gate: teamCheckGateFromName(event.danceGates[videoId]),
          segmentMasteries: masteriesByVideoId[videoId] ?? const {},
        ),
        now: now,
      );
      for (final MapEntry(key: videoId, value: state)
          in evaluation.nextStates.entries) {
        await store.saveReminderState(videoId, state);
      }
      return evaluation.items;
    });
