import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'websocket_service.dart';

/// Drives the two phone → PC casting features over WebSocket port 8769:
///  • Virtual Cam  — native Camera2 JPEG frames (mode 'camera')
///  • Projector    — native MediaProjection JPEG frames (mode 'projector')
///
/// The native side (MainActivity + CameraStreamer/ScreenCastService) produces
/// JPEG bytes on an EventChannel; this service forwards them to the PC and
/// decodes every few frames into [preview] for the on-phone UI.
class CastService {
  CastService._();
  static final instance = CastService._();

  static const _castPort = 8769;
  static const _method = MethodChannel('touchplay/cast');
  static const _events = EventChannel('touchplay/cast_frames');

  final ValueNotifier<String?> activeMode = ValueNotifier<String?>(null);
  final ValueNotifier<int> fps = ValueNotifier<int>(0);
  final ValueNotifier<ui.Image?> preview = ValueNotifier<ui.Image?>(null);

  WebSocketChannel? _channel;
  StreamSubscription? _frameSub;
  Timer? _fpsTimer;
  int _frameCount = 0;
  int _previewSkip = 0;
  bool _decodingPreview = false;
  bool _frontCamera = false;

  bool get isActive => activeMode.value != null;
  bool get frontCamera => _frontCamera;

  /// Starts casting in [mode] ('camera' or 'projector').
  /// Returns null on success, or a user-readable error message.
  Future<String?> start(String mode, {bool front = false}) async {
    await stop();

    final ip = WebSocketService.instance.currentIp;
    if (ip == null ||
        WebSocketService.instance.state != ConnectionState.connected) {
      return 'Connect to your PC first — start the TouchPlay server.';
    }

    // 1. Open the cast socket and declare the mode.
    try {
      final channel =
          WebSocketChannel.connect(Uri.parse('ws://$ip:$_castPort'));
      await channel.ready.timeout(const Duration(seconds: 4));
      channel.sink.add(json.encode({
        'type': 'hello',
        'mode': mode,
        'name': 'TouchPlay phone',
      }));
      _channel = channel;
    } catch (_) {
      return 'PC server is running an old version — update it from the '
          'Releases page (the cast port did not answer).';
    }

    // 2. Start the native producer.
    bool ok;
    try {
      ok = mode == 'camera'
          ? (await _method.invokeMethod<bool>(
                  'start_camera', {'front': front}) ??
              false)
          : (await _method.invokeMethod<bool>('start_projection') ?? false);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      _closeSocket();
      return mode == 'camera'
          ? 'Camera permission was denied — allow it in Settings.'
          : 'Screen-record permission was denied.';
    }
    _frontCamera = front;

    // 3. Pump frames native → PC.
    _frameSub = _events.receiveBroadcastStream().listen((data) {
      final bytes =
          data is Uint8List ? data : Uint8List.fromList(data as List<int>);
      try {
        _channel?.sink.add(bytes);
      } catch (_) {}
      _frameCount++;
      // Decode 1 in 4 frames for the on-phone preview (camera only — a live
      // preview of your own mirrored screen is just a hall of mirrors).
      if (mode == 'camera' && ++_previewSkip >= 4) {
        _previewSkip = 0;
        _decodePreview(bytes);
      }
    }, onError: (_) {});

    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      fps.value = _frameCount;
      _frameCount = 0;
    });

    activeMode.value = mode;
    return null;
  }

  /// Flip between front/back camera while the Virtual Cam runs.
  Future<void> flipCamera() async {
    if (activeMode.value != 'camera') return;
    _frontCamera = !_frontCamera;
    try {
      await _method.invokeMethod('start_camera', {'front': _frontCamera});
    } catch (_) {}
  }

  Future<void> stop() async {
    final mode = activeMode.value;
    activeMode.value = null;
    try {
      if (mode == 'camera') {
        await _method.invokeMethod('stop_camera');
      } else if (mode == 'projector') {
        await _method.invokeMethod('stop_projection');
      }
    } catch (_) {}
    await _frameSub?.cancel();
    _frameSub = null;
    _closeSocket();
    _fpsTimer?.cancel();
    _fpsTimer = null;
    _frameCount = 0;
    fps.value = 0;
    final old = preview.value;
    preview.value = null;
    old?.dispose();
  }

  void _closeSocket() {
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> _decodePreview(Uint8List bytes) async {
    if (_decodingPreview) return;
    _decodingPreview = true;
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final codec = await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      final old = preview.value;
      preview.value = frame.image;
      old?.dispose();
    } catch (_) {
    } finally {
      _decodingPreview = false;
    }
  }
}
