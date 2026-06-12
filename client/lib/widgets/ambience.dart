import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui show Gradient;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:url_launcher/url_launcher.dart';

import '../services/haptics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TouchPlay ambience — the home menu's living backdrop, shared by every screen
// so the whole app breathes the same air: near-black gradient, drifting bokeh
// dust with depth-of-field, a soft lamp above the top-right corner, vignette.
// ─────────────────────────────────────────────────────────────────────────────

/// One dust particle. 0 = far: tiny, sharp, dim. 1 = near: big, blurry.
class AmbientDust {
  final double depth;
  final double seedX; // 0..1 horizontal base position
  final double seedY; // gaussian-ish offset from the horizontal dust band
  final double startY;
  final double speed;
  final double swayAmp;
  final double swaySpeed;
  final double phase;
  final double pulseSpeed;
  final double colorMix;
  final bool inCluster;

  // Twinkle: a sharp occasional flare (the "shine" moments in the PS5 video).
  final double sparkleSpeed;
  final double sparklePhase;
  // Focus breathing: depth slowly oscillates so the particle drifts in and
  // out of focus over several seconds.
  final double focusSpeed;
  final double focusPhase;
  final double focusAmp;

  AmbientDust(Random rng, {required this.inCluster})
      : depth = rng.nextDouble() * rng.nextDouble(), // bias toward far/small
        seedX = rng.nextDouble(),
        seedY =
            (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) /
                1.5,
        startY = rng.nextDouble(),
        // Cluster dust crawls sideways along the band; ambient dust floats up.
        speed = inCluster
            ? 0.003 + rng.nextDouble() * 0.009
            : 0.008 + rng.nextDouble() * 0.022,
        swayAmp = 0.004 + rng.nextDouble() * 0.014,
        swaySpeed = 0.15 + rng.nextDouble() * 0.5,
        phase = rng.nextDouble() * 2 * pi,
        pulseSpeed = 0.2 + rng.nextDouble() * 0.7,
        colorMix = 0.05 + rng.nextDouble() * 0.5,
        sparkleSpeed = 0.10 + rng.nextDouble() * 0.45,
        sparklePhase = rng.nextDouble() * 2 * pi,
        focusSpeed = 0.06 + rng.nextDouble() * 0.18,
        focusPhase = rng.nextDouble() * 2 * pi,
        focusAmp = 0.08 + rng.nextDouble() * 0.22;
}

class AmbientPainter extends CustomPainter {
  final ValueNotifier<double> tickNotifier;
  final ValueNotifier<Color> accentNotifier;
  final List<AmbientDust> particles;

  AmbientPainter({
    required this.tickNotifier,
    required this.accentNotifier,
    required this.particles,
  }) : super(repaint: tickNotifier);

  @override
  void paint(Canvas canvas, Size size) {
    final t = tickNotifier.value;
    final accent = accentNotifier.value;

    _paintCornerGlow(canvas, size, t, accent);

    for (final p in particles) {
      double x, y;
      if (p.inCluster) {
        // Horizontal dust band across the lower half of the screen: it crawls
        // sideways slowly, gently undulating, and each particle holds a
        // gaussian offset around the band's center.
        x = (p.seedX + p.speed * t) % 1.0;
        final band = 0.62 + 0.07 * sin(t * 0.05 + x * 2.8);
        y = band +
            p.seedY * (0.16 + 0.05 * sin(t * 0.06 + p.phase)) +
            p.swayAmp * sin(t * p.swaySpeed + p.phase);
      } else {
        // Ambient dust floats slowly upward anywhere on screen.
        final yRaw = (p.startY + p.speed * t) % 1.0;
        y = 1.0 - yRaw;
        x = p.seedX + p.swayAmp * sin(t * p.swaySpeed + p.phase);
      }

      // Focus breathing: the particle's effective depth slowly oscillates, so
      // it swells/softens and shrinks/sharpens over a few seconds.
      final depth =
          (p.depth + p.focusAmp * sin(t * p.focusSpeed + p.focusPhase))
              .clamp(0.0, 1.0);

      // Twinkle: a peaky envelope (sin^8) that's ~zero most of the time and
      // briefly flares bright.
      final sRaw = sin(t * p.sparkleSpeed + p.sparklePhase);
      final sparkle = sRaw > 0 ? pow(sRaw, 8).toDouble() : 0.0;

      // Fade near screen edges so band dust never pops in/out abruptly.
      double edgeFade = 1.0;
      if (y < 0.14) edgeFade *= y / 0.14;
      if (y > 1.0 || y < 0.0) continue;
      if (x < 0.06) edgeFade *= (x / 0.06).clamp(0.0, 1.0);
      if (x > 0.94) edgeFade *= ((1.0 - x) / 0.06).clamp(0.0, 1.0);
      final pulse = 0.7 + 0.3 * sin(t * p.pulseSpeed + p.phase);
      // Near (big) particles are more transparent — out-of-focus bokeh.
      final baseAlpha = 0.10 + 0.38 * (1 - depth);
      final opacity =
          ((baseAlpha * pulse + sparkle * 0.45) * edgeFade).clamp(0.0, 1.0);
      if (opacity < 0.01) continue;

      final blended = Color.lerp(
          Color.lerp(accent, Colors.white, p.colorMix)!,
          Colors.white,
          sparkle * 0.6)!;
      final cx = x * size.width;
      final cy = y * size.height;
      final radius = (1.0 + depth * depth * 9.0) * (1.0 + sparkle * 0.3);

      if (radius < 3.0) {
        // Far dust: tiny sharp speck.
        canvas.drawCircle(Offset(cx, cy), radius,
            Paint()..color = blended.withValues(alpha: opacity));
      } else {
        // Near dust: soft out-of-focus orb — radial falloff to transparent.
        final paint = Paint()
          ..shader = ui.Gradient.radial(
            Offset(cx, cy),
            radius * 1.6,
            [
              blended.withValues(alpha: opacity),
              blended.withValues(alpha: opacity * 0.5),
              blended.withValues(alpha: 0.0),
            ],
            const [0.0, 0.45, 1.0],
          );
        canvas.drawCircle(Offset(cx, cy), radius * 1.6, paint);
      }
    }
  }

