import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/websocket_service.dart';
import '../services/websocket_service.dart' as ws;
import '../widgets/analog_stick.dart';
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub = WebSocketService.instance.stateStream.listen((s) => setState(() => _conn = s));
    WebSocketService.instance.init();
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

          // 2. The massive right/middle touch zone for the Right Stick
          Positioned(
            left: w * 0.35,
            top: 28, // below status bar
            right: 0,
            bottom: 0,
            child: _MassiveRightStick(mouseMode: _mouseMode),
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

          // 5. Mouse Toggle Button in bottom center
          Positioned(
            bottom: h * 0.05,
            left: 0, right: 0,
            child: Align(
              alignment: Alignment.center,
              child: _MouseToggleButton(
                mouseMode: _mouseMode,
                onToggle: () => setState(() => _mouseMode = !_mouseMode),
              ),
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
                  
                  // Left Stick
                  Positioned(
                    bottom: h * 0.05,
                    right: w * 0.02,
                    child: AnalogStick(side: 'left', button: 'LS', size: h * 0.35,
                      sensitivity: WebSocketService.instance.sensitivity.stickSensitivity,
                      deadZone:    WebSocketService.instance.sensitivity.deadZone),
                  ),

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

                    if (_mouseMode)
                      Positioned(
                        bottom: h * 0.1, left: w * 0.05,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          _MouseBtn(button: 'left',  label: 'L-Click'),
                          const SizedBox(width: 8),
                          _MouseBtn(button: 'right', label: 'R-Click'),
                        ]),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // 8. Settings overlay
          if (_showSettings)
            _SettingsPanel(onClose: () => setState(() => _showSettings = false)),
        ],
      ),
    );
  }

  void _showDialog(BuildContext ctx) =>
      showDialog(context: ctx, builder: (_) => const _IpDialog());
}

/// A massive gesture detector that sends Right Stick (or Mouse) data
class _MassiveRightStick extends StatefulWidget {
  const _MassiveRightStick({required this.mouseMode});
  final bool mouseMode;

  @override
  State<_MassiveRightStick> createState() => _MassiveRightStickState();
}

class _MassiveRightStickState extends State<_MassiveRightStick> {
  // Raw Listener approach: bypasses Flutter's gesture arena entirely.
  // Buttons can never steal or cancel this pointer tracking.
  int? _trackId;

  void _onDown(PointerDownEvent e) {
    _trackId ??= e.pointer; // claim the first finger that lands
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _trackId) return;
    if (e.delta.distance < 0.5) return;

    // Always mouse_move — no ±1.0 cap, so 180s/360s are possible.
    // Game mode = Camera Speed setting; MOUSE mode = Mouse Speed setting.
    final double speed = widget.mouseMode
        ? WebSocketService.instance.sensitivity.mouseSensitivity / 10.0
        : WebSocketService.instance.sensitivity.rightStickSensitivity * 0.3;

    WebSocketService.instance.send({
      'type': 'mouse_move',
      'dx': (e.delta.dx * speed).round(),
      'dy': (e.delta.dy * speed).round(),
    });
  }

  void _onUp(PointerUpEvent e) {
    if (e.pointer == _trackId) _trackId = null;
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer == _trackId) _trackId = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown:   _onDown,
    onPointerMove:   _onMove,
    onPointerUp:     _onUp,
    onPointerCancel: _onCancel,
    child: Container(color: Colors.transparent),
  );
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

  @override
  void initState() {
    super.initState();
    final s     = WebSocketService.instance.sensitivity;
    _leftStick  = s.stickSensitivity;
    _rightStick = s.rightStickSensitivity;
    _dead       = s.deadZone;
    _mouse      = s.mouseSensitivity;
    _vibration  = s.vibration;
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
                      _sliderRow('Camera Speed', _rightStick, 1.0, 30.0, (v) {
                        setState(() => _rightStick = v);
                        WebSocketService.instance.sensitivity.rightStickSensitivity = v;
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
