import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'controllers/auth_controller.dart';
import 'controllers/room_controller.dart';
import 'controllers/settings_controller.dart';
import 'models/settings_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/push_notification_service.dart';
import 'theme/app_theme.dart';
import 'widgets/dot_matrix_loader.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await PushNotificationService().initialize();

  Color? initialSeedColor;
  String? startupError;
  try {
    final box = await Hive.openBox('dot_matrix_settings');
    final customColorValue = box.get('custom_primary_color') as int?;
    initialSeedColor = customColorValue != null
        ? Color(customColorValue)
        : null;
  } catch (error) {
    startupError =
        'Dot Matrix could not open local app storage. Check file permissions or reset the local app data, then try again.\n\n$error';
  }

  // Initialize Controllers
  if (startupError == null) {
    Get.put(AuthController());
    Get.put(SettingsController());
    Get.put(RoomController());
  }

  runApp(
    MainApp(initialSeedColor: initialSeedColor, startupError: startupError),
  );
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.initialSeedColor, this.startupError});

  final Color? initialSeedColor;
  final String? startupError;

  @override
  Widget build(BuildContext context) {
    if (startupError != null) {
      return GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Dot Matrix Messenger',
        theme: AppTheme.lightTheme(seedColor: initialSeedColor),
        darkTheme: AppTheme.darkTheme(seedColor: initialSeedColor),
        home: _StartupErrorScreen(error: startupError!),
      );
    }

    return GetBuilder<SettingsController>(
      builder: (settingsController) {
        final settingsState = settingsController.state;
        final appearance = settingsState?.appearance ?? AppAppearance.light;

        final seed = settingsState?.customPrimaryColor ?? initialSeedColor;

        return GetMaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Dot Matrix Messenger',
          theme: AppTheme.lightTheme(seedColor: seed),
          darkTheme: AppTheme.darkTheme(seedColor: seed),
          themeMode: appearance.themeMode,
          home: Get.find<AuthController>().obx(
            (userId) =>
                userId != null ? const HomeScreen() : const LoginScreen(),
            onLoading: const _AuthLoadingScreen(),
            onError: (error) =>
                Scaffold(body: Center(child: Text('Error: $error'))),
          ),
        );
      },
    );
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: const SafeArea(child: Center(child: DotMatrixLoader())),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 42,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Startup failed',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
