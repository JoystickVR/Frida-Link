import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/connection_controller.dart';
import '../widgets/window_title_bar.dart';
import 'mod_library_screen.dart';
import 'settings_screen.dart';

/// Main post-connection shell: sidebar nav + a connected-device badge.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _labels = <(IconData, String)>[
    (Icons.widgets_outlined, 'Mod Library'),
    (Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final conn = ref.watch(connectionControllerProvider);
    final device = conn.device;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          const DraggableTitleBar(title: 'Frida Link'),
          const Divider(height: 1),
          Expanded(
            child: Row(
              children: [
                NavigationRail(
                  backgroundColor: scheme.surfaceContainerLowest,
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  groupAlignment: -1,
                  destinations: [
                    for (final (icon, label) in _labels)
                      NavigationRailDestination(
                        icon: Icon(icon),
                        label: Text(label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: const [
                      ModLibraryScreen(),
                      SettingsScreen(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: scheme.surfaceContainerLowest,
            child: Row(
              children: [
                Icon(Icons.circle,
                    size: 8,
                    color: device != null
                        ? scheme.primary
                        : conn.isDebugBypass
                            ? scheme.tertiary
                            : scheme.error),
                const SizedBox(width: 6),
                Text(
                  device != null
                      ? 'Connected: ${device.address}'
                      : conn.isDebugBypass
                          ? 'Debug mode — no device connected'
                          : 'Disconnected',
                  style: TextStyle(
                      fontSize: 11,
                      color: device != null
                          ? scheme.onSurface
                          : conn.isDebugBypass
                              ? scheme.tertiary
                              : scheme.error,
                      fontFamily: 'monospace'),
                ),
                const Spacer(),
                if (device != null)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: () => ref
                        .read(connectionControllerProvider.notifier)
                        .disconnect(),
                    child: const Text('Disconnect',
                        style: TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}