  /// The lamp: a soft light hugging the right edge with broad diffuse rays
  /// shining down-left through the dust, and a faint pool of light on the
  /// "floor" at the bottom. Everything sways very slowly.
  void _paintCornerGlow(Canvas canvas, Size size, double t, Color accent) {
    final glowTint = Color.lerp(accent, Colors.white, 0.78)!;
    final breathe = 0.84 + 0.16 * sin(t * 0.18);

    final center = Offset(
      size.width * (1.05 + 0.01 * sin(t * 0.11)),
      size.height * (0.16 + 0.05 * sin(t * 0.07 + 1.2)),
    );

    // ── Broad soft rays (3) fanning down-left ──
    final rayLen = size.width * 1.15;
    const rayBases = [2.55, 2.95, 3.35]; // down-left fan, radians
    for (var i = 0; i < rayBases.length; i++) {
      final angle = rayBases[i] + 0.06 * sin(t * (0.09 + i * 0.02) + i * 2.1);
      final bright =
          (0.45 + 0.55 * sin(t * (0.13 + i * 0.025) + i * 2.7)) * breathe;
      if (bright < 0.05) continue;

      final halfW = 0.10 + 0.035 * sin(t * 0.05 + i * 1.3); // broad wedge
      final tip = center + Offset(cos(angle), sin(angle)) * rayLen;
      final p1 =
          center + Offset(cos(angle - halfW), sin(angle - halfW)) * rayLen;
      final p2 =
          center + Offset(cos(angle + halfW), sin(angle + halfW)) * rayLen;
      final ray = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      canvas.drawPath(
        ray,
        Paint()
          ..maskFilter =
              MaskFilter.blur(BlurStyle.normal, size.shortestSide * 0.045)
          ..shader = ui.Gradient.linear(
            center,
            tip,
            [
              glowTint.withValues(alpha: 0.085 * bright),
              glowTint.withValues(alpha: 0.045 * bright),
              glowTint.withValues(alpha: 0.014 * bright),
              glowTint.withValues(alpha: 0.0),
            ],
            const [0.0, 0.35, 0.7, 1.0],
          ),
      );
    }

    // ── Halo + warm core hugging the right edge ──
    final radius = size.height * 0.55;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius,
          [
            glowTint.withValues(alpha: 0.22 * breathe),
            glowTint.withValues(alpha: 0.13 * breathe),
            glowTint.withValues(alpha: 0.065 * breathe),
            glowTint.withValues(alpha: 0.024 * breathe),
            glowTint.withValues(alpha: 0.006 * breathe),
            glowTint.withValues(alpha: 0.0),
          ],
          const [0.0, 0.25, 0.45, 0.65, 0.85, 1.0],
        ),
    );
    canvas.drawCircle(
      center,
      radius * 0.30,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          radius * 0.30,
          [
            Colors.white.withValues(alpha: 0.30 * breathe),
            Colors.white.withValues(alpha: 0.16 * breathe),
            glowTint.withValues(alpha: 0.07 * breathe),
            glowTint.withValues(alpha: 0.02 * breathe),
            glowTint.withValues(alpha: 0.0),
          ],
          const [0.0, 0.3, 0.55, 0.8, 1.0],
        ),
    );

    // ── Faint pool of light on the floor where the rays land ──
    final poolCenter = Offset(
      size.width * (0.30 + 0.03 * sin(t * 0.06)),
      size.height * 1.06,
    );
    canvas.save();
    canvas.translate(poolCenter.dx, poolCenter.dy);
    canvas.scale(1.0, 0.36);
    final poolR = size.width * 0.55;
    canvas.drawCircle(
      Offset.zero,
      poolR,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          poolR,
          [
            glowTint.withValues(alpha: 0.075 * breathe),
            glowTint.withValues(alpha: 0.045 * breathe),
            glowTint.withValues(alpha: 0.020 * breathe),
            glowTint.withValues(alpha: 0.006 * breathe),
            glowTint.withValues(alpha: 0.0),
          ],
          const [0.0, 0.3, 0.55, 0.8, 1.0],
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(AmbientPainter old) =>
      old.accentNotifier.value != accentNotifier.value;
}

