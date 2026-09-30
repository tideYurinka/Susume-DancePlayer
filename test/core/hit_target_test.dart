import 'package:dance_learning_app/core/hit_target.dart';
import 'package:dance_learning_app/player/visual_tokens.dart'
    show kHitTargetDenseMinSize;
import 'package:flutter_test/flutter_test.dart';

/// 命中盒外扩的左/上缘换算：以目标为中心、钳进
/// 可测界；越界钳到边界、界比命中盒还小时钳到 0。
void main() {
  test('命中盒下限取值：通用 48、邻接密集区兜底 44', () {
    expect(kHitTargetMinSize, 48);
    expect(kHitTargetDenseMinSize, 44);
  });

  test('以目标为中心：居中取 center − 24', () {
    expect(hitTargetStart(100, 200), 76);
  });

  test('越界钳到边界：左/上钳 0，右/下钳 extent − 48', () {
    expect(hitTargetStart(10, 200), 0);
    expect(hitTargetStart(195, 200), 152);
  });

  test('可测界比命中盒还小：钳到 0，不越出也不为负', () {
    expect(hitTargetStart(10, 30), 0);
    expect(hitTargetStart(25, 0), 0);
  });
}
