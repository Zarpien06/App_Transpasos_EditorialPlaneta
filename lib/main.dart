import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'core/theme.dart';
import 'core/kiosk_service.dart';
import 'providers/traspaso_provider.dart';
import 'screens/login_screen.dart';
import 'widgets/kiosk_wrapper.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TraspasoProvider()),
        ChangeNotifierProvider(create: (_) => KioskService()),
      ],
      child: const MyApp(),
    ),
  );
}

final navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final kiosk = context.read<KioskService>();

      kiosk.activate();

      kiosk.onTimeout = () {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      };

      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KioskWrapper(          
      child: MaterialApp(
        title: 'Traspasos Planeta',
        theme: appTheme,
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        home: const LoginScreen(),
      ),
    );
  }
}