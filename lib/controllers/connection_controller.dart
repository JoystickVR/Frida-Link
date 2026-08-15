import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/models/connection.dart';
import '../core/services/adb_service.dart';
import 'app_data_controller.dart';

/// State of the connection pipeline.
class ConnectionState {
  const ConnectionState({
    this.isConnected = false,
    this.showConnectionUi = true,
    this.steps = const [],
    this.device,
    this.isDebugBypass = false,
  });

  final bool isConnected;
  final bool showConnectionUi;
  final List<ConnectionStep> steps;
  final ConnectedDevice? device;

  /// True when the Konami-code debug bypass is active (no device connected).
  final bool isDebugBypass;

  static List<ConnectionStep> initialSteps() => const [
        ConnectionStep(
            title: 'Wireless ADB', detail: '', status: CheckStatus.pending),
        ConnectionStep(
            title: 'Root check', detail: '', status: CheckStatus.pending),
        ConnectionStep(
            title: 'frida-server', detail: '', status: CheckStatus.pending),
      ];

  ConnectionState copyWith({
    bool? isConnected,
    bool? showConnectionUi,
    List<ConnectionStep>? steps,
    ConnectedDevice? device,
    bool clearDevice = false,
    bool? isDebugBypass,
  }) {
    return ConnectionState(
      isConnected: isConnected ?? this.isConnected,
      showConnectionUi: showConnectionUi ?? this.showConnectionUi,
      steps: steps ?? this.steps,
      device: clearDevice ? null : (device ?? this.device),
      isDebugBypass: isDebugBypass ?? this.isDebugBypass,
    );
  }
}

/// Drives connect → root check → frida-server check.
class ConnectionController extends StateNotifier<ConnectionState> {
  ConnectionController(this._settings, this._getAdb)
      : super(ConnectionState(steps: ConnectionState.initialSteps()));

  final AppSettings Function() _settings;
  final AdbService Function(AppSettings) _getAdb;

  /// Bumped on every new / cancelled flow. In-flight steps compare against it
  /// after each await so a cancelled flow stops mutating state.
  int _flowToken = 0;

  bool _cancelled(int token) => token != _flowToken;

  AdbService get _adb => _getAdb(_settings());

  ConnectionState get cs => state;

  void _step(int index, CheckStatus status, String detail) {
    final steps = List<ConnectionStep>.from(cs.steps);
    steps[index] = steps[index].copyWith(status: status, detail: detail);
    state = cs.copyWith(steps: steps);
  }

  void _reset() {
    state = cs.copyWith(
      steps: ConnectionState.initialSteps(),
      clearDevice: true,
    );
  }

  /// Connected device serial (the wireless address is the serial for TCP).
  Future<String> _serialFor(String address, AdbService adb) async {
    final devices = await adb.devices();
    for (final d in devices) {
      if (d.serial == address || d.address == address) return d.serial;
    }
    return address;
  }

  /// Runs the full pipeline for [address] (e.g. `192.168.1.50:5555`).
  Future<ConnectedDevice?> connectFlow(String address) async {
    final token = ++_flowToken;
    _reset();
    if (!await _connectStep(address, token)) return null;
    final serial = await _serialFor(address, _adb);
    // Let adb settle the transport.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_cancelled(token)) return null;
    if (!await _rootStep(serial, token)) return null;
    if (!await _serverStep(serial, token)) return null;
    return _finishAndAdvance(address, serial, token);
  }

  /// Re-runs an individual step (and every step after it) after a failure,
  /// without restarting the whole pipeline. [index] is 0-based over the steps
  /// shown in the UI (Wireless ADB = 0, Root = 1, frida-server = 2).
  Future<ConnectedDevice?> retryFrom(int index, String address) async {
    final token = ++_flowToken;
    if (index <= 0) {
      if (!await _connectStep(address, token)) return null;
      final serial = await _serialFor(address, _adb);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (_cancelled(token)) return null;
      if (!await _rootStep(serial, token)) return null;
      if (!await _serverStep(serial, token)) return null;
      return _finishAndAdvance(address, serial, token);
    }
    final serial = await _serialFor(address, _adb);
    if (_cancelled(token)) return null;
    if (index <= 1 && !await _rootStep(serial, token)) return null;
    if (index <= 2 && !await _serverStep(serial, token)) return null;
    return _finishAndAdvance(address, serial, token);
  }

  /// Aborts any connection flow in progress and returns the pipeline to its
  /// idle state. In-flight steps notice via their token and stop updating.
  void cancel() {
    _flowToken++;
    _reset();
  }

  /// Step 0: connect over wireless adb.
  Future<bool> _connectStep(String address, int token) async {
    if (_cancelled(token)) return false;
    _step(0, CheckStatus.checking, 'Connecting to $address…');
    final connect = await _adb.connect(address);
    if (_cancelled(token)) return false;
    if (connect.outcome == ConnectOutcome.failed) {
      _step(
          0,
          CheckStatus.failed,
          'adb connect failed:\n${connect.raw.trim()}\n'
          'Make sure the headset is on the same network and `adb` is installed.');
      return false;
    }
    final wasAlready = connect.outcome == ConnectOutcome.alreadyConnected;
    _step(0, CheckStatus.passed,
        '${wasAlready ? 'Already connected' : 'Connected'} → $address');
    return true;
  }

