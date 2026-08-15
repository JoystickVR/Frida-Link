import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/app_data_controller.dart';
import '../controllers/session_controller.dart';
import '../core/models/connection.dart';
import '../core/models/mod_entry.dart';
import '../core/services/frida_service.dart';
import '../core/theme.dart';
import '../widgets/console_view.dart';
import '../widgets/window_title_bar.dart';

/// Dedicated console screen for an injected mod.
class InjectionScreen extends ConsumerStatefulWidget {
  const InjectionScreen({super.key, required this.mod, required this.device});

  final ModEntry mod;
  final ConnectedDevice device;

  @override
  ConsumerState<InjectionScreen> createState() => _InjectionScreenState();
}

class _InjectionScreenState extends ConsumerState<InjectionScreen> {
  final TextEditingController _input = TextEditingController();
  bool _showTimestamps = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    // Kick off the injection right after the first frame so the mod starts
    // attaching immediately when the console opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_started) {
        _started = true;
        ref
            .read(sessionControllerProvider.notifier)
            .inject(widget.mod, device: widget.device.address);
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _saveLog() async {
    final text = ref.read(sessionControllerProvider.notifier).exportLog();
    final path = await FilePicker.saveFile(
      fileName: 'frida_log_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    if (path == null) return;
    await File(path).writeAsString(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Log saved.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    final settings = ref.watch(settingsProvider);
    final cmd = FridaService().buildCommand(
      mod: widget.mod,
      settings: settings,
      device: widget.device.address,
    );
    final sessionCommand = session.command ?? cmd.preview;

    return Scaffold(
      body: Column(
        children: [
          const DraggableTitleBar(
            title: 'Frida Link — Session',
            leading: _BackButton(),
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _OverviewPanel(
                        mod: widget.mod,
                        device: widget.device,
                        command: sessionCommand,
                        workingDirectory: cmd.workingDirectory,
                        bridgePath: FridaService().resolveBridge(widget.mod, settings),
                        status: session.status,
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ConsoleView(
                          log: session.log,
                          showTimestamps: _showTimestamps,
                        ),
                      ),
                      _ConsoleControls(
                        status: session.status,
                        onStop: () => ref
                            .read(sessionControllerProvider.notifier)
                            .stop(),
                        onRestart: () => ref
                            .read(sessionControllerProvider.notifier)
                            .inject(widget.mod, device: widget.device.address),
                        onCopy: () async {
                          final text = ref
                              .read(sessionControllerProvider.notifier)
                              .exportLog();
                          await Clipboard.setData(ClipboardData(text: text));
                        },
                        onClear: () => ref
                            .read(sessionControllerProvider.notifier)
                            .clearLog(),
                        onSave: _saveLog,
                        onToggleTimestamps: () =>
                            setState(() => _showTimestamps = !_showTimestamps),
                      ),
                      _ReplInput(
                        controller: _input,
                        onSend: (text) => ref
                            .read(sessionControllerProvider.notifier)
                            .sendRepl(text),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                SizedBox(
                  width: 260,
                  child: _SessionPanel(
                      mod: widget.mod,
                      device: widget.device,
                      command: sessionCommand,
                    ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Leaves the session screen and returns to the mod library.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: 'Back to mod library',
      icon: const Icon(Icons.arrow_back, size: 16),
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}

class _OverviewPanel extends StatelessWidget {
  const _OverviewPanel({
    required this.mod,
    required this.device,
    required this.command,
    required this.workingDirectory,
    required this.bridgePath,
    required this.status,
  });

  final ModEntry mod;
  final ConnectedDevice device;
  final String command;
  final String workingDirectory;
  final String bridgePath;
  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(mod.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${mod.appName} · ${mod.bundleId}',
            style: TextStyle(fontSize: 12, color: scheme.onSurface),
          ),
          const SizedBox(height: 4),
          _kvRow(context, 'Script',
              mod.scriptPath.split(RegExp(r'[\\/]')).last,
              path: mod.scriptPath),
          _kvRow(context, 'Bridge',
              bridgePath.isNotEmpty
                  ? bridgePath.split(RegExp(r'[\\/]')).last
                  : '(default not set)',
              path: bridgePath),
          _kvRow(context, 'Device', '${device.address} (${device.serial})'),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (workingDirectory.isNotEmpty) ...[
                  SelectableText(
                    'cd $workingDirectory',
                    style: Mono.code(Theme.of(context).textTheme, size: 12),
                  ),
                  const SizedBox(height: 2),
                ],
                SelectableText(
                  command,
                  style: Mono.code(Theme.of(context).textTheme, size: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kvRow(BuildContext context, String label, String value,
      {String? path}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.outline)),
          ),
          Expanded(
            child: Tooltip(
              message: path ?? value,
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5, color: scheme.onSurface, fontFamily: 'monospace'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final SessionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (String label, Color color) = switch (status) {
      SessionStatus.idle => ('Idle', scheme.onSurfaceVariant),
      SessionStatus.connecting => ('Connecting…', scheme.tertiary),
      SessionStatus.attached => ('Attached', scheme.primary),
      SessionStatus.detached => ('Detached', scheme.secondary),
      SessionStatus.error => ('Error', scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }
}

class _ConsoleControls extends StatelessWidget {
  const _ConsoleControls({
    required this.status,
    required this.onStop,
    required this.onRestart,
    required this.onCopy,
    required this.onClear,
    required this.onSave,
    required this.onToggleTimestamps,
  });

  final SessionStatus status;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onCopy;
  final VoidCallback onClear;
  final VoidCallback onSave;
  final VoidCallback onToggleTimestamps;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          _button(Icons.stop, 'Stop', onStop,
              enabled: status == SessionStatus.attached ||
                  status == SessionStatus.connecting),
          _button(Icons.refresh, 'Restart', onRestart),
          _button(Icons.content_copy, 'Copy log', onCopy),
          _button(Icons.delete_sweep, 'Clear', onClear),
          _button(Icons.save_alt, 'Save log', onSave),
          const Spacer(),
          IconButton(
            tooltip: 'Toggle timestamps',
            iconSize: 16,
            icon: const Icon(Icons.schedule),
            onPressed: onToggleTimestamps,
          ),
        ],
      ),
    );
  }

  Widget _button(IconData icon, String label, VoidCallback onTap,
      {bool enabled = true}) {
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: const TextStyle(fontSize: 11.5),
      ),
      icon: Icon(icon, size: 15),
      label: Text(label),
    );
  }
}

class _ReplInput extends StatelessWidget {
  const _ReplInput({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      color: scheme.surfaceContainerLowest,
      child: Row(
        children: [
          Text('>',
              style: TextStyle(
                  color: scheme.primary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (v) {
                final text = v.trim();
                if (text.isEmpty) return;
                controller.clear();
                onSend(text);
              },
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Send expression to the Frida REPL…',
                hintStyle: TextStyle(fontSize: 12, color: scheme.outline),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            iconSize: 16,
            icon: const Icon(Icons.send),
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              controller.clear();
              onSend(text);
            },
          ),
        ],
      ),
    );
  }
}

class _SessionPanel extends StatelessWidget {
  const _SessionPanel({
    required this.mod,
    required this.device,
    required this.command,
  });

  final ModEntry mod;
  final ConnectedDevice device;
  final String command;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const SizedBox(height: 10),
          _row(context, 'Mod', mod.name),
          _row(context, 'App', mod.appName),
          _row(context, 'Bundle', mod.bundleId),
          _row(context, 'Device', device.address),
          const Divider(height: 20),
          const Text('Tips',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            '• Type expressions at the bottom and press Enter to evaluate in the REPL.\n'
            '• Use the token-based custom command to add -f (spawn) or --runtime=v8.',
            style: TextStyle(fontSize: 11.5, height: 1.5, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: Text(label,
                style: TextStyle(fontSize: 11, color: scheme.outline)),
          ),
          Expanded(
            child: Text(value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurface,
                    fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}