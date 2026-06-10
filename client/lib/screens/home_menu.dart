import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/haptics.dart';
import '../services/websocket_service.dart' show WebSocketService;

class HomeMenu extends StatefulWidget {
  final VoidCallback onGamepad;
  final VoidCallback onMouse;
  final VoidCallback onMirror;
  final VoidCallback onFiles;
  final VoidCallback onVirtualCam;
  final VoidCallback onProjector;

  const HomeMenu({
    super.key,
    required this.onGamepad,
    required this.onMouse,
    required this.onMirror,
    required this.onFiles,
    required this.onVirtualCam,
    required this.onProjector,
  });

  @override
  State<HomeMenu> createState() => _HomeMenuState();
}

class _Feature {
  final String title;
  final String description;
  final String assetPath;
  final VoidCallback? onTap;

  _Feature({
    required this.title,
    required this.description,
    required this.assetPath,
    this.onTap,
  });
}

const _accent = Color(0xFF00D4FF);

// PS5-style STRICT icon spacing and sizing (small scaled for perfect proportion)
const double _slotSel = 74.0;
const double _slotUnsel = 46.0;
const double _iconSel = 64.0;
const double _iconUnsel = 36.0;
const double _railLeftOffset = 20.0;

class _HomeMenuState extends State<HomeMenu> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _showSettings = false;
  bool _showSearch = false;
  late final List<_Feature> _features;

  // Dynamic background color palettes matching each feature's thumbnail
  static const List<List<Color>> _featureGradients = [
    [Color(0xFF0088FF), Color(0xFF000B22)], // Gamepad (Blue/Cyan)
    [Color(0xFF8800FF), Color(0xFF110022)], // Mouse (Purple/Violet)
    [Color(0xFF00AAAA), Color(0xFF001A1A)], // Mirror (Teal)
    [Color(0xFFDD6600), Color(0xFF220B00)], // Files (Orange/Brown)
    [Color(0xFFFF2266), Color(0xFF22000B)], // Camera (Pink/Rose)
    [Color(0xFF00BB44), Color(0xFF001A0B)], // Projector (Emerald)
  ];

  late final AudioPlayer _navPlayer;
  late final AudioPlayer _selectPlayer;
  late final AudioPlayer _backPlayer;

  late final Timer _clockTimer;
  String _clock = _nowStr();

  @override
  void initState() {
    super.initState();
    _features = [
      _Feature(
          title: 'Gamepad',
          description: 'Turn your phone into a wireless controller',
          assetPath: 'assets/covers/gamepad.png',
          onTap: widget.onGamepad),
      _Feature(
          title: 'Mouse & Keys',
          description: 'Use your phone as a trackpad + keyboard',
          assetPath: 'assets/covers/mouse.png',
          onTap: widget.onMouse),
      _Feature(
          title: 'Screen Mirror',
          description: 'Stream your PC screen to your phone',
          assetPath: 'assets/covers/mirror.png',
          onTap: widget.onMirror),
      _Feature(
          title: 'File Transfer',
          description: 'Send files between phone and PC',
          assetPath: 'assets/covers/files.png',
          onTap: widget.onFiles),
      _Feature(
          title: 'Virtual Cam',
          description: 'Use your phone as a PC webcam',
          assetPath: 'assets/covers/camera.png',
          onTap: widget.onVirtualCam),
      _Feature(
          title: 'Projector',
          description: 'Mirror your phone to the PC screen',
          assetPath: 'assets/covers/projector.png',
          onTap: widget.onProjector),
    ];

    _initAudio();
    _clockTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _clock = _nowStr());
    });
  }

  static String _nowStr() {
    final n = TimeOfDay.now();
    final h = n.hourOfPeriod == 0 ? 12 : n.hourOfPeriod;
    final m = n.minute.toString().padLeft(2, '0');
    final ap = n.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  Future<void> _initAudio() async {
    _navPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _selectPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _backPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    try {
      await _navPlayer.setSource(AssetSource('sfx/nav.wav'));
      await _selectPlayer.setSource(AssetSource('sfx/select.wav'));
      await _backPlayer.setSource(AssetSource('sfx/back.wav'));
    } catch (_) {}
  }

  Future<void> _sfx(AudioPlayer p) async {
    try {
      if (p.state == PlayerState.playing) await p.stop();
      await p.resume();
    } catch (_) {}
  }

  void _select(int index) {
    final i = index.clamp(0, _features.length - 1);
    if (i == _selectedIndex) return;
    _sfx(_navPlayer);
    Haptics.instance.tick();
    setState(() => _selectedIndex = i);
  }

  void _move(int dir) => _select(_selectedIndex + dir);

  void _launch() {
    final f = _features[_selectedIndex];
    _sfx(_selectPlayer);
    Haptics.instance.heavy();
    f.onTap?.call();
  }

  void _openSearch() {
    _sfx(_navPlayer);
    Haptics.instance.tick();
    setState(() => _showSearch = true);
  }

  void _openSettings() {
    _sfx(_navPlayer);
    Haptics.instance.tick();
    setState(() => _showSettings = true);
  }

  void _closeSettings() {
    _sfx(_backPlayer);
    Haptics.instance.tick();
    setState(() => _showSettings = false);
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _navPlayer.dispose();
    _selectPlayer.dispose();
    _backPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Dynamic animated background blending
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  radius: 1.5,
                  colors: _featureGradients[_selectedIndex],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xBB000000),
                    Color(0x66000000),
                    Color(0xDD000000)
                  ],
                  stops: [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                _topBar(),
                const SizedBox(height: 16), // Tight gap
                _rail(),
                const SizedBox(height: 6), // Tight gap exactly like PS5
                _titleText(),
                const Spacer(),
              ],
            ),
          ),

          // Hidden left navigation joystick
          Positioned(
            left: 0,
            top: 160,
            bottom: 70,
            width: w * 0.5,
            child: _NavStick(onPrev: () => _move(-1), onNext: () => _move(1)),
          ),

          // Bottom-left: Launch pill
          Positioned(
            left: 20,
            bottom: 20,
            child: _launchPill(),
          ),

          // Bottom-right: face cluster
          Positioned(
            right: 20,
            bottom: 20,
            child: _faceCluster(),
          ),

          if (_showSettings) _settingsOverlay(),
          if (_showSearch)
            _SearchOverlay(
              features: _features,
              onPick: (i) {
                setState(() {
                  _showSearch = false;
                  _selectedIndex = i;
                });
                _launch();
              },
              onClose: () => setState(() => _showSearch = false),
            ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────────
  Widget _topBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text('TouchPlay',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
            const SizedBox(width: 6),
            Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: _accent, shape: BoxShape.circle)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white, size: 22),
              onPressed: _openSearch,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 22),
              onPressed: _openSettings,
            ),
            const SizedBox(width: 12),
            Text(_clock,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      );

  // ── Icon rail ─────────────────────────────────────────────────────────────────
  Widget _rail() => SizedBox(
        height: 80, // Accommodates the centered focused icon precisely
        child: Padding(
          padding: const EdgeInsets.only(left: _railLeftOffset),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(_features.length, _slotFor),
          ),
        ),
      );

  Widget _slotFor(int i) {
    final selected = i == _selectedIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      width: selected ? _slotSel : _slotUnsel,
      child: Align(
        alignment: Alignment.centerLeft,
        child: _iconBox(i, selected),
      ),
    );
  }

  Widget _iconBox(int i, bool selected) {
    final f = _features[i];
    final size = selected ? _iconSel : _iconUnsel;

    if (!selected) {
      return GestureDetector(
        onTap: () => _select(i),
        child: Opacity(
          opacity: 0.6,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.asset(f.assetPath,
                width: size, height: size, fit: BoxFit.cover),
          ),
        ),
      );
    }

    // PS5 focus: clean white frame + a snappy "pop" anchored at the center
    return GestureDetector(
      onTap: _launch,
      child: TweenAnimationBuilder<double>(
        key: ValueKey<int>(i),
        tween: Tween(begin: 0.85, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutBack,
        builder: (_, scale, child) => Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 2.0),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(f.assetPath,
                width: size, height: size, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }

  // ── Feature Title ─────────────────────────────────────────────────────────────
  Widget _titleText() {
    // Exact PS5 dynamic tracking: the text follows the focused icon perfectly
    final leftOffset = _selectedIndex * _slotUnsel;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(left: _railLeftOffset + leftOffset),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Row(
          key: ValueKey<int>(_selectedIndex),
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_features[_selectedIndex].title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }

  // ── Launch pill ───────────────────────────────────────────────────────────────
  Widget _launchPill() {
    return _glass(
      radius: 20,
      onTap: _launch,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _aGlyph(14),
          const SizedBox(width: 10),
          const Text('Launch',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Face cluster (translucent A/B/X/Y) ────────────────────────────────────────
  Widget _faceCluster() => SizedBox(
        width: 86,
        height: 86,
        child: Stack(alignment: Alignment.center, children: [
          Align(
              alignment: Alignment.topCenter,
              child:
                  _GlassFaceButton(size: 30, onTap: _openSettings, label: 'Y')),
          Align(
              alignment: Alignment.centerLeft,
              child: _GlassFaceButton(
                  size: 30, onTap: () => _move(-1), label: 'X')),
          Align(
              alignment: Alignment.centerRight,
              child: _GlassFaceButton(
                  size: 30, onTap: () => _move(1), label: 'B')),
          Align(
              alignment: Alignment.bottomCenter,
              child: _GlassFaceButton(
                  size: 30, accent: true, onTap: _launch, label: 'A')),
        ]),
      );

  Widget _aGlyph(double size) => Container(
        width: size + 8,
        height: size + 8,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _accent, width: 1.4)),
        child: Text('A',
            style: TextStyle(
                color: _accent,
                fontSize: size * 0.8,
                fontWeight: FontWeight.w700)),
      );

  // ── Settings overlay ──────────────────────────────────────────────────────────
  Widget _settingsOverlay() => _SettingsPanel(onClose: _closeSettings);

  // ── Glass helpers ─────────────────────────────────────────────────────────────
  Widget _glass(
          {required Widget child,
          required VoidCallback onTap,
          double radius = 16}) =>
      GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: child,
            ),
          ),
        ),
      );
}

