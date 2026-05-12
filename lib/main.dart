import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'controllers/auth_controller.dart';
import 'controllers/room_controller.dart';
import 'controllers/settings_controller.dart';
import 'models/settings_state.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  
  // Initialize Controllers
  Get.put(AuthController());
  Get.put(SettingsController());
  Get.put(RoomController());
  
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SettingsController>(
      builder: (settingsController) {
        final settingsState = settingsController.state;
        final appearance = settingsState?.appearance ?? AppAppearance.light;

        return GetMaterialApp(
          title: 'Dot Matrix Messenger',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: appearance.themeMode,
          home: Get.find<AuthController>().obx(
            (userId) => userId != null ? const HomeScreen() : const LoginScreen(),
            onLoading: const Scaffold(body: Center(child: CircularProgressIndicator())),
            onError: (error) => Scaffold(body: Center(child: Text('Error: $error'))),
          ),
        );
      },
    );
  }
}
