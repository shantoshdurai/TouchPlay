import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'screens/controller_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/home_menu.dart';
import 'screens/projector_screen.dart';
import 'screens/virtual_cam_screen.dart';
import 'services/haptics.dart';
import 'services/websocket_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

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
          primary: Color(0xFF00D4FF),
          surface: Color(0xFF12121E),
        ),
        dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF12121E)),
      ),
      home: Builder(
        builder: (context) {
          void push(Widget screen) => Navigator.push(
              context, MaterialPageRoute(builder: (_) => screen));
          return HomeMenu(
            onGamepad: () => push(const ControllerScreen()),
            onMouse: () =>
                push(const ControllerScreen(startInMouseMode: true)),
            onMirror: () => push(const ControllerScreen()),
            onFiles: () => push(const FileTransferScreen()),
            onVirtualCam: () => push(const VirtualCamScreen()),
            onProjector: () => push(const ProjectorScreen()),
          );
        },
      ),
    );
  }
}
