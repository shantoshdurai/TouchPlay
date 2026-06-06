import 'package:flutter/material.dart';
import '../services/websocket_service.dart';

class FloatingKeyboard extends StatefulWidget {
  const FloatingKeyboard({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<FloatingKeyboard> createState() => _FloatingKeyboardState();
}

class _FloatingKeyboardState extends State<FloatingKeyboard> {
  Offset _pos = const Offset(100, 100);

  final List<List<String>> _keys = [
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.'],
  ];

  void _send(String char) {
    WebSocketService.instance.send({'type': 'keyboard_string', 'text': char});
  }

  void _backspace() {
    WebSocketService.instance.send({'type': 'key_down', 'key': 'BACKSPACE'});
    Future.delayed(const Duration(milliseconds: 50), () {
      WebSocketService.instance.send({'type': 'key_up', 'key': 'BACKSPACE'});
    });
  }

  void _enter() {
    WebSocketService.instance.send({'type': 'key_down', 'key': 'ENTER'});
    Future.delayed(const Duration(milliseconds: 50), () {
      WebSocketService.instance.send({'type': 'key_up', 'key': 'ENTER'});
    });
  }

  Widget _btn(String label, VoidCallback onTap, {double width = 36}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: width,
      height: 40,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFF24243A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double width = 48, Color? color}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: width,
      height: 40,
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF32324A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 4, offset: const Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white, size: 20),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos += d.delta),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xEE0D0D14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF24243A), width: 1.5),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 24, offset: const Offset(0, 12)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header (Drag handle & Close)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.drag_indicator, color: Colors.white38, size: 16),
                    ),
                    const Text('KEYBOARD', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(4.0),
                        child: Icon(Icons.close, color: Colors.white54, size: 18),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                
                // Keys
                for (final row in _keys)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: row.map((c) => _btn(c, () => _send(c))).toList(),
                  ),
                
                // Bottom row (Space, Backspace, Enter)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _btn('SPACE', () => _send(' '), width: 160),
                    _iconBtn(Icons.backspace, _backspace, color: const Color(0xFFE53935)),
                    _iconBtn(Icons.keyboard_return, _enter, width: 60, color: const Color(0xFF00D4FF).withValues(alpha: 0.2)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
