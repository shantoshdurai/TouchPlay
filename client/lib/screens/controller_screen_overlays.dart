part of 'controller_screen.dart';

// Game picker, template picker, games dropdown, steering chooser, tutorial &
// IP-connect dialog overlays — extracted from controller_screen.dart.

class _GamePicker extends StatefulWidget {
  const _GamePicker({
    required this.currentId,
    required this.customLayouts,
    required this.onPick,
    required this.onNew,
    required this.onEdit,
    required this.onDelete,
    required this.onCustomize,
    required this.onClose,
  });
  final String currentId;
  final List<CustomLayout> customLayouts;
  final ValueChanged<String> onPick;
  final VoidCallback onNew;
  final ValueChanged<CustomLayout> onEdit;
  final ValueChanged<CustomLayout> onDelete;
  final ValueChanged<String> onCustomize;
  final VoidCallback onClose;

  @override
  State<_GamePicker> createState() => _GamePickerState();
}

class _GamePickerState extends State<_GamePicker> {
  int _tab = 0; // 0 = built-in, 1 = custom

  static const _accent = Color(0xFF6FB6FF);

  bool get _onCustomTab => _tab == 1;

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    return Stack(children: [
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: widget.onClose,
        child: Container(color: Colors.black.withValues(alpha: 0.65)))),
      Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: (sz.width * 0.55).clamp(300.0, 480.0),
              constraints: BoxConstraints(maxHeight: sz.height * 0.80),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 28, offset: const Offset(0, 10))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ── Header ────────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                  child: Row(children: [
                    const Text('LAYOUTS', style: TextStyle(
                      color: Colors.white, fontSize: 12,
                      fontWeight: FontWeight.w700, letterSpacing: 2.5)),
                    const Spacer(),
                    GestureDetector(
                      onTap: widget.onClose,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0xFF1A1A24)),
                        child: const Icon(Icons.close, color: Colors.white54, size: 15),
                      ),
                    ),
                  ]),
                ),

                // ── Tab bar ───────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    _tabBtn(0, 'BUILT-IN'),
                    const SizedBox(width: 6),
                    _tabBtn(1, 'CUSTOM (${widget.customLayouts.length})'),
                  ]),
                ),
                const SizedBox(height: 10),
                const Divider(height: 1, color: Color(0xFF20202C)),

                // ── List ──────────────────────────────────────────────────────
                Flexible(child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (!_onCustomTab) ...[
                      for (final p in kGameProfiles.where((p) => !p.comingSoon))
                        _presetRow(p),
                      if (kGameProfiles.any((p) => p.comingSoon))
                        const Padding(
                          padding: EdgeInsets.fromLTRB(18, 8, 18, 2),
                          child: Align(alignment: Alignment.centerLeft,
                            child: Text('COMING SOON', style: TextStyle(
                              color: Colors.white24, fontSize: 9,
                              fontWeight: FontWeight.bold, letterSpacing: 1.8))),
                        ),
                      for (final p in kGameProfiles.where((p) => p.comingSoon))
                        _presetRow(p, disabled: true),
                    ] else ...[
                      if (widget.customLayouts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Text('No custom layouts yet.',
                            style: TextStyle(color: Colors.white38, fontSize: 13)),
                        ),
                      for (final l in widget.customLayouts)
                        _customRow(l),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                        child: GestureDetector(
                          onTap: () { widget.onClose(); widget.onNew(); },
                          child: Container(
                            height: 40, alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _accent)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.add, color: _accent, size: 16),
                              SizedBox(width: 6),
                              Text('New custom layout', style: TextStyle(
                                color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ]),
                )),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _tabBtn(int idx, String label) {
    final active = _tab == idx;
    return GestureDetector(
      onTap: () => setState(() => _tab = idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? const Color(0x226FB6FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? _accent : const Color(0xFF2C2C40)),
        ),
        child: Text(label, style: TextStyle(
          color: active ? _accent : Colors.white38,
          fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.4)),
      ),
    );
  }

  Widget _presetRow(GameProfile p, {bool disabled = false}) {
    final selected = !disabled && widget.currentId == p.id;
    final canCustomize = !disabled &&
        (p.id == 'standard' || p.id == 'forza' || p.id == 'spiderman' || p.id == 'overcooked');
    return InkWell(
      onTap: disabled ? null : () => widget.onPick(p.id),
      child: Container(
        color: selected ? const Color(0x0F6FB6FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(children: [
          Icon(p.icon,
            size: 20,
            color: disabled ? Colors.white24
                : selected ? _accent : Colors.white70),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              Text(p.name, style: TextStyle(
                color: disabled ? Colors.white24
                    : selected ? _accent : Colors.white,
                fontSize: 13, fontWeight: FontWeight.w600)),
              Text(p.tagline, style: TextStyle(
                color: disabled ? Colors.white12 : Colors.white38, fontSize: 10)),
            ],
          )),
          if (selected && !canCustomize)
            const Icon(Icons.check_circle, color: _accent, size: 16)
          else if (canCustomize)
            GestureDetector(
              onTap: () => widget.onCustomize(p.id),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1A24)),
                child: Icon(Icons.tune, size: 14,
                  color: selected ? _accent : Colors.white54),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _customRow(CustomLayout l) {
    final selected = widget.currentId == 'custom:${l.id}';
    return InkWell(
      onTap: () => widget.onPick('custom:${l.id}'),
      child: Container(
        color: selected ? const Color(0x0F6FB6FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Row(children: [
          Icon(Icons.tune, size: 18, color: selected ? _accent : Colors.white54),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
            children: [
              Text(l.name, style: TextStyle(
                color: selected ? _accent : Colors.white,
                fontSize: 13, fontWeight: FontWeight.w600)),
              Text('${l.items.length} controls · custom',
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ],
          )),
          GestureDetector(
            onTap: () => widget.onEdit(l),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1A24)),
              child: Icon(Icons.edit_outlined, size: 14,
                color: selected ? _accent : Colors.white54),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => widget.onDelete(l),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1A24)),
              child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFE53935)),
            ),
          ),
        ]),
      ),
    );
  }
}



