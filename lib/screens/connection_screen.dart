import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/app_data_controller.dart';
import '../controllers/connection_controller.dart';
import '../core/models/app_settings.dart';
import '../core/models/connection.dart';
import '../core/theme.dart';
import '../widgets/window_title_bar.dart';

/// Two-step connection flow.
///
/// * Screen 1 ("Welcome & Connect"): logo, monospace IP/port input with inline
///   validation, recent-device chips, and the Connect action. No checks run
///   here yet.
/// * Screen 2 (pipeline): automatically runs Wireless ADB → Root → frida-server
///   with a shared-axis transition. A modal failure dialog offers Retry or
///   Change device, and once all steps pass the app hands off to the main shell.
class ConnectionScreen extends ConsumerStatefulWidget {
  const ConnectionScreen({super.key});

  @override
  ConsumerState<ConnectionScreen> createState() => _ConnectionScreenState();
}

/// Intro (cold-launch) geometry + timing. The logo is a single 16:9 transparent
/// PNG that rests at a deterministic spot above the welcome fields and is
/// animated entirely by its own transform, so the morph can never drift.
const _logoHb = 100.0; // resting logo height
const _logoWb = _logoHb * 16 / 9; // ~178 wide (16:9 PNG)
const _logoRestTopFactor =
    0.16; // resting logo top as a fraction of viewport height
const _logoGap = 16.0; // gap below the resting logo
const _splashScale = 3.0; // logo scale while centered on cold launch
const _introDuration = Duration(milliseconds: 1150);

/// Timeline (fractions of [_introDuration]).
const _logoMotion = Interval(0.16, 0.56, curve: Curves.easeInOutCubic);
const _subtitleIn = Interval(0.62, 0.84, curve: Curves.easeOutCubic);
const _cardIn = Interval(0.72, 0.95, curve: Curves.easeOutCubic);

