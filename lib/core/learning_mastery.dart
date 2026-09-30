/// 学习段熟练度（私密字段）：线性五档，声明次序即高低。
///
/// 数值口径 = 枚举数值（未练 0 / 学习中 1 / 能跟上 2 / 较熟 3 / 掌握 4）；
/// 舞级派生（百分比 = 段档位值均值 × 25、完全掌握 = 全段最高档）据此计算。
///
/// 落盘见 `lib/persistence/local_document.dart`；取色入口见
/// `lib/core/mastery_colors.dart`。
library;

/// 学习段熟练度五档。
enum LearningMastery { unlearned, learning, keepingUp, familiar, mastered }