  /// Step 1: root (su) check.
  Future<bool> _rootStep(String serial, int token) async {
    if (_cancelled(token)) return false;
    _step(1, CheckStatus.checking, 'Running `su`…');
    final rooted = await _adb.isRooted(serial);
    if (_cancelled(token)) return false;
    if (!rooted) {
      _step(1, CheckStatus.failed,
          'This headset does not appear to be rooted. Frida Link requires root access and cannot continue until the device is rooted.');
      return false;
    }
    _step(1, CheckStatus.passed, '`su` granted.');
    return true;
  }

  /// Step 2: frida-server present + running (in daemon mode so spawns work).
  Future<bool> _serverStep(String serial, int token) async {
    if (_cancelled(token)) return false;
    _step(2, CheckStatus.checking, 'Looking for /data/local/tmp/frida-server…');
    if (!await _adb.fridaServerExists(serial)) {
      _step(2, CheckStatus.failed,
          'frida-server was not found at /data/local/tmp/frida-server. Please install frida-server on your headset before using Frida Link.');
      return false;
    }
    var running = await _adb.fridaServerRunning(serial);
    if (_cancelled(token)) return false;
    if (!running) {
      _step(2, CheckStatus.checking, 'frida-server not running — starting it in daemon mode…');
      final started = await _adb.startFridaServer(serial);
      if (_cancelled(token) || !started) {
        _step(2, CheckStatus.failed,
            'frida-server exists but could not be started. Try launching it manually on the headset.');
        return false;
      }
      running = true;
    } else if (!await _adb.fridaServerDaemonized(serial)) {
      // Spawning apps requires the daemonized frida-server, so restart one
      // that is running without `-D`.
      _step(2, CheckStatus.checking,
          'frida-server running without daemon mode — restarting it…');
      final restarted = await _adb.startFridaServer(serial);
      if (_cancelled(token) || !restarted) {
        _step(2, CheckStatus.failed,
            'frida-server could not be restarted in daemon mode. Try launching `frida-server -D` manually on the headset.');
        return false;
      }
      running = true;
    }
    _step(2, CheckStatus.passed,
        running ? 'frida-server running in daemon mode.' : 'frida-server started.');
    return true;
  }

  /// Records all steps as passed + the connected device. Does not flip
  /// [ConnectionState.isConnected] yet — [advanceConnected] handles the small
  /// success beat so the pipeline shows all green before handing off to the
  /// main shell.
  ConnectedDevice _finish(String address, String serial) {
    final device = ConnectedDevice(
      serial: serial,
      address: address,
      rooted: true,
      fridaServerRunning: true,
    );
    state = cs.copyWith(device: device);
    return device;
  }

  /// After all steps passed, keeps the "all passed" pipeline visible for a
  /// short beat, then hands off to the main shell. Cancelled if the user
  /// changed device / disconnected in the meantime.
  Future<void> _advanceConnected(ConnectedDevice device, int token) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (_cancelled(token) || !_isInFlight(device)) return;
    state =
        cs.copyWith(isConnected: true, showConnectionUi: false, device: device);
  }

  /// True while [device] is still the active connection target and the flow
  /// hasn't flipped the app over to the main shell yet.
  bool _isInFlight(ConnectedDevice device) =>
      cs.device == device && !cs.isConnected;

  Future<ConnectedDevice?> _finishAndAdvance(
      String address, String serial, int token) async {
    if (_cancelled(token)) return null;
    final device = _finish(address, serial);
    await _advanceConnected(device, token);
    return device;
  }

  /// Re-checks root + frida-server (used when the app resumes).
  Future<bool> revalidate() async {
    final device = cs.device;
    if (device == null) return false;
    final adb = _adb;
    _step(1, CheckStatus.checking, 'Re-validating `su`…');
    _step(2, CheckStatus.checking, 'Re-validating frida-server…');

    final rooted = await adb.isRooted(device.serial);
    final server = rooted && await adb.fridaServerExists(device.serial);
    final running = server && await adb.fridaServerRunning(device.serial);

    _step(0, CheckStatus.passed,
        cs.steps[0].detail.isNotEmpty ? cs.steps[0].detail : device.address);
    _step(1, rooted ? CheckStatus.passed : CheckStatus.failed,
        rooted ? '`su` confirmed.' : 'Device no longer rooted.');
    _step(2, running ? CheckStatus.passed : CheckStatus.failed,
        running ? 'frida-server running.' : 'frida-server is not running.');

    if (!running) {
      state = cs.copyWith(isConnected: false, showConnectionUi: true);
      return false;
    }
    return true;
  }

  /// Debug only: skips the connection pipeline and opens the main shell
  /// without a device. Used by the secret Konami-code bypass on the welcome
  /// screen. Mod injection still requires a real device.
  void activateDebugBypass() {
    state = const ConnectionState(
      isConnected: true,
      showConnectionUi: false,
      isDebugBypass: true,
    );
  }

  Future<void> disconnect() async {
    final device = cs.device;
    if (device != null) {
      await _adb.disconnect(device.address);
    }
    state = ConnectionState(steps: ConnectionState.initialSteps());
  }

  Future<List<AdbDeviceInfo>> scanDevices() => _adb.devices();
}

final connectionControllerProvider =
    StateNotifierProvider<ConnectionController, ConnectionState>((ref) {
  return ConnectionController(
    () => ref.read(settingsProvider),
    (settings) => AdbService(adbPath: settings.adbPath),
  );
});
