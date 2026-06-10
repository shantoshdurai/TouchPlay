import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/websocket_service.dart';
import '../services/websocket_service.dart' as ws;
import '../services/device_stats.dart';
import '../services/haptics.dart';
import '../services/stream_service.dart';
import '../games/game_profiles.dart';
import '../games/custom_layout.dart';
import '../widgets/trigger_button.dart';
import '../widgets/action_button.dart';
import '../widgets/floating_keyboard.dart';
import '../widgets/forza_controls.dart';
import '../widgets/custom_controls.dart';
import 'layout_editor.dart';

// Split out of this file for navigability; they remain part of the same library
// so the private (_-prefixed) widgets stay private and share these imports.
part 'controller_screen_settings.dart';
part 'controller_screen_connection.dart';
part 'controller_screen_overlays.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key, this.startInMouseMode = false});

  /// When launched from the home menu's "Mouse & Keys" tile, open straight into
  /// trackpad/mouse mode instead of the gamepad.
  final bool startInMouseMode;

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  late final StreamSubscription<ws.ConnectionState> _sub;
  late final StreamSubscription<bool> _keyboardSub;
  // Connection state is a ValueNotifier so a reconnect repaints only the tiny
  // chip + stream button (via ValueListenableBuilder) instead of rebuilding the
  // entire controller tree — keeps gameplay at a locked frame rate.
  final ValueNotifier<ws.ConnectionState> _conn =
      ValueNotifier(ws.ConnectionState.disconnected);
  bool _mouseMode        = false;
  bool _keyboardMode     = false;
  bool _showSettings     = false;
  bool _showMenu         = false;   // 62Bytes-style hub (right-side panel)
  bool _showTutorial     = false;
  bool _showGames        = false;   // full grid picker (soon games, new, edit)
  bool _showGamesMenu    = false;   // quick-switch dropdown from the pill
  bool _showSteerChooser = false;
  bool _showForzaEditChooser = false; // "edit which steering?" before the editor
  bool _hideHud          = false;

  // ── Game stream ──────────────────────────────────────────────────────────────
  bool        _streamOn   = false;
  double?     _savedVibForStream;
  String _profileId  = 'standard';   // 'standard' | 'forza' | 'custom:<id>'
  String _forzaSteer = 'wheel';      // 'wheel' | 'pads'
  List<CustomLayout> _customLayouts = [];
  DateTime? _lastBackPress;          // back-button "press again to exit" guard
  OverlayEntry? _toast;              // current fade-in/out toast (replaced, not stacked)

  bool get _anyOverlayOpen =>
      _showSettings || _showMenu || _showGames || _showGamesMenu ||
      _showTutorial || _showSteerChooser || _showForzaEditChooser || _keyboardMode;

  // Android back: close any open overlay first; otherwise require a double-press
  // so you can't rage-quit the game by brushing the back gesture mid-match.
  void _onBackInvoked(bool didPop, Object? result) {
    if (didPop) return;
    if (_anyOverlayOpen) {
      setState(() {
        _showSettings = false; _showMenu = false; _showGames = false; _showGamesMenu = false;
        _showTutorial = false; _showSteerChooser = false; _showForzaEditChooser = false;
        _keyboardMode = false;
      });
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress == null || now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      // If we were opened from the home menu, the second press returns there;
      // otherwise (launched as root) it exits the app.
      _showToast(Navigator.of(context).canPop()
          ? 'Press back again for the menu'
          : 'Press back again to exit');
    } else {
      if (Navigator.of(context).canPop()) {
        StreamService.instance.disconnect();
        Navigator.of(context).pop();
      } else {
        SystemNavigator.pop();
      }
    }
  }

  // Lightweight transparent toast that fades in, holds, fades out — fits the
  // dark monochrome design instead of the blocky white Material SnackBar.
  void _showToast(String message) {
    _toast?.remove();
    final entry = OverlayEntry(
      builder: (_) => _Toast(message: message),
    );
    _toast = entry;
    Overlay.of(context).insert(entry);
    // Self-remove after the widget has fully faded out.
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (_toast == entry) {
        entry.remove();
        _toast = null;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _mouseMode = widget.startInMouseMode;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _sub = WebSocketService.instance.stateStream.listen((s) {
      _conn.value = s;
      // If the server drops while mirroring, stop the dead stream and restore
      // vibration — otherwise the toggle stays "on" showing a frozen frame.
      if (s != ws.ConnectionState.connected && _streamOn) _toggleStream();
    });
    _keyboardSub = WebSocketService.instance.keyboardStream.listen((show) {
      if (_keyboardMode != show) setState(() => _keyboardMode = show);
    });
    WebSocketService.instance.init();
    DeviceStats.instance.start();
    _initPrefs();
  }

  Future<void> _initPrefs() async {
    final prefs       = await SharedPreferences.getInstance();
    final customs     = await CustomLayoutStore.load();
    var   p           = prefs.getString('selected_profile') ?? 'standard';
    final steer       = prefs.getString('forza_steering') ?? 'wheel';
    final chooserSeen = prefs.getBool('forza_chooser_seen') ?? false;
    final tutSeen     = prefs.getBool('tutorial_seen_v2') ?? false;

    // If the saved custom layout no longer exists, fall back to standard.
    if (p.startsWith('custom:') && !customs.any((l) => 'custom:${l.id}' == p)) {
      p = 'standard';
    }

    bool showTut = false, showChooser = false;
    if (p == 'standard' && !tutSeen) {
      await prefs.setBool('tutorial_seen_v2', true);
      showTut = true;
    } else if (p == 'forza' && !chooserSeen) {
      showChooser = true;
    }
    if (!mounted) return;
    setState(() {
      _customLayouts    = customs;
      _profileId        = p;
      _forzaSteer       = steer;
      _showTutorial     = showTut;
      _showSteerChooser = showChooser;
    });
  }

  CustomLayout? get _activeCustom {
    if (!_profileId.startsWith('custom:')) return null;
    final id = _profileId.substring(7);
    for (final l in _customLayouts) { if (l.id == id) return l; }
    return null;
  }

  // ── Custom layout management ─────────────────────────────────────────────────
  Future<void> _openEditor(CustomLayout layout) async {
    final edited = await Navigator.of(context).push<CustomLayout>(
      MaterialPageRoute(builder: (_) => LayoutEditorScreen(layout: layout.copy())),
    );
    // Restore our own immersive mode after the editor route pops.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (edited == null) return;
    final i = _customLayouts.indexWhere((l) => l.id == edited.id);
    if (i >= 0) {
      _customLayouts[i] = edited;
    } else {
      _customLayouts.add(edited);
    }
    await CustomLayoutStore.saveAll(_customLayouts);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', 'custom:${edited.id}');
    if (!mounted) return;
    setState(() { _profileId = 'custom:${edited.id}'; _showGames = false; });
  }

  Future<void> _deleteCustom(CustomLayout layout) async {
    _customLayouts.removeWhere((l) => l.id == layout.id);
    await CustomLayoutStore.saveAll(_customLayouts);
    final wasActive = _profileId == 'custom:${layout.id}';
    if (wasActive) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_profile', 'standard');
    }
    if (!mounted) return;
    setState(() { if (wasActive) _profileId = 'standard'; });
  }

  // ── Game stream toggle ───────────────────────────────────────────────────────
  void _toggleStream() {
    if (_streamOn) {
      // Restore vibration strength that was in effect before streaming.
      if (_savedVibForStream != null) {
        final s = WebSocketService.instance.sensitivity;
        s.vibrationStrength = _savedVibForStream!;
        s.vibration = _savedVibForStream! > 0.01;
        _savedVibForStream = null;
      }
      StreamService.instance.disconnect();
      setState(() => _streamOn = false);
    } else {
      // Guard: screen mirroring needs a live server. A stale discovered/manual
      // IP can linger in currentIp even when nothing is listening, so check the
      // real connection state — not just "do we have an IP".
      final ip = WebSocketService.instance.currentIp;
      if (_conn.value != ws.ConnectionState.connected || ip == null) {
        _showToast('Connect to the PC server first to mirror the screen');
        return;
      }
      // Only now that we're actually starting — zero vibration while streaming
      // video to avoid interference (restored when streaming stops).
      final s = WebSocketService.instance.sensitivity;
      if (s.vibrationStrength > 0.01) {
        _savedVibForStream = s.vibrationStrength;
        s.vibrationStrength = 0.0;
        s.vibration = false;
      }
      StreamService.instance.connect(ip);
      WebSocketService.instance.send({
        'type': 'set_stream_quality',
        'quality': WebSocketService.instance.sensitivity.streamQuality,
      });
      setState(() => _streamOn = true);
      _showToast('Streaming on • Tune quality anytime in Settings');
    }
  }

  void _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', _profileId);
  }

  void _openEditCurrent() {
    if (_profileId == 'standard' || _profileId == 'forza' || _profileId == 'spiderman' || _profileId == 'overcooked') {
      _customizePreset(_profileId);
    } else {
      final c = _activeCustom;
      if (c != null) _openEditor(c);
    }
  }

  void _deleteCurrentCustom() {
    if (!_profileId.startsWith('custom:')) return;
    final id = _profileId.substring(7);
    setState(() {
      _customLayouts.removeWhere((l) => l.id == id);
      _profileId = 'standard';
    });
    CustomLayoutStore.saveAll(_customLayouts);
    _saveProfile();
  }

  void _newLayout() async {
    showDialog(context: context, builder: (_) =>
      _TemplatePicker(onPick: (tpl) {
        Navigator.of(context).pop();
        _openEditor(newLayoutFromTemplate(tpl));
      }));
  }

  // "Customize" a built-in preset → open an editable copy in the editor.
  // Forza first asks which steering style to edit (wheel / slider / tilt / pads),
  // then opens the editor with that steering control + pedals + buttons.
  Future<void> _customizePreset(String id) async {
    if (id == 'standard') {
      await _openEditor(cloneStandard());
    } else if (id == 'forza') {
      setState(() { _showGames = false; _showForzaEditChooser = true; });
    } else if (id == 'spiderman') {
      await _openEditor(cloneSpiderman());
    } else if (id == 'overcooked') {
      await _openEditor(cloneOvercooked());
    }
  }

  Future<void> _selectProfile(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_profile', id);
    final seen = prefs.getBool('forza_chooser_seen') ?? false;
    if (!mounted) return;
    setState(() {
      _profileId        = id;
      _showGames        = false;
      _showSteerChooser = id == 'forza' && !seen;
    });
  }

  Future<void> _setSteer(String mode, {bool markSeen = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('forza_steering', mode);
    if (markSeen) await prefs.setBool('forza_chooser_seen', true);
    if (!mounted) return;
    setState(() {
      _forzaSteer = mode;
      if (markSeen) _showSteerChooser = false;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    _keyboardSub.cancel();
    _conn.dispose();
    StreamService.instance.disconnect();
    DeviceStats.instance.stop();
    _toast?.remove();
    _toast = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final h = size.height;
    final w = size.width;
    final isForza  = _profileId == 'forza';
    final isSpider = _profileId == 'spiderman';
    final isOvercooked = _profileId == 'overcooked';
    final custom   = _activeCustom;
    final disp     = profileById(_profileId);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onBackInvoked,
      child: Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: Stack(
        children: [
          // 1. Background — game stream if active, else standard glow.
          // The video layer repaints in isolation (RepaintBoundary +
          // ValueListenableBuilder) so 60fps frame updates never rebuild the HUD.
          if (_streamOn)
            const Positioned.fill(child: _VideoLayer())
          else
            _BgGlow(),

          // 2. Active game layout
          if (!_hideHud) ...[
            ...(custom != null
                ? _customChildren(custom, w, h)
                : isSpider
                    ? _spidermanChildren(w, h)
                    : isOvercooked
                        ? _overcookedChildren(w, h)
                    : isForza
                        ? _forzaChildren(w, h)
                        : _standardChildren(w, h)),

            // 3. Top-left: Settings gear + connection chip (latency/temp/fps)
            Positioned(
              top: 0, left: 8,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _SettingsBtn(onTap: () => setState(() => _showSettings = !_showSettings)),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<ws.ConnectionState>(
                      valueListenable: _conn,
                      builder: (_, conn, __) => _ConnChip(
                        state: conn,
                        streamOn: _streamOn,
                        onTap: () => _showDialog(context),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ],

          // 4. Top-right: Games tab + Settings + Visibility
          if (!_hideHud)
            Positioned(
              top: 0, right: 8,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    // The game/layout pill is meaningless in mouse mode (the
                    // gamepad controls are hidden), so hide it there too.
                    if (!_mouseMode) ...[
                      _GamesBtn(
                        icon: custom != null ? Icons.tune : disp.icon,
                        label: custom != null ? custom.name : disp.name,
                        onTap: () => setState(() => _showGamesMenu = !_showGamesMenu),
                      ),
                      const SizedBox(width: 8),
                    ],
                    ValueListenableBuilder<ws.ConnectionState>(
                      valueListenable: _conn,
                      builder: (_, conn, __) => _StreamBtn(
                        active: _streamOn,
                        enabled: conn == ws.ConnectionState.connected,
                        onTap: _toggleStream,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Menu (62Bytes-style hub): server download, help, settings,
                    // about, community — opens as a right-side panel.
                    GestureDetector(
                      onTap: () => setState(() => _showMenu = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x99000000),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12, width: 1),
                        ),
                        child: const Icon(Icons.menu, color: Colors.white60, size: 16),
                      ),
                    ),
                  ]),
                ),
              ),
            ),

          // Monitor mode: controls hidden. Double-tap anywhere brings them
          // back (the ghost button is deliberately faint and easy to miss).
          if (_hideHud)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onDoubleTap: () => setState(() => _hideHud = false),
              ),
            ),

          // Faint bottom hint so the player knows how to bring controls back.
          if (_hideHud)
            Positioned(
              left: 0, right: 0, bottom: 10,
              child: SafeArea(
                top: false,
                child: IgnorePointer(
                  child: Center(child: Text('Double-tap anywhere to show controls',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 10, letterSpacing: 0.5))),
                ),
              ),
            ),

          if (_hideHud)
            Positioned(
              top: 8, right: 8,
              child: SafeArea(
                child: GestureDetector(
                  onTap: () => setState(() => _hideHud = false),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0x11FFFFFF), // Extremely faint ghost button
                    ),
                    child: const Icon(Icons.visibility, color: Color(0x44FFFFFF), size: 24),
                  ),
                ),
              ),
            ),

          // 5. Overlays
          if (_showSettings)
            _SettingsPanel(
              onClose: () => setState(() => _showSettings = false),
              profileId: _profileId,
              steerMode: _forzaSteer,
              onSteerMode: (m) => _setSteer(m),
              onEditCurrent: _openEditCurrent,
              streamOn: _streamOn,
              mouseMode: _mouseMode,
              onHideHud: () => setState(() { _showSettings = false; _hideHud = true; }),
            ),
          if (_showMenu)
            _MenuPanel(
              onClose: () => setState(() => _showMenu = false),
              onSettings: () => setState(() { _showMenu = false; _showSettings = true; }),
              onLink: (label) {
                setState(() => _showMenu = false);
                _showToast(label);
              },
            ),
          if (_showGamesMenu)
            _GamesDropdown(
              currentId: _profileId,
              customLayouts: _customLayouts,
              onPick: (id) { setState(() => _showGamesMenu = false); _selectProfile(id); },
              onNew: () { setState(() => _showGamesMenu = false); _newLayout(); },
              onMore: () => setState(() { _showGamesMenu = false; _showGames = true; }),
              onEditCurrent: () {
                setState(() => _showGamesMenu = false);
                _openEditCurrent();
              },
              onDeleteCurrent: () {
                setState(() => _showGamesMenu = false);
                _deleteCurrentCustom();
              },
              onClose: () => setState(() => _showGamesMenu = false),
            ),
          if (_showGames)
            _GamePicker(
              currentId: _profileId,
              customLayouts: _customLayouts,
              onPick: _selectProfile,
              onNew: _newLayout,
              onEdit: _openEditor,
              onDelete: _deleteCustom,
              onCustomize: _customizePreset,
              onClose: () => setState(() => _showGames = false),
            ),
          if (_keyboardMode)
            FloatingKeyboard(onClose: () => setState(() => _keyboardMode = false)),
          if (_showTutorial)
            _TutorialOverlay(onDismiss: () => setState(() => _showTutorial = false)),
          if (_showSteerChooser)
            _SteerChooser(onPick: (m) => _setSteer(m, markSeen: true)),
          if (_showForzaEditChooser)
            _SteerChooser(
              title: 'EDIT WHICH STEERING?',
              subtitle: 'Pick the steering you use — the editor opens with it,\n'
                  'plus the pedals & buttons, all movable & resizable.',
              onPick: (style) {
                setState(() => _showForzaEditChooser = false);
                _openEditor(cloneForza(style));
              },
              onClose: () => setState(() => _showForzaEditChooser = false),
            ),
        ],
      ),
    )); // PopScope + Scaffold
  }

  // ── STANDARD GAMEPAD layout ──────────────────────────────────────────────────
  List<Widget> _standardChildren(double w, double h) => [
        // Center split line
        Positioned(
          left: w * 0.5, top: 0, bottom: 0,
          child: Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
        ),
        // LEFT floating stick (movement) — hidden in mouse mode
        if (!_mouseMode)
          Positioned(
            left: 0, top: 28, bottom: 0, width: w * 0.5,
            child: _FloatingStick(side: 'left', screenH: h),
          ),
        // RIGHT floating stick — full-screen trackpad in mouse mode, right-half otherwise
        Positioned(
          right: 0, top: 28, bottom: 0, width: _mouseMode ? w : w * 0.5,
          child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
        ),
        // Top / center navigation
        Positioned(
          top: h * 0.15, left: 0, right: 0,
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
        // Mouse toggle + R-Click pill
        Positioned(
          bottom: h * 0.05, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MouseToggleButton(
                mouseMode: _mouseMode,
                onToggle: () => setState(() => _mouseMode = !_mouseMode),
              ),
              if (_mouseMode) ...[
                const SizedBox(width: 12),
                const _MouseBtn(button: 'right', label: 'R-Click'),
                const SizedBox(width: 8),
                _KeyboardBtn(onToggle: () => setState(() => _keyboardMode = !_keyboardMode), active: _keyboardMode),
              ],
            ],
          ),
        ),
        // Left side buttons — hidden in mouse mode (left half becomes click zone)
        if (!_mouseMode)
          Positioned(
            top: 28, left: w * 0.02, bottom: h * 0.05,
            child: SizedBox(
              width: w * 0.35,
              child: Stack(
                children: [
                  Positioned(top: h * 0.05, left: w * 0.05, child: const TriggerBar(side: 'left', label: 'LT', width: 56, height: 56)),
                  Positioned(top: h * 0.05, right: w * 0.05, child: const BumperButton(button: 'LB', label: 'LB', width: 56)),
                  Positioned(bottom: h * 0.05, left: 0, child: const ActionButton(button: 'LS', label: 'L3', size: 56)),
                  Positioned(top: h * 0.3, left: w * 0.02, child: const DPad(size: 140)),
                ],
              ),
            ),
          ),
        // Right side buttons
        if (!_mouseMode)
          Positioned(
            top: 28, right: w * 0.02, bottom: h * 0.05,
            child: SizedBox(
              width: w * 0.35,
              child: Stack(
                children: [
                  Positioned(top: h * 0.05, left: w * 0.05, child: const BumperButton(button: 'RB', label: 'RB', width: 56)),
                  Positioned(top: h * 0.05, right: w * 0.05, child: const TriggerBar(side: 'right', label: 'RT', width: 56, height: 56)),
                  Positioned(bottom: h * 0.05, right: 0, child: const ActionButton(button: 'RS', label: 'R3', size: 56)),
                  Positioned(bottom: h * 0.25, right: w * 0.05, child: _FaceButtons()),
                ],
              ),
            ),
          ),
      ];

  // ── FORZA HORIZON layout — mobile racing HUD ─────────────────────────────────
  // Every control sends a standard gamepad event (FH5 default mapping):
  //   GAS→RT  BRAKE→LT  HANDBRAKE→A  CAM→RB  REWIND→Y  HORN→RS
  //   CLUTCH→LB  SHIFTâ†‘→B  MAP→BACK  ANNA→DPADâ†“  PHOTO→DPADâ†‘  PAUSE→START
  List<Widget> _forzaChildren(double w, double h) {
    final s      = WebSocketService.instance.sensitivity;
    final joyR   = s.joyRadius;
    final pedalW = (w * 0.12).clamp(70.0, 150.0);
    final small  = (h * 0.13).clamp(46.0, 78.0);
    final big    = (h * 0.18).clamp(64.0, 110.0);
    final mini   = small * 0.72;

    // The four main racing controls are each resizable from Settings: steering
    // uses joyRadius (above); gas / brake / handbrake use their own size factors.
    final gasW   = pedalW * s.gasSize;
    final brakeW = pedalW * s.brakeSize;
    final gasH   = (h * 0.46 * s.gasSize).clamp(150.0, 360.0);
    final brakeH = (h * 0.36 * s.brakeSize).clamp(120.0, 300.0);
    final hbSize = (big * s.handbrakeSize).clamp(56.0, 150.0);

    return [
      // Right floating stick — full-screen trackpad in mouse mode
      Positioned(
        right: 0, top: 28, bottom: 0, width: _mouseMode ? w : w * 0.5,
        child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
      ),
      // Left floating stick (LS) — hidden/locked, same as the Standard layout.
      // Lets you navigate menus and select cars with full X/Y. Drawn UNDER the
      // wheel + left buttons (added later in this list), so those capture their
      // own touches first and the stick only activates on the empty left area.
      if (!_mouseMode)
        Positioned(
          left: 0, top: 28, bottom: 0, width: w * 0.5,
          child: _FloatingStick(side: 'left', screenH: h),
        ),
      // Mouse toggle + R-Click pill
      Positioned(
        bottom: h * 0.05, left: 0, right: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _MouseToggleButton(
              mouseMode: _mouseMode,
              onToggle: () => setState(() => _mouseMode = !_mouseMode),
            ),
            if (_mouseMode) ...[
              const SizedBox(width: 8),
              const _MouseBtn(button: 'right', label: 'R-Click'),
              const SizedBox(width: 8),
              _KeyboardBtn(onToggle: () => setState(() => _keyboardMode = !_keyboardMode), active: _keyboardMode),
            ],
          ],
        ),
      ),

      // STEERING (bottom-left) — wheel / slider / tilt / L-R pads
      if (_forzaSteer == 'wheel')
        Positioned(
          left: 0, right: w * 0.54, top: h * 0.30, bottom: 0,
          child: SteeringWheel(diameter: (h * 0.42 * joyR).clamp(150.0, 320.0)),
        )
      else if (_forzaSteer == 'slider')
        Positioned(
          left: 0, right: w * 0.50, top: h * 0.42, bottom: 0,
          child: SteeringSlider(width: (w * 0.34 * joyR).clamp(220.0, 380.0)),
        )
      else if (_forzaSteer == 'tilt')
        Positioned(
          left: w * 0.05, bottom: h * 0.10,
          child: const SteeringTilt(),
        )
      else ...[
        Positioned(
          left: w * 0.05, bottom: h * 0.11,
          child: SteeringPad(left: true, size: (h * 0.22 * joyR).clamp(80.0, 150.0)),
        ),
        Positioned(
          left: w * 0.21, bottom: h * 0.11,
          child: SteeringPad(left: false, size: (h * 0.22 * joyR).clamp(80.0, 150.0)),
        ),
      ],

      // PEDALS (bottom-right): GAS=RT, BRAKE=LT
      if (!_mouseMode) Positioned(
        right: w * 0.035, bottom: h * 0.07,
        child: RacePedal(gas: true, label: 'GAS', icon: Icons.local_gas_station,
            width: gasW, height: gasH),
      ),
      if (!_mouseMode) Positioned(
        right: w * 0.035 + gasW + w * 0.02, bottom: h * 0.07,
        child: RacePedal(gas: false, label: 'BRAKE', icon: Icons.front_hand,
            width: brakeW, height: brakeH),
      ),

      // HANDBRAKE (drift) = A — just left of the pedals
      if (!_mouseMode) Positioned(
        right: w * 0.06 + gasW + brakeW, bottom: h * 0.13,
        child: RaceButton(button: 'A', label: 'HBRAKE', icon: Icons.local_parking, size: hbSize),
      ),

      // Secondary cluster (upper-right): CAM=RB, REWIND=Y, HORN=RS
      if (!_mouseMode) Positioned(
        top: h * 0.15, right: w * 0.04,
        child: Row(children: [
          RaceButton(button: 'RB', label: 'CAM', icon: Icons.cameraswitch, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'Y', label: 'REWIND', icon: Icons.replay, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'RS', label: 'HORN', icon: Icons.campaign, size: small),
        ]),
      ),

      // Menu cluster (upper-left): A = select/confirm, B = back/close — so you can
      // answer in-game prompts (e.g. rewind "confirm?") without switching layouts.
      Positioned(
        top: h * 0.15, left: w * 0.04,
        child: Row(children: [
          RaceButton(button: 'A', label: 'SELECT', icon: Icons.check, size: small),
          SizedBox(width: w * 0.015),
          RaceButton(button: 'B', label: 'BACK', icon: Icons.close, size: small),
        ]),
      ),

      // Top-center utility (quiet, icon-only): MAP, ANNA, PHOTO, PAUSE
      Positioned(
        top: h * 0.05, left: 0, right: 0,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          RaceButton(button: 'BACK', label: 'MAP', icon: Icons.map, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'DPAD_DOWN', label: 'ANNA', icon: Icons.assistant, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'DPAD_UP', label: 'PHOTO', icon: Icons.photo_camera, size: mini, showLabel: false),
          SizedBox(width: w * 0.022),
          RaceButton(button: 'START', label: 'PAUSE', icon: Icons.pause, size: mini, showLabel: false),
        ]),
      ),
    ];
  }

  // ── MARVEL'S SPIDER-MAN 2 layout ─────────────────────────────────────────────
  // Rendered from the SAME editable definition you get when you tap Customize, so
  // the default and the editor always match. Left half = MOVE, right half =
  // CAMERA (fixed sticks); SWING on the right; every button is rebindable.
  CustomLayout? _spidermanLayout;
  List<Widget> _spidermanChildren(double w, double h) =>
      _customChildren(_spidermanLayout ??= cloneSpiderman(), w, h);

  CustomLayout? _overcookedLayout;
  List<Widget> _overcookedChildren(double w, double h) =>
      _customChildren(_overcookedLayout ??= cloneOvercooked(), w, h);

  // ── CUSTOM layout (play mode) ────────────────────────────────────────────────
  List<Widget> _customChildren(CustomLayout layout, double w, double h) {
    if (layout.items.isEmpty) {
      return [
        Center(child: GestureDetector(
          onTap: () => _openEditor(layout),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0x66FFFFFF))),
            child: const Text('Empty layout — tap to add controls',
              style: TextStyle(color: Colors.white54, fontSize: 13)),
          ),
        )),
      ];
    }
    return [
      // Standard "Xbox" fixed sticks — full-half floating sticks drawn under the
      // editable controls (so buttons on top still capture their own touches).
      if (layout.floatingSticks) ...[
        Positioned(
          left: w * 0.5, top: 0, bottom: 0,
          child: Container(width: 1, color: Colors.white.withValues(alpha: 0.07)),
        ),
        if (!_mouseMode)
          Positioned(
            left: 0, top: 28, bottom: 0, width: w * 0.5,
            child: _FloatingStick(side: 'left', screenH: h),
          ),
        Positioned(
          right: 0, top: 28, bottom: 0, width: _mouseMode ? w : w * 0.5,
          child: _FloatingStick(side: 'right', screenH: h, mouseMode: _mouseMode),
        ),
        Positioned(
          bottom: h * 0.05, left: 0, right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MouseToggleButton(
                mouseMode: _mouseMode,
                onToggle: () => setState(() => _mouseMode = !_mouseMode),
              ),
              if (_mouseMode) ...[
                const SizedBox(width: 12),
                const _MouseBtn(button: 'right', label: 'R-Click'),
                const SizedBox(width: 8),
                _KeyboardBtn(onToggle: () => setState(() => _keyboardMode = !_keyboardMode), active: _keyboardMode),
              ],
            ],
          ),
        ),
      ],
      for (final item in layout.items)
        if (!_mouseMode || item.x <= 0.5) _positionedCustom(item, w, h),
    ];
  }

  Widget _positionedCustom(ControlItem item, double w, double h) {
    final fp = controlFootprint(item);
    return Positioned(
      left: item.x * w - fp.width / 2,
      top:  item.y * h - fp.height / 2,
      width: fp.width, height: fp.height,
      child: buildCustomControl(item),
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
  DateTime? _downTime;

  // Two-finger trackpad gestures (mouse mode): scroll / pinch-zoom / right-click
  int?      _trackId2;
  Offset?   _pos1, _pos2;
  DateTime? _twoDownTime;
  double    _scrollAcc = 0, _zoomAcc = 0;
  bool      _gestureSent = false;

  bool get _isLeft  => widget.side == 'left';
  String get _stick => _isLeft ? 'left_stick' : 'right_stick';

  // Same base radius for BOTH sticks → identical size. Scaled by one setting.
  double get _joyR =>
      widget.screenH * 0.16 * WebSocketService.instance.sensitivity.joyRadius;

  static const _tapSlop     = 12.0;

  void _sendZero() =>
      WebSocketService.instance.send({'type': _stick, 'x': 0.0, 'y': 0.0});

  void _reset() {
    _trackId = null;
    _downPos = null;
    setState(() { _center = null; _thumb = Offset.zero; });
  }

  void _onDown(PointerDownEvent e) {
    if (_trackId != null) {
      // Second finger in mouse mode → start a scroll / zoom / right-click gesture
      if (widget.mouseMode && _trackId2 == null) {
        _trackId2 = e.pointer;
        _pos2 = e.localPosition;
        _twoDownTime = DateTime.now();
        _scrollAcc = 0;
        _zoomAcc = 0;
        _gestureSent = false;
        _downPos = null;            // a two-finger touch is never a left click
      }
      return;
    }
    _trackId = e.pointer;
    _downPos = e.localPosition;
    _downTime = DateTime.now();

    if (widget.mouseMode) {
      _pos1 = e.localPosition;
      return;
    }
    setState(() { _center = e.localPosition; _thumb = Offset.zero; });
  }

  void _onTwoFingerMove(PointerMoveEvent e) {
    final old1 = _pos1, old2 = _pos2;
    if (e.pointer == _trackId) {
      _pos1 = e.localPosition;
    } else if (e.pointer == _trackId2) {
      _pos2 = e.localPosition;
    }
    if (old1 == null || old2 == null || _pos1 == null || _pos2 == null) return;

    _zoomAcc   += (_pos1! - _pos2!).distance - (old1 - old2).distance;
    _scrollAcc += e.delta.dy / 2;   // both fingers report — halve to avoid 2×

    if (_zoomAcc.abs() > 28) {
      // Pinch out → zoom in (Ctrl + wheel on the PC)
      WebSocketService.instance.send({
        'type': 'mouse_zoom', 'delta': _zoomAcc > 0 ? 120 : -120});
      _zoomAcc = 0;
      _scrollAcc = 0;
      _gestureSent = true;
    } else if (_scrollAcc.abs() > 6) {
      // Natural scrolling: content follows the fingers (swipe down → scroll up)
      WebSocketService.instance.send({
        'type': 'mouse_scroll', 'dx': 0, 'dy': (_scrollAcc * 8).round()});
      _scrollAcc = 0;
      _gestureSent = true;
    }
  }

  void _onMove(PointerMoveEvent e) {
    if (e.pointer != _trackId) {
      if (widget.mouseMode && e.pointer == _trackId2 && _trackId2 != null) {
        _onTwoFingerMove(e);
      }
      return;
    }

    // ── Mouse / trackpad mode (right side toggle) ──
    if (widget.mouseMode) {
      if (_trackId2 != null) {
        _onTwoFingerMove(e);
        return;
      }
      _pos1 = e.localPosition;
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

  void _endTwoFinger() {
    // Quick two-finger tap with no scroll/zoom sent → right click
    if (!_gestureSent && _twoDownTime != null &&
        DateTime.now().difference(_twoDownTime!).inMilliseconds < 300) {
      WebSocketService.instance.send({'type': 'mouse_click', 'button': 'right'});
    }
    _trackId2 = null;
    _pos2 = null;
    _twoDownTime = null;
    _scrollAcc = 0;
    _zoomAcc = 0;
    _gestureSent = false;
  }

  void _onUp(PointerUpEvent e) {
    if (widget.mouseMode && e.pointer == _trackId2) {
      _endTwoFinger();
      return;
    }
    if (e.pointer != _trackId) return;
    if (widget.mouseMode) {
      if (_trackId2 != null) {
        // First finger lifted mid-gesture — finish it and stop tracking both.
        _endTwoFinger();
      } else if (_downPos != null && _downTime != null) {
        final dist = (e.localPosition - _downPos!).distance;
        final time = DateTime.now().difference(_downTime!).inMilliseconds;
        if (dist < _tapSlop && time < 350) {
          // single-tap → left click
          WebSocketService.instance.send({'type': 'mouse_click', 'button': 'left'});
        }
      }
      _trackId = null;
      _downPos = null;
      _downTime = null;
      _pos1 = null;
      return;
    }
    _sendZero();
    _reset();
  }

  void _onCancel(PointerCancelEvent e) {
    if (e.pointer == _trackId2) {
      _trackId2 = null;
      _pos2 = null;
      _gestureSent = false;
      return;
    }
    if (e.pointer != _trackId) return;
    if (!widget.mouseMode) _sendZero();
    _trackId2 = null;
    _pos1 = null;
    _pos2 = null;
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

// ── Video layer — isolated repaint surface for the game stream ────────────────
// Wrapped in a RepaintBoundary and driven by StreamService.frame so that
// decoded frames (up to 60fps) repaint ONLY this texture, never the HUD above it.

class _VideoLayer extends StatelessWidget {
  const _VideoLayer();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ValueListenableBuilder<ui.Image?>(
        valueListenable: StreamService.instance.frame,
        builder: (context, image, _) {
          if (image == null) return const SizedBox.expand();
          return RawImage(
            image: image,
            fit: WebSocketService.instance.sensitivity.streamFitStretch
                ? BoxFit.fill
                : BoxFit.contain,
          );
        },
      ),
    );
  }
}

// ── Toast — transparent pill that fades in, holds, then fades out ─────────────

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

// ── Settings panel (profile-aware) ────────────────────────────────────────────

class _BgGlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _GlowPainter(), size: Size.infinite);
}

class _GlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    // Cross-hatch subtle background pattern matching the reference image
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.02)
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
    p.color = Colors.white.withValues(alpha: 0.03);
    canvas.drawCircle(Offset(s.width * 0.2, s.height * 0.5), s.width * 0.3, p);
    canvas.drawCircle(Offset(s.width * 0.8, s.height * 0.5), s.width * 0.3, p);
  }
  @override bool shouldRepaint(_) => false;
}

