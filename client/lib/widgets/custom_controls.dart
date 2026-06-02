import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../games/custom_layout.dart';
import '../services/websocket_service.dart';
import 'trigger_button.dart';
import 'action_button.dart';
import 'forza_controls.dart';

const _kAccent  = Color(0xFF00D4FF);
const _kRest    = Color(0x66FFFFFF);
const _kRestDim = Color(0x33FFFFFF);
const _kFill    = Color(0x2200D4FF);

bool get _vib => WebSocketService.instance.sensitivity.vibration;

/// Footprint of a control (most are square; mouse pad is wide, pedal is tall).
Size controlFootprint(ControlItem i) {
  switch (i.kind) {
    case ControlKind.mousepad: return Size(i.size, i.size * 0.66);
    case ControlKind.pedal:    return Size(i.size, i.size * 1.4);
    default:                   return Size(i.size, i.size);
  }
}

/// Builds the LIVE control for a placed item (used in play mode). The editor
/// wraps this in IgnorePointer so it shows the real thing without firing.
/// [applyOpacity] is false in the editor so faded controls stay easy to grab.
Widget buildCustomControl(ControlItem item, {bool applyOpacity = true}) {
  final child = _rawControl(item);
  if (!applyOpacity || item.opacity >= 0.999) return child;
  return Opacity(opacity: item.opacity.clamp(0.1, 1.0), child: child);
}

Widget _rawControl(ControlItem item) {
  switch (item.kind) {
    case ControlKind.button:
      return _CustomButton(item: item);
    case ControlKind.stick:
      return _CustomStick(item: item);
    case ControlKind.trigger:
      final left = item.action == 'trig:left';
      return TriggerBar(
        side: left ? 'left' : 'right',
        label: left ? 'LT' : 'RT',
        width: item.size, height: item.size,
      );
    case ControlKind.dpad:
      return DPad(size: item.size);
    case ControlKind.mousepad:
      return _CustomMousePad(item: item);
    case ControlKind.wheel:
      return _CustomWheel(item: item);
    case ControlKind.pedal:
      final gas = item.action == 'pedal:gas';
      return RacePedal(
        gas: gas,
        label: gas ? 'GAS' : 'BRAKE',
        icon: gas ? Icons.local_gas_station : Icons.front_hand,
        width: item.size, height: item.size * 1.4,
      );
  }
}

// ── Button: gamepad / keyboard / mouse, momentary (press = down, release = up) ──

class _CustomButton extends StatefulWidget {
  const _CustomButton({required this.item});
  final ControlItem item;
  @override
  State<_CustomButton> createState() => _CustomButtonState();
}

class _CustomButtonState extends State<_CustomButton> {
  int? _ptr;
  bool get _down => _ptr != null;

  void _press(PointerDownEvent e) {
    if (_ptr != null) return;
    setState(() => _ptr = e.pointer);
    final a = widget.item.action;
    final s = WebSocketService.instance;
    if (a.startsWith('gp:')) {
      s.send({'type': 'button_press', 'button': a.substring(3)});
    } else if (a.startsWith('key:')) {
      s.send({'type': 'key_down', 'key': a.substring(4)});
    } else if (a == 'mouse:left') {
      s.send({'type': 'mouse_down', 'button': 'left'});
    } else if (a == 'mouse:right') {
      s.send({'type': 'mouse_down', 'button': 'right'});
    }
    if (_vib) HapticFeedback.mediumImpact();
  }