class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({required this.onPick});
  final ValueChanged<String> onPick;

  Widget _opt(IconData icon, String title, String sub, String tpl) => GestureDetector(
    onTap: () => onPick(tpl),
    child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF24243A)),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFF6FB6FF), size: 26),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right, color: Colors.white24),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    insetPadding: const EdgeInsets.all(20),
    child: Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF20202C)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('START FROM', style: TextStyle(
          color: Color(0xFF6FB6FF), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
        const SizedBox(height: 14),
        _opt(Icons.crop_square, 'Blank canvas', 'Start empty', 'blank'),
        _opt(Icons.sports_esports, 'Gamepad starter', 'ABXY, sticks, bumpers, D-pad', 'gamepad'),
        _opt(Icons.keyboard, 'Keyboard + Mouse', 'WASD, mouse pad, clicks', 'kbm'),
      ]),
    ),
  );
}

// ── Games quick-switch dropdown (from the top-bar pill) ───────────────────────

class _GamesDropdown extends StatelessWidget {
  const _GamesDropdown({
    required this.currentId,
    required this.customLayouts,
    required this.onPick,
    required this.onNew,
    required this.onMore,
    required this.onEditCurrent,
    required this.onDeleteCurrent,
    required this.onClose,
  });
  final String currentId;
  final List<CustomLayout> customLayouts;
  final ValueChanged<String> onPick;
  final VoidCallback onNew, onMore, onEditCurrent, onDeleteCurrent, onClose;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final sz  = MediaQuery.of(context).size;
    return Stack(children: [
      // tap-outside to dismiss
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: onClose,
        child: const SizedBox.expand())),
      Positioned(
        top: top + 42, right: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * -8), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 196,
              // Always fit the visible (landscape) screen — never run off-screen.
              constraints: BoxConstraints(maxHeight: (sz.height - top - 54).clamp(140.0, sz.height)),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 9, 12, 3),
                  child: Align(alignment: Alignment.centerLeft,
                    child: Text('SWITCH LAYOUT', style: TextStyle(
                      color: Colors.white38, fontSize: 9,
                      fontWeight: FontWeight.bold, letterSpacing: 1.8))),
                ),
                Flexible(child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    for (final p in kGameProfiles.where((p) => !p.comingSoon))
                      _row(p.icon, p.name, currentId == p.id, () => onPick(p.id),
                          onEdit: currentId == p.id ? onEditCurrent : null),
                    for (final l in customLayouts)
                      _row(Icons.tune, l.name, currentId == 'custom:${l.id}',
                          () => onPick('custom:${l.id}'),
                          onEdit: currentId == 'custom:${l.id}' ? onEditCurrent : null,
                          onDelete: currentId == 'custom:${l.id}' ? onDeleteCurrent : null),
                  ]),
                )),
                const Divider(height: 1, color: Color(0xFF20202C)),
                _row(Icons.add_circle_outline, 'New layout', false, onNew, accentIcon: true),
                _row(Icons.grid_view_rounded, 'All layouts & more', false, onMore, accentIcon: true),
                const SizedBox(height: 4),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _row(IconData icon, String label, bool active, VoidCallback onTap,
      {bool accentIcon = false, VoidCallback? onEdit, VoidCallback? onDelete}) {
    const accent = Color(0xFF6FB6FF);
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? const Color(0x146FB6FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Icon(icon, size: 16, color: active || accentIcon ? accent : Colors.white70),
          const SizedBox(width: 10),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: active ? accent : Colors.white, fontSize: 12,
              fontWeight: active ? FontWeight.w600 : FontWeight.normal))),
          if (active && onEdit == null) const Icon(Icons.check, size: 15, color: accent),
          if (active && onEdit != null) ...[
            GestureDetector(
              onTap: onEdit,
              child: const Icon(Icons.edit_outlined, size: 16, color: accent),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

// ── First-time steering chooser (Forza) ───────────────────────────────────────

class _SteerChooser extends StatelessWidget {
  const _SteerChooser({
    required this.onPick,
    this.title = 'CHOOSE YOUR STEERING',
    this.subtitle = 'How do you want to steer in Forza?\nYou can change this anytime in Settings.',
    this.onClose,
  });
  final ValueChanged<String> onPick;
  final String title;
  final String subtitle;
  final VoidCallback? onClose; // tap-outside to dismiss (null = forced choice)

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose ?? () {},
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Center(
          // Absorb taps on the card so only taps on the backdrop dismiss.
          child: GestureDetector(
            onTap: () {},
            child: Container(
            width: (w * 0.92).clamp(360.0, 760.0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF20202C)),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(
                color: Color(0xFF6FB6FF), fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2.5)),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
              const SizedBox(height: 22),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12, runSpacing: 12,
                children: [
                  _SteerOption(icon: Icons.trip_origin, title: 'WHEEL',
                    sub: 'Drag a wheel\nsmooth & precise', onTap: () => onPick('wheel')),
                  _SteerOption(icon: Icons.tune, title: 'SLIDER',
                    sub: 'Slide a knob\nhands stay put', onTap: () => onPick('slider')),
                  _SteerOption(icon: Icons.screen_rotation, title: 'TILT',
                    sub: 'Tilt the phone\nlike a wheel', onTap: () => onPick('tilt')),
                  _SteerOption(icon: Icons.swap_horiz, title: 'L / R PADS',
                    sub: 'Tap arrows\nsimple & arcade', onTap: () => onPick('pads')),
                ],
              ),
            ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SteerOption extends StatelessWidget {
  const _SteerOption({required this.icon, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 152,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF12121C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF24243A)),
      ),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF6FB6FF), size: 42),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(
          color: Colors.white, fontSize: 15,
          fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 6),
        Text(sub, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white38, fontSize: 11, height: 1.3)),
      ]),
    ),
  );
}

