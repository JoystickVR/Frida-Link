/// Persistent application settings.
class AppSettings {
  const AppSettings({
    this.adbPath = '',
    this.defaultBridgePath = '',
    this.defaultCommandTemplate = _defaultTemplate,
    this.bundleIdTemplate = _defaultBundleTemplate,
    this.darkMode = true,
    this.recentDevices = const <String>[],
    this.defaultDevice = '',
    this.neverAskDefaultDevice = false,
    this.accentColor = _defaultAccent,
    this.useMaterial2 = false,
  });

  /// Path to the adb binary. Empty string = use `adb` from PATH.
  final String adbPath;

  /// Path to the global default `frida-il2cpp-bridge.js`.
  final String defaultBridgePath;

  /// Command template used to build the injection command. Supports
  /// `{bridge}`, `{script}`, `{app}`, `{bundle_id}` and `{device}` tokens.
  final String defaultCommandTemplate;

  /// Template used to build a bundle id from the "app name" convenience field.
  /// Supports the `{app}` token.
  final String bundleIdTemplate;

  final bool darkMode;
  final List<String> recentDevices;

  /// Last "default" wireless ADB address (`ip:port`) that the app should
  /// auto-connect to on launch. Empty = none.
  final String defaultDevice;

  /// When true, the app never asks to keep a device as default again.
  final bool neverAskDefaultDevice;

  /// Material 3 theme seed (ARGB int). Defaults to Meta blue `#0081FB`.
  final int accentColor;

  /// When true, uses the older Material 2 look instead of Material 3.
  final bool useMaterial2;

  static const String _defaultTemplate =
      'frida -U -f "{bundle_id}" -l "{bridge}" -l "{script}"';
  static const String _defaultBundleTemplate = 'com.{app}.{app}';
  static const int _defaultAccent = 0xFF0081FB;

  AppSettings copyWith({
    String? adbPath,
    String? defaultBridgePath,
    String? defaultCommandTemplate,
    String? bundleIdTemplate,
    bool? darkMode,
    List<String>? recentDevices,
    String? defaultDevice,
    bool? neverAskDefaultDevice,
    int? accentColor,
    bool? useMaterial2,
  }) {
    return AppSettings(
      adbPath: adbPath ?? this.adbPath,
      defaultBridgePath: defaultBridgePath ?? this.defaultBridgePath,
      defaultCommandTemplate:
          defaultCommandTemplate ?? this.defaultCommandTemplate,
      bundleIdTemplate: bundleIdTemplate ?? this.bundleIdTemplate,
      darkMode: darkMode ?? this.darkMode,
      recentDevices: recentDevices ?? this.recentDevices,
      defaultDevice: defaultDevice ?? this.defaultDevice,
      neverAskDefaultDevice:
          neverAskDefaultDevice ?? this.neverAskDefaultDevice,
      accentColor: accentColor ?? this.accentColor,
      useMaterial2: useMaterial2 ?? this.useMaterial2,
    );
  }

  /// Adds [address] to the front of the recent devices list (deduped, capped).
  AppSettings withRecentDevice(String address) {
    final list = <String>[
      address,
      ...recentDevices.where((d) => d != address),
    ].take(8).toList();
    return copyWith(recentDevices: list);
  }

  Map<String, dynamic> toJson() => {
        'adbPath': adbPath,
        'defaultBridgePath': defaultBridgePath,
        'defaultCommandTemplate': defaultCommandTemplate,
        'bundleIdTemplate': bundleIdTemplate,
        'darkMode': darkMode,
        'recentDevices': recentDevices,
        'defaultDevice': defaultDevice,
        'neverAskDefaultDevice': neverAskDefaultDevice,
        'accentColor': accentColor,
        'useMaterial2': useMaterial2,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        adbPath: json['adbPath'] as String? ?? '',
        defaultBridgePath: json['defaultBridgePath'] as String? ?? '',
        defaultCommandTemplate:
            json['defaultCommandTemplate'] as String? ?? _defaultTemplate,
        bundleIdTemplate:
            json['bundleIdTemplate'] as String? ?? _defaultBundleTemplate,
        darkMode: json['darkMode'] as bool? ?? true,
        recentDevices: (json['recentDevices'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        defaultDevice: json['defaultDevice'] as String? ?? '',
        neverAskDefaultDevice: json['neverAskDefaultDevice'] as bool? ?? false,
        accentColor: json['accentColor'] as int? ?? _defaultAccent,
        useMaterial2: json['useMaterial2'] as bool? ?? false,
      );
}

/// Given an app-name convenience string, build the bundle id using a template.
String buildBundleId(String template, String appName) {
  final trimmed = appName.trim();
  if (trimmed.isEmpty) return '';
  return template.replaceAll('{app}', trimmed).trim();
}

/// Shared default template used when nothing has been customized yet.
String defaultCommandTemplate() => AppSettings._defaultTemplate;
