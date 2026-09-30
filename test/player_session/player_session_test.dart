import 'package:dance_learning_app/player_session/player_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player_session 取值与派生谓词', () {
    test('八取值齐全：观看 / 编辑 / 八拍矫正待命 / 段内倍频待命 / 对比-播放 / 对比-控制层 / 对比取景 / 单画面取景', () {
      expect(PlayerSessionMode.values, hasLength(8));
      expect(PlayerSessionMode.values, contains(PlayerSessionMode.watching));
      expect(PlayerSessionMode.values, contains(PlayerSessionMode.editing));
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.beatCorrectionStandby),
      );
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.segmentDensityStandby),
      );
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.compareWatching),
      );
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.compareEditing),
      );
      // 写入的第三值：compareFraming（取景调节态）。
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.compareFraming),
      );
      // 单画面取景调节态：观看面、非对比态。
      expect(
        PlayerSessionMode.values,
        contains(PlayerSessionMode.framing),
      );
      expect(
        const PlayerSession(PlayerSessionMode.framing).isCompare,
        isFalse,
      );
      expect(
        const PlayerSession(PlayerSessionMode.framing).controlOpen,
        isFalse,
      );
    });

    test('控制层展开位由取值派生：观看面为否，编辑面为是', () {
      expect(
        const PlayerSession(PlayerSessionMode.watching).controlOpen,
        isFalse,
      );
      expect(
        const PlayerSession(PlayerSessionMode.editing).controlOpen,
        isTrue,
      );
      expect(
        const PlayerSession(PlayerSessionMode.beatCorrectionStandby)
            .controlOpen,
        isTrue,
      );
      expect(
        const PlayerSession(PlayerSessionMode.compareWatching).controlOpen,
        isFalse,
      );
      expect(
        const PlayerSession(PlayerSessionMode.compareEditing).controlOpen,
        isTrue,
      );
      // 取景调节态：控制层收起——画面手势完全交给取景。
      expect(
        const PlayerSession(PlayerSessionMode.compareFraming).controlOpen,
        isFalse,
      );
    });

    test('仅待命态的待命谓词为真', () {
      expect(
        const PlayerSession(PlayerSessionMode.watching).isBeatCorrectionStandby,
        isFalse,
      );
      expect(
        const PlayerSession(PlayerSessionMode.editing).isBeatCorrectionStandby,
        isFalse,
      );
      expect(
        const PlayerSession(PlayerSessionMode.beatCorrectionStandby)
            .isBeatCorrectionStandby,
        isTrue,
      );
    });

    test('对比态谓词：三对比取值为真，其余为假', () {
      for (final mode in PlayerSessionMode.values) {
        final expected =
            mode == PlayerSessionMode.compareWatching ||
            mode == PlayerSessionMode.compareEditing ||
            mode == PlayerSessionMode.compareFraming;
        expect(
          PlayerSession(mode).isCompare,
          expected,
          reason: '$mode 的 isCompare 应为 $expected',
        );
      }
    });
  });

  group('player_session 进入声明表', () {
    test('结构断言：取值集合大小 = 声明表行数', () {
      expect(
        playerSessionEntryDeclarationTable.length,
        PlayerSessionMode.values.length,
      );
      for (final mode in PlayerSessionMode.values) {
        expect(
          playerSessionEntryDeclarationTable.containsKey(mode),
          isTrue,
          reason: '$mode 缺进入声明行',
        );
      }
    });

    test('所在面谓词与声明表行一致（单一真相交叉护栏）', () {
      for (final mode in PlayerSessionMode.values) {
        expect(
          faceOf(mode),
          playerSessionEntryDeclarationTable[mode]!.face,
          reason: '$mode 的所在面在 faceOf 与声明表两处不一致',
        );
      }
    });

    test('所在面：观看面三值，编辑面三值（穷尽）', () {
      expect(
        faceOf(PlayerSessionMode.watching),
        PlayerSessionFace.watchingFace,
      );
      expect(faceOf(PlayerSessionMode.editing), PlayerSessionFace.editorFace);
      expect(
        faceOf(PlayerSessionMode.beatCorrectionStandby),
        PlayerSessionFace.editorFace,
      );
      expect(
        faceOf(PlayerSessionMode.compareWatching),
        PlayerSessionFace.watchingFace,
      );
      expect(
        faceOf(PlayerSessionMode.compareEditing),
        PlayerSessionFace.editorFace,
      );
      // 取景调节态：观看面（分屏画面 + 取景条，随设备方向）。
      expect(
        faceOf(PlayerSessionMode.compareFraming),
        PlayerSessionFace.watchingFace,
      );
    });

    test('进入前置：compareFraming 需相机授权', () {
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode.compareFraming]!
            .requirement,
        PlayerSessionEntryRequirement.cameraPermission,
      );
    });

    test('进入前置：编辑面三值无前置；compareWatching 需相机授权；watching 无前置', () {
      const none = PlayerSessionEntryRequirement.none;
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode.watching]!
            .requirement,
        none,
      );
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode.editing]!
            .requirement,
        none,
      );
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode
                .beatCorrectionStandby]!
            .requirement,
        none,
      );
      // 「相机授权」进入前置：进入对比-播放态先过相机门。
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode.compareWatching]!
            .requirement,
        PlayerSessionEntryRequirement.cameraPermission,
      );
      expect(
        playerSessionEntryDeclarationTable[PlayerSessionMode.compareEditing]!
            .requirement,
        none,
      );
    });
  });

  group('player_session 进入与结果族', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    PlayerSession read() => container.read(playerSessionProvider);

    test('默认观看态、无待办', () {
      expect(read().mode, PlayerSessionMode.watching);
      expect(read().pendingEntry, isNull);
    });

    test('从每个取值进入每个取值：结果与终值', () {
      for (final from in PlayerSessionMode.values) {
        for (final target in PlayerSessionMode.values) {
          container.read(playerSessionProvider.notifier).reset();
          container.read(playerSessionProvider.notifier).enter(from);
          final result = container
              .read(playerSessionProvider.notifier)
              .enter(target);
          if (from == target) {
            expect(result, PlayerSessionEntryResult.alreadyThere);
          } else {
            expect(result, PlayerSessionEntryResult.entered);
          }
          expect(read().mode, target);
        }
      }
    });

    test('自反进入 = 本就在目标态：终值不变、不报错', () {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      final before = read();
      final result = container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      expect(result, PlayerSessionEntryResult.alreadyThere);
      expect(read().mode, before.mode);
      expect(read().pendingEntry, isNull);
    });

    test('具名便捷与进入目标态落到同一终值', () {
      container.read(playerSessionProvider.notifier).openEditor();
      expect(
        container
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.editing),
        PlayerSessionEntryResult.alreadyThere,
      );
      expect(read().mode, PlayerSessionMode.editing);

      container.read(playerSessionProvider.notifier).collapse();
      expect(
        container
            .read(playerSessionProvider.notifier)
            .enter(PlayerSessionMode.watching),
        PlayerSessionEntryResult.alreadyThere,
      );
      expect(read().mode, PlayerSessionMode.watching);
    });

    test('收起即回观看态：待命态随收起退出（结构承载）', () {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.beatCorrectionStandby);
      expect(read().isBeatCorrectionStandby, isTrue);
      container.read(playerSessionProvider.notifier).collapse();
      expect(read().mode, PlayerSessionMode.watching);
      expect(read().isBeatCorrectionStandby, isFalse);
    });

    test('对比-控制层收起 = 退到对比-播放态（不退回普通观看态）', () {
      final model = container.read(playerSessionProvider.notifier);
      model.enter(PlayerSessionMode.compareEditing);
      final result = model.collapse();
      expect(result, PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.compareWatching);
      expect(read().controlOpen, isFalse);
    });

    test('对比态互转：enter 直达，自反幂等', () {
      final model = container.read(playerSessionProvider.notifier);
      expect(
        model.enter(PlayerSessionMode.compareWatching),
        PlayerSessionEntryResult.entered,
      );
      expect(read().mode, PlayerSessionMode.compareWatching);
      expect(
        model.enter(PlayerSessionMode.compareWatching),
        PlayerSessionEntryResult.alreadyThere,
      );
      expect(
        model.enter(PlayerSessionMode.compareEditing),
        PlayerSessionEntryResult.entered,
      );
      expect(read().mode, PlayerSessionMode.compareEditing);
      expect(read().controlOpen, isTrue);
    });

    test('退出对比态：三对比取值都回 watching；非对比态幂等 no-op', () {
      final model = container.read(playerSessionProvider.notifier);
      model.enter(PlayerSessionMode.compareEditing);
      expect(model.exitCompare(), PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.watching);
      expect(read().controlOpen, isFalse);

      model.enter(PlayerSessionMode.compareWatching);
      expect(model.exitCompare(), PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.watching);

      // 取景调节态：isCompare 含第三值，退出亦回 watching。
      model.enter(PlayerSessionMode.compareFraming);
      expect(model.exitCompare(), PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.watching);

      // 非对比态：不误收控制层（编辑面保持展开）、值一位不动。
      model.openEditor();
      expect(model.exitCompare(), PlayerSessionEntryResult.alreadyThere);
      expect(read().mode, PlayerSessionMode.editing);
    });

    test('直接进入不清残留待办：宿主须显式提交或取消', () {
      container
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.beatCorrectionStandby);
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      expect(read().mode, PlayerSessionMode.editing);
      expect(
        read().pendingEntry?.target,
        PlayerSessionMode.beatCorrectionStandby,
      );
    });

    test('不成立（空槽提交）：终值一位不动、待办槽不残留', () {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      final result = container.read(playerSessionProvider.notifier).commit();
      expect(result, PlayerSessionEntryResult.rejected);
      expect(read().mode, PlayerSessionMode.editing);
      expect(read().pendingEntry, isNull);
    });
  });

  group('player_session 待办槽', () {
    late ProviderContainer container;
    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    PlayerSession read() => container.read(playerSessionProvider);

    test('落待办 → 提交 → 值变且槽清空', () {
      container
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.beatCorrectionStandby);
      expect(
        read().pendingEntry?.target,
        PlayerSessionMode.beatCorrectionStandby,
      );
      expect(read().mode, PlayerSessionMode.watching);

      final result = container.read(playerSessionProvider.notifier).commit();
      expect(result, PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.beatCorrectionStandby);
      expect(read().pendingEntry, isNull);
    });

    test('落待办 → 取消 → 值不变且槽清空', () {
      container
          .read(playerSessionProvider.notifier)
          .enter(PlayerSessionMode.editing);
      container
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.beatCorrectionStandby);
      container.read(playerSessionProvider.notifier).cancelPendingEntry();
      expect(read().mode, PlayerSessionMode.editing);
      expect(read().pendingEntry, isNull);
    });

    test('重复落待办不叠加：槽内只有最后一次', () {
      container
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.editing);
      container
          .read(playerSessionProvider.notifier)
          .requestEntry(PlayerSessionMode.beatCorrectionStandby);
      expect(
        read().pendingEntry?.target,
        PlayerSessionMode.beatCorrectionStandby,
      );

      final result = container.read(playerSessionProvider.notifier).commit();
      expect(result, PlayerSessionEntryResult.entered);
      expect(read().mode, PlayerSessionMode.beatCorrectionStandby);
      expect(read().pendingEntry, isNull);
    });
  });

  group('player_session 复位', () {
    test('复位回到观看态并清空待办，幂等', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final model = container.read(playerSessionProvider.notifier);
      model.enter(PlayerSessionMode.beatCorrectionStandby);
      model.requestEntry(PlayerSessionMode.editing);

      model.reset();
      expect(
        container.read(playerSessionProvider).mode,
        PlayerSessionMode.watching,
      );
      expect(container.read(playerSessionProvider).pendingEntry, isNull);

      model.reset();
      expect(
        container.read(playerSessionProvider).mode,
        PlayerSessionMode.watching,
      );
      expect(container.read(playerSessionProvider).pendingEntry, isNull);
    });
  });
}
