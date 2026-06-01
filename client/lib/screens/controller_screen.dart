import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';
import '../services/websocket_service.dart' as ws;
import '../widgets/trigger_button.dart';
import '../widgets/action_button.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});
  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  late final StreamSubscription<ws.ConnectionState> _sub;
  ws.ConnectionState _conn = ws.ConnectionState.disconnected;
  bool _mouseMode    = false;
  bool _showSettings = false;
  bool _showTutorial = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub = WebSocketService.instance.stateStream.listen((s) => setState(() => _conn = s));
    WebSocketService.instance.init();
    _initTutorial();
  }

  Future<void> _initTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('tutorial_seen_v2') ?? false)) {
      await prefs.setBool('tutorial_seen_v2', true);
      if (mounted) setState(() => _showTutorial = true);
    }
  }

  @override
  void dispose() { _sub.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Stack(
        children: [
          // 1. The glowing background
          _BgGlow(),

          // 1b. Center split line
          Positioned(
            left: w * 0.5,
            top: 0, bottom: 0,
            child: Container(width: 1, color: Colors.white.withOpacity(0.07)),
          ),

          // 2a. LEFT floating stick zone (left half) — movement
          Positioned(
            left: 0, top: 28, bottom: 0, width: w * 0.5,
            child: _FloatingStick(side: 'left', screenH: h),
          ),
          // 2b. RIGHT floating stick zone (right half) — camera / mouse
          Positioned(
            right: 0, top: 28, bottom: 0, width: w * 0.5,
            child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
          ),

          // 3. Connection chip (top-left, compact)
          Positioned(
            top: 0, left: 8,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _ConnChip(
                  state: _conn,
                  ip: WebSocketService.instance.currentIp ?? '',
                  onTap: () => _showDialog(context),
                ),
              ),
            ),
          ),
          // Settings button (top-right, compact)
          Positioned(
            top: 0, right: 8,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _SettingsBtn(
                  onTap: () => setState(() => _showSettings = !_showSettings),
                ),
              ),
            ),
          ),

          // 4. The Top / Center Navigation Buttons
          Positioned(
            top: h * 0.15,
            left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CenterButton(button: 'BACK', icon: Icons.arrow_back_ios_new, size: 24),
                SizedBox(width: w * 0.04),
                const GuideButton(size: 44),
                SizedBox(width: w * 0.04),
                const CenterButton(button: 'START', icon: Icons.play_arrow, size: 24),
              ],
            ),
          ),

          // 5. Mouse toggle + R-Click pill (mouse mode only)
          Positioned(
            bottom: h * 0.05,
            left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _MouseToggleButton(
                  mouseMode: _mouseMode,
                  onToggle: () => setState(() => _mouseMode = !_mouseMode),
                ),
                if (_mouseMode) ...[
                  const SizedBox(width: 12),
                  _MouseBtn(button: 'right', label: 'R-Click'),
                ],
              ],
            ),
          ),

          // 6. Left Side Buttons (Triggers, Bumpers, DPad, Analog)
          Positioned(
            top: 28, left: w * 0.02, bottom: h * 0.05,
            child: SizedBox(
              width: w * 0.35,
              child: Stack(
                children: [
                  Positioned(top: h * 0.05, left: w * 0.05, child: const TriggerBar(side: 'left', label: 'LT', width: 56, height: 56)),
                  Positioned(top: h * 0.05, right: w * 0.05, child: const BumperButton(button: 'LB', label: 'LB', width: 56)),
                  Positioned(bottom: h * 0.05, left: 0, child: const ActionButton(button: 'LS', label: 'L3', size: 56)),

                  // D-Pad
                  Positioned(
                    top: h * 0.3,
                    left: w * 0.02,
                    child: const DPad(size: 140),
                  ),
                ],
              ),
            ),
          ),

          // 7. Right Side Buttons (over top of the massive gesture area)
          Positioned(
            top: 28, right: w * 0.02, bottom: h * 0.05,
            child: IgnorePointer(
              // The main container ignores pointers so the background stick can catch misses,
              // but we wrap the actual buttons in an overlay so they catch hits.
              // Actually, Flutter Stack automatically routes hits to children. 
              // We just don't want a solid container blocking the background.
              ignoring: false, 
              child: SizedBox(
                width: w * 0.35,
                child: Stack(
                  children: [
                    Positioned(top: h * 0.05, left: w * 0.05, child: const BumperButton(button: 'RB', label: 'RB', width: 56)),
                    Positioned(top: h * 0.05, right: w * 0.05, child: const TriggerBar(side: 'right', label: 'RT', width: 56, height: 56)),
                    Positioned(bottom: h * 0.05, right: 0, child: const ActionButton(button: 'RS', label: 'R3', size: 56)),
                    
                    // Face Buttons (A, B, X, Y)
                    Positioned(
                      bottom: h * 0.25,
                      right: w * 0.05,
                      child: _FaceButtons(),
                    ),

                    // L-Click: double-tap right area. R-Click: pill next to MOUSE toggle.
                  ],
                ),
              ),
            ),
          ),

          // 8. Settings overlay
          if (_showSettings)
            _SettingsPanel(onClose: () => setState(() => _showSettings = false)),

          // 9. First-launch tutorial
          if (_showTutorial)
            _TutorialOverlay(onDismiss: () => setState(() => _showTutorial = false)),
        ],
      ),
    );
  }

  void _showDialog(BuildContext ctx) =>
      showDialog(context: ctx, builder: (_) => const _IpDialog());
}

