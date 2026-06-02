import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../games/custom_layout.dart';
import '../widgets/custom_controls.dart';

const _accent = Color(0xFF00D4FF);
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

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _layout = widget.layout;
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

        for (final item in _layout.items) _editable(item, w, h),

        if (_layout.items.isEmpty)
          const Center(child: Text('Tap  + Add  to drop a control,\nthen drag it where you want.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 14, height: 1.5))),

        _topBar(),
        if (sel != null) _inspector(sel),
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
        onPanStart: (_) => setState(() => _selId = item.id),
        onPanUpdate: (d) => setState(() {
          item.x = (item.x + d.delta.dx / w).clamp(0.04, 0.96);
          item.y = (item.y + d.delta.dy / h).clamp(0.06, 0.94);
        }),
        child: Stack(clipBehavior: Clip.none, children: [
          // Soft cyan glow on the SELECTED control only — clean, no clutter.
          if (selected)
            Positioned(left: -7, top: -7, right: -7, bottom: -7,
              child: IgnorePointer(child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: _accent.withOpacity(0.06),
                  border: Border.all(color: _accent, width: 2),
                  boxShadow: [BoxShadow(
                    color: _accent.withOpacity(0.35), blurRadius: 18, spreadRadius: 1)],
                ),
              ))),
          // The real control, full opacity for clarity while editing.
          IgnorePointer(child: buildCustomControl(item, applyOpacity: false)),
        ]),
      ),
    );
  }

  // ── Top bar ──────────────────────────────────────────────────────────────────
  Widget _topBar() => Positioned(
    top: 0, left: 0, right: 0,
    child: Container(
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(gradient: LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.black.withOpacity(0.9), Colors.black.withOpacity(0.0)])),
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
              decoration: BoxDecoration(
                color: _accent, borderRadius: BorderRadius.circular(10)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check, color: Colors.black, size: 18),
                SizedBox(width: 4),
                Text('Save', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
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

  // ── Inspector for the selected control ───────────────────────────────────────
  Widget _inspector(ControlItem item) {
    final isButton = item.kind == ControlKind.button;
    final isSided  = item.kind == ControlKind.stick || item.kind == ControlKind.trigger;
    final isPedal  = item.kind == ControlKind.pedal;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: _panel,
          border: Border(top: BorderSide(color: _border)),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Icon(kindIcon(item.kind), color: _accent, size: 18),
            const SizedBox(width: 8),
            Text(kindName(item.kind), style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: () => _delete(item),
              child: const Row(children: [
                Icon(Icons.delete_outline, color: Color(0xFFE53935), size: 18),
                SizedBox(width: 4),
                Text('Delete', style: TextStyle(color: Color(0xFFE53935), fontSize: 13)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          if (isButton)
            Row(children: [
              const Text('Binding', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              GestureDetector(
                onTap: () => _pickBinding(item),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: const Color(0x2200D4FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _accent)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(actionLabel(item.action), style: const TextStyle(
                      color: _accent, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    const Icon(Icons.edit, color: _accent, size: 13),
                  ]),
                ),
              ),
            ]),
          if (isSided)
            Row(children: [
              const Text('Side', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              _sideToggle(item),
            ]),
          if (isPedal)
            Row(children: [
              const Text('Pedal', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const Spacer(),
              _pedalToggle(item),
            ]),
          Row(children: [
            const Text('Size', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Expanded(child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: _accent,
                inactiveTrackColor: _border,
                thumbColor: Colors.white,
                overlayColor: const Color(0x1500D4FF),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: item.size.clamp(40, 320),
                min: 40, max: 320,
                onChanged: (v) => setState(() => item.size = v),
              ),
            )),
            Text('${item.size.round()}', style: const TextStyle(color: _accent, fontSize: 12)),
          ]),
          Row(children: [
            const Text('Opacity', style: TextStyle(color: Colors.white70, fontSize: 13)),
            Expanded(child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 3,
                activeTrackColor: _accent,
                inactiveTrackColor: _border,
                thumbColor: Colors.white,
                overlayColor: const Color(0x1500D4FF),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: item.opacity.clamp(0.2, 1.0),
                min: 0.2, max: 1.0,
                onChanged: (v) => setState(() => item.opacity = v),
              ),
            )),
            Text('${(item.opacity * 100).round()}%', style: const TextStyle(color: _accent, fontSize: 12)),
          ]),
        ])),
      ),
    );
  }

  Widget _sideToggle(ControlItem item) {
    final prefix = item.kind == ControlKind.stick ? 'stick' : 'trig';
    final left = item.action == '$prefix:left';
    Widget seg(String label, bool isLeft, bool active) => GestureDetector(
      onTap: () => setState(() => item.action = '$prefix:${isLeft ? 'left' : 'right'}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0x2200D4FF) : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isLeft ? const Radius.circular(7) : Radius.zero,
            right: !isLeft ? const Radius.circular(7) : Radius.zero),
          border: Border.all(color: active ? _accent : const Color(0xFF3A3A55))),
        child: Text(label, style: TextStyle(
          color: active ? _accent : Colors.white38,
          fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      seg('LEFT', true, left), seg('RIGHT', false, !left),
    ]);
  }

  Widget _pedalToggle(ControlItem item) {
    final gas = item.action == 'pedal:gas';
    Widget seg(String label, bool isGas, bool active) => GestureDetector(
      onTap: () => setState(() => item.action = isGas ? 'pedal:gas' : 'pedal:brake'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0x2200D4FF) : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isGas ? const Radius.circular(7) : Radius.zero,
            right: !isGas ? const Radius.circular(7) : Radius.zero),
          border: Border.all(color: active ? _accent : const Color(0xFF3A3A55))),
        child: Text(label, style: TextStyle(
          color: active ? _accent : Colors.white38,
          fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      ),
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      seg('GAS', true, gas), seg('BRAKE', false, !gas),
    ]);
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
    void set(String action) { setState(() => item.action = action); Navigator.of(context).pop(); }

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
              _chip('↑', 'gp:DPAD_UP', set), _chip('↓', 'gp:DPAD_DOWN', set),
              _chip('←', 'gp:DPAD_LEFT', set), _chip('→', 'gp:DPAD_RIGHT', set),
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
    final p = Paint()..color = Colors.white.withOpacity(0.04)..strokeWidth = 1;
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
