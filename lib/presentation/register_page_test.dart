import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _userController = TextEditingController();
  final _passController = TextEditingController();
  final _nicknameController = TextEditingController();

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final auth = context.read<AuthModel>();
    final success = await auth.register(
      _userController.text.trim(),
      _passController.text,
      _nicknameController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('注册成功！已自动登录')),
      );
      Navigator.pop(context); // 注册成功，返回上一页（登录页）
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMsg ?? '注册失败'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthModel>().isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('注册新账号')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 根据接口文档：用户名 3-50 字符
              TextFormField(
                controller: _userController,
                decoration: const InputDecoration(
                  labelText: '用户名 (3-50字符)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.length < 3) return '用户名至少 3 个字符';
                  if (text.length > 50) return '用户名不能超过 50 个字符';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              // 昵称是可选的
              TextFormField(
                controller: _nicknameController,
                decoration: const InputDecoration(
                  labelText: '昵称 (可选)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              // 密码至少 6 位
              TextFormField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: '密码 (至少6位)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.length < 6) ? '密码不能少于 6 位' : null,
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : _submit,
                  child: isLoading
                      ? const CircularProgressIndicator()
                      : const Text('注 册', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}