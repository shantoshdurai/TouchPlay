import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../games/custom_layout.dart';
import '../widgets/custom_controls.dart';

const _accent = Color(0xFF6FB6FF);
const _panel  = Color(0xFF0D0D14);
const _border = Color(0xFF20202C);

/// Full-screen editor. Returns the edited [CustomLayout] on Save, or null on
/// Cancel. Renders the real live controls (wrapped so they don't fire) so the
/// editor is true WYSIWYG with play mode.
class LayoutEditorScreen extends StatefulWidget {
  const LayoutEditorScreen({super.key, required this.layout});
  final CustomLayout layout;
  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  late CustomLayout _layout;
  late TextEditingController _name;
  String? _selId;
  bool _dragging = false;

  // Active snap guides while dragging (logical px; null = not snapped).
  double? _guideX, _guideY;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // Work on a copy: Cancel must leave the original untouched.
    _layout = widget.layout.copy();
    _name = TextEditingController(text: _layout.name);
  }

  @override
  void dispose() { _name.dispose(); super.dispose(); }

  ControlItem? get _sel {
    for (final i in _layout.items) { if (i.id == _selId) return i; }
    return null;
  }

  void _save() {
    _layout.name = _name.text.trim().isEmpty ? 'My Layout' : _name.text.trim();
    Navigator.of(context).pop(_layout);
  }

  void _addKind(ControlKind kind, {String action = ''}) {
    final item = newControl(kind, action: action);
    setState(() { _layout.items.add(item); _selId = item.id; });
    if (kind == ControlKind.button) _pickBinding(item);
  }

  void _delete(ControlItem item) => setState(() {
        _layout.items.removeWhere((e) => e.id == item.id);
        _selId = null;
      });

  /// Drag with alignment snapping: the item magnetises to the screen's center
  /// lines and to other controls' axes (within 7px), showing a hairline guide
  /// — makes tidy rows/columns effortless.
  void _dragItem(ControlItem item, Offset delta, double w, double h) {
    var nx = (item.x + delta.dx / w).clamp(0.04, 0.96);
    var ny = (item.y + delta.dy / h).clamp(0.06, 0.94);
    const snapPx = 7.0;
    double? gx, gy;
    final xTargets = <double>[
      0.5 * w,
      for (final o in _layout.items) if (o.id != item.id) o.x * w,
    ];
    final yTargets = <double>[
      0.5 * h,
      for (final o in _layout.items) if (o.id != item.id) o.y * h,
    ];
    for (final t in xTargets) {
      if ((nx * w - t).abs() <= snapPx) { nx = t / w; gx = t; break; }
    }
    for (final t in yTargets) {
      if ((ny * h - t).abs() <= snapPx) { ny = t / h; gy = t; break; }
    }
    setState(() {
      item.x = nx;
      item.y = ny;
      _guideX = gx;
      _guideY = gy;
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width, h = size.height;
    final sel = _sel;

    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      resizeToAvoidBottomInset: false,
      body: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _GridPaint())),
        // tap empty space to deselect
        Positioned.fill(child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selId = null))),

        // Standard "Xbox" sticks are fixed — shown as faint locked hints, never
        // as editable controls (you customize everything around them).
        if (_layout.floatingSticks) ..._fixedStickHints(w, h),

        for (final item in _layout.items) _editable(item, w, h),

        if (_layout.items.isEmpty)
          const Center(child: Text('Tap  + Add  to drop a control,\nthen drag it where you want.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 14, height: 1.5))),

        // Alignment guides while dragging
        if (_guideX != null)
          Positioned(left: _guideX! - 0.5, top: 0, bottom: 0,
            child: IgnorePointer(child: Container(
                width: 1, color: _accent.withValues(alpha: 0.55)))),
        if (_guideY != null)
          Positioned(top: _guideY! - 0.5, left: 0, right: 0,
            child: IgnorePointer(child: Container(
                height: 1, color: _accent.withValues(alpha: 0.55)))),

        _topBar(),
        // Hidden while dragging so the card never blocks the very control
        // you're placing (it used to trap controls dropped on the right side).
        if (sel != null && !_dragging) _inspector(sel),
      ]),
    );
  }

  // ── Editable item ──────────────────────────────────────────────────────────
  Widget _editable(ControlItem item, double w, double h) {
    final fp = controlFootprint(item);
    final selected = item.id == _selId;
    return Positioned(
      left: item.x * w - fp.width / 2,
      top:  item.y * h - fp.height / 2,
      width: fp.width, height: fp.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selId = item.id),
        onPanStart: (_) => setState(() {
          _selId = item.id;
          _dragging = true;
        }),
        onPanUpdate: (d) => _dragItem(item, d.delta, w, h),
        onPanEnd: (_) => setState(() {
          _guideX = null;
          _guideY = null;
          _dragging = false;
        }),
        onPanCancel: () => setState(() {
          _guideX = null;
          _guideY = null;
          _dragging = false;
        }),
        child: Stack(clipBehavior: Clip.none, children: [
          // Quiet design-tool selection: a thin outline + four corner ticks.
          // No glow, no neon — the control itself stays the focus.
          if (selected) ...[
            Positioned(left: -5, top: -5, right: -5, bottom: -5,
              child: IgnorePointer(child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85), width: 1),
                ),
              ))),
            for (final a in const [
              Alignment.topLeft, Alignment.topRight,
              Alignment.bottomLeft, Alignment.bottomRight,
            ])
              Positioned(
                left:   a.x < 0 ? -8 : null,  right:  a.x > 0 ? -8 : null,
                top:    a.y < 0 ? -8 : null,  bottom: a.y > 0 ? -8 : null,
                child: IgnorePointer(child: Container(
                  width: 7, height: 7,
                  decoration: const BoxDecoration(
                      color: _accent, shape: BoxShape.circle),
                )),
              ),
          ],
          // The real control, full opacity for clarity while editing.
          IgnorePointer(child: buildCustomControl(item, applyOpacity: false)),
        ]),
      ),
    );
  }

  // ── Fixed floating-stick hints (Standard layout) ─────────────────────────────
  // Non-interactive, faded markers on each half so the user knows the left/right
  // sticks are there and fixed — they can't be selected, moved, resized or deleted.
  List<Widget> _fixedStickHints(double w, double h) {
    Widget hint(bool left) => Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      width: w * 0.5,
      top: h * 0.46, bottom: h * 0.06,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.16,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 84, height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.lock_outline, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 6),
            Text(left ? 'LEFT STICK · FIXED' : 'RIGHT STICK · FIXED',
              style: const TextStyle(color: Colors.white, fontSize: 9,
                fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ]),
        ),
      ),
    );
    return [hint(true), hint(false)];
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────
  Widget _topBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black.withValues(alpha: 0.9), Colors.black.withValues(alpha: 0.0)])),
      child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
        child: Row(children: [
          _circleBtn(Icons.close, () => Navigator.of(context).pop()),
          const SizedBox(width: 10),
          Expanded(child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: _panel, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border)),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _name,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: const InputDecoration(
                isDense: true, border: InputBorder.none,
                hintText: 'Layout name',
                hintStyle: TextStyle(color: Colors.white24)),
            ),
          )),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showAddSheet,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.transparent, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _accent)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add, color: _accent, size: 18),
                SizedBox(width: 4),
                Text('Add', style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFE9EDF4),
                borderRadius: BorderRadius.circular(19),
                boxShadow: [
                  BoxShadow(
                      color: Colors.white.withValues(alpha: 0.18),
                      blurRadius: 12),
                ],
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check, color: Color(0xFF10141B), size: 18),
                SizedBox(width: 4),
                Text('Save',
                    style: TextStyle(
                        color: Color(0xFF10141B),
                        fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
        ]),
      ),
      ),
    ),
  );

  Widget _circleBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 38, height: 38,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: _panel),
      child: Icon(icon, color: Colors.white70, size: 18),
    ),
  );

  // ── Inspector — compact side card so it never covers the controls you're
  // placing (the old full-width bottom sheet hid everything near the bottom).
  Widget _inspector(ControlItem item) {
    final isButton = item.kind == ControlKind.button;
    final isSided  = item.kind == ControlKind.stick ||
                     item.kind == ControlKind.trigger ||
                     item.kind == ControlKind.steerPad;
    final isPedal  = item.kind == ControlKind.pedal;

    Widget sectionLabel(String t) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(t.toUpperCase(), style: const TextStyle(
        color: Colors.white30, fontSize: 9,
        fontWeight: FontWeight.w600, letterSpacing: 1.4)),
    );

    Widget slider(double value, double min, double max, String readout,
            ValueChanged<double> onChanged) =>
        Row(children: [
          Expanded(child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: Colors.white70,
              inactiveTrackColor: _border,
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          )),
          SizedBox(width: 38, child: Text(readout, textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white60, fontSize: 11))),
        ]);

    // Sit on the opposite half from the selected control so the card never
    // covers it — controls dragged to the right side stay grabbable.
    final onLeft = item.x > 0.55;
    return Positioned(
      left: onLeft ? 10 : null,
      right: onLeft ? null : 10,
      top: 58, bottom: 12, width: 232,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _panel.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(kindIcon(item.kind), color: Colors.white54, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(kindName(item.kind),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w600))),
                GestureDetector(
                  onTap: () => setState(() => _selId = null),
                  child: const Padding(
                    padding: EdgeInsets.all(2),
                    child: Icon(Icons.close, color: Colors.white38, size: 16)),
                ),
              ]),
              if (isButton) ...[
                sectionLabel('Binding'),
                GestureDetector(
                  onTap: () => _pickBinding(item),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF15151F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border)),
                    child: Row(children: [
                      Expanded(child: Text(actionLabel(item.action),
                          style: const TextStyle(color: Colors.white,
                              fontSize: 13, fontWeight: FontWeight.w600))),
                      const Icon(Icons.edit, color: Colors.white38, size: 13),
                    ]),
                  ),
                ),
              ],
              if (isSided) ...[
                sectionLabel('Side'),
                _sideToggle(item),
              ],
              if (isPedal) ...[
                sectionLabel('Pedal'),
                _pedalToggle(item),
              ],
              sectionLabel('Size · ${item.size.round()}'),
              slider(item.size.clamp(40, 320), 40, 320,
                  '${item.size.round()}',
                  (v) => setState(() => item.size = v)),
              sectionLabel('Opacity · ${(item.opacity * 100).round()}%'),
              slider(item.opacity.clamp(0.2, 1.0), 0.2, 1.0,
                  '${(item.opacity * 100).round()}%',
                  (v) => setState(() => item.opacity = v)),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: () => _delete(item),
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0x66E53935))),
                  child: const Text('Remove control', style: TextStyle(
                      color: Color(0xFFE57373), fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Two-option segment row — stretches to the inspector card's width.
  Widget _segments(String aLabel, String bLabel, bool aActive,
      void Function(bool pickedA) onPick) {
    Widget seg(String label, bool isA, bool active) => Expanded(
      child: GestureDetector(
        onTap: () => onPick(isA),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? const Color(0x1A6FB6FF) : Colors.transparent,
            borderRadius: BorderRadius.horizontal(
              left: isA ? const Radius.circular(7) : Radius.zero,
              right: !isA ? const Radius.circular(7) : Radius.zero),
            border: Border.all(color: active ? _accent : _border)),
          child: Text(label, style: TextStyle(
            color: active ? _accent : Colors.white38,
            fontSize: 11,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
        ),
      ),
    );
    return Row(children: [seg(aLabel, true, aActive), seg(bLabel, false, !aActive)]);
  }

  Widget _sideToggle(ControlItem item) {
    final prefix = item.kind == ControlKind.stick ? 'stick'
                 : item.kind == ControlKind.steerPad ? 'steerpad'
                 : 'trig';
    final left = item.action == '$prefix:left';
    return _segments('LEFT', 'RIGHT', left, (pickedLeft) =>
        setState(() => item.action = '$prefix:${pickedLeft ? 'left' : 'right'}'));
  }

  Widget _pedalToggle(ControlItem item) {
    final gas = item.action == 'pedal:gas';
    return _segments('GAS', 'BRAKE', gas, (pickedGas) =>
        setState(() => item.action = pickedGas ? 'pedal:gas' : 'pedal:brake'));
  }

  // ── Add sheet ────────────────────────────────────────────────────────────────
  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Align(alignment: Alignment.centerLeft, child: Text('Add a control',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)))),
        _addTile(Icons.radio_button_unchecked, 'Button', 'Gamepad / key / mouse',
            () => _addKind(ControlKind.button)),
        _addTile(Icons.gamepad, 'Left stick', 'Analog movement',
            () => _addKind(ControlKind.stick, action: 'stick:left')),
        _addTile(Icons.gamepad, 'Right stick', 'Analog camera',
            () => _addKind(ControlKind.stick, action: 'stick:right')),
        _addTile(Icons.expand_circle_down, 'Left trigger', 'LT',
            () => _addKind(ControlKind.trigger, action: 'trig:left')),
        _addTile(Icons.expand_circle_down, 'Right trigger', 'RT',
            () => _addKind(ControlKind.trigger, action: 'trig:right')),
        _addTile(Icons.control_camera, 'D-Pad', '4-way',
            () => _addKind(ControlKind.dpad)),
        _addTile(Icons.mouse, 'Mouse pad', 'Drag to move, tap to click',
            () => _addKind(ControlKind.mousepad)),
        _addTile(Icons.trip_origin, 'Steering wheel', 'Drag to steer (racing)',
            () => _addKind(ControlKind.wheel)),
        _addTile(Icons.tune, 'Steering slider', 'Slide a knob — hands stay put',
            () => _addKind(ControlKind.steerSlider, action: 'steer:slider')),
        _addTile(Icons.screen_rotation, 'Steering tilt', 'Tilt the phone to steer',
            () => _addKind(ControlKind.steerTilt, action: 'steer:tilt')),
        _addTile(Icons.chevron_left, 'Steer pad — left', 'Hold = full left lock',
            () => _addKind(ControlKind.steerPad, action: 'steerpad:left')),
        _addTile(Icons.chevron_right, 'Steer pad — right', 'Hold = full right lock',
            () => _addKind(ControlKind.steerPad, action: 'steerpad:right')),
        _addTile(Icons.filter_tilt_shift, 'Swing (Spider-Man)', 'Hold = swing · drag down = boost',
            () => _addKind(ControlKind.swing, action: 'swing')),
        _addTile(Icons.local_gas_station, 'Gas pedal', 'Hold = full throttle (RT)',
            () => _addKind(ControlKind.pedal, action: 'pedal:gas')),
        _addTile(Icons.front_hand, 'Brake pedal', 'Hold = full brake (LT)',
            () => _addKind(ControlKind.pedal, action: 'pedal:brake')),
        const SizedBox(height: 8),
      ]))),
    );
  }

  Widget _addTile(IconData icon, String title, String sub, VoidCallback onTap) => ListTile(
    leading: Icon(icon, color: _accent),
    title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
    subtitle: Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 11)),
    onTap: () { Navigator.of(context).pop(); onTap(); },
  );

  // ── Binding picker ───────────────────────────────────────────────────────────
  void _pickBinding(ControlItem item) {
    final keyCtrl = TextEditingController();
    // Rebinding drops the preset icon/label so the button reflects its new binding.
    void set(String action) {
      setState(() { item.action = action; item.icon = ''; item.label = ''; });
      Navigator.of(context).pop();
    }

    showDialog(context: context, builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 460,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _panel, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border)),
        child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
          children: [
            const Text('CHOOSE BINDING', style: TextStyle(
              color: _accent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 2)),
            const SizedBox(height: 14),
            _grpLabel('Gamepad'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in ['A','B','X','Y','LB','RB','LS','RS','START','BACK','GUIDE'])
                _chip(b, 'gp:$b', set),
              _chip('â†‘', 'gp:DPAD_UP', set), _chip('â†“', 'gp:DPAD_DOWN', set),
              _chip('â†', 'gp:DPAD_LEFT', set), _chip('→', 'gp:DPAD_RIGHT', set),
            ]),
            const SizedBox(height: 14),
            _grpLabel('Keyboard'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in ['W','A','S','D','SPACE','SHIFT','CTRL','ALT','E','Q','R','F',
                               'TAB','ESC','ENTER','1','2','3','4','5'])
                _chip(k, 'key:$k', set),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(
                controller: keyCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'type any key, e.g. G',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true, fillColor: const Color(0xFF15151F),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _border)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _accent)),
                ),
                onSubmitted: (v) {
                  final t = v.trim();
                  if (t.isNotEmpty) set('key:${t.length == 1 ? t.toUpperCase() : t.toUpperCase()}');
                },
              )),
            ]),
            const SizedBox(height: 14),
            _grpLabel('Mouse'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _chip('Left click', 'mouse:left', set),
              _chip('Right click', 'mouse:right', set),
            ]),
          ],
        )),
      ),
    ));
  }

  Widget _grpLabel(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t.toUpperCase(), style: const TextStyle(
      color: Colors.white38, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.6)),
  );

  Widget _chip(String label, String action, void Function(String) onPick) => GestureDetector(
    onTap: () => onPick(action),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF15151F),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border)),
      child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
    ),
  );
}

class _GridPaint extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.025)..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < s.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, s.height), p);
    }
    for (double y = 0; y < s.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}
