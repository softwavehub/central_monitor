# central_monitor

Lightweight Flutter client SDK for Central App Monitor.

Reports customer, device, permission, and address data to your central Laravel server, and applies a remote enable/disable kill switch (a blank white screen when a project is disabled). Designed to be near-invisible to the host app: async, cached, never blocks startup, never throws, and stays completely silent if the server or network is unavailable.

## Usage

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  CentralMonitor.init(
    clientKey: const String.fromEnvironment('CM_CLIENT_KEY'),
    baseUrl: const String.fromEnvironment('CM_BASE_URL'),
  );

  runApp(const MyApp());
}
```

Wrap your `MaterialApp`/`GetMaterialApp` builder so the disabled-state white screen can be applied:

```dart
builder: (context, child) => CentralMonitor.guard(child),
```

### Reporting data

```dart
// Guest / pre-verification phone (e.g. OTP just requested)
CentralMonitor.reportOtpRequested(phone);

// Verified customer - upgrades the guest record above in place if the phone matches
CentralMonitor.identifyCustomer(
  externalCustomerId: user.id.toString(),
  name: user.name,
  phone: user.phone,
  email: user.email,
  role: 'Customer',
);

// One of the customer's saved addresses - each may have its own contact name/phone
CentralMonitor.reportAddress(
  externalCustomerId: user.id.toString(),
  externalAddressId: address.id.toString(),
  label: address.label,
  address: address.line,
  contactName: address.contactName,
  contactPhone: address.contactPhone,
);

// Permission states the app already knows (never requested by this SDK)
CentralMonitor.reportPermissions({'camera': 'granted', 'location': 'denied'});
```

## Install

```yaml
dependencies:
  central_monitor:
    git:
      url: https://github.com/softwavehub/central_monitor.git
```