/// Unified floating joystick — used IDENTICALLY for both left and right halves.
/// Hidden until touched; spawns at the touch point; same size/style on both sides.
class _FloatingStick extends StatefulWidget {
  const _FloatingStick({
    required this.side,        // 'left' = movement, 'right' = camera
    required this.screenH,
    this.mouseMode = false,    // right side only
  });
  final String side;
  final double screenH;
  final bool   mouseMode;

  @override
  State<_FloatingStick> createState() => _FloatingStickState();
}

class _FloatingStickState extends State<_FloatingStick> {
  int?      _trackId;
  Offset?   _center;
  Offset    _thumb = Offset.zero;
  Offset?   _downPos;
  DateTime? _lastTapTime;

  bool get _isLeft  => widget.side == 'left';
  String get _stick => _isLeft ? 'left_stick' : 'right_stick';

  // Same base radius for BOTH sticks → identical size. Scaled by one setting.
  double get _joyR =>
      widget.screenH * 0.16 * WebSocketService.instance.sensitivity.joyRadius;

  static const _tapSlop     = 12.0;
  static const _doubleTapMs = 320;

  void _sendZero() =>
      WebSocketService.instance.send({'type': _stick, 'x': 0.0, 'y': 0.0});

  void _reset() {
    _trackId = null;
    _downPos = null;
    setState(() { _center = null; _thumb = Offset.zero; });
  }

  void _onDown(PointerDownEvent e) {
    if (_trackId != null) return;   // already tracking a finger
    _trackId = e.pointer;
    _downPos = e.localPosition;

    if (widget.mouseMode) {
      // double-tap → left click
      final now = DateTime.now();
      if (_lastTapTime != null &&
          now.difference(_lastTapTime!).inMilliseconds < _doubleTapMs) {
        WebSocketService.instance.send({'type': 'mouse_click', 'button': 'left'});
        _lastTapTime = null;
      }
      return;
    }
    setState(() { _center = e.localPosition; _thumb = Offset.zero; });
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _trackId) return;

    // ── Mouse / trackpad mode (right side toggle) ──
    if (widget.mouseMode) {
      if (e.delta.distance < 0.5) return;
      final sens = WebSocketService.instance.sensitivity.mouseSensitivity / 10.0;
      WebSocketService.instance.send({
        'type': 'mouse_move',
        'dx': (e.delta.dx * sens).round(),
        'dy': (e.delta.dy * sens).round(),
      });
      return;
    }

    // ── Joystick mode ──
    if (_center == null) return;
    final r = _joyR;
    var offset  = e.localPosition - _center!;
    var center  = _center!;

