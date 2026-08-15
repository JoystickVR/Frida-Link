/// A single saved mod in the library.
class ModEntry {
  ModEntry({
    required this.id,
    required this.name,
    required this.scriptPath,
    this.appName = '',
    this.bundleId = '',
    this.bridgeOverridePath = '',
    this.customCommand = '',
    this.iconPath = '',
    this.lastUsed,
    this.addedAt,
  });

  final String id;
  String name;
  String scriptPath;
  String appName;
  String bundleId;

  /// Custom bridge file for this mod only ('' = use global default).
  String bridgeOverridePath;

  /// Custom frida command. '' = use the global default command template.
  String customCommand;

  /// Local path of a user-picked icon for this mod ('' = use the fetched
  /// app icon / placeholder).
  String iconPath;

  DateTime? lastUsed;
  DateTime? addedAt;

  String get bridgePath =>
      bridgeOverridePath.isEmpty ? '' : bridgeOverridePath;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'scriptPath': scriptPath,
        'appName': appName,
        'bundleId': bundleId,
        'bridgeOverridePath': bridgeOverridePath,
        'customCommand': customCommand,
        'iconPath': iconPath,
        'lastUsed': lastUsed?.toIso8601String(),
        'addedAt': addedAt?.toIso8601String(),
      };

  factory ModEntry.fromJson(Map<String, dynamic> json) => ModEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        scriptPath: json['scriptPath'] as String? ?? '',
        appName: json['appName'] as String? ?? '',
        bundleId: json['bundleId'] as String? ?? '',
        bridgeOverridePath: json['bridgeOverridePath'] as String? ?? '',
        customCommand: json['customCommand'] as String? ?? '',
        iconPath: json['iconPath'] as String? ?? '',
        lastUsed: DateTime.tryParse(json['lastUsed'] as String? ?? ''),
        addedAt: DateTime.tryParse(json['addedAt'] as String? ?? ''),
      );

  ModEntry copyWith({String? name, String? iconPath, DateTime? lastUsed}) =>
      ModEntry(
        id: id,
        name: name ?? this.name,
        scriptPath: scriptPath,
        appName: appName,
        bundleId: bundleId,
        bridgeOverridePath: bridgeOverridePath,
        customCommand: customCommand,
        iconPath: iconPath ?? this.iconPath,
        lastUsed: lastUsed ?? this.lastUsed,
        addedAt: addedAt,
      );
}