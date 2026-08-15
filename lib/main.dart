import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'controllers/app_data_controller.dart';
import 'controllers/connection_controller.dart';
import 'core/theme.dart';
import 'screens/connection_screen.dart';
import 'screens/home_shell.dart';

/// Picks the script path (if any) passed as a launch argument, e.g. when the
/// user right-clicked a `.ts`/`.js` and chose "Open with Frida Link".
String? _extractLaunchScript() {
  final args = Platform.executableArguments;
  for (final raw in args) {
    final arg = raw.trim();
    if (arg.isEmpty || arg.startsWith('-')) continue;
    final file = File(arg);
    final ext = arg.split('.').last.toLowerCase();
    if (file.existsSync() && (ext == 'ts' || ext == 'js')) return arg;
  }
  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1200, 760),
    minimumSize: Size(940, 600),
    center: true,
    title: 'Frida Link',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final launchScript = _extractLaunchScript();
  runApp(ProviderScope(
    overrides: [
      if (launchScript != null)
        launchScriptProvider.overrideWith((ref) {
          final n = LaunchScriptNotifier();
          n.set(launchScript);
          return n;
        }),
    ],
    child: const FridaLinkApp(),
  ));
}

class FridaLinkApp extends ConsumerWidget {
  const FridaLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = buildFridaTheme(
        dark: settings.darkMode,
        accentSeed: settings.accentColor,
        material2: settings.useMaterial2);

    return MaterialApp(
      title: 'Frida Link',
      debugShowCheckedModeBanner: false,
      theme: theme,
      builder: (context, child) => VirtualWindowFrameInit()(context, child),
      home: const _RootRouter(),
    );
  }
}

/// Shows the connection screen until the pipeline passes, then the main shell.
class _RootRouter extends ConsumerStatefulWidget {
  const _RootRouter();

  @override
  ConsumerState<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends ConsumerState<_RootRouter>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-validate root + frida-server when the app returns to foreground.
    if (state == AppLifecycleState.resumed &&
        ref.read(connectionControllerProvider).isConnected) {
      ref.read(connectionControllerProvider.notifier).revalidate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(connectionControllerProvider);
    if (state.isConnected) {
      return const HomeShell();
    }
    return const ConnectionScreen();
  }
}