    // Re-centering: if finger passes the ring edge, the ring follows the finger
    // so you can keep turning/moving continuously (no hard stop at the edge).
    if (offset.distance > r) {
      final unit = offset / offset.distance;
      center = e.localPosition - unit * r;
      offset = unit * r;
    }

    setState(() { _center = center; _thumb = offset; });

    final sens = _isLeft
        ? WebSocketService.instance.sensitivity.stickSensitivity
        : WebSocketService.instance.sensitivity.rightStickSensitivity;
    final dead = WebSocketService.instance.sensitivity.deadZone;
    final nx   = offset.dx / r;
    final ny   = -offset.dy / r;
    final mag  = offset.distance / r;
    final x    = mag < dead ? 0.0 : (nx * sens).clamp(-1.0, 1.0);
    final y    = mag < dead ? 0.0 : (ny * sens).clamp(-1.0, 1.0);

    WebSocketService.instance.send({
      'type': _stick,
      'x': double.parse(x.toStringAsFixed(3)),
      'y': double.parse(y.toStringAsFixed(3)),
    });
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer != _trackId) return;
    if (widget.mouseMode) {
      if (_downPos != null && (e.localPosition - _downPos!).distance < _tapSlop)
        _lastTapTime = DateTime.now();
      _trackId = null;
      _downPos = null;
      return;
    }
    _sendZero();
    _reset();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer != _trackId) return;
    if (!widget.mouseMode) _sendZero();
    _reset();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown:   _onDown,
    onPointerMove:   _onMove,
    onPointerUp:     _onUp,
    onPointerCancel: _onCancel,
    child: CustomPaint(
      // null painter when idle → completely hidden, nothing "stuck" on screen
      painter: _center != null
          ? _StickPainter(center: _center!, thumb: _thumb, radius: _joyR)
          : null,
      child: const SizedBox.expand(),
    ),
  );
}

// ── Stick painter — identical style for both sides ────────────────────────────

class _StickPainter extends CustomPainter {
  const _StickPainter({required this.center, required this.thumb, required this.radius});
  final Offset center;
  final Offset thumb;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    // Outer + inner rings — same color/thickness/opacity on both sticks
    final ring = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius,       ring);
    canvas.drawCircle(center, radius * 0.7, ring);

    // Gray dotted thumb — identical to the original left stick
    final tp     = center + thumb;
    final thumbR = radius * 0.38;
    canvas.drawCircle(tp, thumbR,
        Paint()..color = const Color(0xFFC0C0C0)..style = PaintingStyle.fill);

    final dot     = Paint()..color = const Color(0xFF888888)..style = PaintingStyle.fill;
    final spacing = thumbR * 0.25;
    final sx = tp.dx - 2 * spacing;
    final sy = tp.dy - 2 * spacing;
    for (int i = 0; i < 5; i++) {
      for (int j = 0; j < 5; j++) {
        final dx = sx + j * spacing - tp.dx;
        final dy = sy + i * spacing - tp.dy;
        if (dx * dx + dy * dy < (thumbR * 0.6) * (thumbR * 0.6))
          canvas.drawCircle(Offset(sx + j * spacing, sy + i * spacing), 1.5, dot);
      }
    }
  }

  @override
  bool shouldRepaint(_StickPainter o) =>
      o.center != center || o.thumb != thumb || o.radius != radius;
}

class _MouseToggleButton extends StatelessWidget {
  const _MouseToggleButton({required this.mouseMode, required this.onToggle});
  final bool mouseMode;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onToggle,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: mouseMode ? Colors.white24 : Colors.transparent,
        border: Border.all(
          color: mouseMode ? Colors.white : const Color(0x66FFFFFF),
          width: 1.5,
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mouse, size: 13, color: mouseMode ? Colors.white : Colors.white60),
        const SizedBox(width: 6),
        Text('MOUSE', style: TextStyle(
          color: mouseMode ? Colors.white : Colors.white60,
          fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2,
        )),
      ]),
    ),
  );
}

// ── Face buttons ──────────────────────────────────────────────────────────────

