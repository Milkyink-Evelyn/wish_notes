import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_theme.dart';
import '../utils/toast_utils.dart';
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

  // 用户名: 字母/数字/下划线; 密码: 6-20 位且不能有空格
  final _usernameReg = RegExp(r'^[a-zA-Z0-9_]{3,50}$');
  final _passwordReg = RegExp(r'^\S{6,20}$');

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
      context.showSnack('注册成功！已自动登录');
      Navigator.pop(context); // 注册成功,返回上一页(登录页)
    } else {
      context.showSnack(auth.errorMsg ?? '注册失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthModel>().isLoading;

    return Scaffold(
      backgroundColor: AppTheme.mintBackground,
      appBar: AppBar(
        title: const Text('注册新账号'),
        backgroundColor: AppTheme.mintAppBar,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(
            color: AppTheme.cardColor(context),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.textColor.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              children: [
                Image.asset(
                  'assets/images/clover.png',
                  width: 72,
                  height: 72,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.favorite,
                    size: 52,
                    color: Colors.pinkAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '创建心愿账号',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),

                // 根据接口文档：用户名 3-50 字符
                TextFormField(
                  controller: _userController,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: '用户名 (3-50位字母/数字/下划线)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (!_usernameReg.hasMatch(text)) {
                      return '用户名只能包含字母、数字、下划线, 长度 3-50';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 昵称是可选的
                TextFormField(
                  controller: _nicknameController,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: '昵称 (可选)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.length > 20) return '昵称不能超过 20 个字符';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // 密码至少 6 位
                TextFormField(
                  controller: _passController,
                  obscureText: true,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: '密码 (6-20位, 不含空格)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (!_passwordReg.hasMatch(v ?? '')) {
                      return '密码需为 6-20 位, 且不能包含空格';
                    }
                    return null;
                  },
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
      ),
    );
  }
}
