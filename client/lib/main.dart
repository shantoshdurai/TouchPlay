import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/controller_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/home_menu.dart';
import 'screens/mouse_keys_screen.dart';
import 'screens/projector_screen.dart';
import 'screens/screen_mirror_screen.dart';
import 'screens/virtual_cam_screen.dart';
import 'services/haptics.dart';
import 'services/websocket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The home menu adapts to portrait and landscape; feature screens that are
  // landscape-only lock the orientation on entry (see push() below).
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  WakelockPlus.enable();

  // Probe the vibrator once up front so the first buzz isn't delayed.
  await Haptics.instance.init();

  // Start discovery + connection at boot so File Transfer / Virtual Cam /
  // Projector work straight from the menu without opening the gamepad first.
  WebSocketService.instance.init();

  runApp(const FH6ControllerApp());
}

class FH6ControllerApp extends StatelessWidget {
  const FH6ControllerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TouchPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080810),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6FB6FF),
          surface: Color(0xFF12121E),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF12121E)),
      ),
      home: Builder(
        builder: (context) {
          Future<void> push(Widget screen, {bool landscape = true}) async {
            if (landscape) {
              await SystemChrome.setPreferredOrientations([
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
            }
            if (!context.mounted) return;
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => screen));
            // Back on the home menu — portrait allowed again.
            SystemChrome.setPreferredOrientations(DeviceOrientation.values);
          }

          return HomeMenu(
            onGamepad: () => push(const ControllerScreen()),
            onMouse: () => push(const MouseKeysScreen(), landscape: false),
            onMirror: () => push(const ScreenMirrorScreen()),
            onFiles: () => push(const FileTransferScreen(), landscape: false),
            onVirtualCam: () => push(const VirtualCamScreen(), landscape: false),
            onProjector: () => push(const ProjectorScreen(), landscape: false),
          );
        },
      ),
    );
  }
}