// ── Tutorial overlay (first launch) ──────────────────────────────────────────

class _TutorialOverlay extends StatefulWidget {
  const _TutorialOverlay({required this.onDismiss});
  final VoidCallback onDismiss;
  @override State<_TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<_TutorialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, value: 1.0,
        duration: const Duration(milliseconds: 600));
    Future.delayed(const Duration(seconds: 3), _dismiss);
  }
  @override void dispose() { _fade.dispose(); super.dispose(); }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) widget.onDismiss();
  }

  Widget _half(String title, String sub, IconData icon, Alignment align) =>
    Align(alignment: align, child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: align == Alignment.centerLeft
            ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.45), size: 34),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          Text(sub, style: TextStyle(color: Colors.white.withValues(alpha: 0.3),
              fontSize: 10, letterSpacing: 0.5)),
        ],
      ),
    ));

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: GestureDetector(
      onTap: _dismiss,
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        child: Stack(children: [
          // Vertical divider
          Center(child: Container(width: 1, color: Colors.white.withValues(alpha: 0.1))),
          // Left label
          _half('MOVE', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerLeft),
          // Right label
          _half('CAMERA', 'touch anywhere → stick spawns',
              Icons.touch_app, Alignment.centerRight),
          // Bottom hint
          Align(alignment: Alignment.bottomCenter, child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text('tap to dismiss',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.2), fontSize: 10)),
          )),
        ]),
      ),
    ),
  );
}

