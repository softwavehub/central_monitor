import 'dart:ui' show PlatformDispatcher;

import 'package:package_info_plus/package_info_plus.dart';

import 'platform_device_info.dart';

/// Lightweight, legitimately-available device/app metadata.
/// No identifiers, no contacts/SMS/location - see doc.md #22.
class DeviceSnapshot {
  DeviceSnapshot({
    required this.packageName,
    required this.platform,
    required this.appVersion,
    required this.buildNumber,
    this.osVersion,
    this.manufacturer,
    this.model,
    this.locale,
    this.timezone,
  });

  final String packageName;
  final String platform; // android | ios | web | macos | windows | linux | other
  final String appVersion;
  final String buildNumber;
  final String? osVersion;
  final String? manufacturer;
  final String? model;
  final String? locale;
  final String? timezone;

  static Future<DeviceSnapshot> collect() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final platformInfo = await collectPlatformDeviceInfo();

    return DeviceSnapshot(
      packageName: packageInfo.packageName,
      platform: platformInfo.platform,
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      osVersion: platformInfo.osVersion,
      manufacturer: platformInfo.manufacturer,
      model: platformInfo.model,
      locale: PlatformDispatcher.instance.locale.toString(),
      timezone: DateTime.now().timeZoneName,
    );
  }

  Map<String, dynamic> toSyncJson() => {
        'platform': platform,
        'os_version': osVersion,
        'manufacturer': manufacturer,
        'model': model,
        'app_version': appVersion,
        'build_number': buildNumber,
        'locale': locale,
        'timezone': timezone,
      };

  /// Fields that, if changed, should trigger a re-sync.
  String get fingerprint =>
      '$platform|$osVersion|$manufacturer|$model|$appVersion|$buildNumber';
}
