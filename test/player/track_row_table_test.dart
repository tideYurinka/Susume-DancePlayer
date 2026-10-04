import 'package:dance_learning_app/player/track_row_table.dart';
import 'package:flutter_test/flutter_test.dart';

/// 轨道行表直测——行序、逐行行高与行键、
/// 行间间隙、整带高、行矩形、坐标 → 行的含端点口径、单行/空行集退化、
/// 行不在行集内显式报错。不启动 widget 环境。
void main() {
  group('具名行集 normal', () {
    test('行序 = 备注轨 → 局部镜像轨 → 学习段轨 → 节拍轨 → 轨道手柄带行', () {
      expect(
        TrackRowTable.normal.rows.map((r) => r.id),
        const [
          TrackRowId.note,
          TrackRowId.localMirror,
          TrackRowId.learning,
          TrackRowId.beat,
          TrackRowId.handleStrip,
        ],
      );
    });

    test('逐行行高与行键：备注轨 36dp 新增，其余逐位沿用今天取值', () {
      final rows = TrackRowTable.normal.rows;
      expect(rows[0].height, 36);
      expect(rows[0].key, 'track_notes');
      expect(rows[1].height, 30);
      expect(rows[1].key, 'track_mirror');
      expect(rows[2].height, 48);
      expect(rows[2].key, 'track_learning');
      expect(rows[3].height, 24);
      expect(rows[3].key, 'track_beat');
      expect(rows[4].height, 30);
      expect(rows[4].key, 'track_handle_strip_row');
    });

    test('行间间隙为具名常量 10dp', () {
      expect(kTrackRowGap, 10);
      expect(TrackRowTable.normal.gap, kTrackRowGap);
    });

    test('整带高 = Σ行高 + 间隙 × (行数 − 1)', () {
      // 36 + 30 + 48 + 24 + 30 + 10 × 4 = 208
      expect(TrackRowTable.normal.totalHeight, 208);
    });
  });

  group('行矩形', () {
    final table = TrackRowTable.normal;

    test('逐行顶与高正确', () {
      expect(
        table.rectOf(TrackRowId.note),
        const TrackRowRect(top: 0, height: 36),
      );
      expect(
        table.rectOf(TrackRowId.localMirror),
        const TrackRowRect(top: 46, height: 30),
      );
      expect(
        table.rectOf(TrackRowId.learning),
        const TrackRowRect(top: 86, height: 48),
      );
      expect(
        table.rectOf(TrackRowId.beat),
        const TrackRowRect(top: 144, height: 24),
      );
      expect(
        table.rectOf(TrackRowId.handleStrip),
        const TrackRowRect(top: 178, height: 30),
      );
    });

    test('相邻行不重叠，行与行之间的空档恰为行间间隙', () {
      final rects = table.rows
          .map((r) => table.rectOf(r.id))
          .toList(growable: false);
      for (var i = 0; i + 1 < rects.length; i++) {
        expect(rects[i + 1].top - rects[i].bottom, kTrackRowGap);
      }
      for (final rect in rects) {
        expect(rect.height, greaterThan(0));
      }
    });

    test('行不在本行集内时显式报错', () {
      const onlyMirror = TrackRowTable(
        rows: [
          TrackRow(
            id: TrackRowId.localMirror,
            height: 30,
            key: 'track_mirror',
            prefixLabel: '镜像',
          ),
        ],
        gap: kTrackRowGap,
      );
      expect(
        () => onlyMirror.rectOf(TrackRowId.beat),
        throwsArgumentError,
      );
    });
  });

  group('坐标 → 行（含两端，行优先于间隙）', () {
    final table = TrackRowTable.normal;

    test('行顶与行底含两端命中该行', () {
      expect(table.rowAt(0), TrackRowId.note);
      expect(table.rowAt(36), TrackRowId.note); // 备注轨底边
      expect(table.rowAt(46), TrackRowId.localMirror);
      expect(table.rowAt(76), TrackRowId.localMirror); // 镜像行底边
      expect(table.rowAt(86), TrackRowId.learning);
      expect(table.rowAt(134), TrackRowId.learning); // 学习段轨底边仍判为学习段轨
      expect(table.rowAt(144), TrackRowId.beat);
      expect(table.rowAt(168), TrackRowId.beat);
      expect(table.rowAt(178), TrackRowId.handleStrip);
      expect(table.rowAt(208), TrackRowId.handleStrip); // 整带底边
    });

    test('行间隙返回空', () {
      expect(table.rowAt(41), isNull); // 备注轨与镜像行之间
      expect(table.rowAt(81), isNull); // 镜像行与学习段轨之间
      expect(table.rowAt(139), isNull); // 学习段轨与节拍轨之间
      expect(table.rowAt(173), isNull); // 节拍轨与手柄带行之间
    });

    test('带外与负坐标返回空', () {
      expect(table.rowAt(-1), isNull);
      expect(table.rowAt(-0.5), isNull);
      expect(table.rowAt(208.5), isNull);
      expect(table.rowAt(1000), isNull);
    });
  });

  group('具名行集 compare（对比练习）', () {
    test('行序 = 备注轨 → 练习视频轨 → 学习段轨 → 节拍轨（无局部镜像轨、无手柄带行）', () {
      expect(
        TrackRowTable.compare.rows.map((r) => r.id),
        const [
          TrackRowId.note,
          TrackRowId.practiceVideo,
          TrackRowId.learning,
          TrackRowId.beat,
        ],
      );
    });

    test('逐行行高与行键：备注轨 36dp 在顶、练习视频轨 48dp（与学习段轨同高、不新增视觉常量）', () {
      final rows = TrackRowTable.compare.rows;
      expect(rows[0].height, kNoteTrackRowHeight);
      expect(rows[0].height, 36);
      expect(rows[0].key, 'track_notes');
      expect(rows[1].height, kLearningTrackRowHeight);
      expect(rows[1].height, 48);
      expect(rows[1].key, 'track_practice');
      expect(rows[2].height, 48);
      expect(rows[2].key, 'track_learning');
      expect(rows[3].height, 24);
      expect(rows[3].key, 'track_beat');
    });

    test('行间间隙与 normal 同值；整带高 = 48+36+48+24 + 10×3 = 186', () {
      expect(TrackRowTable.compare.gap, kTrackRowGap);
      expect(TrackRowTable.compare.totalHeight, 186);
    });

    test('行矩形与含端点 rowAt 口径按新行序派生', () {
      final table = TrackRowTable.compare;
      expect(
        table.rectOf(TrackRowId.note),
        const TrackRowRect(top: 0, height: 36),
      );
      expect(
        table.rectOf(TrackRowId.practiceVideo),
        const TrackRowRect(top: 46, height: 48),
      );
      expect(
        table.rectOf(TrackRowId.beat),
        const TrackRowRect(top: 162, height: 24),
      );
      expect(table.rowAt(0), TrackRowId.note);
      expect(table.rowAt(36), TrackRowId.note); // 备注轨底边
      expect(table.rowAt(46), TrackRowId.practiceVideo); // 间隙后
      expect(table.rowAt(186), TrackRowId.beat); // 整带底边
      expect(table.rowAt(41), isNull); // 行间隙
    });
  });

  group('轨道片头标签声明', () {
    test('编辑态标签集：行序（自上而下）逐行声明短标签', () {
      expect(TrackRowTable.normal.prefixLabels, const [
        '备注',
        '镜像',
        '分段',
        '节拍',
        '控制',
      ]);
    });

    test('对比态标签集：条数与次序跟随该态行集，无局部镜像轨即无「镜像」', () {
      expect(TrackRowTable.compare.prefixLabels, const ['备注', '练习', '分段', '节拍']);
    });

    test('标签文案与行键、行标识分离：标签不改行键', () {
      expect(TrackRowTable.compare.prefixLabelOf(TrackRowId.practiceVideo), '练习');
      expect(
        TrackRowTable.compare.rows
            .firstWhere((row) => row.id == TrackRowId.practiceVideo)
            .key,
        'track_practice',
      );
      expect(TrackRowTable.normal.rows.map((row) => row.key), const [
        'track_notes',
        'track_mirror',
        'track_learning',
        'track_beat',
        'track_handle_strip_row',
      ]);
    });

    test('行不在该态行集内时没有对应标签（空）', () {
      expect(TrackRowTable.normal.prefixLabelOf(TrackRowId.handleStrip), '控制');
      expect(
        TrackRowTable.normal.prefixLabelOf(TrackRowId.practiceVideo),
        isNull,
      );
      expect(TrackRowTable.compare.prefixLabelOf(TrackRowId.practiceVideo), '练习');
      expect(TrackRowTable.compare.prefixLabelOf(TrackRowId.localMirror), isNull);
      expect(TrackRowTable.compare.prefixLabelOf(TrackRowId.handleStrip), isNull);
    });

    test('自下而上（片头列读序）= 行集倒序的标签', () {
      expect(TrackRowTable.normal.prefixLabels.reversed, const [
        '控制',
        '节拍',
        '分段',
        '镜像',
        '备注',
      ]);
      expect(TrackRowTable.compare.prefixLabels.reversed, const [
        '节拍',
        '分段',
        '练习',
        '备注',
      ]);
    });
  });

  group('去掉若干行（剪裁出新表）', () {
    test('紧凑档剪掉备注轨与局部镜像轨：余行次序不变，整带高按剪裁后逐行重算', () {
      final trimmed = TrackRowTable.normal.withoutRows(const {
        TrackRowId.note,
        TrackRowId.localMirror,
      });
      expect(trimmed.rows.map((r) => r.id), const [
        TrackRowId.learning,
        TrackRowId.beat,
        TrackRowId.handleStrip,
      ]);
      expect(trimmed.gap, kTrackRowGap);
      // 48 + 24 + 30 + 10 × 2 = 122（worked example）。
      expect(trimmed.totalHeight, 122);
      // 行顶按新行序重排：学习段轨 0、节拍轨 58、手柄带行 92。
      expect(
        trimmed.rectOf(TrackRowId.learning),
        const TrackRowRect(top: 0, height: 48),
      );
      expect(
        trimmed.rectOf(TrackRowId.beat),
        const TrackRowRect(top: 58, height: 24),
      );
      expect(
        trimmed.rectOf(TrackRowId.handleStrip),
        const TrackRowRect(top: 92, height: 30),
      );
    });

    test('成员谓词与片头标签集随剪裁收缩；被剪掉的行取标签为空、取矩形仍报错', () {
      final trimmed = TrackRowTable.normal.withoutRows(const {
        TrackRowId.note,
        TrackRowId.localMirror,
      });
      expect(trimmed.hasRow(TrackRowId.note), isFalse);
      expect(trimmed.hasRow(TrackRowId.localMirror), isFalse);
      expect(trimmed.hasRow(TrackRowId.learning), isTrue);
      expect(trimmed.hasRow(TrackRowId.beat), isTrue);
      expect(trimmed.hasRow(TrackRowId.handleStrip), isTrue);
      expect(trimmed.prefixLabels, const ['分段', '节拍', '控制']);
      expect(trimmed.prefixLabelOf(TrackRowId.note), isNull);
      expect(trimmed.prefixLabelOf(TrackRowId.localMirror), isNull);
      expect(trimmed.prefixLabelOf(TrackRowId.handleStrip), '控制');
      // 不在行集内取矩形仍按既有口径显式报错，不静默返回空矩形。
      expect(() => trimmed.rectOf(TrackRowId.note), throwsArgumentError);
      expect(() => trimmed.rectOf(TrackRowId.localMirror), throwsArgumentError);
    });

    test('坐标 → 行按剪裁后的行序与行高派生（原备注轨那一段现属下一行）', () {
      final trimmed = TrackRowTable.normal.withoutRows(const {
        TrackRowId.note,
        TrackRowId.localMirror,
      });
      // 原备注轨行中（18）现落学习段轨；区间含两端、间隙返回空。
      expect(trimmed.rowAt(18), TrackRowId.learning);
      expect(trimmed.rowAt(0), TrackRowId.learning);
      expect(trimmed.rowAt(48), TrackRowId.learning);
      expect(trimmed.rowAt(53), isNull); // 行间隙
      expect(trimmed.rowAt(58), TrackRowId.beat);
      expect(trimmed.rowAt(122), TrackRowId.handleStrip); // 整带底边
      expect(trimmed.rowAt(122.5), isNull);
    });

    test('行集里没有的身份是空操作：对比行集剪局部镜像轨不改变任何行', () {
      final trimmed = TrackRowTable.compare.withoutRows(const {
        TrackRowId.localMirror,
      });
      expect(
        trimmed.rows.map((r) => r.id),
        TrackRowTable.compare.rows.map((r) => r.id),
      );
      expect(
        trimmed.rows.map((r) => r.key),
        TrackRowTable.compare.rows.map((r) => r.key),
      );
      expect(trimmed.gap, TrackRowTable.compare.gap);
      expect(trimmed.totalHeight, TrackRowTable.compare.totalHeight);
    });

    test('对比行集剪掉空备注轨：练习视频轨升到最顶，整带高 140', () {
      final trimmed = TrackRowTable.compare.withoutRows(const {TrackRowId.note});
      expect(trimmed.rows.map((r) => r.id), const [
        TrackRowId.practiceVideo,
        TrackRowId.learning,
        TrackRowId.beat,
      ]);
      // 48 + 48 + 24 + 10 × 2 = 140（worked example）。
      expect(trimmed.totalHeight, 140);
      expect(
        trimmed.rectOf(TrackRowId.practiceVideo),
        const TrackRowRect(top: 0, height: 48),
      );
      expect(trimmed.hasRow(TrackRowId.note), isFalse);
    });
  });

  group('退化', () {
    test('单行集：整带高等于该行行高，无间隙参与', () {
      const single = TrackRowTable(
        rows: [
          TrackRow(
            id: TrackRowId.learning,
            height: 48,
            key: 'track_learning',
            prefixLabel: '分段',
          ),
        ],
        gap: kTrackRowGap,
      );
      expect(single.totalHeight, 48);
      expect(single.rowAt(0), TrackRowId.learning);
      expect(single.rowAt(48), TrackRowId.learning);
      expect(single.rowAt(48.5), isNull);
    });

    test('空行集：整带高 0，任何查询返回空', () {
      const empty = TrackRowTable(rows: [], gap: kTrackRowGap);
      expect(empty.totalHeight, 0);
      expect(empty.rowAt(0), isNull);
      expect(empty.rowAt(-1), isNull);
      expect(empty.rowAt(100), isNull);
    });
  });
}
