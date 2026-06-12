import 'dart:async';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/haptics.dart';
import '../services/player_profile.dart';
import '../widgets/ambience.dart';

// ─────────────────────────────────────────────────────────────────────────────
// First-launch introduction: black boot cover → staggered "TouchPlay."
// wordmark → "What should we call you?" name entry → "Hey, {name}." welcome,
// then the home menu fades in. Plays once — the saved name skips it forever
// after (replayable from the home menu's settings to change the name).
// ─────────────────────────────────────────────────────────────────────────────

const _accent = Color(0xFF6FB6FF);
const _ink = Color(0xFFE9EDF4);
const _riseCurve = Cubic(0.2, 0.7, 0.2, 1);

enum _Phase { boot, logo, name, welcome, server }

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});

  /// Called after the welcome beat — the root swaps in the home menu.
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  _Phase _phase = _Phase.boot;
  final _nameCtrl = TextEditingController();
  final _nameFocus = FocusNode();
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    // Replaying from settings: prefill so changing the name starts from the
    // current one instead of an empty field.
    _nameCtrl.text = PlayerProfile.instance.name.value ?? '';
    _nameCtrl.addListener(() => setState(() {}));
    _after(550, () {
      if (_phase == _Phase.boot) setState(() => _phase = _Phase.logo);
    });
  }

  void _after(int ms, VoidCallback fn) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) fn();
    }));
  }

  void _toName() {
    setState(() => _phase = _Phase.name);
    _after(500, () => _nameFocus.requestFocus());
  }

  void _finish(String raw) {
    final name = raw.trim().isEmpty ? 'Player' : raw.trim();
    PlayerProfile.instance.save(name);
    _nameFocus.unfocus();
    setState(() => _phase = _Phase.welcome);
    _after(2900, () {
      setState(() => _phase = _Phase.server);
    });
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    _nameCtrl.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const AmbientBackground(scrim: 0.0),
          _layer(
            _Phase.logo,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_phase == _Phase.logo) {
                  Haptics.instance.medium();
                  _toName();
                }
              },
              child: _logo(),
            ),
          ),
          _layer(_Phase.name, _nameEntry()),
          _layer(_Phase.welcome, _welcome()),
          _layer(_Phase.server, _serverSetup()),
          // Boot cover — pure black that lifts once the ambience is warm.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _phase == _Phase.boot ? 1 : 0,
              duration: const Duration(milliseconds: 1100),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: AnimatedOpacity(
                opacity: (_phase == _Phase.name || _phase == _Phase.server) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: (_phase != _Phase.name && _phase != _Phase.server),
                  child: GestureDetector(
                    onTap: () {
                      Haptics.instance.tick();
                      if (_phase == _Phase.name) {
                        setState(() => _phase = _Phase.logo);
                        _nameFocus.unfocus();
                      } else if (_phase == _Phase.server) {
                        setState(() => _phase = _Phase.name);
                        _after(500, () => _nameFocus.requestFocus());
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white54, size: 24),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cross-fading phase layer: the active phase sits at rest, inactive ones
  /// hold 26 px above/below so every transition is a gentle rise or settle.
  Widget _layer(_Phase p, Widget child) {
    final active = _phase == p;
    final dy = active ? 0.0 : (p.index > _phase.index ? 26.0 : -26.0);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !active,
        child: AnimatedOpacity(
          opacity: active ? 1 : 0,
          duration: const Duration(milliseconds: 750),
          curve: Curves.ease,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 750),
            curve: _riseCurve,
            transform: Matrix4.translationValues(0, dy, 0),
            child: child,
          ),
        ),
      ),
    );
  }

  // ── Phase: wordmark reveal ──────────────────────────────────────────────────
  Widget _logo() {
    // Built only once the boot cover lifts so the letter stagger starts then.
    if (_phase.index < _Phase.logo.index) return const SizedBox.expand();
    return Stack(children: [
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _Rise(
            delayMs: 250,
            child: Text('WELCOME TO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 5,
                    color: _ink.withValues(alpha: 0.42))),
          ),
          const SizedBox(height: 20),
          const _StaggerText(
            segments: [
              _Seg('Touch', FontWeight.w200, _ink),
              _Seg('Play', FontWeight.w500, _ink),
              _Seg('.', FontWeight.w500, _accent),
            ],
            fontSize: 46,
            startDelayMs: 420,
            stepMs: 75,
            letterSpacing: 2,
          ),
          const SizedBox(height: 20),
          _Rise(
            delayMs: 1600,
            durationMs: 1000,
            child: Text('Your phone. A real controller.',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.4,
                    color: _ink.withValues(alpha: 0.55))),
          ),
        ]),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 36,
        child: _Rise(
          delayMs: 2600,
          durationMs: 1200,
          rise: 0,
          child: Center(
            child: Text('TAP TO CONTINUE',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.4,
                    color: _ink.withValues(alpha: 0.28))),
          ),
        ),
      ),
    ]);
  }

  // ── Phase: name entry ───────────────────────────────────────────────────────
  Widget _nameEntry() {
    final canGo = _nameCtrl.text.trim().isNotEmpty;
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 120, 30, 60),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent,
                    boxShadow: [
                      BoxShadow(
                          color: _accent.withValues(alpha: 0.8), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('FIRST THINGS FIRST',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3.2,
                        color: _ink.withValues(alpha: 0.45))),
              ]),
              const SizedBox(height: 18),
              const Text('What should we\ncall you?',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w300,
                      height: 1.3,
                      letterSpacing: 0.2,
                      color: _ink)),
              const SizedBox(height: 30),
              TextField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                maxLength: 14,
                cursorColor: _accent,
                textInputAction: TextInputAction.done,
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _finish(v);
                },
                style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.6,
                    color: _ink),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  hintText: 'Your name',
                  hintStyle: TextStyle(
                      color: _ink.withValues(alpha: 0.25),
                      fontWeight: FontWeight.w200),
                  contentPadding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
                  enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: _ink.withValues(alpha: 0.22))),
                  focusedBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: _accent.withValues(alpha: 0.65))),
                ),
              ),
              const SizedBox(height: 14),
              Text('This is how your controller shows up on the PC.',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.2,
                      color: _ink.withValues(alpha: 0.38))),
              const SizedBox(height: 32),
              Row(children: [
                AnimatedOpacity(
                  opacity: canGo ? 1 : 0.35,
                  duration: const Duration(milliseconds: 350),
                  child: IgnorePointer(
                    ignoring: !canGo,
                    child: _continuePill(),
                  ),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () {
                    Haptics.instance.tick();
                    _finish('Player');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    child: Text('Skip',
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.3,
                            color: _ink.withValues(alpha: 0.40))),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _continuePill() => GestureDetector(
        onTap: () {
          Haptics.instance.heavy();
          _finish(_nameCtrl.text);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
          decoration: BoxDecoration(
            color: _ink,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                  color: Colors.white.withValues(alpha: 0.22),
                  blurRadius: 20,
                  spreadRadius: 1),
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: const Text('Continue',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  color: Color(0xFF10141B))),
        ),
      );

  // ── Phase: server setup check ────────────────────────────────────────────────
  Widget _serverSetup() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(30, 24, 30, 60),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _accent,
                    boxShadow: [
                      BoxShadow(
                          color: _accent.withValues(alpha: 0.8), blurRadius: 8),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text('ONE LAST THING',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 3.2,
                        color: _ink.withValues(alpha: 0.45))),
              ]),
              const SizedBox(height: 18),
              const Text('Did you setup\nthe PC server?',
                  style: TextStyle(
                      fontSize: 31,
                      fontWeight: FontWeight.w300,
                      height: 1.3,
                      letterSpacing: 0.2,
                      color: _ink)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161F).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.redAccent.withValues(alpha: 0.8), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                          "Don't worry, I got you. But keep in mind, this app has no use without the TouchPlay PC server running on your computer.",
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w300,
                              height: 1.4,
                              color: _ink.withValues(alpha: 0.8))),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Haptics.instance.tick();
                        launchUrl(Uri.parse('https://github.com/shantoshdurai/touchplay-releases/releases/latest'), mode: LaunchMode.externalApplication);
                      },
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: _ink,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.white.withValues(alpha: 0.22),
                                blurRadius: 20,
                                spreadRadius: 1),
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4)),
                          ],
                        ),
                        child: const Text('Go to Release',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF10141B))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Haptics.instance.tick();
                      Clipboard.setData(const ClipboardData(text: 'https://github.com/shantoshdurai/touchplay-releases/releases/latest'));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Link copied to clipboard', style: TextStyle(color: Colors.white)),
                        backgroundColor: Color(0xFF14161F),
                        duration: Duration(seconds: 2),
                      ));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: _ink,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.content_copy_rounded,
                          color: Color(0xFF10141B), size: 18),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: () {
                    Haptics.instance.heavy();
                    widget.onDone();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Text('Skip, I did it already',
                        style: TextStyle(
                            fontSize: 12,
                            letterSpacing: 0.3,
                            color: _ink.withValues(alpha: 0.40))),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Phase: personal welcome ─────────────────────────────────────────────────
  Widget _welcome() {
    // Built only when the phase arrives so the stagger plays on entry.
    if (_phase != _Phase.welcome) return const SizedBox.expand();
    final name = PlayerProfile.instance.name.value ?? 'Player';
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _StaggerText(
          segments: [
            const _Seg('Hey, ', FontWeight.w200, _ink),
            _Seg(name, FontWeight.w500, _ink),
            const _Seg('.', FontWeight.w500, _accent),
          ],
          fontSize: 36,
          startDelayMs: 150,
          stepMs: 55,
          letterSpacing: 1,
        ),
        const SizedBox(height: 22),
        _Rise(
          delayMs: 900,
          child: Text('Your controller is ready.',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 0.4,
                  color: _ink.withValues(alpha: 0.55))),
        ),
        const SizedBox(height: 22),
        _Rise(delayMs: 1100, durationMs: 600, rise: 0, child: _readyBar()),
      ]),
    );
  }

  /// The thin accent bar that fills while the home menu warms up behind.
  Widget _readyBar() => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 2550),
        curve: const Interval(1150 / 2550, 1, curve: Cubic(0.4, 0, 0.2, 1)),
        builder: (_, t, __) => Container(
          width: 120,
          height: 2,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: _ink.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(1),
          ),
          child: Container(
            width: 120 * t,
            height: 2,
            decoration: BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.circular(1),
              boxShadow: [
                BoxShadow(
                    color: _accent.withValues(alpha: 0.8), blurRadius: 10),
              ],
            ),
          ),
        ),
      );
}

