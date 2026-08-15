// Smoke tests for models / command building that don't need platform channels.

import 'package:flutter_test/flutter_test.dart';

import 'package:frida_link_v2/core/models/app_settings.dart';
import 'package:frida_link_v2/core/models/mod_entry.dart';
import 'package:frida_link_v2/core/models/connection.dart';
import 'package:frida_link_v2/core/services/frida_service.dart';
import 'package:frida_link_v2/core/services/process_runner.dart';

void main() {
  test('parseCommandLine splits quoting correctly', () {
    final tokens = parseCommandLine(r'frida -U -l "C:\bridge.js" -l "script file.ts" "Game" --no-pause');
    expect(tokens, [
      'frida',
      '-U',
      '-l',
      r'C:\bridge.js',
      '-l',
      'script file.ts',
      'Game',
      '--no-pause',
    ]);
  });

  test('buildBundleId applies template', () {
    expect(buildBundleId('com.{app}.{app}', 'BeatSaber'),
        'com.BeatSaber.BeatSaber');
    expect(buildBundleId('com.{app}.{app}', '  '), '');
  });

  test('ModEntry JSON round-trips', () {
    final mod = ModEntry(
      id: 'm1',
      name: 'My mod',
      scriptPath: r'C:\mods\script.ts',
      appName: 'BeatSaber',
      bundleId: 'com.BeatGames.BeatSaber',
      customCommand: 'frida -U --no-pause "{app}"',
      addedAt: DateTime.utc(2026, 1, 1),
    );
    final restored = ModEntry.fromJson(mod.toJson());
    expect(restored.id, mod.id);
    expect(restored.name, mod.name);
    expect(restored.customCommand, mod.customCommand);
    expect(restored.bundleId, mod.bundleId);
  });

  test('AdbDeviceInfo.fromLine parses wireless entries', () {
    final info = AdbDeviceInfo.fromLine('192.168.1.50:5555\tdevice');
    expect(info.serial, '192.168.1.50:5555');
    expect(info.address, '192.168.1.50:5555');
    expect(info.isReady, isTrue);

    final usb = AdbDeviceInfo.fromLine('R5CR1234ABCD\tdevice');
    expect(usb.address, '');
  });

  test('buildCommand uses script folder as working directory + relative paths',
      () {
    final mod = ModEntry(
      id: 'm2',
      name: 'TS mod',
      scriptPath: r'C:\mods\aim\script.ts',
      appName: 'BeatSaber',
      bundleId: 'com.BeatGames.BeatSaber',
    );
    const settings = AppSettings(
      defaultBridgePath: r'C:\bridges\frida-il2cpp-bridge.js',
    );
    final cmd = FridaService().buildCommand(mod: mod, settings: settings);

    expect(cmd.workingDirectory, r'C:\mods\aim');
    expect(cmd.preview, contains(r'frida-il2cpp-bridge.js'));
    expect(cmd.preview, contains('script.ts'));
    expect(cmd.preview, isNot(contains(r'C:\bridges')));
    expect(cmd.preview, isNot(contains(r'C:\mods\aim\')));
    expect(cmd.args, contains('script.ts'));
    // Bridge lives outside the script folder -> staged copy is planned.
    expect(cmd.bridgeCopyTarget, r'C:\mods\aim\frida-il2cpp-bridge.js');
    expect(cmd.bridgeSource, r'C:\bridges\frida-il2cpp-bridge.js');
  });

  test('buildCommand skips bridge copy when it shares the script folder', () {
    final mod = ModEntry(
      id: 'm3',
      name: 'Local bridge mod',
      scriptPath: r'C:\mods\aim\script.ts',
      appName: 'Game',
      bundleId: 'com.example.Game',
    );
    const settings = AppSettings(
      defaultBridgePath: r'C:\mods\aim\bridge.js',
    );
    final cmd = FridaService().buildCommand(mod: mod, settings: settings);

    expect(cmd.workingDirectory, r'C:\mods\aim');
    expect(cmd.bridgeCopyTarget, '');
    expect(cmd.bridgeSource, '');
  });

  test('custom command is not rewritten but still gets working directory', () {
    final mod = ModEntry(
      id: 'm4',
      name: 'Custom',
      scriptPath: r'C:\mods\aim\script.ts',
      appName: 'Game',
      bundleId: 'com.example.Game',
      customCommand: 'frida -U -f {bundle_id} -l {script} --no-pause',
    );
    const settings = AppSettings(defaultBridgePath: r'C:\bridges\b.js');
    final cmd = FridaService().buildCommand(mod: mod, settings: settings);

    expect(cmd.usedCustom, isTrue);
    expect(cmd.workingDirectory, r'C:\mods\aim');
    expect(cmd.preview, 'frida -U -f com.example.Game -l script.ts --no-pause');
    expect(cmd.bridgeCopyTarget, r'C:\mods\aim\b.js');
  });
}
