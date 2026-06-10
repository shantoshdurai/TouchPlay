import 'package:flutter/material.dart';

import '../services/cast_service.dart';
import '../services/haptics.dart';

const _accent = Color(0xFF00D4FF);

/// Phone camera → PC webcam. The PC feeds frames into the OBS virtual camera
/// (or shows a preview window if the driver isn't installed).
class VirtualCamScreen extends StatefulWidget {
  const VirtualCamScreen({super.key});

  @override
  State<VirtualCamScreen> createState() => _VirtualCamScreenState();
}

class _VirtualCamScreenState extends State<VirtualCamScreen> {
  bool _busy = false;
  String? _error;

  bool get _live => CastService.instance.activeMode.value == 'camera';

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
      final err = await CastService.instance.start('camera');
      if (mounted && err != null) setState(() => _error = err);
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    // Leaving the screen ends the cast — no orphaned camera in the background.
    if (_live) CastService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080810),
      body: SafeArea(
        child: Row(
          children: [
            // ── Left: live preview ──
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    color: const Color(0xFF0D0D16),
                    child: ValueListenableBuilder(
                      valueListenable: CastService.instance.preview,
                      builder: (_, img, __) => img != null
                          ? RawImage(image: img, fit: BoxFit.contain)
                          : Center(
                              child: Icon(Icons.videocam_off_outlined,
                                  color: Colors.white.withValues(alpha: 0.12),
                                  size: 56),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            // ── Right: controls ──
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
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
                        const Text('Virtual Cam',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        ValueListenableBuilder(
                          valueListenable: CastService.instance.fps,
                          builder: (_, fps, __) => _live && fps > 0
                              ? Text('$fps fps',
                                  style: const TextStyle(
                                      color: _accent, fontSize: 11))
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _live
                          ? 'LIVE — pick "OBS Virtual Camera" as the webcam in '
                            'Discord, Zoom, Meet or OBS on your PC.'
                          : 'Streams this phone\'s camera to your PC as a '
                            'webcam. If the PC has no virtual-camera driver, '
                            'a preview window opens instead (install OBS '
                            'Studio to get the driver).',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11.5, height: 1.45),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_error!,
                          style: const TextStyle(
                              color: Color(0xFFFF6B6B),
                              fontSize: 11,
                              height: 1.4)),
                    ],
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: _toggle,
                            child: Container(
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
                                      _live ? 'Stop Camera' : 'Go Live',
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
                        if (_live) ...[
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () {
                              Haptics.instance.tick();
                              CastService.instance.flipCamera();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color:
                                        Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Icon(Icons.flip_camera_android,
                                  color: Colors.white70, size: 20),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
