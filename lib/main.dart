import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'services/backend_service.dart';
import 'ui/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize media_kit native bindings (libmpv)
  MediaKit.ensureInitialized();

  // 2. Initialize window_manager for desktop window controls
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(960, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    title: 'BDSplayer - 百度网盘视频播放器',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 3. Ensure local backend microservice is running
  await BackendService.ensureStarted();

  runApp(const BDSplayerApp());
}

class BDSplayerApp extends StatefulWidget {
  const BDSplayerApp({super.key});

  @override
  State<BDSplayerApp> createState() => _BDSplayerAppState();
}

class _BDSplayerAppState extends State<BDSplayerApp> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initPreventClose();
  }

  void _initPreventClose() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    final isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      // Gracefully tell backend to exit
      await BackendService.shutdown();
      await windowManager.destroy();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BDSplayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F1218),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          surface: Color(0xFF141820),
        ),
        fontFamily: 'Segoe UI',
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
