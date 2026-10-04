import 'package:dance_learning_app/annotation/compare_materials.dart';
import 'package:dance_learning_app/player/beat_animation.dart'
    show BeatAnimationStyle;
import 'package:dance_learning_app/player/metronome_sound.dart'
    show MetronomeSoundType;
import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/persistence/local_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalDocument schema v4 往返', () {
    test('全字段往返：熟练度/激活段（session）+ 偏好与浮层（prefs）', () {
      const doc = LocalDocument(
        mastery: {0: LearningMastery.learning, 2: LearningMastery.mastered},
        activatedSegments: [1, 2],
        previewSnapEnabled: false,
        layoutLocked: true,
        overlay: OverlayPlacementFields(
          dx: 24.0,
          dy: 96.0,
          landscapeDx: 11.0,
          landscapeDy: 22.0,
          compareDx: 33.0,
          compareDy: 44.0,
          landscapeCompareDx: 55.0,
          landscapeCompareDy: 66.0,
          rectWidthFactor: 1.5,
          pendulumScale: 0.8,
        ),
      );

      final restored = LocalDocument.fromJson(doc.toJson());
      expect(restored.mastery, {
        0: LearningMastery.learning,
        2: LearningMastery.mastered,
      });
      expect(restored.activatedSegments, [1, 2]);
      expect(restored.previewSnapEnabled, false);
      expect(restored.layoutLocked, true);
      expect(restored.overlay!.dx, 24.0);
      expect(restored.overlay!.dy, 96.0);
      expect(restored.overlay!.landscapeDx, 11.0);
      expect(restored.overlay!.landscapeDy, 22.0);
      expect(restored.overlay!.compareDx, 33.0);
      expect(restored.overlay!.compareDy, 44.0);
      expect(restored.overlay!.landscapeCompareDx, 55.0);
      expect(restored.overlay!.landscapeCompareDy, 66.0);
      expect(restored.overlay!.rectWidthFactor, 1.5);
      expect(restored.overlay!.pendulumScale, 0.8);
      expect(restored, doc);
      expect(restored.hashCode, doc.hashCode);
    });

    test('JSON 段形状：session{mastery,activatedSegments} + prefs{…,overlay}', () {
      final json = const LocalDocument(
        mastery: {3: LearningMastery.mastered},
        activatedSegments: [0],
        previewSnapEnabled: false,
        layoutLocked: true,
        overlay: OverlayPlacementFields(
          dx: 1.0,
          dy: 2.0,
          rectWidthFactor: 1.25,
          pendulumScale: 1.75,
        ),
      ).toJson();
      expect(json['version'], 4);
      expect(json['session'], {
        'mastery': {'3': 'mastered'},
        'activatedSegments': [0],
      });
      expect(json['prefs'], {
        'previewSnapEnabled': false,
        'layoutLocked': true,
        'overlay': {
          'dx': 1.0,
          'dy': 2.0,
          'rectWidthFactor': 1.25,
          'pendulumScale': 1.75,
        },
      });
      expect(json.keys, {'version', 'session', 'prefs'});
    });

    test('承诺性形状：无自定义浮层不写 overlay 键；默认文档两段仍写', () {
      final json = const LocalDocument(previewSnapEnabled: false).toJson();
      expect(json['prefs'].containsKey('overlay'), isFalse);
      expect(json['session'], {'mastery': {}, 'activatedSegments': []});
    });

    test('默认值文档为空态：未练不入 mastery、默认吸附开/不锁', () {
      const empty = LocalDocument.empty();
      expect(empty.mastery, isEmpty);
      expect(empty.activatedSegments, isEmpty);
      expect(empty.previewSnapEnabled, true);
      expect(empty.layoutLocked, false);
      expect(LocalDocument.fromJson(const {}), empty);
    });

    test('随舞预备拍数两字段退场：残留键按未知键保底区透传', () {
      // 旧文件里的 delayedLoopBeats / recordingPrepBeats 不再是本版本字段：
      // 读入按未知键带回 prefsExtra、写回原样保留，本地文档版本不升。
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {'delayedLoopBeats': 8, 'recordingPrepBeats': 4},
      });
      expect(doc.prefsExtra['delayedLoopBeats'], 8);
      expect(doc.prefsExtra['recordingPrepBeats'], 4);
      expect(doc.toJson()['prefs']['delayedLoopBeats'], 8);
      expect(doc.toJson()['prefs']['recordingPrepBeats'], 4);
    });

    test('自动删除预留字段：默认关、保留最近 30 条 / 90 天、往返与兜底', () {
      // 默认值：关 + 保留最近条数策略 + 30 条 / 90 天。
      final defaults = const LocalDocument.empty().autoDelete;
      expect(defaults.enabled, isFalse);
      expect(defaults.strategy, MaterialAutoDeleteStrategy.keepRecentCount);
      expect(defaults.keepCount, 30);
      expect(defaults.keepDays, 90);

      // 自定义值往返。
      const doc = LocalDocument(
        autoDelete: MaterialAutoDeleteSettings(
          enabled: true,
          strategy: MaterialAutoDeleteStrategy.keepRecentDays,
          keepCount: 10,
          keepDays: 60,
        ),
      );
      final restored = LocalDocument.fromJson(doc.toJson());
      expect(restored.autoDelete, doc.autoDelete);

      // 缺键/畸形按默认值兜底。
      final fallback = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {'autoDelete': 'junk'},
      });
      expect(fallback.autoDelete, const LocalDocument().autoDelete);
    });

    test('非法值兜底：未知熟练度丢弃、系数钳制 0.5–3.0', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'session': {
          'mastery': {'0': 'practicing', '9': 'mastered', '2': 'unknown-value'},
        },
        'prefs': {
          'overlay': {
            'dx': 1.0,
            'dy': 2.0,
            'rectWidthFactor': 9.0,
            'pendulumScale': 0.1,
          },
        },
      });
      expect(doc.mastery, {
        0: LearningMastery.learning,
        9: LearningMastery.mastered,
      });
      expect(learningSegmentMastery(doc.mastery, 2), LearningMastery.unlearned);
      expect(doc.overlay!.rectWidthFactor, 3.0);
      expect(doc.overlay!.pendulumScale, 0.5);
    });

    test('五档名往返：五档全量 JSON 往返逐位相等', () {
      const doc = LocalDocument(
        mastery: {
          0: LearningMastery.unlearned,
          1: LearningMastery.learning,
          2: LearningMastery.keepingUp,
          3: LearningMastery.familiar,
          4: LearningMastery.mastered,
        },
      );

      expect(doc.toJson()['session']['mastery'], {
        '0': 'unlearned',
        '1': 'learning',
        '2': 'keepingUp',
        '3': 'familiar',
        '4': 'mastered',
      });
      expect(LocalDocument.fromJson(doc.toJson()), doc);
    });

    test('旧三态文件读出映射为五档、不报错、不丢其它段；写盘只写新枚举名', () {
      // 旧本地文档：三态值（未学 / 练习中 / 已掌握）+ 其它段与其它段字段。
      final legacy = LocalDocument.fromJson(const {
        'version': 3,
        'session': {
          'mastery': {'0': 'unlearned', '1': 'practicing', '2': 'mastered'},
          'activatedSegments': [1],
        },
        'prefs': {'layoutLocked': true, 'delayedLoopBeats': 8},
      });

      expect(legacy.mastery, {
        0: LearningMastery.unlearned, // 未学 → 未练
        1: LearningMastery.learning, // 练习中 → 学习中
        2: LearningMastery.mastered, // 已掌握 → 掌握
      });
      // 不丢其它段/其它字段，读出不报错；退场键按未知键透传。
      expect(legacy.activatedSegments, [1]);
      expect(legacy.layoutLocked, isTrue);
      expect(legacy.toJson()['prefs']['delayedLoopBeats'], 8);

      // 写盘只写新枚举名（旧名 'practicing' 不再出现）。
      expect(legacy.toJson()['session']['mastery'], {
        '0': 'unlearned',
        '1': 'learning',
        '2': 'mastered',
      });
    });
    test('练习片段列表：往返保留、空列表省键、畸形条目整条跳过', () {
      const clip = PracticeClip(
        id: 'clip_a',
        materialId: 'mat_a',
        materialSourceStartMs: 10000,
        inMs: 0,
        outMs: 8000,
      );
      final doc = LocalDocument(practiceClips: [clip]);
      final restored = LocalDocument.fromJson(doc.toJson());
      expect(restored.practiceClips, [clip]);
      expect(restored, doc);

      // 空列表省键（承诺：缺键即空轨）。
      expect(
        const LocalDocument().toJson()['prefs'].containsKey('practiceClips'),
        isFalse,
      );

      // 畸形条目整条跳过、合法条目保留。
      final partial = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'practiceClips': [
            {
              'id': 'clip_b',
              'materialId': 'mat_b',
              'materialSourceStartMs': 0,
              'inMs': 0,
              'outMs': 1000,
            },
            {'id': 'bad'},
          ],
        },
      });
      expect(partial.practiceClips, hasLength(1));
      expect(partial.practiceClips.single.id, 'clip_b');
    });
  });

  group('LocalDocument 版本政策（v1／v2 低于地板一次性丢弃）', () {
    test('版本头读不出 → 认识多少读多少 + 只读', () {
      const onDisk = {
        'session': {
          'mastery': {'0': 'mastered'},
        },
        'prefs': {'layoutLocked': true},
      };
      final doc = LocalDocument.fromJson(onDisk);
      expect(doc.layoutLocked, isTrue);
      expect(LocalDocument.versionPolicy.isWritable(onDisk), isFalse);
    });

    test('低于地板 → 空态；链上（v3）与更高版本（v5）读得出、可写性分明', () {
      for (final version in [1, 2]) {
        expect(
          LocalDocument.fromJson({
            'version': version,
            'session': {
              'mastery': {'0': 'mastered'},
            },
          }),
          const LocalDocument.empty(),
          reason: 'version=$version 低于地板',
        );
      }
      const onChain = {
        'version': 3,
        'prefs': {'layoutLocked': true},
      };
      expect(LocalDocument.fromJson(onChain).layoutLocked, isTrue);
      expect(LocalDocument.versionPolicy.isWritable(onChain), isTrue);

      const higher = {
        'version': 5,
        'prefs': {'layoutLocked': true},
      };
      // 更高版本按「认识多少读多少」打开。
      expect(LocalDocument.fromJson(higher).layoutLocked, isTrue);
      expect(LocalDocument.versionPolicy.isWritable(higher), isFalse);
    });
  });

  group('LocalDocument 逐层陌生键保底（文档/段/overlay 子对象）', () {
    test('三层未知键都原样带回、写回不丢', () {
      final fromFile = LocalDocument.fromJson(const {
        'version': 3,
        'docReserved': [1],
        'session': {
          'mastery': {'0': 'mastered'},
          'sessionReserved': 's',
        },
        'prefs': {
          'layoutLocked': true,
          'prefsReserved': 'p',
          'overlay': {'dx': 1.0, 'dy': 2.0, 'overlayReserved': 'o'},
        },
      });
      final json = fromFile.toJson();
      expect(json['docReserved'], [1]);
      expect(json['session']['sessionReserved'], 's');
      expect(json['prefs']['prefsReserved'], 'p');
      expect(json['prefs']['overlay']['overlayReserved'], 'o');
    });

    test('保底区不参与相等：本版本字段相同的文档互相相等', () {
      final a = LocalDocument.fromJson(const {
        'version': 3,
        'docReserved': 'x',
        'prefs': {'prefsReserved': 'y'},
      });
      expect(a, const LocalDocument.empty());
    });

    test('本版本字段变化才判不等（overlay 字段参与相等）', () {
      expect(
        const LocalDocument(
              overlay: OverlayPlacementFields(dx: 1.0, dy: 0.0),
            ) ==
            const LocalDocument(),
        isFalse,
      );
      expect(
        const LocalDocument(
              overlay: OverlayPlacementFields(rectWidthFactor: 1.5),
            ) ==
            const LocalDocument(
              overlay: OverlayPlacementFields(rectWidthFactor: 1.5),
            ),
        isTrue,
      );
      expect(
        const LocalDocument(mastery: {0: LearningMastery.mastered}) ==
            const LocalDocument(),
        isFalse,
      );
    });
  });

  group('LocalDocument wither 链携带（各段字段互不擦除）', () {
    test('wither 链全程携带浮层与偏好字段', () {
      const doc = LocalDocument(
        overlay: OverlayPlacementFields(
          dx: 1.0,
          dy: 2.0,
          landscapeCompareDx: 3.0,
          landscapeCompareDy: 4.0,
          rectWidthFactor: 1.5,
          pendulumScale: 0.8,
        ),
      );
      final chained = doc
          .withSnap(previewSnapEnabled: false)
          .withLayoutLocked(true);
      expect(chained.overlay, doc.overlay);
      expect(chained.layoutLocked, isTrue);
    });
  });

  group('LocalDocument 倍速记忆', () {
    test('写入倍率后读回同一个值（两位小数精度）', () {
      const doc = LocalDocument(speedRate: 0.5);

      final json = doc.toJson();
      expect(json['prefs']['speedRate'], 0.5);
      expect(json['version'], 4);

      final restored = LocalDocument.fromJson(json);
      expect(restored.speedRate, 0.5);
      expect(restored, doc);
      expect(restored.hashCode, doc.hashCode);
    });

    test('两位小数取整：文件里更精的值读入归到两位小数', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {'speedRate': 1.256},
      });
      expect(doc.speedRate, 1.26);
      // 取整后的值写回原样。
      expect(doc.toJson()['prefs']['speedRate'], 1.26);
    });

    test('从未记过倍率：文件中没有 speedRate 键，读回为「没有意见」', () {
      const doc = LocalDocument();
      expect(doc.speedRate, isNull);
      expect(doc.toJson()['prefs'].containsKey('speedRate'), isFalse);

      final restored = LocalDocument.fromJson(doc.toJson());
      expect(restored.speedRate, isNull);
    });

    test('越界值与错误形状按「没有意见」兜底，不抛错', () {
      for (final raw in const [
        0.05, // 低于 0.1×
        2.5, // 高于 2.0×
        '1.25', // 字符串
        [1.25], // 列表
        {'value': 1.25}, // 对象
        true, // 布尔
      ]) {
        final doc = LocalDocument.fromJson({
          'version': 3,
          'prefs': {'speedRate': raw},
        });
        expect(doc.speedRate, isNull, reason: 'raw=$raw');
        // 非法值不落盘回写（该键省略）。
        expect(
          doc.toJson()['prefs'].containsKey('speedRate'),
          isFalse,
          reason: 'raw=$raw',
        );
      }
    });

    test('边界值在范围内：0.1 与 2.0 读回原值', () {
      expect(
        LocalDocument.fromJson(const {
          'version': 3,
          'prefs': {'speedRate': 0.1},
        }).speedRate,
        0.1,
      );
      expect(
        LocalDocument.fromJson(const {
          'version': 3,
          'prefs': {'speedRate': 2.0},
        }).speedRate,
        2.0,
      );
    });

    test('陌生键不被吞：speedRate 与 prefs 陌生键互不擦除', () {
      final fromFile = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {'speedRate': 0.75, 'oldReserved': 'keep-me'},
      });
      final json = fromFile.toJson();
      expect(json['prefs']['speedRate'], 0.75);
      expect(json['prefs']['oldReserved'], 'keep-me');

      // 写入倍率不动陌生键。
      final written = fromFile.withSpeedRate(1.25).toJson();
      expect(written['prefs']['speedRate'], 1.25);
      expect(written['prefs']['oldReserved'], 'keep-me');
    });

    test('相等判定纳入 speedRate：只有倍率变化时判不等', () {
      expect(
        const LocalDocument(speedRate: 0.5) == const LocalDocument(),
        isFalse,
      );
      expect(
        const LocalDocument(speedRate: 0.5) ==
            const LocalDocument(speedRate: 0.5),
        isTrue,
      );
      // 其余字段不变时不产生写盘：陌生键差异不参与相等。
      expect(
        LocalDocument.fromJson(const {
              'version': 3,
              'prefs': {'speedRate': 0.5, 'extra': 1},
            }) ==
            const LocalDocument(speedRate: 0.5),
        isTrue,
      );
    });
  });

  group('LocalDocument 节拍提示记忆', () {
    test('全字段往返：五值写进 prefs.beatPrompt，读回逐字段相等', () {
      const doc = LocalDocument(
        beatPrompt: BeatPromptMemoryFields(
          animation: true,
          animationStyle: 'pendulum',
          sound: false,
          soundType: 'vocal',
          halfBeat: true,
        ),
      );

      final json = doc.toJson();
      expect(json['version'], 4);
      expect(json['prefs']['beatPrompt'], {
        'animation': true,
        'animationStyle': 'pendulum',
        'sound': false,
        'soundType': 'vocal',
        'halfBeat': true,
      });

      final restored = LocalDocument.fromJson(json);
      expect(restored.beatPrompt!.animation, isTrue);
      expect(restored.beatPrompt!.animationStyle, 'pendulum');
      expect(restored.beatPrompt!.sound, isFalse);
      expect(restored.beatPrompt!.soundType, 'vocal');
      expect(restored.beatPrompt!.halfBeat, isTrue);
      expect(restored, doc);
      expect(restored.hashCode, doc.hashCode);
    });

    test('只写部分字段：缺席字段读回仍是缺席，不被补成默认值', () {
      const doc = LocalDocument(
        beatPrompt: BeatPromptMemoryFields(animation: true, soundType: 'geigi'),
      );

      final json = doc.toJson();
      expect(json['prefs']['beatPrompt'], {
        'animation': true,
        'soundType': 'geigi',
      });

      final restored = LocalDocument.fromJson(json);
      expect(restored.beatPrompt!.animation, isTrue);
      expect(restored.beatPrompt!.soundType, 'geigi');
      expect(restored.beatPrompt!.animationStyle, isNull);
      expect(restored.beatPrompt!.sound, isNull);
      expect(restored.beatPrompt!.halfBeat, isNull);
      expect(restored, doc);
    });

    test('整份记录不存在 vs 记录在但全字段缺席，两种状态可区分', () {
      const noRecord = LocalDocument();
      const emptyRecord = LocalDocument(beatPrompt: BeatPromptMemoryFields());

      // 无记录：prefs 里不写 beatPrompt 键。
      expect(noRecord.toJson()['prefs'].containsKey('beatPrompt'), isFalse);
      // 有记录但全缺席：beatPrompt 键在，值为空对象。
      expect(emptyRecord.toJson()['prefs']['beatPrompt'], <String, dynamic>{});

      expect(
        LocalDocument.fromJson(emptyRecord.toJson()).beatPrompt,
        isNotNull,
      );
      expect(LocalDocument.fromJson(noRecord.toJson()).beatPrompt, isNull);
      expect(emptyRecord == noRecord, isFalse);
    });

    test('未知键保底：prefs 段与 beatPrompt 子对象里的陌生键原样带回写回', () {
      final fromFile = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'beatPromptReserved': 'p',
          'beatPrompt': {'animation': true, 'memoryReserved': 'm'},
        },
      });
      final json = fromFile.toJson();
      expect(json['prefs']['beatPromptReserved'], 'p');
      expect(json['prefs']['beatPrompt']['memoryReserved'], 'm');
      expect(json['prefs']['beatPrompt']['animation'], isTrue);
      // 保底区不参与相等：本版本字段相同的文档互相相等。
      expect(
        fromFile,
        const LocalDocument(
          beatPrompt: BeatPromptMemoryFields(animation: true),
        ),
      );
    });

    test('非法枚举名按缺席兜底：未知 animationStyle 读回为缺席', () {
      final doc = LocalDocument.fromJson(const {
        'version': 3,
        'prefs': {
          'beatPrompt': {'animationStyle': 'junk', 'sound': true},
        },
      });
      expect(doc.beatPrompt!.animationStyle, isNull);
      expect(doc.beatPrompt!.sound, isTrue);
      // 非法名不落盘回写（该键省略）。
      expect(
        doc.toJson()['prefs']['beatPrompt'].containsKey('animationStyle'),
        isFalse,
      );
    });

    test('wither 链携带：withBeatPrompt 不擦其它段字段，其它写入不擦记忆', () {
      const memory = BeatPromptMemoryFields(animation: true, sound: false);
      final chained = const LocalDocument(
        overlay: OverlayPlacementFields(dx: 1.0, dy: 2.0),
      ).withBeatPrompt(memory).withSnap(previewSnapEnabled: false);
      expect(chained.beatPrompt, memory);
      expect(chained.overlay!.dx, 1.0);
      expect(chained.previewSnapEnabled, isFalse);

      final other = const LocalDocument(beatPrompt: memory)
          .withLayoutLocked(true);
      expect(other.beatPrompt, memory);
      expect(other.layoutLocked, isTrue);
    });

    test('词表锁：记忆单元枚举名与播放器层枚举名一致', () {
      // 纯值层持枚举名字符串；播放器层枚举改名时这里先红，
      // 防止词表静默脱钩、记忆值读入跌为缺席。
      expect(BeatAnimationStyle.values.map((s) => s.name).toSet(), {
        'bar',
        'pendulum',
      });
      expect(MetronomeSoundType.values.map((s) => s.name).toSet(), {
        'normal',
        'vocal',
        'geigi',
      });
    });

    test('字段参与相等：记忆值不同判不等，null 与空记录判不等', () {
      expect(
        const LocalDocument(
              beatPrompt: BeatPromptMemoryFields(animation: true),
            ) ==
            const LocalDocument(),
        isFalse,
      );
      expect(
        const LocalDocument(
              beatPrompt: BeatPromptMemoryFields(soundType: 'normal'),
            ) ==
            const LocalDocument(
              beatPrompt: BeatPromptMemoryFields(soundType: 'normal'),
            ),
        isTrue,
      );
    });
  });

  group('v3 → v4 迁移：旧取景键直接复位', () {
    const v3Doc = <String, dynamic>{
      'version': 3,
      'docReserved': {'keep': 1},
      'session': {
        'mastery': {'0': 'mastered'},
        'sessionReserved': 's',
      },
      'prefs': {
        'layoutLocked': true,
        'framingSource': {'scale': 2.5, 'offsetX': 0.1, 'offsetY': -0.05},
        'framingPractice': {'scale': 1.5, 'offsetX': 0.2, 'offsetY': 0.3},
        'prefsReserved': 'p',
      },
    };

    test('结构断言：版本链从地板无缝连到本版', () {
      expect(LocalDocument.versionPolicy.floor, 3);
      expect(LocalDocument.versionPolicy.currentVersion, 4);
      expect(LocalDocument.versionPolicy.steps.map((step) => step.from), [3]);
    });

    test('v3 打开：旧取景两键直接丢弃，其余字段与陌生键逐字不变', () {
      final doc = LocalDocument.fromJson(v3Doc);
      expect(doc.layoutLocked, isTrue);

      final json = doc.toJson();
      expect(json['version'], 4);
      final prefs = json['prefs'] as Map;
      expect(prefs.containsKey('framingSource'), isFalse);
      expect(prefs.containsKey('framingPractice'), isFalse);
      // 与取景无关的其余字段、段与逐层陌生键原样带过。
      expect(json['docReserved'], {'keep': 1});
      expect((json['session'] as Map)['sessionReserved'], 's');
      expect(prefs['prefsReserved'], 'p');
      expect(prefs['layoutLocked'], true);
    });

    test('迁移幂等：迁后文档再解码再写出不再变化', () {
      final once = LocalDocument.fromJson(v3Doc).toJson();
      final twice = LocalDocument.fromJson(once).toJson();
      expect(twice, once);
    });
  });
}
