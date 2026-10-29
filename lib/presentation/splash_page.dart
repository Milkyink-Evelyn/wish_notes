import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../logic/auth_model.dart';
import '../logic/wish_list_model.dart';
import 'main_navigation_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
    );

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _ctrl.forward();

    // 首帧渲染完成后执行预加载和跳转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goToHome();
    });
  }

  Future<void> _goToHome() async {
    if (!mounted) return;

    final wishModel = context.read<WishListModel>();

    // 把旧 App 用到的图片也一并加进来预缓存
    final List<String> imagePaths = [
      'assets/images/bottom_nav_bg.png',
      'assets/images/wish.png',
      'assets/images/wish_active.png',
      'assets/images/profile.png',
      'assets/images/profile_active.png',
      'assets/images/clover.png',
      'assets/images/LuckyMiao.png',
    ];

    try {
      // 把加载数据、预缓存图片、延迟分开处理,避免并发时的异常
      // 1. 开启 1.5 秒倒计时
      final delayFuture = Future.delayed(const Duration(milliseconds: 1500));

      // 2. 预加载数据
      final currentUsername = context.read<AuthModel>().username;
      final loadDataFuture = wishModel.loadLocalData(currentUsername);

      // 3. 预缓存图片
      final preCacheFuture = Future.wait(
        imagePaths.map((path) {
          if (mounted) {
            return precacheImage(AssetImage(path), context).catchError((e) {
              debugPrint('单张图片预缓存异常 $path: $e');
            });
          }
          return Future.value();
        }),
      );

      await Future.wait([
        delayFuture,
        loadDataFuture,
        preCacheFuture,
      ]);
    } catch (e) {
      debugPrint('启动页预加载异常: $e');
    }

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: Duration.zero,
        pageBuilder: (_, __, ___) => const MainNavigationPage(playFadeIn: true),
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/LuckyMiao.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.white),
          ),

          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
              child: Container(
                color: Colors.white.withValues(alpha: 0.15),
              ),
            ),
          ),

          Center(
            child: FadeTransition(
              opacity: _fade,
              child: ScaleTransition(
                scale: _scale,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/clover.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.favorite,
                        size: 80,
                        color: Colors.pinkAccent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '顺心遂愿~',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            shadows: const [
                              Shadow(color: Colors.white, blurRadius: 8),
                            ],
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}