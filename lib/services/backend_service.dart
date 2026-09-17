import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BackendService {
  static const String statusUrl = 'http://127.0.0.1:18900/api/status';
  static const String exitUrl = 'http://127.0.0.1:18900/api/exit';

  /// Check if the local backend server is running and responding.
  static Future<bool> isAlive() async {
    try {
      final res = await http.get(Uri.parse(statusUrl)).timeout(
        const Duration(milliseconds: 600),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ensure backend server is running. If not, automatically launch bds-server.exe.
  static Future<void> ensureStarted() async {
    if (await isAlive()) {
      debugPrint('[BackendService] Backend is already running on port 18900.');
      return;
    }

    final exeFile = _findBackendExecutable();
    if (exeFile == null) {
      debugPrint('[BackendService] No backend executable found. Will rely on external service.');
      return;
    }

    debugPrint('[BackendService] Launching backend: ${exeFile.path}');
    try {
      await Process.start(
        exeFile.path,
        ['--server-only', '--port=18900'],
        mode: ProcessStartMode.detached,
      );

      // Wait until backend becomes responsive (up to 6 seconds)
      final sw = Stopwatch()..start();
      while (sw.elapsedMilliseconds < 6000) {
        await Future.delayed(const Duration(milliseconds: 200));
        if (await isAlive()) {
          debugPrint('[BackendService] Backend successfully started in ${sw.elapsedMilliseconds}ms.');
          return;
        }
      }
      debugPrint('[BackendService] Timeout waiting for backend startup.');
    } catch (e) {
      debugPrint('[BackendService] Failed to start backend process: $e');
    }
  }

  /// Gracefully request the backend server to exit.
  static Future<void> shutdown() async {
    try {
      await http.post(Uri.parse(exitUrl)).timeout(
        const Duration(milliseconds: 500),
      );
    } catch (_) {}
  }

  static File? _findBackendExecutable() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final candidates = [
      '$exeDir\\bds-server.exe',
      '$exeDir\\share-service.exe',
      '$exeDir\\share-player.exe',
      // Development fallbacks
      '..\\dist\\payload\\bds-server.exe',
      '..\\share-player\\bds-server.exe',
      '..\\share-player\\share-player.exe',
      'share-player\\share-player.exe',
    ];

    for (final p in candidates) {
      final f = File(p);
      if (f.existsSync()) {
        return f;
      }
    }
    return null;
  }
}
