import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models/mod_entry.dart';
import '../core/services/adb_service.dart';
import '../core/services/app_icon_service.dart';
import 'app_data_controller.dart';

/// Provides the shared icon service, wired to the current adb path.
final appIconServiceProvider = Provider<AppIconService>((ref) {
  final settings = ref.watch(settingsProvider);
  return AppIconService(adb: AdbService(adbPath: settings.adbPath));
});

/// Tracks resolved app icons: bundleId → local icon file path ('' = not
/// available / failed). Fetches are deduped and keyed by bundle id.
class AppIconController extends StateNotifier<Map<String, String>> {
  AppIconController(this._service) : super(const {});

  final AppIconService _service;
  final Set<String> _inflight = {};

  /// Fires background icon fetches for every mod that has a bundle id and no
  /// resolved icon yet. Safe to call on every rebuild.
  void ensureIcons(List<ModEntry> mods, String? serial) {
    if (serial == null) return;
    for (final m in mods) {
      final bundle = m.bundleId.trim();
      if (bundle.isEmpty) continue;
      if (state.containsKey(bundle)) continue;
      if (_inflight.contains(bundle)) continue;
      unawaited(_fetch(serial, bundle));
    }
  }

  /// Clears the cached icon for [bundleId] and fetches a fresh one.
  Future<void> refreshIcon(String serial, String bundleId) async {
    final bundle = bundleId.trim();
    if (bundle.isEmpty) return;
    final existing = state[bundle];
    if (existing != null && existing.isNotEmpty) {
      try {
        await File(existing).delete();
      } catch (_) {}
    }
    state = {...state}..remove(bundle);
    await _fetch(serial, bundle);
  }

  Future<void> _fetch(String serial, String bundle) async {
    if (_inflight.contains(bundle)) return;
    _inflight.add(bundle);
    String? path;
    try {
      path = await _service.fetchAppIcon(serial, bundle);
    } catch (_) {
      path = null;
    } finally {
      _inflight.remove(bundle);
    }
    state = {...state, bundle: path ?? ''};
  }
}

final appIconControllerProvider =
    StateNotifierProvider<AppIconController, Map<String, String>>(
        (ref) => AppIconController(ref.watch(appIconServiceProvider)));