class _ConnectionScreenState extends ConsumerState<ConnectionScreen>
    with SingleTickerProviderStateMixin {
  static const _axisDuration = Duration(milliseconds: 380);

  /// Only auto-connect to the default device once per app launch.
  static bool _autoConnectionAttempted = false;

  /// Only play the cold-launch intro once per app lifetime. Navigating back
  /// to the welcome form reuses the same State, so no replay happens there.
  static bool _introPlayed = false;

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _address = TextEditingController();
  final TextEditingController _port = TextEditingController(text: '5555');

  /// Whether this mount owns a running intro animation.
  late final bool _playIntro;
  AnimationController? _introController;

  /// True once this mount's intro has finished, so the (invisible) welcome
  /// fields stop being pointer-blocked.
  bool _introDone = false;

  /// Secret debug bypass (Konami code): opens the main shell without a device.
  static const List<LogicalKeyboardKey> _debugCode = [
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.enter,
  ];
  int _debugCodeIndex = 0;

  List<AdbDeviceInfo> _discovered = [];
  bool _scanning = false;
  bool _connecting = false;
  bool _showPipeline = false;
  bool _dialogOpen = false;

  /// True while `_connect` was kicked off by the saved default device rather
  /// than the Connect button. Drives the "automatically connecting" banner.
  bool _autoConnecting = false;

  /// Whether the settings-received listener has already scheduled the default
  /// device auto-connect for this mount.
  bool _autoConnectScheduled = false;

  /// Bumped on every connect/cancel so a stale in-flight connect never clears
  /// the busy flag of a newer one.
  int _connectSeq = 0;

  @override
  void initState() {
    super.initState();
    // Cold-launch intro: the welcome logo morphs from center + large to its
    // resting spot above the fields, which fade in afterward.
    _playIntro = !_introPlayed;
    if (_playIntro) {
      _introController = AnimationController(
        vsync: this,
        duration: _introDuration,
      )..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _introPlayed = true;
            if (mounted) setState(() => _introDone = true);
          }
        });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _playIntro) _introController!.forward();
      });
    }
    _debugCodeIndex = 0;
    HardwareKeyboard.instance.addHandler(_onDebugKey);
    _refreshDevices();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onDebugKey);
    _address.dispose();
    _port.dispose();
    _introController?.dispose();
    super.dispose();
  }

  /// Watches for the Konami-style debug code (arrows + Enter). When it
  /// completes, jumps straight into the main shell without a device.
  bool _onDebugKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    if (key == _debugCode[_debugCodeIndex]) {
      _debugCodeIndex++;
      if (_debugCodeIndex == _debugCode.length) {
        _debugCodeIndex = 0;
        return _activateDebugBypass();
      }
    } else if (key != _debugCode[0]) {
      // Wrong key breaks the streak.
      _debugCodeIndex = 0;
    }
    return false;
  }

  /// Returns true when the bypass was activated (key was consumed).
  bool _activateDebugBypass() {
    if (!mounted || _connecting || _showPipeline) return false;
    ref.read(connectionControllerProvider.notifier).activateDebugBypass();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Debug mode — no device connected.'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
    ));
    return true;
  }

  String get _hostPort {
    final host = _address.text.trim();
    final port = _port.text.trim().isEmpty ? '5555' : _port.text.trim();
    return '$host:$port';
  }

  /// Pops a recent `ip:port` (or bare address) into the input fields.
  void _applyAddress(String device) {
    final parts = device.split(':');
    if (parts.length == 2) {
      _address.text = parts[0];
      _port.text = parts[1];
    } else if (parts.isNotEmpty) {
      _address.text = parts[0];
    }
    _inputChanged();
  }

  Future<void> _refreshDevices() async {
    setState(() => _scanning = true);
    final list =
        await ref.read(connectionControllerProvider.notifier).scanDevices();
    if (mounted) {
      setState(() {
        _discovered = list;
        _scanning = false;
      });
    }
  }

  /// Pre-fill the fields and, once per launch, auto-connect to the saved
  /// default device.
  void _maybeAutoConnect(AppSettings settings) {
    if (settings.defaultDevice.isNotEmpty && !_autoConnectionAttempted) {
      _applyAddress(settings.defaultDevice);
      if (_autoConnectionAttempted) return;
      _autoConnectionAttempted = true;
      // Let the form register itself so `_connect`'s validation sees the
      // pre-filled fields.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_connecting && !_showPipeline) _autoConnect();
      });
    } else if (settings.recentDevices.isNotEmpty &&
        _address.text.trim().isEmpty) {
      _applyAddress(settings.recentDevices.first);
    }
  }

  /// Kicks off `_connect` for the default device, marking it as automatic so
  /// the UI can say "Automatically connecting to…".
  void _autoConnect() {
    _autoConnecting = true;
    _connect();
  }

  /// Validates the form, records the address, then moves to the pipeline.
  Future<void> _connect() async {
    if (_connecting) return;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _autoConnecting = false;
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();

    final address = _hostPort;
    final seq = ++_connectSeq;
    setState(() {
      _connecting = true;
      _showPipeline = true;
    });
    // Remember this address so it can be prefilled on next launch.
    final data = ref.read(appDataControllerProvider.notifier);
    await data.updateSettings((s) => s.withRecentDevice(address));

    await ref.read(connectionControllerProvider.notifier).connectFlow(address);
    if (mounted && seq == _connectSeq) setState(() => _connecting = false);
  }

  /// Back to the welcome form. Aborts any background flow so the Connect
  /// button is immediately usable again.
  void _goToWelcome() {
    _connectSeq++;
    _autoConnecting = false;
    ref.read(connectionControllerProvider.notifier).cancel();
    setState(() {
      _connecting = false;
      _showPipeline = false;
    });
  }

  void _retry(int index) {
    ref.read(connectionControllerProvider.notifier).retryFrom(index, _hostPort);
  }

  /// Re-evaluates the Connect button's enabled state as the fields change.
  void _inputChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final cs = ref.watch(connectionControllerProvider);
    final settings = ref.watch(settingsProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen<AppSettings>(settingsProvider, (prev, next) {
      // Settings load asynchronously, so on a cold boot `defaultDevice` is
      // empty when initState runs. When it finally arrives, carry out the
      // auto-connect that was waiting for it.
      if (mounted && !_autoConnectScheduled) {
        _autoConnectScheduled = true;
        _maybeAutoConnect(next);
      }
    });

    ref.listen(connectionControllerProvider, (prev, next) {
      if (!_showPipeline || _dialogOpen || !mounted) return;
      for (var i = 0; i < next.steps.length; i++) {
        final step = next.steps[i];
        final wasFailed = prev != null &&
            prev.steps.length > i &&
            prev.steps[i].status == CheckStatus.failed;
        if (step.status == CheckStatus.failed && !wasFailed) {
          _openFailureDialog(i);
          break;
        }
      }
    });

    // The intro controller (or a completed stand-in) drives both the shared
    // logo's placement and the staggered content reveal inside the welcome view.
    final intro = _introController ?? const AlwaysStoppedAnimation<double>(1.0);
    final switcherChild = _showPipeline
        ? _PipelineView(
            key: const ValueKey('pipeline'),
            steps: cs.steps,
            address: _hostPort,
            autoConnecting: _autoConnecting,
            onChange: _goToWelcome,
          )
        : _WelcomeView(
            key: const ValueKey('welcome'),
            formKey: _formKey,
            address: _address,
            port: _port,
            intro: intro,
            connecting: _connecting,
            scanning: _scanning,
            recentDevices: settings.recentDevices,
            discovered: _discovered,
            onConnect: _connect,
            onScan: _refreshDevices,
            onRecent: _applyAddress,
            onCancel: _goToWelcome,
            onInputChanged: _inputChanged,
          );

    return Scaffold(
      backgroundColor: scheme.surface,
      body: Column(
        children: [
          const DraggableTitleBar(title: 'Frida Link'),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: _axisDuration,
              reverseDuration: _axisDuration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _screenTransition,
              child: KeyedSubtree(
                // Keep the switcher able to tell the two screens apart so the
                // content cards cross-fade (the logo lives inside the welcome
                // content, not in the switcher's key path).
                key: ValueKey(_showPipeline ? 'pipeline' : 'welcome'),
                child: _buildHome(switcherChild),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Blocks input while the cold-launch intro is hiding the welcome fields, so a
  /// stray tap during the animation can't land on an invisible control. Once the
  /// intro completes everything is interactive again.
  Widget _buildHome(Widget content) {
    return IgnorePointer(
      ignoring: _playIntro && !_introDone,
      child: content,
    );
  }

  /// Shared-axis style transition: slight slide + scale with ease-in-out.
  Widget _screenTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1.0).animate(curved),
          child: child,
        ),
      ),
    );
  }

  /// Modal failure dialog for a failed pipeline step. The failed row stays
  /// visibly red behind the dialog.
  void _openFailureDialog(int index) {
    _dialogOpen = true;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final detail = ref.read(connectionControllerProvider).steps[index].detail;

    final (String title, String hint) = switch (index) {
      0 => (
          "Couldn't Connect",
          'Check that the headset is on the same network and `adb` is installed.',
        ),
      1 => (
          'Not Rooted',
          'The device does not appear to be rooted. Frida Link requires root '
              'access and cannot continue until the device is rooted.',
        ),
      _ => detail.contains('not found')
          ? (
              'frida-server Not Found',
              'frida-server is missing on the headset. Install it at '
                  '/data/local/tmp/frida-server, then retry.'
            )
          : (
              'frida-server Not Running',
              'frida-server is present but could not be started. Try launching '
                  'it manually on the headset.'
            ),
    };

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.errorContainer,
              ),
              child: Icon(
                Icons.error_outline,
                size: 22,
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title)),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 280),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${index + 1} did not pass.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                if (detail.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      detail,
                      style: Mono.code(theme.textTheme)
                          .copyWith(color: scheme.error),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  hint,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _dialogOpen = false;
              _goToWelcome();
            },
            child: const Text('Change device'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _dialogOpen = false;
              _retry(index);
            },
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    ).whenComplete(() => _dialogOpen = false);
  }
}

