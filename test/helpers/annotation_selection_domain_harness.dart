import 'package:dance_learning_app/annotation/annotation_timeline.dart';
import 'package:dance_learning_app/player/annotation_selection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 选中域直测的**测试侧唯一共享构造**（先例 `buildTrackBandSession`）。
///
/// 只挂域的状态 provider（裸容器、不 pump widget、不经 `AnnotationEditor`），
/// 注入假时间线读取闭包、假只读门、假计数读口与记录器端口，装出域对象——
/// 失败时指向明确的模块，不牵扯编辑库装配。
///
/// 端口与生产装配同构（`annotationSelectionDomainProvider`）：新增
/// 学习段 store、组员方案只读读口与写入端口两个钩子；`beforeUserWrite`／
/// `persistSelection` 是调用方注入的记录器（缺省 no-op）。
AnnotationSelectionDomain buildAnnotationSelectionDomain({
  required ProviderContainer container,
  AnnotationTimeline Function()? timeline,
  bool Function()? memberSchemeReadonly,
  void Function()? beforeUserWrite,
  void Function(Set<int>)? persistSelection,
  int Function()? localMirrorFragmentCount,
  int Function()? noteCount,
}) {
  final port = AnnotationSelectionWritePort(
    beforeUserWrite: beforeUserWrite ?? () {},
    persistSelection: persistSelection ?? (_) {},
  );
  return AnnotationSelectionDomain(
    store: container.read(annotationSelectionProvider.notifier),
    learningStore: container.read(selectedLearningSegmentsProvider.notifier),
    timeline:
        timeline ?? () => AnnotationTimeline.wholeVideo(Duration.zero),
    memberSchemeReadonly: memberSchemeReadonly ?? () => false,
    writePort: port,
    localMirrorFragmentCount: localMirrorFragmentCount ?? () => 0,
    noteCount: noteCount ?? () => 0,
  );
}
