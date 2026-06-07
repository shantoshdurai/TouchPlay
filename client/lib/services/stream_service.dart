import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Connects to the PC stream server on port 8767 and exposes the latest
/// frame as a hardware-decoded [ui.Image] via [frameStream].
class StreamService {
  StreamService._();
  static final instance = StreamService._();

  static const _streamPort = 8767;

  WebSocketChannel? _channel;
  final _controller = StreamController<ui.Image>.broadcast();
  bool _connected = false;

  Stream<ui.Image> get frameStream => _controller.stream;
  bool get isConnected => _connected;

  Future<void> connect(String serverIp) async {
    if (_connected) return;
    try {
      final uri = Uri.parse('ws://$serverIp:$_streamPort');
      _channel = IOWebSocketChannel.connect(uri,
          connectTimeout: const Duration(seconds: 3));
      _connected = true;

      _channel!.stream.listen(
        (data) {
          if (data is List<int>) {
            ui.decodeImageFromList(Uint8List.fromList(data), (image) {
              _controller.add(image);
            });
          } else if (data is Uint8List) {
            ui.decodeImageFromList(data, (image) {
              _controller.add(image);
            });
          }
        },
        onDone: () => _connected = false,
        onError: (_) => _connected = false,
        cancelOnError: true,
      );
    } catch (_) {
      _connected = false;
    }
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _connected = false;
  }
}
