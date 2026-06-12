import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/haptics.dart';
import '../services/websocket_service.dart';

/// Floating, draggable AND scalable keyboard overlay.
///
/// Scale it three ways: pinch anywhere on the panel, or the −/＋ buttons in
/// the header. Position + scale persist across sessions so it stays exactly
/// where (and how big) you like it.
class FloatingKeyboard extends StatefulWidget {
  const FloatingKeyboard({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<FloatingKeyboard> createState() => _FloatingKeyboardState();
}

class _FloatingKeyboardState extends State<FloatingKeyboard> {
  Offset _pos = const Offset(100, 60);
  double _scale = 1.0;
  double _scaleAtGestureStart = 1.0;
  bool _shift = false;

  static const _minScale = 0.65;
  static const _maxScale = 1.8;

  // Unscaled panel footprint (used to clamp the drag inside the screen).
  static const _baseW = 460.0;
  static const _baseH = 280.0;

  final List<List<String>> _keys = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.'],
  ];

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _scale = (prefs.getDouble('float_kb_scale') ?? 1.0)
          .clamp(_minScale, _maxScale);
      final x = prefs.getDouble('float_kb_x');
      final y = prefs.getDouble('float_kb_y');
      if (x != null && y != null) _pos = Offset(x, y);
    });
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('float_kb_scale', _scale);
    await prefs.setDouble('float_kb_x', _pos.dx);
    await prefs.setDouble('float_kb_y', _pos.dy);
  }

  void _clampToScreen(Size screen) {
    final w = _baseW * _scale, h = _baseH * _scale;
    _pos = Offset(
      _pos.dx.clamp(-w * 0.5, screen.width - w * 0.5),
      _pos.dy.clamp(0.0, (screen.height - h * 0.5).clamp(0.0, double.infinity)),
    );
  }

  void _setScale(double s, Size screen) {
    _scale = s.clamp(_minScale, _maxScale);
    _clampToScreen(screen);
  }

  void _send(String char) {
    Haptics.instance.tick();
    WebSocketService.instance.send({'type': 'keyboard_string', 'text': char});
  }

  void _tapKey(String key) {
    WebSocketService.instance.send({'type': 'key_down', 'key': key});
    Future.delayed(const Duration(milliseconds: 50), () {
      WebSocketService.instance.send({'type': 'key_up', 'key': key});
    });
  }

  Widget _btn(String label, VoidCallback onTap, {double width = 34}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF3A3A4C),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 1,
                  offset: const Offset(0, 1.5)),
            ],
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w400)),
        ),
      );

  Widget _iconBtn(IconData icon, VoidCallback onTap,
          {double width = 48, Color? color, bool active = false}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: width,
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6FB6FF) : color ?? const Color(0xFF45455A),
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 1,
                  offset: const Offset(0, 1.5)),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(icon,
              color: active ? const Color(0xFF06121A) : Colors.white, size: 20),
        ),
      );

  Widget _headerIcon(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: () {
          Haptics.instance.tick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Icon(icon, color: Colors.white54, size: 18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        // Scale gesture also reports translation, so this one handler gives us
        // both one-finger drag and two-finger pinch-to-resize.
        onScaleStart: (_) => _scaleAtGestureStart = _scale,
        onScaleUpdate: (d) => setState(() {
          _pos += d.focalPointDelta;
          if (d.pointerCount > 1) {
            _setScale(_scaleAtGestureStart * d.scale, screen);
          } else {
            _clampToScreen(screen);
          }
        }),
        onScaleEnd: (_) => _persist(),
        child: Transform.scale(
          scale: _scale,
          alignment: Alignment.topLeft,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xD91E1E2A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.1), width: 1),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header: drag handle · resize − / + · close
                      Row(
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Icon(Icons.drag_indicator,
                                color: Colors.white38, size: 16),
                          ),
                          const SizedBox(width: 4),
                          const Text('drag · pinch to resize',
                              style: TextStyle(
                                  color: Colors.white24, fontSize: 9)),
                          const Spacer(),
                          _headerIcon(Icons.remove, () {
                            setState(() => _setScale(_scale - 0.15, screen));
                            _persist();
                          }),
                          _headerIcon(Icons.add, () {
                            setState(() => _setScale(_scale + 0.15, screen));
                            _persist();
                          }),
                          const SizedBox(width: 4),
                          _headerIcon(Icons.close, widget.onClose),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Keys
                      for (int i = 0; i < _keys.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (i == 2) const SizedBox(width: 17),
                            if (i == 3)
                              _iconBtn(Icons.keyboard_capslock, () {
                                Haptics.instance.tick();
                                setState(() => _shift = !_shift);
                              }, width: 40, active: _shift),
                            ..._keys[i].map((c) {
                              final ch = _shift ? c.toUpperCase() : c;
                              return _btn(ch, () {
                                _send(ch);
                                if (_shift) setState(() => _shift = false);
                              });
                            }),
                            if (i == 2) const SizedBox(width: 17),
                          ],
                        ),

                      // Bottom row (Space, Backspace, Enter)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _iconBtn(Icons.keyboard_tab, () => _tapKey('TAB'),
                              width: 42),
                          _btn('space', () => _send(' '), width: 170),
                          _iconBtn(Icons.backspace_outlined,
                              () => _tapKey('BACKSPACE'),
                              width: 48, color: const Color(0xFF505068)),
                          _iconBtn(Icons.keyboard_return, () => _tapKey('ENTER'),
                              width: 64, color: const Color(0xFF0081FF)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
