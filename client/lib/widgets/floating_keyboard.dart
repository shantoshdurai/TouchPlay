import 'dart:ui';
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

  Widget _btn(String label, VoidCallback onTap, {double width = 34}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: width,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF3A3A4C), // Lighter, minimalistic key color
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 1, offset: const Offset(0, 1.5)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w400)),
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap, {double width = 48, Color? color}) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: width,
      height: 42,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
      decoration: BoxDecoration(
        color: color ?? const Color(0xFF45455A),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 1, offset: const Offset(0, 1.5)),
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xD91E1E2A), // Translucent dark background
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
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
                        GestureDetector(
                          onTap: widget.onClose,
                          child: const Padding(
                            padding: EdgeInsets.all(4.0),
                            child: Icon(Icons.close, color: Colors.white54, size: 18),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    
                    // Keys
                    for (int i = 0; i < _keys.length; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Staggering offsets
                          if (i == 2) const SizedBox(width: 17), // 'a' row offset
                          if (i == 3) const SizedBox(width: 34), // 'z' row offset
                          
                          ..._keys[i].map((c) => _btn(c, () => _send(c))),
                          
                          if (i == 2) const SizedBox(width: 17),
                          if (i == 3) const SizedBox(width: 34),
                        ],
                      ),
                    
                    // Bottom row (Space, Backspace, Enter)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _iconBtn(Icons.language, () {}, width: 42),
                        _btn('space', () => _send(' '), width: 180),
                        _iconBtn(Icons.backspace_outlined, _backspace, width: 48, color: const Color(0xFF505068)),
                        _iconBtn(Icons.keyboard_return, _enter, width: 64, color: const Color(0xFF0081FF)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
