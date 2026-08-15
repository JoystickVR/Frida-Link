import 'dart:async';

import '../models/connection.dart';
import 'process_runner.dart';

/// Encapsulates all adb interaction (discovery, connect, root + frida checks).
class AdbService {
  AdbService({
    required String adbPath,
    ProcessRunner? runner,
  })  : _runner = runner ?? const ProcessRunner(),
        _adbPath = adbPath.isEmpty ? 'adb' : adbPath;

  final ProcessRunner _runner;
  final String _adbPath;

  String get adbPath => _adbPath;

  /// `adb devices` — returns a list of discovered devices.
  Future<List<AdbDeviceInfo>> devices() async {
    final result = await _runner.run(_adbPath, const ['devices']);
    if (!result.success) return <AdbDeviceInfo>[];
    final list = <AdbDeviceInfo>[];
    for (final line in result.stdout.split('\n')) {
      if (line.trim().isEmpty || line.startsWith('List of devices')) continue;
      final info = AdbDeviceInfo.fromLine(line);
      if (info.serial.isEmpty) continue;
      list.add(info);
    }
    return list;
  }

  /// `adb connect host:port` — returns the outcome enum plus raw output.
  Future<({ConnectOutcome outcome, String raw})> connect(String address) async {
    final result = await _runner.run(_adbPath, ['connect', address]);
    final out = result.stdout.trim();
    if (out.contains('connected to') || out.contains('already connected')) {
      final already = out.contains('already');
      return (
        outcome: already ? ConnectOutcome.alreadyConnected : ConnectOutcome.connected,
        raw: out,
      );
    }
    return (outcome: ConnectOutcome.failed, raw: result.combined);
  }

  /// `adb disconnect host:port` — disconnects a wireless device.
  Future<void> disconnect(String address) async {
    await _runner.run(_adbPath, ['disconnect', address]);
  }

  /// Runs `adb -s <serial> shell <command string>`.
  Future<RunResult> shell(String serial, String command) async {
    return _runner.run(_adbPath, ['-s', serial, 'shell', command]);
  }

  /// Runs `adb -s <serial> exec-out <command>` and returns raw bytes
  /// (binary safe — used for streaming files off the device).
  Future<RunResultBytes> execOut(
    String serial,
    List<String> command, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    return _runner.runBytes(
      _adbPath,
      ['-s', serial, 'exec-out', ...command],
      timeout: timeout,
    );
  }

  /// Runs a command under `su -c` in the device shell.
  Future<RunResult> suShell(String serial, String command) async {
    return _runner.run(_adbPath, ['-s', serial, 'shell', 'su', '-c', command]);
  }

  /// Runs the root-drop test: if `uid=0(root)` appears we are rooted.
  Future<bool> isRooted(String serial) async {
    final result = await suShell(serial, 'id');
    return result.stdout.contains('uid=0(root)');
  }

  /// Checks whether frida-server binary exists at the expected path.
  Future<bool> fridaServerExists(String serial) async {
    final result = await suShell(serial, 'ls -l /data/local/tmp/frida-server');
    return result.stdout.contains('frida-server');
  }

  /// Checks whether frida-server is running (via pidof).
  Future<bool> fridaServerRunning(String serial) async {
    final result = await suShell(serial, 'pidof frida-server');
    return result.stdout.trim().isNotEmpty;
  }

  /// Check /proc/<pid>/cmdline for the `-D` daemon flag.
  Future<bool> fridaServerDaemonized(String serial) async {
    final pid = await suShell(serial, 'pidof frida-server');
    final id = pid.stdout.trim().split(RegExp(r'\s+')).firstOrNull;
    if (id == null || id.isEmpty) return false;
    final result = await suShell(serial, 'cat /proc/$id/cmdline');
    return _isDaemonCmdline(result.stdout);
  }

  /// True when the raw cmdline blob contains a `-D` / `--daemonize` flag.
  /// NUL-separated args are also matched by a plain contains() since `-D`
  /// is a whole argument.
  static bool _isDaemonCmdline(String raw) {
    final text = raw.replaceAll('\u0000', '|');
    return text.contains('-D') || text.contains('--daemonize');
  }

  /// Starts frida-server detached under su, in daemon mode so app spawns
  /// (`frida -f …`) work. Spawns require the daemonized server on Android.
  Future<bool> startFridaServer(String serial) async {
    await suShell(serial, "pkill -f frida-server");
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await suShell(
        serial, "nohup /data/local/tmp/frida-server -D >/dev/null 2>&1 &");
    // Give it a moment to boot before we verify.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return fridaServerRunning(serial);
  }

  /// Returns the connected/ready device matching [address], or null.
  Future<AdbDeviceInfo?> findReadyDevice(String address) async {
    final found = await devices();
    for (final device in found) {
      if (device.serial == address || device.address == address) {
        return device.isReady ? device : null;
      }
    }
    return null;
  }
}