/// Drop-in living backdrop for inner screens: wrap the screen body in this and
/// it sits on the same near-black, dust-lit world as the home menu. Slightly
/// dimmer than home (scrim) so foreground UI stays the hero.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({
    super.key,
    this.child,
    this.animated = true,
    this.clusterCount = 34,
    this.ambientCount = 20,
    this.scrim = 0.22,
  });

  final Widget? child;
  final bool animated;
  final int clusterCount;
  final int ambientCount;
  final double scrim;

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  final _tick = ValueNotifier<double>(0);
  final _accent = ValueNotifier<Color>(const Color(0xFF8FB6E0));
  late final List<AmbientDust> _particles;
  Ticker? _ticker;

  @override
  void initState() {
    super.initState();
    final rng = Random(42);
    _particles = [
      ...List.generate(
          widget.clusterCount, (_) => AmbientDust(rng, inCluster: true)),
      ...List.generate(
          widget.ambientCount, (_) => AmbientDust(rng, inCluster: false)),
    ];
    if (widget.animated) {
      _ticker = createTicker((elapsed) {
        _tick.value = elapsed.inMilliseconds / 1000.0;
      })
        ..start();
    } else {
      // A pleasing frozen moment for screens that must spend every frame on
      // input latency (the gamepad).
      _tick.value = 40.0;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _tick.dispose();
    _accent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(1.0, -0.5),
              radius: 1.8,
              colors: [Color(0xFF0C1118), Color(0xFF04060A)],
            ),
          ),
        ),
        RepaintBoundary(
          child: CustomPaint(
            painter: AmbientPainter(
              tickNotifier: _tick,
              accentNotifier: _accent,
              particles: _particles,
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x33000000),
                Color(0x11000000),
                Color(0x77000000),
              ],
              stops: [0.0, 0.4, 1.0],
            ),
          ),
        ),
        if (widget.scrim > 0)
          ColoredBox(color: Colors.black.withValues(alpha: widget.scrim)),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GetServerHint — a quiet pair of chips shown when a feature needs the PC
// server and we aren't connected: open the releases page, or copy the link to
// type on the PC. Deliberately small so it never shouts over the clean UI.
// ─────────────────────────────────────────────────────────────────────────────
class GetServerHint extends StatefulWidget {
  const GetServerHint({super.key});

  @override
  State<GetServerHint> createState() => _GetServerHintState();
}

class _GetServerHintState extends State<GetServerHint> {
  static const _url =
      'https://github.com/shantoshdurai/touchplay-releases/releases/latest';
  bool _copied = false;
  Timer? _revert;

  void _copy() {
    Haptics.instance.tick();
    Clipboard.setData(const ClipboardData(text: _url));
    setState(() => _copied = true);
    _revert?.cancel();
    _revert = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _open() async {
    Haptics.instance.tick();
    try {
      await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Widget _chip({required Widget child, required VoidCallback onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: child,
        ),
      );

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF6FB6FF);
    const green = Color(0xFF3DDC84);
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: [
        _chip(
          onTap: _open,
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.download_rounded, color: accent, size: 14),
            SizedBox(width: 6),
            Text('Get the PC server',
                style: TextStyle(
                    color: accent,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
        _chip(
          onTap: _copy,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_copied ? Icons.check_rounded : Icons.link_rounded,
                color: _copied ? green : Colors.white60, size: 14),
            const SizedBox(width: 6),
            Text(_copied ? 'Link copied' : 'Copy link',
                style: TextStyle(
                    color: _copied ? green : Colors.white60,
                    fontSize: 11.5)),
          ]),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PillButton — the home menu's white Launch pill as the app-wide primary
// button. `danger: true` is the stop/destructive state: quiet frosted dark
// with a red ring, matching "quiet at rest, loud on press".
// ─────────────────────────────────────────────────────────────────────────────
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.busy = false,
    this.danger = false,
    this.width,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool busy;
  final bool danger;
  final double? width;

  static const _ink = Color(0xFF10141B);
  static const _pill = Color(0xFFE9EDF4);
  static const _red = Color(0xFFFF6B6B);

  @override
  Widget build(BuildContext context) {
    final fg = danger ? _red : _ink;
    return GestureDetector(
      onTap: () {
        Haptics.instance.tick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: danger ? Colors.white.withValues(alpha: 0.06) : _pill,
          borderRadius: BorderRadius.circular(28),
          border: danger ? Border.all(color: _red.withValues(alpha: 0.8)) : null,
          boxShadow: danger
              ? null
              : [
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
        // A min-size centered Row shrink-wraps under loose constraints (the
        // FloatingActionButton slot — an aligned Container blew up to full
        // screen there) yet still centers when stretched by Expanded.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: busy
              ? [
                  SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: fg)),
                ]
              : [
                  if (icon != null) ...[
                    Icon(icon, color: fg, size: 17),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: fg,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
        ),
      ),
    );
  }
}
