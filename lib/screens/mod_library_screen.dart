import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/app_data_controller.dart';
import '../controllers/app_icon_controller.dart';
import '../controllers/connection_controller.dart';
import '../core/models/mod_entry.dart';
import '../screens/add_mod_sheet.dart';
import '../screens/injection_screen.dart';

enum _SortMode { alpha, lastUsed, addedAt }

/// Main mod management screen.
class ModLibraryScreen extends ConsumerStatefulWidget {
  const ModLibraryScreen({super.key});

  @override
  ConsumerState<ModLibraryScreen> createState() => _ModLibraryScreenState();
}

class _ModLibraryScreenState extends ConsumerState<ModLibraryScreen> {
  String _search = '';
  _SortMode _sort = _SortMode.lastUsed;
  bool _groupByApp = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybePromptDefaultDevice();
    });
    // Right-clicked a script in Explorer ("Open with Frida Link")? Jump
    // straight into the Add Mod sheet with it pre-filled.
    final launchScript = ref.read(launchScriptProvider.notifier).take();
    if (launchScript != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openAddMod(scriptPath: launchScript);
      });
    }
  }

  /// After a fresh connection, offer to keep the connected device as the
  /// default (auto-connect) one. Skips if it already is the default, or if
  /// the user asked never to be prompted again.
  void _maybePromptDefaultDevice() {
    final address =
        ref.read(connectionControllerProvider).device?.address ?? '';
    if (address.isEmpty) return;
    final settings = ref.read(settingsProvider);
    if (settings.neverAskDefaultDevice) return;
    if (address == settings.defaultDevice) return;
    _promptDefaultDevice(address);
  }

  Future<void> _promptDefaultDevice(String address) async {
    var dontAsk = false;
    final scheme = Theme.of(context).colorScheme;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(Icons.wifi_tethering,
                    size: 22, color: scheme.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              const Expanded(child: Text('Keep as default device?')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Auto-connect to this wireless ADB address every time you '
                'open Frida Link?',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  address,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                ),
              ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  "Don't ask me again",
                  style: TextStyle(fontSize: 13),
                ),
                value: dontAsk,
                onChanged: (v) => setLocal(() => dontAsk = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _applyDefaultChoice(
                    setDefault: false, dontAsk: dontAsk, address: address);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () {
                _applyDefaultChoice(
                    setDefault: true, dontAsk: dontAsk, address: address);
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Yes'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyDefaultChoice({
    required bool setDefault,
    required bool dontAsk,
    required String address,
  }) {
    return ref
        .read(appDataControllerProvider.notifier)
        .updateSettings((s) => s.copyWith(
              defaultDevice: setDefault ? address : s.defaultDevice,
              neverAskDefaultDevice: dontAsk,
            ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mods = ref.watch(modLibraryProvider);
    final settings = ref.watch(settingsProvider);
    final device = ref.watch(connectionControllerProvider).device;

    // Kick off background app-icon fetches for mods missing one (deduped).
    ref.read(appIconControllerProvider.notifier).ensureIcons(mods, device?.serial);

    final bridgeReady = settings.defaultBridgePath.isNotEmpty;
    final filtered = _filterAndSort(mods);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('Mod Library',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
              const Spacer(),
              if (!bridgeReady)
                Tooltip(
                  message:
                      'Set a default frida-il2cpp-bridge.js in Settings to enable adding mods.',
                  child: Icon(Icons.info_outline,
                      size: 16, color: Theme.of(context).colorScheme.tertiary),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: bridgeReady ? () => _openAddMod() : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Mod'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: const InputDecoration(
                    hintText: 'Search by mod name or app…',
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownMenu<_SortMode>(
                width: 150,
                label: const Text('Sort'),
                initialSelection: _sort,
                onSelected: (v) => setState(() => _sort = v ?? _sort),
                dropdownMenuEntries: const [
                  DropdownMenuEntry(value: _SortMode.alpha, label: 'A–Z'),
                  DropdownMenuEntry(
                      value: _SortMode.lastUsed, label: 'Last used'),
                  DropdownMenuEntry(
                      value: _SortMode.addedAt, label: 'Date added'),
                ],
              ),
              const SizedBox(width: 10),
              FilterChip(
                label: const Text('Group by app'),
                selected: _groupByApp,
                onSelected: (v) => setState(() => _groupByApp = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyState(
                  bridgeReady: bridgeReady, onAdd: () => _openAddMod())
              : _buildList(filtered),
        ),
      ],
    );
  }

  List<ModEntry> _filterAndSort(List<ModEntry> mods) {
    final query = _search.toLowerCase();
    final result = mods.where((m) {
      if (query.isEmpty) return true;
      return m.name.toLowerCase().contains(query) ||
          m.appName.toLowerCase().contains(query) ||
          m.bundleId.toLowerCase().contains(query);
    }).toList();

    switch (_sort) {
      case _SortMode.alpha:
        result.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortMode.lastUsed:
        result.sort((a, b) {
          final ta =
              a.lastUsed ?? a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb =
              b.lastUsed ?? b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
        break;
      case _SortMode.addedAt:
        result.sort((a, b) {
          final ta = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final tb = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
        break;
    }
    return result;
  }

  Widget _buildList(List<ModEntry> mods) {
    final icons = ref.watch(appIconControllerProvider);

    if (!_groupByApp) {
      return ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: mods.length,
        itemBuilder: (_, i) => _ModCard(
          mod: mods[i],
          iconPath: _resolveIcon(mods[i], icons),
          onInject: _inject,
          onEdit: _edit,
          onDelete: _delete,
          onDuplicate: _duplicate,
          onRefetchIcon: _refetchIcon,
          onRemoveIcon: _removeIcon,
        ),
      );
    }

    // Group by appName (or bundleId).
    final groups = <String, List<ModEntry>>{};
    for (final m in mods) {
      final key = m.appName.isNotEmpty ? m.appName : m.bundleId;
      groups.putIfAbsent(key, () => []).add(m);
    }
    final keys = groups.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final key in keys) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Icon(Icons.sports_esports,
                    size: 16, color: Theme.of(context).colorScheme.secondary),
                const SizedBox(width: 6),
                Text(key,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(width: 8),
                Text('${groups[key]!.length}',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline)),
                const Divider(height: 1, indent: 8),
              ],
            ),
          ),
          for (final m in groups[key]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ModCard(
                mod: m,
                iconPath: _resolveIcon(m, icons),
                onInject: _inject,
                onEdit: _edit,
                onDelete: _delete,
                onDuplicate: _duplicate,
                onRefetchIcon: _refetchIcon,
                onRemoveIcon: _removeIcon,
              ),
            ),
        ],
      ],
    );
  }

  /// Custom user icon wins, then the fetched app icon, else '' (placeholder).
  String _resolveIcon(ModEntry m, Map<String, String> icons) {
    if (m.iconPath.isNotEmpty && File(m.iconPath).existsSync()) {
      return m.iconPath;
    }
    final fetched = icons[m.bundleId.trim()];
    if (fetched != null && fetched.isNotEmpty && File(fetched).existsSync()) {
      return fetched;
    }
    return '';
  }

  void _refetchIcon(ModEntry mod) {
    final device = ref.read(connectionControllerProvider).device;
    if (device == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Not connected to a headset.')));
      return;
    }
    if (mod.bundleId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This mod has no bundle ID.')));
      return;
    }
    ref
        .read(appIconControllerProvider.notifier)
        .refreshIcon(device.serial, mod.bundleId);
  }

  void _removeIcon(ModEntry mod) {
    ref
        .read(appDataControllerProvider.notifier)
        .patchMod(mod.id, (m) => m.copyWith(iconPath: ''));
    ref.read(appIconServiceProvider).removeModIcon(mod.id);
  }

  void _inject(ModEntry mod) {
    final device = ref.read(connectionControllerProvider).device;
    if (device == null) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InjectionScreen(mod: mod, device: device),
    ));
  }

  void _openAddMod({ModEntry? existing, String? scriptPath}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      builder: (ctx) => AddModSheet(existing: existing, scriptPath: scriptPath),
    );
  }

  void _edit(ModEntry mod) => _openAddMod(existing: mod);

  Future<void> _delete(ModEntry mod) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete mod?'),
        content: Text('Delete "${mod.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(appDataControllerProvider.notifier).removeMod(mod.id);
    }
  }

  void _duplicate(ModEntry mod) {
    final copy = ModEntry(
      id: '${mod.id}-dup-${DateTime.now().millisecondsSinceEpoch}',
      name: '${mod.name} (copy)',
      scriptPath: mod.scriptPath,
      appName: mod.appName,
      bundleId: mod.bundleId,
      bridgeOverridePath: mod.bridgeOverridePath,
      customCommand: mod.customCommand,
      iconPath: mod.iconPath,
      addedAt: DateTime.now(),
    );
    ref.read(appDataControllerProvider.notifier).upsertMod(copy);
  }
}

