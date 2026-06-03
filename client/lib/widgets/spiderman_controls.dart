import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/websocket_service.dart';

// Spider-Man accent — one restrained red over the monochrome base (cyan stays
// the app accent elsewhere; red is reserved for the swing so it reads as "the
// big one"). Quiet at rest, loud as you charge.
const _kAccent  = Color(0xFFE5484D);
const _kRest    = Color(0x66FFFFFF);
const _kRestDim = Color(0x33FFFFFF);
const _kFill    = Color(0x22E5484D);

bool get _vib => WebSocketService.instance.sensitivity.vibration;

/// The hero control. Hold to web-swing (RT held); drag DOWN to charge a launch,
/// then release past the line to fire the boost (A) with a heavy haptic kick.
/// One thumb does what used to need three fingers on the keyboard launch.
class SwingButton extends StatefulWidget {
  const SwingButton({super.key, required this.width, required this.height});
  final double width;   // knob diameter
  final double height;  // full track height (vertical drag room)

  @override
  State<SwingButton> createState() => _SwingButtonState();
}

class _SwingButtonState extends State<SwingButton> {
  int?     _ptr;
  double   _drag = 0;        // 0..1 down the track
  double   _startY = 0;
  bool     _launching = false;
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  double get _knob   => widget.width;
  double get _travel => (widget.height - _knob).clamp(1.0, double.infinity);
  bool   get _charged => _drag >= 0.62;

  void _down(PointerDownEvent e) {
    if (_ptr != null) return;
    _ptr = e.pointer;
    _startY = e.localPosition.dy;
    setState(() { _drag = 0; _launching = false; });
    WebSocketService.instance.send({'type': 'right_trigger', 'value': 1.0}); // hold = swing
    // NO haptic on a plain swing touch — vibration is reserved for the drag/boost.
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _ptr) return;
    final d = ((e.localPosition.dy - _startY) / _travel).clamp(0.0, 1.0);
    final wasCharged = _charged;
    final now = DateTime.now();
    if (_vib && (d - _drag).abs() > 0.03 &&
        now.difference(_lastTick).inMilliseconds > 45) {
      HapticFeedback.selectionClick();    // tension ticks as you pull down
      _lastTick = now;
    }
    setState(() => _drag = d);
    if (_vib && !wasCharged && _charged) HapticFeedback.mediumImpact(); // crossed the launch line
  }

  void _up(PointerEvent e) {
    if (e.pointer != _ptr) return;
    _ptr = null;
    final launch = _charged;
    WebSocketService.instance.send({'type': 'right_trigger', 'value': 0.0}); // stop swinging
    if (launch) {
      // Boost = SPACE (tap). The drag-to-release "alternative to three-finger Space".
      WebSocketService.instance.send({'type': 'key_down', 'key': 'SPACE'});
      Future.delayed(const Duration(milliseconds: 60), () =>
          WebSocketService.instance.send({'type': 'key_up', 'key': 'SPACE'}));
      if (_vib) HapticFeedback.heavyImpact(); // the launch kick — this is part of the drag
      setState(() { _launching = true; _drag = 0; });
      Future.delayed(const Duration(milliseconds: 240), () {
        if (mounted) setState(() => _launching = false);
      });
    } else {
      setState(() => _drag = 0); // plain swing release — no vibration
    }
  }

  @override
  Widget build(BuildContext context) {
    final knob   = _knob;
    final lvl    = _launching ? 1.0 : _drag;
    final accent = Color.lerp(_kRest, _kAccent, lvl)!;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerMove: _move,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Stack(clipBehavior: Clip.none, children: [
          // Vertical track behind the knob.
          Positioned(
            left: widget.width / 2 - knob * 0.16, top: knob * 0.4, bottom: knob * 0.4,
            width: knob * 0.32,
            child: Container(decoration: BoxDecoration(
              color: _kFill,
              borderRadius: BorderRadius.circular(knob),
              border: Border.all(color: _kRestDim, width: 1),
            )),
          ),
          // "BOOST" hint near the bottom once you're past the line.
          if (_charged && !_launching)
            Positioned(left: 0, right: 0, bottom: 0, child: Text(
              'BOOST', textAlign: TextAlign.center,
              style: TextStyle(color: _kAccent, fontSize: knob * 0.14,
                fontWeight: FontWeight.bold, letterSpacing: 2))),
          // Knob — follows the finger, springs back up on release.
          AnimatedPositioned(
            duration: Duration(milliseconds: _ptr == null ? 180 : 0),
            curve: Curves.easeOut,
            left: 0, top: _drag * _travel,
            child: Container(
              width: knob, height: knob,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (_drag > 0 || _launching) ? _kFill : Colors.transparent,
                border: Border.all(color: accent, width: 2.5),
                boxShadow: (_charged || _launching)
                    ? [BoxShadow(color: _kAccent.withOpacity(0.5), blurRadius: 16, spreadRadius: 1)]
                    : null,
              ),
              alignment: Alignment.center,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_launching ? Icons.rocket_launch : Icons.keyboard_double_arrow_down,
                    color: Colors.white, size: knob * 0.32),
                SizedBox(height: knob * 0.03),
                Text('SWING', style: TextStyle(color: Colors.white,
                    fontSize: knob * 0.15, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
