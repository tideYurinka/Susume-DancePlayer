import 'dart:convert';
import 'dart:io';

import 'package:dance_learning_app/annotation/learning_segment_attributes.dart';
import 'package:dance_learning_app/package/susume_package.dart';
import 'package:dance_learning_app/share/dance_share.dart';
import 'package:dance_learning_app/core/document_codec.dart';
import 'package:dance_learning_app/core/document_version_policy.dart';
import 'package:dance_learning_app/persistence/practice_plan.dart';

import '../helpers/in_memory_video_document_storage.dart';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/in_memory_practice_plan_storage.dart';

void main() {
  late InMemoryPracticePlanStorage storage;
  late PracticePlanStore store;

  setUp(() {
    storage = InMemoryPracticePlanStorage();
    store = PracticePlanStore(storage);
  });

  DanceDdl ddl(
    String date, {
    String occasion = '约舞',
    String remark = '',
    int? leadDays,
    List<PlanChecklistItem> checklist = const [],
  }) => DanceDdl(
    date: DateTime.parse(date),
    occasion: occasion,
    remark: remark,
    leadDays: leadDays,
    checklist: checklist,
  );

  test('无该舞条目 = 没有 DDL（文件缺失按空态兜底）', () async {
    expect(await store.ddlOf('v1'), isNull);
  });

  test('设 DDL 后可读回五要素；重启（新 store 同一文件）仍在', () async {
    await store.setDdl(
      videoId: 'v1',
      ddl: ddl(
        '2026-10-01',
        occasion: '演出',
        remark: '带扇子',
        leadDays: 3,
        checklist: const [
          PlanChecklistItem(text: '练发型'),
          PlanChecklistItem(text: '充电宝', checked: true),
        ],
      ),
    );
    expect(storage.savedJson, isNotNull);

    final reopened = PracticePlanStore(storage);
    final read = await reopened.ddlOf('v1');
    expect(read, isNotNull);
    expect(read!.date, DateTime(2026, 10, 1));
    expect(read.occasion, '演出');
    expect(read.remark, '带扇子');
    expect(read.leadDays, 3);
    expect(read.checklist, const [
      PlanChecklistItem(text: '练发型'),
      PlanChecklistItem(text: '充电宝', checked: true),
    ]);
  });

  test('改期 = 整体替换该舞 DDL，其余舞不受影响', () async {
    await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
    await store.setDdl(videoId: 'v2', ddl: ddl('2026-11-11'));
    await store.setDdl(
      videoId: 'v1',
      ddl: ddl('2026-10-20', occasion: '约舞'),
    );
    expect((await store.ddlOf('v1'))!.date, DateTime(2026, 10, 20));
    expect((await store.ddlOf('v2'))!.date, DateTime(2026, 11, 11));
  });

  test('清除 DDL 后读回为空；再清一次仍成功', () async {
    await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
    await store.clearDdl('v1');
    expect(await store.ddlOf('v1'), isNull);
    expect(await store.clearDdl('v1'), isTrue);
  });

  test('清单项可增、可勾、可删；勾选态随重启保留', () async {
    await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
    await store.addChecklistItem(videoId: 'v1', text: '带水');
    await store.addChecklistItem(videoId: 'v1', text: '充电宝');
    await store.setChecklistItemChecked(videoId: 'v1', index: 0, checked: true);

    var read = await store.ddlOf('v1');
    expect(read!.checklist.map((i) => i.text), ['带水', '充电宝']);
    expect(read.checklist[0].checked, isTrue);
    expect(read.checklist[1].checked, isFalse);

    await store.removeChecklistItem(videoId: 'v1', index: 0);
    read = await store.ddlOf('v1');
    expect(read!.checklist.map((i) => i.text), ['充电宝']);

    // 重启后勾选态仍在。
    final reopened = PracticePlanStore(storage);
    read = await reopened.ddlOf('v1');
    expect(read!.checklist.single, const PlanChecklistItem(text: '充电宝'));
  });

  test('清单操作作用于不存在的 DDL：no-op，不建条目', () async {
    await store.addChecklistItem(videoId: 'v1', text: '带水');
    expect(await store.ddlOf('v1'), isNull);
    expect(
      await store.setChecklistItemChecked(
        videoId: 'v1',
        index: 0,
        checked: true,
      ),
      isFalse,
    );
  });

  test('缺字段兜底：无 ddl 键 = 没有 DDL；清单缺项 = 空清单', () async {
    storage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion,
      'entries': [
        {'videoId': 'v1'},
        {
          'videoId': 'v2',
          'ddl': {'date': '2026-10-01'},
        },
      ],
    };
    final reopened = PracticePlanStore(storage);
    final read = await reopened.ddlOf('v2');
    expect(read!.date, DateTime(2026, 10, 1));
    expect(read.occasion, '');
    expect(read.remark, '');
    expect(read.leadDays, isNull);
    expect(read.checklist, isEmpty);
  });

  test('videoId 缺失的损坏条目整条丢弃', () async {
    storage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion,
      'entries': [
        {
          'ddl': {'date': '2026-10-01'},
        },
        {
          'videoId': 'v1',
          'ddl': {'date': '2026-10-01'},
        },
      ],
    };
    final reopened = PracticePlanStore(storage);
    expect(await reopened.ddlOf('v1'), isNotNull);
    await reopened.setDdl(videoId: 'v1', ddl: ddl('2026-10-02'));
    final entries = (storage.savedJson!['entries'] as List)
        .cast<Map<String, dynamic>>();
    expect(entries.length, 1);
    expect(entries.single['videoId'], 'v1');
  });

  test('非法 DDL 日期：该舞按没有 DDL 兜底', () async {
    storage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion,
      'entries': [
        {
          'videoId': 'v1',
          'ddl': {'date': 'not-a-date'},
        },
      ],
    };
    expect(await PracticePlanStore(storage).ddlOf('v1'), isNull);
  });

  test('未知键三级保留：文档 / 条目 / DDL / 清单项各层原样带回、写回原样', () async {
    storage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion,
      'futureDocKey': 1,
      'entries': [
        {
          'videoId': 'v1',
          'futureEntryKey': 'e',
          'ddl': {
            'date': '2026-10-01',
            'futureDdlKey': true,
            'checklist': [
              {'text': '带水', 'checked': false, 'futureItemKey': 'i'},
            ],
          },
        },
      ],
    };
    final reopened = PracticePlanStore(storage);
    await reopened.setChecklistItemChecked(
      videoId: 'v1',
      index: 0,
      checked: true,
    );

    final saved = storage.savedJson!;
    expect(saved['futureDocKey'], 1);
    final entry = (saved['entries'] as List).single as Map<String, dynamic>;
    expect(entry['futureEntryKey'], 'e');
    final savedDdl = entry['ddl'] as Map<String, dynamic>;
    expect(savedDdl['futureDdlKey'], true);
    final item = (savedDdl['checklist'] as List).single as Map<String, dynamic>;
    expect(item['futureItemKey'], 'i');
    expect(item['checked'], true);
  });

  test('版本政策：版本头读不出与更高版本都读得出、只读不写回', () async {
    const rawMissingVersion = <String, dynamic>{
      'entries': [
        {
          'videoId': 'v1',
          'ddl': {'date': '2026-10-01'},
        },
      ],
    };
    storage.rawJson = Map.of(rawMissingVersion);
    final storeMissingVersion = PracticePlanStore(storage);
    expect(
      (await storeMissingVersion.ddlOf('v1'))!.date,
      DateTime(2026, 10, 1),
    );
    expect(
      await storeMissingVersion.setDdl(videoId: 'v1', ddl: ddl('2026-10-02')),
      isFalse,
    );
    expect(storage.saveCount, 0, reason: '只读文件不写回');
    expect(
      (await PracticePlanStore(storage).ddlOf('v1'))!.date,
      DateTime(2026, 10, 1),
      reason: '盘上原文一字未动',
    );

    storage.rawJson = {
      'version': PracticePlanDocument.versionPolicy.currentVersion + 1,
      'entries': [
        {
          'videoId': 'v1',
          'ddl': {'date': '2026-10-01'},
        },
      ],
    };
    final storeHigher = PracticePlanStore(storage);
    expect((await storeHigher.ddlOf('v1'))!.date, DateTime(2026, 10, 1));
    expect(
      await storeHigher.setDdl(videoId: 'v1', ddl: ddl('2026-10-02')),
      isFalse,
    );
    expect(storage.saveCount, 0, reason: '只读文件不写回');
  });

  test('列表形状版本能力：合成两级链上中间版本可升位', () {
    final policy = DocumentVersionPolicy(
      floor: 1,
      steps: [
        MigrationStep(1, (json) => {...json, 'v1Shape': true}),
        MigrationStep(2, (json) => {...json, 'v2Shape': true}),
      ],
    );
    final codec =
        ListDocumentCodec<PracticePlanDocument, DancePlanEntry,
            DancePlanEntryField>(
          policy: policy,
          listKey: 'entries',
          elementCodec: DancePlanEntry.codec,
          empty: () => const PracticePlanDocument.empty(),
          build: (elements) => PracticePlanDocument(entries: elements),
          listOf: (doc) => doc.entries,
          extraOf: (doc) => doc.extra,
          withExtra: (doc, extra) =>
              PracticePlanDocument(entries: doc.entries, extra: extra),
        );
    final onDisk = <String, Object?>{
      'version': 1,
      'entries': [const DancePlanEntry(videoId: 'v1').toJson()],
    };
    final doc = codec.decode(onDisk);
    expect(doc.entries, hasLength(1));
    expect(doc.extra['v1Shape'], isTrue);
    expect(doc.extra['v2Shape'], isTrue);
    expect(policy.isWritable(onDisk), isTrue);
    expect(codec.encode(doc)['version'], 3);
  });

  test('写失败静默承接：内存态保留，下次写重试落盘', () async {
    storage.saveError = Exception('disk full');
    await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
    expect((await store.ddlOf('v1'))!.date, DateTime(2026, 10, 1));

    storage.saveError = null;
    await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-02'));
    expect(
      (await PracticePlanStore(storage).ddlOf('v1'))!.date,
      DateTime(2026, 10, 2),
    );
  });

  test('纯件归一：空标签 / 空备注归空串，空文本清单项丢弃，文本去首尾空白', () {
    final value = ddl(
      '2026-10-01',
      occasion: ' 演出 ',
      remark: ' 带扇子 ',
      checklist: const [
        PlanChecklistItem(text: ' 带水 '),
        PlanChecklistItem(text: '   '),
      ],
    ).normalized;
    expect(value.occasion, '演出');
    expect(value.remark, '带扇子');
    expect(value.checklist, const [PlanChecklistItem(text: '带水')]);
  });

  test('纯件相等：登记字段相同即相等，保底区不参与', () {
    final a = ddl(
      '2026-10-01',
      leadDays: 3,
      checklist: const [PlanChecklistItem(text: '带水', checked: true)],
    );
    final b = ddl(
      '2026-10-01',
      leadDays: 3,
      checklist: const [PlanChecklistItem(text: '带水', checked: true)],
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(ddl('2026-10-02')));
    expect(a, isNot(ddl('2026-10-01', occasion: '演出')));
    expect(a, isNot(ddl('2026-10-01', remark: 'x')));
    expect(a, isNot(ddl('2026-10-01', leadDays: 2)));
    expect(
      a,
      isNot(
        ddl('2026-10-01', checklist: const [PlanChecklistItem(text: '带水')]),
      ),
    );
  });

  PlanEvent event(
    String id, {
    String date = '2026-10-01',
    String? startTime,
    int? leadDays,
    String location = '',
    String remark = '',
    List<String> danceIds = const [],
    List<PlanChecklistItem> checklist = const [],
  }) => PlanEvent(
    id: id,
    date: DateTime.parse(date),
    startTime: startTime,
    leadDays: leadDays,
    location: location,
    remark: remark,
    danceIds: danceIds,
    checklist: checklist,
  );

  group('写盘通知钩子（推送排程随之取消 / 重排）', () {
    test('setDdl 与 clearDdl 成功即触发；无变化不触发', () async {
      var changes = 0;
      final hooked = PracticePlanStore(storage, onChanged: () => changes++);
      await hooked.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
      expect(changes, 1);
      var quietChanges = 0;
      final quiet = PracticePlanStore(
        InMemoryPracticePlanStorage(),
        onChanged: () => quietChanges++,
      );
      await quiet.entries();
      expect(quietChanges, 0, reason: '只装载不写盘不触发');
      await hooked.clearDdl('v1');
      expect(changes, 2);
    });
  });

  group('随舞事件', () {
    test('全字段往返：重启（新 store 同一文件）后各字段与两份清单一致', () async {
      await store.saveEvent(
        event(
          'ev-1',
          startTime: '18:30',
          leadDays: 2,
          location: '操场',
          remark: '自备水',
          danceIds: const ['v1', 'v2'],
          checklist: const [
            PlanChecklistItem(text: '服装'),
            PlanChecklistItem(text: '充电宝', checked: true),
          ],
        ),
      );

      final reopened = PracticePlanStore(storage);
      final events = await reopened.events();
      expect(events.length, 1);
      final read = events.single;
      expect(read.id, 'ev-1');
      expect(read.type, kPlanEventTypeSocial);
      expect(read.date, DateTime(2026, 10, 1));
      expect(read.startTime, '18:30');
      expect(read.leadDays, 2);
      expect(read.location, '操场');
      expect(read.remark, '自备水');
      expect(read.danceIds, const ['v1', 'v2']);
      expect(read.checklist, const [
        PlanChecklistItem(text: '服装'),
        PlanChecklistItem(text: '充电宝', checked: true),
      ]);
    });

    test('同 id 保存 = 替换（编辑），其它事件不受影响', () async {
      await store.saveEvent(event('ev-1', date: '2026-10-01'));
      await store.saveEvent(event('ev-2', date: '2026-10-02'));
      await store.saveEvent(event('ev-1', date: '2026-10-20', remark: '改期'));

      final events = await store.events();
      // 替换按原位置（落盘次序不打乱），新增追加在后。
      expect(events.map((e) => e.id), ['ev-1', 'ev-2']);
      expect(
        events.firstWhere((e) => e.id == 'ev-1').date,
        DateTime(2026, 10, 20),
      );
      expect(events.last.remark, '');
    });

    test('删除事件即连同其准备清单消失；再删一次仍成功', () async {
      await store.saveEvent(
        event('ev-1', checklist: const [PlanChecklistItem(text: '水')]),
      );
      expect(await store.deleteEvent('ev-1'), isTrue);
      expect(await store.events(), isEmpty);
      expect(await store.deleteEvent('ev-1'), isTrue);
    });

    test('缺项兜底：无 id 或无合法日期的事件整条丢弃；其余字段给默认', () async {
      storage.rawJson = {
        'version': PracticePlanDocument.versionPolicy.currentVersion,
        'events': [
          {'type': kPlanEventTypeSocial, 'date': '2026-10-01'},
          {'id': 'ev-2'},
          {'id': 'ev-3', 'type': kPlanEventTypeSocial, 'date': '2026-10-03'},
          {'id': 'ev-4', 'date': 'bad-date'},
        ],
      };
      final reopened = PracticePlanStore(storage);
      final events = await reopened.events();
      expect(events.map((e) => e.id), ['ev-3']);
      expect(events.single.startTime, isNull);
      expect(events.single.location, '');
      expect(events.single.remark, '');
      expect(events.single.danceIds, isEmpty);
      expect(events.single.checklist, isEmpty);
    });

    test('未知键保留：事件层原样带回、写回原样', () async {
      storage.rawJson = {
        'version': PracticePlanDocument.versionPolicy.currentVersion,
        'events': [
          {'id': 'ev-1', 'date': '2026-10-01', 'futureEventKey': 'x'},
        ],
      };
      final reopened = PracticePlanStore(storage);
      await reopened.saveEvent(event('ev-2'));

      final saved = (storage.savedJson!['events'] as List)
          .cast<Map<String, dynamic>>();
      expect(saved.first['futureEventKey'], 'x');
    });

    test('单条事件字段类型损坏：只丢该字段（或整条），不炸掉整份文档的 DDL 条目', () async {
      storage.rawJson = {
        'version': PracticePlanDocument.versionPolicy.currentVersion,
        'entries': [
          {
            'videoId': 'v1',
            'ddl': {'date': '2026-10-01'},
          },
        ],
        'events': [
          {
            'id': 'ev-1',
            'date': '2026-10-02',
            'danceIds': 'v1',
            'checklist': 'not-a-list',
          },
        ],
      };
      final reopened = PracticePlanStore(storage);
      expect(await reopened.ddlOf('v1'), isNotNull);
      final events = await reopened.events();
      expect(events.single.id, 'ev-1');
      expect(events.single.danceIds, isEmpty);
      expect(events.single.checklist, isEmpty);
    });

    test('events 键整体非列表：events 按空兜底，DDL 条目原样保留', () async {
      storage.rawJson = {
        'version': PracticePlanDocument.versionPolicy.currentVersion,
        'entries': [
          {
            'videoId': 'v1',
            'ddl': {'date': '2026-10-01'},
          },
        ],
        'events': 'oops',
      };
      final reopened = PracticePlanStore(storage);
      expect(await reopened.ddlOf('v1'), isNotNull);
      expect(await reopened.events(), isEmpty);
    });

    test('归一：文本去空白、空文本清单项丢弃', () async {
      await store.saveEvent(
        event(
          'ev-1',
          location: ' 操场 ',
          remark: ' 带扇子 ',
          checklist: const [
            PlanChecklistItem(text: ' 水 '),
            PlanChecklistItem(text: '  '),
          ],
        ),
      );
      final read = (await store.events()).single;
      expect(read.location, '操场');
      expect(read.remark, '带扇子');
      expect(read.checklist, const [PlanChecklistItem(text: '水')]);
    });
  });

  group('随舞曲库开关', () {
    test('默认开：无条目 = 开', () async {
      expect(await store.socialLibraryEnabledOf('v1'), isTrue);
    });

    test('关掉后读回关、重启仍在；开回 = 无 DDL 时条目一并清掉', () async {
      await store.setSocialLibrary(videoId: 'v1', enabled: false);
      expect(await store.socialLibraryEnabledOf('v1'), isFalse);

      final reopened = PracticePlanStore(storage);
      expect(await reopened.socialLibraryEnabledOf('v1'), isFalse);

      await reopened.setSocialLibrary(videoId: 'v1', enabled: true);
      expect(await reopened.socialLibraryEnabledOf('v1'), isTrue);
      expect(await reopened.socialLibraryDisabledIds(), isEmpty);
    });

    test('关掉开回不动既有 DDL 与清单', () async {
      await store.setDdl(
        videoId: 'v1',
        ddl: ddl('2026-10-01', checklist: const [PlanChecklistItem(text: '水')]),
      );
      await store.setSocialLibrary(videoId: 'v1', enabled: false);
      await store.setSocialLibrary(videoId: 'v1', enabled: true);

      final read = await store.ddlOf('v1');
      expect(read, isNotNull);
      expect(read!.checklist.single, const PlanChecklistItem(text: '水'));
    });

    test('清 DDL 后开关关的舞条目仍在（开关不丢）；开关开的舞条目消失', () async {
      await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
      await store.setDdl(videoId: 'v2', ddl: ddl('2026-10-02'));
      await store.setSocialLibrary(videoId: 'v1', enabled: false);

      await store.clearDdl('v1');
      await store.clearDdl('v2');

      expect(await store.ddlOf('v1'), isNull);
      expect(await store.socialLibraryEnabledOf('v1'), isFalse);
      expect(await store.socialLibraryEnabledOf('v2'), isTrue);
    });

    test('socialLibraryDisabledIds：缺项按开，只收显式关的舞', () async {
      storage.rawJson = {
        'version': PracticePlanDocument.versionPolicy.currentVersion,
        'entries': [
          {'videoId': 'v1'},
          {'videoId': 'v2', 'socialLibrary': false},
        ],
      };
      final reopened = PracticePlanStore(storage);
      expect(await reopened.socialLibraryDisabledIds(), {'v2'});
    });
  });

  group('隐私面：计划文档完全私密', () {
    test('计划写入不触碰公开标记与本地私密文档（markers / local 原样）', () async {
      final videoDoc = InMemoryVideoDocumentStorage(
        markers: {
          'version': 8,
          'meta': {'song': '海草舞'},
        },
        local: {'version': 1},
      );
      final planStore = PracticePlanStore(storage);
      await planStore.setDdl(
        videoId: 'v1',
        ddl: ddl('2026-10-01', remark: '机密'),
      );
      await planStore.addChecklistItem(videoId: 'v1', text: '带水');

      // 舞级文档原样：计划数据只住计划文档这一份文件。
      expect(await videoDoc.loadMarkers(), {
        'version': 8,
        'meta': {'song': '海草舞'},
      });
      expect(await videoDoc.loadLocal(), {'version': 1});
    });

    test('分享包不含计划数据：装配后包体 JSON 里找不到 DDL 私密文本', () async {
      final secret = '机密备注-唯一串';
      await store.setDdl(
        videoId: 'v1',
        ddl: ddl('2026-10-01', remark: secret),
      );

      final tempDir = await Directory.systemTemp.createTemp('plan_privacy');
      addTearDown(() => tempDir.delete(recursive: true));
      final output = await assembleDancePackage(
        outputDir: tempDir,
        manifest: SusumeManifest(
          videoId: 'abc123',
          schemeName: '海草舞',
          schemeId: 'scheme-1',
        ),
        markers: {
          'version': 8,
          'meta': {'song': '海草舞'},
        },
        videoFileName: 'source.mp4',
      );
      final parsed = await readSusumePackage(output.path);
      // 分享包不是整机备份载荷：practicePlan 只在 backup 类包里出现。
      expect(parsed.isBackup, isFalse);
      expect(parsed.manifest.schemeName.contains(secret), isFalse);
      expect(parsed.manifest.schemeRemark.contains(secret), isFalse);
      expect(jsonEncode(parsed.markers).contains(secret), isFalse);
    });
  });

  group('生命周期：恢复全量替换与删舞清理', () {
    test('replaceWithJson：按备份原文整份替换，条目与事件逐字段、未知键原样落位', () async {
      await store.setDdl(videoId: 'old', ddl: ddl('2026-01-01'));

      final backupJson = <String, dynamic>{
        'version': 1,
        'entries': [
          {
            'videoId': 'v1',
            'socialLibrary': false,
            'ddl': {
              'date': '2026-10-01',
              'occasion': '演出',
              'remark': '道具扇子',
              'leadDays': 3,
              'checklist': [
                {'text': '带水', 'checked': true},
              ],
              'settlement': {'outcome': 'onTime', 'judgedOn': '2026-10-02'},
            },
          },
        ],
        'events': [
          {
            'id': 'e1',
            'type': kPlanEventTypeSocial,
            'date': '2026-11-08',
            'startTime': '19:30',
            'location': '滨江区',
            'remark': '带音箱',
            'danceIds': ['v1', 'v2'],
            'checklist': [
              {'text': '充电宝', 'checked': true},
            ],
          },
        ],
        'unknownTop': {'kept': true},
      };
      final ok = await store.replaceWithJson(backupJson);

      expect(ok, isTrue);
      expect(storage.savedJson, backupJson);
      expect(await store.ddlOf('old'), isNull); // 替换不是合并
      final expected = ddl(
        '2026-10-01',
        occasion: '演出',
        remark: '道具扇子',
        leadDays: 3,
        checklist: const [PlanChecklistItem(text: '带水', checked: true)],
      ).withSettlement(
        DdlSettlement(
          outcome: DdlSettlementOutcome.onTime,
          judgedOn: DateTime(2026, 10, 2),
        ),
      );
      expect(await store.ddlOf('v1'), expected);
      // 随舞曲库开关：开关关着的条目随原文落位（缺项按开）。
      expect(await store.socialLibraryEnabledOf('v1'), isFalse);
      // 事件逐字段落位。
      expect(await store.events(), [
        PlanEvent(
          id: 'e1',
          type: kPlanEventTypeSocial,
          date: DateTime(2026, 11, 8),
          startTime: '19:30',
          location: '滨江区',
          remark: '带音箱',
          danceIds: const ['v1', 'v2'],
          checklist: const [PlanChecklistItem(text: '充电宝', checked: true)],
        ),
      ]);
      // 重启（新 store 同一文件）逐字段仍在。
      final reopened = PracticePlanStore(storage);
      expect(await reopened.ddlOf('v1'), expected);
      expect(await reopened.events(), await store.events());
    });

    test('replaceWithJson：损坏的备份原文按空态替换，盘上不残留损坏原文（恢复 = 显式全量替换）', () async {
      await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));

      await store.replaceWithJson({'version': 99, 'entries': 'bad'});

      expect(await store.ddlOf('v1'), isNull);
      expect(storage.savedJson, const PracticePlanDocument.empty().toJson());
    });

    test('replaceWithJson：写失败回滚内存态并返回 false，下次写重试落盘', () async {
      await store.setDdl(videoId: 'v1', ddl: ddl('2026-01-01'));
      storage.saveError = StateError('磁盘满');

      expect(
        await store.replaceWithJson({
          'version': 1,
          'entries': [
            {
              'videoId': 'v2',
              'ddl': {'date': '2026-11-05'},
            },
          ],
        }),
        isFalse,
      );
      // 内存回滚：仍是替换前的本机计划（store 单例下不与磁盘分叉）。
      expect(await store.ddlOf('v2'), isNull);
      expect(await store.ddlOf('v1'), ddl('2026-01-01'));

      storage.saveError = null;
      expect(await store.setDdl(videoId: 'v3', ddl: ddl('2026-12-01')), isTrue);
      expect(await store.ddlOf('v1'), ddl('2026-01-01'));
      expect(await store.ddlOf('v3'), ddl('2026-12-01'));
    });

    test('retainDances：不在保留集里的舞条目被清、事件只摘其关联项，其余保留；无变化不写盘', () async {
      await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01'));
      await store.setDdl(videoId: 'v2', ddl: ddl('2026-11-05'));
      await store.saveEvent(
        PlanEvent(
          id: 'e1',
          date: DateTime(2026, 11, 8),
          danceIds: const ['v1', 'v2'],
        ),
      );
      final before = storage.saveCount;

      expect(await store.retainDances({'v2'}), isTrue);
      expect(await store.ddlOf('v1'), isNull);
      expect(await store.ddlOf('v2'), ddl('2026-11-05'));
      // 事件条目保留，关联清单只剩 v2。
      expect((await store.events()).single.id, 'e1');
      expect((await store.events()).single.danceIds, ['v2']);
      expect(storage.saveCount, before + 1);

      // 再保留一次：条目与事件关联都无变化，不写盘（幂等）。
      expect(await store.retainDances({'v2'}), isTrue);
      expect(storage.saveCount, before + 1);
    });

    test('removeDance：该舞条目整条移除、事件保留且关联清单少一项（可为空）', () async {
      await store.setDdl(videoId: 'v1', ddl: ddl('2026-10-01', remark: '备注'));
      await store.setDdl(videoId: 'v2', ddl: ddl('2026-11-05'));
      await store.saveEvent(
        PlanEvent(
          id: 'e1',
          date: DateTime(2026, 11, 8),
          danceIds: const ['v1', 'v2'],
        ),
      );
      await store.saveEvent(
        PlanEvent(id: 'e2', date: DateTime(2026, 12, 1), danceIds: const ['v1']),
      );

      expect(await store.removeDance('v1'), isTrue);
      // 条目：v1 的没了，v2 的还在。
      expect(await store.ddlOf('v1'), isNull);
      expect(await store.ddlOf('v2'), ddl('2026-11-05'));
      // 事件都在：e1 关联清单少一项，e2 清单为空；他舞事件不受影响。
      final events = await store.events();
      expect(events.map((e) => e.id), ['e1', 'e2']);
      expect(events[0].danceIds, ['v2']);
      expect(events[1].danceIds, isEmpty);
      // 再删一次与删不存在的舞：无变化不写盘，仍视为成功。
      final before = storage.saveCount;
      expect(await store.removeDance('v1'), isTrue);
      expect(await store.removeDance('missing'), isTrue);
      expect(storage.saveCount, before);
    });
  });

  group('到期落档与装载补判（假时钟）', () {
    /// 预置一份已过期的未落档 DDL（2026-10-01，时钟停在 2026-10-02）。
    void seedPastDueDdl({DateTime? date}) {
      storage.rawJson = PracticePlanDocument(
        entries: [
          DancePlanEntry(
            videoId: 'v1',
            ddl: DanceDdl(date: date ?? DateTime(2026, 10, 1)),
          ),
        ],
      ).toJson();
    }

    DateTime clock() => DateTime(2026, 10, 2, 9, 0);
    final mastered = <LearningMastery>{LearningMastery.mastered};
    final mixed = <LearningMastery>{
      LearningMastery.mastered,
      LearningMastery.familiar,
    };

    test('装载补判：已过到期日未落档的条目判定一次并落盘（全段掌握=按时）', () async {
      seedPastDueDdl();
      final backfilling = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      final read = await backfilling.ddlOf('v1');
      expect(read!.settlement!.outcome, DdlSettlementOutcome.onTime);
      expect(read.settlement!.judgedOn, DateTime(2026, 10, 2));
      expect(storage.savedJson, isNotNull);
    });

    test('一段未达判逾期；零段舞（空集）判逾期', () async {
      seedPastDueDdl();
      final overdue = await PracticePlanStore(
        storage,
        masteryOf: (_) async => mixed,
        clock: clock,
      ).ddlOf('v1');
      expect(overdue!.settlement!.outcome, DdlSettlementOutcome.overdue);

      seedPastDueDdl();
      final zeroSegments = await PracticePlanStore(
        storage,
        masteryOf: (_) async => const <LearningMastery>{},
        clock: clock,
      ).ddlOf('v1');
      expect(zeroSegments!.settlement!.outcome, DdlSettlementOutcome.overdue);
    });

    test('未到期不预判：剩余天数 ≥ 0 的条目装载后仍无落档、不写盘', () async {
      seedPastDueDdl(date: DateTime(2026, 10, 2));
      final store2 = PracticePlanStore(
        storage,
        masteryOf: (_) async => mixed,
        clock: clock,
      );
      expect((await store2.ddlOf('v1'))!.settlement, isNull);
      expect(storage.saveCount, 0);
    });

    test('幂等：已落档条目不被重写，段状态再变化（档位读面变化）也不改写', () async {
      seedPastDueDdl();
      final settled = PracticePlanStore(
        storage,
        masteryOf: (_) async => mixed,
        clock: clock,
      );
      final first = await settled.ddlOf('v1');
      expect(first!.settlement!.outcome, DdlSettlementOutcome.overdue);
      final savesAfterFirst = storage.saveCount;

      // 重启 + 档位读面已变（补到全掌握）：历史仍逾期，不重写、不写盘。
      final reopened = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: () => DateTime(2026, 10, 5),
      );
      final second = await reopened.ddlOf('v1');
      expect(second!.settlement, first.settlement);
      expect(storage.saveCount, savesAfterFirst);
    });

    test('改期后落档重置：同日改写保留落档，改期由装载按新日期重算', () async {
      seedPastDueDdl();
      final backfilling = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      expect(
        (await backfilling.ddlOf('v1'))!.settlement!.outcome,
        DdlSettlementOutcome.onTime,
      );

      // 同日改写（改备注）：落档保留。
      await backfilling.setDdl(
        videoId: 'v1',
        ddl: ddl('2026-10-01', remark: '带扇子'),
      );
      expect(
        (await backfilling.ddlOf('v1'))!.settlement!.outcome,
        DdlSettlementOutcome.onTime,
      );

      // 改期到新的已过期日：落档重置，重启装载按新日期重判。
      await backfilling.setDdl(videoId: 'v1', ddl: ddl('2026-09-20'));
      expect((await backfilling.ddlOf('v1'))!.settlement, isNull);
      final reopened = PracticePlanStore(
        storage,
        masteryOf: (_) async => mixed,
        clock: clock,
      );
      final rejudged = await reopened.ddlOf('v1');
      expect(rejudged!.settlement!.outcome, DdlSettlementOutcome.overdue);
      expect(rejudged.settlement!.judgedOn, DateTime(2026, 10, 2));

      // 改期到未到期日：无落档也不预判。
      await reopened.setDdl(videoId: 'v1', ddl: ddl('2027-01-01'));
      final future = await reopened.ddlOf('v1');
      expect(future!.settlement, isNull);
      final afterReload = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      expect((await afterReload.ddlOf('v1'))!.settlement, isNull);
    });

    test('清除后无落档：条目整条移除，重启读回为空', () async {
      seedPastDueDdl();
      final backfilling = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      await backfilling.ddlOf('v1');
      await backfilling.clearDdl('v1');
      expect((await backfilling.ddlOf('v1')), isNull);
      final reopened = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      expect((await reopened.ddlOf('v1')), isNull);
    });

    test('落档后改清单 / 改备注：copyWith 路径不动落档（只写一次）', () async {
      seedPastDueDdl();
      final backfilling = PracticePlanStore(
        storage,
        masteryOf: (_) async => mastered,
        clock: clock,
      );
      expect(
        (await backfilling.ddlOf('v1'))!.settlement!.outcome,
        DdlSettlementOutcome.onTime,
      );

      await backfilling.addChecklistItem(videoId: 'v1', text: '充电宝');
      await backfilling.setChecklistItemChecked(
        videoId: 'v1',
        index: 0,
        checked: true,
      );
      await backfilling.removeChecklistItem(videoId: 'v1', index: 0);
      await backfilling.setDdl(
        videoId: 'v1',
        ddl: ddl('2026-10-01', remark: '带扇子'),
      );

      final read = await PracticePlanStore(storage).ddlOf('v1');
      expect(read!.settlement!.outcome, DdlSettlementOutcome.onTime);
      expect(read.settlement!.judgedOn, DateTime(2026, 10, 2));
      expect(read.remark, '带扇子');
    });

    test('档位读不到（resolver 抛错）跳过，留待下次装载、不写盘', () async {
      seedPastDueDdl();
      var calls = 0;
      final skipping = PracticePlanStore(
        storage,
        masteryOf: (videoId) async {
          calls++;
          if (videoId == 'v1') throw StateError('读不到');
          return mastered;
        },
        clock: clock,
      );
      expect((await skipping.ddlOf('v1'))!.settlement, isNull);
      expect(calls, 1);
      expect(storage.saveCount, 0);
    });
  });

  group('团内检查与达标门', () {
    PlanEvent teamCheck() => PlanEvent(
      id: 'tc-1',
      type: kPlanEventTypeTeamCheck,
      date: DateTime.parse('2026-11-05'),
      remark: '周四团练',
      danceIds: const ['v1', 'v2'],
      danceGates: const {'v1': 'mastered', 'v2': 'familiar'},
      checkMode: kTeamCheckModeVideoSubmission,
      submittedOn: DateTime.parse('2026-11-03'),
    );

    test('团检五要素与关联舞清单往返一致（重启后仍在）', () async {
      await store.saveEvent(teamCheck());

      final reopened = PracticePlanStore(storage);
      final read = (await reopened.events()).single;
      expect(read.id, 'tc-1');
      expect(read.type, kPlanEventTypeTeamCheck);
      expect(read.date, DateTime(2026, 11, 5));
      expect(read.remark, '周四团练');
      expect(read.danceIds, const ['v1', 'v2']);
      expect(read.danceGates, const {'v1': 'mastered', 'v2': 'familiar'});
      expect(read.checkMode, kTeamCheckModeVideoSubmission);
      expect(read.submittedOn, DateTime(2026, 11, 3));
    });

    test('编辑团检：整体替换（改门、改方式、取消提交标记）', () async {
      await store.saveEvent(teamCheck());
      await store.saveEvent(
        PlanEvent(
          id: 'tc-1',
          type: kPlanEventTypeTeamCheck,
          date: DateTime.parse('2026-11-05'),
          danceIds: const ['v1'],
          danceGates: const {'v1': 'unset'},
          checkMode: kTeamCheckModeRehearsal,
        ),
      );

      final read = (await store.events()).single;
      expect(read.danceGates, const {'v1': 'unset'});
      expect(read.checkMode, kTeamCheckModeRehearsal);
      expect(read.submittedOn, isNull);
    });

    test('删除团检：清单随事件一起消失', () async {
      await store.saveEvent(teamCheck());
      expect(await store.deleteEvent('tc-1'), isTrue);
      expect(await store.events(), isEmpty);
    });

    test('旧事件缺团检字段按兜底读取：不设 / 到场排练 / 未提交', () {
      final read = PlanEvent.tryFromJson({
        'id': 'ev-old',
        'date': '2026-11-05',
        'type': kPlanEventTypeTeamCheck,
        'danceIds': const ['v1'],
      });
      expect(read, isNotNull);
      expect(read!.checkMode, kTeamCheckModeRehearsal);
      expect(read.danceGates, isEmpty);
      expect(read.submittedOn, isNull);
    });

    test('旧随舞事件也按兜底读取，且未知门名归一为不设', () {
      final read = PlanEvent.tryFromJson({
        'id': 'ev-2',
        'date': '2026-11-06',
        'danceIds': const ['v1'],
        'danceGates': const {'v1': 'bogus', 'v2': 'mastered'},
        'checkMode': 'rehearsal',
      });
      expect(read!.danceGates, const {'v2': 'mastered'});
      expect(read.type, kPlanEventTypeSocial);
    });

    test('非法提交日期按未提交兜底，不炸读取', () {
      final read = PlanEvent.tryFromJson({
        'id': 'tc-2',
        'date': '2026-11-07',
        'type': kPlanEventTypeTeamCheck,
        'submittedOn': 'not-a-date',
      });
      expect(read!.submittedOn, isNull);
    });

    test('归一：达标门表的键去空白去空串，空串门值丢弃', () {
      final normalized = PlanEvent(
        id: 'tc-3',
        type: kPlanEventTypeTeamCheck,
        date: DateTime.parse('2026-11-08'),
        danceIds: const ['v1'],
        danceGates: const {' v1 ': 'mastered', '': 'familiar'},
      ).normalized;
      expect(normalized.danceGates, const {'v1': 'mastered'});
    });
  });
}
