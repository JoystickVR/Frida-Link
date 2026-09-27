import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../controllers/app_data_controller.dart';
import '../controllers/connection_controller.dart';
import '../core/models/connection.dart';
import '../widgets/accent_swatch.dart';
import '../widgets/color_picker.dart';
import '../widgets/window_title_bar.dart';

enum _Step { welcome, appearance, root, adb }

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const Duration _introDuration = Duration(milliseconds: 2400);
  static const int _defaultAccent = 0xFF0081FB;

  late final AnimationController _intro;
  late final CurvedAnimation _logoFade;
  late final CurvedAnimation _logoMove;
  late final CurvedAnimation _copyIn;
  late final CurvedAnimation _buttonIn;
  late final TapGestureRecognizer _apkLink;
  late final TextEditingController _host;
  late final TextEditingController _port;

  _Step _step = _Step.welcome;
  bool _introDone = false;
  bool _connecting = false;
  bool _failed = false;
  String _failureDetail = '';
  String? _hostError;
  String? _portError;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(settingsProvider).defaultDevice;
    final parts = saved.split(':');
    _host = TextEditingController(text: parts.isEmpty ? '' : parts.first);
    _port = TextEditingController(text: parts.length > 1 ? parts[1] : '5555');
    _apkLink = TapGestureRecognizer()..onTap = _openSingularityApk;

    _intro = AnimationController(vsync: this, duration: _introDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted) {
          setState(() => _introDone = true);
        }
      });
    _logoFade = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.0, 0.28, curve: Curves.easeOut),
    );
    _logoMove = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.4, 0.72, curve: Curves.easeInOutCubic),
    );
    _copyIn = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.66, 0.9, curve: Curves.easeOutCubic),
    );
    _buttonIn = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.84, 1.0, curve: Curves.easeOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startIntroWhenVisible();
    });
  }

  Future<void> _startIntroWhenVisible() async {
    while (mounted && !await windowManager.isVisible()) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (mounted) _intro.forward();
  }

  Future<void> _openSingularityApk() async {
    const url =
        'https://github.com/Lumince/singularity/releases/latest/download/Singularity.apk';
    if (Platform.isWindows) {
      await Process.start('cmd.exe', ['/c', 'start', '', url]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [url]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [url]);
    }
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _apkLink.dispose();
    _logoFade.dispose();
    _logoMove.dispose();
    _copyIn.dispose();
    _buttonIn.dispose();
    _intro.dispose();
    super.dispose();
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  void _goTo(_Step step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _step = step);
  }

  void _next() {
    final index = _step.index + 1;
    if (index < _Step.values.length) _goTo(_Step.values[index]);
  }

  void _back() {
    final index = _step.index - 1;
    if (index >= 0) _goTo(_Step.values[index]);
  }

  Future<void> _updateAppearance({int? accent, bool? dark}) async {
    await ref.read(appDataControllerProvider.notifier).updateSettings(
          (settings) => settings.copyWith(
            accentColor: accent ?? settings.accentColor,
            darkMode: dark ?? settings.darkMode,
          ),
        );
  }

  Future<void> _useDefaults() async {
    await _updateAppearance(accent: _defaultAccent, dark: true);
    if (mounted) _next();
  }

  Future<void> _pickCustomAccent(int current) async {
    final picked = await AccentColorPickerDialog.show(context, Color(current));
    if (picked != null) {
      await _updateAppearance(accent: picked.toARGB32());
    }
  }

  Future<void> _showAdbHelp() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        final code = TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        );
        return AlertDialog(
          title: const Text('Find your ADB details'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('From Singularity on the headset:'),
                const SizedBox(height: 8),
                const Text('1. Open Singularity.'),
                const SizedBox(height: 4),
                const Text('2. Tap "Setup Wireless ADB".'),
                const SizedBox(height: 4),
                const Text(
                  '3. Singularity shows an address such as '
                  '192.168.1.50:5555. Enter the IP and port above.',
                ),
                const SizedBox(height: 14),
                const Text('If Singularity does not show it:'),
                const SizedBox(height: 8),
                const Text(
                  'Connect the headset over USB, then run these commands in '
                  'a terminal on your PC:',
                ),
                const SizedBox(height: 8),
                const SelectableText('adb shell ip route',
                    style: TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 4),
                const Text('Use the address after src, then run:'),
                const SizedBox(height: 8),
                const SelectableText('adb tcpip 5555',
                    style: TextStyle(fontFamily: 'monospace')),
                const SizedBox(height: 14),
                Text(
                  'The headset and your PC must be on the same network. '
                  'Port 5555 is the usual wireless ADB port.',
                  style: code,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        );
      },
    );
  }

  String? _pipelineFailureDetail(List<ConnectionStep> steps) {
    for (final step in steps.reversed) {
      if (step.status == CheckStatus.failed) return step.detail;
    }
    return 'Frida Link could not finish the connection checks.';
  }

  Future<void> _connect() async {
    final host = _host.text.trim();
    final port = _port.text.trim();
    final hostValid = isValidIpv4Address(host);
    final portValid = isValidPortNumber(port);
    setState(() {
      _hostError = hostValid ? null : 'Enter a valid IPv4 address.';
      _portError = portValid ? null : 'Enter a port from 1 to 65535.';
    });
    if (!hostValid || !portValid) return;

    final address = buildWirelessAddress(host, port);
    setState(() {
      _connecting = true;
      _failed = false;
      _failureDetail = '';
    });
    await ref.read(appDataControllerProvider.notifier).updateSettings(
          (settings) => settings.withRecentDevice(address).copyWith(
                defaultDevice: address,
                neverAskDefaultDevice: true,
              ),
        );
    if (!mounted) return;
    final device = await ref
        .read(connectionControllerProvider.notifier)
        .connectFlow(address);
    if (!mounted) return;
    if (device != null) {
      await _complete();
      return;
    }
    final steps = ref.read(connectionControllerProvider).steps;
    setState(() {
      _connecting = false;
      _failed = true;
      _failureDetail = _pipelineFailureDetail(steps) ?? '';
    });
  }

  Future<void> _skipConnection() async {
    ref.read(connectionControllerProvider.notifier).cancel();
    await _complete();
  }

  Future<void> _complete() async {
    await ref.read(appDataControllerProvider.notifier).updateSettings(
        (settings) => settings.copyWith(onboardingCompleted: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const DraggableTitleBar(title: 'Frida Link'),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.06, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: _buildStep(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _Step.welcome:
        return _buildWelcome();
      case _Step.appearance:
        return _buildAppearance();
      case _Step.root:
        return _buildRoot();
      case _Step.adb:
        return _buildAdb();
    }
  }

  Widget _buildWelcome() {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !_introDone,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: _intro,
            builder: (context, child) {
              final width = constraints.maxWidth;
              final height = constraints.maxHeight;
              final logoWidth = _lerp(
                math.min(620.0, width * 0.62),
                96,
                _logoMove.value,
              );
              final logoHeight = logoWidth * 9 / 16;
              final logoX =
                  _lerp(width / 2, 20 + logoWidth / 2, _logoMove.value);
              final logoY =
                  _lerp(height * 0.34, 8 + logoHeight / 2, _logoMove.value);
              final copyWidth = math.min(520.0, width - 128).toDouble();
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 14,
                    right: 24,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'Step 1 of 4',
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.outline,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: logoX - logoWidth / 2,
                    top: logoY - logoHeight / 2,
                    width: logoWidth,
                    height: logoHeight,
                    child: Opacity(
                      opacity: _logoFade.value,
                      child: Image.asset(
                        'assets/frida_link_logo.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 64,
                    top: height * 0.38,
                    width: copyWidth,
                    child: Opacity(
                      opacity: _copyIn.value,
                      child: Transform.translate(
                        offset: Offset(-36 * (1 - _copyIn.value), 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 3,
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Welcome to Frida Link',
                              style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Connect your rooted Meta Quest, manage your mods, and '
                              'inject Frida scripts over wireless ADB.',
                              style: TextStyle(
                                fontSize: 14.5,
                                height: 1.45,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 64,
                    top: height * 0.6,
                    child: Opacity(
                      opacity: _buttonIn.value,
                      child: FilledButton.icon(
                        onPressed: _next,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: const Text('Continue'),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildAppearance() {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    return _StepFrame(
      step: _Step.appearance,
      title: 'Make it yours',
      subtitle:
          'Pick a theme and accent color. You can change both later in Settings.',
      sections: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.dark_mode, size: 16),
                      label: Text('Dark'),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.light_mode, size: 16),
                      label: Text('Light'),
                    ),
                  ],
                  selected: {settings.darkMode},
                  onSelectionChanged: (selection) =>
                      _updateAppearance(dark: selection.first),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Accent color',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, argb) in accentPresets)
                      AccentSwatch(
                        name: name,
                        color: Color(argb),
                        selected: settings.accentColor == argb,
                        onTap: () => _updateAppearance(accent: argb),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _pickCustomAccent(settings.accentColor),
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
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
      actions: [
        TextButton(
          onPressed: _useDefaults,
          child: const Text('Skip — use default blue + dark'),
        ),
        FilledButton(
          onPressed: _next,
          child: const Text('Continue'),
        ),
      ],
    );
  }

  Widget _buildRoot() {
    final scheme = Theme.of(context).colorScheme;
    const steps = [
      (
        'Enable Developer Mode',
        'Turn on Developer Mode in the Meta Horizon mobile app, then connect '
            'the headset over USB and enable USB debugging.',
      ),
      (
        'Install Singularity',
        'Download the latest Singularity APK and sideload it with the -g flag.',
      ),
      (
        'Set up wireless ADB',
        'Open Singularity on the headset and tap "Setup Wireless ADB".',
      ),
      (
        'Root now',
        'Tap "Root Now". If it stops and becomes available again, tap it a '
            'second time. Wait for the soft reboot to finish.',
      ),
      (
        'Grant root',
        'Confirm Singularity-Magisk appears in Unknown Sources, open it, grant '
            'Singularity root in the Super User tab, then reopen Singularity.',
      ),
    ];
    return _StepFrame(
      step: _Step.root,
      title: 'Root your headset with Singularity',
      subtitle:
          'Frida Link needs root access to install and manage frida-server.',
      sections: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primaryContainer,
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              steps[i].$1,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 3),
                            if (i == 1)
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    height: 1.45,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                  children: [
                                    const TextSpan(
                                        text: 'Download the latest '),
                                    TextSpan(
                                      text: 'Singularity APK',
                                      style: TextStyle(
                                        color: scheme.primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor: scheme.primary,
                                      ),
                                      recognizer: _apkLink,
                                    ),
                                    const TextSpan(
                                      text:
                                          ' and sideload it with the -g flag.',
                                    ),
                                  ],
                                ),
                              )
                            else
                              Text(
                                steps[i].$2,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.45,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (i == 1) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const SelectableText(
                        'adb install -g Singularity.apk',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                  if (i != steps.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
      actions: [
        TextButton(
          onPressed: _next,
          child: const Text('My headset is already rooted'),
        ),
        FilledButton(
          onPressed: _next,
          child: const Text('I finished rooting — continue'),
        ),
      ],
    );
  }

  Widget _buildAdb() {
    final scheme = Theme.of(context).colorScheme;
    final connection = ref.watch(connectionControllerProvider);
    final steps = connection.steps.isEmpty
        ? ConnectionState.initialSteps()
        : connection.steps;
    return _StepFrame(
      step: _Step.adb,
      title: 'Connect over wireless ADB',
      subtitle:
          'Enter the address from Singularity, then Frida Link runs the same '
          'wireless ADB, root, and frida-server checks it uses every day.',
      sections: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _host,
                        enabled: !_connecting,
                        onSubmitted: (_) => _connect(),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'ADB IP address',
                          hintText: '192.168.1.50',
                          errorText: _hostError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _port,
                        enabled: !_connecting,
                        onSubmitted: (_) => _connect(),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Port',
                          hintText: '5555',
                          errorText: _portError,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _connecting ? null : _showAdbHelp,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: scheme.primary,
                  ),
                  icon: const Icon(Icons.help_outline, size: 15),
                  label: const Text('Where do I find this in Singularity?'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _connecting ? null : _connect,
                  icon: _connecting
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: Text(_connecting ? 'Running checks…' : 'Run checks'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Connection checks',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < steps.length; i++) ...[
                  _CheckRow(index: i + 1, step: steps[i]),
                  if (i != steps.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
        if (_failed) ...[
          const SizedBox(height: 12),
          Card(
            color: scheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Checks did not pass',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _failureDetail,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      height: 1.45,
                      color: scheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: _connect,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
      actions: [
        TextButton(onPressed: _back, child: const Text('Back')),
        TextButton(
          onPressed: _connecting ? null : _skipConnection,
          child: const Text('Skip anyway'),
        ),
      ],
    );
  }
}

class _StepFrame extends StatelessWidget {
  const _StepFrame({
    required this.step,
    required this.title,
    required this.subtitle,
    required this.sections,
    required this.actions,
  });

  final _Step step;
  final String title;
  final String subtitle;
  final List<Widget> sections;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 92,
                    height: 30,
                    child: Image.asset(
                      'assets/frida_link_logo.png',
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Step ${step.index + 1} of 4',
                    style: TextStyle(fontSize: 11, color: scheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (step.index + 1) / 4,
                  minHeight: 3,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ...sections,
              const SizedBox(height: 20),
              Row(
                children: [
                  ...actions.take(1),
                  const Spacer(),
                  ...actions.skip(1),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.index, required this.step});

  final int index;
  final ConnectionStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, background, foreground) = switch (step.status) {
      CheckStatus.pending => (
          Icons.circle_outlined,
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
      CheckStatus.checking => (
          Icons.circle,
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      CheckStatus.passed => (
          Icons.check,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      CheckStatus.failed => (
          Icons.close,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: background),
          child: Icon(icon, size: 15, color: foreground),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$index. ${step.title}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              if (step.detail.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  step.detail,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.4,
                    color: step.status == CheckStatus.failed
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
