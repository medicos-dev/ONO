import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/room_provider.dart';
import 'providers/game_provider.dart';
import 'services/isar_service.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await IsarService.initialize();
  runApp(const AppRoot());
}

class AppRoot extends StatelessWidget {
  const AppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => RoomProvider(),
        ),
        ChangeNotifierProxyProvider<RoomProvider, GameProvider>(
          create: (_) => GameProvider(RoomProvider()),
          update: (_, roomProvider, previous) =>
              previous ?? GameProvider(roomProvider),
        ),
      ],
      child: MaterialApp(
        title: 'ONO',
        theme: AppTheme.darkTheme,
        home: const SplashScreenWrapper(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class SplashScreenWrapper extends StatelessWidget {
  const SplashScreenWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
