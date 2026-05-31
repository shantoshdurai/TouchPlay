import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
          _BgGlow(),
          Column(
            children: [
              // ── Status bar ───────────────────────────────────────────
              _StatusBar(
                state: _conn,
                ip: WebSocketService.instance.currentIp ?? '',
                onTap: () => _showDialog(context),
                onSettings: () => setState(() => _showSettings = !_showSettings),
              ),

              // ── Triggers ─────────────────────────────────────────────
              SizedBox(
                height: h * 0.13,
                child: Row(children: [
                  TriggerBar(side: 'left',  label: 'LT', width: w * 0.28, height: double.infinity),
                  const Spacer(),
                  TriggerBar(side: 'right', label: 'RT', width: w * 0.28, height: double.infinity),
                ]),
              ),

              // ── Bumpers ───────────────────────────────────────────────
              SizedBox(
                height: h * 0.09,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.03, vertical: 6),
                  child: Row(children: [
                    BumperButton(button: 'LB', label: 'LB', width: w * 0.22),
                    const Spacer(),
                    BumperButton(button: 'RB', label: 'RB', width: w * 0.22),
                  ]),
                ),
              ),

              // ── Main body ─────────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.01),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _LeftSide(h: h),
                      const Spacer(),
                      _CenterCluster(
                        mouseMode: _mouseMode,
                        onMouseToggle: () => setState(() => _mouseMode = !_mouseMode),
                      ),
                      const Spacer(),
                      _RightSide(mouseMode: _mouseMode, h: h),
                    ],
                  ),
                ),
              ),
              SizedBox(height: h * 0.015),
            ],
          ),

          // ── Settings overlay ──────────────────────────────────────────
          if (_showSettings)
            _SettingsPanel(onClose: () => setState(() => _showSettings = false)),
        ],
      ),
    );
  }

  void _showDialog(BuildContext ctx) =>
      showDialog(context: ctx, builder: (_) => const _IpDialog());
}

// ── Left side ────────────────────────────────────────────────────────────────

class _LeftSide extends StatelessWidget {
  const _LeftSide({required this.h});
  final double h;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      AnalogStick(side: 'left', button: 'LS', size: h * 0.25,
          sensitivity: WebSocketService.instance.sensitivity.stickSensitivity,
          deadZone:    WebSocketService.instance.sensitivity.deadZone),
      SizedBox(height: h * 0.03),
      const DPad(size: 108),
    ],
  );
}

// ── Right side ────────────────────────────────────────────────────────────────

class _RightSide extends StatelessWidget {
  const _RightSide({required this.mouseMode, required this.h});
  final bool mouseMode;
  final double h;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      _FaceButtons(),
      SizedBox(height: h * 0.03),
      AnalogStick(
        side: 'right', button: 'RS', size: h * 0.22,
        mouseMode: mouseMode,
        mouseSensitivity: WebSocketService.instance.sensitivity.mouseSensitivity,
        sensitivity:      WebSocketService.instance.sensitivity.stickSensitivity,
        deadZone:         WebSocketService.instance.sensitivity.deadZone,
      ),
      if (mouseMode) ...[
        const SizedBox(height: 6),
        Row(mainAxisSize: MainAxisSize.min, children: [
          _MouseBtn(button: 'left',  label: 'L-Click'),
          const SizedBox(width: 8),
          _MouseBtn(button: 'right', label: 'R-Click'),
        ]),
      ],
    ],
  );
}

// ── Center cluster ────────────────────────────────────────────────────────────

class _CenterCluster extends StatelessWidget {
  const _CenterCluster({required this.mouseMode, required this.onMouseToggle});
  final bool mouseMode;
  final VoidCallback onMouseToggle;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        CenterButton(button: 'BACK',  icon: Icons.menu,  size: 32),
        const SizedBox(width: 10),
        const GuideButton(size: 46),
        const SizedBox(width: 10),
        CenterButton(button: 'START', icon: Icons.pause, size: 32),
      ]),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: onMouseToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: mouseMode ? const Color(0xFFFF6B35).withOpacity(0.2) : const Color(0xFF1A1A2E),
            border: Border.all(
              color: mouseMode ? const Color(0xFFFF6B35) : const Color(0xFF3A3A55),
              width: 1.5,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mouse, size: 13, color: mouseMode ? const Color(0xFFFF6B35) : Colors.white38),
            const SizedBox(width: 4),
            Text('MOUSE', style: TextStyle(
              color: mouseMode ? const Color(0xFFFF6B35) : Colors.white30,
              fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.2,
            )),
          ]),
        ),
      ),
    ],
  );
}

// ── Face buttons ──────────────────────────────────────────────────────────────

