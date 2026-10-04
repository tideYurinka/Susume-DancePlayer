import 'package:dance_learning_app/persistence/document_version_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// 八份文档的版本链集中登记表。
///
/// 直测：登记表列全八份、每份的链从地板无缝连到本版（遍历断言，
/// 防将来升版时假绿）、八份地板与本版与历史事实一致。
void main() {
  test('登记表列全八份文档，键稳定', () {
    expect(documentVersionPolicies.keys, {
      'markers',
      'local',
      'videoIndex',
      'practiceStats',
      'practicePlan',
      'fourBeatBucket',
      'memberSchemes',
      'materialManifest',
    });
  });

  test('每份链从地板无缝连到本版（遍历断言，防升版假绿）', () {
    for (final entry in documentVersionPolicies.entries) {
      final policy = entry.value;
      expect(
        policy.currentVersion,
        policy.floor + policy.steps.length,
        reason: '${entry.key}：本版 = 链尾',
      );
      for (var i = 0; i < policy.steps.length; i++) {
        expect(
          policy.steps[i].from,
          policy.floor + i,
          reason: '${entry.key} 第 $i 级必须紧接地板 + $i',
        );
      }
    }
  });

  test('八份地板与本版与历史事实一致', () {
    const expected = {
      'markers': (7, 9),
      'local': (3, 4),
      'videoIndex': (2, 2),
      'practiceStats': (2, 2),
      'practicePlan': (1, 1),
      'fourBeatBucket': (1, 1),
      'memberSchemes': (1, 2),
      'materialManifest': (2, 3),
    };
    for (final entry in expected.entries) {
      final policy = documentVersionPolicies[entry.key]!;
      expect(policy.floor, entry.value.$1, reason: '${entry.key} 地板');
      expect(policy.currentVersion, entry.value.$2, reason: '${entry.key} 本版');
    }
  });
}