// ── Connection chip + Settings button ─────────────────────────────────────────

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

// ── Stream toggle button (top bar) ───────────────────────────────────────────
class _StreamBtn extends StatelessWidget {
  const _StreamBtn({required this.active, required this.onTap, this.enabled = true});
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1.0 : 0.4,
    child: GestureDetector(
      onTap: onTap, // still fires when disabled → shows the "connect first" hint
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0x3300D4FF) : const Color(0x99000000),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? const Color(0xFF00D4FF) : Colors.white12,
            width: 1,
          ),
        ),
        child: Icon(
          Icons.cast,
          color: active ? const Color(0xFF00D4FF) : Colors.white60,
          size: 16,
        ),
      ),
    ),
  );
}

// ── Games tab (top bar) ───────────────────────────────────────────────────────

class _GamesBtn extends StatelessWidget {
  const _GamesBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
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
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: const Color(0xFF00D4FF), size: 14),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70, fontSize: 9,
              fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.expand_more, color: Colors.white38, size: 13),
      ]),
    ),
  );
}

// ── Game picker overlay — minimal tabbed panel ────────────────────────────────

class _KeyboardBtn extends StatelessWidget {
  const _KeyboardBtn({required this.onToggle, required this.active});
  final VoidCallback onToggle;
  final bool active;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onToggle,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF00D4FF).withValues(alpha: 0.2) : const Color(0x33000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? const Color(0xFF00D4FF) : Colors.white24, width: 1),
      ),
      child: Icon(Icons.keyboard, size: 16, color: active ? const Color(0xFF00D4FF) : Colors.white),
    ),
  );
}