// ── Translucent press-animated face button ────────────────────────────────────
class _GlassFaceButton extends StatefulWidget {
  const _GlassFaceButton(
      {required this.label,
      required this.onTap,
      this.size = 34,
      this.accent = false});
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool accent;

  @override
  State<_GlassFaceButton> createState() => _GlassFaceButtonState();
}

class _GlassFaceButtonState extends State<_GlassFaceButton> {
  bool _p = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _p = true),
      onTapCancel: () => setState(() => _p = false),
      onTapUp: (_) => setState(() => _p = false),
      onTap: () {
        Haptics.instance.tick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _p ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: ClipOval(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              width: widget.size,
              height: widget.size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _p
                    ? Colors.white.withValues(alpha: 0.24)
                    : Colors.white.withValues(alpha: 0.1),
                border: Border.all(
                  color: widget.accent
                      ? _accent.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.24),
                  width: widget.accent ? 1.6 : 1,
                ),
              ),
              child: Text(widget.label,
                  style: TextStyle(
                    color: widget.accent ? _accent : Colors.white70,
                    fontSize: widget.size * 0.45,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Hidden navigation joystick — same look as the gamepad's floating stick ──────
class _NavStick extends StatefulWidget {
  const _NavStick({required this.onPrev, required this.onNext});
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  State<_NavStick> createState() => _NavStickState();
}

class _NavStickState extends State<_NavStick> {
  int? _trackId;
  Offset? _center;
  Offset _thumb = Offset.zero;

  static const double _radius = 64;
  static const double _deadzone = 24;

  Timer? _repeatTimer;
  int _currentDir = 0;

  void _onDown(PointerDownEvent e) {
    if (_trackId != null) return;
    _trackId = e.pointer;
    setState(() {
      _center = e.localPosition;
      _thumb = Offset.zero;
    });
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _trackId || _center == null) return;
    var offset = e.localPosition - _center!;
    if (offset.distance > _radius) offset = offset / offset.distance * _radius;
    setState(() => _thumb = offset);

    _checkDirection();
  }

  void _checkDirection() {
    int newDir = 0;
    if (_thumb.dx > _deadzone)
      newDir = 1;
    else if (_thumb.dx < -_deadzone) newDir = -1;

    if (newDir != _currentDir) {
      _currentDir = newDir;
      _repeatTimer?.cancel();

      if (_currentDir != 0) {
        _fire(); // Fire immediately on tilt
        // Start hold-to-repeat delay
        _repeatTimer =
            Timer(const Duration(milliseconds: 350), _startRepeating);
      }
    }
  }

  void _startRepeating() {
    if (_currentDir == 0) return;
    // Fast repeat while held at the edge, exactly like holding a PS5 thumbstick
    _repeatTimer =
        Timer.periodic(const Duration(milliseconds: 140), (_) => _fire());
  }

  void _fire() {
    if (_currentDir == 1)
      widget.onNext();
    else if (_currentDir == -1) widget.onPrev();
  }

  void _reset(PointerEvent e) {
    if (e.pointer != _trackId) return;
    _trackId = null;
    _currentDir = 0;
    _repeatTimer?.cancel();
    setState(() {
      _center = null;
      _thumb = Offset.zero;
    });
  }

  @override
  void dispose() {
    _repeatTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _reset,
        onPointerCancel: _reset,
        child: CustomPaint(
          painter: _center != null
              ? _StickPainter(center: _center!, thumb: _thumb, radius: _radius)
              : null,
          child: const SizedBox.expand(),
        ),
      );
}

class _StickPainter extends CustomPainter {
  const _StickPainter(
      {required this.center, required this.thumb, required this.radius});
  final Offset center;
  final Offset thumb;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, ring);
    canvas.drawCircle(center, radius * 0.7, ring);
    final tp = center + thumb;
    canvas.drawCircle(
        tp, radius * 0.38, Paint()..color = const Color(0xFFC0C0C0));
  }

  @override
  bool shouldRepaint(_StickPainter o) => o.center != center || o.thumb != thumb;
}