// ── IP dialog ─────────────────────────────────────────────────────────────────

class _IpDialog extends StatefulWidget {
  const _IpDialog();
  @override State<_IpDialog> createState() => _IpDialogState();
}

class _IpDialogState extends State<_IpDialog> {
  final _ctrl = TextEditingController();
  late StreamSubscription<ws.ConnectionState> _sub;
  Timer? _refresh;
  ws.ConnectionState _conn = WebSocketService.instance.state;

  @override
  void initState() {
    super.initState();
    _sub = WebSocketService.instance.stateStream.listen((s) {
      setState(() => _conn = s);
      if (s == ws.ConnectionState.connected) {
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    });
    // Keep diagnostics (discovered IP, candidates) live while it searches.
    _refresh = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _sub.cancel(); _refresh?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _connect() {
    final ip = _ctrl.text.trim();
    if (ip.isNotEmpty) WebSocketService.instance.setManualIp(ip);
  }

  Widget _diagRow(String label, String value, {Color? valueColor}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 62, child: Text(label,
        style: const TextStyle(color: Colors.white38, fontSize: 11))),
      Expanded(child: Text(value, style: TextStyle(
        color: valueColor ?? Colors.white70, fontSize: 11, fontWeight: FontWeight.w500))),
    ]),
  );

  Widget _label(String text) => Text(text, style: const TextStyle(
    color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.8));

  @override
  Widget build(BuildContext context) {
    final svc        = WebSocketService.instance;
    final connected  = _conn == ws.ConnectionState.connected;
    final connecting = _conn == ws.ConnectionState.connecting;
    final statusColor = connected
        ? const Color(0xFF1DB954)
        : connecting ? const Color(0xFFF9A825) : const Color(0xFFE53935);
    final statusText = connected ? 'Connected'
        : connecting ? 'Connecting…' : 'Not connected';

    final sz         = MediaQuery.of(context).size;
    final found      = svc.discoveredIp;
    final candidates = svc.candidateIps;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
        width: 360,
        constraints: BoxConstraints(maxHeight: sz.height * 0.92),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF14161F).withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header with live status
            Row(children: [
              const Text('CONNECTION', style: TextStyle(
                color: Colors.white, fontSize: 12,
                fontWeight: FontWeight.bold, letterSpacing: 2.5)),
              const Spacer(),
              Container(width: 8, height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: statusColor)),
              const SizedBox(width: 6),
              Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
            ]),
            const SizedBox(height: 16),

            // Diagnostics
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF15151F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF222232)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _diagRow('Found PC', found ?? (connecting ? 'searching…' : 'not found yet'),
                    valueColor: found != null ? const Color(0xFF6FB6FF) : Colors.white38),
                _diagRow('Trying', candidates.isEmpty ? '—' : candidates.join('   ·   ')),
                if (svc.serverVersion != null) _diagRow('Server', 'v${svc.serverVersion}', 
                  valueColor: svc.versionMismatch ? const Color(0xFFE53935) : null),
              ]),
            ),
            if (svc.versionMismatch) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x33E53935),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0x88E53935)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFE53935), size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Version mismatch! Please download the correct v1.0.0 server.',
                    style: TextStyle(color: Color(0xFFE53935), fontSize: 11)
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 14),



            _label('OR ENTER PC IP MANUALLY'),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onSubmitted: (_) => _connect(),
              decoration: InputDecoration(
                hintText: '192.168.1.42',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF15151F),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF252535))),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF6FB6FF))),
              ),
            ),
            const SizedBox(height: 14),

            Row(children: [
              // Quiet glass secondary, white pill primary — same language as
              // the home menu's Launch pill.
              Expanded(child: GestureDetector(
                onTap: () => WebSocketService.instance.reconnect(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, size: 16, color: Colors.white70),
                      SizedBox(width: 6),
                      Text('Rescan',
                          style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              )),
              const SizedBox(width: 10),
              Expanded(child: PillButton(label: 'Connect', onTap: _connect)),
            ]),
          ]),
        ),
        ),
        ),
      ),
    );
  }
}