class _FaceButtons extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 140, height: 140,
    child: Stack(alignment: Alignment.center, children: [
      Positioned(top: 0,    left: 46, child: ActionButton(button: 'Y', size: 48)),
      Positioned(left: 0,   top: 46,  child: ActionButton(button: 'X', size: 48)),
      Positioned(right: 0,  top: 46,  child: ActionButton(button: 'B', size: 48)),
      Positioned(bottom: 0, left: 46, child: ActionButton(button: 'A', size: 48)),
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
        color: _p ? const Color(0xFFFF6B35) : const Color(0xFF1E1E30),
        border: Border.all(color: const Color(0xFFFF6B35)),
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
  late double _stick;
  late double _dead;
  late double _mouse;

  @override
  void initState() {
    super.initState();
    final s = WebSocketService.instance.sensitivity;
    _stick = s.stickSensitivity;
    _dead  = s.deadZone;
    _mouse = s.mouseSensitivity;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onClose,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF12121E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF3A3A55)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  const Text('Settings', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(onTap: widget.onClose,
                    child: const Icon(Icons.close, color: Colors.white54)),
                ]),
                const SizedBox(height: 20),
                _slider('Stick Sensitivity', _stick, 0.3, 2.0, (v) {
                  setState(() => _stick = v);
                  WebSocketService.instance.sensitivity.stickSensitivity = v;
                }),
                _slider('Dead Zone', _dead, 0.01, 0.25, (v) {
                  setState(() => _dead = v);
                  WebSocketService.instance.sensitivity.deadZone = v;
                }),
                _slider('Mouse Speed', _mouse, 5, 40, (v) {
                  setState(() => _mouse = v);
                  WebSocketService.instance.sensitivity.mouseSensitivity = v;
                }),
                const SizedBox(height: 8),
                const Text('Tap anywhere outside to close',
                    style: TextStyle(color: Colors.white24, fontSize: 11)),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _slider(String label, double val, double min, double max, ValueChanged<double> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        Text(val.toStringAsFixed(2), style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 13)),
      ]),
      Slider(
        value: val, min: min, max: max,
        activeColor: const Color(0xFF00D4FF),
        inactiveColor: const Color(0xFF2A2A40),
        onChanged: onChanged,
      ),
      const SizedBox(height: 4),
    ]);
  }
}

// ── Background glow ───────────────────────────────────────────────────────────

class _BgGlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GlowPainter());
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 80);
    p.color = const Color(0xFF00D4FF).withOpacity(0.04);
    canvas.drawCircle(Offset(s.width * 0.15, s.height * 0.5), s.width * 0.25, p);
    p.color = const Color(0xFF7B2FFF).withOpacity(0.04);
    canvas.drawCircle(Offset(s.width * 0.85, s.height * 0.5), s.width * 0.25, p);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Status bar ────────────────────────────────────────────────────────────────

class _StatusBar extends StatefulWidget {
  const _StatusBar({required this.state, required this.ip, required this.onTap, required this.onSettings});
  final ws.ConnectionState state;
  final String ip;
  final VoidCallback onTap, onSettings;
  @override State<_StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<_StatusBar> with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }
  @override void dispose() { _pulse.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    Color dot; String label;
    switch (widget.state) {
      case ws.ConnectionState.connected:
        dot = const Color(0xFF1DB954); label = 'Connected';
      case ws.ConnectionState.connecting:
        dot = const Color(0xFFF9A825); label = 'Connecting…';
      case ws.ConnectionState.disconnected:
        dot = const Color(0xFFE53935); label = 'Disconnected';
    }
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        height: 28, color: const Color(0xFF0D0D18),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          widget.state == ws.ConnectionState.connecting
              ? FadeTransition(opacity: _pulse, child: _Dot(color: dot))
              : _Dot(color: dot),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
          if (widget.ip.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(widget.ip, style: const TextStyle(color: Colors.white30, fontSize: 10)),
          ],
          const SizedBox(width: 4),
          Text('• tap to change IP', style: TextStyle(color: Colors.white.withOpacity(0.12), fontSize: 9)),
          const Spacer(),
          GestureDetector(
            onTap: widget.onSettings,
            child: const Icon(Icons.tune, color: Colors.white38, size: 16),
          ),
        ]),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
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
              // Live connection dot
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
              const SizedBox(width: 6),
              Text(
                _conn == ws.ConnectionState.connected ? 'Connected!' :
                _conn == ws.ConnectionState.connecting ? 'Trying…' : 'Not connected',
                style: TextStyle(
                  color: _conn == ws.ConnectionState.connected
                      ? const Color(0xFF1DB954) : Colors.white38,
                  fontSize: 12,
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // IP input — clearly visible above keyboard
            TextField(
              controller: _ctrl,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 1),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                labelText: 'PC IP Address',
                labelStyle: const TextStyle(color: Colors.white54),
                hintText: 'e.g. 192.168.1.5',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF1A1A2E),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3A3A55))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3A3A55))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00D4FF), width: 2)),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white38),
                  onPressed: () => _ctrl.clear(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Your PC IP is shown in the server terminal window',
              style: TextStyle(color: Colors.white38, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // QR scanner
            if (_scanning)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  child: MobileScanner(
                    controller: _qrCtrl ??= MobileScannerController(),
                    onDetect: _onDetect,
                  ),
                ),
              ),
            if (_scanning) const SizedBox(height: 12),

            // Buttons
            Row(children: [
              TextButton.icon(
                onPressed: () => setState(() {
                  _scanning = !_scanning;
                  if (!_scanning) _qrCtrl?.stop();
                }),
                icon: Icon(_scanning ? Icons.camera_alt_outlined : Icons.qr_code_scanner,
                    size: 16, color: Colors.white54),
                label: Text(_scanning ? 'Hide QR' : 'Scan QR',
                    style: const TextStyle(color: Colors.white54)),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _connect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D4FF),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: const Text('Connect',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
