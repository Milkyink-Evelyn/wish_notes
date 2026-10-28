import 'package:flutter/material.dart';
import '../../models/wish_model.dart';

class WishCard extends StatelessWidget {
  final WishModel wish;
  final VoidCallback? onChangeStatus;
  final VoidCallback? onDelete;
  const WishCard({super.key, required this.wish, this.onChangeStatus, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isRealized = wish.status == 'REALIZED';
    final statusColor = isRealized ? Colors.green : Colors.orange;

return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 状态标签
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, color: Colors.grey, size: 20),
                onSelected: (value) {
                  if (value == 'toggle') onChangeStatus?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(isRealized ? '标记为未实现' : '标记为已实现'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('删除', style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
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
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${wish.comments.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(width: 16),
              Text(
                _formatTime(wish.createdAt),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
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