class _FaceButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 150, height: 150,
    child: Stack(alignment: Alignment.center, children: [
      Positioned(top: 0,    child: ActionButton(button: 'Y', size: 52)),
      Positioned(left: 0,   child: ActionButton(button: 'X', size: 52)),
      Positioned(right: 0,  child: ActionButton(button: 'B', size: 52)),
      Positioned(bottom: 0, child: ActionButton(button: 'A', size: 52)),
    ]),
  );
}

// ── Mouse click buttons ───────────────────────────────────────────────────────

class _MouseBtn extends StatefulWidget {
  const _MouseBtn({required this.button, required this.label});
  final String button, label;
  @override
  State<_MouseBtn> createState() => _MouseBtnState();
}

class _MouseBtnState extends State<_MouseBtn> {
  bool _p = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTapDown: (_) {
      setState(() => _p = true);
      WebSocketService.instance.send({'type': 'mouse_click', 'button': widget.button});
    },
    onTapUp: (_) => setState(() => _p = false),
    onTapCancel: () => setState(() => _p = false),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 60),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: _p ? Colors.white24 : Colors.transparent,
        border: Border.all(color: _p ? Colors.white : const Color(0x66FFFFFF)),
      ),
      child: Text(widget.label, style: const TextStyle(color: Colors.white, fontSize: 10)),
    ),
  );
}

// ── Settings panel ────────────────────────────────────────────────────────────

class _SettingsPanel extends StatefulWidget {
  const _SettingsPanel({required this.onClose});
  final VoidCallback onClose;
  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  late double _leftStick;
  late double _rightStick;
  late double _dead;
  late double _mouse;
  late bool   _vibration;
  late double _joyRadius;

  @override
  void initState() {
    super.initState();
    final s     = WebSocketService.instance.sensitivity;
    _leftStick  = s.stickSensitivity;
    _rightStick = s.rightStickSensitivity;
    _dead       = s.deadZone;
    _mouse      = s.mouseSensitivity;
    _vibration  = s.vibration;
    _joyRadius  = s.joyRadius;
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black.withOpacity(0.82),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: (sz.width * 0.52).clamp(300.0, 420.0),
              constraints: BoxConstraints(maxHeight: sz.height * 0.9),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF252535)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _header(),
                const Divider(color: Color(0xFF252535), height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(children: [
                      _section('CONTROLS'),
                      _toggleRow('Vibration', _vibration, (v) {
                        setState(() => _vibration = v);
                        WebSocketService.instance.sensitivity.vibration = v;
                      }),
                      _section('SENSITIVITY'),
                      _sliderRow('Left Stick',  _leftStick,  0.3,  2.0,  (v) {
                        setState(() => _leftStick = v);
                        WebSocketService.instance.sensitivity.stickSensitivity = v;
                      }),
                      _sliderRow('Right Stick',  _rightStick, 0.5,  3.0, (v) {
                        setState(() => _rightStick = v);
                        WebSocketService.instance.sensitivity.rightStickSensitivity = v;
                      }),
                      _sliderRow('Stick Size', _joyRadius, 0.5, 2.0, (v) {
                        setState(() => _joyRadius = v);
                        WebSocketService.instance.sensitivity.joyRadius = v;
                      }),
                      _sliderRow('Dead Zone',   _dead,       0.01, 0.25, (v) {
                        setState(() => _dead = v);
                        WebSocketService.instance.sensitivity.deadZone = v;
                      }),
                      _section('MOUSE'),
                      _sliderRow('Speed', _mouse, 5, 40, (v) {
                        setState(() => _mouse = v);
                        WebSocketService.instance.sensitivity.mouseSensitivity = v;
                      }),
                      const SizedBox(height: 12),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
    child: Row(children: [
      const Text('SETTINGS', style: TextStyle(
        color: Colors.white, fontSize: 12,
        fontWeight: FontWeight.bold, letterSpacing: 2.5,
      )),
      const Spacer(),
      GestureDetector(
        onTap: widget.onClose,
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF3A3A55)),
          ),
          child: const Icon(Icons.close, color: Colors.white54, size: 14),
        ),
      ),
    ]),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 2),
    child: Row(children: [
      Text(title, style: const TextStyle(
        color: Color(0xFF00D4FF), fontSize: 9,
        fontWeight: FontWeight.bold, letterSpacing: 2,
      )),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 1, color: const Color(0x1A00D4FF))),
    ]),
  );

  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
    child: Row(children: [
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      const Spacer(),
      _TogglePair(value: value, onChanged: onChanged),
    ]),
  );

  Widget _sliderRow(String label, double value, double min, double max,
      ValueChanged<double> onChanged) =>
    Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF3A3A55)),
            ),
            child: Text(value.toStringAsFixed(2), style: const TextStyle(
              color: Color(0xFF00D4FF), fontSize: 11, fontWeight: FontWeight.bold,
            )),
          ),
        ]),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: const Color(0xFF00D4FF),
            inactiveTrackColor: const Color(0xFF252535),
            thumbColor: Colors.white,
            overlayColor: const Color(0x1500D4FF),
          ),
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
      ]),
    );
}

