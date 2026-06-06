import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

/// Connects to the PC stream server on port 8767 and exposes the latest
/// JPEG frame as a [Uint8List] via [frameStream].
///
/// Usage:
///   StreamService.instance.connect('192.168.1.5');
///   StreamService.instance.frameStream → Stream<Uint8List>
///   StreamService.instance.disconnect();
class StreamService {
  StreamService._();
  static final instance = StreamService._();

  static const _streamPort = 8767;

  WebSocketChannel? _channel;
  final _controller = StreamController<Uint8List>.broadcast();
  bool _connected = false;

  Stream<Uint8List> get frameStream => _controller.stream;
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
            _controller.add(Uint8List.fromList(data));
          } else if (data is Uint8List) {
            _controller.add(data);
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
