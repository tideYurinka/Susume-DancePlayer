import 'package:dance_learning_app/persistence/song_signature.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeSignature（净化边界）', () {
    test('无净化需求时三字段原样保留', () {
      const raw = SongSignature(dancer: '如', song: 'My Love', remark: '9人版');
      expect(sanitizeSignature(raw, fallbackSong: 'x.mp4'), raw);
    });

    test('去首尾空白', () {
      const raw = SongSignature(
        dancer: ' 如 ',
        song: ' My Love ',
        remark: ' 9人版 ',
      );
      expect(
        sanitizeSignature(raw, fallbackSong: 'x.mp4'),
        const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
      );
    });

    test('剥离控制字符与换行（C0 与 DEL）', () {
      const raw = SongSignature(
        dancer: '如\x00',
        song: 'My\nLove\x1b',
        remark: '\x7f9人版\r\n',
      );
      expect(
        sanitizeSignature(raw, fallbackSong: 'x.mp4'),
        const SongSignature(dancer: '如', song: 'MyLove', remark: '9人版'),
      );
    });

    test('歌曲名净化后为空回退净化后的文件名', () {
      const raw = SongSignature(dancer: '如', song: '   ', remark: '9人版');
      expect(
        sanitizeSignature(raw, fallbackSong: ' 123.mp4 '),
        const SongSignature(dancer: '如', song: '123.mp4', remark: '9人版'),
      );
    });

    test('歌曲名全为控制字符同样回退文件名', () {
      const raw = SongSignature(song: '\n\t');
      expect(sanitizeSignature(raw, fallbackSong: 'a.mp4').song, 'a.mp4');
    });

    test('回退文件名也为空时歌曲名为空串（显示层再回退）', () {
      const raw = SongSignature(song: ' ');
      expect(sanitizeSignature(raw, fallbackSong: '').song, '');
    });
  });

  group('songFallbackName（文件名回落名：把文件名当名字用时的唯一去扩展名点）', () {
    test('去最后一个点及其之后：a.b.mp4 → a.b', () {
      expect(songFallbackName('a.b.mp4'), 'a.b');
    });

    test('无点原样：dance → dance', () {
      expect(songFallbackName('dance'), 'dance');
    });

    test('点在开头（隐藏文件）原样：.mp4 → .mp4', () {
      expect(songFallbackName('.mp4'), '.mp4');
    });

    test('.hidden.mp4 → .hidden', () {
      expect(songFallbackName('.hidden.mp4'), '.hidden');
    });

    test('不改大小写：DANCE.MP4 → DANCE', () {
      expect(songFallbackName('DANCE.MP4'), 'DANCE');
    });

    test('点后为空原样：dance. → dance.', () {
      expect(songFallbackName('dance.'), 'dance.');
    });

    test('空串 → 空串', () {
      expect(songFallbackName(''), '');
    });

    test('不查扩展名白名单：任何后缀照去', () {
      expect(songFallbackName('舞.mkv2'), '舞');
    });

    test('不替换非法字符：只去扩展名，其余原样', () {
      expect(songFallbackName('a b:c?.mp4'), 'a b:c?');
    });
  });

  group('danceDisplayTitle（署名显示串，未署名回落文件名回落名）', () {
    test('有署名：取显示串，文件名不参与', () {
      expect(
        danceDisplayTitle(
          const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
          'dance.mp4',
        ),
        '「如」My Love - 9人版',
      );
    });

    test('未署名：回落「文件名回落名」（去扩展名）', () {
      expect(danceDisplayTitle(null, 'My Dance.mp4'), 'My Dance');
    });

    test('歌曲名为空视为未署名：同样回落去扩展名的文件名', () {
      expect(
        danceDisplayTitle(const SongSignature(dancer: '如'), 'a.b.mp4'),
        'a.b',
      );
    });

    test('回落名自身的边界照纯件规则：点在开头原样（.mp4 → .mp4）', () {
      expect(danceDisplayTitle(null, '.mp4'), '.mp4');
    });
  });

  group('signatureDisplayText（显示串渲染：回退串由调用方给）', () {
    test('未署名回退调用方给的串', () {
      expect(signatureDisplayText(null, 'dance.mp4'), 'dance.mp4');
    });

    test('歌曲名为空视为未署名，同样回退调用方给的串', () {
      expect(
        signatureDisplayText(const SongSignature(dancer: '如'), 'dance.mp4'),
        'dance.mp4',
      );
    });

    test('完整三段：「版本舞者」歌曲名 - 版本注记', () {
      expect(
        signatureDisplayText(
          const SongSignature(dancer: '如', song: 'My Love', remark: '9人版'),
          'dance.mp4',
        ),
        '「如」My Love - 9人版',
      );
    });

    test('空舞者省略「」段', () {
      expect(
        signatureDisplayText(
          const SongSignature(song: 'My Love', remark: '9人版'),
          'dance.mp4',
        ),
        'My Love - 9人版',
      );
    });

    test('空注记省略「 - 注记」段', () {
      expect(
        signatureDisplayText(
          const SongSignature(dancer: '如', song: 'My Love'),
          'dance.mp4',
        ),
        '「如」My Love',
      );
    });

    test('只有歌曲名', () {
      expect(
        signatureDisplayText(const SongSignature(song: 'My Love'), 'dance.mp4'),
        'My Love',
      );
    });
  });
}
