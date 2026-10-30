import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wish_notes/logic/auth_model.dart';
import '../repositories/wish_repository.dart';
import '../utils/toast_utils.dart';
import '../logic/wish_list_model.dart';
import 'wish_form_page.dart';
import 'wishes_page.dart';
import 'profile_page.dart';

class MainNavigationPage extends StatefulWidget {
  final bool playFadeIn; 
  const MainNavigationPage({super.key, this.playFadeIn = false});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;
  late final AuthModel _auth;
  String? _lastUsername;
  bool _checkingOrphan = false;
  bool _orphanPromptDismissed = false;

  // 定义两个子页面列表
  final List<Widget> _pages = const [
    WishesPage(),
    ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _auth = context.read<AuthModel>();
    _lastUsername = _auth.username;
    _auth.addListener(_onAuthChanged);

    // 启动时检查一次本机遗留的无主心愿
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOrphanWishes());
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    final username = _auth.username;
    if (username == _lastUsername) return;

    // 登录状态切换后重新加载对应账号的数据
    // 未登录时用 null 读本地游客数据, 登录后读当前账号数据
    _lastUsername = username;
    _orphanPromptDismissed = false;
    context.read<WishListModel>().loadLocalData(username);

    if (username != null && username.isNotEmpty) {
      _checkOrphanWishes();
    }
  }

  /// 本机可能留下没有归属账号的心愿(含未登录时创建的本地私有心愿)
  /// 登录后问一下要不要归到当前账号, 否则这些心愿会被 owner 过滤掉
  Future<void> _checkOrphanWishes() async {
    if (_checkingOrphan || _orphanPromptDismissed) return;

    final username = _auth.username;
    if (username == null || username.isEmpty) return;

    _checkingOrphan = true;
    try {
      // 等登录页返回动画结束, 避免对话框被一起 pop 掉
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;

      final repo = WishRepository();
      final count = await repo.countOrphanWishes();
      if (!mounted) return;
      if (count == 0) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('发现未归属的心愿'),
          content: Text('本机有 $count 条心愿还没有归属账号(包括未登录时创建的本地私有心愿), 登录后它们不会显示在你的列表里。\n\n要把它们归到当前账号 @$username 名下吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('暂不处理'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('归到当前账号'),
            ),
          ],
        ),
      );

      if (!mounted || _auth.username != username) return;

      if (confirm != true) {
        // 本次登录不再打扰, 下次启动仍会重新检查
        _orphanPromptDismissed = true;
        return;
      }

      final claimed = await repo.claimOrphanWishes(username);
      if (!mounted) return;

      await context.read<WishListModel>().loadLocalData(username);
      if (!mounted) return;
      context.showSnack('已归属 $claimed 条心愿');
    } catch (e) {
      debugPrint('检查无主心愿失败: $e');
    } finally {
      _checkingOrphan = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. 把原来的 Scaffold 抽出来作为基础组件
    final scaffold = Scaffold(
      // 页面内容能够延伸到最底部
      extendBody: true,
      backgroundColor: Colors.transparent, // 必须透明,让底层的背景图露出来
      body: Stack(
        children: [
          // 两个页面都保留在 Stack 里, 切换时只改变透明度和点击响应, 避免丢状态
          ..._pages.asMap().entries.map((entry) {
            int idx = entry.key;
            Widget page = entry.value;
            bool isCurrent = _currentIndex == idx;

            return AnimatedOpacity(
              opacity: isCurrent ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !isCurrent, // 隐藏的页面不响应点击事件
                child: page,
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: SizedBox(
        // 导航栏总高度为 110,包含安全区域的高度
        height: 110,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none, // 允许溢出显示(小巧思Ciallo～(∠・ω< )⌒★)
          children: [
            // 背景
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Image.asset(
                'assets/images/bottom_nav_bg.png',
                fit: BoxFit.cover,
                height: 110,
                errorBuilder: (context, error, stackTrace) {
                  // 如果图片加载失败,返回一个白色的容器
                  return Container(
                    height: 110,
                    color: Colors.white,
                  );
                },
              ),
            ),
            // Tab
            Positioned(
              bottom: 15,
              left: 0,
              right: 0,
              child: Row(
               mainAxisAlignment: MainAxisAlignment.spaceAround,
               crossAxisAlignment: CrossAxisAlignment.end,
               children: [
                _buildNavItem(0, '心愿', 'wish'),
                const SizedBox(width: 80,), // 留空给加号
                _buildNavItem(1, '我的', 'profile'),
               ],
              ),
            ),
            // 加号
            Positioned(
              bottom: 25,
              child: GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (_) => const WishFormPage()),
                  );
                  debugPrint('--- 收到表单结果: $result ---');
                  if (result == true && context.mounted) {
                    context.showSnack('心愿已记录~');
                    final currentUsername = context.read<AuthModel>().username;
                    context.read<WishListModel>().loadLocalData(currentUsername); 
                  }
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Color.fromARGB(228, 248, 226, 243),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 32,),
                ),
              )
            ),
          ]
        ),
      ),
    );

    // 接收启动页传过来的 playFadeIn,执行 800ms 整体淡入
    if (widget.playFadeIn) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800), 
        curve: Curves.easeInOut,
        builder: (context, value, child) {
          return Opacity(opacity: value, child: child);
        },
        child: scaffold,
      );
    }

    // 正常状态直接返回
    return scaffold;
  }

  Widget _buildNavItem(int index, String label, String imageName) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? const Color(0xFFFFE4F1) : Colors.white;

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 80,
        height: 100,
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            Positioned(
              top: 30,
              child: Image.asset(
                isSelected
                  ? 'assets/images/${imageName}_active.png'
                  : 'assets/images/$imageName.png',
                width: 60,
                height: 60,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  imageName == 'wish' ? Icons.favorite : Icons.person,
                  size: 30,
                  color: color,
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}