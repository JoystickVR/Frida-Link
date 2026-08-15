import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

/// Result of a completed short-lived process run.
class RunResult {
  const RunResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get success => exitCode == 0;
  String get combined => '$stdout\n$stderr';

  @override
  String toString() => 'RunResult($exitCode)';
}

/// Result of a completed short-lived process run whose stdout is raw bytes
/// (e.g. `adb exec-out` streaming a binary file).
class RunResultBytes {
  const RunResultBytes(this.exitCode, this.stdoutBytes);

  final int exitCode;
  final List<int> stdoutBytes;

  bool get success => exitCode == 0;

  @override
  String toString() => 'RunResultBytes($exitCode, ${stdoutBytes.length}B)';
}

/// Handle to a long-running process with streamed output + writable input.
class LiveProcess {
  LiveProcess._(this._process);

  final Process _process;
  final _stdoutBuffer = StringBuffer();
  final _stderrBuffer = StringBuffer();

  /// Sends raw bytes (or a line) to the process stdin.
  void send(String data) => _process.stdin.write(data);

  void sendLine(String line) => _process.stdin.writeln(line);

  Future<int> get done => _process.exitCode;

  Future<void> kill({ProcessSignal signal = ProcessSignal.sigterm}) async {
    try {
      _process.kill(signal);
    } catch (_) {}
  }

  String get capturedStdout => _stdoutBuffer.toString();
  String get capturedStderr => _stderrBuffer.toString();
}

/// Thin wrapper around `Process.run` / `Process.start`.
class ProcessRunner {
  const ProcessRunner();

  /// Runs [executable] to completion with a timeout.
  Future<RunResult> run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 25),
    String? workingDirectory,
  }) async {
    try {
      final process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        environment: Platform.environment,
        mode: ProcessStartMode.normal,
      );
      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      process.stdout.transform(utf8.decoder).listen(stdoutBuf.write);
      process.stderr.transform(utf8.decoder).listen(stderrBuf.write);
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      return RunResult(code, stdoutBuf.toString(), stderrBuf.toString());
    } on ProcessException catch (e) {
      return RunResult(-1, '', e.message);
    }
  }

  /// Runs [executable] to completion, returning stdout as raw bytes (binary
  /// safe). stderr is discarded.
  Future<RunResultBytes> runBytes(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    try {
      final process = await Process.start(
        executable,
        args,
        environment: Platform.environment,
        mode: ProcessStartMode.normal,
      );
      final stdoutBuf = BytesBuilder(copy: false);
      process.stdout.listen(stdoutBuf.add);
      process.stderr.drain<void>();
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      return RunResultBytes(code, stdoutBuf.takeBytes());
    } on ProcessException {
      return const RunResultBytes(-1, <int>[]);
    }
  }

  /// Starts a process and streams each output line through [onStdout]/[onStderr].
  Future<LiveProcess> startStreaming(
    String executable,
    List<String> args, {
    String? workingDirectory,
    void Function(String line)? onStdout,
    void Function(String line)? onStderr,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      environment: Platform.environment,
      mode: ProcessStartMode.normal,
    );
    final handle = LiveProcess._(process);
    process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      handle._stdoutBuffer.writeln(line);
      onStdout?.call(line);
    });
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
      handle._stderrBuffer.writeln(line);
      onStderr?.call(line);
    });
    return handle;
  }
}

/// Parses a `frida` style command string into argument tokens, honoring
/// double- and single-quoting and `--flag=value` forms.
List<String> parseCommandLine(String line) {
  final tokens = <String>[];
  final buf = StringBuffer();
  String? quote;
  var escaping = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    // Backslash escapes are only honored outside quotes (preserving Windows
    // paths like C:\tools\script.js inside double quotes).
    if (escaping) {
      buf.write(ch);
      escaping = false;
      continue;
    }
    if (quote == null && ch == r'\' && i + 1 < line.length) {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      continue;
    }
    if (ch == ' ') {
      if (buf.isNotEmpty) {
        tokens.add(buf.toString());
        buf.clear();
      }
      continue;
    }
    buf.write(ch);
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  return tokens;
}