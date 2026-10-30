import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../../models/wish_model.dart';
import '../utils/time_utils.dart';
import 'custom_popup_menu.dart';
import 'wish_tags.dart';

/// 心愿卡片
/// 左侧色条表示分类, 顶部是状态和操作菜单, 底部放评论数、作者和时间
class WishCard extends StatelessWidget {
  final WishModel wish;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onDelete;
  final VoidCallback? onTap;
  final bool showMenu;
  final bool compact; // 广场两列布局用的紧凑样式
  const WishCard({
    super.key,
    required this.wish,
    this.onChangeStatus,
    this.onDelete,
    this.onTap,
    this.showMenu = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isRealized = WishStatus.isRealized(wish.status);
    // 公开的云端心愿可能没有作者, 不能当成本地游客
    final isAnonymous = wish.ownerUsername == null &&
        wish.visibility == WishVisibility.public &&
        wish.storageMode != StorageMode.local;
    final ownerLabel = wish.ownerUsername ?? (isAnonymous ? '匿名用户' : '本地游客');

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: compact ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
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
                padding: EdgeInsets.all(compact ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 状态标签
                        WishStatusTag(status: wish.status),

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
                    SizedBox(height: compact ? 8 : 12),

                    // 心愿内容限制最大行数, 超出部分用省略号
                    if (compact)
                      Expanded(
                        child: Text(
                          wish.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
                        ),
                      )
                    else
                      Text(
                        wish.content,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, height: 1.4, color: Colors.black87),
                      ),
                    SizedBox(height: compact ? 8 : 16),

                    // 底部时间与评论
                    if (compact)
                      _buildCompactFooter(ownerLabel)
                    else
                      _buildFooter(ownerLabel),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单列卡片的底部: 分类、评论数、作者和时间排成一行
  Widget _buildFooter(String ownerLabel) {
    return Row(
      children: [
        WishCategoryTag(category: wish.category),
        const Spacer(),
        const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text('${wish.comments.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 12), // 间距
        Text(ownerLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(width: 16),
        Text(
          formatWishTime(wish.createdAt),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  /// 两列卡片宽度有限, 分类和评论放一行, 作者和时间放下一行
  Widget _buildCompactFooter(String ownerLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            WishCategoryTag(category: wish.category),
            const Spacer(),
            const Icon(Icons.chat_bubble_outline, size: 13, color: Colors.grey),
            const SizedBox(width: 3),
            Text('${wish.comments.length}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                ownerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatWishTime(wish.createdAt),
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ],
    );
  }
}
