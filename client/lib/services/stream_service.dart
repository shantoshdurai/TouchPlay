import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Connects to the PC stream server on port 8767 and exposes the latest
/// frame as a hardware-decoded [ui.Image] via [frame].
///
/// The frame is published through a [ValueNotifier] (not a Stream + setState)
/// so the UI can rebuild ONLY the video layer — wrapped in a RepaintBoundary —
/// instead of the entire controller HUD on every decoded frame. At 60fps that
/// is the difference between repainting one texture vs. re-walking the whole
/// button/stick widget tree 60 times a second.
class StreamService {
  StreamService._();
  static final instance = StreamService._();

  static const _streamPort = 8767;

  WebSocketChannel? _channel;

  /// Latest decoded frame. Listeners (a ValueListenableBuilder in the UI) repaint
  /// in isolation. The previous frame is disposed automatically when replaced.
  final ValueNotifier<ui.Image?> frame = ValueNotifier<ui.Image?>(null);

  /// Real rendered frames-per-second — the rate at which decoded frames are
  /// actually published to the screen (i.e. what the phone is really showing),
  /// recomputed once a second. 0 when not streaming.
  final ValueNotifier<int> fps = ValueNotifier<int>(0);
  int _frameCount = 0;
  Timer? _fpsTimer;

  bool _connected = false;

  // Prevent decode backlog: if a new frame arrives while we're still decoding
  // the previous one, we skip the stale frame rather than queuing it.
  bool _decoding = false;
  Uint8List? _pending; // latest frame waiting if we were busy

  bool get isConnected => _connected;

  Future<void> connect(String serverIp) async {
    if (_connected) return;
    try {
      final uri = Uri.parse('ws://$serverIp:$_streamPort');
      _channel = IOWebSocketChannel.connect(uri,
          connectTimeout: const Duration(seconds: 3));
      _connected = true;

      // Publish the real frame rate once a second from the live frame count.
      _frameCount = 0;
      _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        fps.value = _frameCount;
        _frameCount = 0;
      });

      _channel!.stream.listen(
        (data) {
          final bytes = data is Uint8List
              ? data
              : Uint8List.fromList(data as List<int>);

          if (_decoding) {
            // Already busy — remember only the freshest frame, drop older ones.
            _pending = bytes;
            return;
          }
          _decodeAndEmit(bytes);
        },
        onDone:  () => _connected = false,
        onError: (_) => _connected = false,
        cancelOnError: true,
      );
    } catch (_) {
      _connected = false;
    }
  }

  /// Decode one frame using Flutter's modern async pipeline (hardware-backed on
  /// Android) then immediately check if a newer frame arrived while we were busy.
  Future<void> _decodeAndEmit(Uint8List bytes) async {
    _decoding = true;
    try {
      final image = await _decodeFrame(bytes);
      // Publish the new frame and dispose the one it replaces.
      final old = frame.value;
      frame.value = image;
      old?.dispose();
      _frameCount++;   // count only frames actually shown on screen
    } catch (_) {
      // Bad frame — skip silently, don't crash the stream.
    } finally {
      _decoding = false;
      // If a fresher frame came in while we decoded, process it now.
      final next = _pending;
      if (next != null) {
        _pending = null;
        _decodeAndEmit(next);
      }
    }
  }

  /// Modern Flutter image decode — uses ImmutableBuffer + ImageDescriptor
  /// which is async, off the UI thread, and hardware-accelerated on Android.
  static Future<ui.Image> _decodeFrame(Uint8List bytes) async {
    final buffer     = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final codec      = await descriptor.instantiateCodec();
    final frameInfo  = await codec.getNextFrame();
    buffer.dispose();
    descriptor.dispose();
    codec.dispose();
    return frameInfo.image;
  }

  void disconnect() {
    _channel?.sink.close();
    _channel  = null;
    _connected = false;
    _decoding  = false;
    _pending   = null;
    _fpsTimer?.cancel();
    _fpsTimer  = null;
    _frameCount = 0;
    fps.value   = 0;
    final old = frame.value;
    frame.value = null;
    old?.dispose();
  }
}
