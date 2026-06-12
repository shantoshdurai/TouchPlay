import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/haptics.dart';
import '../services/stream_service.dart';
import '../services/websocket_service.dart' as ws;
import '../widgets/ambience.dart';

const _accent = Color(0xFF6FB6FF);

/// Dedicated PC-screen viewer ("Screen Mirror") — no gamepad HUD on top.
///
/// Watch your PC fullscreen, switch quality (360p → 1080p / 2nd-screen mode),
/// and optionally turn on Touch Control to use the picture itself as a big
/// trackpad: slide to move the PC cursor, tap to click, two fingers to
/// scroll / right-click — enough to drive the desktop or even a game from
/// the couch. (For playing with gamepad controls overlaid, use Gamepad and
/// hit the cast button there.)
class ScreenMirrorScreen extends StatefulWidget {
  const ScreenMirrorScreen({super.key});

  @override
  State<ScreenMirrorScreen> createState() => _ScreenMirrorScreenState();
}

class _ScreenMirrorScreenState extends State<ScreenMirrorScreen> {
  late final StreamSubscription<ws.ConnectionState> _sub;
  ws.ConnectionState _conn = ws.WebSocketService.instance.state;

  bool _touchControl = false;
  bool _barVisible = true;
  Timer? _barTimer;
  Timer? _retryTimer;

  /// How the PC picture maps onto the phone screen:
  ///  'fill'    — fills the whole screen, crops a sliver at the edges (default)
  ///  'fit'     — whole picture visible, black bars on the sides
  ///  'stretch' — fills by distorting
  String _fitMode = 'fill';

