import 'platform_device_info.dart';

Future<PlatformDeviceInfo> collectPlatformDeviceInfo() async {
  return PlatformDeviceInfo(platform: 'web');
}
