part of 'controller_screen.dart';

// Connection status chip + transient toast — extracted from controller_screen.dart.
// Repaints independently of the controller tree (driven by a ValueNotifier).

class _Toast extends StatefulWidget {
  const _Toast({required this.message});
  final String message;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    // Fade in next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
    // Hold, then fade out (parent removes the entry shortly after).
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _opacity = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom + 40;
    return Positioned(
      left: 0, right: 0, bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _opacity,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            // Material ancestor → kills the default yellow debug underline on Text.
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xCC0B0B12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x336FB6FF)),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Text(widget.message,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500,
                    letterSpacing: 0.2, decoration: TextDecoration.none)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stick painter — identical style for both sides ────────────────────────────

class _ConnChip extends StatefulWidget {
  const _ConnChip({required this.state, required this.onTap, this.streamOn = false});
  final ws.ConnectionState state;
  final VoidCallback onTap;
  final bool streamOn;   // while streaming, show real FPS in place of battery
  @override State<_ConnChip> createState() => _ConnChipState();
}

class _ConnChipState extends State<_ConnChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  StreamSubscription<int>? _latSub;
  StreamSubscription<DeviceReading>? _devSub;
  StreamSubscription<int?>? _playerSub;
  int? _latency;
  int? _player;
  DeviceReading? _dev;
  int _fps = 0;

  void _onFps() { if (mounted) setState(() => _fps = StreamService.instance.fps.value); }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
    _fps = StreamService.instance.fps.value;
    StreamService.instance.fps.addListener(_onFps);
    _latency = WebSocketService.instance.latencyMs;
    _latSub  = WebSocketService.instance.latencyStream.listen((ms) {
      if (mounted) setState(() => _latency = ms);
    });
    _player    = WebSocketService.instance.playerNumber;
    _playerSub = WebSocketService.instance.playerStream.listen((p) {
      if (mounted) setState(() => _player = p);
    });
    _dev    = DeviceStats.instance.last;
    _devSub = DeviceStats.instance.stream.listen((r) {
      if (mounted) setState(() => _dev = r);
    });
  }

  @override
  void dispose() {
    _latSub?.cancel(); _devSub?.cancel(); _playerSub?.cancel();
    StreamService.instance.fps.removeListener(_onFps);
    _pulse.dispose(); super.dispose();
  }

  // Green when smooth, amber when choppy, red when the stream is struggling.
  Color _fpsColor(int f) {
    if (f >= 50) return const Color(0xFF1DB954);
    if (f >= 30) return const Color(0xFFF9A825);
    return const Color(0xFFE53935);
  }

  Color _latColor(int ms) {
    if (ms < 40) return const Color(0xFF1DB954);
    if (ms < 90) return const Color(0xFFF9A825);
    return const Color(0xFFE53935);
  }

  Color _heatColor(double c) {
    if (c < 38) return const Color(0xFF1DB954);
    if (c < 43) return const Color(0xFFF9A825);
    return const Color(0xFFE53935);
  }

  Color _battColor(int p) =>
      p <= 15 ? const Color(0xFFE53935) : Colors.white60;

  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 6),
    child: Text('•', style: TextStyle(color: Colors.white24, fontSize: 11)),
  );

  Widget _stat(String text, Color color, {FontWeight w = FontWeight.normal}) =>
      Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: w));



  @override
  Widget build(BuildContext context) {
    final connected = widget.state == ws.ConnectionState.connected;
    final mismatch = WebSocketService.instance.versionMismatch;
    Color dotColor; String label; Color labelColor = Colors.white60;

    if (connected) {
      if (mismatch) {
        dotColor = const Color(0xFFE53935);
        label = 'Version Mismatch';
        labelColor = dotColor;
      } else if (_latency != null) {
        dotColor   = _latColor(_latency!);
        final showP = _player != null && WebSocketService.instance.connectedPlayers > 1;
        label      = showP ? 'P$_player • ${_latency}ms' : '${_latency}ms';
        labelColor = dotColor;
      } else {
        dotColor = const Color(0xFF1DB954); 
        final showP = _player != null && WebSocketService.instance.connectedPlayers > 1;
        label = showP ? 'P$_player • Connected' : 'Connected';
      }
    } else if (widget.state == ws.ConnectionState.connecting) {
      dotColor = const Color(0xFFF9A825); label = 'Connecting';
    } else {
      dotColor = const Color(0xFFE53935);
      label = WebSocketService.instance.serverFull ? 'Server full' : 'Offline';
    }

    final dot = Container(
      width: 7, height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
    );

    final dev = _dev;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [

          widget.state == ws.ConnectionState.connecting
              ? FadeTransition(opacity: _pulse, child: dot)
              : dot,
          const SizedBox(width: 6),
          _stat(label, labelColor,
              w: connected && _latency != null ? FontWeight.w600 : FontWeight.normal),
          if (dev != null && dev.hasTemp) ...[
            _sep(),
            _stat('${dev.tempC.toStringAsFixed(0)}\u00B0', _heatColor(dev.tempC)),
          ],
          // While streaming, FPS is what matters \u2014 show it where battery sits.
          if (widget.streamOn) ...[
            _sep(),
            _stat('$_fps fps', _fpsColor(_fps), w: FontWeight.w600),
          ] else if (dev != null && dev.hasBattery) ...[
            _sep(),
            _stat('${dev.battery}%', _battColor(dev.battery)),
          ],
        ]),
      ),
    );
  }
}
