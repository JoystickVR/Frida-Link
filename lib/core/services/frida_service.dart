import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_settings.dart';
import '../models/mod_entry.dart';
import 'process_runner.dart';

/// Result of a frida injection command assembly.
class FridaCommand {
  const FridaCommand({
    required this.args,
    required this.preview,
    required this.usedCustom,
    required this.workingDirectory,
    this.bridgeSource = '',
    this.bridgeCopyTarget = '',
  });

  /// Full argv (executable first) using filenames relative to
  /// [workingDirectory].
  final List<String> args;

  /// The expanded command string exactly as it will be executed.
  final String preview;

  final bool usedCustom;

  /// Directory the `frida` process must run in (the script's parent dir).
  final String workingDirectory;

  /// Absolute path of the bridge to stage when it lives outside the script
  /// folder (empty when no copy is needed).
  final String bridgeSource;

  /// Absolute path to place the staged bridge copy at (empty when no copy is
  /// needed). Stable per-run path — the copy is reused/replaced, not duplicated.
  final String bridgeCopyTarget;
}

/// Builds and runs the `frida` client.
class FridaService {
  FridaService({ProcessRunner? runner}) : _runner = runner ?? const ProcessRunner();

  final ProcessRunner _runner;

  /// Resolve bridge file for [mod] given global [settings].
  String resolveBridge(ModEntry mod, AppSettings settings) {
    final override = mod.bridgeOverridePath.trim();
    if (override.isNotEmpty) return override;
    return settings.defaultBridgePath.trim();
  }

  /// Expand `{token}` placeholders in [template].
  String expandTokens(
    String template, {
    required String bridge,
    required String script,
    required String app,
    required String bundleId,
    required String device,
  }) {
    return template
        .replaceAll('{bridge}', bridge)
        .replaceAll('{script}', script)
        .replaceAll('{app}', app)
        .replaceAll('{bundle_id}', bundleId.isNotEmpty ? bundleId : app)
        .replaceAll('{device}', device)
        .trim();
  }

  /// Resolve the target name used in the command (app name → bundle id).
  String targetName(ModEntry mod) => mod.appName.trim().isNotEmpty
      ? mod.appName.trim()
      : mod.bundleId.trim();

  /// Assemble a [FridaCommand] — honors per-mod custom command override.
  ///
  /// .ts entrypoints are compiled by Frida's built-in TypeScript compiler,
  /// which derives a "project root" from the process's current working
  /// directory (or nearest package.json). Passing an absolute path outside
  /// that root fails with "entrypoint must be inside the project root", so we
  /// run `frida` from the script's own folder and pass relative filenames.
  /// This is required for .ts and harmless for .js.
  /// https://github.com/frida/frida-compile/issues/82
  FridaCommand buildCommand({
    required ModEntry mod,
    required AppSettings settings,
    String device = '',
  }) {
    final bridge = resolveBridge(mod, settings);
    final script = mod.scriptPath.trim();
    final app = targetName(mod);
    final custom = mod.customCommand.trim();
    final usedCustom = custom.isNotEmpty;

    // Use the Windows-flavoured path context so absolute paths written with
    // backslashes (and forward slashes) both resolve the same way.
    final scriptDir = script.isNotEmpty ? p.windows.dirname(script) : '';
    final scriptName = script.isNotEmpty ? p.windows.basename(script) : script;

    // Bridge: use its filename relative to the script folder. When it lives
    // elsewhere, stage a copy into the script folder on a stable path so it is
    // reused/replaced across runs rather than duplicated.
    String bridgeName = '';
    String bridgeCopyTarget = '';
    var sameFolder = false;
    if (bridge.isNotEmpty) {
      bridgeName = p.windows.basename(bridge);
      final bridgeDir = p.windows.dirname(bridge);
      sameFolder = scriptDir.isNotEmpty &&
          p.windows.equals(scriptDir, bridgeDir);
      if (!sameFolder && scriptDir.isNotEmpty) {
        bridgeCopyTarget = p.windows.join(scriptDir, bridgeName);
      }
    }

    final template = usedCustom ? custom : settings.defaultCommandTemplate;
    final expanded = expandTokens(
      template,
      bridge: bridgeName,
      script: scriptName,
      app: app,
      bundleId: mod.bundleId.trim(),
      device: device,
    );
    return FridaCommand(
      args: parseCommandLine(expanded),
      preview: expanded,
      usedCustom: usedCustom,
      workingDirectory: scriptDir,
      bridgeSource: sameFolder ? '' : bridge,
      bridgeCopyTarget: bridgeCopyTarget,
    );
  }

  /// Stages the bridge copy into the script folder when it lives elsewhere.
  /// The target path is stable, so an existing copy is simply overwritten
  /// (reused) rather than duplicated on every run.
  Future<void> prepareBridgeCopy(FridaCommand cmd) async {
    if (cmd.bridgeCopyTarget.isEmpty || cmd.bridgeSource.isEmpty) return;
    final source = File(cmd.bridgeSource);
    if (!await source.exists()) return;
    try {
      await source.copy(cmd.bridgeCopyTarget);
    } catch (_) {
      // Leave any previously staged copy in place; the launch will still work.
    }
  }

  /// Starts `frida` with [args] (the binary name is expected as args[0]).
  Future<LiveProcess> start(
    String executable,
    List<String> args, {
    String? workingDirectory,
    void Function(String line)? onStdout,
    void Function(String line)? onStderr,
  }) {
    return _runner.startStreaming(executable, args,
        workingDirectory: workingDirectory,
        onStdout: onStdout,
        onStderr: onStderr);
  }
}