import 'package:dance_learning_app/feedback/device_snapshot.dart';

/// 测试共用的设备信息六项（包组装与表单递出两侧同一份，不各抄一份字面量）。
const DeviceSnapshot testDeviceSnapshot = DeviceSnapshot(
  appVersion: '0.1.0+1',
  buildId: 'abc1234',
  platform: 'android',
  model: 'DNP-AN00',
  osVersion: '15',
  androidSdkVersion: 36,
);
