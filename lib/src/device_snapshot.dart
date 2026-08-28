import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  final String platform; // 'android' | 'ios'
  final String appVersion;
  final String buildNumber;
  final String? osVersion;
  final String? manufacturer;
  final String? model;
  final String? locale;
  final String? timezone;

  static Future<DeviceSnapshot> collect() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();
    final locale = Platform.localeName;
    final timezone = DateTime.now().timeZoneName;

    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      return DeviceSnapshot(
        packageName: packageInfo.packageName,
        platform: 'android',
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        osVersion: info.version.release,
        manufacturer: info.manufacturer,
        model: info.model,
        locale: locale,
        timezone: timezone,
      );
    }

    if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      return DeviceSnapshot(
        packageName: packageInfo.packageName,
        platform: 'ios',
        appVersion: packageInfo.version,
        buildNumber: packageInfo.buildNumber,
        osVersion: info.systemVersion,
        manufacturer: 'Apple',
        model: info.utsname.machine,
        locale: locale,
        timezone: timezone,
      );
    }

    return DeviceSnapshot(
      packageName: packageInfo.packageName,
      platform: 'other',
      appVersion: packageInfo.version,
      buildNumber: packageInfo.buildNumber,
      locale: locale,
      timezone: timezone,
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
