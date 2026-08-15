import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/app_data_controller.dart';
import '../controllers/app_icon_controller.dart';
import '../controllers/connection_controller.dart';
import '../core/models/app_settings.dart';
import '../core/models/mod_entry.dart';
import '../core/services/adb_service.dart';
import '../core/services/frida_service.dart';
import '../widgets/file_drop_zone.dart';

/// Add/edit a mod.
class AddModSheet extends ConsumerStatefulWidget {
  const AddModSheet({super.key, this.existing, this.scriptPath});

  final ModEntry? existing;

  /// Pre-filled script path (e.g. opened via the Explorer context menu).
  final String? scriptPath;

  @override
  ConsumerState<AddModSheet> createState() => _AddModSheetState();
}

class _AddModSheetState extends ConsumerState<AddModSheet> {
  late final TextEditingController _name;
  final TextEditingController _appName = TextEditingController();
  final TextEditingController _bundleId = TextEditingController();
  late final TextEditingController _customCommandCtrl;
  String? _scriptPath;
  String _bridgeOverride = '';
  String _customCommand = '';
  bool _useCustomBridge = false;
  bool _useCustomCommand = false;
  String? _iconSource;
  bool _fetchingIcon = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _name = TextEditingController(text: existing?.name ?? '');
    _appName.text = existing?.appName ?? '';
    _bundleId.text = existing?.bundleId ?? '';
    _scriptPath = existing?.scriptPath ?? widget.scriptPath;
    _bridgeOverride = existing?.bridgeOverridePath ?? '';
    _customCommand = existing?.customCommand ?? '';
    _iconSource = existing?.iconPath.isNotEmpty == true ? existing?.iconPath : null;
    _customCommandCtrl = TextEditingController(text: _customCommand);
    _useCustomBridge = (_bridgeOverride.isNotEmpty);
    _useCustomCommand = (_customCommand.isNotEmpty);
    if (_name.text.isEmpty && _scriptPath != null) {
      final fileName = _scriptPath!.split(RegExp(r'[\\/]')).last;
      final dot = fileName.lastIndexOf('.');
      _name.text = dot > 0 ? fileName.substring(0, dot) : fileName;
    }
    if (_bridgeOverride.isNotEmpty || _customCommand.isNotEmpty) {
      // seed the preview when editing a custom command
      _buildDefaultCommand();
    }
  }

  void _buildDefaultCommand() {
    final settings = ref.read(settingsProvider);
    final cmd = FridaService().buildCommand(
      mod: _previewMod(),
      settings: settings,
      device: ref.read(connectionControllerProvider).device?.address ?? '',
    );
    if (_customCommand.isEmpty) _customCommand = cmd.preview;
  }

  ModEntry _previewMod() => ModEntry(
        id: widget.existing?.id ?? 'preview',
        name: _name.text.trim(),
        scriptPath: _scriptPath ?? '',
        appName: _appName.text.trim(),
        bundleId: _bundleId.text.trim(),
        bridgeOverridePath: _useCustomBridge ? _bridgeOverride : '',
        customCommand: _useCustomCommand ? _customCommand : '',
      );

  @override
  void dispose() {
    _name.dispose();
    _appName.dispose();
    _bundleId.dispose();
    _customCommandCtrl.dispose();
    super.dispose();
  }

  Future<void> _browseInstalledApps() async {
    final device = ref.read(connectionControllerProvider).device;
    if (device == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected to a headset.')));
      return;
    }
    final settings = ref.read(settingsProvider);
    final adb = AdbService(adbPath: settings.adbPath);
    final result = await adb.shell(device.serial, 'pm list packages -3');
    final list = result.stdout
        .split('\n')
        .map((l) => l.replaceAll('package:', '').trim())
        .where((l) => l.isNotEmpty)
        .toList()
      ..sort();
    if (!mounted) return;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No third-party packages found on the headset.')));
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => _AppPicker(list: list),
    );
    if (picked != null) {
      setState(() {
        _bundleId.text = picked;
        if (_appName.text.isEmpty) {
          _appName.text = picked.split('.').last;
        }
      });
    }
  }

  Future<void> _fetchFromHeadset() async {
    final device = ref.read(connectionControllerProvider).device;
    if (device == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not connected to a headset.')));
      return;
    }
    final bundle = _bundleId.text.trim();
    if (bundle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a bundle ID first.')));
      return;
    }
    setState(() => _fetchingIcon = true);
    String? path;
    try {
      path = await ref
          .read(appIconServiceProvider)
          .fetchAppIcon(device.serial, bundle);
    } catch (_) {
      path = null;
    }
    if (!mounted) return;
    setState(() => _fetchingIcon = false);
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not find an icon for that app on the headset.')));
      return;
    }
    setState(() => _iconSource = path);
  }

  void _clearIcon() => setState(() => _iconSource = null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final device = ref.watch(connectionControllerProvider).device;
    final height = MediaQuery.of(context).size.height;

    return SizedBox(
      height: height * 0.92,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_isEdit ? 'Edit Mod' : 'Add Mod',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Mod name',
                    child: TextField(
                      controller: _name,
                      decoration: InputDecoration(
                        hintText: 'My Beat Saber mod',
                        hintStyle: TextStyle(color: scheme.outline),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'Script file (.ts / .js)',
                    child: FileDropZone(
                      label: 'Script file',
                      placeholder: 'Drop a .ts or .js file here, or browse',
                      allowedExtensions: const ['ts', 'js'],
                      value: _scriptPath,
                      onPicked: (path) {
                        setState(() {
                          _scriptPath = path;
                          if (_name.text.isEmpty) {
                            final name =
                                path.split(RegExp(r'[\\/]')).last;
                            final dot = name.lastIndexOf('.');
                            _name.text =
                                dot > 0 ? name.substring(0, dot) : name;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Target app',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _appName,
                          decoration: const InputDecoration(
                              labelText: 'App name (e.g. BeatSaber)'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _bundleId,
                          decoration: const InputDecoration(
                              labelText: 'Bundle ID (optional)',
                              hintText: 'com.BeatGames.BeatSaber'),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _browseInstalledApps,
                        icon: const Icon(Icons.apps, size: 18),
                        label: const Text('Browse installed'),
                      ),
                    ],
                  ),
                  if (_appName.text.isNotEmpty &&
                      _bundleId.text.isEmpty &&
                      settings.bundleIdTemplate.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Will use: ${buildBundleId(settings.bundleIdTemplate, _appName.text)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: scheme.outline,
                            fontFamily: 'monospace'),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _Field(
                    label: 'App icon (optional)',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _IconPreview(iconPath: _iconSource),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FileDropZone(
                                label: 'Icon file',
                                placeholder:
                                    'Drop a PNG/JPG image, or browse',
                                allowedExtensions: const [
                                  'png',
                                  'jpg',
                                  'jpeg',
                                  'webp'
                                ],
                                value: _iconSource,
                                onPicked: (path) =>
                                    setState(() => _iconSource = path),
                              ),
                            ),
                          ],
                        ),
                        if (device != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed:
                                      _fetchingIcon ? null : _fetchFromHeadset,
                                  icon: _fetchingIcon
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.download, size: 16),
                                  label: const Text('Fetch icon from headset'),
                                ),
                                if (_iconSource != null &&
                                    _iconSource!.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: _clearIcon,
                                    icon: const Icon(Icons.close, size: 16),
                                    label: const Text('Remove'),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Use custom bridge file for this mod',
                        style: TextStyle(fontSize: 13)),
                    value: _useCustomBridge,
                    onChanged: (v) => setState(() => _useCustomBridge = v),
                  ),
                  if (_useCustomBridge) ...[
                    const SizedBox(height: 6),
                    FileDropZone(
                      label: 'Bridge file',
                      placeholder: 'Drop frida-il2cpp-bridge.js',
                      allowedExtensions: const ['js'],
                      value: _bridgeOverride,
                      onPicked: (path) => setState(() => _bridgeOverride = path),
                      compact: true,
                    ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        settings.defaultBridgePath.isNotEmpty
                            ? 'Default bridge: ${settings.defaultBridgePath.split(RegExp(r'[\\/]')).last}'
                            : 'No default bridge set — add one in Settings.',
                        style: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Use custom Frida command',
                        style: TextStyle(fontSize: 13)),
                    subtitle: const Text(
                        'Override the generated command with your own flags.',
                        style: TextStyle(fontSize: 11)),
                    value: _useCustomCommand,
                    onChanged: (v) {
                      setState(() {
                        _useCustomCommand = v;
                        if (v && _customCommand.isEmpty) _buildDefaultCommand();
                      });
                    },
                  ),
                  if (_useCustomCommand) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _customCommandCtrl,
                      onChanged: (v) => setState(() => _customCommand = v),
                      maxLines: 2,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Command (tokens: {bridge} {script} {app} {bundle_id} {device})',
                        labelStyle: TextStyle(fontSize: 11, color: scheme.outline),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Runs in the script\'s folder (cd below) so .ts entrypoints '
                      'compile correctly; your command is not rewritten.',
                      style: TextStyle(fontSize: 10, color: scheme.outline),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _CommandPreview(mod: _previewMod()),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                children: [
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _canSave ? _save : null,
                    icon: const Icon(Icons.save, size: 18),
                    label: const Text('Save Mod'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _scriptPath != null &&
      (_appName.text.trim().isNotEmpty || _bundleId.text.trim().isNotEmpty);

  Future<void> _save() async {
    final settings = ref.read(settingsProvider);
    final bundleId = _bundleId.text.trim().isNotEmpty
        ? _bundleId.text.trim()
        : buildBundleId(settings.bundleIdTemplate, _appName.text);
    final now = DateTime.now();
    final modId = widget.existing?.id ?? 'mod-${now.millisecondsSinceEpoch}';
    final iconService = ref.read(appIconServiceProvider);

    var iconPath = '';
    if (_iconSource != null && _iconSource!.isNotEmpty) {
      iconPath = await iconService.saveModIcon(modId, _iconSource!);
    } else if (widget.existing?.iconPath.isNotEmpty == true) {
      await iconService.removeModIcon(modId);
    }

    final mod = ModEntry(
      id: modId,
      name: _name.text.trim(),
      scriptPath: _scriptPath!,
      appName: _appName.text.trim(),
      bundleId: bundleId,
      bridgeOverridePath: _useCustomBridge ? _bridgeOverride : '',
      customCommand: _useCustomCommand ? _customCommand : '',
      iconPath: iconPath,
      lastUsed: widget.existing?.lastUsed,
      addedAt: widget.existing?.addedAt ?? now,
    );
    await ref.read(appDataControllerProvider.notifier).upsertMod(mod);
    if (mounted) Navigator.pop(context);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({this.iconPath});

  final String? iconPath;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = iconPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(path),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _empty(scheme),
        ),
      );
    }
    return _empty(scheme);
  }

  Widget _empty(ColorScheme scheme) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(Icons.image_outlined, size: 22, color: scheme.outline),
      );
}

class _CommandPreview extends ConsumerWidget {
  const _CommandPreview({required this.mod});

  final ModEntry mod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final device = ref.watch(connectionControllerProvider).device;
    final cmd = FridaService().buildCommand(
      mod: mod,
      settings: settings,
      device: device?.address ?? '',
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Command preview',
              style: TextStyle(fontSize: 10.5, color: scheme.outline)),
          const SizedBox(height: 4),
          if (cmd.workingDirectory.isNotEmpty)
            SelectableText(
              'cd ${cmd.workingDirectory}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          SelectableText(
            cmd.preview,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          if (cmd.usedCustom)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('(custom command)',
                  style: TextStyle(fontSize: 10, color: scheme.tertiary)),
            ),
        ],
      ),
    );
  }
}

class _AppPicker extends StatefulWidget {
  const _AppPicker({required this.list});

  final List<String> list;

  @override
  State<_AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<_AppPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.list
        .where((a) => a.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('Installed apps'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                  hintText: 'Search packages…', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (_, i) => ListTile(
                  dense: true,
                  title: Text(filtered[i],
                      style:
                          const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                  onTap: () => Navigator.pop(context, filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ],
    );
  }
}