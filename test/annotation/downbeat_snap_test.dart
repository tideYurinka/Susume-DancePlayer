import 'package:flutter_test/flutter_test.dart';

import 'package:dance_learning_app/annotation/downbeat_snap.dart';
import 'package:dance_learning_app/core/beat_grid.dart';
import 'package:dance_learning_app/core/document_beat_grid.dart';
import 'package:dance_learning_app/persistence/marker_document.dart'
    as marker_doc;

import '../helpers/beat_test_seam.dart';
import '../helpers/document_grid_of.dart';

/// 最近强拍解析：八拍锚点的唯一
/// 合法落点 = **强拍**（八拍大线或四拍中线）；本 seam 把任意请求位置解析为
/// 最近强拍时刻，风格仿既有 `half_beat_snap` 套件。

Duration ms(int v) => Duration(milliseconds: v);

/// 真实网格样例：拍点每 0.5s 一拍、强拍每 4 拍——强拍时刻 0/2/4…s；网格
/// 构造复用共享助手（`test/helpers/beat_test_seam.dart`）。
DocumentBeatGrid uniformGrid({int beats = 12}) =>
    documentGridOf(uniformDownbeatGridDoc(seconds: (beats - 1) / 2));

void main() {
  group('最近强拍解析（八拍锚点落点）', () {
    test('就绪真实网格：吸最近强拍，弱拍/非强拍不落点', () {
      final grid = uniformGrid();
      // 每个强拍周围的邻域都吸到该强拍（含非强拍请求位置）。
      expect(resolveDownbeatSnap(ms(0), grid: grid), ms(0));
      expect(resolveDownbeatSnap(ms(700), grid: grid), ms(0));
      expect(resolveDownbeatSnap(ms(1400), grid: grid), ms(2000));
      expect(resolveDownbeatSnap(ms(3100), grid: grid), ms(4000));
      // 落在非强拍上的请求位置也被解析到强拍（「非强拍上无落点」）。
      expect(resolveDownbeatSnap(ms(900), grid: grid), ms(0));
      expect(resolveDownbeatSnap(ms(1500), grid: grid), ms(2000));
    });

    test('等距并列取时间靠后者（与既有对齐落点纪律一致）', () {
      final grid = uniformGrid();
      expect(resolveDownbeatSnap(ms(1000), grid: grid), ms(2000));
      expect(resolveDownbeatSnap(ms(999), grid: grid), ms(0));
      expect(resolveDownbeatSnap(ms(1001), grid: grid), ms(2000));
    });

    test('早于首拍 / 晚于末拍不越界：贴首强拍 / 贴末强拍', () {
      final grid = uniformGrid(beats: 12); // 末拍 11 → 5.5s，末强拍 4.0s
      expect(resolveDownbeatSnap(ms(-5000), grid: grid), ms(0));
      expect(resolveDownbeatSnap(ms(60000), grid: grid), ms(4000));
      // 网格无强拍：无合法落点。
      final noDown = documentGridOf(
        marker_doc.BeatGrid(
          model: 'm',
          fps: 100,
          generatedAt: DateTime.utc(2024),
          beats: [
            for (var i = 0; i < 8; i++)
              marker_doc.BeatPoint(t: i * 0.5, down: false),
          ],
        ),
      );
      expect(resolveDownbeatSnap(ms(1000), grid: noDown), isNull);
    });

    test('占位/异常网格：按各自强拍周期解析（就绪门在调用侧）', () {
      // 占位均匀网格（120bpm、强拍每 4 拍 = 每 2s）。
      expect(resolveDownbeatSnap(ms(700), grid: placeholderBeatGrid), ms(0));
      expect(
        resolveDownbeatSnap(ms(1400), grid: placeholderBeatGrid),
        ms(2000),
      );
      // 异常态秒制兜底网格（每拍 0.5s、强拍每 4 拍）。
      const error = UnavailableBeatGrid();
      expect(resolveDownbeatSnap(ms(700), grid: error), ms(0));
      expect(resolveDownbeatSnap(ms(1400), grid: error), ms(2000));
    });
  });
}