// ── Toggle pair (✓ ON / ✗ OFF) ────────────────────────────────────────────────

class _TogglePair extends StatelessWidget {
  const _TogglePair({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    _ToggleBtn(
      label: 'ON',  icon: Icons.check,
      active: value,  activeColor: const Color(0xFF00D4FF),
      onTap: () => onChanged(true),  isLeft: true,
    ),
    _ToggleBtn(
      label: 'OFF', icon: Icons.close,
      active: !value, activeColor: const Color(0xFFE53935),
      onTap: () => onChanged(false), isLeft: false,
    ),
  ]);
}

class _ToggleBtn extends StatelessWidget {
  const _ToggleBtn({
    required this.label,    required this.icon,
    required this.active,   required this.activeColor,
    required this.onTap,    required this.isLeft,
  });
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final bool isLeft;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: active ? activeColor.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.horizontal(
          left:  isLeft  ? const Radius.circular(7) : Radius.zero,
          right: !isLeft ? const Radius.circular(7) : Radius.zero,
        ),
        border: Border.all(
          color: active ? activeColor : const Color(0xFF3A3A55),
        ),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: active ? activeColor : Colors.white24),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(
          color: active ? activeColor : Colors.white24,
          fontSize: 11,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        )),
      ]),
    ),
  );
}

// ── Background glow ───────────────────────────────────────────────────────────

class _BgGlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GlowPainter(), size: Size.infinite);
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    // Cross-hatch subtle background pattern matching the reference image
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.02)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
      
    final int spacing = 40;
    
    // Draw diagonal lines
    for (double i = -s.height; i < s.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i + s.height, s.height), paint);
    }
    for (double i = s.width + s.height; i > 0; i -= spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i - s.height, s.height), paint);
    }

    // Retain subtle glow
    final p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    p.color = Colors.white.withOpacity(0.03);
    canvas.drawCircle(Offset(s.width * 0.2, s.height * 0.5), s.width * 0.3, p);
    canvas.drawCircle(Offset(s.width * 0.8, s.height * 0.5), s.width * 0.3, p);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Connection chip + Settings button ─────────────────────────────────────────

class _ConnChip extends StatefulWidget {
  const _ConnChip({required this.state, required this.ip, required this.onTap});
  final ws.ConnectionState state;
  final String ip;
  final VoidCallback onTap;
  @override State<_ConnChip> createState() => _ConnChipState();
}

class _ConnChipState extends State<_ConnChip> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }
  @override void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    Color dotColor; String label;
    switch (widget.state) {
      case ws.ConnectionState.connected:
        dotColor = const Color(0xFF1DB954); label = 'Connected';
      case ws.ConnectionState.connecting:
        dotColor = const Color(0xFFF9A825); label = 'Connecting';
      case ws.ConnectionState.disconnected:
        dotColor = const Color(0xFFE53935); label = 'Offline';
    }
    final dot = Container(
      width: 7, height: 7,
      decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
    );
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
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10)),
          if (widget.ip.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(widget.ip, style: const TextStyle(color: Colors.white30, fontSize: 9)),
          ],
        ]),
      ),
    );
  }
}