  static const _qualities = [
    ('360p', '360p'),
    ('480p', '480p'),
    ('720p', '720p'),
    ('1080p', '1080p'),
    ('screen', '2nd Screen'),
  ];

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final m = prefs.getString('mirror_fit');
      if (m != null && mounted) setState(() => _fitMode = m);
    });
    _sub = ws.WebSocketService.instance.stateStream.listen((s) {
      if (!mounted) return;
      setState(() => _conn = s);
      if (s == ws.ConnectionState.connected) _startStream();
    });
    _startStream();
    _scheduleBarHide();
    // Self-healing: if the stream socket drops (PC sleep, Wi-Fi blip) while
    // the control link is still up, quietly redial every 2s.
    _retryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted &&
          _conn == ws.ConnectionState.connected &&
          !StreamService.instance.isConnected) {
        _startStream();
      }
    });
  }

  void _cycleFit() {
    Haptics.instance.tick();
    setState(() {
      _fitMode = switch (_fitMode) {
        'fill' => 'fit',
        'fit' => 'stretch',
        _ => 'fill',
      };
    });
    SharedPreferences.getInstance()
        .then((p) => p.setString('mirror_fit', _fitMode));
    _scheduleBarHide();
  }

  BoxFit get _boxFit => switch (_fitMode) {
        'fit' => BoxFit.contain,
        'stretch' => BoxFit.fill,
        _ => BoxFit.cover,
      };

  void _startStream() {
    final ip = ws.WebSocketService.instance.currentIp;
    if (ip == null ||
        ws.WebSocketService.instance.state != ws.ConnectionState.connected) {
      return;
    }
    StreamService.instance.connect(ip);
    ws.WebSocketService.instance.send({
      'type': 'set_stream_quality',
      'quality': ws.WebSocketService.instance.sensitivity.streamQuality,
    });
  }

  @override
  void dispose() {
    _barTimer?.cancel();
    _retryTimer?.cancel();
    _sub.cancel();
    StreamService.instance.disconnect();
    super.dispose();
  }

  void _scheduleBarHide() {
    _barTimer?.cancel();
    _barTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _barVisible = false);
    });
  }

  void _toggleBar() {
    setState(() => _barVisible = !_barVisible);
    if (_barVisible) _scheduleBarHide();
  }

  void _setQuality(String q) {
    Haptics.instance.tick();
    final svc = ws.WebSocketService.instance;
    setState(() => svc.sensitivity.streamQuality = q);
    svc.saveSensitivity();
    svc.send({'type': 'set_stream_quality', 'quality': q});
    _scheduleBarHide();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _conn == ws.ConnectionState.connected;
    return Scaffold(
      backgroundColor: Colors.black,
      // StackFit.expand: with only Positioned/fill children plus the top bar,
      // a loose Stack would otherwise collapse to the BAR's height — which
      // squeezed the whole video into a 228px thumbnail at the top.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Video
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<ui.Image?>(
                valueListenable: StreamService.instance.frame,
                builder: (context, image, _) {
                  if (image == null) {
                    return AmbientBackground(
                        child: _waitingState(connected));
                  }
                  // FittedBox does the scaling through layout itself: the
                  // child is laid out at the frame's intrinsic pixel size and
                  // then scaled/cropped to fill the screen per the fit mode.
                  // (RawImage with fit/width/height proved unreliable on some
                  // devices — frames rendered at native size instead.)
                  return ClipRect(
                    child: SizedBox.expand(
                      child: FittedBox(
                        fit: _boxFit,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: image.width.toDouble(),
                          height: image.height.toDouble(),
                          child: RawImage(image: image),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Input layer: trackpad when Touch Control is on, else tap = HUD.
          Positioned.fill(
            child: _touchControl
                ? _MirrorTrackpad(onTwoFingerTripleTap: _toggleBar)
                : GestureDetector(
                    behavior: HitTestBehavior.opaque, onTap: _toggleBar),
          ),

          // Top bar — explicitly pinned so it never dictates the Stack's size.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 200),
              offset: _barVisible ? Offset.zero : const Offset(0, -1.2),
              child: _topBar(),
            ),
          ),

          // Always-reachable bar handle: a small translucent chevron pinned to
          // the top-right corner. Works even in Touch Control mode (it sits
          // above the trackpad layer), so the controls are never out of reach.
          if (!_barVisible)
            Positioned(
              top: 0,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: GestureDetector(
                  onTap: _toggleBar,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(10)),
                    ),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white38, size: 18),
                  ),
                ),
              ),
            ),

          // Touch-control hint chip (only right after enabling)
          if (_touchControl && _barVisible)
            Positioned(
              left: 0,
              right: 0,
              bottom: 14,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Touch control: slide = cursor · tap = click · '
                      '2 fingers = scroll / right-click',
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _waitingState(bool connected) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(connected ? Icons.monitor : Icons.wifi_off,
                color: Colors.white12, size: 48),
            const SizedBox(height: 14),
            Text(
              connected
                  ? 'Connecting to the PC screen…'
                  : 'Not connected.\nStart the TouchPlay server on your PC — '
                      'this connects automatically.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 12, height: 1.5),
            ),
            if (connected) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: _accent),
              ),
            ],
          ],
        ),
      );

  Widget _topBar() {
    final s = ws.WebSocketService.instance.sensitivity;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white70, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            const SizedBox(width: 8),
            const Text('Screen Mirror',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            ValueListenableBuilder(
              valueListenable: StreamService.instance.fps,
              builder: (_, fps, __) => fps > 0
                  ? Text('$fps fps',
                      style: const TextStyle(color: _accent, fontSize: 10.5))
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 6),
            // Incoming frame resolution — also a remote-diagnosis aid.
            ValueListenableBuilder(
              valueListenable: StreamService.instance.frame,
              builder: (_, img, __) => img == null
                  ? const SizedBox.shrink()
                  : Text('${img.width}×${img.height}',
                      style:
                          const TextStyle(color: Colors.white24, fontSize: 9)),
            ),
            const Spacer(),
            // Quality chips
            for (final q in _qualities) ...[
              GestureDetector(
                onTap: () => _setQuality(q.$1),
                child: Container(
                  margin: const EdgeInsets.only(left: 5),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: s.streamQuality == q.$1
                        ? _accent.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: s.streamQuality == q.$1
                            ? _accent
                            : Colors.white12),
                  ),
                  child: Text(q.$2,
                      style: TextStyle(
                          color: s.streamQuality == q.$1
                              ? _accent
                              : Colors.white54,
                          fontSize: 10)),
                ),
              ),
            ],
            const SizedBox(width: 10),
            // Fit-mode cycle: FILL (crop) → FIT (bars) → STRETCH
            GestureDetector(
              onTap: _cycleFit,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    switch (_fitMode) {
                      'fit' => Icons.fit_screen,
                      'stretch' => Icons.open_in_full,
                      _ => Icons.fullscreen,
                    },
                    color: _accent,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    switch (_fitMode) {
                      'fit' => 'FIT',
                      'stretch' => 'STRETCH',
                      _ => 'FILL',
                    },
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1),
                  ),
                ]),
              ),
            ),
            const SizedBox(width: 14),
            // Touch-control toggle
            GestureDetector(
              onTap: () {
                Haptics.instance.tick();
                setState(() => _touchControl = !_touchControl);
                _scheduleBarHide();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _touchControl
                      ? _accent.withValues(alpha: 0.18)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _touchControl ? _accent : Colors.white12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.touch_app,
                      color: _touchControl ? _accent : Colors.white54,
                      size: 13),
                  const SizedBox(width: 5),
                  Text('TOUCH',
                      style: TextStyle(
                          color: _touchControl ? _accent : Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fullscreen trackpad over the mirrored picture ────────────────────────────

class _MirrorTrackpad extends StatefulWidget {
  const _MirrorTrackpad({required this.onTwoFingerTripleTap});

  /// Escape hatch to re-show the HUD while touch control eats every tap:
  /// a quick three-finger tap toggles the bar.
  final VoidCallback onTwoFingerTripleTap;

  @override
  State<_MirrorTrackpad> createState() => _MirrorTrackpadState();
}

class _MirrorTrackpadState extends State<_MirrorTrackpad> {
  int? _id1, _id2;
  Offset? _pos1, _pos2;
  Offset? _downPos;
  DateTime? _downTime, _twoDownTime;
  double _scrollAcc = 0, _zoomAcc = 0;
  bool _gestureSent = false;
  int _activePointers = 0;

  static const _tapSlop = 12.0;

  void _send(Map<String, dynamic> msg) => ws.WebSocketService.instance.send(msg);

  void _onDown(PointerDownEvent e) {
    _activePointers++;
    if (_activePointers >= 3) {
      widget.onTwoFingerTripleTap();
      return;
    }
    if (_id1 == null) {
      _id1 = e.pointer;
      _pos1 = e.localPosition;
      _downPos = e.localPosition;
      _downTime = DateTime.now();
    } else if (_id2 == null) {
      _id2 = e.pointer;
      _pos2 = e.localPosition;
      _twoDownTime = DateTime.now();
      _scrollAcc = 0;
      _zoomAcc = 0;
      _gestureSent = false;
      _downPos = null;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (_id2 != null) {
      final old1 = _pos1, old2 = _pos2;
      if (e.pointer == _id1) {
        _pos1 = e.localPosition;
      } else if (e.pointer == _id2) {
        _pos2 = e.localPosition;
      } else {
        return;
      }
      if (old1 == null || old2 == null || _pos1 == null || _pos2 == null) {
        return;
      }
      _zoomAcc += (_pos1! - _pos2!).distance - (old1 - old2).distance;
      _scrollAcc += e.delta.dy / 2;
      if (_zoomAcc.abs() > 28) {
        _send({'type': 'mouse_zoom', 'delta': _zoomAcc > 0 ? 120 : -120});
        _zoomAcc = 0;
        _scrollAcc = 0;
        _gestureSent = true;
      } else if (_scrollAcc.abs() > 6) {
        _send(
            {'type': 'mouse_scroll', 'dx': 0, 'dy': (_scrollAcc * 8).round()});
        _scrollAcc = 0;
        _gestureSent = true;
      }
      return;
    }
    if (e.pointer != _id1) return;
    _pos1 = e.localPosition;
    if (e.delta.distance < 0.5) return;
    final sens =
        ws.WebSocketService.instance.sensitivity.mouseSensitivity / 10.0;
    _send({
      'type': 'mouse_move',
      'dx': (e.delta.dx * sens).round(),
      'dy': (e.delta.dy * sens).round(),
    });
  }

  void _endTwoFinger() {
    if (!_gestureSent &&
        _twoDownTime != null &&
        DateTime.now().difference(_twoDownTime!).inMilliseconds < 300) {
      _send({'type': 'mouse_click', 'button': 'right'});
    }
    _id2 = null;
    _pos2 = null;
    _twoDownTime = null;
    _scrollAcc = 0;
    _zoomAcc = 0;
    _gestureSent = false;
  }

  void _onUp(PointerUpEvent e) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (e.pointer == _id2) {
      _endTwoFinger();
      return;
    }
    if (e.pointer != _id1) return;
    if (_id2 != null) {
      _endTwoFinger();
    } else if (_downPos != null && _downTime != null) {
      final dist = (e.localPosition - _downPos!).distance;
      final time = DateTime.now().difference(_downTime!).inMilliseconds;
      if (dist < _tapSlop && time < 350) {
        _send({'type': 'mouse_click', 'button': 'left'});
      }
    }
    _id1 = null;
    _pos1 = null;
    _downPos = null;
    _downTime = null;
  }

  void _onCancel(PointerCancelEvent e) {
    _activePointers = (_activePointers - 1).clamp(0, 10);
    if (e.pointer == _id2) {
      _id2 = null;
      _pos2 = null;
      _gestureSent = false;
      return;
    }
    if (e.pointer != _id1) return;
    _id1 = null;
    _id2 = null;
    _pos1 = null;
    _pos2 = null;
    _downPos = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: const SizedBox.expand(),
      );
}
