import 'package:flutter/material.dart';
import 'wishes_page.dart';
import 'profile_page.dart';
import '../widgets/background.dart'; 

class MainNavigationPage extends StatefulWidget {
  final bool playFadeIn; 
  const MainNavigationPage({super.key, this.playFadeIn = false});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  // 定义两个子页面列表
  final List<Widget> _pages = const [
    WishesPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    // 1. 把原来的 Scaffold 抽出来作为基础组件
    final scaffold = Scaffold(
      // 页面内容能够延伸到最底部
      extendBody: true,
      backgroundColor: Colors.transparent, // 必须透明，让底层的背景图露出来
      body: Stack(
        children: [
          
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
        // 导航栏总高度为 110，包含安全区域的高度
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
                  // 如果图片加载失败，返回一个白色的容器
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
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("准备发布心愿(待完成)"), duration: Duration(seconds: 1),),
                  );
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

    // 接收启动页传过来的 playFadeIn，执行 800ms 整体淡入
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
    final color = isSelected ? Colors.limeAccent : Colors.white;

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