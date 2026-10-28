import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/toast_utils.dart';
import '../logic/auth_model.dart';
import 'register_page_test.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 表单校验
    if (!_formKey.currentState!.validate()) return;
    
    // 收起键盘
    FocusScope.of(context).unfocus();

    // 调用 Provider 的登录方法
    final auth = context.read<AuthModel>();
    final success = await auth.login(
      _userController.text.trim(),
      _passController.text,
    );

    if (!mounted) return;

    // 根据结果给反馈
    if (success) {
      context.showSnack('登录成功！');
    } else {
      context.showSnack(auth.errorMsg ?? '登录失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 监听 loading 状态
    final isLoading = context.watch<AuthModel>().isLoading;
    final isLoggedIn = context.watch<AuthModel>().isLoggedIn;

    return Scaffold(
      appBar: AppBar(title: const Text('测试真实登录')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoggedIn)
                const Text(
                  '🎉 当前状态：已登录\n',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, color: Colors.green),
                ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v!.trim().isEmpty ? '请输入用户名' : null,
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.length < 6) ? '密码至少 6 位' : null,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : const Text('登 录', style: TextStyle(fontSize: 16)),
                ),
              ),

              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RegisterPage()),
                  );
                },
                child: const Text('还没有账号？去注册'),
              ),
              
              if (isLoggedIn) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.read<AuthModel>().logout(),
                  child: const Text('退出登录', style: TextStyle(color: Colors.red)),
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}