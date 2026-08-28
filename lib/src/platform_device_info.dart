import 'platform_device_info_io.dart'
    if (dart.library.html) 'platform_device_info_web.dart' as impl;

/// Legitimately-available platform/device fields. No identifiers.
class PlatformDeviceInfo {
  PlatformDeviceInfo({
    required this.platform,
    this.osVersion,
    this.manufacturer,
    this.model,
  });

  final String platform;
  final String? osVersion;
  final String? manufacturer;
  final String? model;
}

Future<PlatformDeviceInfo> collectPlatformDeviceInfo() =>
    impl.collectPlatformDeviceInfo();
