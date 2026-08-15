import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'adb_service.dart';

/// Fetches launcher icons for installed apps from a connected headset and
/// manages user-picked mod icons. Icons live in `<app support>/icons/`.
///
/// App icons are pulled straight out of the installed APK via `unzip` on the
/// device (no full-APK download): we list the res/ folder, grab the biggest
/// square PNG/WebP (the launcher icon — works even for obfuscated Unity
/// builds), and cache it locally keyed by bundle id.
class AppIconService {
  AppIconService({required AdbService adb}) : _adb = adb;

  final AdbService _adb;

  Future<Directory> _iconsDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'icons'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Local path of the cached app icon for [bundleId], or null.
  Future<String?> cachedAppIcon(String bundleId) async {
    final icons = await _iconsDir();
    final file = File(p.join(icons.path, '$bundleId.png'));
    return await file.exists() ? file.path : null;
  }

  /// Copies a user-chosen image into the icon store for a specific mod.
  Future<String> saveModIcon(String modId, String sourcePath) async {
    final icons = await _iconsDir();
    final ext = p.extension(sourcePath).toLowerCase();
    final dest = File(p.join(icons.path, 'mod-$modId$ext'));
    if (p.equals(p.normalize(sourcePath), p.normalize(dest.path))) return dest.path;
    await File(sourcePath).copy(dest.path);
    return dest.path;
  }