  void _release(PointerEvent e) {
    if (e.pointer != _ptr) return;
    setState(() => _ptr = null);
    final a = widget.item.action;
    final s = WebSocketService.instance;
    if (a.startsWith('gp:')) {
      s.send({'type': 'button_release', 'button': a.substring(3)});
    } else if (a.startsWith('key:')) {
      s.send({'type': 'key_up', 'key': a.substring(4)});
    } else if (a == 'mouse:left') {
      s.send({'type': 'mouse_up', 'button': 'left'});
    } else if (a == 'mouse:right') {
      s.send({'type': 'mouse_up', 'button': 'right'});
    }
    if (_vib) HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.item.label.isNotEmpty
        ? widget.item.label
        : actionLabel(widget.item.action);
    final fs = (widget.item.size * (text.length > 3 ? 0.24 : 0.36)).clamp(9.0, 30.0);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _press,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        width: widget.item.size,
        height: widget.item.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _down ? _kFill : Colors.transparent,
          border: Border.all(color: _down ? _kAccent : _kRest, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Stick (fixed position, analog) ────────────────────────────────────────────

class _CustomStick extends StatefulWidget {
  const _CustomStick({required this.item});
  final ControlItem item;
  @override
  State<_CustomStick> createState() => _CustomStickState();
}

class _CustomStickState extends State<_CustomStick> {
  int? _ptr;
  Offset _thumb = Offset.zero;

  String get _msg => widget.item.action == 'stick:right' ? 'right_stick' : 'left_stick';
  double get _r => widget.item.size / 2;

  void _update(Offset pos) {
    final c = Offset(_r, _r);
    var off = pos - c;
    if (off.distance > _r) off = off / off.distance * _r;
    setState(() => _thumb = off);
    final s = WebSocketService.instance.sensitivity;
    final sens = widget.item.action == 'stick:right'
        ? s.rightStickSensitivity
        : s.stickSensitivity;
    final nx = off.dx / _r, ny = -off.dy / _r, mag = off.distance / _r;
    final x = mag < s.deadZone ? 0.0 : (nx * sens).clamp(-1.0, 1.0);
    final y = mag < s.deadZone ? 0.0 : (ny * sens).clamp(-1.0, 1.0);
    WebSocketService.instance.send({
      'type': _msg,
      'x': double.parse(x.toStringAsFixed(3)),
      'y': double.parse(y.toStringAsFixed(3)),
    });
  }

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _update(e.localPosition);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    _update(e.localPosition);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    setState(() => _thumb = Offset.zero);
    WebSocketService.instance.send({'type': _msg, 'x': 0.0, 'y': 0.0});
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: CustomPaint(
          painter: _StickPaint(thumb: _thumb, radius: _r),
          child: SizedBox(width: widget.item.size, height: widget.item.size),
        ),
      );
}

class _StickPaint extends CustomPainter {
  const _StickPaint({required this.thumb, required this.radius});
  final Offset thumb;
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final ring = Paint()
      ..color = _kRest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(c, radius, ring);
    canvas.drawCircle(c, radius * 0.7, ring);
    final tp = c + thumb;
    canvas.drawCircle(tp, radius * 0.36,
        Paint()..color = const Color(0xFFC0C0C0)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_StickPaint o) => o.thumb != thumb || o.radius != radius;
}

// ── Mouse pad (drag = move cursor, tap = left click) ──────────────────────────

class _CustomMousePad extends StatefulWidget {
  const _CustomMousePad({required this.item});
  final ControlItem item;
  @override
  State<_CustomMousePad> createState() => _CustomMousePadState();
}

class _CustomMousePadState extends State<_CustomMousePad> {
  int? _ptr;
  Offset? _down;
  bool _moved = false;

  void _onDown(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _down = e.localPosition;
    _moved = false;
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    if (e.delta.distance < 0.5) return;
    _moved = true;
    final sens = WebSocketService.instance.sensitivity.mouseSensitivity / 10.0;
    WebSocketService.instance.send({
      'type': 'mouse_move',
      'dx': (e.delta.dx * sens).round(),
      'dy': (e.delta.dy * sens).round(),
    });
  }

  void _onUp(PointerEvent e) {
    if (e.pointer != _ptr) return;
    if (!_moved) WebSocketService.instance.send({'type': 'mouse_click', 'button': 'left'});
    _ptr = null;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.item.size, h = widget.item.size * 0.66;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onDown,
      onPointerMove: _onMove,
      onPointerUp: _onUp,
      onPointerCancel: _onUp,
      child: Container(
        width: w, height: h,
        decoration: BoxDecoration(
          color: _kFill.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kRestDim, width: 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
          Icon(Icons.mouse, color: Colors.white38, size: 22),
          SizedBox(height: 6),
          Text('MOUSE', style: TextStyle(
            color: Colors.white38, fontSize: 9,
            fontWeight: FontWeight.bold, letterSpacing: 2)),
        ]),
      ),
    );
  }
}

// ── Placeable steering wheel (drag left/right to steer → left stick) ──────────

class _CustomWheel extends StatefulWidget {
  const _CustomWheel({required this.item});
  final ControlItem item;
  @override
  State<_CustomWheel> createState() => _CustomWheelState();
}

class _CustomWheelState extends State<_CustomWheel> {
  int? _ptr;
  double _startX = 0;
  double _angle = 0;
  double _value = 0;

  double get _range => widget.item.size * 0.5;

  void _send(double x) => WebSocketService.instance.send({
        'type': 'left_stick',
        'x': double.parse(x.toStringAsFixed(3)),
        'y': 0.0,
      });

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _startX = e.localPosition.dx;
    if (_vib) HapticFeedback.selectionClick();
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    final raw = ((e.localPosition.dx - _startX) / _range).clamp(-1.0, 1.0);
    final s = WebSocketService.instance.sensitivity;
    final v = raw.abs() < s.deadZone ? 0.0 : (raw * s.stickSensitivity).clamp(-1.0, 1.0);
    setState(() { _value = v; _angle = raw * (pi * 0.55); });
    _send(v);
  }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    setState(() { _value = 0; _angle = 0; });
    _send(0.0);
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: CustomPaint(
          painter: _CustomWheelPainter(diameter: widget.item.size, angle: _angle, value: _value),
          child: SizedBox(width: widget.item.size, height: widget.item.size),
        ),
      );
}

class _CustomWheelPainter extends CustomPainter {
  const _CustomWheelPainter({required this.diameter, required this.angle, required this.value});
  final double diameter, angle, value;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = diameter / 2 - 2;
    final accent = Color.lerp(_kRest, _kAccent, value.abs())!;
    canvas.drawCircle(c, r, Paint()
      ..color = accent..style = PaintingStyle.stroke..strokeWidth = r * 0.10);
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    final spoke = Paint()
      ..color = accent..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-r * 0.55, 0), Offset(r * 0.55, 0), spoke);
    canvas.drawLine(const Offset(0, 0), Offset(0, r * 0.55), spoke);
    canvas.drawCircle(Offset.zero, r * 0.16, Paint()..color = accent);
    canvas.drawLine(Offset(0, -r * 0.55), Offset(0, -r * 0.86), Paint()
      ..color = _kAccent.withOpacity(0.4 + 0.6 * value.abs())
      ..style = PaintingStyle.stroke..strokeWidth = r * 0.07..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CustomWheelPainter o) =>
      o.angle != angle || o.value != value || o.diameter != diameter;
}
