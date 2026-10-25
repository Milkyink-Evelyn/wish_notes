import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logic/auth_model.dart';
import 'presentation/main_navigation_page.dart';
import 'utils/sp_utils.dart';

void main() async {
  // 确保在调用runApp之前初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化SharedPreferences
  await SPUtils.init();
  runApp(
    // 使用ChangeNotifierProvider提供AuthModel实例给整个应用
    ChangeNotifierProvider(
      create: (_) => AuthModel()..restoreLoginState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: '心愿便签',
      debugShowCheckedModeBanner: false,
      home: MainNavigationPage(), // 直接展示底部导航
    );
  }
}