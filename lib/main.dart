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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await PushNotificationService().initialize();

  final box = await Hive.openBox('dot_matrix_settings');
  final customColorValue = box.get('custom_primary_color') as int?;
  final initialSeedColor = customColorValue != null ? Color(customColorValue) : null;

  // Initialize Controllers
  Get.put(AuthController());
  Get.put(SettingsController());
  Get.put(RoomController());

  runApp(MainApp(initialSeedColor: initialSeedColor));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key, this.initialSeedColor});

  final Color? initialSeedColor;

  @override
  Widget build(BuildContext context) {
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
            (userId) => userId != null ? const HomeScreen() : const LoginScreen(),
            onLoading: const Scaffold(body: SizedBox.shrink()),
            onError: (error) => Scaffold(body: Center(child: Text('Error: $error'))),
          ),
        );
      },
    );
  }
}