class _ModCard extends StatelessWidget {
  const _ModCard({
    required this.mod,
    required this.iconPath,
    required this.onInject,
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRefetchIcon,
    required this.onRemoveIcon,
  });

  final ModEntry mod;
  final String iconPath;
  final ValueChanged<ModEntry> onInject;
  final ValueChanged<ModEntry> onEdit;
  final ValueChanged<ModEntry> onDelete;
  final ValueChanged<ModEntry> onDuplicate;
  final ValueChanged<ModEntry> onRefetchIcon;
  final ValueChanged<ModEntry> onRemoveIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fileName = mod.scriptPath.split(RegExp(r'[\\/]')).last;
    final lastUsed = mod.lastUsed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            _AppIcon(iconPath: iconPath, scheme: scheme),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(mod.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                      ),
                      if (mod.customCommand.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        const _Tag(text: 'custom cmd'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [if (mod.appName.isNotEmpty) mod.appName, mod.bundleId]
                        .where((s) => s.isNotEmpty)
                        .join(' · '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      fileName,
                      if (lastUsed != null)
                        'last used ${_friendlyTime(lastUsed)}'
                    ].join('  ·  '),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => onInject(mod),
              child: const Text('Inject',
                  style: TextStyle(fontFamily: 'monospace')),
            ),
            _IconMenu(
              onEdit: () => onEdit(mod),
              onDelete: () => onDelete(mod),
              onDuplicate: () => onDuplicate(mod),
              onRefetchIcon: () => onRefetchIcon(mod),
              onRemoveIcon: () => onRemoveIcon(mod),
            ),
          ],
        ),
      ),
    );
  }

  static String _friendlyTime(DateTime dt) {
    final local = dt.toLocal();
    final now = DateTime.now();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${local.month}/${local.day}';
  }
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.iconPath, required this.scheme});

  final String iconPath;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (iconPath.isNotEmpty && File(iconPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(iconPath),
          width: 38,
          height: 38,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: scheme.secondary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.code_rounded, size: 20, color: scheme.secondary),
      );
}

class _IconMenu extends StatelessWidget {
  const _IconMenu({
    required this.onEdit,
    required this.onDelete,
    required this.onDuplicate,
    required this.onRefetchIcon,
    required this.onRemoveIcon,
  });

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onRefetchIcon;
  final VoidCallback onRemoveIcon;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (v) {
        switch (v) {
          case 'edit':
            onEdit();
          case 'delete':
            onDelete();
          case 'duplicate':
            onDuplicate();
          case 'refetch_icon':
            onRefetchIcon();
          case 'remove_icon':
            onRemoveIcon();
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(
            value: 'refetch_icon',
            child: Text('Fetch app icon from headset')),
        PopupMenuItem(value: 'remove_icon', child: Text('Remove custom icon')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withOpacity(0.35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 9.5, color: scheme.tertiary, fontFamily: 'monospace')),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.bridgeReady, required this.onAdd});

  final bool bridgeReady;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            bridgeReady
                ? 'No mods yet. Add your first script to get started.'
                : 'Set a default bridge file in Settings, then add mods.',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
          const SizedBox(height: 12),
          if (bridgeReady)
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Mod'),
            ),
        ],
      ),
    );
  }
}