class _SettingsBtn extends StatelessWidget {
  const _SettingsBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12, width: 1),
      ),
      child: const Icon(Icons.settings, color: Colors.white60, size: 16),
    ),
  );
}

// ── Tutorial overlay (first launch) ──────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  const _TutorialOverlay({required this.onDismiss});
  final VoidCallback onDismiss;
  @override State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, value: 1.0,
        duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }
  @override void dispose() { _fade.dispose(); super.dispose(); }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) widget.onDismiss();
  }

  Widget _half(String title, String sub, IconData icon, Alignment align) =>
    Align(alignment: align, child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align == Alignment.centerLeft
            ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.45), size: 34),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.6),
              fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.3),
              fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    ));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: GestureDetector(
      onTap: _dismiss,
      child: Container(
        color: Colors.black.withOpacity(0.55),
        child: Stack(children: [
          // Vertical divider
          Center(child: Container(width: 1, color: Colors.white.withOpacity(0.1))),
          // Left label
          _half('MOVE', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerLeft),
          // Right label
          _half('CAMERA', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerRight),
          // Bottom hint
          Align(alignment: Alignment.bottomCenter, child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text('tap to dismiss',
              style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 10)),
          )),
        ]),
      ),
    ),
  );
}

// ── IP dialog ─────────────────────────────────────────────────────────────────

class _IpDialog extends StatefulWidget {
  const _IpDialog();
  @override State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  final _ctrl    = TextEditingController();
  final _focusNode = FocusNode();
  bool _scanning = false;
  MobileScannerController? _qrCtrl;
  late StreamSubscription<ws.ConnectionState> _sub;
  ws.ConnectionState _conn = WebSocketService.instance.state;

  @override
  void initState() {
    super.initState();
    _sub = WebSocketService.instance.stateStream.listen((s) {
      setState(() => _conn = s);
      if (s == ws.ConnectionState.connected) {
        Future.delayed(const Duration(milliseconds: 600), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
  }

  @override
  void dispose() {
    _sub.cancel(); _ctrl.dispose(); _qrCtrl?.dispose(); super.dispose();
  }

  void _connect() {
    final ip = _ctrl.text.trim();
    if (ip.isNotEmpty) WebSocketService.instance.setManualIp(ip);
  }

  void _onDetect(BarcodeCapture capture) {
    final code = capture.barcodes.firstOrNull?.rawValue ?? '';
    final uri  = Uri.tryParse(code);
    if (uri != null && uri.host.isNotEmpty) {
      _qrCtrl?.stop();
      WebSocketService.instance.setManualIp(uri.host);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Container(
          width: 360,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF12121E),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF3A3A55)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Header
            Row(children: [
              const Text('Connect to PC',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 10, height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _conn == ws.ConnectionState.connected
                      ? const Color(0xFF1DB954)
                      : _conn == ws.ConnectionState.connecting
                          ? const Color(0xFFF9A825)
                          : const Color(0xFFE53935),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                labelText: 'PC IP Address',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            if (_scanning)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: MobileScanner(
                    controller: _qrCtrl ??= MobileScannerController(),
                    onDetect: _onDetect,
                    errorBuilder: (context, error, child) {
                      return const Center(child: Text('Camera error. Check permissions.', style: TextStyle(color: Colors.redAccent)));
                    },
                  ),
                ),
              ),
            Row(children: [
              TextButton.icon(
                onPressed: () async {
                  if (!_scanning) {
                    final status = await Permission.camera.request();
                    if (status.isGranted) {
                      setState(() => _scanning = true);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Camera permission required to scan QR')),
                        );
                      }
                    }
                  } else {
                    setState(() => _scanning = false);
                    _qrCtrl?.stop();
                  }
                },
                icon: Icon(_scanning ? Icons.camera_alt_outlined : Icons.qr_code_scanner, color: Colors.white54),
                label: Text(_scanning ? 'Hide' : 'Scan QR', style: const TextStyle(color: Colors.white54)),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _connect,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                child: const Text('Connect', style: TextStyle(color: Colors.black)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
