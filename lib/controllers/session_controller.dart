import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/models/mod_entry.dart';
import '../core/services/frida_service.dart';
import '../core/services/process_runner.dart';
import 'app_data_controller.dart';

enum SessionStatus { idle, connecting, attached, detached, error }

enum LogLevel { system, output, error, info }

/// One line in the console log.
class SessionLogLine {
  const SessionLogLine(this.level, this.text, {this.timestamp});

  final LogLevel level;
  final String text;
  final DateTime? timestamp;
}

/// State of the running frida injection session.
class FridaSessionState {
  const FridaSessionState({
    this.status = SessionStatus.idle,
    this.command,
    this.log = const <SessionLogLine>[],
  });

  final SessionStatus status;
  final String? command;
  final List<SessionLogLine> log;

  FridaSessionState copyWith({
    SessionStatus? status,
    String? command,
    List<SessionLogLine>? log,
  }) {
    return FridaSessionState(
      status: status ?? this.status,
      command: command ?? this.command,
      log: log ?? this.log,
    );
  }
}

class FridaSessionController extends StateNotifier<FridaSessionState> {
  FridaSessionController(this._frida, this._settings, this._touchMod)
      : super(const FridaSessionState());

  final FridaService _frida;
  final AppSettings Function() _settings;
  final Future<void> Function(String id) _touchMod;

  LiveProcess? _process;

  FridaSessionState get s => state;

  /// Runs injection for [mod] against [device] (adb address).
  Future<bool> inject(ModEntry mod, {required String device}) async {
    await stop(silent: true);

    final settings = _settings();
    final cmd = _frida.buildCommand(mod: mod, settings: settings, device: device);
    final preview = cmd.preview;

    // Stage the bridge copy before launching so relative filenames resolve.
    await _frida.prepareBridgeCopy(cmd);

    final args = cmd.args.toList();
    final executable = args.isNotEmpty ? args.first : 'frida';
    final rest = args.length > 1 ? args.sublist(1) : <String>[];

    // Frida's CLI treats non-TTY stdin as headless/quiet and exits right after
    // the `-l` scripts complete (default `-t 0`), regardless of the attach
    // succeeding — leaving the session "Detached". Silent the REPL prompt and
    // set an infinite quiet timeout so the process stays alive: the mod stays
    // injected, script logs keep streaming, and Stop stays enabled. We only
    // inject these flags into generated commands (custom commands are owned by
    // the user).
    var display = preview;
    if (!cmd.usedCustom) {
      var extra = <String>[];
      if (!rest.contains('-q')) extra.add('-q');
      if (!rest.contains('-t') && !rest.any((a) => a.startsWith('--timeout'))) {
        extra.addAll(['-t', 'inf']);
      }
      if (extra.isNotEmpty) {
        rest.addAll(extra);
        display = [executable, ...rest].map(_quoteArg).join(' ');
      }
    }

    if (cmd.workingDirectory.isNotEmpty) {
      _emit(LogLevel.info, '> cd ${cmd.workingDirectory}');
    }
    _emit(LogLevel.info, '> $display');
    state = s.copyWith(status: SessionStatus.connecting, command: display);

    try {
      final process = await _frida.start(
        executable,
        rest,
        workingDirectory: cmd.workingDirectory,
        onStdout: (line) => _emit(LogLevel.output, line),
        onStderr: (line) => _emit(LogLevel.error, line),
      );
      _process = process;
      state = state.copyWith(status: SessionStatus.attached);

      unawaited(process.done.then((code) {
        if (_process == process) _process = null;
        _emit(LogLevel.info, 'frida exited (code $code).');
        state = state.copyWith(status: SessionStatus.detached);
      }));
      unawaited(_touchMod(mod.id));
      return true;
    } catch (e) {
      _emit(LogLevel.error, 'Failed to start frida: $e');
      state = state.copyWith(status: SessionStatus.error);
      return false;
    }
  }

  /// Send an expression/command to the attached REPL.
  void sendRepl(String code) {
    final process = _process;
    if (process == null) {
      _emit(LogLevel.info, 'Not attached — nothing to send to.');
      return;
    }
    _emit(LogLevel.output, '> $code');
    process.sendLine(code);
  }

  Future<void> stop({bool silent = false}) async {
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.kill();
      } catch (_) {}
    }
    if (!silent) _emit(LogLevel.info, 'Session stopped.');
    state = state.copyWith(status: SessionStatus.idle);
  }

  void clearLog() =>
      state = state.copyWith(log: const <SessionLogLine>[]);

  /// Plain-text dump of the current log.
  String exportLog() => state.log.map((l) => l.text).join('\n');

  /// Re-quotes an argument for display (spaces need quotes for readability).
  static String _quoteArg(String arg) =>
      arg.contains(' ') ? '"$arg"' : arg;

  void _emit(LogLevel level, String text) {
    state = state.copyWith(log: [
      ...state.log,
      SessionLogLine(level, text, timestamp: DateTime.now()),
    ]);
  }
}

final fridaServiceProvider = Provider<FridaService>((ref) => FridaService());

final sessionControllerProvider =
    StateNotifierProvider<FridaSessionController, FridaSessionState>((ref) {
  return FridaSessionController(
    ref.watch(fridaServiceProvider),
    () => ref.read(settingsProvider),
    (id) async {
      ref.read(appDataControllerProvider.notifier).patchMod(
            id,
            (m) => m.copyWith(lastUsed: DateTime.now()),
          );
    },
  );
});