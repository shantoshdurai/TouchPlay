import 'package:flutter/material.dart';

import '../services/cast_service.dart';
import '../services/haptics.dart';

const _accent = Color(0xFF00D4FF);

/// Phone screen → PC window ("Projector"). Uses Android MediaProjection via a
/// foreground service, so it keeps casting while you switch apps on the phone.
class ProjectorScreen extends StatefulWidget {
  const ProjectorScreen({super.key});

  @override
  State<ProjectorScreen> createState() => _ProjectorScreenState();
}

class _ProjectorScreenState extends State<ProjectorScreen> {
  bool _busy = false;
  String? _error;

  bool get _live => CastService.instance.activeMode.value == 'projector';

  Future<void> _toggle() async {
    if (_busy) return;
    Haptics.instance.heavy();
    setState(() {
      _busy = true;
      _error = null;
    });
    if (_live) {
      await CastService.instance.stop();
    } else {
      final err = await CastService.instance.start('projector');
      if (mounted && err != null) setState(() => _error = err);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white70, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text('Projector',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  ValueListenableBuilder(
                    valueListenable: CastService.instance.fps,
                    builder: (_, fps, __) => _live && fps > 0
                        ? Text('$fps fps',
                            style:
                                const TextStyle(color: _accent, fontSize: 11))
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              const Spacer(),
              Center(
                child: ValueListenableBuilder(
                  valueListenable: CastService.instance.activeMode,
                  builder: (_, mode, __) {
                    final live = mode == 'projector';
                    return Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: live
                                ? _accent.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.04),
                            border: Border.all(
                                color: live ? _accent : Colors.white24,
                                width: 2),
                          ),
                          child: Icon(
                            live
                                ? Icons.cast_connected
                                : Icons.cast,
                            color: live ? _accent : Colors.white38,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          live
                              ? 'Casting — your phone screen is live in a '
                                'window on the PC.'
                              : 'Mirror this phone\'s screen into a window on '
                                'your PC. Great for showing photos, apps or '
                                'mobile gameplay on the big screen.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              height: 1.5),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFFF6B6B),
                                  fontSize: 11,
                                  height: 1.4)),
                        ],
                      ],
                    );
                  },
                ),
              ),
              const Spacer(),
              Center(
                child: GestureDetector(
                  onTap: _toggle,
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _live
                          ? Colors.white.withValues(alpha: 0.08)
                          : _accent,
                      borderRadius: BorderRadius.circular(12),
                      border: _live
                          ? Border.all(color: const Color(0xFFFF6B6B))
                          : null,
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(
                            _live ? 'Stop Casting' : 'Start Casting',
                            style: TextStyle(
                                color: _live
                                    ? const Color(0xFFFF6B6B)
                                    : const Color(0xFF06121A),
                                fontSize: 14,
                                fontWeight: FontWeight.w800),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
