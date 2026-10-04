/// 通用命中盒下限的唯一声明处。密集区兜底值住播放域视觉 token 层；两个下限名字各
/// 只有一个写者。
///
/// 跨域可读：`lib/help`/`lib/stats`/`lib/plan`/`lib/home` 的下限取值与
/// 播放域同源，故声明在 `lib/core`。播放域由
/// `lib/player/visual_tokens.dart` 转出 [kHitTargetMinSize]，播放域读取点
/// 照常读视觉 token 层；密集区兜底值只服务播放域，与兜底清单同住该层。
library;

/// 命中盒下限（dp）：可点区域的实际命中矩形不得小于 48×48。视觉尺寸一律
/// 不变，达标靠透明外扩（把可点层撑到下限、视觉件居中其内）。
const double kHitTargetMinSize = 48;

/// 以 [center] 为中心、边长 [kHitTargetMinSize] 的命中盒的左上缘坐标（单轴）。
///
/// 钳进 `[0, extent − 边长]`（[extent] 小于边长时钳到 0）：越出可测界的
/// 命中层收不到命中，也会让矩形断言落空，同时视觉件位置不受影响。
double hitTargetStart(double center, double extent) =>
    (center - kHitTargetMinSize / 2).clamp(
      0.0,
      (extent - kHitTargetMinSize).clamp(0.0, double.infinity),
    );