// ── Menu (62Bytes-style hub) ──────────────────────────────────────────────────
// Side-docked panel on the RIGHT edge (same motion/anchor language as the
// settings panel, just mirrored) — nothing centered. Holds the get-the-server
// prompt, help, settings, about and community. How-to and About open inline as
// detail views so we never spawn a centered dialog.

class _MenuPanel extends StatefulWidget {
  const _MenuPanel({
    required this.onClose,
    required this.onSettings,
    required this.onLink,
  });
  final VoidCallback onClose;
  final VoidCallback onSettings;
  final void Function(String label) onLink;   // external links (wired once URLs exist)
  @override State<_MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<_MenuPanel> {
  String _view = 'home';   // 'home' | 'howto' | 'about'

  // Public releases repo (server APK + version history).
  static const _releasesUrl =
      'https://github.com/shantoshdurai/touchplay-releases/releases/latest';
  static const _feedbackUrl =
      'https://github.com/shantoshdurai/touchplay-releases/issues/new';
  static const _communityUrl =
      'https://github.com/shantoshdurai/touchplay-releases/discussions';

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && mounted) widget.onLink('Could not open link');
  }

  Widget _step(int n, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 22, height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x226FB6FF),
          border: Border.all(color: const Color(0xFF6FB6FF)),
        ),
        child: Text('$n', style: const TextStyle(
          color: Color(0xFF6FB6FF), fontSize: 11, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(body, style: const TextStyle(
          color: Colors.white54, fontSize: 11, height: 1.35)),
      ])),
    ]),
  );

  Widget _row(IconData icon, String label, VoidCallback onTap, {Color? tint, bool last = false}) =>
    GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: last ? null : const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF1C1C28))),
        ),
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          Icon(icon, color: tint ?? Colors.white60, size: 17),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
            color: tint ?? Colors.white.withValues(alpha: 0.85), fontSize: 12.5)),
          const Spacer(),
          Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.18), size: 16),
        ]),
      ),
    );

  Widget _home() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    // Make-or-break first step: the PC server.
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x1A6FB6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x556FB6FF)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.download_rounded, color: Color(0xFF6FB6FF), size: 18),
          SizedBox(width: 8),
          Text('Get the PC server', style: TextStyle(
            color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        const Text('Have you installed the latest TouchPlay server on your PC? It’s required to connect.',
          style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.35)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => _open(_releasesUrl),
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFE9EDF4),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.15),
                    blurRadius: 12),
              ],
            ),
            child: const Text('Go to Release', style: TextStyle(
              color: Color(0xFF10141B), fontSize: 12.5, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _view = 'howto'),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 2),
            child: Text('How to install →', style: TextStyle(
              color: Color(0xFF6FB6FF), fontSize: 11)),
          ),
        ),
      ]),
    ),
    const SizedBox(height: 8),
    _row(Icons.feedback_outlined, 'Send Feedback', () => _open(_feedbackUrl)),
    _row(Icons.system_update_alt, 'Check for Update', () => _open(_releasesUrl)),
    _row(Icons.help_outline, 'How to use', () => setState(() => _view = 'howto')),
    _row(Icons.settings_outlined, 'Settings', widget.onSettings),
    _row(Icons.info_outline, 'About the App', () => setState(() => _view = 'about')),
    _row(Icons.privacy_tip_outlined, 'Privacy Policy',
        () => setState(() => _view = 'privacy')),
    _row(Icons.forum_outlined, 'Join Community', () => _open(_communityUrl),
        tint: const Color(0xFF6FB6FF), last: true),
  ]);

  Widget _privacy() => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Your data stays on your network.', style: TextStyle(
        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      SizedBox(height: 8),
      Text(
        'TouchPlay talks directly to the TouchPlay server on your own PC over '
        'local Wi-Fi or USB. Controller input, the screen stream, camera '
        'frames and transferred files travel only between your phone and '
        'your PC — nothing is sent to us or any third party. No analytics, '
        'no ads, no tracking.\n\n'
        'Settings are stored only on this device. Camera and screen-capture '
        'run only while you actively use Virtual Cam or Projector.',
        style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.5)),
    ]);

  Widget _howto() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Text('This app is your gamepad — it sends your touches to a PC running the free TouchPlay server.',
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
    Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF15151F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF222232)),
      ),
      child: const Row(children: [
        Icon(Icons.lightbulb_outline, color: Color(0xFF6FB6FF), size: 16),
        SizedBox(width: 8),
        Expanded(child: Text('No PC server = nothing to connect to. Step 1 is required.',
          style: TextStyle(color: Colors.white54, fontSize: 10.5, height: 1.3))),
      ]),
    ),
  ]);

  Widget _about() {
    final ver = WebSocketService.instance.serverVersion;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TouchPlay', style: TextStyle(
        color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      const Text('Turn your phone into a gamepad for any PC game.',
        style: TextStyle(color: Colors.white60, fontSize: 11.5, height: 1.4)),
      const SizedBox(height: 14),
      if (ver != null)
        Text('Connected PC server: v$ver',
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      const SizedBox(height: 6),
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
            child: Icon(Icons.arrow_back, color: Colors.white54, size: 18)),
        ),
      Text(switch (_view) {
        'howto' => 'How to use',
        'privacy' => 'Privacy Policy',
        'home' => 'Menu',
        _ => 'About',
      },
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      const Spacer(),
      GestureDetector(
        onTap: widget.onClose,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1A1A24)),
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
      Positioned.fill(child: GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: widget.onClose,
        child: const SizedBox.expand())),
      Positioned(
        top: top + 42, right: 10,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          builder: (_, t, child) => Opacity(
            opacity: t,
            child: Transform.translate(offset: Offset(0, (1 - t) * -8), child: child),
          ),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 230,
              constraints: BoxConstraints(maxHeight: (sz.height - top - 54).clamp(200.0, sz.height)),
              decoration: BoxDecoration(
                color: const Color(0xFF0D0D14),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF24243A)),
                boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _header(),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: switch (_view) {
                      'howto' => _howto(),
                      'privacy' => _privacy(),
                      'home' => _home(),
                      _ => _about(),
                    },
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }
}
