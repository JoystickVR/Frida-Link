import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/app_data_controller.dart';
import '../core/models/app_settings.dart';
import '../widgets/color_picker.dart';
import '../widgets/file_drop_zone.dart';

/// Settings: bridge file, adb path, command template, theme, history.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

/// Pre-set accent colors offered in settings.
const _accentPresets = <(String, int)>[
  ('Meta Blue', 0xFF0081FB),
  ('Terminal Green', 0xFF7CFA6F),
  ('Fire Red', 0xFFEF5350),
  ('Orange', 0xFFFFB300),
  ('Amber', 0xFFFFC23E),
  ('Purple', 0xFFAB47BC),
  ('Pink', 0xFFE91E63),
  ('Teal', 0xFF26A69A),
  ('Indigo', 0xFF5C6BC0),
];

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _adbPath;
  late final TextEditingController _cmdTemplate;
  late final TextEditingController _bundleTemplate;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      _loaded = true;
      _initFromSettings();
    }
  }

  void _initFromSettings() {
    final s = ref.read(settingsProvider);
    _adbPath = TextEditingController(text: s.adbPath);
    _cmdTemplate = TextEditingController(text: s.defaultCommandTemplate);
    _bundleTemplate = TextEditingController(text: s.bundleIdTemplate);
  }

  @override
  void dispose() {
    _adbPath.dispose();
    _cmdTemplate.dispose();
    _bundleTemplate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final notifier = ref.read(appDataControllerProvider.notifier);
    await notifier.updateSettings((s) => s.copyWith(
          adbPath: _adbPath.text.trim(),
          defaultCommandTemplate: _cmdTemplate.text,
          bundleIdTemplate: _bundleTemplate.text.trim(),
        ));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved.')));
    }
  }

  Future<void> _pickCustom(int current) async {
    final picked = await AccentColorPickerDialog.show(context, Color(current));
    if (picked != null && mounted) {
      await ref
          .read(appDataControllerProvider.notifier)
          .updateSettings((s) => s.copyWith(accentColor: picked.value));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    final data = ref.watch(appDataControllerProvider);

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Row(
          children: [
            Text('Settings',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const Spacer(),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Save'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default bridge file',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Used for every mod that does not override it.',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
                const SizedBox(height: 10),
                FileDropZone(
                  label: 'frida-il2cpp-bridge.js',
                  placeholder: 'Drop frida-il2cpp-bridge.js here, or browse',
                  allowedExtensions: const ['js'],
                  value: settings.defaultBridgePath,
                  onPicked: (path) => ref
                      .read(appDataControllerProvider.notifier)
                      .updateSettings(
                          (s) => s.copyWith(defaultBridgePath: path)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ADB path',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Leave empty to use `adb` from PATH.',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _adbPath,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12.5),
                        decoration: const InputDecoration(
                          labelText: 'adb path',
                          hintText: r'C:\adb\adb.exe',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () {
                        _adbPath.text = '';
                        _save();
                      },
                      child: const Text('Use PATH'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Default device',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text(
                    'Automatically connect to this wireless ADB address on launch.',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          settings.defaultDevice.isEmpty
                              ? 'None'
                              : settings.defaultDevice,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12.5,
                            color: settings.defaultDevice.isEmpty
                                ? scheme.outline
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: settings.defaultDevice.isEmpty
                          ? null
                          : () => ref
                              .read(appDataControllerProvider.notifier)
                              .updateSettings(
                                  (s) => s.copyWith(defaultDevice: '')),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                if (settings.recentDevices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Set from history',
                      style: TextStyle(fontSize: 11, color: scheme.outline)),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final d in settings.recentDevices)
                        ActionChip(
                          avatar: settings.defaultDevice == d
                              ? const Icon(Icons.check, size: 14)
                              : null,
                          label: Text(d,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => ref
                              .read(appDataControllerProvider.notifier)
                              .updateSettings(
                                  (s) => s.copyWith(defaultDevice: d)),
                        ),
                    ],
                  ),
                ],
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Ask before switching devices'),
                  subtitle: Text(
                      'Show a prompt when a different device connects.',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  value: !settings.neverAskDefaultDevice,
                  onChanged: (v) => ref
                      .read(appDataControllerProvider.notifier)
                      .updateSettings(
                          (s) => s.copyWith(neverAskDefaultDevice: !v)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Command template',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 4),
                Text('Tokens: {bridge} {script} {app} {bundle_id} {device} · '
                    'use {bundle_id} with -f to spawn the app',
                    style: TextStyle(fontSize: 11, color: scheme.outline)),
                const SizedBox(height: 10),
                TextField(
                  controller: _cmdTemplate,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: () {
                    _cmdTemplate.text = defaultCommandTemplate();
                    _bundleTemplate.text =
                        'com.{app}.{app}';
                    _save();
                  },
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Reset to default'),
                ),
                const SizedBox(height: 10),
                Text('Bundle ID template',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 6),
                TextField(
                  controller: _bundleTemplate,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Accent color',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const Spacer(),
                    TextButton(
                      onPressed: () => ref
                          .read(appDataControllerProvider.notifier)
                          .updateSettings(
                              (s) => s.copyWith(accentColor: 0xFF0081FB)),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
                Text('Seed color used by the Material 3 theme.',
                    style: TextStyle(fontSize: 12, color: scheme.outline)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, argb) in _accentPresets)
                      _AccentSwatch(
                        name: name,
                        color: Color(argb),
                        selected: settings.accentColor == argb,
                        onTap: () => ref
                            .read(appDataControllerProvider.notifier)
                            .updateSettings(
                                (s) => s.copyWith(accentColor: argb)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickCustom(settings.accentColor),
                      icon: const Icon(Icons.colorize, size: 16),
                      label: const Text('Custom…'),
                    ),
                    const Spacer(),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(settings.accentColor),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      colorHex(Color(settings.accentColor)),
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: scheme.onSurface)),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark mode'),
                  value: settings.darkMode,
                  onChanged: (v) => ref
                      .read(appDataControllerProvider.notifier)
                      .updateSettings((s) => s.copyWith(darkMode: v)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Material 2 design'),
                  subtitle: Text(
                      'Use the older Material 2 look instead of Material 3.',
                      style: TextStyle(fontSize: 12, color: scheme.outline)),
                  value: settings.useMaterial2,
                  onChanged: (v) => ref
                      .read(appDataControllerProvider.notifier)
                      .updateSettings((s) => s.copyWith(useMaterial2: v)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Connection history',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                    const Spacer(),
                    Text('${data.settings.recentDevices.length} saved',
                        style: TextStyle(fontSize: 11, color: scheme.outline)),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final d in data.settings.recentDevices)
                      Chip(
                          label: Text(d,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 11))),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: data.settings.recentDevices.isEmpty
                      ? null
                      : () => ref
                          .read(appDataControllerProvider.notifier)
                          .updateSettings(
                              (s) => s.copyWith(recentDevices: const [])),
                  icon: const Icon(Icons.delete_sweep, size: 16),
                  label: const Text('Clear history'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Circular preset swatch with a selection ring/check.
class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.name,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: name,
      child: Material(
        shape: const CircleBorder(),
        color: color,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? scheme.onSurface : scheme.outlineVariant,
                width: selected ? 2.4 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: selected
                ? const Icon(Icons.check, size: 18, color: Colors.white)
                : null,
          ),
        ),
      ),
    );
  }
}
