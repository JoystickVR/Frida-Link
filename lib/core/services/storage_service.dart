import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/mod_entry.dart';

/// Persists [AppSettings] + [List<ModEntry>] to a local JSON file.
class StorageService {
  StorageService({this.fileOverride});

  /// Test hook: use this file instead of the platform dir.
  final File? fileOverride;

  Future<File> _file() async {
    if (fileOverride != null) return fileOverride!;
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'frida_link_data.json'));
  }

  Future<({AppSettings settings, List<ModEntry> mods})> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return (settings: const AppSettings(), mods: <ModEntry>[]);
      }
      final raw = jsonDecode(await file.readAsString());
      final map = raw is Map<String, dynamic> ? raw : <String, dynamic>{};
      final settingsJson =
          map['settings'] is Map<String, dynamic> ? map['settings'] as Map<String, dynamic> : <String, dynamic>{};
      final modsJson = (map['mods'] as List<dynamic>? ?? <dynamic>[]);
      return (
        settings: AppSettings.fromJson(settingsJson),
        mods: modsJson
            .map((e) => ModEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      return (settings: const AppSettings(), mods: <ModEntry>[]);
    }
  }

  Future<void> save(AppSettings settings, List<ModEntry> mods) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final map = <String, dynamic>{
      'settings': settings.toJson(),
      'mods': mods.map((m) => m.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(map));
  }
}