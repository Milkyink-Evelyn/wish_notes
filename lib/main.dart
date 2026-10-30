import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wish_notes/app_theme.dart';
import 'logic/wish_list_model.dart';
import 'presentation/splash_page.dart';
import 'logic/auth_model.dart';
import 'repositories/wish_repository.dart';
import 'utils/sp_utils.dart';
import 'utils/db_utils.dart';

void main() async {
  // 确保在调用runApp之前初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化SharedPreferences (用于token存取)
  await SPUtils.init();
  // 初始化数据库
  await DBUtils.init();

  final auth = AuthModel()..restore();
  // 未登录时清掉上次会话残留的云端心愿, 避免被当成游客数据展示
  if (!auth.isLoggedIn) {
    await WishRepository().clearCloudWishes();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        ChangeNotifierProvider(create: (_) => WishListModel()),
      ],
      child: const MyApp(),
    )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '心愿便签',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      
      builder: (context, child) {
        return Stack(
          children: [
            // 全局背景图
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 1.3, sigmaY: 1.3),
                child: Image.asset(
                  'assets/images/LuckyMiao.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.white),
                ),
              ),
            ),
            // 页面路由
            if (child != null) child,
          ],
        );
      },
      
      home: const SplashPage(),
    );
  }
}