  /// Deletes a stored mod icon (if any).
  Future<void> removeModIcon(String modId) async {
    final icons = await _iconsDir();
    if (!await icons.exists()) return;
    await for (final f in icons.list()) {
      if (f is File && p.basename(f.path).startsWith('mod-$modId.')) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Best-effort launcher icon for [bundleId], pulled off the headset.
  /// Returns the local cached file path, or null when nothing could be found.
  Future<String?> fetchAppIcon(String serial, String bundleId) async {
    final apks = await _apkPaths(serial, bundleId);
    if (apks.isEmpty) return null;

    Uint8List? best;
    var bestScore = -1;
    for (final apk in apks) {
      final candidates = await _resCandidates(serial, apk);
      if (candidates.isEmpty) continue;
      // Biggest candidates first (icons are small); cap to avoid pulling
      // hundreds of round trips on busy APKs.
      candidates.sort((a, b) => b.$1.compareTo(a.$1));
      final subset = candidates.length > 40
          ? candidates.sublist(0, 40)
          : candidates;
      for (final (_, name) in subset) {
        try {
          final result = await _adb.execOut(serial, ['unzip', '-p', apk, name]);
          if (!result.success) continue;
          final bytes = Uint8List.fromList(result.stdoutBytes);
          final dims = _dimensions(bytes);
          if (dims == null) continue;
          final score = _score(dims.$1, dims.$2);
          if (score > bestScore) {
            bestScore = score;
            best = bytes;
          }
        } catch (_) {}
      }
    }

    if (best == null && apks.isNotEmpty) {
      // No usable res/ entries (device lacks unzip, or exotic APK layout) —
      // fall back to streaming the APK and parsing it locally.
      for (final apk in apks) {
        try {
          final bytes = await _fetchStreaming(serial, apk);
          if (bytes != null) {
            best = bytes;
            break;
          }
        } catch (_) {}
      }
    }

    if (best == null) return null;

    final icons = await _iconsDir();
    final dest = File(p.join(icons.path, '$bundleId.png'));
    await dest.writeAsBytes(best, flush: true);
    return dest.path;
  }

  /// `pm path` → list of installed APK paths for [bundleId].
  Future<List<String>> _apkPaths(String serial, String bundleId) async {
    final result = await _adb.shell(serial, 'pm path $bundleId');
    final apks = <String>[];
    for (final line in result.stdout.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('package:')) continue;
      final path = trimmed.substring('package:'.length).trim();
      if (path.isNotEmpty && !apks.contains(path)) apks.add(path);
    }
    return apks;
  }

  /// Lists `res/*.png` / `res/*.webp` entries (name + uncompressed size) from
  /// an APK on the device using `unzip -l`. Empty when unavailable.
  Future<List<(int, String)>> _resCandidates(String serial, String apk) async {
    final result = await _adb.execOut(serial, ['unzip', '-l', apk]);
    if (!result.success) return <(int, String)>[];
    final text = utf8.decode(result.stdoutBytes, allowMalformed: true);
    final list = <(int, String)>[];
    for (final line in text.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final name = parts[3];
      final lower = name.toLowerCase();
      if (!lower.startsWith('res/')) continue;
      if (!lower.endsWith('.png') && !lower.endsWith('.webp')) continue;
      final size = int.tryParse(parts[0]);
      if (size == null || size > 3 * 1024 * 1024) continue;
      list.add((size, name));
    }
    return list;
  }

  /// Streams the whole APK over adb and picks the launcher icon locally
  /// (last-resort path for devices without `unzip`).
  Future<Uint8List?> _fetchStreaming(String serial, String apk) async {
    final tmpDir = await Directory.systemTemp.createTemp('fl_icon_');
    final tmp = File(p.join(tmpDir.path, 'bundle.apk'));
    try {
      final process = await Process.start(
        _adb.adbPath,
        ['-s', serial, 'exec-out', 'cat', apk],
        environment: Platform.environment,
      );
      final sink = tmp.openWrite();
      await process.stdout.pipe(sink);
      await sink.close();

      Uint8List? best;
      var bestScore = -1;
      final archive = ZipDecoder().decodeStream(InputFileStream(tmp.path));
      for (final f in archive) {
        final lower = f.name.toLowerCase();
        if (!lower.startsWith('res/')) continue;
        if (!lower.endsWith('.png') && !lower.endsWith('.webp')) continue;
        final bytes = f.content;
        final dims = _dimensions(bytes);
        if (dims == null) continue;
        final score = _score(dims.$1, dims.$2);
        if (score > bestScore) {
          bestScore = score;
          best = bytes;
        }
      }
      return best;
    } catch (_) {
      return null;
    } finally {
      try {
        await tmp.delete();
        await tmpDir.delete();
      } catch (_) {}
    }
  }

  /// Prefers square icons, then higher resolution; huge assets (e.g. 1024px
  /// splash screens) are de-prioritized below the 512px launcher-icon range.
  static int _score(int w, int h) {
    final isSquare = w == h;
    var score = isSquare ? 0x40000000 : 0;
    final area = w * h;
    if (w <= 512 && h <= 512) {
      score |= area;
    } else {
      score |= area >> 4;
    }
    return score;
  }

  /// PNG or WebP dimensions from a file header, or null.
  static (int, int)? _dimensions(Uint8List b) {
    if (b.length >= 24 &&
        b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47) {
      final w = _u32(b, 16);
      final h = _u32(b, 20);
      if (_valid(w, h)) return (w, h);
    }
    if (b.length >= 30 &&
        b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      final four = String.fromCharCodes(b.sublist(12, 16));
      if (four == 'VP8X') {
        final w = _u24(b, 24) + 1;
        final h = _u24(b, 27) + 1;
        if (_valid(w, h)) return (w, h);
      } else if (four == 'VP8 ') {
        final w = _u16(b, 26);
        final h = _u16(b, 28);
        if (_valid(w, h)) return (w, h);
      } else if (four == 'VP8L') {
        final bits = _u32(b, 21);
        final w = (bits & 0x3fff) + 1;
        final h = ((bits >> 14) & 0x3fff) + 1;
        if (_valid(w, h)) return (w, h);
      }
    }
    return null;
  }

  static bool _valid(int w, int h) => w > 0 && h > 0 && w < 8192 && h < 8192;

  static int _u16(Uint8List b, int o) => (b[o] << 8) | b[o + 1];

  static int _u24(Uint8List b, int o) =>
      (b[o] << 16) | (b[o + 1] << 8) | b[o + 2];

  static int _u32(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
}