// ── One-shot rise-in (opacity + upward settle) after a delay ─────────────────
class _Rise extends StatelessWidget {
  const _Rise({
    required this.child,
    this.delayMs = 0,
    this.durationMs = 900,
    this.rise = 16,
  });

  final Widget child;
  final int delayMs;
  final int durationMs;
  final double rise;

  @override
  Widget build(BuildContext context) {
    final total = delayMs + durationMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1.0, curve: _riseCurve),
      builder: (_, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: c),
      ),
      child: child,
    );
  }
}

// ── Per-letter staggered reveal (the wordmark / "Hey, name." treatment) ──────
class _Seg {
  final String text;
  final FontWeight weight;
  final Color color;
  const _Seg(this.text, this.weight, this.color);
}

class _StaggerText extends StatefulWidget {
  const _StaggerText({
    required this.segments,
    required this.fontSize,
    this.startDelayMs = 0,
    this.stepMs = 75,
    this.letterSpacing = 0,
  });

  final List<_Seg> segments;
  final double fontSize;
  final int startDelayMs;
  final int stepMs;
  final double letterSpacing;

  @override
  State<_StaggerText> createState() => _StaggerTextState();
}

class _StaggerTextState extends State<_StaggerText>
    with SingleTickerProviderStateMixin {
  static const _letterMs = 850;

  late final AnimationController _ctrl;
  late final List<Animation<double>> _anims;
  late final List<Text> _letters;

  @override
  void initState() {
    super.initState();
    final letters = <Text>[];
    for (final seg in widget.segments) {
      for (final ch in seg.text.split('')) {
        letters.add(Text(ch,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: seg.weight,
              color: seg.color,
              letterSpacing: widget.letterSpacing,
              height: 1.1,
            )));
      }
    }
    _letters = letters;
    final totalMs =
        widget.startDelayMs + widget.stepMs * (letters.length - 1) + _letterMs;
    _ctrl = AnimationController(
        vsync: this, duration: Duration(milliseconds: totalMs))
      ..forward();
    _anims = [
      for (var i = 0; i < letters.length; i++)
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(
            (widget.startDelayMs + i * widget.stepMs) / totalMs,
            (widget.startDelayMs + i * widget.stepMs + _letterMs) / totalMs,
            curve: _riseCurve,
          ),
        ),
    ];
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Wrap(
        alignment: WrapAlignment.center,
        children: [
          for (var i = 0; i < _letters.length; i++)
            Opacity(
              opacity: _anims[i].value,
              child: Transform.translate(
                offset: Offset(0, 18 * (1 - _anims[i].value)),
                child: _letters[i],
              ),
            ),
        ],
      ),
    );
  }
}
