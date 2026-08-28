import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';

import 'platform_device_info.dart';

Future<PlatformDeviceInfo> collectPlatformDeviceInfo() async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isAndroid) {
    final info = await deviceInfo.androidInfo;
    return PlatformDeviceInfo(
      platform: 'android',
      osVersion: info.version.release,
      manufacturer: info.manufacturer,
      model: info.model,
    );
  }

  if (Platform.isIOS) {
    final info = await deviceInfo.iosInfo;
    return PlatformDeviceInfo(
      platform: 'ios',
      osVersion: info.systemVersion,
      manufacturer: 'Apple',
      model: info.utsname.machine,
    );
  }

  if (Platform.isMacOS) {
    final info = await deviceInfo.macOsInfo;
    return PlatformDeviceInfo(
      platform: 'macos',
      osVersion: info.osRelease,
      manufacturer: 'Apple',
      model: info.model,
    );
  }

  if (Platform.isWindows) {
    final info = await deviceInfo.windowsInfo;
    return PlatformDeviceInfo(
      platform: 'windows',
      osVersion: info.displayVersion,
      manufacturer: 'Microsoft',
      model: info.productName,
    );
  }

  if (Platform.isLinux) {
    final info = await deviceInfo.linuxInfo;
    return PlatformDeviceInfo(
      platform: 'linux',
      osVersion: info.version,
      manufacturer: null,
      model: info.name,
    );
  }

  return PlatformDeviceInfo(platform: 'other');
}
