import 'package:flutter/material.dart';

class AppTheme {
  /// 设置页、登录页共用的背景色
  static const Color mintBackground = Color.fromARGB(255, 241, 242, 224);
  /// 设置页、登录页 AppBar 的颜色（比背景深一档）
  static const Color mintAppBar = Color.fromARGB(142, 219, 223, 178);
  
  /// 全局统一的主文字颜色（深蓝灰）
  static const Color textColor = Color(0xFF546E7A);
  /// 全局统一的辅助文字颜色（浅蓝灰）
  static const Color subTextColor = Color(0xFF90A4AE);

  static ThemeData get light => ThemeData(
        scaffoldBackgroundColor: Colors.transparent,
        
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF80CBC4),
          brightness: Brightness.light,
        ).copyWith(
          onSurface: textColor,
          primary: const Color(0xFF80CBC4), 
        ),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color.fromARGB(171, 249, 228, 244),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          toolbarHeight: 48.0,
          titleTextStyle: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            color: textColor,
          ),
          iconTheme: IconThemeData(color: textColor),
        ),

        textTheme: const TextTheme(
          displayLarge: TextStyle(color: textColor),
          displayMedium: TextStyle(color: textColor),
          displaySmall: TextStyle(color: textColor),
          headlineLarge: TextStyle(color: textColor),
          headlineMedium: TextStyle(color: textColor),
          headlineSmall: TextStyle(fontWeight: FontWeight.w800, fontSize: 24, color: textColor),
          
          titleLarge: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: textColor),
          titleMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: textColor),
          titleSmall: TextStyle(fontWeight: FontWeight.w500, fontSize: 14, color: textColor),
          
          bodyLarge: TextStyle(fontWeight: FontWeight.w500, fontSize: 16, color: textColor),
          bodyMedium: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor),
          bodySmall: TextStyle(fontWeight: FontWeight.w500, fontSize: 12, color: subTextColor),
          
          labelLarge: TextStyle(color: textColor),
          labelMedium: TextStyle(color: textColor),
          labelSmall: TextStyle(color: textColor),
        ),

        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFB2DFDB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: textColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF80CBC4), width: 2),
          ),
          labelStyle: const TextStyle(color: textColor),
          hintStyle: const TextStyle(color: Color(0xFFB0BEC5)),
        ),
        
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF4FFF4),
            foregroundColor: const Color(0xFF757575), 
            elevation: 0,
            textStyle: const TextStyle(
              inherit: true, // 防止插值崩溃
              fontWeight: FontWeight.w600, 
              fontSize: 15,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: FadePageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(), 
          },
        ),
      );
}

class FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 400ms 的平滑淡入
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    );
  }
}