/// Screen 1 — the single logo (in place of the old title text) + subtitle +
/// input card. Nothing is checked here.
///
/// The logo is `Positioned` at a deterministic resting spot (a fraction of the
/// viewport height from the top) and on cold launch it is morphed — through its
/// own translate + scale — from window-center + large to that exact spot; the
/// subtitle + card fade in after. One widget, no overlay/hand-off, so there is
/// nothing that can "snap".
class _WelcomeView extends StatelessWidget {
  const _WelcomeView({
    super.key,
    required this.formKey,
    required this.address,
    required this.port,
    required this.intro,
    required this.connecting,
    required this.scanning,
    required this.recentDevices,
    required this.discovered,
    required this.onConnect,
    required this.onScan,
    required this.onRecent,
    required this.onCancel,
    required this.onInputChanged,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController address;
  final TextEditingController port;
  final Animation<double> intro;
  final bool connecting;
  final bool scanning;
  final List<String> recentDevices;
  final List<AdbDeviceInfo> discovered;
  final VoidCallback onConnect;
  final VoidCallback onScan;
  final ValueChanged<String> onRecent;
  final VoidCallback onCancel;
  final VoidCallback onInputChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hostEmpty = address.text.trim().isEmpty;

    // Staggered reveal below the logo: subtitle first, then the form card.
    final subtitleIn = CurvedAnimation(parent: intro, curve: _subtitleIn);
    final cardIn = CurvedAnimation(parent: intro, curve: _cardIn);
    final motion = CurvedAnimation(parent: intro, curve: _logoMotion);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        // Deterministic resting spot — independent of the fields' height, fonts
        // or scroll position, so the logo can never shift once the intro ends.
        final restTop = h * _logoRestTopFactor;
        final restLeft = (w - _logoWb) / 2;
        final splashOffset = Offset(w / 2, h / 2) -
            Offset(restLeft + _logoWb / 2, restTop + _logoHb / 2);

        return Stack(
          children: [
            Positioned(
              top: restTop,
              left: restLeft,
              child: AnimatedBuilder(
                animation: intro,
                builder: (context, _) {
                  final f = motion.value;
                  return Transform.translate(
                    offset: Offset(
                      splashOffset.dx * (1 - f),
                      splashOffset.dy * (1 - f),
                    ),
                    child: Transform.scale(
                      scale: _splashScale + (1 - _splashScale) * f,
                      child: const _Logo(height: _logoHb),
                    ),
                  );
                },
              ),
            ),
            // Everything below the resting logo, scrollable if it doesn't fit.
            Positioned.fill(
              child: Column(
                children: [
                  SizedBox(height: restTop + _logoHb + _logoGap),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Form(
                          key: formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FadeTransition(
                                opacity: subtitleIn,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.06),
                                    end: Offset.zero,
                                  ).animate(subtitleIn),
                                  child: Text(
                                    'Connect a rooted Meta Quest headset to continue.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 26),
                              FadeTransition(
                                opacity: cardIn,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.06),
                                    end: Offset.zero,
                                  ).animate(cardIn),
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Wireless ADB connection',
                                            style: theme.textTheme.titleMedium,
                                          ),
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 3,
                                                child: TextFormField(
                                                  controller: address,
                                                  style: const TextStyle(
                                                      fontFamily: 'monospace'),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .allow(
                                                      RegExp(r'[\d.]'),
                                                    ),
                                                  ],
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'IP address',
                                                    hintText: '192.168.1.50',
                                                  ),
                                                  validator: _validateIp,
                                                  onChanged: (_) =>
                                                      onInputChanged(),
                                                  onFieldSubmitted: (_) =>
                                                      onConnect(),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                flex: 1,
                                                child: TextFormField(
                                                  controller: port,
                                                  style: const TextStyle(
                                                      fontFamily: 'monospace'),
                                                  keyboardType:
                                                      TextInputType.number,
                                                  inputFormatters: [
                                                    FilteringTextInputFormatter
                                                        .digitsOnly,
                                                  ],
                                                  decoration:
                                                      const InputDecoration(
                                                    labelText: 'Port',
                                                  ),
                                                  validator: _validatePort,
                                                  onChanged: (_) =>
                                                      onInputChanged(),
                                                  onFieldSubmitted: (_) =>
                                                      onConnect(),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 8,
                                            children: [
                                              if (connecting)
                                                FilledButton.icon(
                                                  onPressed: onCancel,
                                                  icon: const Icon(Icons.close,
                                                      size: 18),
                                                  label: const Text('Cancel'),
                                                )
                                              else
                                                FilledButton.icon(
                                                  onPressed: hostEmpty
                                                      ? null
                                                      : onConnect,
                                                  icon: const Icon(Icons.link,
                                                      size: 18),
                                                  label: const Text('Connect'),
                                                ),
                                              OutlinedButton.icon(
                                                onPressed:
                                                    scanning || connecting
                                                        ? null
                                                        : onScan,
                                                icon: const Icon(Icons.dns,
                                                    size: 18),
                                                label: Text(scanning
                                                    ? 'Scanning…'
                                                    : 'Scan / Refresh'),
                                              ),
                                            ],
                                          ),
                                          if (recentDevices.isNotEmpty) ...[
                                            const SizedBox(height: 10),
                                            Text(
                                              'Recent devices',
                                              style: theme.textTheme.labelMedium
                                                  ?.copyWith(
                                                      color: scheme
                                                          .onSurfaceVariant),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                for (final d in recentDevices)
                                                  ActionChip(
                                                    avatar: const Icon(
                                                        Icons.history,
                                                        size: 14),
                                                    label: Text(
                                                      d,
                                                      style: const TextStyle(
                                                          fontFamily:
                                                              'monospace',
                                                          fontSize: 11),
                                                    ),
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                    onPressed: () =>
                                                        onRecent(d),
                                                  ),
                                              ],
                                            ),
                                          ],
                                          if (discovered.isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            _DiscoveredDevice(
                                              devices: discovered,
                                              onTap: onRecent,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The brand mark. It sits at the top of the welcome content above the fields,
/// doubling as the app's splash + title on cold launch.
class _Logo extends StatelessWidget {
  const _Logo({this.height = _logoHb});

  final double height;

  @override
  Widget build(BuildContext context) {
    // 16:9 transparent PNG.
    return SizedBox(
      width: height * 16 / 9,
      height: height,
      child: Image.asset(
        'assets/frida_link_logo.png',
        fit: BoxFit.contain,
      ),
    );
  }
}

/// Screen 2 — runs the pipeline automatically for the target address.
class _PipelineView extends StatelessWidget {
  const _PipelineView({
    super.key,
    required this.steps,
    required this.address,
    required this.autoConnecting,
    required this.onChange,
  });

  final List<ConnectionStep> steps;
  final String address;
  final bool autoConnecting;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (autoConnecting) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_tethering,
                          size: 16, color: scheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Automatically connecting to $address…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onTertiaryContainer,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Connection pipeline',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          address,
                          textAlign: TextAlign.center,
                          style: Mono.small(theme.textTheme)
                              .copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: onChange,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < steps.length; i++) ...[
                        if (i > 0) const Divider(),
                        _StepTile(step: steps[i], index: i),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single pipeline step: animated status indicator + title/badge + detail.
class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.step,
    required this.index,
  });

  final ConnectionStep step;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = step.status == CheckStatus.failed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusIndicator(status: step.status),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '${index + 1}. ${step.title}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (step.status != CheckStatus.pending) ...[
                      const SizedBox(width: 8),
                      _StatusChip(status: step.status),
                    ],
                  ],
                ),
                if (step.detail.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    step.detail,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: failed ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Leading status circle — animates between pending / checking / result.
class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 32,
      height: 32,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: switch (status) {
          CheckStatus.pending => Container(
              key: const ValueKey('pending'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outlineVariant, width: 2),
              ),
            ),
          CheckStatus.checking => Container(
              key: const ValueKey('checking'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.surfaceContainerHigh,
              ),
              padding: const EdgeInsets.all(7),
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: scheme.primary,
              ),
            ),
          CheckStatus.passed => Container(
              key: const ValueKey('passed'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiaryContainer,
              ),
              child: Icon(Icons.check,
                  size: 18, color: scheme.onTertiaryContainer),
            ),
          CheckStatus.failed => Container(
              key: const ValueKey('failed'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.errorContainer,
              ),
              child:
                  Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
            ),
        },
      ),
    );
  }
}

