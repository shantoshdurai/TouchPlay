import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

enum ConnectionState { connected, connecting, disconnected }

const _port         = 8765;
const _udpPort      = 8766;
const _pingInterval = Duration(seconds: 3);
const _pongTimeout  = Duration(seconds: 5);
const _reconnectDelay = Duration(seconds: 2);
const _maxQueue     = 10;

// Sensitivity defaults
class SensitivitySettings {
  double stickSensitivity;
  double deadZone;
  double mouseSensitivity;

  SensitivitySettings({
    this.stickSensitivity = 1.0,
    this.deadZone         = 0.08,
    this.mouseSensitivity = 18.0,
  });
}

class WebSocketService {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  // Connection state
  final _stateCtrl = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get stateStream => _stateCtrl.stream;
  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  // Discovered server IP (via UDP)
  String? _discoveredIp;
  String? _manualIp;
  String? get currentIp => _discoveredIp ?? _manualIp;

  // Sensitivity
  final sensitivity = SensitivitySettings();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;
  RawDatagramSocket? _udpSocket;

  final _queue   = <Map<String, dynamic>>[];
  bool _running  = false;

  void _setState(ConnectionState s) {
    _state = s;
    _stateCtrl.add(s);
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _manualIp = prefs.getString('manual_ip');
    _running  = true;
    _startUdpDiscovery();
    _scheduleConnect();
  }

  // ── UDP auto-discovery ──────────────────────────────────────────────────────

  void _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _udpPort);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = _udpSocket!.receive();
          if (dg == null) return;
          try {
            final msg = json.decode(utf8.decode(dg.data)) as Map<String, dynamic>;
            if (msg['type'] == 'server_hello') {
              final ip = msg['ip'] as String;
              if (ip != _discoveredIp) {
                _discoveredIp = ip;
                // If not connected, connect immediately
                if (_state != ConnectionState.connected) {
                  _reconnectTimer?.cancel();
                  _disconnect();
                  _scheduleConnect(immediately: true);
                }
              }
            }
          } catch (_) {}
        }
      });
    } catch (_) {}
  }

  // ── IP management ───────────────────────────────────────────────────────────

  Future<void> setManualIp(String ip) async {
    _manualIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manual_ip', _manualIp!);
    _disconnect();
    _scheduleConnect(immediately: true);
  }

  List<String> _candidates() {
    final ips = <String>{};
    if (_discoveredIp != null) ips.add(_discoveredIp!); // UDP found — highest priority
    ips.add('127.0.0.1');                                 // ADB forward (USB cable)
    ips.add('192.168.42.129');                            // USB tethering
    if (_manualIp != null && _manualIp!.isNotEmpty) ips.add(_manualIp!);
    return ips.toList();
  }

  // ── Connection logic ────────────────────────────────────────────────────────

  void _scheduleConnect({bool immediately = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      immediately ? Duration.zero : _reconnectDelay,
      _tryConnect,
    );
  }

  Future<void> _tryConnect() async {
    if (!_running) return;
    for (final ip in _candidates()) {
      if (await _connect(ip)) return;
    }
    _scheduleConnect();
  }

  Future<bool> _connect(String ip) async {
    _setState(ConnectionState.connecting);
    try {
      final uri     = Uri.parse('ws://$ip:$_port');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 3));

      _channel = channel;
      _sub = channel.stream.listen(
        _onMessage,
        onDone:    _onDisconnected,
        onError:   (_) => _onDisconnected(),
        cancelOnError: true,
      );

      _setState(ConnectionState.connected);
      _flushQueue();
      _startPing();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      if (data['type'] == 'pong') _pongTimer?.cancel();
    } catch (_) {}
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _channel = null;
    _setState(ConnectionState.disconnected);
    if (_running) _scheduleConnect();
  }

  void _disconnect() {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_state != ConnectionState.connected) return;
      send({'type': 'ping'});
      _pongTimer?.cancel();
      _pongTimer = Timer(_pongTimeout, _onDisconnected);
    });
  }

  // ── Send ────────────────────────────────────────────────────────────────────

  void send(Map<String, dynamic> message) {
    if (_state == ConnectionState.connected && _channel != null) {
      _channel!.sink.add(json.encode(message));
    } else {
      if (_queue.length >= _maxQueue) _queue.removeAt(0);
      _queue.add(message);
    }
  }

  void _flushQueue() {
    while (_queue.isNotEmpty && _channel != null) {
      _channel!.sink.add(json.encode(_queue.removeAt(0)));
    }
  }

  void dispose() {
    _running = false;
    _udpSocket?.close();
    _disconnect();
    _stateCtrl.close();
  }
}
