/// Discovery / connection related types shared across the app.
// ignore: always_use_package_imports
library;

/// A device discovered via `adb devices`.
class AdbDeviceInfo {
  const AdbDeviceInfo({
    required this.serial,
    required this.state,
    this.address = '',
  });

  final String serial;

  /// e.g. `device`, `offline`, `unauthorized`, `no permissions`.
  final String state;

  /// `ip:port` when it is a wireless entry, empty otherwise.
  final String address;

  bool get isReady => state == 'device';
  bool get isNetwork => address.isNotEmpty;

  static AdbDeviceInfo fromLine(String line) {
    final parts = line.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return const AdbDeviceInfo(serial: '', state: '');
    }
    final serialPart = parts.first;
    final addr =
        serialPart.contains(':') && !serialPart.contains('usb') ? serialPart : '';
    return AdbDeviceInfo(
      serial: serialPart,
      state: parts.length > 1 ? parts[1] : 'device',
      address: addr,
    );
  }
}

/// Status of one step in the connect → root → frida-server pipeline.
enum CheckStatus { pending, checking, passed, failed }

/// A single step shown in the connection screen checklist.
class ConnectionStep {
  const ConnectionStep({
    required this.title,
    required this.detail,
    this.status = CheckStatus.pending,
  });

  final String title;
  final String detail;
  final CheckStatus status;

  ConnectionStep copyWith({
    String? title,
    String? detail,
    CheckStatus? status,
  }) {
    return ConnectionStep(
      title: title ?? this.title,
      detail: detail ?? this.detail,
      status: status ?? this.status,
    );
  }
}

/// The device we are attached to, after a successful connection.
class ConnectedDevice {
  const ConnectedDevice({
    required this.serial,
    required this.address,
    this.rooted = false,
    this.fridaServerRunning = false,
  });

  final String serial;

  /// `ip:port` used to connect (wireless).
  final String address;
  final bool rooted;
  final bool fridaServerRunning;

  ConnectedDevice copyWith({
    String? serial,
    String? address,
    bool? rooted,
    bool? fridaServerRunning,
  }) {
    return ConnectedDevice(
      serial: serial ?? this.serial,
      address: address ?? this.address,
      rooted: rooted ?? this.rooted,
      fridaServerRunning: fridaServerRunning ?? this.fridaServerRunning,
    );
  }
}

/// The result of running `adb connect`.
enum ConnectOutcome { connected, alreadyConnected, failed }