// ── Settings Panel (Gamepad-style UI with Gaussian Blur) ──────────────────────
class _SettingsPanel extends StatefulWidget {
  final VoidCallback onClose;

  const _SettingsPanel({required this.onClose});

  @override
  State<_SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<_SettingsPanel> {
  String _view = 'home';

  static const _releasesUrl =
      'https://github.com/shantoshdurai/touchplay-releases/releases/latest';
  static const _feedbackUrl =
      'https://github.com/shantoshdurai/touchplay-releases/issues/new';
  static const _communityUrl =
      'https://github.com/shantoshdurai/touchplay-releases/discussions';

  Future<void> _open(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Widget _step(int n, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0x2200D4FF),
              border: Border.all(color: const Color(0xFF00D4FF)),
            ),
            child: Text('$n',
                style: const TextStyle(
                    color: Color(0xFF00D4FF),
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11, height: 1.35)),
              ])),
        ]),
      );

  Widget _row(IconData icon, String label, VoidCallback onTap,
          {Color? tint, bool last = false}) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: last
              ? null
              : const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0xFF1C1C28))),
                ),
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(children: [
            Icon(icon, color: tint ?? Colors.white60, size: 17),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(
                    color: tint ?? Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5)),
            const Spacer(),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.18), size: 16),
          ]),
        ),
      );

  Widget _home() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1A00D4FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x5500D4FF)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.download_rounded, color: Color(0xFF00D4FF), size: 18),
              SizedBox(width: 8),
              Text('Get the PC server',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            const Text(
                'Have you installed the latest TouchPlay server on your PC? It’s required to connect.',
                style: TextStyle(
                    color: Colors.white60, fontSize: 11, height: 1.35)),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _open(_releasesUrl),
              child: Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D4FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Go to Release',
                    style: TextStyle(
                        color: Color(0xFF06121A),
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => setState(() => _view = 'howto'),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 2),
                child: Text('How to install →',
                    style: TextStyle(color: Color(0xFF00D4FF), fontSize: 11)),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        _row(Icons.feedback_outlined, 'Send Feedback',
            () => _open(_feedbackUrl)),
        _row(Icons.system_update_alt, 'Check for Update',
            () => _open(_releasesUrl)),
        _row(Icons.help_outline, 'How to use',
            () => setState(() => _view = 'howto')),
        _row(Icons.tune_rounded, 'Controller Settings',
            () => setState(() => _view = 'controls')),
        _row(Icons.info_outline, 'About the App',
            () => setState(() => _view = 'about')),
        _row(Icons.privacy_tip_outlined, 'Privacy Policy',
            () => setState(() => _view = 'privacy')),
        _row(Icons.forum_outlined, 'Join Community',
            () => _open(_communityUrl),
            tint: const Color(0xFF00D4FF), last: true),
      ]);

  // ── Controller settings (quick tuning — full editor lives in the gamepad) ──
  Widget _slider(String label, double value, double min, double max,
          ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
          const Spacer(),
          Text(value.toStringAsFixed(1),
              style: const TextStyle(color: Color(0xFF00D4FF), fontSize: 11)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            activeTrackColor: const Color(0xFF00D4FF),
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 6),
      ]);

  Widget _controls() {
    final s = WebSocketService.instance.sensitivity;
    void save() => WebSocketService.instance.saveSensitivity();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _slider('Left stick sensitivity', s.stickSensitivity, 0.5, 2.0, (v) {
        setState(() => s.stickSensitivity = v);
        save();
      }),
      _slider('Right stick sensitivity', s.rightStickSensitivity, 0.5, 3.0,
          (v) {
        setState(() => s.rightStickSensitivity = v);
        save();
      }),
      _slider('Mouse sensitivity', s.mouseSensitivity, 4.0, 40.0, (v) {
        setState(() => s.mouseSensitivity = v);
        save();
      }),
      _slider('Vibration strength', s.vibrationStrength, 0.0, 1.0, (v) {
        setState(() {
          s.vibrationStrength = v;
          s.vibration = v > 0;
        });
        save();
      }),
      const SizedBox(height: 4),
      const Text('Stream quality',
          style: TextStyle(color: Colors.white70, fontSize: 11.5)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        children: [
          for (final q in const ['360p', '480p', '720p', 'screen'])
            GestureDetector(
              onTap: () {
                setState(() => s.streamQuality = q);
                save();
                WebSocketService.instance
                    .send({'type': 'set_stream_quality', 'quality': q});
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: s.streamQuality == q
                      ? const Color(0x3300D4FF)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: s.streamQuality == q
                          ? const Color(0xFF00D4FF)
                          : Colors.white12),
                ),
                child: Text(q == 'screen' ? '2nd screen' : q,
                    style: TextStyle(
                        color: s.streamQuality == q
                            ? const Color(0xFF00D4FF)
                            : Colors.white54,
                        fontSize: 10.5)),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      const Text(
          'Per-game layouts, button sizes and more live in the gamepad\'s '
          'own settings (gear icon while playing).',
          style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.4)),
    ]);
  }

  Widget _privacy() => const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your data stays on your network.',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text(
            'TouchPlay connects directly to the TouchPlay server on your own '
            'PC over your local Wi-Fi or USB. Controller input, the screen '
            'stream, camera frames and transferred files travel only between '
            'your phone and your PC — nothing is sent to us or any third '
            'party, and the app has no analytics, ads or tracking.\n\n'
            'The app stores your settings (sensitivity, vibration, layouts) '
            'only on this device. Camera and screen-capture access run only '
            'while you actively use Virtual Cam or Projector and stop the '
            'moment you end them.\n\n'
            'TouchPlay is free and open: if you have questions, open an '
            'issue on our GitHub.',
            style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.5),
          ),
        ],
      );

  Widget _howto() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
            'This app is your gamepad — it sends your touches to a PC running the free TouchPlay server.',
            style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.4)),
        const SizedBox(height: 16),
        _step(1, 'Install the PC server',
            'On your gaming PC, download the TouchPlay server from the Releases page and run it.'),
        _step(2, 'Same Wi-Fi',
            'Keep your phone and PC on the same Wi-Fi network.'),
        _step(3, 'Connect',
            'Tap the status chip (top-left) — the app auto-finds your PC, or enter its IP manually.'),
        _step(4, 'Play',
            'Launch your game on the PC. Use the gamepad here — optionally mirror the screen with the stream button.'),
      ]);

  Widget _about() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TouchPlay',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Turn your phone into a gamepad for any PC game.',
          style: TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.4)),
      const SizedBox(height: 14),
      const Text('Made for gamers, by gamers.',
          style: TextStyle(color: Colors.white24, fontSize: 10)),
    ]);
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 8),
        child: Row(children: [
          if (_view != 'home')
            GestureDetector(
              onTap: () => setState(() => _view = 'home'),
              child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child:
                      Icon(Icons.arrow_back, color: Colors.white54, size: 18)),
            ),
          Text(
              switch (_view) {
                'howto' => 'How to use',
                'about' => 'About',
                'controls' => 'Controller Settings',
                'privacy' => 'Privacy Policy',
                _ => 'Menu',
              },
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const Spacer(),
          GestureDetector(
            onTap: widget.onClose,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF1A1A24)),
              child: const Icon(Icons.close, color: Colors.white54, size: 16),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sz = MediaQuery.of(context).size;
    return Stack(children: [
      Positioned.fill(
          child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
              child: Container(color: Colors.black.withValues(alpha: 0.5)))),
      Positioned(
        top: top + 16,
        right: 16,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(
                offset: Offset(0, (1 - t) * -8), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  width: 250,
                  constraints: BoxConstraints(
                      maxHeight:
                          (sz.height - top - 32).clamp(200.0, sz.height)),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14161F).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(16),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _header(),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                        child: switch (_view) {
                          'howto' => _howto(),
                          'about' => _about(),
                          'controls' => _controls(),
                          'privacy' => _privacy(),
                          _ => _home(),
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

// ── Search overlay — quick-jump to any feature ─────────────────────────────────
class _SearchOverlay extends StatefulWidget {
  const _SearchOverlay(
      {required this.features, required this.onPick, required this.onClose});
  final List<_Feature> features;
  final void Function(int) onPick;
  final VoidCallback onClose;

  @override
  State<_SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<_SearchOverlay> {
  String _query = '';

  List<int> get _matches {
    final q = _query.trim().toLowerCase();
    return [
      for (var i = 0; i < widget.features.length; i++)
        if (q.isEmpty ||
            widget.features[i].title.toLowerCase().contains(q) ||
            widget.features[i].description.toLowerCase().contains(q))
          i
    ];
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: Container(color: Colors.black.withValues(alpha: 0.55)),
        ),
      ),
      Positioned(
        top: top + 16,
        left: 60,
        right: 60,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF14161F).withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(
                    autofocus: true,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    cursorColor: _accent,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search features...',
                      hintStyle: const TextStyle(
                          color: Colors.white30, fontSize: 13),
                      prefixIcon: const Icon(Icons.search,
                          color: Colors.white38, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: _accent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: _matches.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: Text('No matches',
                                style: TextStyle(
                                    color: Colors.white38, fontSize: 12)),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final i in _matches)
                                ListTile(
                                  dense: true,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.asset(
                                        widget.features[i].assetPath,
                                        width: 30,
                                        height: 30,
                                        fit: BoxFit.cover),
                                  ),
                                  title: Text(widget.features[i].title,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                  subtitle: Text(
                                      widget.features[i].description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white38,
                                          fontSize: 10.5)),
                                  onTap: () => widget.onPick(i),
                                ),
                            ],
                          ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
