library central_monitor;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'src/device_snapshot.dart';

enum AppStatus { enabled, disabled }

/// CentralMonitor - low-impact SDK for Central App Monitor.
///
/// Usage:
/// ```dart
/// void main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   CentralMonitor.init(clientKey: 'cm_live_xxx');
///   runApp(const MyApp());
/// }
/// ```
/// Then wrap the app so the disabled-state white screen can be applied:
/// ```dart
/// MaterialApp(builder: (context, child) => CentralMonitor.guard(child), ...)
/// ```
class CentralMonitor {
  CentralMonitor._();

  static const _prefsStatus = 'cm_status';
  static const _prefsConfigVersion = 'cm_config_version';
  static const _prefsDeviceUid = 'cm_device_uid';
  static const _prefsDeviceFingerprint = 'cm_device_fingerprint';
  static const _prefsCustomerHash = 'cm_customer_hash';
  static const _prefsPermissionsHash = 'cm_permissions_hash';
  static const _prefsPendingCustomer = 'cm_pending_customer';
  static const _prefsPendingPermissions = 'cm_pending_permissions';

  static final ValueNotifier<AppStatus> _status =
      ValueNotifier<AppStatus>(AppStatus.enabled);

  static String? _clientKey;
  static String _baseUrl = '';
  static bool _initialized = false;
  static Duration _timeout = const Duration(seconds: 5);
  static final Set<String> _reportedStages = <String>{};

  /// Call once, right after [WidgetsFlutterBinding.ensureInitialized()].
  /// Never awaited by callers - runs fully in the background and never
  /// throws, so it cannot delay [runApp] or crash the host app.
  static void init({
    required String clientKey,
    required String baseUrl,
    Duration timeout = const Duration(seconds: 5),
  }) {
    if (_initialized) return;
    _initialized = true;
    _clientKey = clientKey;
    _baseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    _timeout = timeout;

    unawaited(_bootstrapInBackground());
  }

