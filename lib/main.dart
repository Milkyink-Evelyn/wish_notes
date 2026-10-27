import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wish_notes/logic/wish_list_model.dart';
import 'logic/auth_model.dart';
import 'presentation/main_navigation_page.dart';
import 'utils/sp_utils.dart';
import 'utils/db_utils.dart';

void main() async {
  // 确保在调用runApp之前初始化Flutter绑定
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化SharedPreferences (用于token存取)
  await SPUtils.init();
  // 初始化数据库
  await DBUtils.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthModel()..restore()),
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
    return const MaterialApp(
      title: '心愿便签',
      debugShowCheckedModeBanner: false,
      home: MainNavigationPage(), // 直接展示底部导航
    );
  }
}