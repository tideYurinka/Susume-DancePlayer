import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:dance_learning_app/player/song_naming.dart';
import 'package:flutter_test/flutter_test.dart';

/// 命名/改名对话框初值规则纯函数测试：场景 + 现值 + 回退文件名 → 各字段初值。
/// 导入恒为空，改名保留现值（无现值回退文件名）。
void main() {
  const fallback = 'dance.mp4';

  group('导入命名', () {
    test('无现值：三字段均为空', () {
      final initial = resolveSongNamingInitial(
        scene: SongNamingScene.import,
        current: null,
        fallbackFileName: fallback,
      );
      expect(initial.song, '');
      expect(initial.dancer, '');
      expect(initial.remark, '');
    });

    test('已有现值：仍为空（导入场景不改写为现值）', () {
      const current = SongSignature(song: 'My Love', dancer: '如');
      final initial = resolveSongNamingInitial(
        scene: SongNamingScene.import,
        current: current,
        fallbackFileName: fallback,
      );
      expect(initial.song, '');
      expect(initial.dancer, '');
      expect(initial.remark, '');
    });
  });

  group('改名', () {
    test('有现值：三字段保留原值（不预填替换、不留空）', () {
      const current = SongSignature(
        dancer: '如',
        song: 'My Love',
        remark: '9人版',
      );
      final initial = resolveSongNamingInitial(
        scene: SongNamingScene.rename,
        current: current,
        fallbackFileName: fallback,
      );
      expect(initial.song, 'My Love');
      expect(initial.dancer, '如');
      expect(initial.remark, '9人版');
    });

    test('无现值：歌曲名回退文件名（把文件名改成歌名的入口语义）', () {
      final initial = resolveSongNamingInitial(
        scene: SongNamingScene.rename,
        current: null,
        fallbackFileName: fallback,
      );
      expect(initial.song, 'dance.mp4');
      expect(initial.dancer, '');
      expect(initial.remark, '');
    });

    test('无现值且文件名为空：歌曲名为空', () {
      final initial = resolveSongNamingInitial(
        scene: SongNamingScene.rename,
        current: null,
        fallbackFileName: '',
      );
      expect(initial.song, '');
    });
  });
}
