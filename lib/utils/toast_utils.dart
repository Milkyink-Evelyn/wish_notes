import 'package:flutter/material.dart';

/// 自定义浮窗样式
extension SnackBarExtension on BuildContext {
  void showSnack(String text) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(
        content: Text(text, textAlign: TextAlign.center),
        duration: const Duration(milliseconds: 1333), 
        behavior: SnackBarBehavior.floating, 
        margin: const EdgeInsets.only(bottom: 10, left: 20, right: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}