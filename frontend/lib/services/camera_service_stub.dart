// camera_service_stub.dart
// ────────────────────────
// No-op stub used on native platforms (Windows, Android, iOS).
// On native, combined_asl_live.py handles the camera entirely.

import 'dart:typed_data';

class CameraService {
  static const String videoViewId = 'asl-camera-preview';

  bool get isRunning => false;

  void Function(Uint8List jpeg)? onFrame;
  void Function(String error)? onError;

  Future<void> start() async {
    // Native: camera is handled by combined_asl_live.py → WebSocket pipeline
  }

  void stop() {}
  void dispose() {}
}
