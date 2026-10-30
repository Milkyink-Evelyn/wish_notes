import 'package:flutter/material.dart';
import '../models/wish_model.dart';

/// 心愿状态标签: 已实现绿色, 未实现橙色
class WishStatusTag extends StatelessWidget {
  final String status;

  const WishStatusTag({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final isRealized = WishStatus.isRealized(status);
    final color = isRealized ? Colors.green : Colors.orange;

    return _TagBox(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      radius: 6,
      child: Text(
        isRealized ? '已实现' : '未实现',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 可见性标签: 公开蓝色, 私有紫色
class WishVisibilityTag extends StatelessWidget {
  final WishVisibility visibility;

  const WishVisibilityTag({super.key, required this.visibility});

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == WishVisibility.public;
    final color = isPublic ? Colors.blue : Colors.purple;

    return _TagBox(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      radius: 6,
      child: Text(
        isPublic ? '公开' : '私有',
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// 分类标签: 小图标 + 分类名, 颜色跟随分类
class WishCategoryTag extends StatelessWidget {
  final WishCategory category;

  const WishCategoryTag({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return _TagBox(
      color: category.color,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      radius: 4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(category.icon, size: 12, color: category.color),
          const SizedBox(width: 4),
          Text(
            category.label,
            style: TextStyle(
              fontSize: 10,
              color: category.color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// 标签底框, 统一处理淡色背景和圆角
class _TagBox extends StatelessWidget {
  final Color color;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Widget child;

  const _TagBox({
    required this.color,
    required this.padding,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
