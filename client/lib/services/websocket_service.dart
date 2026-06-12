import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'haptics.dart';

enum ConnectionState { connected, connecting, disconnected }

const _port         = 8765;
const _udpPort      = 8766;
const _pingInterval = Duration(seconds: 2);   // 2s interval — enough for live readout, less noise
const _pongTimeout  = Duration(seconds: 12);  // was 5s — tolerate a brief Wi-Fi stall
const _maxQueue     = 10;

// Reconnect back-off: start at 1 s, double each attempt up to a 16 s ceiling.
// Fast on a quick blip, gentle on a sustained drop so we don't spam the network.
const _reconnectBase = Duration(seconds: 1);
const _reconnectMax  = Duration(seconds: 16);

// Sensitivity defaults
class SensitivitySettings {
  double stickSensitivity;
  double rightStickSensitivity;
  double deadZone;
  double mouseSensitivity;
  bool   vibration;          // master on/off (kept in sync with strength > 0)
  double vibrationStrength;  // 0..1 — scales motor amplitude (user-adjustable)
  double joyRadius;
  // Per-control size factors for the Forza racing HUD (1.0 = default size).
  double gasSize;
  double brakeSize;
  double handbrakeSize;
  String streamQuality;    // '360p' | '480p' | '720p'
  bool   streamFitStretch;

  SensitivitySettings({
    this.stickSensitivity      = 1.0,
    this.rightStickSensitivity = 1.8,
    this.deadZone              = 0.08,
    this.mouseSensitivity      = 18.0,
    this.vibration             = false,
    this.vibrationStrength     = 0.0,
    this.joyRadius             = 1.0,
    this.gasSize               = 1.0,
    this.brakeSize             = 1.0,
    this.handbrakeSize         = 1.0,
    this.streamQuality         = '480p',
    this.streamFitStretch      = false,
  });
}

class WebSocketService with WidgetsBindingObserver {
  WebSocketService._();
  static final WebSocketService instance = WebSocketService._();

  // Connection state
  final _stateCtrl = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get stateStream => _stateCtrl.stream;
  ConnectionState _state = ConnectionState.disconnected;
  ConnectionState get state => _state;

  // Keyboard auto-popup
  final _keyboardCtrl = StreamController<bool>.broadcast();
  Stream<bool> get keyboardStream => _keyboardCtrl.stream;

  // Latency (round-trip ping → pong, in ms)
  final _latencyCtrl = StreamController<int>.broadcast();
  Stream<int> get latencyStream => _latencyCtrl.stream;
  int? _latencyMs;
  int? get latencyMs => _latencyMs;
  DateTime? _pingSentAt;

  // Discovered server IP (via UDP)
  String? _discoveredIp;
  String? _manualIp;
  String? get currentIp => _discoveredIp ?? _manualIp;

  // Diagnostics (surfaced in the "Can't connect?" dialog)
  String? get discoveredIp => _discoveredIp;
  List<String> get candidateIps => _candidates();
  /// The server version this app ships with (keep in sync with server VERSION).
  static const expectedServerVersion = '1.3.0';
  String? _serverVersion;
  String? get serverVersion => _serverVersion;
  bool get versionMismatch =>
      _serverVersion != null && _serverVersion != expectedServerVersion;
  String? _deviceId;

  // Local co-op: which player slot the server assigned this phone (1..maxPlayers),
  // and whether the server turned us away because it's already full.
  final _playerCtrl = StreamController<int?>.broadcast();
  Stream<int?> get playerStream => _playerCtrl.stream;
  int? _playerNumber;
  int? get playerNumber => _playerNumber;
  int? _maxPlayers;
  int? get maxPlayers => _maxPlayers;
  int _connectedPlayers = 1;
  int get connectedPlayers => _connectedPlayers;
  bool _serverFull = false;
  bool get serverFull => _serverFull;

  String _deviceName = "Unknown Device";

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

  bool _inited = false;

