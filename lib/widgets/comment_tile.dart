import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../models/wish_model.dart';
import '../utils/time_utils.dart';

/// 单条评论气泡
/// 自己的评论偏粉, 作者的评论偏蓝, 其他人用默认卡片色
class CommentTile extends StatelessWidget {
  final CommentModel comment;
  final bool isMine;
  final bool isAuthor;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  const CommentTile({
    super.key,
    required this.comment,
    required this.isMine,
    required this.isAuthor,
    required this.onReply,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = comment.nickname.isNotEmpty ? comment.nickname : comment.username;

    final Color bubbleColor;
    if (isMine) {
      bubbleColor = const Color(0xFFFFF0F6).withValues(alpha: 0.92);
    } else if (isAuthor) {
      bubbleColor = const Color(0xFFEFF7FF).withValues(alpha: 0.92);
    } else {
      bubbleColor = AppTheme.cardColor(context);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头像用昵称首字, 没昵称时用用户名
          CircleAvatar(
            radius: 16,
            backgroundColor: Colors.pinkAccent.withValues(alpha: 0.15),
            child: Text(
              nickname.isNotEmpty ? nickname.substring(0, 1) : '?',
              style: const TextStyle(fontSize: 13, color: Colors.pinkAccent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        nickname,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isMine || isAuthor) ...[
                      const SizedBox(width: 6),
                      _buildRoleTag(),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                _buildContent(),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      formatCommentTime(comment.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: onReply,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          '回复',
                          style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 只有自己的评论才有删除按钮
          if (isMine)
            GestureDetector(
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  /// 我 / 作者 小标签
  Widget _buildRoleTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: (isMine ? Colors.pinkAccent : Colors.blue).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isMine ? '我' : '作者',
        style: TextStyle(
          fontSize: 10,
          color: isMine ? Colors.pinkAccent : Colors.blue,
        ),
      ),
    );
  }

  /// 识别 "回复 @xxx :" 前缀, 用蓝色标出来
  Widget _buildContent() {
    final match = RegExp(r'^(回复\s*@[^:：\n]+?\s*[:：]\s*)').firstMatch(comment.content);
    if (match == null) {
      return Text(
        comment.content,
        style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
      );
    }

    final prefix = match.group(1)!;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: prefix,
            style: const TextStyle(color: Colors.blue),
          ),
          TextSpan(text: comment.content.substring(prefix.length)),
        ],
      ),
      style: const TextStyle(fontSize: 14, height: 1.4, color: Colors.black87),
    );
  }
}
