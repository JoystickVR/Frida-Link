import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/app_settings.dart';
import '../core/models/mod_entry.dart';
import '../core/services/storage_service.dart';

/// Provides the storage service instance.
final storageProvider = Provider<StorageService>((ref) => StorageService());

/// Combined persisted state: settings + mod library.
class AppData {
  const AppData({required this.settings, required this.mods});

  final AppSettings settings;
  final List<ModEntry> mods;
}

/// Loads once on startup and persists on every mutation. This is the single
/// source of truth for settings + mod library.
class AppDataController extends StateNotifier<AppData> {
  AppDataController(this._storage)
      : super(const AppData(settings: AppSettings(), mods: []));

  final StorageService _storage;
  bool _ready = false;

  Future<void> load() async {
    if (_ready) return;
    _ready = true;
    final data = await _storage.load();
    state = AppData(settings: data.settings, mods: data.mods);
  }

  Future<void> saveSettings(AppSettings next) async {
    state = AppData(settings: next, mods: state.mods);
    await _persist();
  }

  Future<void> updateSettings(AppSettings Function(AppSettings) mutate) async {
    await saveSettings(mutate(state.settings));
  }

  Future<void> upsertMod(ModEntry mod) async {
    final list = <ModEntry>[
      for (final m in state.mods)
        if (m.id != mod.id) m,
      mod,
    ];
    state = AppData(settings: state.settings, mods: list);
    await _persist();
  }

  Future<void> patchMod(String id, ModEntry Function(ModEntry) mutate) async {
    state = AppData(settings: state.settings, mods: [
      for (final m in state.mods) m.id == id ? mutate(m) : m,
    ]);
    await _persist();
  }

  Future<void> removeMod(String id) async {
    state = AppData(settings: state.settings, mods: [
      for (final m in state.mods)
        if (m.id != id) m,
    ]);
    await _persist();
  }

  Future<void> _persist() async {
    await _storage.save(state.settings, state.mods);
  }
}

final appDataControllerProvider =
    StateNotifierProvider<AppDataController, AppData>((ref) {
  final ctrl = AppDataController(ref.watch(storageProvider));
  ctrl.load();
  return ctrl;
});

/// Convenience: current settings.
final settingsProvider = Provider<AppSettings>((ref) {
  ref.watch(appDataControllerProvider.notifier);
  return ref.watch(appDataControllerProvider).settings;
});

/// Convenience: current mod library.
final modLibraryProvider = Provider<List<ModEntry>>((ref) {
  ref.watch(appDataControllerProvider.notifier);
  return ref.watch(appDataControllerProvider).mods;
});

/// Holds a script path passed on the command line (e.g. via the "Open with
/// Frida Link" explorer context menu). The mod library consumes it once to
/// pre-fill the Add Mod sheet, then it is cleared.
final launchScriptProvider =
    StateNotifierProvider<LaunchScriptNotifier, String?>(
        (ref) => LaunchScriptNotifier());

class LaunchScriptNotifier extends StateNotifier<String?> {
  LaunchScriptNotifier() : super(null);

  void set(String path) => state = path;

  /// Clears and returns the current value (if any).
  String? take() {
    final v = state;
    state = null;
    return v;
  }
}