  Future<void> init() async {
    // Idempotent — called from main() at startup and again by screens that
    // need the link, so whichever runs first wins and the rest are no-ops.
    if (_inited) return;
    _inited = true;
    WidgetsBinding.instance.addObserver(this);
    final prefs = await SharedPreferences.getInstance();
    _manualIp = prefs.getString('manual_ip');
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = '${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1000000)}';
      await prefs.setString('device_id', _deviceId!);
    }
    
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final manufacturer = info.manufacturer.replaceFirst(RegExp(r'^[a-z]'), info.manufacturer.substring(0, 1).toUpperCase());
        _deviceName = '$manufacturer ${info.model}'.trim();
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        _deviceName = info.name;
      } else {
        _deviceName = Platform.localHostname;
      }
    } catch (_) {}

    await loadSensitivity();
    _running  = true;
    _startUdpDiscovery();
    _sweepLocalSubnets();
    _scheduleConnect(immediately: true);
  }

  // ── Settings persistence ─────────────────────────────────────────────────────
  // Sensitivity / vibration used to live only in memory, so every setting reset
  // to default on each app launch. Persist them so the player's tuning sticks.

  static const _sKey = 'sensitivity_v1';

  Future<void> loadSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    final s = sensitivity;
    double d(String k, double v) => prefs.getDouble('${_sKey}_$k') ?? v;
    s.stickSensitivity      = d('left',  s.stickSensitivity);
    s.rightStickSensitivity = d('right', s.rightStickSensitivity);
    s.deadZone              = d('dead',  s.deadZone);
    s.mouseSensitivity      = d('mouse', s.mouseSensitivity);
    s.vibration             = prefs.getBool('${_sKey}_vib') ?? s.vibration;
    s.vibrationStrength     = d('vibstr', s.vibrationStrength);
    s.joyRadius             = d('joy',   s.joyRadius);
    s.gasSize               = d('gas',   s.gasSize);
    s.brakeSize             = d('brake', s.brakeSize);
    s.handbrakeSize         = d('hb',    s.handbrakeSize);
    // Migrate old bool key → quality string if present.
    final oldHq = prefs.getBool('${_sKey}_hq');
    s.streamQuality     = prefs.getString('${_sKey}_quality')
        ?? (oldHq == true ? '720p' : '480p');
    s.streamFitStretch  = prefs.getBool('${_sKey}_fit') ?? s.streamFitStretch;
  }

  Future<void> saveSensitivity() async {
    final prefs = await SharedPreferences.getInstance();
    final s = sensitivity;
    await prefs.setDouble('${_sKey}_left',  s.stickSensitivity);
    await prefs.setDouble('${_sKey}_right', s.rightStickSensitivity);
    await prefs.setDouble('${_sKey}_dead',  s.deadZone);
    await prefs.setDouble('${_sKey}_mouse', s.mouseSensitivity);
    await prefs.setBool  ('${_sKey}_vib',   s.vibration);
    await prefs.setDouble('${_sKey}_vibstr',s.vibrationStrength);
    await prefs.setDouble('${_sKey}_joy',   s.joyRadius);
    await prefs.setDouble('${_sKey}_gas',   s.gasSize);
    await prefs.setDouble('${_sKey}_brake', s.brakeSize);
    await prefs.setDouble('${_sKey}_hb',    s.handbrakeSize);
    await prefs.setString('${_sKey}_quality', s.streamQuality);
    await prefs.setBool  ('${_sKey}_fit',     s.streamFitStretch);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_state != ConnectionState.connected) {
        _disconnect();
        _tryConnect(silent: false);
      } else {
        // Send a ping immediately to verify connection is still alive
        _sendPing();
      }
    } else {
      // Backgrounded / inactive — release everything so nothing stays held down.
      if (_state == ConnectionState.connected) send({'type': 'reset'});
    }
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

  // ── Subnet Sweeper (USB Tethering Fallback) ─────────────────────────────────

  void _sweepLocalSubnets() async {
    try {
      final interfaces = await NetworkInterface.list();
      final subnets = <String>{};
      
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final ip = addr.address;
            if (ip.startsWith('127.')) continue;
            final parts = ip.split('.');
            if (parts.length == 4) {
              subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
            }
          }
        }
      }
      
      // Always include standard tethering just in case
      subnets.add('192.168.42');
      subnets.add('192.168.137');
      
      for (final subnet in subnets) {
        for (int i = 1; i < 255; i++) {
          if (_state == ConnectionState.connected) return;
          _pingSweep('$subnet.$i');
          // brief yield to not block the main thread
          if (i % 20 == 0) await Future.delayed(const Duration(milliseconds: 10));
        }
      }
    } catch (_) {}
  }

  Future<void> _pingSweep(String ip) async {
    try {
      final s = await Socket.connect(ip, _port, timeout: const Duration(milliseconds: 300));
      s.destroy();
      if (_discoveredIp != ip) {
        _discoveredIp = ip;
        if (_state != ConnectionState.connected) {
          _reconnectTimer?.cancel();
          _disconnect();
          _scheduleConnect(immediately: true);
        }
      }
    } catch (_) {}
  }

  // ── IP management ───────────────────────────────────────────────────────────

  Future<void> setManualIp(String ip) async {
    _manualIp = ip.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('manual_ip', _manualIp!);
    _disconnect();
    _tryConnect(silent: false);
  }

  /// Force a fresh discovery + connection attempt (the "Rescan" button).
  void reconnect() {
    _disconnect();
    _sweepLocalSubnets();
    _tryConnect(silent: false);
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

  bool _isConnecting = false;
  int  _connectionGen = 0;
  Duration _backOff = _reconnectBase; // grows on each failed attempt, resets on success

  void _scheduleConnect({bool immediately = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      immediately ? Duration.zero : _backOff,
      () => _tryConnect(silent: true),
    );
  }

  Future<void> _tryConnect({bool silent = false}) async {
    if (!_running || _isConnecting) return;
    _isConnecting = true;
    final gen = _connectionGen;
    
    if (!silent) {
      _setState(ConnectionState.connecting);
    }

    for (final ip in _candidates()) {
      if (gen != _connectionGen) return; // Aborted by newer connection attempt
      if (await _connect(ip, gen)) {
        if (gen != _connectionGen) return; // Aborted during await
        _backOff = _reconnectBase; // reset back-off on success
        _isConnecting = false;
        return;
      }
    }
    
    if (gen != _connectionGen) return; // Aborted
    _setState(ConnectionState.disconnected);
    _isConnecting = false;
    // Exponential back-off: double delay each failure, cap at max.
    _backOff = Duration(milliseconds:
        (_backOff.inMilliseconds * 2).clamp(
            _reconnectBase.inMilliseconds, _reconnectMax.inMilliseconds));
    _scheduleConnect();
  }

  Future<bool> _connect(String ip, int gen) async {
    try {
      final uri     = Uri.parse('ws://$ip:$_port');
      final channel = WebSocketChannel.connect(uri);
      await channel.ready.timeout(const Duration(seconds: 3));
      
      if (gen != _connectionGen) {
        channel.sink.close();
        return false;
      }

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

  void _sendPing() {
    _pingSentAt = DateTime.now();
    send({'type': 'ping'});
    _pongTimer?.cancel();
    _pongTimer = Timer(_pongTimeout, _onDisconnected);
  }

  void _onMessage(dynamic raw) {
    try {
      final data = json.decode(raw as String) as Map<String, dynamic>;
      if (data['type'] == 'pong') {
        _pongTimer?.cancel();
        if (_pingSentAt != null) {
          _latencyMs = DateTime.now().difference(_pingSentAt!).inMilliseconds;
          _latencyCtrl.add(_latencyMs!);
        }
      } else if (data['type'] == 'server_info') {
        _serverVersion = data['version'] as String?;
        _serverFull    = false;
        _playerNumber  = (data['player'] as num?)?.toInt();
        _maxPlayers    = (data['maxPlayers'] as num?)?.toInt();
        _playerCtrl.add(_playerNumber);
        send({'type': 'client_info', 'phone_name': _deviceName, 'device_id': _deviceId});
      } else if (data['type'] == 'rumble') {
        final large = (data['large'] as num?)?.toInt() ?? 0;
        final small = (data['small'] as num?)?.toInt() ?? 0;
        Haptics.instance.rumble(large, small);
      } else if (data['type'] == 'player_count') {
        _connectedPlayers = (data['count'] as num?)?.toInt() ?? 1;
        _playerCtrl.add(_playerNumber); // trigger UI update
      } else if (data['type'] == 'server_full') {
        _serverFull   = true;
        _maxPlayers   = (data['max'] as num?)?.toInt();
        _playerNumber = null;
        _playerCtrl.add(null);
      } else if (data['type'] == 'keyboard_requested') {
        _keyboardCtrl.add(data['show'] == true);
      }
    } catch (_) {}
  }

  void _onDisconnected() {
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _channel = null;
    _latencyMs = null;
    _setState(ConnectionState.disconnected);
    if (_running) _scheduleConnect();
  }

  void _disconnect() {
    _connectionGen++;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
    _setState(ConnectionState.disconnected);
    _isConnecting = false;
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (_state != ConnectionState.connected) return;
      _sendPing();
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
    WidgetsBinding.instance.removeObserver(this);
    _running = false;
    _udpSocket?.close();
    _disconnect();
    _stateCtrl.close();
    _playerCtrl.close();
    _keyboardCtrl.close();
  }
}