  /// Wrap the app's `builder` with this so the app renders a blank white
  /// screen instead of [child] whenever the project is remotely disabled.
  static Widget guard(Widget? child) {
    return ValueListenableBuilder<AppStatus>(
      valueListenable: _status,
      builder: (context, status, _) {
        if (status == AppStatus.disabled) {
          return const _WhiteScreen();
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }

  /// Report the current signed-in customer. Call after login /
  /// registration / profile update. Only sent to the server when the
  /// data actually changed since the last successful send.
  ///
  /// If a guest record already exists for this [phone] from an earlier
  /// [reportOtpRequested] call, passing the real [externalCustomerId]
  /// here upgrades that same record in place rather than creating a
  /// duplicate.
  static void identifyCustomer({
    String? externalCustomerId,
    String? name,
    String? phone,
    String? email,
    String? role,
  }) {
    final customer = <String, dynamic>{
      if (externalCustomerId != null) 'external_customer_id': externalCustomerId,
      if (name != null) 'name': name,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (role != null) 'role': role,
    };

    unawaited(_queueAndFlush(customer: customer));
  }

  /// Call when the app sends/requests an OTP for a phone number, before
  /// verification completes. Lets you see signups that started but never
  /// finished. Once verified, call [identifyCustomer] with the real
  /// external ID and the same phone - the guest record is upgraded in
  /// place, not duplicated.
  static void reportOtpRequested(String phone) {
    unawaited(_queueAndFlush(customer: {'phone': phone, 'otp_requested': true}));
  }

  /// Report one of the customer's saved addresses. Call whenever the app
  /// adds or updates an address. Each address may carry its own contact
  /// name/phone, separate from the account's - common for "deliver to a
  /// different person" style addresses. Best-effort only: if the network
  /// call fails it is not retried or queued, unlike [identifyCustomer].
  static void reportAddress({
    required String externalCustomerId,
    String? externalAddressId,
    String? label,
    String? address,
    String? contactName,
    String? contactPhone,
    String? city,
    String? state,
    String? country,
    String? pincode,
    double? latitude,
    double? longitude,
  }) {
    final addressPayload = <String, dynamic>{
      if (externalAddressId != null) 'external_address_id': externalAddressId,
      if (label != null) 'label': label,
      if (address != null) 'address': address,
      if (contactName != null) 'contact_name': contactName,
      if (contactPhone != null) 'contact_phone': contactPhone,
      if (city != null) 'city': city,
      if (state != null) 'state': state,
      if (country != null) 'country': country,
      if (pincode != null) 'pincode': pincode,
      if (latitude != null) 'latitude': latitude.toString(),
      if (longitude != null) 'longitude': longitude.toString(),
    };

    unawaited(_sendAddress(externalCustomerId, addressPayload));
  }

  /// Report permission states the app already legitimately knows
  /// (e.g. from `permission_handler`). CentralMonitor never requests
  /// permissions itself. Status: granted | denied | not_requested |
  /// restricted | unknown.
  static void reportPermissions(Map<String, String> permissions) {
    unawaited(_queueAndFlush(permissions: permissions));
  }

  // ---------------------------------------------------------------------

  static Future<void> _bootstrapInBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final storedStatus = prefs.getString(_prefsStatus);
      if (storedStatus == 'disabled') {
        _status.value = AppStatus.disabled;
      }

      final deviceUid = await _deviceUid(prefs);
      final snapshot = await DeviceSnapshot.collect();

      final response = await _post('bootstrap', '/api/v1/client/bootstrap', {
        'client_key': _clientKey,
        'package_name': snapshot.packageName,
        'platform': snapshot.platform,
        'app_version': snapshot.appVersion,
        'build_number': snapshot.buildNumber,
        'device_uid': deviceUid,
      });

      if (response != null && response['success'] == true) {
        final status = response['status'] == 'disabled'
            ? AppStatus.disabled
            : AppStatus.enabled;
        _status.value = status;
        await prefs.setString(
            _prefsStatus, status == AppStatus.disabled ? 'disabled' : 'enabled');
        if (response['config_version'] != null) {
          await prefs.setInt(_prefsConfigVersion, response['config_version'] as int);
        }
      }

      // Sync device details only when something about them changed.
      final lastFingerprint = prefs.getString(_prefsDeviceFingerprint);
      final pendingCustomer = _readJson(prefs, _prefsPendingCustomer);
      final pendingPermissions = _readJson(prefs, _prefsPendingPermissions);

      if (lastFingerprint != snapshot.fingerprint ||
          pendingCustomer != null ||
          pendingPermissions != null) {
        await _sync(
          prefs: prefs,
          deviceUid: deviceUid,
          packageName: snapshot.packageName,
          device: lastFingerprint != snapshot.fingerprint ? snapshot.toSyncJson() : null,
          customer: pendingCustomer,
          permissions: pendingPermissions,
        );
        await prefs.setString(_prefsDeviceFingerprint, snapshot.fingerprint);
      }
    } catch (e) {
      // Never let monitoring failures affect the host app - just log and sleep.
      _reportError('bootstrap', e);
    }
  }

  static Future<void> _queueAndFlush({
    Map<String, dynamic>? customer,
    Map<String, String>? permissions,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (customer != null) {
        final hash = jsonEncode(customer);
        if (prefs.getString(_prefsCustomerHash) == hash) return;
        await prefs.setString(_prefsPendingCustomer, hash);
      }

      if (permissions != null) {
        final hash = jsonEncode(permissions);
        if (prefs.getString(_prefsPermissionsHash) == hash) return;
        await prefs.setString(_prefsPendingPermissions, hash);
      }

      if (_clientKey == null) return; // init() not called yet

      final snapshot = await DeviceSnapshot.collect();
      final deviceUid = await _deviceUid(prefs);

      await _sync(
        prefs: prefs,
        deviceUid: deviceUid,
        packageName: snapshot.packageName,
        customer: customer,
        permissions: permissions,
      );
    } catch (e) {
      // Left queued in SharedPreferences; retried on next app launch.
      _reportError('sync', e);
    }
  }

  static Future<void> _sendAddress(
    String externalCustomerId,
    Map<String, dynamic> addressPayload,
  ) async {
    if (_clientKey == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final snapshot = await DeviceSnapshot.collect();
      final deviceUid = await _deviceUid(prefs);

      await _post('address', '/api/v1/client/sync', {
        'client_key': _clientKey,
        'package_name': snapshot.packageName,
        'device_uid': deviceUid,
        'customer': {'external_customer_id': externalCustomerId},
        'addresses': [addressPayload],
      });
    } catch (e) {
      // Best-effort only - not retried or queued for later.
      _reportError('address', e);
    }
  }

  static Future<void> _sync({
    required SharedPreferences prefs,
    required String deviceUid,
    required String packageName,
    Map<String, dynamic>? device,
    Map<String, dynamic>? customer,
    Map<String, dynamic>? permissions,
  }) async {
    final permissionsPayload = permissions
        ?.entries
        .map((e) => {'name': e.key, 'status': e.value})
        .toList();

    final response = await _post('sync', '/api/v1/client/sync', {
      'client_key': _clientKey,
      'package_name': packageName,
      'device_uid': deviceUid,
      if (device != null) 'device': device,
      if (customer != null) 'customer': customer,
      if (permissionsPayload != null) 'permissions': permissionsPayload,
    });

    if (response != null && response['success'] == true) {
      if (customer != null) {
        await prefs.setString(_prefsCustomerHash, jsonEncode(customer));
        await prefs.remove(_prefsPendingCustomer);
      }
      if (permissions != null) {
        await prefs.setString(_prefsPermissionsHash, jsonEncode(permissions));
        await prefs.remove(_prefsPendingPermissions);
      }
      if (response['status'] != null) {
        _status.value =
            response['status'] == 'disabled' ? AppStatus.disabled : AppStatus.enabled;
      }
    }
  }

  static Future<Map<String, dynamic>?> _post(
    String stage,
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }

      _reportError(stage, 'HTTP ${res.statusCode}');
    } catch (e) {
      // Offline or server unavailable - fail silently, keep cached state.
      _reportError(stage, e);
    }
    return null;
  }

  /// Best-effort diagnostic ping only. Never awaited by callers, never
  /// retried, and failures here are swallowed completely - this must
  /// never become a second way for the SDK to misbehave.
  static void _reportError(String stage, Object error) {
    if (_clientKey == null) return;
    if (!_reportedStages.add(stage)) return; // once per stage per app run

    unawaited(Future(() async {
      try {
        var deviceUid = '';
        try {
          deviceUid = (await SharedPreferences.getInstance())
                  .getString(_prefsDeviceUid) ??
              '';
        } catch (_) {}

        final message = error.toString();

        await http
            .post(
              Uri.parse('$_baseUrl/api/v1/client/error'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'client_key': _clientKey,
                if (deviceUid.isNotEmpty) 'device_uid': deviceUid,
                'stage': stage,
                'message': message.length > 500 ? message.substring(0, 500) : message,
              }),
            )
            .timeout(_timeout);
      } catch (_) {
        // Reporting the error itself failed - stay silent, no retry.
      }
    }));
  }

  static Future<String> _deviceUid(SharedPreferences prefs) async {
    var uid = prefs.getString(_prefsDeviceUid);
    if (uid == null) {
      uid = _generateUuid();
      await prefs.setString(_prefsDeviceUid, uid);
    }
    return uid;
  }

  static Map<String, dynamic>? _readJson(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _generateUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

class _WhiteScreen extends StatelessWidget {
  const _WhiteScreen();

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: Colors.white,
        child: SizedBox.expand(),
      ),
    );
  }
}
