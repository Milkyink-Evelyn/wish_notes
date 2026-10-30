import 'package:flutter/material.dart';
import '../app_theme.dart';

/// 登录页和注册页共用的外壳
/// 统一背景、AppBar、卡片、logo 和标题, 页面里只放表单内容
class AuthScaffold extends StatelessWidget {
  final String appBarTitle;
  final String heading;
  final GlobalKey<FormState> formKey;
  final AutovalidateMode? autovalidateMode;
  final List<Widget> children;

  const AuthScaffold({
    super.key,
    required this.appBarTitle,
    required this.heading,
    required this.formKey,
    this.autovalidateMode,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.mintBackground,
      appBar: AppBar(
        title: Text(appBarTitle),
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
            key: formKey,
            autovalidateMode: autovalidateMode,
            child: Column(
              children: [
                // 两个页面共用的小图标和标题
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
                  heading,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
