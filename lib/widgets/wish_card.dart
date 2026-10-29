import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../../models/wish_model.dart';
import 'custom_popup_menu.dart';

class WishCard extends StatelessWidget {
  final WishModel wish;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final bool showMenu;
  const WishCard({
    super.key,
    required this.wish,
    this.onChangeStatus,
    this.onDelete,
    this.onTap,
    this.showMenu = true,
  });

  @override
  Widget build(BuildContext context) {
    final isRealized = wish.status == 'REALIZED';
    final statusColor = isRealized ? Colors.green : Colors.orange;
    // 公开的云端心愿可能没有作者, 不能当成本地游客
    final isAnonymous = wish.ownerUsername == null &&
        wish.visibility == WishVisibility.public &&
        wish.storageMode != StorageMode.local;
    final ownerLabel = wish.ownerUsername ?? (isAnonymous ? '匿名用户' : '本地游客');

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.cardColor(context),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // 左侧分类色条
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 4,
                child: ColoredBox(
                  color: wish.category.color.withValues(alpha: 0.55),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 状态标签
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isRealized ? '已实现' : '未实现',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (showMenu)
                          CustomPopupMenu<String>(
                            items: [
                              PopupMenuItemData(
                                value: 'toggle',
                                label: isRealized ? '标记为未实现' : '标记为已实现',
                              ),
                              PopupMenuItemData(
                                value: 'delete',
                                label: '删除',
                                textColor: Colors.red, // 红色删除按钮
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'toggle') onChangeStatus?.call();
                              if (value == 'delete') onDelete?.call();
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // 心愿内容
                    Text(
                      wish.content,
                      style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.black87),
                    ),
                    const SizedBox(height: 16),

                    // 底部时间与评论
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: wish.category.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(wish.category.icon, size: 12, color: wish.category.color),
                              const SizedBox(width: 4),
                              Text(
                                wish.category.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: wish.category.color,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        // 右侧：评论数与时间
                        const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${wish.comments.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        const SizedBox(width: 12), // 间距
                        Text(ownerLabel,style: const TextStyle(fontSize: 12, color: Colors.grey),),
                        const SizedBox(width: 16),
                        Text(
                          _formatTime(wish.createdAt),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '今天 ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
