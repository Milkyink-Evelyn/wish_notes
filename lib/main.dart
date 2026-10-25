import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'logic/auth_model.dart';
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
      home: LoginTestPage(),
    );
  }
}

// 这是一个用来测试登录的临时页面
class LoginTestPage extends StatefulWidget {
  const LoginTestPage({super.key});

  @override
  State<LoginTestPage> createState() => _LoginTestPageState();
}

class _LoginTestPageState extends State<LoginTestPage> {
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 用 Consumer 局部监听状态，避免整个页面重建
    return Scaffold(
      appBar: AppBar(title: const Text('登录测试')),
      body: Consumer<AuthModel>(
        builder: (context, auth, child) {
          if (auth.isLoggedIn) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('欢迎回来，${auth.nickname}'),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      // 点击事件用 read，不建立监听
                      context.read<AuthModel>().logout();
                    },
                    child: const Text('退出登录'),
                  )
                ],
              ),
            );
          }

          // 未登录状态
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(labelText: '用户名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                ),
                const SizedBox(height: 24),
                if (auth.errorMsg != null)
                  Text(auth.errorMsg!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: auth.isLoading
                      ? null
                      : () async {
                          // 用 read 获取模型调用方法
                          final ok = await context.read<AuthModel>().login(
                                _userController.text.trim(),
                                _passController.text,
                              );
                          if (!ok) {
                            // 登录失败逻辑已经在 UI 中显示
                          }
                        },
                  child: auth.isLoading
                      ? const CircularProgressIndicator()
                      : const Text('登录'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}