/// Small M3-style status pill ("Passed" / "Checking…" / "Failed").
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final CheckStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg, String label) = switch (status) {
      CheckStatus.passed => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          'Passed'
        ),
      CheckStatus.failed => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          'Failed'
        ),
      CheckStatus.checking => (
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
          'Checking…'
        ),
      CheckStatus.pending => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          'Waiting'
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

/// Small label for the discovered-devices list.
class _DiscoveredDevice extends StatelessWidget {
  const _DiscoveredDevice({required this.devices, required this.onTap});

  final List<AdbDeviceInfo> devices;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(
          'Discovered devices',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        for (final d in devices.take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              d.isReady ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: d.isReady ? scheme.primary : scheme.outline,
            ),
            title: Text(
              d.serial,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            subtitle: Text(
              d.isReady ? 'ready' : d.state,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            trailing: d.isReady
                ? TextButton(
                    onPressed: () =>
                        onTap(d.address.isNotEmpty ? d.address : d.serial),
                    child: const Text(
                      'Select',
                      style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  )
                : null,
          ),
      ],
    );
  }
}

String? _validateIp(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter the headset IP address';
  if (!RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(v)) {
    return 'e.g. 192.168.1.50';
  }
  return null;
}

String? _validatePort(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return null; // falls back to 5555
  final p = int.tryParse(v);
  if (p == null || p < 1 || p > 65535) return '1 – 65535';
  return null;
}
